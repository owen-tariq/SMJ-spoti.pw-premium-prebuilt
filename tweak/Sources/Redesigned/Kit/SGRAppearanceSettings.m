// SPDX-License-Identifier: GPL-3.0-only
// Base file is byte-identical to upstream v0.21.1 (a08b38b); new opt-in rows below.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "SGRAccent.h"
#import "SGRTrackAccent.h"
#import "Redesigned/Player/PlayerVolume.h"

// Going back to Spotify's green is offered only once a colour of the mod's is set, so a stray tap
// cannot wipe it.
static void chooseAccent(void) {
    if (!SGRAccentColor()) {
        SGRPickAccent();
        return;
    }
    UIViewController *top = SGTopController();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Accent colour" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Pick a colour" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRPickAccent(); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Spotify's green" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { SGSetInt(SGRKeyAccent, -1); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = top.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 0, 0);
    sheet.popoverPresentationController.permittedArrowDirections = 0;
    [top presentViewController:sheet animated:YES completion:nil];
}

// The redesign's rows of the Appearance card (App/Pages.m). AMOLED has no row: the redesign is always black.
NSArray<SGModRow *> *SGRAppearanceRows(void) {
    SGModRow *follows = SGOptionRow(@"Follow artwork colours", @"Use the current cover for redesigned Kit accents; falls back to your chosen colour.", SGRKeyTrackAccent);
    follows.changed = ^(BOOL on) { (void)on; SGRTrackAccentRefresh(); };
    SGModRow *volume = SGOptionRow(@"Player device volume", @"Controls this iPhone's audio route, not a remote Spotify Connect device.", SGRKeyPlayerVolume);
    volume.changed = ^(BOOL on) { (void)on; SGRPlayerVolumeRefresh(); };
    return @[
        SGWithSymbol(follows, @"photo.artframe"),
        SGWithSymbol(volume, @"speaker.wave.2"),
        SGWithSymbol(SGStatActionRow(@"Accent colour", nil, ^NSString *{ return SGRAccentLabel(); }, ^{ chooseAccent(); }), @"paintpalette"),
    ];
}
