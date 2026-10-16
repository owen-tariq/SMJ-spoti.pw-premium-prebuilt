// SPDX-License-Identifier: MIT
// Sleep timer (Mod Settings > Player > Sleep timer): Spotify's player paused after 15 to 90 minutes, or at the
// end of the track playing, under either look. The deadline is kept as an absolute time in the settings, so a
// timer started before the app was sent to the background, or before Spotify was quit, is still the same
// timer when it comes back: a timer that fires on the main run loop is set towards the deadline and set again
// whenever the app becomes active, and the player's own state reports are a second check on the way. A
// timer whose deadline passed while Spotify was not running is dropped quietly, since nothing was playing.
//
//     SleepTimer.m          the deadline, the timer, the end-of-track watch and the pause
//     SleepTimerSettings.m  the Sleep timer card of the Player page (App/Pages.m puts it by Transitions)
//
// Pausing goes through the player's own -pause: (Headers/SPTPlayer.h), the way the Live Activity's controls
// pause it. There is no fade: Spotify's player exposes no volume to the mod (its slider is the system's, and
// the mod does not change the system volume), so the player is paused outright when the time is up; the
// card says so. Threading: main thread only.
#import <UIKit/UIKit.h>

// The length picked, as the index into SGSleepTimerLengthNames (30 minutes unless set).
#define SGKeySleepTimerLength @"spotifyglass.sleepTimer.length"
// The running timer: the deadline as a CFAbsoluteTime (0 or unset: none), or the base62 id of the track it
// ends with for End of track. Only one of the two is set at a time.
#define SGKeySleepTimerDeadline @"spotifyglass.sleepTimer.deadline"
#define SGKeySleepTimerTrack @"spotifyglass.sleepTimer.track"

typedef NS_ENUM(NSInteger, SGSleepTimerLength) {
    SGSleepTimer15, SGSleepTimer30, SGSleepTimer45, SGSleepTimer60, SGSleepTimer90,
    SGSleepTimerEndOfTrack,
};
enum { SGSleepTimerLengthDefault = SGSleepTimer30 };
NSArray<NSString *> *SGSleepTimerLengthNames(void);
SGSleepTimerLength SGSleepTimerLengthChoice(void);

// Starts a timer of the length picked (replacing one running); cancels the one running.
void SGSleepTimerStart(void);
void SGSleepTimerCancel(void);
BOOL SGSleepTimerRunning(void);
// A line for the card: the time left, "End of this track", or "Off".
NSString *SGSleepTimerStatus(void);
// Posted (main queue) when the timer starts, is cancelled or fires.
extern NSNotificationName const SGSleepTimerDidChangeNotification;

@class SGModSection;
// The Sleep timer card of the Player page.
NSArray<SGModSection *> *SGSleepTimerSections(void);
