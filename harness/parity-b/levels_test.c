// SPDX-License-Identifier: MIT
// The visualizer's analyser (tweak/Sources/Shared/Visualizer/SGAudioLevelsMath.h) checked on the Mac or
// Linux: a 100 Hz sine lands in the low band, an 8 kHz one in the high band, a 1 kHz one in the middle,
// silence reads as zero, and a buffer full of NaN and infinities reads as silence and leaves the filters
// fit for the next buffer.
//   cc -std=c11 -Wall -Wextra -Werror harness/parity-b/levels_test.c -lm && ./a.out
#include <stdio.h>
#include <stdlib.h>
#include "../../tweak/Sources/Shared/Visualizer/SGAudioLevelsMath.h"

enum { kRate = 48000, kFrames = 1024, kWarmupBuffers = 8 };

static int failures;

#define CHECK(condition, ...) do { \
    if (!(condition)) { \
        failures++; \
        printf("FAIL %s:%d: ", __FILE__, __LINE__); \
        printf(__VA_ARGS__); \
        printf("\n"); \
    } \
} while (0)

// Feeds `buffers` of the tone and returns the last buffer's result, so the filters have settled.
static SGAudioLevelsResult tone(SGAudioLevelsAnalyzer *analyzer, double frequency, float amplitude, int buffers) {
    static float mono[kFrames];
    SGAudioLevelsResult result = {0};
    double phase = 0, step = 2 * SGAudioLevelsPi * frequency / kRate;
    for (int b = 0; b < buffers; b++) {
        for (int i = 0; i < kFrames; i++) {
            mono[i] = amplitude * (float)sin(phase);
            phase += step;
        }
        SGAudioLevelsAnalyzerBegin(analyzer);
        // Two chunks, the way the render callback feeds a long buffer.
        SGAudioLevelsAnalyzerFeed(analyzer, mono, kFrames / 2);
        SGAudioLevelsAnalyzerFeed(analyzer, mono + kFrames / 2, kFrames - kFrames / 2);
        SGAudioLevelsAnalyzerEnd(analyzer, &result);
    }
    return result;
}

static void print(const char *name, SGAudioLevelsResult r) {
    printf("%-10s rms %.3f peak %.3f low %.3f mid %.3f high %.3f (%u frames)\n", name, r.rms, r.peak, r.low, r.mid, r.high, r.frames);
}

int main(void) {
    SGAudioLevelsAnalyzer analyzer;
    SGAudioLevelsAnalyzerReset(&analyzer, kRate);

    // A 100 Hz sine at 0.5: RMS 0.354, peak 0.5, and nearly all of it in the low band.
    SGAudioLevelsResult low = tone(&analyzer, 100, 0.5f, kWarmupBuffers);
    print("100 Hz", low);
    CHECK(fabs(low.rms - 0.3536) < 0.01, "rms %.3f", low.rms);
    CHECK(fabs(low.peak - 0.5) < 0.01, "peak %.3f", low.peak);
    CHECK(low.low > 0.3 && low.low > 4 * low.mid && low.low > 20 * low.high, "low band should dominate");

    // 8 kHz: the high band.
    SGAudioLevelsResult high = tone(&analyzer, 8000, 0.5f, kWarmupBuffers);
    print("8 kHz", high);
    CHECK(high.high > 0.3 && high.high > 4 * high.mid && high.high > 20 * high.low, "high band should dominate");

    // 1 kHz: the middle.
    SGAudioLevelsResult mid = tone(&analyzer, 1000, 0.5f, kWarmupBuffers);
    print("1 kHz", mid);
    CHECK(mid.mid > 0.3 && mid.mid > 4 * mid.low && mid.mid > 4 * mid.high, "mid band should dominate");

    // Silence after a tone: everything falls to zero once the filters ring out.
    SGAudioLevelsResult silence = tone(&analyzer, 1000, 0, kWarmupBuffers);
    print("silence", silence);
    CHECK(silence.rms == 0 && silence.peak == 0, "silence rms/peak");
    CHECK(silence.low < 1e-4f && silence.mid < 1e-4f && silence.high < 1e-4f, "silence bands");
    CHECK(silence.frames == kFrames, "frames %u", silence.frames);

    // A buffer of NaN and infinities reads as silence, and the next real buffer reads right.
    {
        static float bad[kFrames];
        for (int i = 0; i < kFrames; i++) bad[i] = (i % 3 == 0) ? NAN : (i % 3 == 1) ? INFINITY : -INFINITY;
        SGAudioLevelsResult r;
        SGAudioLevelsAnalyzerBegin(&analyzer);
        SGAudioLevelsAnalyzerFeed(&analyzer, bad, kFrames);
        SGAudioLevelsAnalyzerEnd(&analyzer, &r);
        print("NaN", r);
        CHECK(r.rms == 0 && r.peak == 0 && r.low == 0 && r.mid == 0 && r.high == 0, "NaN buffer reads as silence");
        CHECK(isfinite(analyzer.low[0].z1) && isfinite(analyzer.high[1].z2), "filters stay finite");
        SGAudioLevelsResult after = tone(&analyzer, 100, 0.5f, kWarmupBuffers);
        print("after NaN", after);
        CHECK(after.low > 0.3 && after.low > 20 * after.high, "recovers after NaN");
    }

    // Filter state poisoned by hand (a NaN that slipped past) is cleared by End rather than kept.
    {
        analyzer.low[0].z1 = NAN;
        SGAudioLevelsResult r = tone(&analyzer, 100, 0.5f, 1);
        CHECK(r.low == 0 && r.frames == kFrames, "a NaN result reads as silence");
        CHECK(analyzer.low[0].z1 == 0, "the poisoned state was cleared");
        SGAudioLevelsResult after = tone(&analyzer, 100, 0.5f, kWarmupBuffers);
        CHECK(after.low > 0.3, "and the band reads again");
    }

    // Clipping stays in range.
    SGAudioLevelsResult loud = tone(&analyzer, 100, 3.0f, kWarmupBuffers);
    print("clipping", loud);
    CHECK(loud.rms == 1 && loud.peak == 1 && loud.low == 1, "clamped to 1");

    // No frames fed is no result.
    {
        SGAudioLevelsResult r;
        SGAudioLevelsAnalyzerBegin(&analyzer);
        SGAudioLevelsAnalyzerEnd(&analyzer, &r);
        CHECK(r.frames == 0 && r.rms == 0, "empty buffer");
    }

    // A nonsense sample rate falls back rather than making unstable filters.
    {
        SGAudioLevelsAnalyzer odd;
        SGAudioLevelsAnalyzerReset(&odd, NAN);
        CHECK(odd.sampleRate == 44100, "NaN rate falls back");
        SGAudioLevelsAnalyzerReset(&odd, 1000);
        CHECK(odd.sampleRate == 44100, "too low a rate falls back");
    }

    if (failures) {
        printf("%d failure(s)\n", failures);
        return EXIT_FAILURE;
    }
    printf("levels_test: all checks passed\n");
    return EXIT_SUCCESS;
}
