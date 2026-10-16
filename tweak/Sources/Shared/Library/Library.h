// SPDX-License-Identifier: MIT
// Mod Settings > Library: what the user brings in from Files and the mod keeps, with no server behind any of
// it. Four shelves under Library/Application Support/spoti.pw/Library in Spotify's container (the Sing model
// under spoti.pw/Sing/Custom, beside the downloaded one):
//
//     Fonts/            .ttf and .otf files, registered with CoreText for this process at launch and on import,
//                       offered to the redesign's lyrics by family name (SGLibraryFontFamilies)
//     Looks/            visualizer looks, one small JSON dictionary per file: stored, listed and deleted here,
//                       read and written by the visualizer through SGLibraryStore.h
//     Audio effects     no shelf of its own: the page's rows open Shared/AudioEffects' own libraries
//                       (impulse responses, DDC files, Liveprog scripts, the GraphicEQ text)
//     Sing/Custom/      a separator.mlmodelc the user imported (a folder or a .zip holding one), used in the
//                       downloaded model's place while Use custom model is on (SGSingModel.m asks
//                       SGLibraryCustomSingModelURL)
//
//     LibraryPage.m       the page and its file lists
//     SGLibraryStore.m    the shelves: directories, import, list, delete; the zip reader; font registration
//
// Threading: the functions here are safe from any thread unless said otherwise; the notifications are posted
// on the main queue. Every key starts with "spotifyglass.".
#import <UIKit/UIKit.h>

// Sing runs the imported model instead of the downloaded one while this is on (off until switched on).
#define SGKeySingCustomModel @"spotifyglass.sing.customModel"

// Posted on the main queue when a look is imported, saved or deleted; the visualizer reads the shelf again.
extern NSNotificationName const SGLibraryLooksDidChangeNotification;
// Posted on the main queue when the custom Sing model is imported or removed, or its switch flips.
extern NSNotificationName const SGLibrarySingModelDidChangeNotification;
// Posted on the main queue when a font is imported or deleted.
extern NSNotificationName const SGLibraryFontsDidChangeNotification;

// The families of every font file on the shelf, registered with CoreText so UIFont finds them, sorted. Empty
// until something is imported. Registers the shelf first if launch has not got to it yet.
NSArray<NSString *> *SGLibraryFontFamilies(void);

// The imported separator.mlmodelc, or nil: unless SGKeySingCustomModel is on and the folder still holds a
// model (model.mil or coremldata.bin), there is none, and Sing uses the downloaded model.
NSURL *SGLibraryCustomSingModelURL(void);

// The page (main thread).
UIViewController *SGLibraryPage(void);
