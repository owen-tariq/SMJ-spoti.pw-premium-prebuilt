// SPDX-License-Identifier: MIT
// Runs WorkshopValidate.h, the header the Workshop page uses, over inputs it has to accept and refuse.
// validate_test.py checks the catalogue's files (hashes, sizes, schema); this checks the checks.
//   zig cc -std=c11 -Wall -Wextra -Werror -I../../tweak/Sources/Shared/Workshop validate_test.c -lm -o /tmp/ws && /tmp/ws
#define _DEFAULT_SOURCE
#include <stdio.h>
#include "WorkshopValidate.h"

static int failures;
#define EXPECT(cond) do { bool ok_ = (cond); printf("%s  %s\n", ok_ ? "ok  " : "FAIL", #cond); if (!ok_) failures++; } while (0)

int main(void) {
    // ids
    EXPECT(sg_ws_id_ok("calm-dusk") && sg_ws_id_ok("A_1"));
    EXPECT(!sg_ws_id_ok("") && !sg_ws_id_ok("..") && !sg_ws_id_ok("a/b") && !sg_ws_id_ok("a..b") && !sg_ws_id_ok("a b") && !sg_ws_id_ok(NULL));
    EXPECT(!sg_ws_id_ok("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
    // files
    EXPECT(sg_ws_file_ok("looks/calm-dusk.json", ".json") && sg_ws_file_ok("x.txt", ".txt") && sg_ws_file_ok("a/B.JSON", ".json"));
    EXPECT(!sg_ws_file_ok("../x.json", ".json") && !sg_ws_file_ok("a/../b.json", ".json") && !sg_ws_file_ok("/x.json", ".json"));
    EXPECT(!sg_ws_file_ok("a/b/c.json", ".json") && !sg_ws_file_ok(".x.json", ".json") && !sg_ws_file_ok("a\\b.json", ".json"));
    EXPECT(!sg_ws_file_ok("looks/x.dylib", ".json") && !sg_ws_file_ok("a//b.json", ".json") && !sg_ws_file_ok(".json", ".json"));
    // addresses
    EXPECT(sg_ws_https_ok("https://raw.githubusercontent.com/o/r/crack/workshop/") && sg_ws_https_ok("HTTPS://example.com"));
    EXPECT(!sg_ws_https_ok("http://example.com/") && !sg_ws_https_ok("https://") && !sg_ws_https_ok("https:///x"));
    EXPECT(!sg_ws_https_ok("https://user@evil.com/") && !sg_ws_https_ok("https://a b/") && !sg_ws_https_ok("file:///etc/passwd"));
    EXPECT(sg_ws_https_ok("https://example.com/a@b") && !sg_ws_base_url_ok("https://example.com/?x=1") && sg_ws_base_url_ok("https://example.com/w/"));
    // sizes and hashes
    EXPECT(sg_ws_size_ok(1, SG_WS_MAX_FILE_BYTES) && sg_ws_size_ok(SG_WS_MAX_FILE_BYTES, SG_WS_MAX_FILE_BYTES));
    EXPECT(!sg_ws_size_ok(SG_WS_MAX_FILE_BYTES + 1, SG_WS_MAX_FILE_BYTES) && !sg_ws_size_ok(0, SG_WS_MAX_FILE_BYTES));
    EXPECT(!sg_ws_size_ok(SG_WS_MAX_INDEX_BYTES + 1, SG_WS_MAX_INDEX_BYTES));
    unsigned char digest[32];
    char hex[65];
    for (int i = 0; i < 32; i++) { digest[i] = (unsigned char)(i * 8 + 1); snprintf(hex + i * 2, 3, "%02x", digest[i]); }
    EXPECT(sg_ws_sha_ok(hex) && sg_ws_hash_matches(hex, digest));
    hex[10] = hex[10] == '0' ? '1' : '0';
    EXPECT(!sg_ws_hash_matches(hex, digest));   // wrong hash
    EXPECT(!sg_ws_sha_ok("abc") && !sg_ws_hash_matches("zz", digest));
    // looks
    EXPECT(sg_ws_colour_ok("#00ffAA") && !sg_ws_colour_ok("00ffAA") && !sg_ws_colour_ok("#00ffA") && !sg_ws_colour_ok("#00ffGG") && !sg_ws_colour_ok("red"));
    EXPECT(sg_ws_intensity_ok(50) && sg_ws_intensity_ok(200) && !sg_ws_intensity_ok(49.9) && !sg_ws_intensity_ok(201) && !sg_ws_intensity_ok(NAN));
    EXPECT(sg_ws_motion_ok(25) && sg_ws_motion_ok(200) && !sg_ws_motion_ok(24) && !sg_ws_motion_ok(INFINITY));
    EXPECT(sg_ws_glow_ok(0) && sg_ws_glow_ok(2) && sg_ws_glow_ok(4) && !sg_ws_glow_ok(1) && !sg_ws_glow_ok(5) && !sg_ws_glow_ok(2.5));
    // eq and corrections
    EXPECT(sg_ws_gain_ok(12) && sg_ws_gain_ok(-12) && !sg_ws_gain_ok(12.1) && !sg_ws_gain_ok(NAN));
    EXPECT(sg_ws_graphiceq_ok("GraphicEQ: 20 0; 1000 -1.5; 20000 -7\n") && sg_ws_graphiceq_ok("graphiceq: 20 0;30 1;"));
    EXPECT(!sg_ws_graphiceq_ok("20 0; 30 1") && !sg_ws_graphiceq_ok("GraphicEQ: 20 0") && !sg_ws_graphiceq_ok("GraphicEQ: 30 0; 20 0"));
    EXPECT(!sg_ws_graphiceq_ok("GraphicEQ: 20 0; 30 99") && !sg_ws_graphiceq_ok("GraphicEQ: 20 0; 30 x") && !sg_ws_graphiceq_ok("GraphicEQ: 20 0; 30 1 2"));
    EXPECT(!sg_ws_graphiceq_ok("GraphicEQ: 5 0; 30 1") && !sg_ws_graphiceq_ok("GraphicEQ: 20 0; 30 1; rm -rf"));
    printf(failures ? "%d FAILED\n" : "PASS\n", failures);
    return failures != 0;
}
