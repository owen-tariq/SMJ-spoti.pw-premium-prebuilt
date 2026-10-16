#include "SGSingResample.h"
#include "SGSingFormat.h"
#include <math.h>
#include <stdlib.h>

// 64 taps at the input rate, a Kaiser window of beta 9 (about 90 dB of stopband): 88,200 output frames of
// stereo take some 11 million multiply-adds a way, a few milliseconds beside the model's run. The cutoff is
// the lower of the two Nyquist frequencies; its transition band lies above anything the model's mel bands
// weigh, and the model only ever sees 44.1 kHz.
enum { kHalfTaps = 32, kTaps = 2 * kHalfTaps };
static const double kKaiserBeta = 9, kPi = 3.14159265358979323846;

struct SGSingResampler {
    uint32_t up, down;  // outRate : inRate in lowest terms; an output frame n sits at input position n * down / up
    float *taps;        // up phases of kTaps, phase p for the fractional position p / up
};

static double bessel0(double x) { // the modified Bessel function of the first kind, order zero
    double sum = 1, term = 1, half = x / 2;
    for (unsigned k = 1; k < 100; k++) {
        term *= (half / k) * (half / k);
        sum += term;
        if (term < sum * 1e-17) break;
    }
    return sum;
}
static uint32_t gcd(uint32_t a, uint32_t b) {
    while (b) { uint32_t t = a % b; a = b; b = t; }
    return a;
}

SGSingResampler *SGSingResamplerCreate(uint32_t inRate, uint32_t outRate) {
    if (!SGSingSupportedRate(inRate) || !SGSingSupportedRate(outRate)) return NULL;
    uint32_t divisor = gcd(inRate, outRate);
    SGSingResampler *r = calloc(1, sizeof *r);
    double *row = calloc(kTaps, sizeof *row);
    if (!r || !row) { free(r); free(row); return NULL; }
    r->up = outRate / divisor; r->down = inRate / divisor;
    r->taps = calloc((size_t)r->up * kTaps, sizeof(float));
    if (!r->taps) { free(r); free(row); return NULL; }
    double cutoff = r->up < r->down ? (double)r->up / r->down : 1; // relative to the input's Nyquist
    double peak = bessel0(kKaiserBeta);
    for (uint32_t phase = 0; phase < r->up; phase++) {
        // An output frame at input position q + phase / up takes the input frames q - kHalfTaps + 1 to
        // q + kHalfTaps; tap i is for frame q + i - (kHalfTaps - 1), at distance t from the position.
        double fraction = (double)phase / r->up, sum = 0;
        for (unsigned i = 0; i < kTaps; i++) {
            double t = fraction - ((double)i - (kHalfTaps - 1));
            double x = t / kHalfTaps;
            double window = fabs(x) < 1 ? bessel0(kKaiserBeta * sqrt(1 - x * x)) / peak : 0;
            // At a whole number of cycles the sinc is exactly zero, not sin(pi)'s rounding: the same rate
            // twice is then an exact copy.
            double cycles = cutoff * t;
            double sinc = cycles == 0 ? 1 : cycles == rint(cycles) ? 0 : sin(kPi * cycles) / (kPi * cycles);
            row[i] = cutoff * sinc * window;
            sum += row[i];
        }
        // Unity gain at DC in every phase: the window's ripple would otherwise modulate a tone at the output
        // rate's fraction of the input's.
        for (unsigned i = 0; i < kTaps; i++) r->taps[(size_t)phase * kTaps + i] = (float)(row[i] / sum);
    }
    free(row);
    return r;
}
void SGSingResamplerDestroy(SGSingResampler *r) {
    if (r) { free(r->taps); free(r); }
}
bool SGSingResamplerProcess(const SGSingResampler *r, const float *in, uint32_t inFrames, float *out, uint32_t outFrames) {
    if (!r || !in || !out || !inFrames || !outFrames || (uint64_t)inFrames * r->up != (uint64_t)outFrames * r->down) return false;
    for (uint32_t n = 0; n < outFrames; n++) {
        uint64_t position = (uint64_t)n * r->down; // in 1 / up of an input frame
        uint64_t q = position / r->up;
        const float *taps = r->taps + (size_t)(position % r->up) * kTaps;
        int64_t first = (int64_t)q - (kHalfTaps - 1);
        // Beyond either end of the window there is silence: those taps are skipped. q is below inFrames, so
        // at least kHalfTaps + 1 taps remain.
        unsigned i = first < 0 ? (unsigned)-first : 0;
        unsigned end = first + kTaps > (int64_t)inFrames ? (unsigned)((int64_t)inFrames - first) : kTaps;
        const float *frame = in + (size_t)(first + i) * 2;
        float left = 0, right = 0;
        for (; i < end; i++, frame += 2) {
            left += taps[i] * frame[0];
            right += taps[i] * frame[1];
        }
        out[(size_t)n * 2] = left; out[(size_t)n * 2 + 1] = right;
    }
    return true;
}
