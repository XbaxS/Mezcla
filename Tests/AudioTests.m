#import "../Sources/AudioBridge.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static AudioBufferList *Buffers(unsigned count) {
    return calloc(1, offsetof(AudioBufferList, mBuffers) + count * sizeof(AudioBuffer));
}
static void near(float actual, float expected) { assert(fabsf(actual - expected) < 0.00001f); }

int main(void) {
    float source[1024], target[1024];
    for (int i = 0; i < 512; i++) { source[2*i] = 0.8f; source[2*i+1] = -0.4f; }
    AudioBufferList *input = Buffers(1), *output = Buffers(1);
    input->mNumberBuffers = output->mNumberBuffers = 1;
    input->mBuffers[0] = (AudioBuffer){2, sizeof(source), source};
    output->mBuffers[0] = (AudioBuffer){2, sizeof(target), target};
    float gain = 0.5f, peak = 0;
    MZProcessBuffers(input, output, 0, &gain, 0.5f, &peak);
    near(target[0], 0.4f); near(target[1], -0.2f); near(peak, 0.8f);
    MZProcessBuffers(input, output, 0, &gain, 0, &peak);
    assert(target[0] > 0 && target[0] < 0.4f);
    near(target[510], 0); near(target[1023], 0); near(gain, 0);
    MZProcessBuffers(input, output, 0, &gain, 0, &peak);
    for (int i = 0; i < 1024; i++) near(target[i], 0);

    // An unrelated physical input must never leak into the output.
    float microphone[512], left[512], right[512];
    for (int i = 0; i < 512; i++) microphone[i] = 99;
    AudioBufferList *combined = Buffers(2), *planar = Buffers(2);
    combined->mNumberBuffers = planar->mNumberBuffers = 2;
    combined->mBuffers[0] = (AudioBuffer){1, sizeof(microphone), microphone};
    combined->mBuffers[1] = input->mBuffers[0];
    planar->mBuffers[0] = (AudioBuffer){1, sizeof(left), left};
    planar->mBuffers[1] = (AudioBuffer){1, sizeof(right), right};
    gain = 1;
    MZProcessBuffers(combined, planar, 1, &gain, 1, &peak);
    near(left[0], 0.8f); near(right[0], -0.4f);
    near(left[511], 0.8f); near(right[511], -0.4f);
    combined->mBuffers[0].mData = NULL;
    MZProcessBuffers(combined, planar, 1, &gain, 1, &peak);
    near(left[0], 0.8f);

    // Mono downmix, missing input, short buffers, and extra output channels.
    output->mBuffers[0] = (AudioBuffer){1, sizeof(left), left};
    MZProcessBuffers(input, output, 0, &gain, 1, &peak);
    near(left[0], 0.2f);
    input->mBuffers[0].mDataByteSize = sizeof(float) * 2;
    MZProcessBuffers(input, output, 0, &gain, 1, &peak);
    near(left[0], 0.2f); near(left[1], 0);
    float surround[8] = {99,99,99,99,99,99,99,99};
    output->mBuffers[0] = (AudioBuffer){4, sizeof(surround), surround};
    MZProcessBuffers(input, output, 0, &gain, 1, &peak);
    near(surround[0], 0.8f); near(surround[1], -0.4f); near(surround[2], 0); near(surround[3], 0);
    input->mBuffers[0].mData = NULL;
    MZProcessBuffers(input, output, 0, &gain, 1, &peak);
    for (int i = 0; i < 8; i++) near(surround[i], 0);
    free(input); free(output); free(combined); free(planar);
    puts("PASS: gain, mute ramp, stereo/mono/planar routing, microphone isolation, short/null buffers, multichannel clearing.");
}
