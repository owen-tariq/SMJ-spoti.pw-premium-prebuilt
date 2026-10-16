// SPDX-License-Identifier: MIT
// Home redesign: the feed's own list, found once and told to whoever follows Home's scrolling. The tab bar
// minimizes by the page's list (Navbar/TabBar.x), which it otherwise has to guess at from whatever vertical
// list is on screen -- and Home's feed is a Home_CarouselKit.TouchCancellingCollectionView, the very class
// of the horizontal shelves inside it, so Home is the page the guess is likeliest to miss. Named here, it
// is never guessed. The header is told of each pass too, for its collapsing title (HomeHeader.x).
//
// Tree (HomePerf.x, trees/clean/home/10.txt): FunkisViewController > EvoLoadableResourceViewController, whose
// view's direct subview is the feed's UICollectionView, the one list over the whole page. A list lays out on
// every frame it moves, which is where its offset is read; both calls return at once when nothing changed.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Home.h"

static __weak UIScrollView *sg_list;
static char kHomeTabKey;

static BOOL isHomeTab(UIViewController *page) {
    NSNumber *answer = objc_getAssociatedObject(page, &kHomeTabKey);
    if (answer) return answer.boolValue;
    static Class funkis;
    if (!funkis) funkis = NSClassFromString(@"_TtC19Home_FunkisPageImpl20FunkisViewController");
    BOOL home = NO;
    for (UIViewController *parent = page.parentViewController; parent && !home; parent = parent.parentViewController) {
        home = [parent isKindOfClass:funkis];
    }
    if (page.parentViewController) objc_setAssociatedObject(page, &kHomeTabKey, @(home), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return home;
}

static void findList(UIViewController *page) {
    if (sg_list || !isHomeTab(page)) return;
    for (UIView *sub in page.viewIfLoaded.subviews) {
        if ([sub isKindOfClass:UICollectionView.class]) sg_list = (UIScrollView *)sub;
    }
    static dispatch_once_t once;
    if (sg_list) {
        dispatch_once(&once, ^{ SGLog(@"redesign home: the feed's list is %@ %@", NSStringFromClass(sg_list.class), NSStringFromCGRect(sg_list.frame)); });
    } else {
        dispatch_once(&once, ^{ SGLog(@"redesign home: no list under %@, the tab bar guesses at Home's", NSStringFromClass(page.class)); });
    }
}

%hook _TtC16Home_EvoPageImpl33EvoLoadableResourceViewController
- (void)viewDidLayoutSubviews {
    %orig;
    findList((UIViewController *)self);
}
%end

%hook _TtC16Home_CarouselKit29TouchCancellingCollectionView
- (void)layoutSubviews {
    %orig;
    UIScrollView *list = (UIScrollView *)self;
    if (list != sg_list) return;
    if (list.window) SGRTabBarFollowScroll(list);
    SGRHomeListScrolled(list);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC16Home_EvoPageImpl33EvoLoadableResourceViewController",
        @"_TtC16Home_CarouselKit29TouchCancellingCollectionView",
    ]);
}
