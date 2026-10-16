// SPDX-License-Identifier: MIT
// Player redesign: Audio visualizer, the third background. Soft glows in the cover's colours drift over
// the field and swell with the sound Spotify sends to the speaker, read at the pipeline's visualizer
// stage (Shared/Visualizer/SGAudioLevels.h) and drawn by SGRVisualizerLayer (Redesigned/Kit). Opt-in on
// the Player page; Fluid artwork stays the default.
//
// The view sits over the field the way Animated artwork's clip does (PlayerField.x keeps it there), fades
// in once the layer can draw and out when another background is picked, and covers the field while it
// shows so the warp underneath stops. The output is listened to only while this background is picked and
// the player is on screen with the app in front; out of sight the stage passes the audio through and
// nothing is drawn. A paused song lets the glows settle, then holds them still.
//
// The palette is read from the now playing artwork off the main thread: the picture shrunk to a few
// pixels, and up to four colours picked by how saturated and bright they are, each a different hue from
// the last; the field's own colour stands in until one is read and when a cover has too few.
// Threading: main thread only, apart from the palette's read.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRVisualizerLayer.h"
#import "Shared/Visualizer/SGAudioLevels.h"
#import "Player.h"

static const NSTimeInterval kFadeIn = 0.6, kFadeOut = 0.45;
// A buffer older than this without a newer one means the output stopped: the glows hear silence.
static const double kStaleSeconds = 0.25;
// After a pause the glows go on settling this long before they are held still.
static const double kSettleSeconds = 1.2;
// The band levels are RMS values of music, mostly 0.03...0.3; these bring them up to the 0...1 the glows take.
static const float kLowGain = 3.0f, kMidGain = 3.5f, kHighGain = 6.0f, kWholeGain = 2.5f;
enum { kSwatchSide = 12, kMaxColors = 4 };
// A pixel at least this saturated and this bright can be a glow's colour; hues this far apart are two colours.
static const float kMinSaturation = 0.18f, kMinValue = 0.15f, kHueApart = 40;
// Every colour is brought to this value: the layer holds the light under its ceiling, so dark covers glow too.
static const float kGlowValue = 0.9f;

static char kViewKey;

#define say(format, ...) SGLog(@"redesign player: visualizer: " format, ##__VA_ARGS__)

#pragma mark - the view

@interface SGRPlayerVisualizerView : UIView
@property (nonatomic, readonly) SGRVisualizerLayer *glowLayer;
@property (nonatomic, copy) void (^windowChanged)(void);
@end

@implementation SGRPlayerVisualizerView

+ (Class)layerClass {
    return SGRVisualizerLayer.class;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.layer.opacity = 0;
    return self;
}

- (SGRVisualizerLayer *)glowLayer {
    return (SGRVisualizerLayer *)self.layer;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (_windowChanged) _windowChanged();
}

@end

#pragma mark - state

static __weak SGRPlayerVisualizerView *sg_view;
static __weak SGRArtworkField *sg_field;
static BOOL sg_picked;      // read at launch and when the choice changes
static BOOL sg_shown;       // the view is on screen or fading in
static BOOL sg_listening;   // the stage is analysing
static uint64_t sg_lastSequence;
static CFTimeInterval sg_lastHeard, sg_pausedAt;
static NSUInteger sg_paletteGeneration;
static NSArray<UIColor *> *sg_palette;
static UIImage *sg_paletteFor;

static float shownOpacity(CALayer *layer) {
    return ((CALayer *)layer.presentationLayer ?: layer).opacity;
}

static void fade(CALayer *layer, float to, NSTimeInterval duration) {
    float from = shownOpacity(layer);
    layer.opacity = to;
    if (duration <= 0 || fabsf(from - to) < 0.001f) {
        [layer removeAnimationForKey:@"fade"];
        return;
    }
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    animation.fromValue = @(from);
    animation.toValue = @(to);
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer addAnimation:animation forKey:@"fade"];
}

#pragma mark - the levels

static void setShown(BOOL shown, BOOL animated);

static inline float lift(float level, float gain) {
    if (!isfinite(level) || level <= 0) return 0;
    float lifted = sqrtf(level * gain);
    return lifted > 1 ? 1 : lifted;
}

// Whether a paused song has had its time to settle: the glows are then held still, as the field holds the warp.
static BOOL settled(CFTimeInterval now) {
    return sg_pausedAt > 0 && now - sg_pausedAt > kSettleSeconds;
}

