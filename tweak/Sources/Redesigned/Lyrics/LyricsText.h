// What the redesign's lyrics show of a line besides its words: the pronunciation and the translation a
// source has for it (Shared/Lyrics/Lyrics.h), each switched on from the lyrics' own menu, and the order
// of sizes the three are set in, from the Lyrics page. The switches apply at once, to every lyrics
// view there is, and are kept for the next song and the next launch.
#import <UIKit/UIKit.h>

// A line's three texts. The order puts them largest first; the lyrics are always among them.
typedef NS_ENUM(NSInteger, SGRLyricsText) {
    SGRLyricsTextLyrics = 0,
    SGRLyricsTextPronunciation,
    SGRLyricsTextTranslation,
};

#define SGRKeyLyricsPronunciation @"spotifyglass.redesign.lyricsPronunciation"   // off until switched on
#define SGRKeyLyricsTranslation @"spotifyglass.redesign.lyricsTranslation"       // off until switched on
// The three as the words "lyrics", "pronunciation" and "translation", largest first.
#define SGRKeyLyricsTextOrder @"spotifyglass.redesign.lyricsTextOrder"
// The family the lyrics are set in, one the Library registered (Shared/Library); unset or gone is the system font.
#define SGRKeyLyricsFontFamily @"spotifyglass.redesign.lyrics.fontFamily"

// Posted on the main queue when either switch or the order changes.
extern NSNotificationName const SGRLyricsTextDidChangeNotification;

// The order, SGRLyricsText values largest first; unset is Apple Music's: lyrics, pronunciation, translation.
NSArray<NSNumber *> *SGRLyricsTextOrder(void);
void SGRSetLyricsTextOrder(NSArray<NSNumber *> *order);
NSString *SGRLyricsTextName(SGRLyricsText text);
void SGRSetLyricsTextShown(SGRLyricsText text, BOOL shown);

// The lyrics' family as stored, nil for the system font; setting one posts the change.
NSString *SGRLyricsFontFamily(void);
void SGRSetLyricsFontFamily(NSString *family);
// A font of the chosen family at the size and weight, the system font when none is chosen or UIFont does not
// have it (the file was deleted from the Library).
UIFont *SGRLyricsFont(CGFloat size, UIFontWeight weight);

// LyricsTextSettings.m: the Lyrics page's row for the order, which opens a list of the three to drag.
@class SGModRow;
SGModRow *SGRLyricsTextSizesRow(void);
// LyricsTextSettings.m: the Lyrics page's Font row, System and the Library's families.
SGModRow *SGRLyricsFontRow(void);
