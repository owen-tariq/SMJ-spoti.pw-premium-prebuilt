// SPDX-License-Identifier: MIT
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../../tweak/Sources/Redesigned/Kit/SGRAccentMath.h"

static void test_solid_red_and_blue(void) {
    const uint8_t red[] = {255, 0, 0, 255};
    const uint8_t blue[] = {0, 0, 255, 255};
    uint8_t result[4] = {0};
    assert(SGRAccentColorFromRGBA(red, 1, 1, 4, result));
    assert(result[0] > result[1] && result[0] > result[2]);
    assert(result[3] == 255 && SGRAccentMathContrast(result[0], result[1], result[2]) >= 4.5);
    assert(SGRAccentColorFromRGBA(blue, 1, 1, 4, result));
    assert(result[2] > result[0] && result[2] > result[1]);
    assert(result[3] == 255 && SGRAccentMathContrast(result[0], result[1], result[2]) >= 4.5);
}

static void test_transparent_pixels_are_ignored(void) {
    /* Premultiplied transparent red occupies most of this row; only one pixel is opaque blue. */
    const uint8_t pixels[] = {
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 255, 255,
    };
    uint8_t result[4] = {0};
    assert(SGRAccentColorFromRGBA(pixels, 5, 1, sizeof(pixels), result));
    assert(result[2] > result[0] && result[2] > result[1]);
}

static void test_gray_uses_manual_fallback(void) {
    const uint8_t gray[] = {128, 128, 128, 255};
    uint8_t result[4] = {0};
    assert(!SGRAccentColorFromRGBA(gray, 1, 1, 4, result));
}

static void test_dark_colors_are_readable(void) {
    const uint8_t darkPurple[] = {24, 8, 36, 255};
    const uint8_t darkBlue[] = {2, 12, 48, 255};
    uint8_t result[4] = {0};
    assert(SGRAccentColorFromRGBA(darkPurple, 1, 1, 4, result));
    assert(SGRAccentMathContrast(result[0], result[1], result[2]) >= 4.5);
    assert(SGRAccentColorFromRGBA(darkBlue, 1, 1, 4, result));
    assert(SGRAccentMathContrast(result[0], result[1], result[2]) >= 4.5);
}

static void test_invalid_dimensions_and_stride(void) {
    const uint8_t pixel[] = {255, 0, 0, 255};
    uint8_t result[4] = {0};
    assert(!SGRAccentColorFromRGBA(pixel, 0, 1, 4, result));
    assert(!SGRAccentColorFromRGBA(pixel, 1, 0, 4, result));
    assert(!SGRAccentColorFromRGBA(pixel, 1, 1, 3, result));
    assert(!SGRAccentColorFromRGBA(NULL, 1, 1, 4, result));
    assert(!SGRAccentColorFromRGBA(pixel, 1, 1, 4, NULL));
    assert(!SGRAccentColorFromRGBA(pixel, 1, SIZE_MAX, 4, result));
    assert(!SGRAccentColorFromRGBA(pixel, SIZE_MAX, 1, SIZE_MAX, result));
}

static void test_padded_row_stride(void) {
    /* A three-pixel row padded to 16 bytes; the padding is not sampled. */
    const uint8_t pixels[16] = {
        255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255,
        0, 255, 0, 255,
    };
    uint8_t result[4] = {0};
    assert(SGRAccentColorFromRGBA(pixels, 3, 1, sizeof(pixels), result));
    assert(result[0] > result[1]);
}

static void test_premultiplied_alpha(void) {
    const uint8_t halfGreen[] = {0, 128, 0, 128};
    uint8_t result[4] = {0};
    assert(SGRAccentColorFromRGBA(halfGreen, 1, 1, 4, result));
    assert(result[1] == 255 && result[0] == 0 && result[2] == 0);
}

static void test_dominant_hue_not_rgb_average(void) {
    const uint8_t redAndBlue[] = {255, 0, 0, 255, 255, 0, 0, 255, 0, 0, 255, 255};
    uint8_t result[4] = {0};
    assert(SGRAccentColorFromRGBA(redAndBlue, 3, 1, 12, result));
    assert(result[0] == 255 && result[2] == 0); // Not a synthetic purple average.
}

static void test_seeded_colour_properties(void) {
    uint32_t seed = 0x53e91u;
    for (unsigned int i = 0; i < 10000; ++i) {
        uint8_t pixel[4];
        for (unsigned int c = 0; c < 3; ++c) {
            seed = seed * 1664525u + 1013904223u;
            pixel[c] = (uint8_t)(seed >> 24);
        }
        pixel[3] = 255;
        uint8_t a[4] = {0}, b[4] = {0};
        int found = SGRAccentColorFromRGBA(pixel, 1, 1, 4, a);
        assert(found == SGRAccentColorFromRGBA(pixel, 1, 1, 4, b));
        assert(memcmp(a, b, sizeof(a)) == 0);
        if (found) {
            assert(a[3] == 255);
            assert(SGRAccentMathContrast(a[0], a[1], a[2]) >= 4.5);
        }
    }
}

int main(void) {
    test_solid_red_and_blue();
    test_transparent_pixels_are_ignored();
    test_gray_uses_manual_fallback();
    test_dark_colors_are_readable();
    test_invalid_dimensions_and_stride();
    test_padded_row_stride();
    test_premultiplied_alpha();
    test_dominant_hue_not_rgb_average();
    test_seeded_colour_properties();
    puts("player-parity accent tests passed");
    return 0;
}
