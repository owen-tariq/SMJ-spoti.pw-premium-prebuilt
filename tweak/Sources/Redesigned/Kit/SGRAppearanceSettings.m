// SPDX-License-Identifier: GPL-3.0-only
// Base file is byte-identical to upstream v0.21.1 (a08b38b); new opt-in rows below.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "SGRAccent.h"
#import "SGRTrackAccent.h"
#import "SGRTokens.h"
#import "SGRGlass.h"
#import "Redesigned/Player/PlayerVolume.h"
#import "Redesigned/Player/Player.h"
#import "Redesigned/Home/Home.h"

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
    // Whole percents, stored as they are dragged; the glass and the accent read them on their next pass, so
    // neither needs a relaunch (a control already drawn with the accent takes it when Spotify next sets it).
    NSString *(^percent)(double) = ^NSString *(double value) { return [NSString stringWithFormat:@"%ld%%", lround(value)]; };
    SGModRow *glassStrength = SGSliderRow(@"Glass strength", @"How much of the material the redesign's glass shows: thinner below 100%, denser above.",
                                          50, 150, 5,
                                          ^double { return (double)MIN(150, MAX(50, SGInt(SGRKeyGlassStrength, 100))); },
                                          ^(double value) { SGSetInt(SGRKeyGlassStrength, lround(value)); }, percent);
    SGModRow *accentIntensity = SGSliderRow(@"Accent intensity", @"Saturation and brightness of the accent, whichever colour it is; kept readable on black.",
                                            60, 140, 5,
                                            ^double { return (double)MIN(140, MAX(60, SGInt(SGRKeyAccentIntensity, 100))); },
                                            ^(double value) { SGSetInt(SGRKeyAccentIntensity, lround(value)); }, percent);
    SGModRow *glassTiles = SGOptionRow(@"Home shortcuts on glass", @"Each shortcut tile as glass tinted with its cover's colour, in place of the solid tint.", SGRKeyHomeGlassTiles);
    SGModRow *djLook = SGOptionRow(@"DJ card in the player's look", @"The DJ card on an artwork field with glass inside its control, like the redesigned player.", SGRKeyHomeDJPlayerLook);
    SGModRow *collapsingTitle = SGOptionRow(@"Home title collapses on scroll", @"The large title gives way to a small centred one over a hairline as Home scrolls, like the Music app.", SGRKeyHomeCollapsingTitle);
    SGModRow *shelvesOnly = SGOptionRow(@"Home shelves only", @"The shortcuts grid and the DJ go too, so Home begins with its first shelf, like the Music app's Top Picks.", SGRKeyHomeShelvesOnly);
    SGModRow *star = SGSwitchRow(@"Favourite star in the player", @"Spotify's add button beside the title drawn as the Music app's star, filled in the accent colour once saved.", SGRKeyPlayerFavouriteStar);
    return @[
        SGWithSymbol(follows, @"photo.artframe"),
        SGWithSymbol(star, @"star"),
        SGWithSymbol(volume, @"speaker.wave.2"),
        SGWithSymbol(SGStatActionRow(@"Accent colour", nil, ^NSString *{ return SGRAccentLabel(); }, ^{ chooseAccent(); }), @"paintpalette"),
        SGWithSymbol(glassStrength, @"circle.lefthalf.filled"),
        SGWithSymbol(accentIntensity, @"slider.horizontal.3"),
        SGWithSymbol(glassTiles, @"square.grid.2x2"),
        SGWithSymbol(djLook, @"waveform.circle"),
        SGWithSymbol(collapsingTitle, @"textformat.size.smaller"),
        SGWithSymbol(shelvesOnly, @"rectangle.grid.1x2"),
    ];
}
