// Home redesign: the header the way the Music app has it. The filter pills (All, Music, Podcasts) go and
// a large title takes their place at the leading edge; the avatar that opens the side drawer moves to the
// trailing edge; the scrim Spotify lays behind the header goes too, the soft scroll edge (Kit/SGREdgeEffect.x)
// being what keeps the title clear of the page scrolling under it, as on every other redesigned page.
//
// Tree (trees/clean/home/10.txt:3018-3051): FunkisViewController's view holds a 402x112 UIView around
// Reprise_LiquidGlassKit LiquidGlass.GradientView (the scrim) and, at {0, 62}, an
// ElementView<HomeHeaderElement> 402x50 holding HomeHeaderView > UIStackView {0, 8} 402x34 of two arranged
// views: ListeningActivity_ElementsKit.AdaptiveFaceContainer {16, 0} 32x34 (the avatar,
// id=Components.UI.SideDrawerButton) and LiquidGlass.LeadingFadeMaskView {48, 1} 354x32 around
// Home_PillUIKit.PillScrollView.
//
// The avatar moves by the stack's layout direction rather than by a frame of ours. Right to left, the stack
// lays its first view out at the trailing edge itself on every pass, whatever width the face container
// takes when friends listening show beside the avatar; its leading margin, 16pt, is the one Spotify gives
// the header in a right to left language. The pills stay in the stack with no alpha rather than hidden,
// the way the redesign takes any view out of a stack Spotify arranges (Kit/SGRRestyle.h).
//
// The title is Spotify's own name for the tab, read off its tab bar item (id=TabBar.Item.Home, 10.txt:3100),
// so it follows the app's language.
//
// Collapsing title (SGRKeyHomeCollapsingTitle, off unless asked for): the header neither moves nor shrinks as
// the feed scrolls, so the Music app's large title scrolling away is done as a crossfade in place. Once the
// feed has scrolled kCollapseAt past its top the large title fades out and a small centred title fades in
// over a hairline along the header's bottom; back within kExpandAt of the top the large title returns. A fade
// is not motion and stays under Reduce Motion. HomeScroll.x tells this file where the list is on every pass.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

// Tries at finding the tab's name before settling for the English one: a miss walks the window.
static const NSUInteger kTitleTries = 8;

static char kTitleKey, kTabKey, kSmallTitleKey, kHairlineKey;
static NSString *sg_tabName;
// Collapsing title: scrolled this far past the top the small title takes over, this near it the large one returns.
static const CGFloat kCollapseAt = 32, kExpandAt = 12;
static BOOL sg_collapsed;

static void vanish(UIView *view) {
    if (!view) return;
    if (view.alpha != 0) view.alpha = 0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static UIView *childNamed(UIView *host, NSString *marker) {
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) containsString:marker]) return sub;
    }
    return nil;
}

static NSString *tabName(UIWindow *window) {
    if (sg_tabName || !window) return sg_tabName ?: @"Home";
    static NSUInteger tries;
    if (tries >= kTitleTries) return @"Home";
    tries++;
    UIView *item = SGRFindByIdentifier(window, @"TabBar.Item.Home", &kTabKey);
    __block NSString *name = nil;
    if (item) SGForEachView(item, ^(UIView *v) {
        if (!name && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) name = ((UILabel *)v).text;
    });
    if (!name) {
        if (tries == kTitleTries) SGLog(@"redesign home: the Home tab's name not found, the title stays English");
        return @"Home";
    }
    sg_tabName = [name copy];
    SGLog(@"redesign home: title \"%@\" from the tab bar", sg_tabName);
    return sg_tabName;
}

