// SPDX-License-Identifier: MIT
#import "SGRTrackAccent.h"

#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "SGRBridges.h"
#import "SGRAccentMath.h"

#include <string.h>

NSNotificationName const SGRTrackAccentDidChangeNotification = @"spotifyglass.redesign.trackAccentDidChange";

@interface SGRAccentWork : NSObject
@property (nonatomic, readonly) CGImageRef image;
@property (nonatomic, copy, readonly) NSString *trackURI;
@property (nonatomic, copy, readonly) NSString *identity;
@property (nonatomic, readonly) NSUInteger generation;
- (instancetype)initWithImage:(CGImageRef)image trackURI:(NSString *)trackURI
                     identity:(NSString *)identity generation:(NSUInteger)generation;
@end

@implementation SGRAccentWork
- (instancetype)initWithImage:(CGImageRef)image trackURI:(NSString *)trackURI
                     identity:(NSString *)identity generation:(NSUInteger)generation {
    if (!(self = [super init])) return nil;
    _image = CGImageRetain(image);
    _trackURI = [trackURI copy];
    _identity = [identity copy];
    _generation = generation;
    return self;
}
- (void)dealloc {
    if (_image) CGImageRelease(_image);
}
@end

@interface SGRTrackAccentCoordinator : NSObject <SGPlayerStateObserver>
+ (instancetype)shared;
- (UIColor *)color;
- (void)refresh;
@end

@implementation SGRTrackAccentCoordinator {
    dispatch_queue_t _processingQueue;
    NSLock *_pendingLock;
    SGRAccentWork *_pendingWork;
    BOOL _workerScheduled;

    NSString *_currentTrackURI;
    NSString *_requestedIdentity;
    NSUInteger _generation;
    BOOL _enabled;
    BOOL _hasColor;
    uint8_t _colorRGBA[4];
}

+ (instancetype)shared {
    static SGRTrackAccentCoordinator *coordinator;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        coordinator = [[self alloc] init];
    });
    return coordinator;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _processingQueue = dispatch_queue_create("spotifyglass.track-accent.processing", DISPATCH_QUEUE_SERIAL);
    _pendingLock = [NSLock new];
    _enabled = SGFlag(SGRKeyTrackAccent, NO);

    // The observer API is weak; the dispatch_once singleton above is its strong owner.
    SGAddPlayerStateObserver(self);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(artworkDidChange:) name:SGRNowPlayingArtworkDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self synchronizeTrackWithState:SGPlayerState()];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    (void)state;
    // Shared player state and the artwork bridge are main-thread-only. Read the latest state, not
    // a possibly delayed state argument, so an old report cannot restore an old track's accent.
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self playerStateDidChange:nil]; });
        return;
    }
    [self synchronizeTrackWithState:SGPlayerState()];
    [self refresh];
}

- (void)artworkDidChange:(NSNotification *)note {
    (void)note;
    [self refresh];
}

- (void)applicationDidBecomeActive:(NSNotification *)note {
    (void)note;
    [self refresh];
}

- (UIColor *)color {
    if (!NSThread.isMainThread) return nil;
    [self synchronizeEnabledState];
    if (!_enabled) return nil;
    [self refresh];
    if (!_hasColor) return nil;
    return [UIColor colorWithRed:(CGFloat)_colorRGBA[0] / 255.0
                           green:(CGFloat)_colorRGBA[1] / 255.0
                            blue:(CGFloat)_colorRGBA[2] / 255.0 alpha:1.0];
}

- (void)refresh {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
        return;
    }
    [self synchronizeEnabledState];
    [self synchronizeTrackWithState:SGPlayerState()];
    if (!_enabled) return;

    SPTPlayerState *state = SGPlayerState();
    NSString *trackURI = SGURIString(state.track.URI);
    if (!trackURI || ![_currentTrackURI isEqualToString:trackURI]) {
        _requestedIdentity = nil;
        return;
    }

    NSString *artworkTrackURI = nil;
    NSString *identity = nil;
    UIImage *image = SGRNowPlayingArtwork(&artworkTrackURI, &identity);
    // Artwork can legitimately lag the player state. Do not ever borrow that prior cover.
    if (!image || !identity.length || ![artworkTrackURI isEqualToString:trackURI] || !image.CGImage) {
        _requestedIdentity = nil;
        return;
    }
    if ([_requestedIdentity isEqualToString:identity]) return;

    CGImageRef cgImage = image.CGImage; // UIImage/image access stays on main; retain in the work item.
    SGRAccentWork *work = [[SGRAccentWork alloc] initWithImage:cgImage trackURI:trackURI
                                                     identity:identity generation:_generation];
    // Claim this identity before notifying: observers may synchronously ask for SGRAccent().
    _requestedIdentity = [identity copy];
    [self publishNoColor]; // Same-track cover replacements must not keep the prior image's colour.
    [_pendingLock lock];
    _pendingWork = work; // Replace a waiting job with the newest artwork (single-slot coalescing).
    BOOL scheduleWorker = !_workerScheduled;
    if (scheduleWorker) _workerScheduled = YES;
    [_pendingLock unlock];
    if (scheduleWorker) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(_processingQueue, ^{
            [weakSelf drainPendingWork];
        });
    }
}

