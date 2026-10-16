#!/bin/sh
# SPDX-License-Identifier: MIT
# Compile/syntax validation of this batch only; not a full tweak or IPA build.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
: "${LOGOS_DIR:?Set LOGOS_DIR to a checkout of https://github.com/theos/logos}"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
# Every .x and .m added or changed by the parity batches, against the base the fork tracks.
BASE=${PARITY_BASE:-8f4342e2f219ed64e4a0bed938f64595c5bd70d1}
FILES=$(git diff --name-only --diff-filter=AM "$BASE" HEAD -- 'tweak/Sources/*.m' 'tweak/Sources/*.x')
for FILE in $FILES; do
    case "$FILE" in
        *.x) perl "$LOGOS_DIR/bin/logos.pl" -c generator=internal "$FILE" > "$TMP/$(basename "$FILE" .x).m"; SRC="$TMP/$(basename "$FILE" .x).m" ;;
        *)   SRC="$FILE" ;;
    esac
    xcrun --sdk iphoneos clang -fsyntax-only -target arm64-apple-ios15.0 \
        -isysroot "$SDK" -fobjc-arc -fblocks -Werror=implicit-function-declaration \
        -Werror=incompatible-pointer-types -Wno-deprecated-declarations \
        -I tweak/Sources -I "$(dirname "$FILE")" "$SRC"
done
printf '%s\n' 'Player parity batch passed iPhoneOS syntax checks (not a device test).'
