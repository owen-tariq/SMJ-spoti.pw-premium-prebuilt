// SPDX-License-Identifier: MIT
// The maths of a softened track entry, plain C11 so the render thread and harness/parity-b/transitions_test.c
// run the very same code: a gain ramp (dB-linear, -12 dB to 0) and a second-order low-pass whose cutoff glides
// (log-linear) from a start frequency up to 20 kHz over the first `lengthFrames` of a track. Nothing here
// allocates, locks or calls out; every function is bounded by its frame count.
#pragma once
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

enum { SGTransitionChannels = 2, SGTransitionBlock = 64 };

// What the main thread sets (double-buffered in Transitions.x), in the units the render thread needs.
typedef struct {
    double sampleRate;      // of the buffers rendered; 0 until the output's format is known
    uint32_t lengthFrames;  // 0 is identity: nothing is shaped
    float startCutoffHz;    // where the low-pass starts; it ends at SGTransitionEndCutoffHz (or under Nyquist)
    float startGainDb;      // where the gain starts; it ends at 0 dB
} SGTransitionParams;

typedef struct { double b0, b1, b2, a1, a2; } SGBiquadCoefficients;
typedef struct { float z1, z2; } SGBiquadState;   // transposed direct form II, one per channel

// The run of one transition on the render thread.
typedef struct {
    uint32_t position;  // frames of the current entry already shaped; >= length means idle
    uint32_t length;
    double sampleRate;
    float startCutoffHz, startGainDb;
    SGBiquadCoefficients coefficients;
    SGBiquadState state[SGTransitionChannels];
} SGTransitionRun;

#define SGTransitionEndCutoffHz 20000.0
#define SGTransitionPi 3.14159265358979323846
#define SGTransitionQ 0.70710678118654752

static inline double SGTransitionDecibelsToGain(double decibels) { return pow(10.0, decibels / 20.0); }

// RBJ low-pass; the cutoff is held under Nyquist so the filter is always stable.
static inline SGBiquadCoefficients SGBiquadLowPass(double sampleRate, double cutoffHz) {
    SGBiquadCoefficients c;
    double limit = sampleRate * 0.45;
    if (cutoffHz > limit) cutoffHz = limit;
    if (cutoffHz < 10.0) cutoffHz = 10.0;
    double w0 = 2.0 * SGTransitionPi * cutoffHz / sampleRate;
    double cw = cos(w0), sw = sin(w0), alpha = sw / (2.0 * SGTransitionQ);
    double a0 = 1.0 + alpha;
    c.b0 = ((1.0 - cw) * 0.5) / a0;
    c.b1 = (1.0 - cw) / a0;
    c.b2 = c.b0;
    c.a1 = (-2.0 * cw) / a0;
    c.a2 = (1.0 - alpha) / a0;
    return c;
}

// Where the ramp stands at `position` of `length` frames, 0...1; 1 at and past the end.
static inline double SGTransitionProgress(uint32_t position, uint32_t length) {
    if (!length || position >= length) return 1.0;
    return (double)position / (double)length;
}

// The gain at a point of the ramp: linear in dB from startGainDb to 0, so it only ever rises.
static inline float SGTransitionGainAt(double progress, float startGainDb) {
    return (float)SGTransitionDecibelsToGain((double)startGainDb * (1.0 - progress));
}

// The cutoff at a point of the ramp: log-linear from the start up to the end, so each octave takes as long.
static inline double SGTransitionCutoffAt(double progress, double startCutoffHz, double endCutoffHz) {
    if (startCutoffHz < 10.0) startCutoffHz = 10.0;
    if (endCutoffHz < startCutoffHz) endCutoffHz = startCutoffHz;
    return startCutoffHz * pow(endCutoffHz / startCutoffHz, progress);
}

static inline bool SGTransitionRunActive(const SGTransitionRun *run) {
    return run->length && run->position < run->length;
}

// Starts an entry with these parameters; a zero length or rate starts nothing (identity).
static inline void SGTransitionRunStart(SGTransitionRun *run, const SGTransitionParams *params) {
    memset(run, 0, sizeof *run);
    if (!params || params->sampleRate <= 0 || !params->lengthFrames) return;
    run->length = params->lengthFrames;
    run->sampleRate = params->sampleRate;
    run->startCutoffHz = params->startCutoffHz;
    run->startGainDb = params->startGainDb;
    run->coefficients = SGBiquadLowPass(run->sampleRate, run->startCutoffHz);
}

static inline float SGBiquadTick(const SGBiquadCoefficients *c, SGBiquadState *s, float x) {
    double y = c->b0 * x + s->z1;
    s->z1 = (float)(c->b1 * x - c->a1 * y + s->z2);
    s->z2 = (float)(c->b2 * x - c->a2 * y);
    return (float)y;
}

// Shapes `frames` of up to SGTransitionChannels planar float lanes in place (a NULL lane is skipped). The
// coefficients and the gain are recomputed every SGTransitionBlock frames from where the ramp stands, so a
// render of any size glides smoothly. Returns the frames shaped (0 once the run is idle).
static inline uint32_t SGTransitionRunProcess(SGTransitionRun *run, float *const *lanes, uint32_t channels, uint32_t frames) {
    if (!SGTransitionRunActive(run) || !lanes || !frames) return 0;
    if (channels > SGTransitionChannels) channels = SGTransitionChannels;
    uint32_t done = 0;
    while (done < frames && run->position < run->length) {
        // Blocks are aligned to the run, not the render, so renders of any size shape the same frames alike.
        uint32_t count = frames - done, toBoundary = SGTransitionBlock - run->position % SGTransitionBlock;
        if (count > toBoundary) count = toBoundary;
        if (count > run->length - run->position) count = run->length - run->position;
        // The block is shaped with the values at its middle, so the start and the end are met on average.
        uint32_t middle = run->position - run->position % SGTransitionBlock + SGTransitionBlock / 2;
        double progress = SGTransitionProgress(middle < run->length ? middle : run->length, run->length);
        float gain = SGTransitionGainAt(progress, run->startGainDb);
        run->coefficients = SGBiquadLowPass(run->sampleRate, SGTransitionCutoffAt(progress, run->startCutoffHz, SGTransitionEndCutoffHz));
        for (uint32_t ch = 0; ch < channels; ch++) {
            float *lane = lanes[ch];
            if (!lane) continue;
            SGBiquadState *state = &run->state[ch];
            for (uint32_t i = 0; i < count; i++) lane[done + i] = gain * SGBiquadTick(&run->coefficients, state, lane[done + i]);
        }
        run->position += count;
        done += count;
    }
    return done;
}
