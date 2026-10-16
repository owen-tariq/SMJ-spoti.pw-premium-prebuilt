// The player's background on Mod Settings' Player page: Fluid artwork, Animated artwork or Audio visualizer picked in place,
// and under it the settings of the one picked: Fluid artwork's sliders under a preview drawn by the same
// renderer as the player's field, Animated artwork's sources, or Audio visualizer's intensity, motion, glow
// count and colours, with the Library's looks (Shared/Library) to pick from and to save the current settings as.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Library/Library.h"
#import "Shared/Library/SGLibraryStore.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"
#import "Player.h"

NSNotificationName const SGRPlayerFluidLookDidChangeNotification = @"spotifyglass.redesign.player.fluidLookDidChange";
NSNotificationName const SGRPlayerBackgroundDidChangeNotification = @"spotifyglass.redesign.player.backgroundDidChange";
NSNotificationName const SGRVisualizerSettingsDidChangeNotification = @"spotifyglass.redesign.visualizer.settingsDidChange";

static const SGRPlayerBackground kDefaultBackground = SGRPlayerBackgroundFluid;

// A slider of the page: its key, range, step and default, in the whole numbers it stores.
typedef struct {
    __unsafe_unretained NSString *key, *title;
    NSInteger minimum, maximum, step, fallback;
    BOOL percent;
} SGRFluidSlider;

static const SGRFluidSlider kSpeed = {SGRKeyFluidSpeed, @"Speed", 25, 300, 25, 100, YES};
static const SGRFluidSlider kWarp = {SGRKeyFluidWarp, @"Warp", 0, 100, 5, 100, YES};
static const SGRFluidSlider kBlur = {SGRKeyFluidBlur, @"Blur", 2, 24, 1, 8, NO};
static const SGRFluidSlider kSaturation = {SGRKeyFluidSaturation, @"Saturation", 0, 250, 10, 150, YES};
static const SGRFluidSlider kBrightness = {SGRKeyFluidBrightness, @"Brightness", 40, 150, 5, 100, YES};

static NSInteger stored(SGRFluidSlider slider) {
    return MAX(slider.minimum, MIN(slider.maximum, SGInt(slider.key, slider.fallback)));
}

// Still artwork, Colour flow and the Moving background switch are gone, and whatever they stored reads as
// Fluid artwork, the default: the old keys only have to go.
static void migrate(void) {
    static BOOL done;
    if (done) return;
    done = YES;
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[SGRKeyPlayerBackgroundWas, SGRKeyPlayerMotionWas]) {
        id was = [store objectForKey:key];
        if (!was) continue;
        [store removeObjectForKey:key];
        SGLog(@"redesign player: %@ was %@, now Fluid artwork", key, was);
    }
}

SGRPlayerBackground SGRPlayerBackgroundStyle(void) {
    migrate();
    NSInteger style = SGInt(SGRKeyPlayerBackground, kDefaultBackground);
    // Audio visualizer (PlayerVisualizer.x) is the third choice; anything past the last reads as the default.
    return style >= SGRPlayerBackgroundFluid && style <= SGRPlayerBackgroundVisualizer ? (SGRPlayerBackground)style : kDefaultBackground;
}

SGRWarpLook SGRPlayerFluidLook(void) {
    return (SGRWarpLook){
        .speed = stored(kSpeed) / 100.0f,
        .warp = stored(kWarp) / 100.0f,
        .blur = stored(kBlur),
        .saturation = stored(kSaturation) / 100.0f,
        .brightness = stored(kBrightness) / 100.0f,
    };
}

static void lookChanged(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGRPlayerFluidLookDidChangeNotification object:nil];
}

#pragma mark - the preview

static const CGFloat kPreviewHeight = 240, kPreviewRadius = 26;

// A band across the middle of the player at the player's own scale, so the blur and the warp look the
// size they will there.
@interface SGRFluidPreview : SGRWarpView
@end

