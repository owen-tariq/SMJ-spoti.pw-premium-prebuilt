#import "Core/SGCore.h"
#import "SGRGlass.h"
#import "SGRTokens.h"

typedef NS_ENUM(NSInteger, SGRGlassMode) {
    SGRGlassModeGlass,
    SGRGlassModeBlur,
    SGRGlassModeSolid,
};

static SGRGlassMode glassMode(void) {
    if (SGRReduceTransparency()) return SGRGlassModeSolid;
    return SGRGlassModeBlur;
}

#pragma mark - strength (Appearance's Glass strength slider)

CGFloat SGRGlassStrength(void) {
    NSInteger percent = SGInt(SGRKeyGlassStrength, 100);
    return MIN(150, MAX(50, percent)) / 100.0;
}

// A solid shape's fill (Reduce Transparency), its alpha scaled by the strength.
static UIColor *solidFill(BOOL prominent) {
    CGFloat alpha = 0, r = 0, g = 0, b = 0;
    [SGRSolidGlassFill() getRed:&r green:&g blue:&b alpha:&alpha];
    if (prominent) alpha = 0.26;
    return [UIColor colorWithRed:r green:g blue:b alpha:MIN(1, alpha * SGRGlassStrength())];
}

static char kStrengthFilmKey;

// HOOK POINT -- Glass strength. Every shape passes through here on every pass it is laid out, after its
// material, size and films are set. UIKit gives no handle on a material's blur radius or its own tint, so
// the strength works on what it can: under 100% the shape's alpha goes down with it (the material thins and
// what is behind shows more; a visual effect view under alpha 1 renders, if not the way Apple recommends),
// over 100% a black film inside the material deepens it, up to 25% at 150%. A solid shape (Reduce
// Transparency) gets its fill's alpha scaled instead, in solidFill above. To change how strength reads,
// change this function alone.
static void applyStrength(UIView *shape, SGRGlassMode mode) {
    CGFloat strength = SGRGlassStrength();
    CGFloat alpha = mode == SGRGlassModeSolid ? 1 : MIN(1, strength);
    if (shape.alpha != alpha) shape.alpha = alpha;
    UIView *film = objc_getAssociatedObject(shape, &kStrengthFilmKey);
    CGFloat deepen = mode == SGRGlassModeSolid ? 0 : MAX(0, strength - 1) * 0.5;
    if (deepen <= 0) {
        film.hidden = YES;
        return;
    }
    UIView *content = [shape isKindOfClass:UIVisualEffectView.class] ? ((UIVisualEffectView *)shape).contentView : shape;
    if (!film) {
        film = [UIView new];
        film.userInteractionEnabled = NO;
        film.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(shape, &kStrengthFilmKey, film, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    film.hidden = NO;
    UIColor *color = [UIColor colorWithWhite:0 alpha:deepen];
    if (![film.backgroundColor isEqual:color]) film.backgroundColor = color;
    // Under any film the shape carries, so a prominent film still reads a step brighter.
    if (film.superview != content) [content insertSubview:film atIndex:0];
    if (!CGRectEqualToRect(film.frame, content.bounds)) film.frame = content.bounds;
    if (film.layer.cornerRadius != shape.layer.cornerRadius) {
        film.layer.cornerRadius = shape.layer.cornerRadius;
        film.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

static UIView *newShape(SGRGlassMode mode) {
    UIView *shape;
    switch (mode) {
        case SGRGlassModeGlass:
            shape = [[UIVisualEffectView alloc] initWithEffect:SGGlassEffect()];
            break;
        case SGRGlassModeBlur:
            shape = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
            break;
        case SGRGlassModeSolid:
            shape = [UIView new];
            shape.backgroundColor = solidFill(NO);
            break;
    }
    shape.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    shape.userInteractionEnabled = NO;
    return shape;
}

#pragma mark - inside a control

static char kInsideModeKey, kFilmKey;

// The film that makes a shape prominent, inside the effect's own content view so the corners clip it.
static void keepFilm(UIView *shape, BOOL prominent, SGRGlassMode mode) {
    if (mode == SGRGlassModeSolid) {
        UIColor *fill = solidFill(prominent);
        if (![shape.backgroundColor isEqual:fill]) shape.backgroundColor = fill;
        return;
    }
    UIView *film = objc_getAssociatedObject(shape, &kFilmKey);
    if (!prominent) {
        film.hidden = YES;
        return;
    }
    UIView *content = [shape isKindOfClass:UIVisualEffectView.class] ? ((UIVisualEffectView *)shape).contentView : shape;
    if (!film) {
        film = [UIView new];
        film.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
        film.userInteractionEnabled = NO;
        film.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(shape, &kFilmKey, film, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    film.hidden = NO;
    if (film.superview != content) [content addSubview:film];
    // The effect's content view does not clip, so the film carries the shape's corners itself; square ones
    // drew a lighter rectangle around the playlist's Play capsule (harness, 2026-09-17).
    if (!CGRectEqualToRect(film.frame, content.bounds)) {
        film.frame = content.bounds;
        film.layer.cornerRadius = MIN(content.bounds.size.width, content.bounds.size.height) / 2;
        film.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

static UIView *glassInside(UIView *control, const void *key, CGSize size, BOOL capsule, BOOL prominent) {
    if (!control || !key) return nil;
    SGRGlassMode mode = glassMode();
    UIView *shape = objc_getAssociatedObject(control, key);
    if (shape && [objc_getAssociatedObject(shape, &kInsideModeKey) integerValue] != mode) {
        [shape removeFromSuperview];
        shape = nil;
    }
    if (!shape) {
        shape = newShape(mode);
        shape.accessibilityElementsHidden = YES;
        shape.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                               | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        objc_setAssociatedObject(shape, &kInsideModeKey, @(mode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(control, key, shape, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (shape.superview != control) [control addSubview:shape];
    // First among the control's subviews, so the glyph the control draws is genuinely after the shape in the
    // tree. The shape used to be added last and pushed back with zPosition -1 instead, which sorts the
    // compositing but not what glass takes for its backdrop: on the phone the glyph above it was captured
    // into it, so the button showed a soft ghost of its icon through the glass and no icon over it
    // (issue #39, iOS 26.1). The simulator's glass does not refract and shows neither order failing, so this
    // one is ordered the plain way rather than by depth. Re-asserted on every pass the caller makes, since a
    // control that rebuilds its content puts that in at index 0 too and would end up under the shape.
    if (control.subviews.firstObject != shape) [control insertSubview:shape atIndex:0];
    shape.hidden = size.width <= 0 || size.height <= 0;
    CGRect bounds = CGRectMake(0, 0, size.width, size.height);
    if (!CGRectEqualToRect(shape.bounds, bounds)) {
        shape.bounds = bounds;
        SGShapeGlass(shape, MIN(size.width, size.height) / 2, capsule);
    }
    keepFilm(shape, prominent, mode);
    applyStrength(shape, mode);
    CGPoint middle = CGPointMake(CGRectGetMidX(control.bounds), CGRectGetMidY(control.bounds));
    if (!CGPointEqualToPoint(shape.center, middle)) shape.center = middle;
    return shape;
}

UIView *SGRGlassInside(UIView *control, const void *key, CGFloat side) {
    return glassInside(control, key, CGSizeMake(side, side), YES, NO);
}

UIView *SGRGlassCapsuleInside(UIView *control, const void *key, CGSize size, BOOL prominent) {
    return glassInside(control, key, size, YES, prominent);
}

#pragma mark - a plate over a host

static char kPlateModeKey, kTintFilmKey;

// How much of the tint lies over the material: enough to read as the cover's colour, little enough that the
// material still shows through. The tint itself is one SGRPalette made for white text (its luminance is held
// near the surface's), so white over the film keeps its contrast at any strength.
static const CGFloat kTintFilmAlpha = 0.6;

UIView *SGRGlassPlateIn(UIView *host, const void *key, UIView *above, CGFloat radius, UIColor *tint) {
    if (!host || !key) return nil;
    SGRGlassMode mode = glassMode();
    UIView *plate = objc_getAssociatedObject(host, key);
    if (plate && [objc_getAssociatedObject(plate, &kPlateModeKey) integerValue] != mode) {
        [plate removeFromSuperview];
        plate = nil;
    }
    if (!plate) {
        plate = newShape(mode);
        plate.accessibilityElementsHidden = YES;
        plate.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(plate, &kPlateModeKey, @(mode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(host, key, plate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Just above the host's fill, or first: re-asserted on every pass, as inside a control.
    NSArray<UIView *> *subviews = host.subviews;
    if (above && above.superview == host) {
        NSUInteger at = [subviews indexOfObjectIdenticalTo:above];
        BOOL placed = plate.superview == host && at + 1 < subviews.count && subviews[at + 1] == plate;
        if (!placed) [host insertSubview:plate aboveSubview:above];
    } else if (plate.superview != host || subviews.firstObject != plate) {
        [host insertSubview:plate atIndex:0];
    }
    if (plate.hidden) plate.hidden = NO;
    if (!CGRectEqualToRect(plate.frame, host.bounds) || plate.layer.cornerRadius != radius) {
        plate.frame = host.bounds;
        SGShapeGlass(plate, radius, NO);
    }
    if (mode == SGRGlassModeSolid) {
        UIColor *fill = tint ?: solidFill(NO);
        if (![plate.backgroundColor isEqual:fill]) plate.backgroundColor = fill;
    } else {
        UIView *content = ((UIVisualEffectView *)plate).contentView;
        UIView *film = objc_getAssociatedObject(plate, &kTintFilmKey);
        if (!film) {
            film = [UIView new];
            film.userInteractionEnabled = NO;
            film.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            objc_setAssociatedObject(plate, &kTintFilmKey, film, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (film.superview != content) [content addSubview:film];
        if (!CGRectEqualToRect(film.frame, content.bounds)) film.frame = content.bounds;
        UIColor *color = tint ? [tint colorWithAlphaComponent:kTintFilmAlpha] : UIColor.clearColor;
        if (![film.backgroundColor isEqual:color]) film.backgroundColor = color;
    }
    applyStrength(plate, mode);
    return plate;
}