- (void)drainPendingWork {
    while (YES) {
        [_pendingLock lock];
        SGRAccentWork *work = _pendingWork;
        _pendingWork = nil;
        if (!work) {
            _workerScheduled = NO;
            [_pendingLock unlock];
            return;
        }
        [_pendingLock unlock];

        uint8_t rgba[4] = {0, 0, 0, 0};
        BOOL found = [self extractAccentFromImage:work.image rgba:rgba];
        NSData *rgbaData = [NSData dataWithBytes:rgba length:sizeof(rgba)];
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf completeWork:work found:found rgba:rgbaData];
        });
    }
}

- (BOOL)extractAccentFromImage:(CGImageRef)image rgba:(uint8_t[4])rgba {
    if (!image) return NO;
    const size_t imageWidth = CGImageGetWidth(image);
    const size_t imageHeight = CGImageGetHeight(image);
    if (!imageWidth || !imageHeight) return NO;

    enum { side = 40 }; // A true constant, so the bitmap below is a fixed-size array.
    const double scale = MIN((double)side / (double)imageWidth, (double)side / (double)imageHeight);
    const size_t width = MAX((size_t)1, (size_t)((double)imageWidth * scale + 0.5));
    const size_t height = MAX((size_t)1, (size_t)((double)imageHeight * scale + 0.5));
    const size_t bytesPerRow = side * 4;
    uint8_t bitmap[side * side * 4];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) return NO;
    CGContextRef context = CGBitmapContextCreate(bitmap, side, side, 8, bytesPerRow, colorSpace,
                                                  kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (!context) return NO;

    memset(bitmap, 0, sizeof(bitmap));
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    const CGRect destination = CGRectMake((side - width) / 2.0, (side - height) / 2.0, width, height);
    CGContextDrawImage(context, destination, image); // Orientation metadata deliberately ignored.
    const BOOL found = SGRAccentColorFromRGBA(bitmap, side, side, bytesPerRow, rgba) != 0;
    CGContextRelease(context);
    return found;
}

- (void)completeWork:(SGRAccentWork *)work found:(BOOL)found rgba:(NSData *)rgba {
    if (!NSThread.isMainThread) return;
    [self synchronizeEnabledState];
    [self synchronizeTrackWithState:SGPlayerState()];
    if (!_enabled || work.generation != _generation || ![_currentTrackURI isEqualToString:work.trackURI]) return;

    NSString *artworkTrackURI = nil;
    NSString *identity = nil;
    (void)SGRNowPlayingArtwork(&artworkTrackURI, &identity);
    if (![artworkTrackURI isEqualToString:work.trackURI] || ![identity isEqualToString:work.identity]) {
        if ([_requestedIdentity isEqualToString:work.identity]) _requestedIdentity = nil;
        return;
    }

    if (found && rgba.length == 4) [self publishRGBA:rgba.bytes];
    else [self publishNoColor];
}

- (void)synchronizeEnabledState {
    BOOL enabled = SGFlag(SGRKeyTrackAccent, NO);
    if (enabled == _enabled) return;
    _enabled = enabled;
    ++_generation;
    _requestedIdentity = nil;
    if (!enabled) {
        [_pendingLock lock];
        _pendingWork = nil;
        [_pendingLock unlock];
        [self publishNoColor];
    }
}

- (void)synchronizeTrackWithState:(SPTPlayerState *)state {
    NSString *trackURI = SGURIString(state.track.URI);
    BOOL sameTrack = (_currentTrackURI == trackURI) || [_currentTrackURI isEqualToString:trackURI];
    if (sameTrack) return;
    _currentTrackURI = [trackURI copy];
    ++_generation;
    _requestedIdentity = nil;
    [_pendingLock lock];
    _pendingWork = nil;
    [_pendingLock unlock];
    [self publishNoColor]; // Track switches reset synchronously before new artwork is considered.
}

- (void)publishRGBA:(const uint8_t[4])rgba {
    BOOL same = _hasColor && _colorRGBA[0] == rgba[0] && _colorRGBA[1] == rgba[1]
                          && _colorRGBA[2] == rgba[2];
    if (same) return;
    memcpy(_colorRGBA, rgba, sizeof(_colorRGBA));
    _hasColor = YES;
    UIColor *color = [UIColor colorWithRed:(CGFloat)rgba[0] / 255.0
                                     green:(CGFloat)rgba[1] / 255.0
                                      blue:(CGFloat)rgba[2] / 255.0 alpha:1.0];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRTrackAccentDidChangeNotification
                                                       object:color];
}

- (void)publishNoColor {
    if (!_hasColor) return;
    _hasColor = NO;
    memset(_colorRGBA, 0, sizeof(_colorRGBA));
    [NSNotificationCenter.defaultCenter postNotificationName:SGRTrackAccentDidChangeNotification object:nil];
}

@end

UIColor *SGRTrackAccentColor(void) {
    return NSThread.isMainThread ? [[SGRTrackAccentCoordinator shared] color] : nil;
}

void SGRTrackAccentRefresh(void) {
    if (NSThread.isMainThread) [[SGRTrackAccentCoordinator shared] refresh];
    else dispatch_async(dispatch_get_main_queue(), ^{ [[SGRTrackAccentCoordinator shared] refresh]; });
}