// Each frame, before the layer draws: the latest buffer's levels, or silence once none has come for a while.
// The first frame drawn is also when the view fades in: until the shader is ready there is nothing to show.
static void feed(SGRVisualizerLayer *layer) {
    SGAudioLevels read = {0};
    CFTimeInterval now = CACurrentMediaTime();
    BOOL fresh = SGAudioLevelsRead(&read);
    if (fresh && read.sequence != sg_lastSequence) {
        sg_lastSequence = read.sequence;
        sg_lastHeard = now;
    }
    BOOL stale = !fresh || now - sg_lastHeard > kStaleSeconds;
    SGRVisualizerLevels levels = {0};
    if (!stale) {
        levels.low = lift(read.low, kLowGain);
        levels.mid = lift(read.mid, kMidGain);
        levels.high = lift(read.high, kHighGain);
        levels.rms = lift(read.rms, kWholeGain);
    }
    layer.levels = levels;
    if (!sg_shown && sg_picked) setShown(YES, YES);
    // A paused song that has gone quiet (the output stopped, or renders silence) is held once it has settled.
    BOOL quiet = stale || read.rms < 0.001f;
    if (settled(now) && quiet && !layer.paused) {
        layer.paused = YES;
        say(@"held still, the song is paused");
    }
}

#pragma mark - the palette

typedef struct { float r, g, b; } Swatch;

static void hsv(Swatch c, float *h, float *s, float *v) {
    float mx = MAX(c.r, MAX(c.g, c.b)), mn = MIN(c.r, MIN(c.g, c.b)), d = mx - mn;
    *v = mx;
    *s = mx > 0 ? d / mx : 0;
    if (d <= 0) *h = 0;
    else if (mx == c.r) *h = 60 * fmodf((c.g - c.b) / d, 6);
    else if (mx == c.g) *h = 60 * ((c.b - c.r) / d + 2);
    else *h = 60 * ((c.r - c.g) / d + 4);
    if (*h < 0) *h += 360;
}

static float hueDistance(float a, float b) {
    float d = fabsf(a - b);
    return d > 180 ? 360 - d : d;
}

// Off the main thread: up to four colours of the picture, the most saturated and bright first, each a
// hue of its own.
static NSArray<UIColor *> *colorsOf(UIImage *image) {
    CGImageRef picture = image.CGImage;
    if (!picture) return @[];
    uint8_t pixels[kSwatchSide * kSwatchSide * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels, kSwatchSide, kSwatchSide, 8, kSwatchSide * 4, space,
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return @[];
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, kSwatchSide, kSwatchSide), picture);
    CGContextRelease(context);

    enum { kCount = kSwatchSide * kSwatchSide };
    float hues[kCount], scores[kCount];
    Swatch swatches[kCount];
    for (int i = 0; i < kCount; i++) {
        Swatch c = {pixels[i * 4] / 255.0f, pixels[i * 4 + 1] / 255.0f, pixels[i * 4 + 2] / 255.0f};
        float h, s, v;
        hsv(c, &h, &s, &v);
        swatches[i] = c;
        hues[i] = h;
        scores[i] = s >= kMinSaturation && v >= kMinValue ? s * (0.4f + 0.6f * v) : 0;
    }
    NSMutableArray<UIColor *> *colors = [NSMutableArray array];
    float pickedHues[kMaxColors];
    for (int n = 0; n < kMaxColors; n++) {
        int best = -1;
        for (int i = 0; i < kCount; i++) {
            if (scores[i] <= 0 || (best >= 0 && scores[i] <= scores[best])) continue;
            BOOL apart = YES;
            for (int k = 0; apart && k < n; k++) apart = hueDistance(hues[i], pickedHues[k]) >= kHueApart;
            if (apart) best = i;
        }
        if (best < 0) break;
        pickedHues[n] = hues[best];
        Swatch c = swatches[best];
        float mx = MAX(c.r, MAX(c.g, c.b)), scale = mx > 0 ? kGlowValue / mx : 1;
        [colors addObject:[UIColor colorWithRed:MIN(1, c.r * scale) green:MIN(1, c.g * scale) blue:MIN(1, c.b * scale) alpha:1]];
    }
    return colors;
}

static void applyPalette(void) {
    SGRPlayerVisualizerView *view = sg_view;
    if (!view) return;
    NSMutableArray<UIColor *> *colors = [NSMutableArray arrayWithArray:sg_palette ?: @[]];
    UIColor *field = sg_field.fieldColor;
    if (colors.count < 2 && field) {
        // The field's colour, lifted, so a near-grey cover still glows in its own tone.
        CGFloat r = 0, g = 0, b = 0, a = 1;
        if ([field getRed:&r green:&g blue:&b alpha:&a]) {
            CGFloat mx = MAX(r, MAX(g, b)), scale = mx > 0 ? kGlowValue / mx : 1;
            [colors addObject:[UIColor colorWithRed:MIN(1, r * scale) green:MIN(1, g * scale) blue:MIN(1, b * scale) alpha:1]];
        }
    }
    view.glowLayer.colors = colors;
}

static void readPalette(void) {
    UIImage *image = SGRNowPlayingArtwork(NULL, NULL);
    if (!image || image == sg_paletteFor) {
        applyPalette();
        return;
    }
    sg_paletteFor = image;
    NSUInteger generation = ++sg_paletteGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray<UIColor *> *colors = colorsOf(image);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != sg_paletteGeneration) return;
            sg_palette = colors;
            static NSUInteger logged;
            if (logged++ < 3) say(@"%lu colour(s) read from the cover", (unsigned long)colors.count);
            applyPalette();
        });
    });
}

