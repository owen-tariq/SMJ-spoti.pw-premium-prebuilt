// The worker's window resampler (Shared/Sing/SGSingResample.h): exact lengths both ways between every
// supported rate and the model's 44.1 kHz, an exact copy at the same rate, unity gain at DC, tones kept
// through a round trip, independent channels, silence beyond the ends, determinism and rejected lengths.
#include "Shared/Sing/SGSingResample.h"
#include "Shared/Sing/SGSingFormat.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const double kPi = 3.14159265358979323846;
static const uint32_t rates[] = {44100, 48000, 88200, 96000};
enum { edge = 64 }; // frames at either end of a window that the independent-window design leaves imprecise

static double snr(const float *reference, const float *got, uint32_t frames, unsigned channel) {
    double signal = 0, noise = 0;
    for (uint32_t n = edge; n + edge < frames; n++) {
        double a = reference[n*2+channel], b = got[n*2+channel];
        signal += a * a; noise += (a - b) * (a - b);
    }
    return 10 * log10(signal / fmax(noise, 1e-30));
}
static void tones(float *pcm, uint32_t frames, uint32_t rate, double leftHz, double rightHz) {
    for (uint32_t n = 0; n < frames; n++) {
        pcm[n*2] = (float)(.5 * sin(2 * kPi * leftHz * n / rate));
        pcm[n*2+1] = (float)(.25 * cos(2 * kPi * rightHz * n / rate));
    }
}
static void roundTrip(uint32_t rate) {
    SGSingGeometry g; assert(SGSingGeometryAt(rate, &g));
    uint32_t frames = g.windowFrames;
    SGSingResampler *in = SGSingResamplerCreate(rate, SGSingSampleRate), *out = SGSingResamplerCreate(SGSingSampleRate, rate);
    assert(in && out);
    float *source = calloc((size_t)frames * 2, sizeof(float)), *model = calloc(SGSingWindowFrames * 2, sizeof(float));
    float *back = calloc((size_t)frames * 2, sizeof(float)), *again = calloc(SGSingWindowFrames * 2, sizeof(float));
    assert(source && model && back && again);
    // Exactly the model's window from exactly the source's, and back; nothing else is accepted.
    assert(!SGSingResamplerProcess(in, source, frames - 1, model, SGSingWindowFrames));
    assert(!SGSingResamplerProcess(in, source, frames, model, SGSingWindowFrames - 1));
    assert(!SGSingResamplerProcess(in, source, 0, model, 0));
    // Tones well inside the model's band, a different one per channel.
    tones(source, frames, rate, 1000, 3000);
    assert(SGSingResamplerProcess(in, source, frames, model, SGSingWindowFrames));
    float *expected = calloc(SGSingWindowFrames * 2, sizeof(float)); assert(expected);
    tones(expected, SGSingWindowFrames, SGSingSampleRate, 1000, 3000);
    double down0 = snr(expected, model, SGSingWindowFrames, 0), down1 = snr(expected, model, SGSingWindowFrames, 1);
    assert(SGSingResamplerProcess(out, model, SGSingWindowFrames, back, frames));
    double trip0 = snr(source, back, frames, 0), trip1 = snr(source, back, frames, 1);
    // Bit-for-bit the same the second time.
    assert(SGSingResamplerProcess(in, source, frames, again, SGSingWindowFrames));
    assert(!memcmp(model, again, SGSingWindowFrames * 2 * sizeof(float)));
    // A tone near the top of the model's band survives too, less exactly, and nothing becomes non-finite.
    tones(source, frames, rate, 15000, 12000);
    assert(SGSingResamplerProcess(in, source, frames, model, SGSingWindowFrames));
    assert(SGSingResamplerProcess(out, model, SGSingWindowFrames, back, frames));
    double high = fmin(snr(source, back, frames, 0), snr(source, back, frames, 1));
    for (uint32_t n = 0; n < frames * 2; n++) assert(isfinite(back[n]) && fabsf(back[n]) < .6f);
    // DC through either way has unity gain, and the ends settle to the value within the edge.
    for (uint32_t n = 0; n < frames * 2; n++) source[n] = n % 2 ? -.3f : .7f;
    assert(SGSingResamplerProcess(in, source, frames, model, SGSingWindowFrames));
    for (uint32_t n = edge; n + edge < SGSingWindowFrames; n++) {
        assert(fabsf(model[n*2] - .7f) < 2e-5f && fabsf(model[n*2+1] + .3f) < 2e-5f);
    }
    assert(SGSingResamplerProcess(out, model, SGSingWindowFrames, back, frames));
    for (uint32_t n = edge; n + edge < frames; n++) assert(fabsf(back[n*2] - .7f) < 5e-5f && fabsf(back[n*2+1] + .3f) < 5e-5f);
    // Silence is exactly silence, and a window that ends in silence has silence at its end.
    memset(source, 0, (size_t)frames * 2 * sizeof(float));
    assert(SGSingResamplerProcess(in, source, frames, model, SGSingWindowFrames));
    for (uint32_t n = 0; n < SGSingWindowFrames * 2; n++) assert(model[n] == 0);
    source[0] = 1; // an impulse at the very start stays at the start, with nothing wrapping to the end
    assert(SGSingResamplerProcess(in, source, frames, model, SGSingWindowFrames));
    for (uint32_t n = edge; n < SGSingWindowFrames; n++) assert(fabsf(model[n*2]) < 1e-6f);
    printf("%u Hz: tones down %.1f/%.1f dB, round trip %.1f/%.1f dB, 15/12 kHz round trip %.1f dB\n",
           rate, down0, down1, trip0, trip1, high);
    assert(down0 > 60 && down1 > 60 && trip0 > 60 && trip1 > 60 && high > 30);
    free(source); free(model); free(back); free(again); free(expected);
    SGSingResamplerDestroy(in); SGSingResamplerDestroy(out);
}
int main(void) {
    assert(!SGSingResamplerCreate(32000, 44100) && !SGSingResamplerCreate(44100, 22050) && !SGSingResamplerCreate(0, 44100));
    // The same rate twice is an exact copy, so the worker can take the same path at every rate.
    SGSingResampler *same = SGSingResamplerCreate(44100, 44100); assert(same);
    float *pcm = calloc(SGSingWindowFrames * 2, sizeof(float)), *copy = calloc(SGSingWindowFrames * 2, sizeof(float));
    assert(pcm && copy);
    tones(pcm, SGSingWindowFrames, 44100, 440, 7040);
    assert(SGSingResamplerProcess(same, pcm, SGSingWindowFrames, copy, SGSingWindowFrames));
    assert(!memcmp(pcm, copy, SGSingWindowFrames * 2 * sizeof(float)));
    free(pcm); free(copy); SGSingResamplerDestroy(same);
    SGSingResamplerDestroy(NULL);
    // The lossless case in plain numbers: a 1 kHz tone, two seconds of 48 kHz to exactly the model's window,
    // within 1 % RMS of the tone computed at 44.1 kHz over the whole window, edges included.
    SGSingResampler *down = SGSingResamplerCreate(48000, 44100); assert(down);
    float *source = calloc(96000 * 2, sizeof(float)), *model = calloc(SGSingWindowFrames * 2, sizeof(float));
    assert(source && model);
    for (uint32_t n = 0; n < 96000; n++) source[n*2] = source[n*2+1] = (float)sin(2 * kPi * 1000 * n / 48000.);
    assert(SGSingResamplerProcess(down, source, 96000, model, SGSingWindowFrames));
    double error = 0, power = 0;
    for (uint32_t n = 0; n < SGSingWindowFrames; n++) {
        double expected = sin(2 * kPi * 1000 * n / 44100.);
        error += (model[n*2] - expected) * (model[n*2] - expected); power += expected * expected;
    }
    printf("1 kHz, 48 kHz to 44.1 kHz: %.4f %% RMS error over the whole window\n", 100 * sqrt(error / power));
    assert(sqrt(error / power) < .01);
    free(source); free(model); SGSingResamplerDestroy(down);
    for (unsigned i = 0; i < sizeof rates / sizeof *rates; i++) roundTrip(rates[i]);
    puts("sing resampler: exact lengths, identity, unity DC gain, tones, independent channels, silence and determinism passed");
}
