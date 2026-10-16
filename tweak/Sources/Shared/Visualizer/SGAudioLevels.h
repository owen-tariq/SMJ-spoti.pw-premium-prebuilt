// SPDX-License-Identifier: MIT
// What Spotify's output sounds like right now, for a background that moves with the music: the level,
// the peak and three bands of the last buffer bound for the speaker, read on the render thread at
// SGAudioStageVisualizer (Shared/Audio/SGAudioPipeline.h) and handed to the main thread without a lock.
// The audio passes through untouched.
//
// The analysis (SGAudioLevelsMath.h) runs only while enabled; off, the stage returns at once. Results
// are published through a seqlock: one writer, the render thread, one reader, whoever calls Read.
//
// Threading: Enabled from any thread but the render thread; Read from one thread at a time (the main
// thread); Available anywhere.
#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    float rms, peak;          // of the whole sound, 0...1
    float low, mid, high;     // under 250 Hz, between, over 4 kHz: each band's RMS, 0...1
    double sampleRate;        // the output's
    uint32_t frames;          // the buffer's length
    uint64_t sequence;        // one up per buffer; the same again means no new buffer was heard
    uint64_t hostTime;        // mach absolute time the render stamped the buffer with (0 when it did not)
} SGAudioLevels;

// Turns the analysis on or off. Off, the render callback only passes the audio through.
void SGAudioLevelsEnabled(bool on);
// The latest result; false (and `out` zeroed) when nothing has been heard since the analysis was enabled.
bool SGAudioLevelsRead(SGAudioLevels *out);
// Whether the stage is registered on a pipeline that is connected to Spotify's output.
bool SGAudioLevelsAvailable(void);
