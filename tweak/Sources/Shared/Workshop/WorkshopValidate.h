// SPDX-License-Identifier: MIT
// The Workshop's safety checks as plain C, header-only (the tweak's Makefile compiles .m, .x and .swift only),
// so harness/workshop/validate_test.c runs the very code the page does. Nothing here allocates, reads a file
// or touches the network: each function looks at a string or a number and answers yes or no.
//
// The Workshop installs DATA only: looks, EQ gains, GraphicEQ text. A caller that finds a check failing drops
// the item; there is no "close enough".
#ifndef SG_WORKSHOP_VALIDATE_H
#define SG_WORKSHOP_VALIDATE_H

#include <ctype.h>
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

// Hard caps.
#define SG_WS_MAX_INDEX_BYTES 262144    // 256 KB
#define SG_WS_MAX_FILE_BYTES  524288    // 512 KB
#define SG_WS_MAX_ITEMS       200
#define SG_WS_MAX_BASE_URL    512
#define SG_WS_MAX_GRAPHICEQ_POINTS 512

// Look ranges, as the visualizer's Look file holds them: intensity and motion in PERCENT (the reader divides
// by 100 and the layer holds the result to 0.5...2 and 0.25...2), glowCount 0 (one glow per colour) or 2...4.
#define SG_WS_INTENSITY_MIN 50.0
#define SG_WS_INTENSITY_MAX 200.0
#define SG_WS_MOTION_MIN    25.0
#define SG_WS_MOTION_MAX    200.0
#define SG_WS_MAX_COLOURS   4
// The 15 band equalizer's limit (SGDSPEqualizerGainLimit), and the most a GraphicEQ line may ask for.
#define SG_WS_EQ_BANDS      15
#define SG_WS_EQ_GAIN_LIMIT 12.0
#define SG_WS_GEQ_GAIN_LIMIT 20.0

static inline bool sg_ws_name_char(char c, bool allowDot) {
    return isalnum((unsigned char)c) || c == '-' || c == '_' || (allowDot && c == '.');
}

// An item id: 1...64 of letters, digits, '-' and '_'. No separators, no dots, so no '..'.
static inline bool sg_ws_id_ok(const char *id) {
    if (!id) return false;
    size_t n = strlen(id);
    if (n == 0 || n > 64) return false;
    for (size_t i = 0; i < n; i++) if (!sg_ws_name_char(id[i], false)) return false;
    return true;
}

// An item's file, relative to the catalogue: "name.ext" or "folder/name.ext", at most one folder, each part
// letters, digits, '.', '-', '_', never starting with a dot (so never '..'), no backslash, no escapes, and
// ending in `extension` (".json", ".txt"; compared without case).
static inline bool sg_ws_file_ok(const char *file, const char *extension) {
    if (!file || !extension) return false;
    size_t n = strlen(file), e = strlen(extension);
    if (n == 0 || n > 128 || n <= e || strcasecmp(file + n - e, extension) != 0) return false;
    int slashes = 0;
    size_t partStart = 0;
    for (size_t i = 0; i <= n; i++) {
        if (i == n || file[i] == '/') {
            if (i == partStart || file[partStart] == '.') return false;   // empty part, or hidden / '..'
            if (i < n) slashes++;
            partStart = i + 1;
            continue;
        }
        if (!sg_ws_name_char(file[i], true)) return false;
    }
    if (slashes > 1) return false;
    return strstr(file, "..") == NULL;
}

// An address that may be fetched: "https://" and a host, nothing else a person could be fooled by: no
// spaces or controls, no user info ('@'), no backslash, no fragment. Case of the scheme ignored.
static inline bool sg_ws_https_ok(const char *url) {
    if (!url || strncasecmp(url, "https://", 8) != 0) return false;
    size_t n = strlen(url);
    if (n <= 8 || n > SG_WS_MAX_BASE_URL) return false;
    const char *authorityEnd = url + 8 + strcspn(url + 8, "/?#");
    if (authorityEnd == url + 8) return false;   // no host
    for (const char *p = url; *p; p++) {
        unsigned char c = (unsigned char)*p;
        if (c <= 0x20 || c == 0x7f || c == '\\' || c == '#') return false;
        if (c == '@' && p < authorityEnd) return false;
    }
    return true;
}

// A catalogue's base address: https, no query (item files are appended).
static inline bool sg_ws_base_url_ok(const char *url) {
    return sg_ws_https_ok(url) && strchr(url, '?') == NULL;
}

// A size that fits under a cap and is not empty.
static inline bool sg_ws_size_ok(long long size, long long cap) {
    return size > 0 && size <= cap;
}

// A sha256 as the index writes it: 64 hex digits.
static inline bool sg_ws_sha_ok(const char *hex) {
    if (!hex || strlen(hex) != 64) return false;
    for (int i = 0; i < 64; i++) if (!isxdigit((unsigned char)hex[i])) return false;
    return true;
}

// Whether a digest (32 bytes) is the one the index named.
static inline bool sg_ws_hash_matches(const char *hex, const unsigned char *digest) {
    if (!sg_ws_sha_ok(hex) || !digest) return false;
    static const char digits[] = "0123456789abcdef";
    for (int i = 0; i < 32; i++) {
        if (tolower((unsigned char)hex[i * 2]) != digits[digest[i] >> 4]) return false;
        if (tolower((unsigned char)hex[i * 2 + 1]) != digits[digest[i] & 15]) return false;
    }
    return true;
}

// "#RRGGBB", exactly.
static inline bool sg_ws_colour_ok(const char *colour) {
    if (!colour || strlen(colour) != 7 || colour[0] != '#') return false;
    for (int i = 1; i < 7; i++) if (!isxdigit((unsigned char)colour[i])) return false;
    return true;
}

static inline bool sg_ws_intensity_ok(double v) { return isfinite(v) && v >= SG_WS_INTENSITY_MIN && v <= SG_WS_INTENSITY_MAX; }
static inline bool sg_ws_motion_ok(double v) { return isfinite(v) && v >= SG_WS_MOTION_MIN && v <= SG_WS_MOTION_MAX; }
static inline bool sg_ws_glow_ok(double v) { return v == 0 || v == 2 || v == 3 || v == 4; }
static inline bool sg_ws_gain_ok(double v) { return isfinite(v) && fabs(v) <= SG_WS_EQ_GAIN_LIMIT; }

// A GraphicEQ line in the form SGDSPParseGraphicEq reads ("GraphicEQ: 20 -1.2; 21 -1.1; ..."), held to a
// stricter shape than the parser: "GraphicEQ:", then 2...512 pairs of a frequency (20...20000, rising) and a
// gain (within ±20 dB) separated by ';', nothing else. A trailing ';' and whitespace are fine.
static inline bool sg_ws_graphiceq_ok(const char *text) {
    if (!text || strncasecmp(text, "GraphicEQ:", 10) != 0) return false;
    const char *p = text + 10;
    int count = 0;
    double last = 0;
    for (;;) {
        while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
        if (!*p) break;
        char *end;
        double frequency = strtod(p, &end);
        if (end == p || !isfinite(frequency) || frequency < 20 || frequency > 20000 || frequency <= last) return false;
        p = end;
        while (*p == ' ' || *p == '\t') p++;
        double gain = strtod(p, &end);
        if (end == p || !isfinite(gain) || fabs(gain) > SG_WS_GEQ_GAIN_LIMIT) return false;
        p = end;
        while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
        if (*p == ';') p++;
        else if (*p) return false;
        if (++count > SG_WS_MAX_GRAPHICEQ_POINTS) return false;
        last = frequency;
    }
    return count >= 2;
}

#endif
