// SPDX-License-Identifier: MIT
// Transitions (Mod Settings > Player > Transitions): the first moments of each new track eased in, a gain
// ramp from -12 dB up to full and a low-pass that opens from a chosen cutoff to the whole band, so a skip
// or a track boundary lands softly instead of cutting in cold. This is not a DJ mix: the pipeline only ever
// sees the audio being played, so it cannot beat-match or overlap songs, and the outgoing track is not
// faded (SGAudioPipelineSourcePrefix is only answered inside a source pull, which an output stage is not in).
//
//     Transitions.x           the output processor at SGAudioStageTransitions, and the player observer that arms it
//     SGTransitionDSP.h       the ramp and the filter in plain C, shared with harness/parity-b/transitions_test.c
//     TransitionsSettings.m   the Transitions card on the Player page
//
// Everything on the card applies at once, without a restart. Threading: the settings and the observer are
// main thread; the render callback touches only atomics and its own run state.
#import <UIKit/UIKit.h>

#define SGKeyTransitions @"spotifyglass.transitions.enabled"           // off until asked for
#define SGKeyTransitionsLength @"spotifyglass.transitions.lengthMs"
#define SGKeyTransitionsSoftness @"spotifyglass.transitions.softness"   // an SGTransitionsSoftness

enum {
    SGTransitionsLengthMin = 200, SGTransitionsLengthMax = 2000, SGTransitionsLengthDefault = 600, SGTransitionsLengthStep = 50,
};

// How closed the low-pass starts; it always ends fully open.
typedef NS_ENUM(NSInteger, SGTransitionsSoftness) {
    SGTransitionsSoftnessGentle,   // from 2.5 kHz
    SGTransitionsSoftnessMedium,   // from 800 Hz
    SGTransitionsSoftnessStrong,   // from 300 Hz
};

// The settings as stored, within their ranges.
BOOL SGTransitionsEnabled(void);
NSInteger SGTransitionsLengthMs(void);
SGTransitionsSoftness SGTransitionsSoftnessChoice(void);
// From the card: reads the keys again and hands them to the render thread for the next track.
void SGTransitionsSettingsChanged(void);
// A line for the card: what the processor is doing, or why it is not.
NSString *SGTransitionsStatus(void);

@class SGModSection;
// The Transitions card of the Player page, opening out into its settings while its switch is on.
NSArray<SGModSection *> *SGTransitionsSections(void);
