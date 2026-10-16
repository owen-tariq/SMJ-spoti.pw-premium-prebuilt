// SPDX-License-Identifier: MIT
// The sleep timer's clock (SleepTimer.h): an absolute deadline kept in the settings, a timer set towards it
// and set again whenever the app comes back, the end-of-track watch, and the pause through the player's own
// -pause:, the path the Live Activity's controls take.
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "SleepTimer.h"

NSNotificationName const SGSleepTimerDidChangeNotification = @"spotifyglass.sleepTimer.didChange";

static const double kMinutes[] = {15, 30, 45, 60, 90};
// End of track pauses this close to the end rather than letting the next track start and cut it off.
static const NSInteger kEndOfTrackMs = 500;
// How often the end-of-track watch looks at the position; the deadline timer is set once, with this much give.
static const NSTimeInterval kWatchEvery = 1, kTolerance = 1;
// A deadline this near when the app goes to the background is seen through under a background task, in case
// nothing is playing to keep the process awake (iOS grants about 30 s).
static const NSTimeInterval kBackgroundGuard = 25;
// SGKeySleepTimerTrack holding this means End of track was started before the player had reported a track: the
// first track reported is the one it ends with.
static NSString *const kAnyTrack = @"*";

static NSTimer *sg_timer;
static UIBackgroundTaskIdentifier sg_task = UIBackgroundTaskInvalid;

#define say(format, ...) SGLog(@"sleep timer: " format, ##__VA_ARGS__)

#pragma mark - what is stored

NSArray<NSString *> *SGSleepTimerLengthNames(void) {
    return @[@"15 minutes", @"30 minutes", @"45 minutes", @"60 minutes", @"90 minutes", @"End of track"];
}

SGSleepTimerLength SGSleepTimerLengthChoice(void) {
    NSInteger choice = SGInt(SGKeySleepTimerLength, SGSleepTimerLengthDefault);
    return choice >= SGSleepTimer15 && choice <= SGSleepTimerEndOfTrack ? (SGSleepTimerLength)choice : SGSleepTimerLengthDefault;
}

static CFAbsoluteTime deadline(void) {
    double stored = [NSUserDefaults.standardUserDefaults doubleForKey:SGKeySleepTimerDeadline];
    return isfinite(stored) && stored > 0 ? stored : 0;
}

static NSString *armedTrack(void) {
    NSString *track = [NSUserDefaults.standardUserDefaults stringForKey:SGKeySleepTimerTrack];
    return track.length ? track : nil;
}

static void store(CFAbsoluteTime until, NSString *track) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (until > 0) [defaults setDouble:until forKey:SGKeySleepTimerDeadline];
    else [defaults removeObjectForKey:SGKeySleepTimerDeadline];
    if (track) [defaults setObject:track forKey:SGKeySleepTimerTrack];
    else [defaults removeObjectForKey:SGKeySleepTimerTrack];
}

BOOL SGSleepTimerRunning(void) {
    return deadline() > 0 || armedTrack() != nil;
}

#pragma mark - the clock

static void changed(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGSleepTimerDidChangeNotification object:nil];
}

static void endBackgroundTask(void) {
    if (sg_task == UIBackgroundTaskInvalid) return;
    [UIApplication.sharedApplication endBackgroundTask:sg_task];
    sg_task = UIBackgroundTaskInvalid;
}

static void stopClock(void) {
    [sg_timer invalidate];
    sg_timer = nil;
    endBackgroundTask();
}

// The time is up: the player paused through its own command, as the Live Activity pauses it. Without a
// player to ask (none has reported yet) there is nothing to pause, which is said.
static void fire(NSString *why) {
    stopClock();
    store(0, nil);
    id player = SGKaraokePlayer();
    SPTPlayerState *state = SGPlayerState();
    if (state.isPaused) {
        say(@"%@: already paused", why);
    } else if ([player respondsToSelector:@selector(pause:)]) {
        id result = [(id<SPTPlayer>)player pause:nil];
        say(@"%@: paused -> %@", why, result);
    } else {
        say(@"%@: no player to pause (%@)", why, player ? NSStringFromClass([player class]) : @"none reported yet");
    }
    changed();
}

// End of track: the track the timer was started on has ended (another is playing) or is about to.
static void watchTrack(void) {
    NSString *armed = armedTrack();
    if (!armed) return;
    NSString *current = SGKaraokePlayingTrack();
    if (!current) return;
    if ([armed isEqualToString:kAnyTrack]) {
        store(0, current);
        say(@"end of track: the track is %@", current);
        return;
    }
    if (![current isEqualToString:armed]) {
        fire(@"end of track, the next began");
        return;
    }
    SPTPlayerState *state = SGPlayerState();
    double duration = state.duration;
    NSInteger position = SGKaraokePositionMs();
    if (duration > 0 && position >= 0 && duration * 1000 - position < kEndOfTrackMs) fire(@"end of track");
}