#pragma mark - listening and showing

static void setListening(BOOL listening) {
    if (listening == sg_listening) return;
    sg_listening = listening;
    SGAudioLevelsEnabled(listening);
    if (listening) {
        sg_lastSequence = 0;
        sg_lastHeard = 0;
    }
}

static void setShown(BOOL shown, BOOL animated) {
    SGRPlayerVisualizerView *view = sg_view;
    if (!view) return;
    NSTimeInterval duration = animated && view.window ? (shown ? kFadeIn : kFadeOut) : 0;
    fade(view.layer, shown ? 1 : 0, duration);
    if (shown == sg_shown) return;
    sg_shown = shown;
    sg_field.covered = shown;
    say(@"%@ over the field", shown ? @"fades in" : @"fades out");
}

static void update(void) {
    SGRPlayerVisualizerView *view = sg_view;
    if (!view) {
        setListening(NO);
        return;
    }
    UIApplicationState state = UIApplication.sharedApplication.applicationState;
    BOOL inFront = view.window != nil && state == UIApplicationStateActive;
    setListening(sg_picked && inFront);
    // Fading in waits for the first frame drawn (feed); fading out does not.
    if (!sg_picked || !SGRVisualizerAvailable()) setShown(NO, YES);
    CFTimeInterval now = CACurrentMediaTime();
    BOOL paused = SGPlayerState().isPaused;
    if (paused && sg_pausedAt <= 0) sg_pausedAt = now;
    else if (!paused) sg_pausedAt = 0;
    // Still while the player opens or closes, out of sight, and once a paused song has settled (feed).
    view.glowLayer.paused = !sg_picked || !inFront || SGRPlayerIsTransitioning() || (settled(now) && view.glowLayer.paused);
}

UIView *SGRPlayerVisualizerViewIn(UIView *plane, SGRArtworkField *field) {
    SGRPlayerVisualizerView *view = objc_getAssociatedObject(plane, &kViewKey);
    if (!sg_picked || !SGRVisualizerAvailable()) {
        // Kept until it has faded out to the field.
        if (view && shownOpacity(view.layer) < 0.01f) {
            [view removeFromSuperview];
            objc_setAssociatedObject(plane, &kViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (sg_shown) field.covered = NO;
            sg_shown = NO;
            setListening(NO);
            return nil;
        }
        return view;
    }
    if (!view) {
        view = [[SGRPlayerVisualizerView alloc] initWithFrame:plane.bounds];
        objc_setAssociatedObject(plane, &kViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.windowChanged = ^{ update(); };
        view.glowLayer.willDraw = ^(SGRVisualizerLayer *layer) { feed(layer); };
        say(@"view made in the background plane");
    }
    sg_field = field;
    if (sg_view != view) {
        sg_view = view;
        sg_shown = NO;
        readPalette();
        update();
    }
    if (field.covered != sg_shown) field.covered = sg_shown;
    return view;
}

#pragma mark - the player

@interface SGRPlayerVisualizerWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerVisualizerWatcher

- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (!sg_view) return;
    update();
}

@end

static SGRPlayerVisualizerWatcher *sg_watcher;

%ctor {
    if (!SGRedesignedUI()) return;
    sg_watcher = [SGRPlayerVisualizerWatcher new];
    SGAddPlayerStateObserver(sg_watcher);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    sg_picked = SGRPlayerBackgroundStyle() == SGRPlayerBackgroundVisualizer;
    [center addObserverForName:SGRPlayerBackgroundDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        sg_picked = SGRPlayerBackgroundStyle() == SGRPlayerBackgroundVisualizer;
        say(@"%@", sg_picked ? @"picked" : @"another background picked");
        if (sg_picked) {
            SGRVisualizerPrepare();
            if (!SGAudioLevelsAvailable()) say(@"Spotify's output is not tapped, the glows will hear nothing");
        }
        update();
        // The plane hosts or drops the view on its next layout; asked for now rather than on the next scroll.
        [SGRPlayerField().superview setNeedsLayout];
    }];
    [center addObserverForName:SGRNowPlayingArtworkDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if (sg_view) readPalette();
    }];
    [center addObserverForName:SGRFieldColorDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if (sg_view && note.object == sg_field) applyPalette();
    }];
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      UIApplicationDidEnterBackgroundNotification, UIApplicationWillEnterForegroundNotification]) {
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { update(); }];
    }
    SGRObservePlayerTransition(sg_watcher, ^(id owner) { update(); }, ^(id owner) { update(); });
    if (sg_picked) {
        // The shader compiles off the main thread once the launch has settled, so the first open draws at once.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGRVisualizerPrepare(); });
    }
}
