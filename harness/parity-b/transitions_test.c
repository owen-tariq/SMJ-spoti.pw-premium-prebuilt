// SPDX-License-Identifier: MIT
// Standalone check of Shared/Transitions/SGTransitionDSP.h, the maths the render thread runs on a track's
// entry, on the Mac or anywhere with a C11 compiler:
//   zig cc -std=c11 -Wall -Wextra -Werror -lm -I../../tweak/Sources/Shared/Transitions transitions_test.c
// It asserts the gain only ever rises and ends at unity, the cutoff only ever rises, the filter is stable
// (bounded, no NaN or infinity) over white noise and a full-scale step, a zero length leaves the signal
// untouched, and renders of any size land on the same frames as one big render.
#include "../../tweak/Sources/Shared/Transitions/SGTransitionDSP.h"
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(condition, ...) do { if (!(condition)) { failures++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

enum { kFrames = 1 << 16, kRate = 48000 };
static float lanesA[2][kFrames], lanesB[2][kFrames], source[2][kFrames];

static uint32_t rng = 0x9e3779b9u;
static float noise(void) {
    rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    return (float)((double)rng / 4294967296.0 * 2.0 - 1.0);
}

static void fillSource(void) {
    for (int ch = 0; ch < 2; ch++) for (uint32_t i = 0; i < kFrames; i++) source[ch][i] = noise();
}

static void copySource(float dst[2][kFrames]) { memcpy(dst, source, sizeof source); }

static void testGainMonotonic(void) {
    const float start = -12;
    float previous = 0;
    for (int i = 0; i <= 1000; i++) {
        float gain = SGTransitionGainAt(i / 1000.0, start);
        CHECK(gain >= previous, "gain fell at %d: %g < %g", i, gain, previous);
        CHECK(gain == gain && gain <= 1.0f, "gain out of range at %d: %g", i, gain);
        previous = gain;
    }
    CHECK(fabs(SGTransitionGainAt(0, start) - 0.25118864) < 1e-6, "start gain is not -12 dB: %g", SGTransitionGainAt(0, start));
    CHECK(SGTransitionGainAt(1, start) == 1.0f, "end gain is not unity: %g", SGTransitionGainAt(1, start));
}

static void testCutoffMonotonic(void) {
    double previous = 0;
    for (int i = 0; i <= 1000; i++) {
        double cutoff = SGTransitionCutoffAt(i / 1000.0, 800, SGTransitionEndCutoffHz);
        CHECK(cutoff >= previous, "cutoff fell at %d", i);
        previous = cutoff;
    }
    CHECK(fabs(SGTransitionCutoffAt(0, 800, 20000) - 800) < 1e-9, "start cutoff");
    CHECK(fabs(SGTransitionCutoffAt(1, 800, 20000) - 20000) < 1e-6, "end cutoff");
    CHECK(fabs(SGTransitionCutoffAt(0.5, 100, 10000) - 1000) < 1e-6, "log midpoint");
}

static void testFilterStable(void) {
    double rates[] = {44100, 48000, 96000, 8000};
    for (size_t r = 0; r < sizeof rates / sizeof *rates; r++) {
        double rate = rates[r];
        for (double cutoff = 10; cutoff <= 40000; cutoff *= 1.5) {
            SGBiquadCoefficients c = SGBiquadLowPass(rate, cutoff);
            // Stability: poles inside the unit circle (|a2| < 1 and |a1| < 1 + a2).
            CHECK(fabs(c.a2) < 1.0 && fabs(c.a1) < 1.0 + c.a2, "unstable at %g Hz / %g: a1 %g a2 %g", cutoff, rate, c.a1, c.a2);
            // DC gain of a low-pass is unity.
            double dc = (c.b0 + c.b1 + c.b2) / (1.0 + c.a1 + c.a2);
            CHECK(fabs(dc - 1.0) < 1e-6, "DC gain %g at %g Hz / %g", dc, cutoff, rate);
            SGBiquadState s = {0, 0};
            float peak = 0;
            for (int i = 0; i < 20000; i++) {
                float y = SGBiquadTick(&c, &s, 1.0f); // full-scale step
                CHECK(y == y && fabsf(y) < 10, "step blew up at %g Hz: %g", cutoff, y);
                if (fabsf(y) > peak) peak = fabsf(y);
            }
            CHECK(peak < 1.2f, "step overshoot %g at %g Hz / %g", peak, cutoff, rate);
            CHECK(fabsf(s.z1) < 10 && fabsf(s.z2) < 10, "state unbounded");
        }
    }
}

static void testZeroLengthIsIdentity(void) {
    copySource(lanesA);
    SGTransitionRun run;
    SGTransitionParams params = {kRate, 0, 800, -12};
    SGTransitionRunStart(&run, &params);
    CHECK(!SGTransitionRunActive(&run), "zero length started a run");
    float *lanes[2] = {lanesA[0], lanesA[1]};
    uint32_t shaped = SGTransitionRunProcess(&run, lanes, 2, kFrames);
    CHECK(shaped == 0, "zero length shaped %u frames", shaped);
    CHECK(memcmp(lanesA, source, sizeof source) == 0, "zero length changed the signal");
    // A zero rate is identity too (the output's format is not known yet).
    SGTransitionParams noRate = {0, 1000, 800, -12};
    SGTransitionRunStart(&run, &noRate);
    CHECK(!SGTransitionRunActive(&run), "zero rate started a run");
    CHECK(SGTransitionRunProcess(&run, lanes, 2, kFrames) == 0, "zero rate shaped frames");
    CHECK(memcmp(lanesA, source, sizeof source) == 0, "zero rate changed the signal");
}

static void testRunShapesAndEnds(void) {
    copySource(lanesA);
    SGTransitionRun run;
    uint32_t length = kRate * 600 / 1000;
    SGTransitionParams params = {kRate, length, 800, -12};
    SGTransitionRunStart(&run, &params);
    CHECK(SGTransitionRunActive(&run), "run did not start");
    float *lanes[2] = {lanesA[0], lanesA[1]};
    uint32_t shaped = SGTransitionRunProcess(&run, lanes, 2, kFrames);
    CHECK(shaped == length, "shaped %u, expected %u", shaped, length);
    CHECK(!SGTransitionRunActive(&run), "run still active after its length");
    // No NaN or infinity anywhere, and nothing past the length touched.
    for (int ch = 0; ch < 2; ch++) {
        for (uint32_t i = 0; i < kFrames; i++) {
            float y = lanesA[ch][i];
            CHECK(y == y && fabsf(y) < 4, "bad sample %g at %u", y, i);
        }
        CHECK(memcmp(lanesA[ch] + length, source[ch] + length, (kFrames - length) * sizeof(float)) == 0, "frames past the length changed (ch %d)", ch);
    }
    // The envelope rises: RMS of the first 2048 frames is well under that of the last 2048 of the ramp, which
    // in turn is near the source's (the filter is open and the gain unity by then).
    double early = 0, late = 0, ref = 0;
    for (uint32_t i = 0; i < 2048; i++) {
        early += lanesA[0][i] * lanesA[0][i];
        late += lanesA[0][length - 2048 + i] * lanesA[0][length - 2048 + i];
        ref += source[0][length - 2048 + i] * source[0][length - 2048 + i];
    }
    CHECK(early < late * 0.25, "entry not softened: early %g late %g", early, late);
    CHECK(late > ref * 0.5 && late < ref * 1.2, "end of ramp not near the source: late %g ref %g", late, ref);
    // Processing a further buffer once idle is a no-op.
    CHECK(SGTransitionRunProcess(&run, lanes, 2, 512) == 0, "idle run shaped frames");
}

// Renders of odd sizes (as Core Audio hands them) land on the same output as one big render.
static void testBlockSizeIndependence(void) {
    uint32_t length = 12345;
    SGTransitionParams params = {44100, length, 300, -12};
    copySource(lanesA);
    SGTransitionRun one;
    SGTransitionRunStart(&one, &params);
    float *a[2] = {lanesA[0], lanesA[1]};
    SGTransitionRunProcess(&one, a, 2, kFrames);

    copySource(lanesB);
    SGTransitionRun many;
    SGTransitionRunStart(&many, &params);
    uint32_t sizes[] = {1, 7, 64, 100, 471, 512, 1024, 3};
    uint32_t done = 0, s = 0;
    while (done < kFrames) {
        uint32_t count = sizes[s++ % (sizeof sizes / sizeof *sizes)];
        if (count > kFrames - done) count = kFrames - done;
        float *b[2] = {lanesB[0] + done, lanesB[1] + done};
        SGTransitionRunProcess(&many, b, 2, count);
        done += count;
    }
    int mismatches = 0;
    for (int ch = 0; ch < 2; ch++) for (uint32_t i = 0; i < kFrames; i++) if (lanesA[ch][i] != lanesB[ch][i]) mismatches++;
    CHECK(mismatches == 0, "%d samples differ between one render and many", mismatches);
}

static void testMonoAndNullLane(void) {
    copySource(lanesA);
    SGTransitionRun run;
    SGTransitionParams params = {kRate, 4800, 2500, -12};
    SGTransitionRunStart(&run, &params);
    float *lanes[2] = {lanesA[0], NULL};
    CHECK(SGTransitionRunProcess(&run, lanes, 2, kFrames) == 4800, "mono run length");
    CHECK(memcmp(lanesA[1], source[1], sizeof source[1]) == 0, "NULL lane was touched");
    CHECK(lanesA[0][0] != source[0][0] || source[0][0] == 0, "mono lane untouched");
}

int main(void) {
    fillSource();
    testGainMonotonic();
    testCutoffMonotonic();
    testFilterStable();
    testZeroLengthIsIdentity();
    testRunShapesAndEnds();
    testBlockSizeIndependence();
    testMonoAndNullLane();
    if (failures) {
        printf("%d failure(s)\n", failures);
        return 1;
    }
    printf("transitions_test: all checks passed\n");
    return 0;
}
