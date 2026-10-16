// Real model worker and production stream, driven at audio cadence with a local test fixture. With
// `--rate R` the source is at R (one of SGSingSupportedRate; the 44.1 kHz fixture is brought to it by the
// production resampler) and the worker resamples each window to the model and its vocals back.
#include "Shared/Sing/SGSingResample.h"
#include "Shared/Sing/SGSingStream.h"
#include "Shared/Sing/SGStemWorker.h"
#include <assert.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static SGSingStream *stream;
static SGSingGeometry geometry;
static uint32_t rate = 44100, tickFrames = 441; // 10 ms of the source a render
static atomic_bool loading, ready, finished, failed;
static float renderBuffer[960 * 2], *fixture;
static uint64_t pulled, audible;
static size_t fixtureFrames;
static bool injectStall;
static uint64_t firstOutput = UINT64_MAX;
static double loadStarted;
static double now(void);

static int32_t readInput(void *context, float *pcm, uint64_t *metadata) {
    assert(context == stream);
    int32_t state = SGSingStreamWorkerState(stream);
    if (state <= 0) return state;
    SGAudioStamp stamp;
    if (!SGSingStreamReadLiveInput(stream, &stamp, pcm)) return 0;
    metadata[0] = stamp.generation; metadata[1] = stamp.track;
    metadata[2] = stamp.sourceFrame; metadata[3] = stamp.format;
    return stamp.frames;
}
static int32_t writeOutput(void *context, const float *pcm, uint32_t frames, uint64_t generation,
                            uint64_t track, uint64_t frame, uint32_t format) {
    assert(context == stream);
    if (SGSingStreamWorkerState(stream) < 0) return 0;
    if (firstOutput == UINT64_MAX) firstOutput = frame;
    // Hold one completed result until the live buffer actually enters recovery. A fixed sleep
    // can miss depletion on a faster backend or leave too little time to observe its recovery.
    if (injectStall && frame - firstOutput == (uint64_t)geometry.hopFrames * 8) {
        double deadline = now() + 8;
        while (SGSingStreamState(stream) != SGSingTimelineRecovering && now() < deadline &&
               SGSingStreamWorkerState(stream) > 0) usleep(10000);
        assert(SGSingStreamState(stream) == SGSingTimelineRecovering);
    }
    return SGSingStreamWriteVocals(stream, (SGAudioStamp){generation,track,frame,format,frames}, pcm) ? 1 : -1;
}
static void report(void *context, int32_t status) {
    assert(context == stream);
    if (status == SGStemLoading) atomic_store(&loading, true);
    if (status == SGStemReady) {
        fprintf(stderr, "model ready after %.3f seconds\n", now() - loadStarted);
        SGSingStreamSetModelReady(stream, true); atomic_store(&ready, true);
    }
    if (status == SGStemFailed) {
        fprintf(stderr, "worker failed: timeline state %d, queued %llu\n", SGSingStreamState(stream),
                (unsigned long long)SGSingStreamQueued(stream));
        atomic_store(&failed, true);
    }
    if (status == SGStemFinished) atomic_store(&finished, true);
}
static int32_t source(void *context, uint32_t frames, float *pcm) {
    (void)context;
    for (unsigned n = 0; n < frames; n++) {
        size_t at = (pulled+n) % fixtureFrames;
        pcm[n*2] = fixture[at]; pcm[n*2+1] = fixture[fixtureFrames+at];
    }
    pulled += frames;
    return 0;
}
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec/1e9; }
static bool resample(void *resampler, const float *in, uint32_t inFrames, float *out, uint32_t outFrames) {
    return SGSingResamplerProcess(resampler, in, inFrames, out, outFrames);
}
// The planar 44.1 kHz fixture as interleaved stereo at the source's rate, whole seconds of it.
static void fixtureAt(uint32_t hz) {
    size_t seconds = fixtureFrames / 44100; assert(seconds);
    SGSingResampler *up = SGSingResamplerCreate(44100, hz); assert(up);
    float *stereo = malloc(seconds * 44100 * 2 * sizeof(float)), *converted = malloc(seconds * hz * 2 * sizeof(float));
    assert(stereo && converted);
    for (size_t n = 0; n < seconds * 44100; n++) { stereo[n*2] = fixture[n]; stereo[n*2+1] = fixture[fixtureFrames+n]; }
    assert(SGSingResamplerProcess(up, stereo, (uint32_t)(seconds * 44100), converted, (uint32_t)(seconds * hz)));
    fixtureFrames = seconds * hz;
    for (size_t n = 0; n < fixtureFrames; n++) { fixture[n] = converted[n*2]; fixture[fixtureFrames+n] = converted[n*2+1]; }
    free(stereo); free(converted); SGSingResamplerDestroy(up);
}
int main(int argc, char **argv) {
    if (argc == 5 && !strcmp(argv[3], "--rate")) { rate = (uint32_t)atoi(argv[4]); argc = 3; }
    assert(SGSingSupportedRate(rate) && rate % 100 == 0);
    tickFrames = rate / 100;
    assert(argc >= 3 && argc <= 5); // model, golden input, optional cancel tick and stalled-output case
    bool cancelLoading = argc == 4 && !strcmp(argv[3], "--cancel-loading");
    bool cold = argc == 4 && !strcmp(argv[3], "--cold");
    unsigned cancelAt = argc >= 4 && !cancelLoading && !cold ? (unsigned)atoi(argv[3]) : cold ? 2400 : 1200;
    injectStall = argc == 5;
    assert(cancelAt >= 200 && cancelAt <= 2400);
    FILE *file = fopen(argv[2], "rb"); assert(file);
    fseek(file, 0, SEEK_END); long bytes = ftell(file); rewind(file);
    assert(bytes > 0 && bytes % 8 == 0);
    fixture = malloc(bytes); assert(fixture && fread(fixture, 1, bytes, file) == (size_t)bytes); fclose(file);
    fixtureFrames = bytes / 8;
    assert(SGSingGeometryAt(rate, &geometry));
    SGSingResampler *toModel = NULL, *fromModel = NULL;
    if (rate != SGSingSampleRate) {
        fixture = realloc(fixture, (size_t)(fixtureFrames / 44100) * rate * 2 * sizeof(float)); assert(fixture);
        fixtureAt(rate);
        toModel = SGSingResamplerCreate(rate, SGSingSampleRate); fromModel = SGSingResamplerCreate(SGSingSampleRate, rate);
        assert(toModel && fromModel);
    }
    stream = SGSingStreamCreate((SGAudioStamp){1,2,0,3,0}, geometry, 1); assert(stream);
    SGSingStreamSetModelReady(stream, false);
    loadStarted = now();
    void *worker = SGStemWorkerStart(stream, argv[1], geometry.windowFrames, geometry.hopFrames, resample, toModel, fromModel,
                                     readInput, writeOutput, report); assert(worker);
    double deadline = now()+60;
    if (cancelLoading) {
        while (!atomic_load(&loading) && now() < deadline) usleep(1000);
        assert(atomic_load(&loading) && !atomic_load(&ready));
        SGStemWorkerCancel(worker, 1);
        while (!atomic_load(&finished) && now() < deadline) usleep(10000);
        assert(atomic_load(&finished) && !atomic_load(&ready) && !atomic_load(&failed));
        assert(!pulled && !SGSingStreamPresented(stream) && !SGSingStreamQueued(stream));
        SGSingStreamDestroy(stream); free(fixture);
        puts("real worker: cancelled loading before Ready; no source pulls, no failure callback, finished safely");
        return 0;
    }
    if (!cold) {
        while (!atomic_load(&ready) && !atomic_load(&finished) && now() < deadline) usleep(10000);
        assert(atomic_load(&ready) && !atomic_load(&failed));
    }
    double start = now(), activation = 0;
    bool recovered = false, restored = false;
    double recoveryStarted = 0;
    for (unsigned tick = 0; tick < cancelAt + 650; tick++) {
        double wait = start + tick*.01 - now();
        if (wait > 0) usleep((unsigned)(wait*1e6));
        if (tick == cancelAt) SGSingStreamBypass(stream);
        assert(!SGSingStreamRender(stream, tickFrames, renderBuffer, source, NULL, rate));
        SGSingTimelineState state = SGSingStreamState(stream);
        // Original PCM remains continuous throughout model preparation, reduction and drain.
        for (unsigned n = 0; n < tickFrames; n++) {
            size_t at = (audible+n) % fixtureFrames;
            assert(fabsf(renderBuffer[n*2] - fixture[at]) < 1e-6);
            assert(fabsf(renderBuffer[n*2+1] - fixture[fixtureFrames+at]) < 1e-6);
        }
        audible += tickFrames;
        assert(SGSingStreamPresented(stream) == audible);
        if (state == SGSingTimelineActive && !activation) {
            activation = now()-start;
            fprintf(stderr, "first aligned vocal reduction: %.3f s; original audible from callback zero\n", activation);
        }
        if (tick < cancelAt) {
            if (state == SGSingTimelineRecovering) {
                assert(injectStall); recovered = true;
                if (!recoveryStarted) recoveryStarted = now();
            } else if (recovered && state == SGSingTimelineActive && !restored) {
                assert(now() - recoveryStarted < SGSingRecoverySeconds);
                restored = true;
            }
            assert(SGSingStreamStopReason(stream) == SGSingStopNone);
        }
        assert(!atomic_load(&failed));
    }
    if (cancelAt >= 1000) assert(activation > 0 && activation < cancelAt * .01);
    if (injectStall) assert(recovered && restored);
    assert(SGSingStreamState(stream) == SGSingTimelineIdle && pulled == audible);
    SGStemWorkerCancel(worker, 1);
    deadline = now()+5;
    while (!atomic_load(&finished) && now() < deadline) usleep(10000);
    assert(atomic_load(&finished));
    SGSingStreamDestroy(stream); free(fixture);
    SGSingResamplerDestroy(toModel); SGSingResamplerDestroy(fromModel);
    printf("real worker at %u Hz: first reduction %.3fs; original audible from callback zero; %.2f seconds at cadence; exact original samples through active/cancellation and drain; recovery %s; finished safely\n",
           rate, activation, (cancelAt + 650) / 100.0, injectStall ? "passed" : "not injected");
}
