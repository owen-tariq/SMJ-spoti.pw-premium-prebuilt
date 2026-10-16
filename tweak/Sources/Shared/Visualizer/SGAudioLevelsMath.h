// SPDX-License-Identifier: MIT
// The visualizer's ear, as plain C: one buffer of mono samples in, its RMS, its peak and the RMS of three
// bands out -- the low end under 250 Hz, the top over 4 kHz, and the middle between them. Each band is a
// pair of RBJ biquads (24 dB an octave), so a buffer costs eight multiply-adds a sample and nothing is
// allocated, looked up or transformed. Runs on Core Audio's render thread, so nothing here allocates,
// locks, logs or sends a message; compiles with any C11 compiler for harness/parity-b/levels_test.c.
//
// Usage: Reset once with the sample rate (off the render thread), then per buffer Begin, Feed one or more
// chunks, End. A sample that is not a finite number counts as silence, and a result that is not finite
// comes out as silence and clears the filters, so one bad buffer cannot poison the next.
#pragma once
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

enum { SGAudioLevelsBiquadsPerBand = 2 };

static const double SGAudioLevelsLowCutoff = 250, SGAudioLevelsHighCutoff = 4000;
// Spelled out: strict C11 (the harness) has no M_PI.
static const double SGAudioLevelsPi = 3.14159265358979323846, SGAudioLevelsSqrtHalf = 0.70710678118654752440;

typedef struct {
    double b0, b1, b2, a1, a2;
    double z1, z2;
} SGAudioLevelsBiquad;

typedef struct {
    double sampleRate;
    SGAudioLevelsBiquad low[SGAudioLevelsBiquadsPerBand];      // low-pass at 250 Hz
    SGAudioLevelsBiquad high[SGAudioLevelsBiquadsPerBand];     // high-pass at 4 kHz
    SGAudioLevelsBiquad midHigh[SGAudioLevelsBiquadsPerBand];  // high-pass at 250 Hz, then
    SGAudioLevelsBiquad midLow[SGAudioLevelsBiquadsPerBand];   // low-pass at 4 kHz
    // The buffer under way, since Begin.
    double fullSum, lowSum, midSum, highSum;
    float peak;
    uint32_t frames;
} SGAudioLevelsAnalyzer;

typedef struct {
    float rms, peak;          // of the whole sound, 0...1
    float low, mid, high;     // each band's RMS, 0...1
    uint32_t frames;          // samples the result was read from; 0 is no result
} SGAudioLevelsResult;

// RBJ's cookbook, Q 1/sqrt(2): a Butterworth section; two in a row make 24 dB an octave.
static inline void SGAudioLevelsSetBiquad(SGAudioLevelsBiquad *filter, double sampleRate, double cutoff, bool highPass) {
    double w = 2 * SGAudioLevelsPi * cutoff / sampleRate;
    double cosw = cos(w), alpha = sin(w) / (2 * SGAudioLevelsSqrtHalf);
    double a0 = 1 + alpha;
    double b1 = highPass ? -(1 + cosw) : 1 - cosw;
    double b0 = highPass ? (1 + cosw) / 2 : (1 - cosw) / 2;
    filter->b0 = b0 / a0;
    filter->b1 = b1 / a0;
    filter->b2 = b0 / a0;
    filter->a1 = -2 * cosw / a0;
    filter->a2 = (1 - alpha) / a0;
    filter->z1 = filter->z2 = 0;
}

// Transposed direct form II.
static inline double SGAudioLevelsRunBiquad(SGAudioLevelsBiquad *filter, double x) {
    double y = filter->b0 * x + filter->z1;
    filter->z1 = filter->b1 * x - filter->a1 * y + filter->z2;
    filter->z2 = filter->b2 * x - filter->a2 * y;
    return y;
}

static inline void SGAudioLevelsClearState(SGAudioLevelsAnalyzer *analyzer) {
    for (int i = 0; i < SGAudioLevelsBiquadsPerBand; i++) {
        analyzer->low[i].z1 = analyzer->low[i].z2 = 0;
        analyzer->high[i].z1 = analyzer->high[i].z2 = 0;
        analyzer->midHigh[i].z1 = analyzer->midHigh[i].z2 = 0;
        analyzer->midLow[i].z1 = analyzer->midLow[i].z2 = 0;
    }
}

