// SPDX-License-Identifier: MIT
#import <Metal/Metal.h>
#import "Core/SGCore.h"
#import "SGRVisualizerLayer.h"
#import "SGRTokens.h"

// Drawable pixels per point: the picture is all soft gradients, so a small drawable scaled up by the
// compositor looks the same and costs a quarter.
static const CGFloat kPixelsPerPoint = 0.5;
// The colour's linear luminance is held under this (less with Increase Contrast), so white text keeps
// better than 5.5:1 over the brightest glow.
static const float kCeiling = 0.13f, kCeilingContrast = 0.07f;
// The shade under the controls: clear down to this share of the height, then this much black at the bottom.
static const float kShadeFrom = 0.45f, kShadeBottom = 0.35f;
static const float kDither = 0.008f;
// How fast a level is followed up and down: quick enough to land on a beat, slow enough never to flicker.
static const double kAttackSeconds = 0.06, kReleaseSeconds = 0.4;
// Frames a second: the glow drifts slowly, so 30 is plenty; Low Power Mode halves it.
static const double kFrameRate = 30, kFrameRateLowPower = 15;
enum { kMaxColors = 4 };

// Up to four glows, one per band (bass, middle, top, the whole), each drifting on a slow orbit of its own
// and swelling with its band; a ripple through them with the middle; the whole held under the ceiling.
static NSString *const kSource = @R"(
#include <metal_stdlib>
using namespace metal;

struct Vertex { float4 position [[position]]; };

vertex Vertex cover(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    return { float4(p * 2 - 1, 0, 1) };
}

struct Frame {
    float width, height, time, low, mid, high, rms, ceiling, shade, shadeFrom, dither, count;
    // Look: intensity scales each band before it swells a glow (motion is applied to `time` by the layer);
    // three spare floats keep `colors` on its 16-byte boundary.
    float intensity, spare0, spare1, spare2;
    float4 colors[4];
};

float hash21(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

fragment half4 glow(Vertex in [[stage_in]], constant Frame &f [[buffer(0)]]) {
    float2 uv = in.position.xy / float2(f.width, f.height);
    float aspect = f.width / max(f.height, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float bands[4] = { f.low, f.mid, f.high, f.rms };
    // Each glow's orbit: radius, two angular speeds and a phase, all slow, none alike.
    const float4 orbit[4] = {
        float4(0.30, 0.050, 0.037, 0.0),
        float4(0.34, -0.041, 0.055, 2.1),
        float4(0.26, 0.063, -0.046, 4.2),
        float4(0.22, -0.035, 0.029, 1.3),
    };
    const float base[4] = { 0.50, 0.42, 0.34, 0.60 };
    int count = clamp(int(f.count), 1, 4);
    float3 acc = float3(0.0);
    for (int i = 0; i < count; i++) {
        // The look's intensity: a louder or quieter swell than the level alone, still held to 0...1.
        float band = clamp(bands[i] * f.intensity, 0.0, 1.0);
        float4 o = orbit[i];
        float2 centre = float2(cos(f.time * o.y + o.w), sin(f.time * o.z + o.w * 0.7)) * o.x;
        float2 d = p - centre;
        float radius = base[i] * (0.7 + 0.7 * band);
        float weight = exp(-dot(d, d) / (radius * radius)) * (0.30 + 1.1 * band);
        acc += f.colors[i].rgb * weight;
    }
    // A quiet floor of the first colour, so the field is never black, and a ripple with the middle.
    acc += f.colors[0].rgb * 0.12;
    float ring = sin(length(p) * 14.0 - f.time * 2.2 + 2.5 * sin(p.x * 3.0 + f.time * 0.6));
    acc *= 1.0 + 0.10 * f.mid * ring;
    acc *= 1.0 - dot(uv - 0.5, uv - 0.5) * 0.35;

    // Held under the ceiling with a soft knee, in light rather than in code values (gamma 2 is near enough).
    float3 light = acc * acc;
    float lum = dot(light, float3(0.2126, 0.7152, 0.0722));
    float knee = f.ceiling * 0.6;
    if (lum > knee) {
        float held = knee + (f.ceiling - knee) * (1.0 - exp(-(lum - knee) / (f.ceiling - knee)));
        acc *= sqrt(held / lum);
    }
    acc *= 1.0 - f.shade * clamp((uv.y - f.shadeFrom) / (1.0 - f.shadeFrom), 0.0, 1.0);
    acc += (hash21(floor(in.position.xy)) - 0.5) * f.dither;
    return half4(half3(clamp(acc, 0.0, 1.0)), 1.0h);
}
)";

// The same layout as the shader's Frame: sixteen floats, then four float4 colours at a 16-byte boundary.
typedef struct __attribute__((aligned(16))) {
    float width, height, time, low, mid, high, rms, ceiling, shade, shadeFrom, dither, count;
    float intensity, spare0, spare1, spare2;
    float colors[kMaxColors * 4];
} SGRVisualizerFrame;

const SGRVisualizerLook SGRVisualizerLookDefault = {1, 1, 0};
// The look's ranges, as the header promises them.
static const float kIntensityMin = 0.5f, kIntensityMax = 2, kMotionMin = 0.25f, kMotionMax = 2;

#pragma mark - the device and the shader, shared by every layer

@interface SGRVisualizerGPU : NSObject
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> queue;
@property (nonatomic, strong) id<MTLRenderPipelineState> glow;
@end

@implementation SGRVisualizerGPU
@end

static SGRVisualizerGPU *sg_gpu;
static BOOL sg_compiling, sg_failed;
static NSHashTable *sg_waiting;

static id<MTLDevice> sharedDevice(void) {
    static id<MTLDevice> device;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ device = MTLCreateSystemDefaultDevice(); });
    return device;
}

