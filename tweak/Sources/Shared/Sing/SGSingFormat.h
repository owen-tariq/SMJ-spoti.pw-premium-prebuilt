// The shapes of audio Sing works in. The model has one: 44.1 kHz stereo, two seconds a window (the Swift
// worker's SGStemShape in SGStemSeparator.swift names the same numbers and checks the model it loads
// against them). The render side has the source's: Spotify decodes at 44.1 kHz, or at 48, 88.2 or 96 kHz
// for lossless tracks and some output routes, and the stream, timeline and mix keep that rate as it is,
// sized at runtime by SGSingGeometryAt. Only the off-render worker resamples, each window on its own,
// between the source's rate and the model's.
#pragma once
#include <stdbool.h>
#include <stdint.h>

enum {
    SGSingSampleRate = 44100,                          // the model's rate, stereo float
    SGSingWindowFrames = 88200,                        // two seconds at the model's rate, one run of the model
    SGSingHopFrames = SGSingWindowFrames * 3 / 4,      // 66150: a window every 1.5 s, half a second overlapping
    SGSingMaxSampleRate = 96000,                       // the largest rate the render side is sized for
    SGSingMaxWindowFrames = SGSingMaxSampleRate * 2,
    SGSingMaxTimelineFrames = SGSingMaxSampleRate * 8,
    SGSingRecoverySeconds = 8,                         // a late worker's budget before the mix drains to the original
};

// The rates the render side takes: the model's, and the ones Sing resamples from exactly (160/147, 2 and
// 320/147 against the model's). Anything else keeps Spotify's own audio and says so.
static inline bool SGSingSupportedRate(double rate) {
    return rate == 44100 || rate == 48000 || rate == 88200 || rate == 96000;
}

// The render side's sizes at one source rate, all in source frames: two seconds a window, a hop every
// 1.5 s, 120 ms of reserve (what is left in Spotify's own queue when reading ahead, and the ready vocals
// the mix keeps so that its ramp back to the original, SGSingMixerBypass, always has vocals to ramp over),
// and eight seconds of original kept for the worker.
typedef struct {
    uint32_t sampleRate, windowFrames, hopFrames, reserveFrames, timelineFrames;
} SGSingGeometry;
static inline bool SGSingGeometryAt(double rate, SGSingGeometry *geometry) {
    if (!geometry || !SGSingSupportedRate(rate)) return false;
    uint32_t hz = (uint32_t)rate;
    geometry->sampleRate = hz;
    geometry->windowFrames = hz * 2;
    geometry->hopFrames = hz * 2 * 3 / 4;
    geometry->reserveFrames = hz * 120 / 1000;
    geometry->timelineFrames = hz * 8;
    return true;
}
