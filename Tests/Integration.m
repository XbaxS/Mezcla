#import "../Sources/AudioBridge.h"
#import <Foundation/Foundation.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
#include <math.h>
extern char **environ;

typedef struct { double rate, frequency, phase; } Tone;
typedef struct { double rate, real[2], imaginary[2]; uint64_t frames; } Measurement;
static AudioObjectPropertyAddress prop(UInt32 selector, UInt32 scope) { return (AudioObjectPropertyAddress){selector, scope, kAudioObjectPropertyElementMain}; }
static OSStatus toneIO(AudioObjectID d, const AudioTimeStamp *n, const AudioBufferList *i, const AudioTimeStamp *it, AudioBufferList *o, const AudioTimeStamp *ot, void *ctx) {
    Tone *tone = ctx;
    UInt32 frames = o->mBuffers[0].mDataByteSize / (sizeof(float) * o->mBuffers[0].mNumberChannels);
    for (UInt32 f = 0; f < frames; f++) {
        float value = 0.03 * sin(tone->phase);
        tone->phase += 2 * M_PI * tone->frequency / tone->rate;
        if (tone->phase > 2 * M_PI) tone->phase -= 2 * M_PI;
        for (UInt32 b = 0; b < o->mNumberBuffers; b++)
            for (UInt32 c = 0; c < o->mBuffers[b].mNumberChannels; c++)
                if (o->mBuffers[b].mData) ((float *)o->mBuffers[b].mData)[f * o->mBuffers[b].mNumberChannels + c] = value;
    }
    return noErr;
}
static OSStatus measureIO(AudioObjectID d, const AudioTimeStamp *n, const AudioBufferList *i, const AudioTimeStamp *it, AudioBufferList *o, const AudioTimeStamp *ot, void *ctx) {
    Measurement *m = ctx;
    for (UInt32 b = 0; b < o->mNumberBuffers; b++) if (o->mBuffers[b].mData) memset(o->mBuffers[b].mData, 0, o->mBuffers[b].mDataByteSize);
    if (!i->mNumberBuffers || !i->mBuffers[0].mData || !i->mBuffers[0].mNumberChannels) return noErr;
    const AudioBuffer *buffer = &i->mBuffers[0];
    UInt32 frames = buffer->mDataByteSize / (sizeof(float) * buffer->mNumberChannels);
    for (UInt32 f = 0; f < frames; f++, m->frames++) {
        float value = ((const float *)buffer->mData)[f * buffer->mNumberChannels];
        for (int tone = 0; tone < 2; tone++) {
            double phase = 2 * M_PI * (tone == 0 ? 440 : 880) * m->frames / m->rate;
            m->real[tone] += value * cos(phase);
            m->imaginary[tone] += value * sin(phase);
        }
    }
    return noErr;
}
static BOOL measure(AudioObjectID device, double rate, double values[2]) {
    Measurement m = {.rate = rate}; AudioDeviceIOProcID io = NULL;
    if (AudioDeviceCreateIOProcID(device, measureIO, &m, &io) != noErr) return NO;
    OSStatus status = AudioDeviceStart(device, io);
    usleep(700000);
    AudioDeviceStop(device, io); AudioDeviceDestroyIOProcID(device, io);
    if (status != noErr || m.frames == 0) return NO;
    for (int i = 0; i < 2; i++) values[i] = 2 * hypot(m.real[i], m.imaginary[i]) / m.frames;
    return YES;
}
static AudioObjectID findBlackHole(void) {
    AudioObjectPropertyAddress p = prop(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal); UInt32 size = 0;
    AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &p, 0, NULL, &size);
    AudioObjectID *ids = calloc(1, MAX(size, 4)), result = 0;
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &p, 0, NULL, &size, ids);
    for (UInt32 i = 0; i < size / 4; i++) {
        CFStringRef name = NULL; UInt32 stringSize = sizeof(name);
        AudioObjectPropertyAddress np = prop(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal);
        if (AudioObjectGetPropertyData(ids[i], &np, 0, NULL, &stringSize, &name) == noErr && name) {
            if (CFEqual(name, CFSTR("BlackHole 2ch"))) result = ids[i];
            CFRelease(name);
        }
    }
    free(ids); return result;
}
static AudioObjectID processObject(pid_t pid) {
    AudioObjectPropertyAddress p = prop(kAudioHardwarePropertyTranslatePIDToProcessObject, kAudioObjectPropertyScopeGlobal);
    AudioObjectID result = 0; UInt32 size = sizeof(result);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &p, sizeof(pid), &pid, &size, &result);
    return result;
}
int main(int argc, char **argv) {
    @autoreleasepool {
        AudioObjectID device = findBlackHole();
        if (!device) { puts("SKIP: BlackHole 2ch is required for the isolated integration test."); return 77; }
        double rate = 0; UInt32 size = sizeof(rate); AudioObjectPropertyAddress p = prop(kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal);
        AudioObjectGetPropertyData(device, &p, 0, NULL, &size, &rate);
        if (rate <= 0) return 2;
        if (argc == 3 && strcmp(argv[1], "--tone") == 0) {
            Tone tone = {.rate = rate, .frequency = atof(argv[2])}; AudioDeviceIOProcID io = NULL;
            if (AudioDeviceCreateIOProcID(device, toneIO, &tone, &io) != noErr) return 3;
            if (AudioDeviceStart(device, io) != noErr) return 4;
            sleep(20);
            AudioDeviceStop(device, io); AudioDeviceDestroyIOProcID(device, io); return 0;
        }
        CFStringRef cfUID = NULL; size = sizeof(cfUID); p = prop(kAudioDevicePropertyDeviceUID, kAudioObjectPropertyScopeGlobal);
        AudioObjectGetPropertyData(device, &p, 0, NULL, &size, &cfUID);
        if (!cfUID) return 5;
        NSString *uid = CFBridgingRelease(cfUID);
        pid_t children[2] = {0,0}; MZRoute *routes[2] = {NULL,NULL};
        char *argsA[] = {argv[0], "--tone", "440", NULL}, *argsB[] = {argv[0], "--tone", "880", NULL};
        BOOL success = posix_spawn(&children[0], argv[0], NULL, NULL, argsA, environ) == 0 && posix_spawn(&children[1], argv[0], NULL, NULL, argsB, environ) == 0;
        usleep(700000);
        double baseline[2]={0}, adjusted[2]={0}, muted[2]={0}, restored[2]={0};
        success = success && measure(device, rate, baseline);
        for (int i = 0; success && i < 2; i++) {
            AudioObjectID process = processObject(children[i]); int32_t status = 0;
            routes[i] = MZRouteCreate(&process, 1, uid.UTF8String, i == 0 ? 0.25 : 0.5, &status);
            if (!routes[i]) { printf("Route error: %d\n", status); success = NO; }
        }
        usleep(250000);
        success = success && measure(device, rate, adjusted);
        if (routes[0]) MZRouteSetGain(routes[0], 0);
        usleep(100000);
        success = success && measure(device, rate, muted);
        for (int i = 0; i < 2; i++) MZRouteDestroy(routes[i]);
        usleep(250000);
        success = success && measure(device, rate, restored);
        for (int i = 0; i < 2; i++) if (children[i] > 0) { kill(children[i], SIGTERM); waitpid(children[i], NULL, 0); }
        if (baseline[0] < 0.005 || baseline[1] < 0.005) success = NO;
        if (success) success = fabs(adjusted[0]/baseline[0] - 0.25) < 0.06 && fabs(adjusted[1]/baseline[1] - 0.5) < 0.06 && muted[0]/baseline[0] < 0.02 && fabs(muted[1]/baseline[1] - 0.5) < 0.06 && fabs(restored[0]/baseline[0] - 1) < 0.1 && fabs(restored[1]/baseline[1] - 1) < 0.1;
        NSDictionary *report = @{ @"success": @(success), @"device": @"BlackHole 2ch", @"baseline": @[@(baseline[0]),@(baseline[1])], @"gain_25_and_50_percent": @[@(adjusted[0]),@(adjusted[1])], @"first_muted": @[@(muted[0]),@(muted[1])], @"restored": @[@(restored[0]),@(restored[1])] };
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
        return success ? 0 : 1;
    }
}