static void deadlineReached(void) {
    if (deadline() > 0 && CFAbsoluteTimeGetCurrent() >= deadline()) fire(@"time up");
}

// The timer towards whatever is stored, from the clock as it stands now: called at launch, on a start, and
// every time the app comes back, since a timer set before the app was suspended may have been held.
static void arm(void) {
    [sg_timer invalidate];
    sg_timer = nil;
    CFAbsoluteTime until = deadline();
    if (until > 0) {
        NSTimeInterval left = until - CFAbsoluteTimeGetCurrent();
        if (left <= 0) {
            fire(@"time up");
            return;
        }
        sg_timer = [NSTimer timerWithTimeInterval:left repeats:NO block:^(NSTimer *timer) { deadlineReached(); }];
        sg_timer.tolerance = kTolerance;
    } else if (armedTrack()) {
        sg_timer = [NSTimer timerWithTimeInterval:kWatchEvery repeats:YES block:^(NSTimer *timer) { watchTrack(); }];
        sg_timer.tolerance = kWatchEvery / 5;
        watchTrack();
    } else {
        endBackgroundTask();
        return;
    }
    // Common modes: the default mode stands still while a list scrolls.
    [NSRunLoop.mainRunLoop addTimer:sg_timer forMode:NSRunLoopCommonModes];
}

void SGSleepTimerStart(void) {
    SGSleepTimerLength choice = SGSleepTimerLengthChoice();
    if (choice == SGSleepTimerEndOfTrack) {
        NSString *track = SGKaraokePlayingTrack();
        store(0, track ?: kAnyTrack);
        say(@"started: end of track %@", track ?: @"(the first reported)");
    } else {
        double minutes = kMinutes[choice];
        store(CFAbsoluteTimeGetCurrent() + minutes * 60, nil);
        say(@"started: %.0f minutes", minutes);
    }
    arm();
    changed();
}

void SGSleepTimerCancel(void) {
    if (!SGSleepTimerRunning()) return;
    stopClock();
    store(0, nil);
    say(@"cancelled");
    changed();
}

NSString *SGSleepTimerStatus(void) {
    if (armedTrack()) return @"End of this track";
    CFAbsoluteTime until = deadline();
    if (until <= 0) return @"Off";
    NSInteger left = (NSInteger)MAX(0, ceil(until - CFAbsoluteTimeGetCurrent()));
    NSInteger hours = left / 3600, minutes = left % 3600 / 60, seconds = left % 60;
    if (hours > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld left", (long)hours, (long)minutes, (long)seconds];
    return [NSString stringWithFormat:@"%ld:%02ld left", (long)minutes, (long)seconds];
}

#pragma mark - the app and the player

// A deadline about to fall as the app leaves the front: a background task sees it through, should nothing be
// playing to keep the process running. A deadline further off waits for the audio to keep the app up, or for
// the app to come back, when arm() looks at the clock again.
static void enteredBackground(void) {
    CFAbsoluteTime until = deadline();
    if (until <= 0 || until - CFAbsoluteTimeGetCurrent() > kBackgroundGuard || sg_task != UIBackgroundTaskInvalid) return;
    sg_task = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"spotifyglass.sleepTimer" expirationHandler:^{
        deadlineReached();
        endBackgroundTask();
    }];
}

@interface SGSleepTimerWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGSleepTimerWatcher

// A second look on every report of the player's: the track changing is what End of track waits for, and a
// deadline the timer was held past (the app suspended) is seen here too.
- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (armedTrack()) watchTrack();
    else deadlineReached();
}

@end

static SGSleepTimerWatcher *sg_watcher;

__attribute__((constructor)) static void sleepTimerAtLaunch(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Whatever was running when Spotify last quit: nothing was playing in between, so a deadline passed
        // and a track waited for are dropped rather than pausing a fresh start.
        if (armedTrack() || (deadline() > 0 && deadline() <= CFAbsoluteTimeGetCurrent())) {
            say(@"the last run's timer (%@) is dropped", SGSleepTimerStatus());
            store(0, nil);
        }
        sg_watcher = [SGSleepTimerWatcher new];
        SGAddPlayerStateObserver(sg_watcher);
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillEnterForegroundNotification]) {
            [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                endBackgroundTask();
                if (SGSleepTimerRunning()) arm();
            }];
        }
        [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            enteredBackground();
        }];
        if (SGSleepTimerRunning()) {
            say(@"a timer from the last run is still ahead: %@", SGSleepTimerStatus());
            arm();
        }
    });
}
