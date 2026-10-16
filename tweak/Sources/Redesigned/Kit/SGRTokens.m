// SPDX-License-Identifier: GPL-3.0-only
// Base file is byte-identical to upstream v0.21.1 (a08b38b); new integration below.
#import <CoreText/SFNTLayoutTypes.h>
#import "Core/SGCore.h"
#import "SGRTokens.h"
#import "SGRAccent.h"
#import "SGRTrackAccent.h"

const CGFloat SGRSideMargin = 16;
const CGFloat SGRGrid = 8;
const CGFloat SGRRadiusArtwork = 12;
const CGFloat SGRRadiusCard = 16;
const CGFloat SGRRadiusCover = 8;
const CGFloat SGRRadiusThumb = 6;
const CGFloat SGRGlassCircleSize = 44;
const CGFloat SGRActionHeight = 48;
const CGFloat SGRActionSpacing = 12;
const CGFloat SGRGlassSpacing = 16;
const NSTimeInterval SGRCrossfade = 0.35;

// A layout spring settles in about this long without overshooting; a press gives a little back.
static const NSTimeInterval kLayoutDuration = 0.45, kPressDuration = 0.32;
static const CGFloat kPressDamping = 0.62;

UIColor *SGRPrimary(void) {
    return UIColor.whiteColor;
}

UIColor *SGRSecondary(void) {
    return [UIColor colorWithWhite:1 alpha:SGRIncreaseContrast() ? 0.80 : 0.65];
}

UIColor *SGRTertiary(void) {
    return [UIColor colorWithWhite:1 alpha:SGRIncreaseContrast() ? 0.60 : 0.40];
}

#pragma mark - accent intensity

// sRGB relative luminance of a colour in 0...1 components (WCAG).
static CGFloat channelLinear(CGFloat c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

static CGFloat luminanceOf(CGFloat r, CGFloat g, CGFloat b) {
    return 0.2126 * channelLinear(r) + 0.7152 * channelLinear(g) + 0.0722 * channelLinear(b);
}

// Contrast against SGRNeutralField, #121212.
static CGFloat contrastOnField(CGFloat r, CGFloat g, CGFloat b) {
    static CGFloat field;
    if (!field) field = luminanceOf(0x12 / 255.0, 0x12 / 255.0, 0x12 / 255.0);
    return (luminanceOf(r, g, b) + 0.05) / (field + 0.05);
}

static void hsbToRGB(CGFloat h, CGFloat s, CGFloat v, CGFloat *r, CGFloat *g, CGFloat *b) {
    CGFloat sector = fmod(h * 6, 6);
    if (sector < 0) sector += 6;
    NSInteger i = (NSInteger)floor(sector);
    CGFloat f = sector - i, p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
    switch (i) {
        case 0: *r = v; *g = t; *b = p; break;
        case 1: *r = q; *g = v; *b = p; break;
        case 2: *r = p; *g = v; *b = t; break;
        case 3: *r = p; *g = q; *b = v; break;
        case 4: *r = t; *g = p; *b = v; break;
        default: *r = v; *g = p; *b = q; break;
    }
}

// The accent with Appearance's intensity applied: saturation and brightness scaled by it in HSB, then
// brought back up to 4.5:1 on the field. Brightness is lifted first (the hue and saturation stay), and when
// it is already full the saturation comes down, which is a blend towards white. At 100% the colour is
// answered as it is, so the intensity row at its default changes nothing anyone chose.
static UIColor *intensified(UIColor *accent) {
    NSInteger percent = MIN(140, MAX(60, SGInt(SGRKeyAccentIntensity, 100)));
    if (percent == 100 || !accent) return accent;
    CGFloat h = 0, s = 0, v = 0, a = 1;
    if (![accent getHue:&h saturation:&s brightness:&v alpha:&a]) return accent;
    CGFloat k = percent / 100.0;
    s = MIN(1, s * k);
    v = MIN(1, v * k);
    CGFloat r, g, b;
    hsbToRGB(h, s, v, &r, &g, &b);
    for (int step = 0; step < 100 && contrastOnField(r, g, b) < 4.5; step++) {
        if (v < 1) v = MIN(1, v + 0.02);
        else if (s > 0) s = MAX(0, s - 0.02);
        else break;
        hsbToRGB(h, s, v, &r, &g, &b);
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

// Read per call: the accent is stored as it is picked, and the colour row reads it the same way.
UIColor *SGRAccent(void) {
    UIColor *accent = SGRTrackAccentColor() ?: SGRAccentColor() ?: [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1];
    return intensified(accent);
}

UIColor *SGRNeutralField(void) {
    return [UIColor colorWithRed:0x12 / 255.0 green:0x12 / 255.0 blue:0x12 / 255.0 alpha:1];
}

UIColor *SGRSolidGlassFill(void) {
    return [UIColor colorWithWhite:1 alpha:0.16];
}

UIColor *SGRHairline(void) {
    return [UIColor colorWithWhite:1 alpha:SGRIncreaseContrast() ? 0.20 : 0.12];
}

UIColor *SGRElevated(UIColor *field) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![field getRed:&r green:&g blue:&b alpha:&a]) return [UIColor colorWithWhite:1 alpha:0.08];
    // 12% towards white keeps a card on a black field clear of the greys SGRAmoled.x turns black.
    CGFloat lift = 0.12;
    return [UIColor colorWithRed:r + (1 - r) * lift green:g + (1 - g) * lift blue:b + (1 - b) * lift alpha:1];
}

UIFont *SGRFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest) {
    UIContentSizeCategory current = UIApplication.sharedApplication.preferredContentSizeCategory;
    if (largest && UIContentSizeCategoryCompareToCategory(current, largest) == NSOrderedDescending) current = largest;
    UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:current];
    CGFloat size = [UIFont preferredFontForTextStyle:style compatibleWithTraitCollection:traits].pointSize;
    return [UIFont systemFontOfSize:size weight:weight];
}

UIFont *SGRMonospacedDigitsFont(UIFont *font) {
    if (!font) return nil;
    NSArray *features = @[@{UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType), UIFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}];
    UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorFeatureSettingsAttribute: features}];
    return [UIFont fontWithDescriptor:descriptor size:font.pointSize];
}

BOOL SGRReduceMotion(void) {
    return UIAccessibilityIsReduceMotionEnabled();
}

BOOL SGRReduceTransparency(void) {
    return UIAccessibilityIsReduceTransparencyEnabled();
}

BOOL SGRIncreaseContrast(void) {
    return UIAccessibilityDarkerSystemColorsEnabled();
}

void SGRAnimate(SGRMotion motion, void (^animations)(void), void (^completion)(BOOL finished)) {
    if (!animations) return;
    if (motion != SGRMotionFade && SGRReduceMotion()) {
        [UIView performWithoutAnimation:animations];
        if (completion) completion(YES);
        return;
    }
    UIViewAnimationOptions options = UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState;
    switch (motion) {
        case SGRMotionLayout:
            [UIView animateWithDuration:kLayoutDuration delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:options animations:animations completion:completion];
            break;
        case SGRMotionPress:
            [UIView animateWithDuration:kPressDuration delay:0 usingSpringWithDamping:kPressDamping initialSpringVelocity:0 options:options animations:animations completion:completion];
            break;
        case SGRMotionFade:
            [UIView animateWithDuration:SGRCrossfade delay:0 options:options | UIViewAnimationOptionCurveEaseInOut animations:animations completion:completion];
            break;
    }
}
