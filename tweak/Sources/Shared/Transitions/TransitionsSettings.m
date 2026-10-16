// SPDX-License-Identifier: MIT
// The Transitions card of the Player page, under either look (App/Pages.m puts it by Vibrations): one
// switch, opening out into its length and softness while on, and a line of what the processor is doing.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Transitions.h"

static NSString *const kTransitionsInfo = @"The first moments of each new track are eased in: the volume rises from a quarter to full and a low-pass opens up, so a skip or a track boundary lands softly rather than cutting in cold.\n\nThis is not a DJ mix. The mod only hears the sound being played, so it cannot overlap two songs or match their beats, and the track ending is not faded.";

static NSArray<NSString *> *softnessNames(void) {
    return @[@"Gentle", @"Medium", @"Strong"];
}

static NSArray<NSString *> *softnessNotes(void) {
    return @[@"The filter opens from 2.5 kHz: a light touch, most of the song heard from the start",
             @"The filter opens from 800 Hz: the entry clearly muffled, then clear",
             @"The filter opens from 300 Hz: only the bass at first, the rest sweeping in"];
}

NSArray<SGModSection *> *SGTransitionsSections(void) {
    SGModRow *transitions = SGOptionRow(@"Transitions", nil, SGKeyTransitions);
    transitions.info = kTransitionsInfo;
    transitions.changed = ^(BOOL on) { SGTransitionsSettingsChanged(); };
    BOOL (^on)(void) = ^BOOL { return SGTransitionsEnabled(); };

    SGModRow *length = SGSliderRow(@"Length", nil, SGTransitionsLengthMin, SGTransitionsLengthMax, SGTransitionsLengthStep,
        ^double { return SGTransitionsLengthMs(); },
        ^(double value) {
            SGSetInt(SGKeyTransitionsLength, lround(value));
            SGTransitionsSettingsChanged();
        },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%ld ms", lround(value)]; });
    length.visible = on;

    SGModRow *softness = SGChoiceRow(@"Softness", nil, SGKeyTransitionsSoftness, softnessNames(), SGTransitionsSoftnessMedium);
    softness.choiceNotes = softnessNotes();
    softness.chosen = ^(NSInteger index) { SGTransitionsSettingsChanged(); };
    softness.visible = on;

    SGModRow *status = SGStatRow(@"Status", ^NSString *{ return SGTransitionsStatus(); });
    status.visible = on;

    return @[SGSection(@"Transitions", @[SGWithSymbol(transitions, @"arrow.left.arrow.right"), length, softness, status])];
}
