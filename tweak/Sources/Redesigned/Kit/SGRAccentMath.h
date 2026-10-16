// SPDX-License-Identifier: MIT
#ifndef SGR_ACCENT_MATH_H
#define SGR_ACCENT_MATH_H

#include <stddef.h>
#include <stdint.h>

/*
 * Select a saturated artwork colour from premultiplied-last RGBA8 pixels. Pixels are
 * unpremultiplied before classification; transparent and near-gray samples are ignored.
 * Rows may be padded (rowBytes >= width * 4). The selected colour is drawn from the
 * dominant quantized hue/saturation/value histogram, then lifted as needed for WCAG
 * 4.5:1 contrast against #121212. Returns zero for invalid input or no chromatic samples.
 *
 * This is intentionally small, allocation-free, deterministic C for both the Kit and
 * the standalone harness. Image orientation is outside this routine's scope.
 */
static inline double SGRAccentMathSRGBLinear(uint8_t channel) {
    double value = (double)channel / 255.0;
    return value <= 0.04045 ? value / 12.92 : __builtin_pow((value + 0.055) / 1.055, 2.4);
}

static inline double SGRAccentMathLuminance(uint8_t r, uint8_t g, uint8_t b) {
    return 0.2126 * SGRAccentMathSRGBLinear(r)
         + 0.7152 * SGRAccentMathSRGBLinear(g)
         + 0.0722 * SGRAccentMathSRGBLinear(b);
}

static inline double SGRAccentMathContrast(uint8_t r, uint8_t g, uint8_t b) {
    const double background = SGRAccentMathLuminance(18, 18, 18);
    const double foreground = SGRAccentMathLuminance(r, g, b);
    return (foreground + 0.05) / (background + 0.05);
}

static inline int SGRAccentMathReadable(uint8_t *r, uint8_t *g, uint8_t *b) {
    if (SGRAccentMathContrast(*r, *g, *b) >= 4.5) return 1;

    /* Binary-search the least blend toward white that meets the contrast threshold. */
    double low = 0.0, high = 1.0;
    for (unsigned int i = 0; i < 18; ++i) {
        double t = (low + high) * 0.5;
        uint8_t rr = (uint8_t)(*r + (255.0 - *r) * t + 0.5);
        uint8_t gg = (uint8_t)(*g + (255.0 - *g) * t + 0.5);
        uint8_t bb = (uint8_t)(*b + (255.0 - *b) * t + 0.5);
        if (SGRAccentMathContrast(rr, gg, bb) >= 4.5) high = t;
        else low = t;
    }
    *r = (uint8_t)(*r + (255.0 - *r) * high + 0.5);
    *g = (uint8_t)(*g + (255.0 - *g) * high + 0.5);
    *b = (uint8_t)(*b + (255.0 - *b) * high + 0.5);
    return SGRAccentMathContrast(*r, *g, *b) >= 4.5;
}

static inline int SGRAccentColorFromRGBA(const uint8_t *pixels,
                                         size_t width,
                                         size_t height,
                                         size_t rowBytes,
                                         uint8_t outRGBA[4]) {
    enum { kHueBins = 16, kSaturationBins = 4, kValueBins = 8, kBucketCount = 512 };
    if (!pixels || !outRGBA || width == 0 || height == 0 || width > SIZE_MAX / 4) return 0;
    const size_t minimumRowBytes = width * 4;
    if (rowBytes < minimumRowBytes || height - 1 > (SIZE_MAX - minimumRowBytes) / rowBytes) return 0;

    uint32_t counts[kBucketCount] = {0};
    uint32_t redSums[kBucketCount] = {0};
    uint32_t greenSums[kBucketCount] = {0};
    uint32_t blueSums[kBucketCount] = {0};

    for (size_t y = 0; y < height; ++y) {
        const uint8_t *row = pixels + y * rowBytes;
        for (size_t x = 0; x < width; ++x) {
            const uint8_t *p = row + x * 4;
            const unsigned int alpha = p[3];
            if (alpha < 16) continue;

            /* Input is premultiplied RGBA8. Unpremultiply with rounding. */
            unsigned int r = ((unsigned int)p[0] * 255u + alpha / 2u) / alpha;
            unsigned int g = ((unsigned int)p[1] * 255u + alpha / 2u) / alpha;
            unsigned int b = ((unsigned int)p[2] * 255u + alpha / 2u) / alpha;
            if (r > 255) r = 255;
            if (g > 255) g = 255;
            if (b > 255) b = 255;

            const unsigned int maximum = r > g ? (r > b ? r : b) : (g > b ? g : b);
            const unsigned int minimum = r < g ? (r < b ? r : b) : (g < b ? g : b);
            const unsigned int chroma = maximum - minimum;
            /* Exclude low-saturation and quantization-noise candidates. */
            if (maximum == 0 || chroma < 24 || chroma * 100u < maximum * 18u) continue;

            double hue;
            if (maximum == r) hue = 60.0 * ((double)g - (double)b) / chroma;
            else if (maximum == g) hue = 60.0 * (2.0 + ((double)b - (double)r) / chroma);
            else hue = 60.0 * (4.0 + ((double)r - (double)g) / chroma);
            if (hue < 0.0) hue += 360.0;
            if (hue >= 360.0) hue -= 360.0;

            unsigned int hueBin = (unsigned int)(hue * kHueBins / 360.0);
            if (hueBin >= kHueBins) hueBin = 0;
            unsigned int saturationBin = (unsigned int)((double)chroma * kSaturationBins / maximum);
            if (saturationBin >= kSaturationBins) saturationBin = kSaturationBins - 1;
            unsigned int valueBin = maximum * kValueBins / 256u;
            if (valueBin >= kValueBins) valueBin = kValueBins - 1;
            const unsigned int bucket = (hueBin * kSaturationBins + saturationBin) * kValueBins + valueBin;
            ++counts[bucket];
            redSums[bucket] += r;
            greenSums[bucket] += g;
            blueSums[bucket] += b;
        }
    }

    unsigned int selected = kBucketCount;
    uint64_t bestScore = 0;
    for (unsigned int i = 0; i < kBucketCount; ++i) {
        if (!counts[i]) continue;
        const unsigned int saturationBin = (i / kValueBins) % kSaturationBins;
        /* A modest saturation weight breaks count ties without discarding a dominant hue. */
        const uint64_t score = (uint64_t)counts[i] * (4u + saturationBin);
        if (score > bestScore) {
            bestScore = score;
            selected = i;
        }
    }
    if (selected == kBucketCount) return 0;

    uint8_t r = (uint8_t)((redSums[selected] + counts[selected] / 2u) / counts[selected]);
    uint8_t g = (uint8_t)((greenSums[selected] + counts[selected] / 2u) / counts[selected]);
    uint8_t b = (uint8_t)((blueSums[selected] + counts[selected] / 2u) / counts[selected]);
    if (!SGRAccentMathReadable(&r, &g, &b)) return 0;
    outRGBA[0] = r;
    outRGBA[1] = g;
    outRGBA[2] = b;
    outRGBA[3] = 255;
    return 1;
}

#endif /* SGR_ACCENT_MATH_H */