@implementation SGRFluidPreview {
    CGSize _laidOutFor;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.layer.cornerRadius = kPreviewRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    self.warpLayer.look = SGRPlayerFluidLook();
    [self showArtwork];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(showLook) name:SGRPlayerFluidLookDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(showArtwork) name:SGRNowPlayingArtworkDidChangeNotification object:nil];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    if (CGSizeEqualToSize(size, _laidOutFor) || size.width < 1) return;
    _laidOutFor = size;
    CGSize screen = self.window.bounds.size.width > 0 ? self.window.bounds.size : UIScreen.mainScreen.bounds.size;
    CGFloat pictureHeight = size.width * screen.height / MAX(1, screen.width);
    self.warpLayer.pictureFrame = CGRectMake(0, (size.height - pictureHeight) / 2, size.width, pictureHeight);
}

- (void)showLook {
    self.warpLayer.look = SGRPlayerFluidLook();
}

- (void)showArtwork {
    UIImage *artwork = SGRNowPlayingArtwork(NULL, NULL);
    [self.warpLayer setArtwork:artwork ?: SGRWarpSampleArtwork() animated:self.window != nil];
}

@end

#pragma mark - the rows

static SGModRow *sliderRow(SGRFluidSlider slider) {
    return SGSliderRow(slider.title, nil, slider.minimum, slider.maximum, slider.step,
        ^double { return stored(slider); },
        ^(double value) {
            SGSetInt(slider.key, lround(value));
            lookChanged();
        },
        ^NSString *(double value) {
            return slider.percent ? [NSString stringWithFormat:@"%ld%%", lround(value)] : [NSString stringWithFormat:@"%ld", lround(value)];
        });
}

static NSArray<SGModRow *> *shownFor(SGRPlayerBackground background, NSArray<SGModRow *> *rows) {
    for (SGModRow *row in rows) row.visible = ^BOOL { return SGRPlayerBackgroundStyle() == background; };
    return rows;
}

#pragma mark - Audio visualizer's settings

// The sliders reuse SGRFluidSlider: a key, a range and a default in whole percents.
static const SGRFluidSlider kIntensity = {SGRKeyVisualizerIntensity, @"Intensity", 50, 200, 10, 100, YES};
static const SGRFluidSlider kMotion = {SGRKeyVisualizerMotion, @"Motion", 25, 200, 25, 100, YES};
static const NSInteger kGlowsDefault = 2;   // the index of 4 in 2, 3, 4

SGRVisualizerSettings SGRPlayerVisualizerSettings(void) {
    NSInteger glows = SGInt(SGRKeyVisualizerGlows, kGlowsDefault), colours = SGInt(SGRKeyVisualizerColours, SGRVisualizerColoursArtwork);
    return (SGRVisualizerSettings){
        .intensity = stored(kIntensity),
        .motion = stored(kMotion),
        .glowCount = 2 + MAX(0, MIN(2, glows)),
        .colours = colours >= SGRVisualizerColoursArtwork && colours <= SGRVisualizerColoursLook ? (SGRVisualizerColours)colours : SGRVisualizerColoursArtwork,
    };
}

NSString *SGRPlayerVisualizerLookName(void) {
    NSString *name = [NSUserDefaults.standardUserDefaults stringForKey:SGRKeyVisualizerLook];
    return name.length ? name : nil;
}

static void visualizerChanged(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGRVisualizerSettingsDidChangeNotification object:nil];
}

static SGModRow *visualizerSliderRow(SGRFluidSlider slider) {
    return SGSliderRow(slider.title, nil, slider.minimum, slider.maximum, slider.step,
        ^double { return stored(slider); },
        ^(double value) {
            SGSetInt(slider.key, lround(value));
            visualizerChanged();
        },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%ld%%", lround(value)]; });
}

static NSString *hexOf(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        if (![color getWhite:&white alpha:&a]) return nil;
        r = g = b = white;
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(MAX(0, MIN(1, r)) * 255), (int)lround(MAX(0, MIN(1, g)) * 255),
            (int)lround(MAX(0, MIN(1, b)) * 255)];
}

