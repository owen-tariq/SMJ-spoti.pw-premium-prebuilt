// SPDX-License-Identifier: MIT
// The Sleep timer card of the Player page, under either look (App/Pages.m puts it by Transitions): the length
// to pick, Start or Cancel as the timer stands, and the time left, counted down every second while the page
// is open (SGModPage ticks a row with a value) and at once when the timer starts, stops or fires (refreshOn).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "SleepTimer.h"

NSArray<SGModSection *> *SGSleepTimerSections(void) {
    SGModRow *length = SGChoiceRow(@"Length", nil, SGKeySleepTimerLength, SGSleepTimerLengthNames(), SGSleepTimerLengthDefault);
    length.choiceFooter = @"End of track pauses half a second before the track playing ends, or as the next one begins. "
        "A timer already running keeps its own length; start it again for the new one.";

    SGModRow *start = SGActionRow(@"Start", nil, ^{ SGSleepTimerStart(); });
    start.symbol = @"play.circle";
    start.visible = ^BOOL { return !SGSleepTimerRunning(); };

    SGModRow *cancel = SGActionRow(@"Cancel", nil, ^{ SGSleepTimerCancel(); });
    cancel.symbol = @"xmark.circle";
    cancel.color = SGRed();
    cancel.visible = ^BOOL { return SGSleepTimerRunning(); };

    SGModRow *status = SGStatRow(@"Status", ^NSString *{ return SGSleepTimerStatus(); });
    status.refreshOn = SGSleepTimerDidChangeNotification;

    return @[SGNotedSection(@"Sleep timer", @[SGWithSymbol(length, @"moon.zzz"), start, cancel, status],
                            @"Pauses Spotify's player when the time is up, or just before the track playing ends. "
                             "No fade: Spotify's player gives the mod no hold on its volume (the slider in the player is the system's, which the mod leaves alone), so playback pauses outright. "
                             "The deadline is kept while Spotify is in the background; iOS may run it a few seconds late there, and it is checked again as soon as the app is back.")];
}
