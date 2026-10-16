// SPDX-License-Identifier: MIT
#import <UIKit/UIKit.h>

#define SGRKeyTrackAccent @"spotifyglass.redesign.accent.followArtwork"

// Main-thread-only, artwork-derived accent. Returns nil when disabled or unavailable.
UIColor *SGRTrackAccentColor(void);
void SGRTrackAccentRefresh(void);
extern NSNotificationName const SGRTrackAccentDidChangeNotification;