BOOL SGRVisualizerAvailable(void) {
    return sharedDevice() != nil && !sg_failed;
}

static void gpuReady(void);

void SGRVisualizerPrepare(void) {
    if (sg_gpu || sg_compiling || sg_failed) return;
    id<MTLDevice> device = sharedDevice();
    if (!device) {
        sg_failed = YES;
        SGLog(@"redesign visualizer: no Metal device, nothing drawn");
        return;
    }
    sg_compiling = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CFTimeInterval began = CACurrentMediaTime();
        NSError *error = nil;
        id<MTLLibrary> library = [device newLibraryWithSource:kSource options:nil error:&error];
        SGRVisualizerGPU *gpu = [SGRVisualizerGPU new];
        gpu.device = device;
        if (library) {
            MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
            descriptor.label = @"glow";
            descriptor.vertexFunction = [library newFunctionWithName:@"cover"];
            descriptor.fragmentFunction = [library newFunctionWithName:@"glow"];
            descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
            gpu.glow = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
        }
        BOOL ok = gpu.glow != nil;
        if (ok) gpu.queue = [device newCommandQueue];
        CFTimeInterval took = CACurrentMediaTime() - began;
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_compiling = NO;
            if (!ok) {
                sg_failed = YES;
                SGLog(@"redesign visualizer: shader failed, nothing drawn: %@", error);
                return;
            }
            sg_gpu = gpu;
            SGLog(@"redesign visualizer: shader ready in %.0f ms on %@", took * 1000, device.name);
            gpuReady();
        });
    });
}

#pragma mark - the layer

static BOOL inBackground(void) {
    return UIApplication.sharedApplication.applicationState == UIApplicationStateBackground;
}

static NSDictionary *noActions(void) {
    static NSDictionary *none;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNull *off = NSNull.null;
        none = @{@"bounds": off, @"position": off, @"frame": off, @"contents": off, @"hidden": off, @"opacity": off};
    });
    return none;
}

// The display link's target, so the link does not keep the layer.
@interface SGRVisualizerTicker : NSObject
@property (nonatomic, weak) SGRVisualizerLayer *layer;
@end

@interface SGRVisualizerLayer ()
- (void)tick:(CADisplayLink *)link;
- (void)catchUp;
@end

@implementation SGRVisualizerTicker
- (void)tick:(CADisplayLink *)link {
    [self.layer tick:link];
}
@end

static void gpuReady(void) {
    for (SGRVisualizerLayer *layer in sg_waiting.allObjects) [layer catchUp];
    [sg_waiting removeAllObjects];
}

// A soft indigo and violet, for a layer given no colours.
static const float kNeutral[2][3] = {{0.33f, 0.28f, 0.72f}, {0.62f, 0.26f, 0.58f}};

@implementation SGRVisualizerLayer {
    CADisplayLink *_link;
    MTLRenderPassDescriptor *_pass;
    float _palette[kMaxColors * 4];
    int _paletteCount;
    SGRVisualizerLevels _shown;   // the levels as smoothed
    double _time;                 // seconds of drift so far
    CFTimeInterval _lastTick, _lastDraw;
    BOOL _dirty, _drawQueued, _watching;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.device = sharedDevice();
    self.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.framebufferOnly = YES;
    self.opaque = YES;
    self.maximumDrawableCount = 2;
    self.actions = noActions();
    self.contentsGravity = kCAGravityResize;
    _paused = YES;
    _look = SGRVisualizerLookDefault;
    _pass = [MTLRenderPassDescriptor renderPassDescriptor];
    _pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    _pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    [self setColors:@[]];
    SGRVisualizerPrepare();
    return self;
}

