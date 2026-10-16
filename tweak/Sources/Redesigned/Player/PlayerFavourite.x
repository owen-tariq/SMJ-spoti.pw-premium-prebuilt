// SPDX-License-Identifier: MIT
// Player redesign: the add button beside the title drawn as the Music app's favourite star instead of
// Spotify's green disc and checkmark. An outlined star in the secondary colour while the track is not
// saved, a filled star in the accent colour once it is, with a small pop when it changes.
//
// The button stays Spotify's own (id=Components.UI.AddToButton inside the information unit, trees/clean/
// player/01.txt :160): its action, its long-press sheet and its accessibility are untouched. Only what it
// draws goes transparent on every pass, and the star sits over it taking no touches. The saved state is read
// from the button's Encore owner (SGRReadAddTo, Kit/SGRDownload.h), the same read the album and playlist
// headers use; when it cannot be read, Spotify's own button is left exactly as it was.
//
// On by default; Mod Settings > Appearance > "Favourite star in the player" turns it off.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRDownload.h"
#import "Player.h"

static const CGFloat kStarPointSize = 22;
static char kAddKey, kStarKey, kTargetKey;

@interface SGRFavouriteTapWatcher : NSObject
@property (nonatomic, weak) UIView *unitView;
- (void)tapped;
@end

static void refreshStar(UIView *unitView, BOOL animated);

@implementation SGRFavouriteTapWatcher
- (void)tapped {
    // Saving goes through Spotify's collection service and the state arrives a beat later, with no layout
    // pass of its own, so the star is read again a few times rather than guessed.
    __weak UIView *weakView = self.unitView;
    for (NSNumber *delay in @[@0.15, @0.5, @1.2]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *view = weakView;
            if (view) refreshStar(view, YES);
        });
    }
}
@end

static void hideSpotifyGlyph(UIView *button, UIView *star) {
    for (UIView *sub in button.subviews) {
        if (sub == star) continue;
        if (sub.alpha != 0) sub.alpha = 0;
    }
    // A UIButton draws its image and title through its own views as well as its subviews.
    if ([button isKindOfClass:UIButton.class]) {
        UIButton *plain = (UIButton *)button;
        if (plain.imageView.alpha != 0) plain.imageView.alpha = 0;
        if (plain.titleLabel.alpha != 0) plain.titleLabel.alpha = 0;
    }
}

static void showSpotifyGlyph(UIView *button, UIView *star) {
    [star removeFromSuperview];
    for (UIView *sub in button.subviews) sub.alpha = 1;
    if ([button isKindOfClass:UIButton.class]) {
        UIButton *plain = (UIButton *)button;
        plain.imageView.alpha = 1;
        plain.titleLabel.alpha = 1;
    }
}

static void refreshStar(UIView *unitView, BOOL animated) {
    UIView *button = SGRFindByIdentifier(unitView, @"Components.UI.AddToButton", &kAddKey);
    if (!button) return;
    SGRGlyphView *star = objc_getAssociatedObject(button, &kStarKey);
    BOOL added = NO;
    if (!SGEnabled(SGRKeyPlayerFavouriteStar) || !SGRReadAddTo(button, &added)) {
        if (star) {
            showSpotifyGlyph(button, star);
            objc_setAssociatedObject(button, &kStarKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        static BOOL logged;
        if (!logged && SGEnabled(SGRKeyPlayerFavouriteStar)) {
            logged = YES;
            SGLog(@"redesign player: add button state unreadable (%@), Spotify's glyph kept", NSStringFromClass(button.class));
        }
        return;
    }
    if (!star) {
        star = [[SGRGlyphView alloc] initWithSymbol:@"star" pointSize:kStarPointSize weight:UIImageSymbolWeightMedium];
        star.userInteractionEnabled = NO;
        star.isAccessibilityElement = NO;
        star.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                              | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        objc_setAssociatedObject(button, &kStarKey, star, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([button isKindOfClass:UIControl.class] && !objc_getAssociatedObject(button, &kTargetKey)) {
            SGRFavouriteTapWatcher *watcher = [SGRFavouriteTapWatcher new];
            watcher.unitView = unitView;
            [(UIControl *)button addTarget:watcher action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
            // A control holds its targets weakly, so the watcher is kept by the button it watches.
            objc_setAssociatedObject(button, &kTargetKey, watcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        animated = NO;
    }
    if (star.superview != button) [button addSubview:star];
    else if (button.subviews.lastObject != star) [button bringSubviewToFront:star];
    star.center = CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds));
    hideSpotifyGlyph(button, star);

    NSString *symbol = added ? @"star.fill" : @"star";
    BOOL changed = ![star.symbol isEqualToString:symbol];
    UIColor *tint = added ? SGRAccent() : SGRSecondary();
    if (changed) [star setSymbol:symbol animated:animated];
    if (![star.tintColor isEqual:tint]) star.tintColor = tint;
    if (changed && animated && added && !SGRReduceMotion()) {
        // The Music app's star gives a little as it fills.
        star.transform = CGAffineTransformMakeScale(0.7, 0.7);
        SGRAnimate(SGRMotionPress, ^{ star.transform = CGAffineTransformIdentity; }, nil);
    }
}

static void unitLaidOut(UIViewController *unit) {
    UIView *view = unit.viewIfLoaded;
    if (view) refreshStar(view, YES);
}

// PlayerLyrics.x hooks the same method on these classes; Logos chains both, each calling %orig first.
%hook _TtC20NowPlaying_ModesImpl23InformationElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    unitLaidOut((UIViewController *)self);
}
%end

%hook _TtC32ReinventFree_ReinventFreeNpvImpl35ReinventFreeInformationElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    unitLaidOut((UIViewController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    // The tint is read again on every layout pass, so an accent change reaches the star with the next one.
    SGRequireClasses(@[
        @"_TtC20NowPlaying_ModesImpl23InformationElementsUnit",
        @"_TtC32ReinventFree_ReinventFreeNpvImpl35ReinventFreeInformationElementsUnit",
    ]);
}
