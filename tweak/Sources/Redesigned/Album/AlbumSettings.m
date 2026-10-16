#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "Album.h"

UIViewController *SGRAlbumSettingsPage(void) {
    NSArray<SGModSection *> *sections = @[
        SGNotedSection(@"Header", @[
            SGSwitchRow(@"Animated cover", @"Apple Music's, where the album has one", SGRKeyAnimatedCovers),
            SGOptionRow(@"Tinted Play and Shuffle", @"Play on a grey capsule in the accent colour, like the Music app's. Playlists too", SGRKeyTintedHeaderControls),
        ], @"Apple Music gets only the artist and album name. Nothing is downloaded in Low Data or Low Power Mode."),
        SGNotedSection(@"Track list", @[
            SGSwitchRow(@"Hide album artists", @"Featured artists stay visible", SGRKeyHideAlbumArtists),
            SGSwitchRow(@"Hide all track artists", @"Including featured artists", SGRKeyHideAllAlbumArtists),
            SGSwitchRow(@"Hide explicit tags", @"Next to track artists", SGRKeyHideExplicitAlbumTags),
        ], nil),
    ];
    return [[SGModPage alloc] initWithTitle:@"Albums" intro:nil sections:sections footer:nil];
}
