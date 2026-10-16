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
perl "$LOGOS_DIR/bin/logos.pl" -c generator=internal \
    tweak/Sources/Redesigned/Player/PlayerVolume.x > "$TMP/PlayerVolume.m"
for FILE in \
    tweak/Sources/Redesigned/Kit/SGRTrackAccent.m \
    tweak/Sources/Redesigned/Kit/SGRTokens.m \
    tweak/Sources/Redesigned/Kit/SGRAppearanceSettings.m \
    "$TMP/PlayerVolume.m"
do
    xcrun --sdk iphoneos clang -fsyntax-only -target arm64-apple-ios15.0 \
        -isysroot "$SDK" -fobjc-arc -fblocks -Werror=implicit-function-declaration \
        -Werror=incompatible-pointer-types -Wno-deprecated-declarations \
        -I tweak/Sources -I tweak/Sources/Redesigned/Player "$FILE"
done
printf '%s\n' 'Player parity batch passed iPhoneOS syntax checks (not a device test).'
