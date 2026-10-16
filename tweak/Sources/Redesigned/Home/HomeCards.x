// Home redesign: every card Home keeps is the same Encore button, told apart where it lays out:
//   id=Shortcut.Card.Home          a shortcut tile 181x48 r=4 that clips, in a ConfigurableUIEventObservingView
//                                  r=4 (trees/clean/home/01.txt:36-37): the cover radius, continuous, and its
//                                  picture run across it (HomeTiles.m)
//   id=Components.UI.HomeCard      a shelf card, its picture Encore.ImageView 149x149 > UIImageView with no radius
//                                  of its own (10.txt:2280-2286): cut at the cover radius, continuous, over the
//                                  4pt Spotify bakes into the picture (an artist's round one sits inside it)
//   in Discovery_MediumDensityCardKit.DJMDCView   the DJ card 370x192 r=8 that clips (01.txt:477-478): the card
//                                  radius, and without the transcript Spotify's DJ talks through
//                                  (Discovery_MediumDensityCardKit.TranscriptView, :500) or the Beta badge (:503)
//
// The DJ card in the redesigned player's look (SGRKeyHomeDJPlayerLook, off until asked for): the same card, with
// the redesigned player's parts around what it draws. An artwork field (Kit/SGRField.h: the colour of the
// card's own picture, or of the playing track's artwork until the card has one, fading to black down the
// card) is its bottom-most subview, the card's own fill is cleared so the field shows, its corners stay the
// card radius, and a glass shape (Kit/SGRGlass.h) goes inside its round control the way PlayerHeader.x puts
// one behind the header's buttons -- inside the control, under what it draws, taking no touches, so the
// control's action, state and accessibility stay Spotify's. Nothing is moved and nothing of Spotify's
// is hidden beyond what calmDJ already hides. Each part is found by shape rather than by a class name
// (no tree of the card's insides is recorded here): a part not found is left alone and logged once.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

// Below this a card's picture is a glyph or a placeholder, not a cover.
static const CGFloat kCoverMinWidth = 80;

static char kImageKey, kFieldKey, kGlassKey;

static void roundCorners(UIView *view, CGFloat radius) {
    CALayer *layer = view.layer;
    if (layer.cornerRadius != radius) layer.cornerRadius = radius;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
}

static void roundCover(UIView *card) {
    UIView *holder = SGRFindByIdentifier(card, @"Encore.ImageView", &kImageKey);
    if (holder.bounds.size.width < kCoverMinWidth) return;
    for (UIView *sub in holder.subviews) {
        if (![sub isKindOfClass:UIImageView.class]) continue;
        roundCorners(sub, SGRRadiusCover);
        if (!sub.layer.masksToBounds) sub.layer.masksToBounds = YES;
    }
}

// The transcript's own labels are plain UILabels the Kit keeps transparent; the Swift views around them
// take their alpha again on every pass.
static void calmDJ(UIView *card) {
    for (UIView *sub in card.subviews) {
        NSString *name = NSStringFromClass(sub.class);
        if (![name containsString:@"TranscriptView"] && ![name containsString:@"BetaBadge"]) continue;
        if (sub.alpha != 0) sub.alpha = 0;
        sub.accessibilityElementsHidden = YES;
        SGForEachView(sub, ^(UIView *v) {
            if ([v isKindOfClass:UILabel.class]) SGRSuppress(v);
        });
    }
}

#pragma mark - the DJ card in the player's look

static void logDJOnce(NSString *what) {
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    if ([logged containsObject:what]) return;
    [logged addObject:what];
    SGLog(@"redesign home: DJ card, %@", what);
}

// The card's own picture: the widest image view in it showing a cover-sized image. nil when it has none.
static UIImage *djPicture(UIView *card) {
    __block UIImageView *best = nil;
    SGForEachView(card, ^(UIView *v) {
        if (![v isKindOfClass:UIImageView.class] || v.bounds.size.width < kCoverMinWidth) return;
        UIImageView *view = (UIImageView *)v;
        if (!view.image || view.image.CGImage == NULL) return;
        if (!best || view.bounds.size.width > best.bounds.size.width) best = view;
    });
    return best.image;
}

// The card's round control (its Play): the first control under the card, the card itself aside, sized like a
// button rather than a card or a badge. nil when none is.
static UIControl *djControl(UIView *card) {
    __block UIControl *found = nil;
    SGForEachView(card, ^(UIView *v) {
        if (found || v == card || ![v isKindOfClass:UIControl.class]) return;
        CGSize size = v.bounds.size;
        if (size.width < 28 || size.height < 28 || size.height > 72 || size.width > 200) return;
        found = (UIControl *)v;
    });
    return found;
}

