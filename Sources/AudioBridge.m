#import "AudioBridge.h"
#import <Foundation/Foundation.h>
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/AudioHardwareTapping.h>
#include <stdatomic.h>
#include <math.h>
#include <libproc.h>

struct MZRoute {
    AudioObjectID tap, device;
    AudioDeviceIOProcID io;
    _Atomic(float) gain, peak;
    _Atomic(uint64_t) callbacks, audibleCallbacks;
    float currentGain;
    uint32_t inputOffset;
};

int32_t MZParentPID(int32_t pid) {
    struct proc_bsdinfo info = {0};
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) == sizeof(info) ? (int32_t)info.pbi_ppid : 0;
}

static AudioObjectPropertyAddress Address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    return (AudioObjectPropertyAddress){ selector, scope, kAudioObjectPropertyElementMain };
}

// No allocation, locks, Objective-C messaging or system queries on the audio thread.
// Channels are addressed across buffers, covering interleaved and planar Float32.
static float ReadChannel(const AudioBufferList *input, uint32_t channel, uint32_t frame) {
    for (uint32_t b = 0; b < input->mNumberBuffers; b++) {
        const AudioBuffer *buffer = &input->mBuffers[b];
        if (channel < buffer->mNumberChannels) {
            uint64_t index = (uint64_t)frame * buffer->mNumberChannels + channel;
            if (!buffer->mData || index >= buffer->mDataByteSize / sizeof(float)) return 0;
            return ((const float *)buffer->mData)[index];
        }
        channel -= buffer->mNumberChannels;
    }
    return 0;
}

void MZProcessBuffers(const AudioBufferList *input, AudioBufferList *output, uint32_t inputOffset, float *currentGain, float targetGain, float *peak) {
    *peak = 0;
    uint32_t frames = 0, channels = 0;
    for (uint32_t b = 0; b < output->mNumberBuffers; b++) {
        AudioBuffer *buffer = &output->mBuffers[b];
        if (buffer->mData) memset(buffer->mData, 0, buffer->mDataByteSize);
        if (buffer->mNumberChannels && buffer->mData)
            frames = MAX(frames, buffer->mDataByteSize / (sizeof(float) * buffer->mNumberChannels));
        channels += buffer->mNumberChannels;
    }
    if (!frames) return;
    // Smooth abrupt slider/mute changes over 256 frames to avoid clicks.
    float step = (targetGain - *currentGain) / 256.0f;
    for (uint32_t frame = 0; frame < frames; frame++) {
        float gain = frame < 256 ? *currentGain + step * (frame + 1) : targetGain;
        float left = ReadChannel(input, inputOffset, frame);
        float right = ReadChannel(input, inputOffset + 1, frame);
        *peak = fmaxf(*peak, fmaxf(fabsf(left), fabsf(right)));
        uint32_t channel = 0;
        for (uint32_t b = 0; b < output->mNumberBuffers; b++) {
            AudioBuffer *buffer = &output->mBuffers[b];
            for (uint32_t c = 0; c < buffer->mNumberChannels; c++, channel++) {
                uint64_t index = (uint64_t)frame * buffer->mNumberChannels + c;
                if (!buffer->mData || index >= buffer->mDataByteSize / sizeof(float)) continue;
                float sample = channels == 1 ? (left + right) * 0.5f : channel == 0 ? left : channel == 1 ? right : 0;
                ((float *)buffer->mData)[index] = sample * gain;
            }
        }
    }
    *currentGain = frames < 256 ? *currentGain + step * frames : targetGain;
}

static OSStatus Render(AudioObjectID device, const AudioTimeStamp *now, const AudioBufferList *input, const AudioTimeStamp *inputTime, AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    MZRoute *route = context;
    float peak = 0;
    MZProcessBuffers(input, output, route->inputOffset, &route->currentGain, atomic_load_explicit(&route->gain, memory_order_relaxed), &peak);
    atomic_store_explicit(&route->peak, peak, memory_order_relaxed);
    atomic_fetch_add_explicit(&route->callbacks, 1, memory_order_relaxed);
    if (peak > 0.00001f) atomic_fetch_add_explicit(&route->audibleCallbacks, 1, memory_order_relaxed);
    return noErr;
}

static uint32_t ChannelCount(AudioObjectID device, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress address = Address(kAudioDevicePropertyStreamConfiguration, scope);
    UInt32 size = 0, channels = 0;
    if (AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &size) != noErr || !size) return 0;
    AudioBufferList *list = calloc(1, size);
    if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, list) == noErr)
        for (UInt32 i = 0; i < list->mNumberBuffers; i++) channels += list->mBuffers[i].mNumberChannels;
    free(list);
    return channels;
}

static OSStatus ValidateStreams(AudioObjectID device, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress address = Address(kAudioDevicePropertyStreams, scope);
    UInt32 size = 0;
    OSStatus result = AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &size);
    if (result != noErr) return result;
    AudioObjectID *streams = calloc(1, MAX(size, sizeof(AudioObjectID)));
    result = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, streams);
    for (UInt32 i = 0; result == noErr && i < size / sizeof(AudioObjectID); i++) {
        AudioStreamBasicDescription format = {0};
        UInt32 formatSize = sizeof(format);
        AudioObjectPropertyAddress property = Address(kAudioStreamPropertyVirtualFormat, kAudioObjectPropertyScopeGlobal);
        result = AudioObjectGetPropertyData(streams[i], &property, 0, NULL, &formatSize, &format);
        if (result == noErr && (format.mFormatID != kAudioFormatLinearPCM || format.mBitsPerChannel != 32 || !(format.mFormatFlags & kAudioFormatFlagIsFloat) || (format.mFormatFlags & kAudioFormatFlagIsBigEndian))) result = kAudioDeviceUnsupportedFormatError;
    }
    free(streams);
    return result;
}

