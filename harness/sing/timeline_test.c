// The render-side timeline at every source rate it takes (one per argument, or 44.1, 48 and 96 kHz): the
// block is 10 ms of the rate, the capacity four seconds, the window two.
#include "Shared/Sing/SGSingTimeline.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static uint32_t rate = 44100, block = 441, capacity = 44100 * 4, window = 88200, recoveryLimit;
static float dry[960 * 2], vocal[960 * 2], output[960 * 2];
static SGAudioStamp stamp(uint64_t at) { return (SGAudioStamp){7, 12, at, 1, block}; }
static float signal(uint64_t sample) { return .25f + .125f * sinf((float)(sample % rate) * .013f); }
static void fill(uint64_t at) {
    for (unsigned i = 0; i < block; i++) {
        dry[i*2] = signal(at+i); dry[i*2+1] = -dry[i*2];
        vocal[i*2] = dry[i*2] * .4f; vocal[i*2+1] = -vocal[i*2];
    }
}
static void verify(uint64_t at, uint32_t count, float gain) {
    for (unsigned i = 0; i < count; i++) {
        assert(fabsf(output[i*2] - signal(at+i)*gain) < 1e-6);
        assert(fabsf(output[i*2] + output[i*2+1]) < 1e-6);
    }
}
static void recoverWithoutChattering(bool sustained) {
    SGSingTimeline *t = SGSingTimelineCreate(rate, rate * 8, window);
    assert(t && SGSingTimelineRecoveryLimit(t) == recoveryLimit);
    SGSingTimelineBegin(t, stamp(0), .2f);
    uint64_t captured = 0, processed = 0, consumed = 0;
    for (; captured < (uint64_t)rate * 6; captured += block) {
        fill(captured); assert(SGSingTimelineCapture(t, stamp(captured), dry));
    }
    for (; processed < (uint64_t)rate * 3; processed += block) {
        fill(processed); assert(SGSingTimelineVocals(t, stamp(processed), vocal));
    }
    // Every callback emits the next original frame, including recovery and a final drain.
    #define ADVANCE() do { \
        if (SGSingTimelineWritable(t) >= block) { \
            fill(captured); assert(SGSingTimelineCapture(t, stamp(captured), dry)); captured += block; \
        } \
        assert(SGSingTimelineRead(t, output, block) == block); \
        for (unsigned n = 0; n < block; n++) { \
            float ratio = output[n*2] / signal(consumed+n); \
            assert(ratio >= .616f - 1e-5 && ratio <= 1 + 1e-5); \
            assert(fabsf(output[n*2] + output[n*2+1]) < 1e-6); \
        } \
        consumed += block; \
    } while (0)
    while (SGSingTimelineGetState(t) != SGSingTimelineRecovering) ADVANCE();
    uint64_t firstRecovery = consumed;
    for (; processed < consumed + rate; processed += block) {
        fill(processed); assert(SGSingTimelineVocals(t, stamp(processed), vocal));
    }
    ADVANCE();
    // One late hop used to re-enable reduction with only a second of coverage. Another
    // slow inference would bring the original vocals back almost immediately.
    assert(SGSingTimelineGetState(t) == SGSingTimelineRecovering);
    for (; processed < consumed + window; processed += block) {
        fill(processed); assert(SGSingTimelineVocals(t, stamp(processed), vocal));
    }
    ADVANCE();
    assert(SGSingTimelineGetState(t) == SGSingTimelineActive);
    if (sustained) {
        uint64_t healthyUntil = consumed + recoveryLimit + block * 2;
        while (consumed < healthyUntil) {
            for (; processed < captured; processed += block) {
                fill(processed); assert(SGSingTimelineVocals(t, stamp(processed), vocal));
            }
            ADVANCE();
            assert(SGSingTimelineGetState(t) == SGSingTimelineActive);
        }
    }
    while (SGSingTimelineGetState(t) != SGSingTimelineRecovering) ADVANCE();
    if (sustained) {
        // A genuinely healthy interval earns a new budget for a later, unrelated stall.
        firstRecovery = consumed;
        ADVANCE();
        assert(SGSingTimelineGetState(t) == SGSingTimelineRecovering);
    }
    // A brief recovery is not a healthy run and must not reset the outage deadline.
    while (consumed < firstRecovery + recoveryLimit + block) ADVANCE();
    assert(SGSingTimelineGetState(t) == SGSingTimelineDraining);
    SGSingTimelineDestroy(t);
    #undef ADVANCE
}
static void atRate(uint32_t hz) {
    rate = hz; block = hz / 100; capacity = hz * 4; window = hz * 2; recoveryLimit = hz * SGSingRecoverySeconds;
    printf("-- %u Hz: block %u\n", rate, block);
    // Only the supported rates, within the largest timeline the render side is sized for.
    assert(!SGSingTimelineCreate(32000, capacity, window) && !SGSingTimelineCreate(rate, SGSingMaxTimelineFrames + 1, window));
    assert(!SGSingTimelineCreate(rate, capacity, capacity + 1) && !SGSingTimelineCreate(rate, capacity, 0));
    SGSingTimeline *cold = SGSingTimelineCreate(rate, block * 40, block * 2);
    SGSingTimelineBegin(cold, stamp(0), .7f);
    for (unsigned n = 0; n < 32; n++) { fill(n*block); assert(SGSingTimelineCapture(cold,stamp(n*block),dry)); }
    for (unsigned n = 0; n < 4; n++) {
        assert(SGSingTimelineRead(cold, output, block) == block); verify(n*block,block,1);
    }
    fill(5*block); assert(!SGSingTimelineVocals(cold,stamp(5*block),vocal)); // future gap
    fill(4*block); assert(SGSingTimelineVocals(cold,stamp(4*block),vocal)); // expired initial prefix
    fill(6*block); assert(!SGSingTimelineVocals(cold,stamp(6*block),vocal)); // a later gap is still rejected
    fill(5*block); assert(SGSingTimelineVocals(cold,stamp(5*block),vocal));
    for (unsigned n = 6; n < 20; n++) { fill(n*block); assert(SGSingTimelineVocals(cold,stamp(n*block),vocal)); }
    assert(SGSingTimelineRead(cold,output,block) == block && SGSingTimelineGetState(cold) == SGSingTimelineActive);
    SGSingTimelineDestroy(cold);
    recoverWithoutChattering(false);
    recoverWithoutChattering(true);
    assert(!SGSingTimelineCreate(rate, 0, 1));
    SGSingTimeline *t = SGSingTimelineCreate(rate, capacity, block*2);
    assert(t);
    SGSingTimelineBegin(t, stamp(0), 0);
    uint64_t captured = 0, consumed = 0;
    // Capture ahead while original audio remains continuous from the first callback.
    for (unsigned i = 0; i < 200; i++) {
        for (unsigned extra = 0; extra < 2; extra++) {
            fill(captured);
            assert(SGSingTimelineCapture(t, stamp(captured), dry));
            captured += block;
        }
        assert(SGSingTimelineRead(t, output, block) == block);
        verify(consumed, block, 1);
        consumed += block;
        assert(SGSingTimelineConsumed(t) == consumed);
    }
    for (uint64_t at = 0; at < captured; at += block) {
        fill(at); assert(SGSingTimelineVocals(t, stamp(at), vocal));
    }
    // Cross the circular buffer repeatedly while preserving exact source order.
    for (unsigned i = 0; i < 1000; i++) {
        fill(captured);
        assert(SGSingTimelineCapture(t, stamp(captured), dry));
        assert(SGSingTimelineVocals(t, stamp(captured), vocal));
        captured += block;
        assert(SGSingTimelineRead(t, output, block) == block);
        if (i >= 3) verify(consumed, block, .616f); // initial 30 ms fade into reduced vocals
        consumed += block;
    }
    assert(SGSingTimelineGetState(t) == SGSingTimelineActive);
    SGSingTimelineBypass(t);
    assert(!SGSingTimelineWritable(t));
    assert(!SGSingTimelineCapture(t, stamp(captured), dry));
    assert(!SGSingTimelineVocals(t, stamp(captured), vocal));
    unsigned fadeBlocks = 0;
    while (SGSingTimelineQueued(t)) {
        uint32_t count = SGSingTimelineRead(t, output, block);
        assert(count == block);
        if (fadeBlocks++ >= 12) verify(consumed, count, 1);
        consumed += count;
    }
    assert(consumed == captured && SGSingTimelineGetState(t) == SGSingTimelineIdle);
    assert(SGSingTimelineConsumed(t) == captured);
    // No captured frame was skipped or replayed; the next direct pull begins at captured.
    SGSingTimelineBegin(t, (SGAudioStamp){8, 99, 1234, 2, block}, 0);
    assert(!SGSingTimelineVocals(t, stamp(0), vocal));
    assert(!SGSingTimelineCapture(t, stamp(1234), dry));
    assert(!SGSingTimelineCapture(t, (SGAudioStamp){8, 99, 1235, 2, block}, dry));
    assert(SGSingTimelineCapture(t, (SGAudioStamp){8, 99, 1234, 2, block}, dry));
    SGSingTimelineBypass(t); // cancelled before a model result: all buffered original still drains
    assert(SGSingTimelineRead(t, output, block) == block);
    for (unsigned i = 0; i < block*2; i++) assert(output[i] == dry[i]);
    assert(SGSingTimelineGetState(t) == SGSingTimelineIdle);
    // Permanent worker outage first keeps dry playback aligned, then expires its recovery budget
    // and releases the delay. The source keeps supplying audio until the terminal drain.
    SGSingTimelineBegin(t, stamp(0), 0);
    for (uint64_t at = 0; at < rate; at += block) {
        fill(at); assert(SGSingTimelineCapture(t, stamp(at), dry));
        if (at < block * 20) assert(SGSingTimelineVocals(t, stamp(at), vocal));
    }
    consumed = 0;
    captured = rate;
    while (SGSingTimelineGetState(t) != SGSingTimelineIdle) {
        if (SGSingTimelineWritable(t)) {
            fill(captured); assert(SGSingTimelineCapture(t, stamp(captured), dry)); captured += block;
        }
        uint32_t count = SGSingTimelineRead(t, output, block);
        assert(count == block);
        if (consumed >= block * 20 + rate * 120 / 1000) verify(consumed, count, 1); // past the vocals and the 120 ms bypass
        for (unsigned i = 0; i < block*2; i++) assert(isfinite(output[i]) && fabsf(output[i]) <= 1);
        consumed += count;
    }
    assert(consumed == captured && consumed > recoveryLimit && SGSingTimelineGetState(t) == SGSingTimelineIdle);
    SGSingTimelineDestroy(t);
}
int main(int argc, char **argv) {
    if (argc > 1) for (int i = 1; i < argc; i++) atRate((uint32_t)atoi(argv[i]));
    else { atRate(44100); atRate(48000); atRate(96000); }
    puts("sing timeline: buffering, wraparound, exact source order, dry drain, stale results and worker outage passed at every rate");
}