- (void)dealloc {
    [_link invalidate];
    if (_watching) [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)watch {
    if (_watching) return;
    _watching = YES;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      UIApplicationDidEnterBackgroundNotification, UIApplicationWillEnterForegroundNotification,
                                      NSProcessInfoPowerStateDidChangeNotification, UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [center addObserver:self selector:@selector(conditionsChanged) name:name object:nil];
    }
}

// The power state is reported off the main thread.
- (void)conditionsChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateLink];
        [self changed];
    });
}

- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    CGSize size = CGSizeMake(MAX(1, ceil(bounds.size.width * kPixelsPerPoint)), MAX(1, ceil(bounds.size.height * kPixelsPerPoint)));
    if (CGSizeEqualToSize(size, self.drawableSize)) return;
    self.drawableSize = size;
    [self changed];
}

- (void)setHidden:(BOOL)hidden {
    BOOL was = self.hidden;
    [super setHidden:hidden];
    if (was == hidden) return;
    [self updateLink];
    if (!hidden) [self changed];
}

- (void)setColors:(NSArray<UIColor *> *)colors {
    _colors = [colors copy];
    int count = 0;
    for (UIColor *color in colors) {
        if (count == kMaxColors || ![color isKindOfClass:UIColor.class]) continue;
        CGFloat r = 0, g = 0, b = 0, a = 1;
        if (![color getRed:&r green:&g blue:&b alpha:&a]) {
            CGFloat white = 0;
            if (![color getWhite:&white alpha:&a]) continue;
            r = g = b = white;
        }
        _palette[count * 4] = (float)MAX(0, MIN(1, r));
        _palette[count * 4 + 1] = (float)MAX(0, MIN(1, g));
        _palette[count * 4 + 2] = (float)MAX(0, MIN(1, b));
        _palette[count * 4 + 3] = 1;
        count++;
    }
    if (!count) {
        for (int i = 0; i < 2; i++) {
            for (int k = 0; k < 3; k++) _palette[i * 4 + k] = kNeutral[i][k];
            _palette[i * 4 + 3] = 1;
        }
        count = 2;
    }
    // Fewer than two: the last colour again, so two glows always move.
    while (count < 2) {
        memcpy(&_palette[count * 4], &_palette[(count - 1) * 4], 4 * sizeof(float));
        count++;
    }
    _paletteCount = count;
    // The slots past the colours given take them round again (the third glow of a two-colour cover is the
    // first colour's), for a look asking for more glows than there are colours.
    for (int i = count; i < kMaxColors; i++) memcpy(&_palette[i * 4], &_palette[(i % count) * 4], 4 * sizeof(float));
    [self changed];
}

- (void)setLook:(SGRVisualizerLook)look {
    SGRVisualizerLook held = {
        .intensity = isfinite(look.intensity) ? MAX(kIntensityMin, MIN(kIntensityMax, look.intensity)) : 1,
        .motion = isfinite(look.motion) ? MAX(kMotionMin, MIN(kMotionMax, look.motion)) : 1,
        .glowCount = look.glowCount <= 0 ? 0 : MAX(2, MIN(kMaxColors, look.glowCount)),
    };
    if (held.intensity == _look.intensity && held.motion == _look.motion && held.glowCount == _look.glowCount) return;
    _look = held;
    [self changed];
}

// The glows drawn: the look's count, or one per colour given.
- (int)glowsDrawn {
    return _look.glowCount > 0 ? _look.glowCount : _paletteCount;
}

- (void)setPaused:(BOOL)paused {
    if (paused == _paused) return;
    _paused = paused;
    [self updateLink];
    [self changed];
}

- (BOOL)canDraw {
    CGRect bounds = self.bounds;
    return sg_gpu && !self.hidden && bounds.size.width >= 1 && bounds.size.height >= 1 && !inBackground();
}

- (BOOL)wantsLink {
    return [self canDraw] && !_paused && !SGRReduceMotion();
}

- (double)frameRate {
    return NSProcessInfo.processInfo.lowPowerModeEnabled ? kFrameRateLowPower : kFrameRate;
}

#pragma mark - drawing

// Whatever waited for the GPU: a frame.
- (void)catchUp {
    if (!sg_gpu) {
        if (!sg_waiting) sg_waiting = [NSHashTable weakObjectsHashTable];
        [sg_waiting addObject:self];
        return;
    }
    [self updateLink];
    [self changed];
}