// The settings as they stand, and the colours the glows are drawn in now, as the JSON a Library look holds
// (the same shape an imported look is read in: intensity, motion, glowCount, colours as "#RRGGBB").
static NSDictionary<NSString *, id> *currentLook(void) {
    SGRVisualizerSettings settings = SGRPlayerVisualizerSettings();
    NSMutableArray<NSString *> *colours = [NSMutableArray array];
    for (UIColor *color in SGRPlayerVisualizerColors()) {
        NSString *hex = hexOf(color);
        if (hex && colours.count < 4) [colours addObject:hex];
    }
    NSMutableDictionary<NSString *, id> *look = [NSMutableDictionary dictionaryWithDictionary:@{
        @"intensity": @(settings.intensity), @"motion": @(settings.motion), @"glowCount": @(settings.glowCount),
    }];
    // Without colours (the player has not shown the glows yet) the look keeps the cover's.
    if (colours.count) look[@"colours"] = colours;
    return look;
}

static void sayVisualizer(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// Save current as look...: a name asked for in an alert, the look written to the Library's shelf under it and
// picked as the look, so Colours > Look shows it at once.
static void saveCurrentLook(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save as look" message:@"A name for the Library's shelf; one of the same name is replaced."
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Name";
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        // A file name: no path separators, nothing hidden.
        name = [[name componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/:\\"]] componentsJoinedByString:@"-"];
        while ([name hasPrefix:@"."]) name = [name substringFromIndex:1];
        if (!name.length) {
            sayVisualizer(@"Save as look", @"A look needs a name.");
            return;
        }
        NSError *error = nil;
        if (!SGLibrarySaveLook(name, currentLook(), &error)) {
            sayVisualizer(@"Save as look", error.localizedDescription ?: @"The look could not be written.");
            return;
        }
        [NSUserDefaults.standardUserDefaults setObject:name forKey:SGRKeyVisualizerLook];
        SGLog(@"redesign player: visualizer look %@ saved", name);
        visualizerChanged();
    }];
    [alert addAction:save];
    alert.preferredAction = save;
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// Look: the Library's looks by name in an alert (the shelf is read when the row is tapped, so a look imported
// while the page is open is there), the one picked stored by name.
static void pickLook(void) {
    NSArray<NSString *> *names = SGLibraryLookNames();
    if (!names.count) {
        sayVisualizer(@"Look", @"No looks yet. Import a .json under Mod Settings > Library, or save the current settings as one.");
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Look" message:nil preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = SGRPlayerVisualizerLookName();
    for (NSString *name in names) {
        NSString *title = [name isEqualToString:current] ? [@"✓ " stringByAppendingString:name] : name;
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [NSUserDefaults.standardUserDefaults setObject:name forKey:SGRKeyVisualizerLook];
            visualizerChanged();
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static NSArray<SGModRow *> *visualizerRows(void) {
    SGModRow *glows = SGChoiceRow(@"Glow count", nil, SGRKeyVisualizerGlows, @[@"2", @"3", @"4"], kGlowsDefault);
    glows.choiceNotes = @[@"The bass and the middle", @"The bass, the middle and the top", @"The bass, the middle, the top and the whole"];
    glows.choiceFooter = @"A cover with fewer colours than glows lends them round again.";
    glows.chosen = ^(NSInteger index) { visualizerChanged(); };

    SGModRow *colours = SGChoiceRow(@"Colours", nil, SGRKeyVisualizerColours, @[@"From artwork", @"Accent colour", @"Look"], SGRVisualizerColoursArtwork);
    colours.choiceNotes = @[@"Up to four colours read from the cover", @"The accent colour of Appearance and three tones around it",
                            @"A look from Mod Settings > Library, which may bring its own intensity, motion and glow count"];
    colours.chosen = ^(NSInteger index) { visualizerChanged(); };

    SGModRow *look = SGStatActionRow(@"Look", nil, ^NSString *{ return SGRPlayerVisualizerLookName() ?: @"None"; }, ^{ pickLook(); });
    look.visible = ^BOOL {
        return SGRPlayerBackgroundStyle() == SGRPlayerBackgroundVisualizer && SGRPlayerVisualizerSettings().colours == SGRVisualizerColoursLook;
    };

    SGModRow *save = SGActionRow(@"Save current as look…", nil, ^{ saveCurrentLook(); });
    save.symbol = @"square.and.arrow.down";

    return @[visualizerSliderRow(kIntensity), visualizerSliderRow(kMotion), glows, colours, look, save];
}

// The visualizer's rows show while it is picked; the Look row has a condition of its own on top.
static NSArray<SGModRow *> *visualizerSectionRows(void) {
    NSArray<SGModRow *> *rows = visualizerRows();
    for (SGModRow *row in rows) {
        if (row.visible) continue;
        row.visible = ^BOOL { return SGRPlayerBackgroundStyle() == SGRPlayerBackgroundVisualizer; };
    }
    return rows;
}

NSArray<SGModSection *> *SGRPlayerBackgroundSections(void) {
    migrate();
    // The third choice, Audio visualizer, is PlayerVisualizer.x's; its rows are visualizerRows().
    NSArray<SGModRow *> *choices = SGChoiceListRows(SGRKeyPlayerBackground, @[@"Fluid artwork", @"Animated artwork", @"Audio visualizer"],
        @[@"The cover itself, blurred and slowly warped", @"The track's Canvas or the album's animated cover, looping",
          @"Soft glows in the cover's colours, moving with the sound"],
        kDefaultBackground, ^(NSInteger index) {
            [NSNotificationCenter.defaultCenter postNotificationName:SGRPlayerBackgroundDidChangeNotification object:nil];
        });

    SGModRow *preview = SGViewRow([SGRFluidPreview new], kPreviewHeight);
    NSArray<SGModRow *> *sliders = @[sliderRow(kSpeed), sliderRow(kWarp), sliderRow(kBlur), sliderRow(kSaturation), sliderRow(kBrightness)];
    SGModRow *reset = SGActionRow(@"Reset", nil, ^{
        for (NSString *key in @[SGRKeyFluidSpeed, SGRKeyFluidWarp, SGRKeyFluidBlur, SGRKeyFluidSaturation, SGRKeyFluidBrightness]) {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        }
        lookChanged();
    });
    reset.color = SGRed();
    reset.symbol = @"arrow.counterclockwise";

    SGModRow *sources = SGArtworkSourcesRow(SGRKeyPlayerArtworkSources,
        @"Asked top to bottom until one has a clip. Apple Music gets only the artist and album name.");

    return @[
        SGNotedSection(@"Background", choices, @"A paused song holds the background still."),
        SGSection(nil, shownFor(SGRPlayerBackgroundFluid, @[preview])),
        SGNotedSection(nil, shownFor(SGRPlayerBackgroundFluid, sliders),
                       @"The player follows these as they move. Brightness past 100% can make white text harder to read on a light cover."),
        SGSection(nil, shownFor(SGRPlayerBackgroundFluid, @[reset])),
        SGNotedSection(nil, shownFor(SGRPlayerBackgroundAnimated, @[sources]),
                       @"A track without a clip shows Fluid artwork, and so does every track in Low Power Mode or with Reduce Motion on."),
        SGNotedSection(nil, visualizerSectionRows(),
                       @"The player follows these as they move. Whatever the intensity, the glows stay under the brightness white text reads on. "
                        "Saving writes the settings and the colours showing now to Mod Settings > Library as a look."),
    ];
}