MZRoute *MZRouteCreate(const AudioObjectID *processes, uint32_t count, const char *outputUID, float gain, int32_t *status) {
    @autoreleasepool {
        MZRoute *route = calloc(1, sizeof(MZRoute));
        atomic_init(&route->gain, gain);
        atomic_init(&route->peak, 0);
        atomic_init(&route->callbacks, 0);
        atomic_init(&route->audibleCallbacks, 0);
        route->currentGain = gain;
        NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
        for (uint32_t i = 0; i < count; i++) [ids addObject:@(processes[i])];
        CATapDescription *description = [[CATapDescription alloc] initStereoMixdownOfProcesses:ids];
        description.name = @"Mezcla · aplicación";
        description.privateTap = YES;
        description.muteBehavior = CATapMutedWhenTapped;
        *status = AudioHardwareCreateProcessTap(description, &route->tap);
        if (*status != noErr) { MZRouteDestroy(route); return NULL; }
        NSString *uid = [NSString stringWithUTF8String:outputUID];
        NSDictionary *spec = @{
            @kAudioAggregateDeviceNameKey: @"Mezcla · salida privada",
            @kAudioAggregateDeviceUIDKey: [@"cl.mezcla.route." stringByAppendingString:NSUUID.UUID.UUIDString],
            @kAudioAggregateDeviceIsPrivateKey: @YES,
            @kAudioAggregateDeviceIsStackedKey: @NO,
            @kAudioAggregateDeviceMainSubDeviceKey: uid,
            @kAudioAggregateDeviceSubDeviceListKey: @[@{@kAudioSubDeviceUIDKey: uid}],
            @kAudioAggregateDeviceTapListKey: @[@{@kAudioSubTapUIDKey: description.UUID.UUIDString, @kAudioSubTapDriftCompensationKey: @YES}],
            @kAudioAggregateDeviceTapAutoStartKey: @NO
        };
        *status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)spec, &route->device);
        if (*status != noErr) { MZRouteDestroy(route); return NULL; }
        uint32_t inputs = ChannelCount(route->device, kAudioDevicePropertyScopeInput);
        if (inputs < 2 || !ChannelCount(route->device, kAudioDevicePropertyScopeOutput)) {
            *status = kAudioDeviceUnsupportedFormatError; MZRouteDestroy(route); return NULL;
        }
        // Physical-device inputs precede the appended stereo tap. Never mix microphone samples.
        route->inputOffset = inputs - 2;
        *status = ValidateStreams(route->device, kAudioDevicePropertyScopeOutput);
        if (*status == noErr) *status = ValidateStreams(route->device, kAudioDevicePropertyScopeInput);
        if (*status != noErr) { MZRouteDestroy(route); return NULL; }
        *status = AudioDeviceCreateIOProcID(route->device, Render, route, &route->io);
        if (*status == noErr) {
            // Disable physical input streams; only the last stereo tap stream is needed.
            AudioObjectPropertyAddress address = Address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeInput);
            UInt32 size = 0;
            if (AudioObjectGetPropertyDataSize(route->device, &address, 0, NULL, &size) == noErr) {
                UInt32 n = size / sizeof(AudioObjectID);
                if (n > 1) {
                    UInt32 usageSize = (UInt32)(offsetof(AudioHardwareIOProcStreamUsage, mStreamIsOn) + n * sizeof(UInt32));
                    AudioHardwareIOProcStreamUsage *usage = calloc(1, usageSize);
                    usage->mIOProc = route->io;
                    usage->mNumberStreams = n;
                    usage->mStreamIsOn[n - 1] = 1;
                    address.mSelector = kAudioDevicePropertyIOProcStreamUsage;
                    *status = AudioObjectSetPropertyData(route->device, &address, 0, NULL, usageSize, usage);
                    free(usage);
                }
            }
        }
        if (*status == noErr) *status = AudioDeviceStart(route->device, route->io);
        if (*status != noErr) { MZRouteDestroy(route); return NULL; }
        return route;
    }
}

void MZRouteDestroy(MZRoute *route) {
    if (!route) return;
    if (route->device && route->io) {
        AudioDeviceStop(route->device, route->io);
        AudioDeviceDestroyIOProcID(route->device, route->io);
    }
    if (route->device) AudioHardwareDestroyAggregateDevice(route->device);
    if (route->tap) AudioHardwareDestroyProcessTap(route->tap);
    free(route);
}
void MZRouteSetGain(MZRoute *route, float gain) { atomic_store_explicit(&route->gain, fminf(1, fmaxf(0, gain)), memory_order_relaxed); }
float MZRoutePeak(MZRoute *route) { return atomic_load_explicit(&route->peak, memory_order_relaxed); }
uint64_t MZRouteCallbacks(MZRoute *route) { return atomic_load_explicit(&route->callbacks, memory_order_relaxed); }
uint64_t MZRouteAudibleCallbacks(MZRoute *route) { return atomic_load_explicit(&route->audibleCallbacks, memory_order_relaxed); }