static SGRArtworkField *djFieldIn(UIView *card) {
    SGRArtworkField *field = objc_getAssociatedObject(card, &kFieldKey);
    if (!field) {
        field = [[SGRArtworkField alloc] initWithFrame:card.bounds];
        field.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        // The card's own layer clips; the field never does, so it takes the card's corners on its own layer too.
        field.layer.masksToBounds = YES;
        objc_setAssociatedObject(card, &kFieldKey, field, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (field.superview != card || card.subviews.firstObject != field) [card insertSubview:field atIndex:0];
    if (!CGRectEqualToRect(field.frame, card.bounds)) field.frame = card.bounds;
    roundCorners(field, SGRRadiusCard);
    return field;
}

// Spotify's paint the field would be hidden behind: the card's own background, and a plain view over the whole
// of it right above the field (the fill, as a shortcut tile has one). Cleared on every pass, since Spotify
// sets it again on reuse.
static void clearDJPaint(UIView *card, UIView *field) {
    if (card.backgroundColor && !CGColorEqualToColor(card.backgroundColor.CGColor, UIColor.clearColor.CGColor)) card.backgroundColor = UIColor.clearColor;
    NSArray<UIView *> *subviews = card.subviews;
    UIView *next = subviews.count > 1 && subviews.firstObject == field ? subviews[1] : nil;
    if (next && object_getClass(next) == UIView.class && CGRectEqualToRect(next.frame, card.bounds) && next.backgroundColor) {
        if (!CGColorEqualToColor(next.backgroundColor.CGColor, UIColor.clearColor.CGColor)) next.backgroundColor = UIColor.clearColor;
    }
}

static void dressDJ(UIView *card) {
    if (card.bounds.size.width < kCoverMinWidth || card.bounds.size.height < kCoverMinWidth) return;
    SGRArtworkField *field = djFieldIn(card);
    clearDJPaint(card, field);
    UIImage *picture = djPicture(card);
    UIImage *artwork = picture ?: SGRNowPlayingArtwork(NULL, NULL);
    // The same image again is a no-op in the field; nil keeps what it shows (the neutral field until one lands).
    if (artwork) [field setArtwork:artwork identity:nil animated:YES];
    logDJOnce(picture ? @"field from the card's own picture" : artwork ? @"field from the playing track's artwork" : @"field neutral, no picture yet");

    UIControl *control = djControl(card);
    if (!control) {
        logDJOnce(@"no round control found, left as Spotify's");
        return;
    }
    CGSize size = control.bounds.size;
    if (size.width > size.height + 4) SGRGlassCapsuleInside(control, &kGlassKey, size, NO);
    else SGRGlassInside(control, &kGlassKey, MIN(size.width, size.height));
    logDJOnce([NSString stringWithFormat:@"glass inside %@ %@ %.0fx%.0f", NSStringFromClass(control.class),
               control.accessibilityIdentifier ?: @"(no id)", size.width, size.height]);
}

static void style(UIView *button) {
    NSString *identifier = button.accessibilityIdentifier;
    if ([identifier isEqualToString:@"Shortcut.Card.Home"]) {
        roundCorners(button, SGRRadiusCover);
        if (button.superview.layer.cornerRadius > 0) roundCorners(button.superview, SGRRadiusCover);
        SGRHomeStyleTile(button);
        return;
    }
    if ([identifier isEqualToString:@"Components.UI.HomeCard"]) {
        roundCover(button);
        return;
    }
    static Class dj;
    if (!dj) dj = NSClassFromString(@"_TtC30Discovery_MediumDensityCardKit9DJMDCView");
    if (dj && [button.superview isKindOfClass:dj]) {
        roundCorners(button, SGRRadiusCard);
        calmDJ(button);
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign home: DJ card at the card radius, transcript gone"); });
        if (SGFlag(SGRKeyHomeDJPlayerLook, NO)) {
            dressDJ(button);
        } else {
            // Switched off again: the field goes, the paint it cleared comes back on Spotify's next pass.
            UIView *field = objc_getAssociatedObject(button, &kFieldKey);
            if (field.superview) [field removeFromSuperview];
        }
    }
}

%hook _TtC19LegacyUI_ECMCoreKit31InteractableLayoutBackingButton
- (void)layoutSubviews {
    %orig;
    CFTimeInterval began = SGRHomeProbeBegin();
    style((UIView *)self);
    SGRHomeProbeEnd(SGRHomeProbeCards, began);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC19LegacyUI_ECMCoreKit31InteractableLayoutBackingButton",
        @"_TtC30Discovery_MediumDensityCardKit9DJMDCView",
    ]);
}