// Before the first buffer and whenever the sample rate changes. A rate that makes no sense (under twice
// the high cutoff) is taken as 44.1 kHz rather than left to make unstable filters.
static inline void SGAudioLevelsAnalyzerReset(SGAudioLevelsAnalyzer *analyzer, double sampleRate) {
    memset(analyzer, 0, sizeof *analyzer);
    if (!(sampleRate > 2 * SGAudioLevelsHighCutoff) || !isfinite(sampleRate)) sampleRate = 44100;
    analyzer->sampleRate = sampleRate;
    for (int i = 0; i < SGAudioLevelsBiquadsPerBand; i++) {
        SGAudioLevelsSetBiquad(&analyzer->low[i], sampleRate, SGAudioLevelsLowCutoff, false);
        SGAudioLevelsSetBiquad(&analyzer->high[i], sampleRate, SGAudioLevelsHighCutoff, true);
        SGAudioLevelsSetBiquad(&analyzer->midHigh[i], sampleRate, SGAudioLevelsLowCutoff, true);
        SGAudioLevelsSetBiquad(&analyzer->midLow[i], sampleRate, SGAudioLevelsHighCutoff, false);
    }
}

static inline void SGAudioLevelsAnalyzerBegin(SGAudioLevelsAnalyzer *analyzer) {
    analyzer->fullSum = analyzer->lowSum = analyzer->midSum = analyzer->highSum = 0;
    analyzer->peak = 0;
    analyzer->frames = 0;
}

// `mono` holds `count` samples in about -1...1. May be called more than once between Begin and End.
static inline void SGAudioLevelsAnalyzerFeed(SGAudioLevelsAnalyzer *analyzer, const float *mono, uint32_t count) {
    double fullSum = 0, lowSum = 0, midSum = 0, highSum = 0;
    float peak = analyzer->peak;
    for (uint32_t i = 0; i < count; i++) {
        float sample = mono[i];
        if (!isfinite(sample)) sample = 0;
        double x = sample;
        double low = x, high = x, mid = x;
        for (int k = 0; k < SGAudioLevelsBiquadsPerBand; k++) {
            low = SGAudioLevelsRunBiquad(&analyzer->low[k], low);
            high = SGAudioLevelsRunBiquad(&analyzer->high[k], high);
            mid = SGAudioLevelsRunBiquad(&analyzer->midHigh[k], mid);
        }
        for (int k = 0; k < SGAudioLevelsBiquadsPerBand; k++) mid = SGAudioLevelsRunBiquad(&analyzer->midLow[k], mid);
        fullSum += x * x;
        lowSum += low * low;
        midSum += mid * mid;
        highSum += high * high;
        float magnitude = fabsf(sample);
        if (magnitude > peak) peak = magnitude;
    }
    analyzer->fullSum += fullSum;
    analyzer->lowSum += lowSum;
    analyzer->midSum += midSum;
    analyzer->highSum += highSum;
    analyzer->peak = peak;
    analyzer->frames += count;
}

static inline float SGAudioLevelsClamp01(double value) {
    if (!(value > 0)) return 0;   // NaN too
    return value > 1 ? 1 : (float)value;
}

// The buffer's result. Nothing fed since Begin gives silence; a result that is not finite gives silence
// and clears the filters.
static inline void SGAudioLevelsAnalyzerEnd(SGAudioLevelsAnalyzer *analyzer, SGAudioLevelsResult *out) {
    memset(out, 0, sizeof *out);
    uint32_t frames = analyzer->frames;
    if (!frames) return;
    double n = frames;
    double rms = sqrt(analyzer->fullSum / n), low = sqrt(analyzer->lowSum / n);
    double mid = sqrt(analyzer->midSum / n), high = sqrt(analyzer->highSum / n);
    if (!isfinite(rms) || !isfinite(low) || !isfinite(mid) || !isfinite(high) || !isfinite(analyzer->peak)) {
        SGAudioLevelsClearState(analyzer);
        out->frames = frames;
        return;
    }
    out->rms = SGAudioLevelsClamp01(rms);
    out->peak = SGAudioLevelsClamp01(analyzer->peak);
    out->low = SGAudioLevelsClamp01(low);
    out->mid = SGAudioLevelsClamp01(mid);
    out->high = SGAudioLevelsClamp01(high);
    out->frames = frames;
}
