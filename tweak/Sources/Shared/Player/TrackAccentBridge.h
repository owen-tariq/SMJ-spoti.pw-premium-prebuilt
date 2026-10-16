// SPDX-License-Identifier: MIT
// The playing track's artwork colour, handed down for either look to read. Whoever works it out
// publishes it here (the redesign's Kit/SGRTrackAccent.m, which Native/ may not import), and
// whoever needs it below Redesigned/ reads it here (the native look's accent, Native/Appearance/
// Accent.x). The bridge works nothing out itself: it holds the last colour published, tells of a
// change, and keeps the colour in the defaults so a launch that swaps its colours before any
// artwork has been read (the native accent is swapped at UIColor init time) can start from the
// last one.
//
// Threading: main thread only, like the publisher.
#import <UIKit/UIKit.h>

// The last published colour, 0xRRGGBB, kept across launches; unset or negative when none has been.
#define SGKeySharedTrackAccentLast @"spotifyglass.trackAccent.last"

// Publishes `color` (nil for none: the track has no usable artwork, or the follow switch went off).
// Posts SGSharedTrackAccentDidChangeNotification with the colour as the object when it differs from
// the last; a non-nil colour is stored under SGKeySharedTrackAccentLast as it is published.
void SGSetSharedTrackAccent(UIColor *color);
// The colour published this launch; before one has been, the colour stored by the last launch; nil
// when neither exists. The stored one is what the native look's accent starts from.
UIColor *SGSharedTrackAccent(void);
extern NSNotificationName const SGSharedTrackAccentDidChangeNotification;
