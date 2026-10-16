#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
# CC may be e.g. clang or the local Zig compiler's "zig cc" frontend.
${CC:-cc} -std=c11 -Wall -Wextra -Werror -pedantic \
    harness/player-parity/accent_test.c -lm -o "$TMP/accent_test"
"$TMP/accent_test"
sh scripts/check-layers.sh tweak/Sources
git diff --check
python3 harness/player-parity/check_provenance.py