static UILabel *titleIn(UIView *header) {
    UILabel *title = objc_getAssociatedObject(header, &kTitleKey);
    if (!title) {
        title = [UILabel new];
        title.textColor = SGRPrimary();
        title.accessibilityTraits = UIAccessibilityTraitHeader;
        title.adjustsFontSizeToFitWidth = YES;
        title.minimumScaleFactor = 0.6;
        title.userInteractionEnabled = NO;
        objc_setAssociatedObject(header, &kTitleKey, title, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (title.superview != header) [header addSubview:title];
    return title;
}

// The small title and the hairline of the collapsing title, made on the first pass that wants them and kept
// transparent until the feed has scrolled; the large title stays what the header is read by.
static UILabel *smallTitleIn(UIView *header) {
    UILabel *small = objc_getAssociatedObject(header, &kSmallTitleKey);
    if (!small) {
        small = [UILabel new];
        small.textColor = SGRPrimary();
        small.textAlignment = NSTextAlignmentCenter;
        small.userInteractionEnabled = NO;
        small.accessibilityElementsHidden = YES;
        small.alpha = 0;
        objc_setAssociatedObject(header, &kSmallTitleKey, small, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (small.superview != header) [header addSubview:small];
    return small;
}

static UIView *hairlineIn(UIView *header) {
    UIView *line = objc_getAssociatedObject(header, &kHairlineKey);
    if (!line) {
        line = [UIView new];
        line.userInteractionEnabled = NO;
        line.alpha = 0;
        objc_setAssociatedObject(header, &kHairlineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (line.superview != header) [header addSubview:line];
    return line;
}

// The header's views, found once: the page lays out again as it appears, and the walk names classes.
static __weak UIView *sg_header;
static __weak UIStackView *sg_stack;
static __weak UIView *sg_scrim;

static BOOL findHeader(UIView *view) {
    if (sg_stack && [sg_stack isDescendantOfView:view]) return YES;
    for (UIView *wrapper in view.subviews) {
        UIView *scrim = childNamed(wrapper, @"GradientView");
        if (scrim) sg_scrim = scrim;
    }
    UIView *header = childNamed(childNamed(view, @"HomeHeaderElement"), @"HomeHeaderView");
    for (UIView *sub in header.subviews) {
        if ([sub isKindOfClass:UIStackView.class]) sg_stack = (UIStackView *)sub;
    }
    sg_header = header;
    if (sg_stack) return YES;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign home: header stack not found, header left as Spotify's"); });
    return NO;
}

static void layoutHeader(UIViewController *page) {
    UIView *view = page.viewIfLoaded;
    if (!view || !findHeader(view)) return;
    UIView *header = sg_header;
    UIStackView *stack = sg_stack;
    vanish(sg_scrim);

    static Class faceClass;
    if (!faceClass) faceClass = NSClassFromString(@"_TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer");
    UIView *face = nil;
    for (UIView *part in stack.arrangedSubviews) {
        if (faceClass && [part isKindOfClass:faceClass]) face = part;
        else vanish(part);
    }
    if (stack.semanticContentAttribute != UISemanticContentAttributeForceRightToLeft) {
        stack.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        [stack setNeedsLayout];
    }
    [stack layoutIfNeeded];

    UILabel *title = titleIn(header);
    NSString *text = tabName(header.window);
    if (![title.text isEqualToString:text]) {
        title.text = text;
        title.accessibilityLabel = text;
    }
    UIFont *font = SGRFont(UIFontTextStyleLargeTitle, UIFontWeightBold, UIContentSizeCategoryLarge);
    if (![title.font isEqual:font]) title.font = font;

    CGFloat trailing = face ? CGRectGetMinX([stack convertRect:face.frame toView:header]) - SGRGrid : header.bounds.size.width - SGRSideMargin;
    CGFloat height = ceil(font.lineHeight);
    CGRect frame = CGRectMake(SGRSideMargin, round(CGRectGetMidY(stack.frame) - height / 2), MAX(0, trailing - SGRSideMargin), height);
    if (!CGRectEqualToRect(title.frame, frame)) title.frame = frame;

    if (SGHidden(SGRKeyHomeCollapsingTitle)) {
        UILabel *small = smallTitleIn(header);
        if (![small.text isEqualToString:text]) small.text = text;
        UIFont *smallFont = SGRFont(UIFontTextStyleHeadline, UIFontWeightSemibold, UIContentSizeCategoryLarge);
        if (![small.font isEqual:smallFont]) small.font = smallFont;
        // Centred on the page, kept clear of the avatar on either side.
        CGFloat inset = face ? header.bounds.size.width - trailing + SGRGrid : SGRSideMargin;
        CGFloat smallHeight = ceil(smallFont.lineHeight);
        CGRect smallFrame = CGRectMake(inset, round(CGRectGetMidY(stack.frame) - smallHeight / 2), MAX(0, header.bounds.size.width - 2 * inset), smallHeight);
        if (!CGRectEqualToRect(small.frame, smallFrame)) small.frame = smallFrame;
        UIView *line = hairlineIn(header);
        UIColor *hairline = SGRHairline();
        if (![line.backgroundColor isEqual:hairline]) line.backgroundColor = hairline;
        CGFloat pixel = 1 / MAX(1, header.window.screen.scale);
        CGRect lineFrame = CGRectMake(0, header.bounds.size.height - pixel, header.bounds.size.width, pixel);
        if (!CGRectEqualToRect(line.frame, lineFrame)) line.frame = lineFrame;
    } else if (sg_collapsed) {
        // Switched off while collapsed: the large title comes straight back.
        sg_collapsed = NO;
        title.alpha = 1;
        ((UIView *)objc_getAssociatedObject(header, &kSmallTitleKey)).alpha = 0;
        ((UIView *)objc_getAssociatedObject(header, &kHairlineKey)).alpha = 0;
    }

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"redesign home: header %@, avatar %@ in the stack %@, title %@, scrim %@", NSStringFromCGRect(header.frame),
              face ? NSStringFromCGRect(face.frame) : @"not found", NSStringFromCGRect(stack.frame), NSStringFromCGRect(frame),
              sg_scrim ? @"found" : @"not found");
    });
}

void SGRHomeListScrolled(UIScrollView *list) {
    if (!SGHidden(SGRKeyHomeCollapsingTitle)) return;
    UIView *header = sg_header;
    UILabel *title = header ? objc_getAssociatedObject(header, &kTitleKey) : nil;
    UILabel *small = header ? objc_getAssociatedObject(header, &kSmallTitleKey) : nil;
    UIView *line = header ? objc_getAssociatedObject(header, &kHairlineKey) : nil;
    if (!title || !small || !line || !header.window) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign home: no header to collapse the title of, left as it is"); });
        return;
    }
    CGFloat scrolled = list.contentOffset.y + list.adjustedContentInset.top;
    BOOL collapse = sg_collapsed ? scrolled > kExpandAt : scrolled > kCollapseAt;
    if (collapse == sg_collapsed) return;
    sg_collapsed = collapse;
    static NSUInteger logged;
    if (logged++ < 6) SGLog(@"redesign home: title %@ at %.0f pt", collapse ? @"collapsed" : @"expanded", scrolled);
    SGRAnimate(SGRMotionFade, ^{
        title.alpha = collapse ? 0 : 1;
        small.alpha = collapse ? 1 : 0;
        line.alpha = collapse ? 1 : 0;
    }, nil);
}

%hook _TtC19Home_FunkisPageImpl20FunkisViewController
- (void)viewDidLayoutSubviews {
    %orig;
    CFTimeInterval began = SGRHomeProbeBegin();
    layoutHeader((UIViewController *)self);
    SGRHomeProbeEnd(SGRHomeProbeHeader, began);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    %orig;
    [((UIViewController *)self).viewIfLoaded setNeedsLayout];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC19Home_FunkisPageImpl20FunkisViewController",
        @"_TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer",
    ]);
}
