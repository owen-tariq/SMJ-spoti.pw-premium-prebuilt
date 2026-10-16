#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
# CC may be e.g. clang or the local Zig compiler's "zig cc" frontend.
for TEST in harness/player-parity/accent_test.c harness/parity-b/levels_test.c harness/parity-b/transitions_test.c; do
    ${CC:-cc} -std=c11 -Wall -Wextra -Werror -pedantic "$TEST" -lm -o "$TMP/test"
    "$TMP/test"
done
sh scripts/check-layers.sh tweak/Sources
git diff --check
python3 harness/player-parity/check_provenance.py
