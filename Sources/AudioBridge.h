#pragma once
#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stdint.h>
typedef struct MZRoute MZRoute;
MZRoute *MZRouteCreate(const AudioObjectID *processes, uint32_t count, const char *outputUID, float gain, int32_t *status);
void MZRouteDestroy(MZRoute *route);
void MZRouteSetGain(MZRoute *route, float gain);
float MZRoutePeak(MZRoute *route);
uint64_t MZRouteCallbacks(MZRoute *route);
uint64_t MZRouteAudibleCallbacks(MZRoute *route);
int32_t MZParentPID(int32_t pid);
// Exposed for deterministic DSP verification without changing system audio.
void MZProcessBuffers(const AudioBufferList *input, AudioBufferList *output, uint32_t inputOffset, float *currentGain, float targetGain, float *peak);