- (void)changed {
    _dirty = YES;
    [self watch];
    if (!sg_gpu) {
        [self catchUp];
        return;
    }
    [self drawSoon];
}

// Changes made together draw once, and not at all while the link draws anyway.
- (void)drawSoon {
    if (_drawQueued || (_link && !_link.paused)) return;
    _drawQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_drawQueued = NO;
        if (self->_dirty) [self drawAt:CACurrentMediaTime() still:YES];
    });
}

- (void)updateLink {
    BOOL wants = [self wantsLink];
    if (wants && !_link) {
        SGRVisualizerTicker *ticker = [SGRVisualizerTicker new];
        ticker.layer = self;
        _link = [CADisplayLink displayLinkWithTarget:ticker selector:@selector(tick:)];
        _link.paused = YES;
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    if (!_link) return;
    // A range reaching 120 never holds the player's 120 Hz transitions down; the tick itself keeps to the
    // rate wanted when the display runs faster for someone else.
    float rate = (float)[self frameRate];
    _link.preferredFrameRateRange = CAFrameRateRangeMake(rate, 120, rate);
    if (_link.paused == !wants) return;
    _link.paused = !wants;
    _lastTick = 0;
    static NSUInteger logged;
    if (logged++ < 12) SGLog(@"redesign visualizer: link %@", wants ? @"runs" : @"stops");
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.targetTimestamp;
    if (now - _lastDraw < 0.9 / [self frameRate]) return;
    // The look's motion: the drift runs faster or slower by scaling the seconds added, never by scaling the
    // clock itself, so a change of pace never jumps the glows.
    if (_lastTick > 0) _time += MIN(now - _lastTick, 0.1) * _look.motion;
    _lastTick = now;
    [self drawAt:now still:NO];
    if (![self wantsLink]) [self updateLink];
}

// A level follows its target quickly up and slowly down, by the time since the last frame.
static float follow(float shown, float wanted, float up, float down) {
    float target = isfinite(wanted) ? MAX(0, MIN(1, wanted)) : 0;
    return shown + (target - shown) * (target > shown ? up : down);
}

- (void)smoothOver:(CFTimeInterval)dt still:(BOOL)still {
    SGRVisualizerLevels target = _levels;
    if (still) {
        // A still frame shows the sound as it is, with no beat to land on.
        _shown.low = follow(0, target.low, 1, 1);
        _shown.mid = follow(0, target.mid, 1, 1);
        _shown.high = follow(0, target.high, 1, 1);
        _shown.rms = follow(0, target.rms, 1, 1);
        return;
    }
    float up = (float)(1 - exp(-dt / kAttackSeconds)), down = (float)(1 - exp(-dt / kReleaseSeconds));
    _shown.low = follow(_shown.low, target.low, up, down);
    _shown.mid = follow(_shown.mid, target.mid, up, down);
    _shown.high = follow(_shown.high, target.high, up, down);
    _shown.rms = follow(_shown.rms, target.rms, up, down);
}

- (void)drawAt:(CFTimeInterval)now still:(BOOL)still {
    SGRVisualizerGPU *gpu = sg_gpu;
    if (![self canDraw]) return;
    if (_willDraw) _willDraw(self);
    [self smoothOver:_lastDraw > 0 ? MIN(now - _lastDraw, 0.1) : 1.0 / kFrameRate still:still];
    _lastDraw = now;
    CGSize size = self.drawableSize;
    @autoreleasepool {
        id<CAMetalDrawable> drawable = [self nextDrawable];
        if (!drawable) return;
        SGRVisualizerFrame frame = {
            .width = (float)size.width,
            .height = (float)size.height,
            .time = (float)_time,
            .low = _shown.low,
            .mid = _shown.mid,
            .high = _shown.high,
            .rms = _shown.rms,
            .ceiling = SGRIncreaseContrast() ? kCeilingContrast : kCeiling,
            .shade = kShadeBottom,
            .shadeFrom = kShadeFrom,
            .dither = kDither,
            .count = (float)[self glowsDrawn],
            .intensity = _look.intensity,
        };
        memcpy(frame.colors, _palette, sizeof frame.colors);
        id<MTLCommandBuffer> buffer = [gpu.queue commandBuffer];
        _pass.colorAttachments[0].texture = drawable.texture;
        id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:_pass];
        [encoder setRenderPipelineState:gpu.glow];
        [encoder setFragmentBytes:&frame length:sizeof frame atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [encoder endEncoding];
        _pass.colorAttachments[0].texture = nil;
        [buffer presentDrawable:drawable];
        [buffer commit];
    }
    _dirty = NO;
}

@end
