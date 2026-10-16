// SPDX-License-Identifier: MIT
// A background that breathes with the music: two to four soft radial glows in the artwork's colours
// drift slowly over black, each swelling with one band of the sound (the bass, the middle, the top, the
// whole), a faint plasma ripple running through them with the middle, and the whole held under the
// luminance white text reads on, as SGRWarp holds the warped cover. The levels the owner hands in are
// smoothed with an attack and a release so the picture never flickers.
//
// Metal, compiled from source off the main thread the way SGRWarp.m does (its own device and queue; it
// does not touch SGRWarp's); until the shaders are ready, or without Metal, nothing is drawn and the
// owner's colour shows through. Draws at 30 a second on a display link of its own, 15 in Low Power
// Mode, and not at all while paused, hidden, in the background or under Reduce Motion, where one still
// frame is drawn instead. Main thread only.
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>

typedef struct {
    float low, mid, high, rms;   // 0...1, the latest the owner has read
} SGRVisualizerLevels;

// Starts compiling the shaders, if it has not started, so the first layer draws at once.
void SGRVisualizerPrepare(void);
// NO where this device has no Metal, or the shaders failed to compile.
BOOL SGRVisualizerAvailable(void);

@interface SGRVisualizerLayer : CAMetalLayer
// Two to four colours (more are dropped, fewer are filled from the last). Empty draws a neutral glow.
@property (nonatomic, copy) NSArray<UIColor *> *colors;
// Set each frame by the owner, usually from `willDraw`.
@property (nonatomic) SGRVisualizerLevels levels;
// Paused draws a still frame once and then nothing; the owner pauses it out of sight and while the app is
// not in front. Starts paused.
@property (nonatomic) BOOL paused;
// Called on the main thread just before each frame is drawn, so the owner can read the levels in.
@property (nonatomic, copy) void (^willDraw)(SGRVisualizerLayer *layer);
@end
