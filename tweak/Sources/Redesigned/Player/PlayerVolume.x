// SPDX-License-Identifier: MIT
// Independently implemented device-volume row. Uses Apple's MPVolumeView; no private volume
// setters, entitlement changes, audio interception, or changes to Spotify's own controls.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRTrackAccent.h"
#import "PlayerVolume.h"

static char kVolumeRowKey;
static NSHashTable<UIViewController *> *sg_volumeOwners;

@interface SGRDeviceVolumeRow : UIView
@property (nonatomic, strong) MPVolumeView *volume;
- (void)updateAccent;
@end

@implementation SGRDeviceVolumeRow
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.accessibilityIdentifier = @"player-parity.device-volume";
    // Keep MPVolumeView's own VoiceOver-adjustable volume element accessible, not its wrapper.
    self.isAccessibilityElement = NO;
    UIImageView *quiet = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"speaker.fill"]];
    UIImageView *loud = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"speaker.wave.3.fill"]];
    quiet.isAccessibilityElement = NO;
    loud.isAccessibilityElement = NO;
    quiet.tintColor = loud.tintColor = [UIColor colorWithWhite:1 alpha:0.65];
    quiet.contentMode = loud.contentMode = UIViewContentModeScaleAspectFit;
    _volume = [[MPVolumeView alloc] initWithFrame:CGRectZero];
    _volume.showsRouteButton = NO;
    _volume.showsVolumeSlider = YES;
    _volume.accessibilityLabel = @"This device's output volume";
    _volume.accessibilityHint = @"Does not change volume on another Spotify Connect device";
    for (UIView *view in @[quiet, _volume, loud]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:view];
    }
    // The full 44-point row remains available for the system slider's touch handling.
    [NSLayoutConstraint activateConstraints:@[
        [self.heightAnchor constraintEqualToConstant:44],
        [quiet.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
        [quiet.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [quiet.widthAnchor constraintEqualToConstant:16],
        [quiet.heightAnchor constraintEqualToConstant:16],
        [_volume.leadingAnchor constraintEqualToAnchor:quiet.trailingAnchor constant:12],
        [_volume.trailingAnchor constraintEqualToAnchor:loud.leadingAnchor constant:-12],
        [_volume.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_volume.heightAnchor constraintEqualToConstant:44],
        [loud.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18],
        [loud.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [loud.widthAnchor constraintEqualToConstant:20],
        [loud.heightAnchor constraintEqualToConstant:20],
    ]];
    [self updateAccent];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accentChanged:)
        name:SGRTrackAccentDidChangeNotification object:nil];
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)accentChanged:(NSNotification *)note { (void)note; [self updateAccent]; }
- (void)updateAccent { self.volume.tintColor = SGRAccent(); }
@end

static void removeVolumeRow(UIViewController *owner) {
    SGRDeviceVolumeRow *row = objc_getAssociatedObject(owner, &kVolumeRowKey);
    if (!row) return;
    if ([row.superview isKindOfClass:UIStackView.class]) {
        [(UIStackView *)row.superview removeArrangedSubview:row];
    }
    [row removeFromSuperview];
    objc_setAssociatedObject(owner, &kVolumeRowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Search a bounded subtree as host versions can nest the system control inside wrappers.
// If the tree is unexpectedly large, do not risk adding a duplicate.
static BOOL containsSystemVolume(UIView *view, NSUInteger *remaining) {
    if ([view isKindOfClass:SGRDeviceVolumeRow.class] || view.hidden || view.alpha < 0.01) return NO;
    if (*remaining == 0) return YES;
    --*remaining;
    if ([view isKindOfClass:MPVolumeView.class]) return YES;
    for (UIView *child in view.subviews) if (containsSystemVolume(child, remaining)) return YES;
    return NO;
}

static BOOL hasSystemVolumeRow(UIStackView *stack, UIView *footer) {
    NSUInteger remaining = 256;
    for (UIView *sibling in stack.arrangedSubviews) {
        if (sibling == footer || [sibling isKindOfClass:SGRDeviceVolumeRow.class]) continue;
        if (containsSystemVolume(sibling, &remaining)) return YES;
        UIResponder *controller = sibling.nextResponder;
        NSString *name = NSStringFromClass(controller.class);
        // Do not overlay a Spotify volume unit if the host version already provides one.
        if ([name rangeOfString:@"Volume" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static void updateVolumeRow(UIViewController *owner) {
    UIView *footer = owner.viewIfLoaded;
    if (!footer) return;
    if (!sg_volumeOwners) sg_volumeOwners = [NSHashTable weakObjectsHashTable];
    [sg_volumeOwners addObject:owner];
    if (!SGRedesignedUI() || !SGFlag(SGRKeyPlayerVolume, NO)) {
        removeVolumeRow(owner);
        return;
    }
    UIStackView *stack = (UIStackView *)footer.superview;
    if (![stack isKindOfClass:UIStackView.class] || stack.axis != UILayoutConstraintAxisVertical
        || hasSystemVolumeRow(stack, footer)) {
        removeVolumeRow(owner);
        return;
    }
    NSUInteger index = [stack.arrangedSubviews indexOfObjectIdenticalTo:footer];
    if (index == NSNotFound) { removeVolumeRow(owner); return; }
    SGRDeviceVolumeRow *row = objc_getAssociatedObject(owner, &kVolumeRowKey);
    if (!row) {
        row = [[SGRDeviceVolumeRow alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(owner, &kVolumeRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSUInteger current = [stack.arrangedSubviews indexOfObjectIdenticalTo:row];
    BOOL directlyAbove = current != NSNotFound && current + 1 == index;
    if (row.superview != stack || !directlyAbove) {
        if ([row.superview isKindOfClass:UIStackView.class]) {
            [(UIStackView *)row.superview removeArrangedSubview:row];
        }
        [row removeFromSuperview];
        index = [stack.arrangedSubviews indexOfObjectIdenticalTo:footer];
        if (index != NSNotFound) [stack insertArrangedSubview:row atIndex:index];
    }
    [row updateAccent];
}

void SGRPlayerVolumeRefresh(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGRPlayerVolumeRefresh(); });
        return;
    }
    for (UIViewController *owner in sg_volumeOwners.allObjects) updateVolumeRow(owner);
}

%hook _TtC20NowPlaying_ModesImpl18FooterElementsUnit
- (void)viewDidLayoutSubviews { %orig; updateVolumeRow((UIViewController *)self); }
- (void)viewDidDisappear:(BOOL)animated { %orig; removeVolumeRow((UIViewController *)self); }
%end

%hook _TtC32ReinventFree_ReinventFreeNpvImpl30ReinventFreeFooterElementsUnit
- (void)viewDidLayoutSubviews { %orig; updateVolumeRow((UIViewController *)self); }
- (void)viewDidDisappear:(BOOL)animated { %orig; removeVolumeRow((UIViewController *)self); }
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note; SGRPlayerVolumeRefresh();
        }];
}
