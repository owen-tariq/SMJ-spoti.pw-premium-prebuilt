// SPDX-License-Identifier: MIT
#import "TrackAccentBridge.h"
#import "Core/SGCore.h"

NSNotificationName const SGSharedTrackAccentDidChangeNotification = @"spotifyglass.shared.trackAccentDidChange";

static UIColor *sg_live;          // published this launch, nil for none
static BOOL sg_livePublished;     // whether anything has been published this launch, nil included

static NSInteger packed(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (!color || ![color getRed:&r green:&g blue:&b alpha:&a]) return -1;
    return ((NSInteger)lround(MIN(1, MAX(0, r)) * 255) << 16)
         | ((NSInteger)lround(MIN(1, MAX(0, g)) * 255) << 8)
         | (NSInteger)lround(MIN(1, MAX(0, b)) * 255);
}

static UIColor *stored(void) {
    NSInteger rgb = SGInt(SGKeySharedTrackAccentLast, -1);
    if (rgb < 0 || rgb > 0xFFFFFF) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

void SGSetSharedTrackAccent(UIColor *color) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGSetSharedTrackAccent(color); });
        return;
    }
    NSInteger rgb = packed(color);
    UIColor *next = rgb < 0 ? nil : color;
    BOOL same = sg_livePublished && packed(sg_live) == rgb;
    sg_live = next;
    sg_livePublished = YES;
    if (next) SGSetInt(SGKeySharedTrackAccentLast, rgb);
    if (same) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"track accent bridge: first colour %@", next ?: @"none"); });
    [NSNotificationCenter.defaultCenter postNotificationName:SGSharedTrackAccentDidChangeNotification object:next];
}

UIColor *SGSharedTrackAccent(void) {
    if (sg_livePublished) return sg_live;
    return stored();
}
