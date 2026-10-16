// SPDX-License-Identifier: MIT
#import <UIKit/UIKit.h>

// Opt-in. This controls the current iOS audio route, not a remote Spotify Connect device.
#define SGRKeyPlayerVolume @"spotifyglass.redesign.player.deviceVolume"
void SGRPlayerVolumeRefresh(void);
