// The Home redesign: Spotify's Home page kept, with its controllers, lists and cards, decluttered to a
// music app on black and restyled from the Kit. No settings of its own.
//
//     HomeSections.x   an allow list of the feed's sections: the shortcuts grid, the DJ and the shelves of
//                      cards stay; video and episode previews, episode cards and any new kind collapse. The
//                      DJ loses its heading, and the flags the redesign forces on Home
//     HomeHeader.x     a large title where the filter pills were, the avatar at the trailing edge, no scrim
//     HomeHeadings.x   the shelves' headings in the Music app's size, drawn over Spotify's
//     HomeCards.x      the Encore button every card is: shortcut tiles (HomeTiles.m), continuous corners on the
//                      shelf covers, the DJ card at the card radius without its talking transcript
//     HomeTiles.m      a shortcut tile's picture run across the tile, blurred behind its title
//     HomeScroll.x     the feed's own list named to the tab bar, so the bar minimizes by it and not by a guess
//                      (Navbar/TabBar.x), and the header told of each scroll for its collapsing title
//     HomePerf.x       FLEX builds: the frames of each scroll of Home and the time the hooks above took
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI).
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Two opt-ins on the Appearance card (Kit/SGRAppearanceSettings.m), off until asked for and read on every
// pass, so neither waits for a relaunch:
//   a shortcut tile drawn as tinted glass (Kit/SGRGlass.h's plate under the cover's tint) in place of the
//   solid tinted surface (HomeTiles.m)
#define SGRKeyHomeGlassTiles @"spotifyglass.redesign.home.glassTiles"
//   the DJ card in the redesigned player's look: an artwork field behind it, the card radius, glass inside
//   its round control (HomeCards.x)
#define SGRKeyHomeDJPlayerLook @"spotifyglass.redesign.home.djPlayerLook"
// Two more, the Music app's Home, off until asked for:
//   the large title giving way to a small centred one over a hairline once the feed has scrolled past the
//   top, and coming back at the top (HomeHeader.x)
#define SGRKeyHomeCollapsingTitle @"spotifyglass.redesign.home.collapsingTitle"
//   the shelves alone: the shortcuts grid and the DJ card collapse too, so Home begins with its first shelf
//   the way the Music app's begins with Top Picks (HomeSections.x)
#define SGRKeyHomeShelvesOnly @"spotifyglass.redesign.home.shelvesOnly"

// HomeScroll.x tells the header where the feed's list is on every pass the list lays out (HomeHeader.x).
void SGRHomeListScrolled(UIScrollView *list);

// Whether HomeSections.x has collapsed the section in this cell.
BOOL SGRHomeSectionCollapsed(UIView *cell);

// Styles a shortcut tile (id=Shortcut.Card.Home) and keeps its picture in step with its cover (HomeTiles.m).
void SGRHomeStyleTile(UIView *tile);

// FLEX builds only (HomePerf.x): a hook takes the time as it starts and hands it back as it ends; outside
// a FLEX build Begin returns 0 and End does nothing.
typedef NS_ENUM(NSUInteger, SGRHomeProbe) {
    SGRHomeProbeSections,
    SGRHomeProbeHeader,
    SGRHomeProbeHeadings,
    SGRHomeProbeCards,
    SGRHomeProbeTiles,
    SGRHomeProbeCount,
};
CFTimeInterval SGRHomeProbeBegin(void);
void SGRHomeProbeEnd(SGRHomeProbe probe, CFTimeInterval began);
