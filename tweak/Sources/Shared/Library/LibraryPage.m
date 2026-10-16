// SPDX-License-Identifier: MIT
// Mod Settings > Library (Library.h): a row per shelf, each opening its list, the audio effects' rows opening
// Shared/AudioEffects' own libraries, and the Sing model's switch and import on the page itself. A shelf's
// list (fonts, looks) is one page class: the files, a swipe deleting one, Import… at the bottom, and for a
// look a tap offering to export it to Files.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/AudioEffects/AudioEffectsPage.h"
#import "Shared/Workshop/Workshop.h"
#import "Library.h"
#import "SGLibraryStore.h"

static void tell(UIViewController *owner, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [(owner ?: SGTopController()) presentViewController:alert animated:YES completion:nil];
}

#pragma mark - the picker

// Presents a document picker and hands what was picked to a block; keeps itself alive until the picker is done.
@interface SGLibraryPicker : NSObject <UIDocumentPickerDelegate>
+ (void)pickTypes:(NSArray<UTType *> *)types from:(UIViewController *)owner then:(void (^)(NSURL *url))picked;
+ (void)exportURL:(NSURL *)url from:(UIViewController *)owner;
@end

static NSMutableSet<SGLibraryPicker *> *sg_pickers;

@implementation SGLibraryPicker {
    void (^_picked)(NSURL *url);
}

+ (void)pickTypes:(NSArray<UTType *> *)types from:(UIViewController *)owner then:(void (^)(NSURL *url))picked {
    SGLibraryPicker *me = [SGLibraryPicker new];
    me->_picked = [picked copy];
    if (!sg_pickers) sg_pickers = [NSMutableSet set];
    [sg_pickers addObject:me];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = me;
    [owner presentViewController:picker animated:YES completion:nil];
}

+ (void)exportURL:(NSURL *)url from:(UIViewController *)owner {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[url] asCopy:YES];
    [owner presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    void (^picked)(NSURL *) = _picked;
    // The picker is still dismissing here, and anything presented now is refused: one turn later.
    if (url && picked) dispatch_async(dispatch_get_main_queue(), ^{ picked(url); });
    [sg_pickers removeObject:self];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker {
    [sg_pickers removeObject:self];
}

@end

#pragma mark - a shelf's list

typedef NS_ENUM(NSInteger, SGLibraryShelf) {
    SGLibraryShelfFonts,
    SGLibraryShelfLooks,
};

@interface SGLibraryShelfPage : SGPage
- (instancetype)initWithShelf:(SGLibraryShelf)shelf;
@end

@implementation SGLibraryShelfPage {
    SGLibraryShelf _shelf;
    NSArray<NSString *> *_items;   // font files, or look names
    UIView *_footer;
}

- (instancetype)initWithShelf:(SGLibraryShelf)shelf {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _shelf = shelf;
    self.title = shelf == SGLibraryShelfFonts ? @"Fonts" : @"Visualizer looks";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _footer = SGNote(_shelf == SGLibraryShelfFonts
        ? @"Fonts are offered to the redesign's lyrics by family, under Lyrics > Font. Swipe left on one to delete it."
        : @"A look is a small JSON file the visualizer saves and reads. Tap one to export it to Files; swipe left to delete it.");
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    _items = _shelf == SGLibraryShelfFonts ? SGLibraryFontFiles() : SGLibraryLookNames();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 2;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? MAX((NSInteger)_items.count, 1) : 1;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? CGFLOAT_MIN : SGSectionGap;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 1) {
        UITableViewCell *cell = SGDequeueCell(table, @"import");
        SGFillCell(cell, @"Import…", _shelf == SGLibraryShelfFonts ? @"A .ttf or .otf file from Files" : @"A .json file from Files", nil, nil);
        UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
        content.image = SGTileImage(@"square.and.arrow.down");
        content.imageToTextPadding = 14;
        cell.contentConfiguration = content;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.separatorInset = UIEdgeInsetsMake(0, 58, 0, 0);
        return cell;
    }
    UITableViewCell *cell = SGDequeueCell(table, @"item");
    if (!_items.count) {
        SGFillCell(cell, _shelf == SGLibraryShelfFonts ? @"No fonts yet" : @"No looks yet", nil, SGGrey(), nil);
        return cell;
    }
    NSString *item = _items[(NSUInteger)path.row];
    if (_shelf == SGLibraryShelfFonts) {
        NSArray<NSString *> *families = SGLibraryFontFamiliesOf(item);
        SGFillCell(cell, families.count ? [families componentsJoinedByString:@", "] : item, families.count ? item : @"Not readable", nil, @"textformat");
        // The family's own face on its row, where UIFont has it.
        NSString *family = families.firstObject;
        if (family && [UIFont fontNamesForFamilyName:family].count) {
            UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
            UIFontDescriptor *descriptor = [UIFontDescriptor fontDescriptorWithFontAttributes:@{UIFontDescriptorFamilyAttribute: family}];
            content.textProperties.font = [UIFont fontWithDescriptor:descriptor size:SGTitleFont().pointSize + 2];
            cell.contentConfiguration = content;
        }
    } else {
        SGFillCell(cell, item, nil, nil, @"waveform");
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    return path.section == 1 || (_shelf == SGLibraryShelfLooks && _items.count);
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == 1) {
        [self importFile];
        return;
    }
    if (_shelf != SGLibraryShelfLooks || !_items.count) return;
    NSString *name = _items[(NSUInteger)path.row];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Export to Files…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSURL *url = SGLibraryLookURL(name);
        if (url) [SGLibraryPicker exportURL:url from:self];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self deleteItem:name at:path];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    popover.sourceView = [table cellForRowAtIndexPath:path] ?: table;
    popover.sourceRect = popover.sourceView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != 0 || !_items.count) return nil;
    NSString *item = _items[(NSUInteger)path.row];
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            [self deleteItem:item at:path];
            done(YES);
        }];
    delete.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

- (void)deleteItem:(NSString *)item at:(NSIndexPath *)path {
    BOOL deleted = _shelf == SGLibraryShelfFonts ? SGLibraryDeleteFont(item) : SGLibraryDeleteLook(item);
    if (!deleted) {
        tell(self, @"Could not delete it", nil);
        return;
    }
    _items = _shelf == SGLibraryShelfFonts ? SGLibraryFontFiles() : SGLibraryLookNames();
    if (_items.count) [self.tableView deleteRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationAutomatic];
    else [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)importFile {
    // .ttf and .otf have public types of their own; a look is any JSON.
    NSArray<UTType *> *types = _shelf == SGLibraryShelfFonts ? @[UTTypeFont, UTTypeData] : @[UTTypeJSON];
    __weak SGLibraryShelfPage *weakSelf = self;
    [SGLibraryPicker pickTypes:types from:self then:^(NSURL *url) {
        SGLibraryShelfPage *me = weakSelf;
        if (!me) return;
        NSError *error = nil;
        NSString *name = me->_shelf == SGLibraryShelfFonts ? SGLibraryImportFont(url, &error) : SGLibraryImportLook(url, &error);
        if (!name) {
            tell(me, @"Could not import it", error.localizedDescription);
            return;
        }
        [me reload];
    }];
}

@end

#pragma mark - the page

// "Custom · 467 MB", "None imported".
static NSString *customModelStatus(void) {
    if (!SGLibraryHasCustomSingModel()) return @"None imported";
    int64_t bytes = SGLibraryCustomSingModelSize();
    NSString *size = bytes >= 1ll << 30 ? [NSString stringWithFormat:@"%.1f GB", bytes / (double)(1ll << 30)]
                                       : [NSString stringWithFormat:@"%lld MB", (bytes + (1ll << 19)) >> 20];
    return [@"separator.mlmodelc · " stringByAppendingString:size];
}

// The copy or the unzip of a model takes a while: a plain alert holds the page until it is done.
static void importModel(void) {
    UIViewController *owner = SGTopController();
    [SGLibraryPicker pickTypes:@[UTTypeFolder, UTTypePackage, UTTypeZIP] from:owner then:^(NSURL *url) {
        UIAlertController *wait = [UIAlertController alertControllerWithTitle:@"Importing the model…" message:nil preferredStyle:UIAlertControllerStyleAlert];
        UIViewController *top = SGTopController();
        [top presentViewController:wait animated:YES completion:nil];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error = nil;
            BOOL imported = SGLibraryImportSingModel(url, &error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [wait dismissViewControllerAnimated:YES completion:^{
                    if (imported) {
                        // Turning the switch on with the import is what anyone importing a model wants.
                        SGSetEnabled(SGKeySingCustomModel, YES);
                        [NSNotificationCenter.defaultCenter postNotificationName:SGLibrarySingModelDidChangeNotification object:nil];
                    } else {
                        tell(nil, @"Could not import the model", error.localizedDescription);
                    }
                }];
            });
        });
    }];
}

UIViewController *SGLibraryPage(void) {
    SGModRow *fonts = SGWithSymbol(SGPageRow(@"Fonts", ^UIViewController *{ return [[SGLibraryShelfPage alloc] initWithShelf:SGLibraryShelfFonts]; }), @"textformat");
    fonts.value = ^NSString *{ return @(SGLibraryFontFiles().count).stringValue; };
    SGModRow *looks = SGWithSymbol(SGPageRow(@"Visualizer looks", ^UIViewController *{ return [[SGLibraryShelfPage alloc] initWithShelf:SGLibraryShelfLooks]; }), @"waveform");
    looks.value = ^NSString *{ return @(SGLibraryLookNames().count).stringValue; };

    // The audio effects' own libraries, as their rows on the Audio effects page open them.
    SGModRow *impulses = SGWithSymbol(SGPageRow(@"Impulse responses", ^UIViewController *{ return SGDSPLibraryPage(SGDSPFileImpulseResponse); }), @"waveform.path");
    impulses.value = ^NSString *{ return SGDSPChosenFile(SGDSPFileImpulseResponse); };
    SGModRow *ddc = SGWithSymbol(SGPageRow(@"Headphone corrections", ^UIViewController *{ return SGDSPLibraryPage(SGDSPFileDDC); }), @"headphones");
    ddc.value = ^NSString *{ return SGDSPChosenFile(SGDSPFileDDC); };
    SGModRow *scripts = SGWithSymbol(SGPageRow(@"Liveprog scripts", ^UIViewController *{ return SGDSPLibraryPage(SGDSPFileLiveprog); }), @"curlybraces");
    scripts.value = ^NSString *{ return SGDSPChosenFile(SGDSPFileLiveprog); };
    SGModRow *graphicEq = SGWithSymbol(SGPageRow(@"Graphic EQ", ^UIViewController *{ return SGDSPGraphicEqPage(); }), @"slider.horizontal.3");

    SGModRow *useCustom = SGOptionRow(@"Use custom model", @"Sing runs the imported model instead of the downloaded one", SGKeySingCustomModel);
    useCustom.changed = ^(BOOL on) { [NSNotificationCenter.defaultCenter postNotificationName:SGLibrarySingModelDidChangeNotification object:nil]; };
    SGModRow *model = SGStatActionRow(@"Import model…", @"A separator.mlmodelc folder, or a .zip holding one", ^NSString *{ return customModelStatus(); }, ^{ importModel(); });
    model.refreshOn = SGLibrarySingModelDidChangeNotification;
    SGModRow *remove = SGActionRow(@"Remove custom model", nil, ^{
        SGLibraryRemoveCustomSingModel();
        SGSetEnabled(SGKeySingCustomModel, NO);
    });
    remove.color = SGRed();
    remove.visible = ^BOOL { return SGLibraryHasCustomSingModel(); };

    NSArray<SGModSection *> *sections = @[
        SGNotedSection(@"Workshop", @[SGWithSymbol(SGPageRow(@"Workshop", ^UIViewController *{ return SGWorkshopPageController(); }), @"shippingbox")],
                       @"Looks, equalizer settings and GraphicEQ curves to download: data files only, checked before they are installed."),
        SGNotedSection(@"Fonts", @[fonts], @"Font files you bring in, for the redesign's lyrics."),
        SGNotedSection(@"Audio presets & headphone corrections", @[impulses, ddc, scripts, graphicEq],
                       @"The same libraries the Audio effects page uses: impulse responses for the convolver, ViPER DDC files, Liveprog scripts, and the GraphicEQ text."),
        SGNotedSection(@"Visualizer", @[looks], @"Looks the visualizer saved, to export, import and keep."),
        SGNotedSection(@"Sing voice model", @[useCustom, model, remove],
                       @"A compiled Core ML separator of your own, in place of the downloaded one. It has to take the same input as Sing's model; "
                       "one that does not fails to load when Sing starts. Nothing is downloaded here."),
    ];
    return [[SGModPage alloc] initWithTitle:@"Library" intro:@"Everything here comes from your own files in Files. Nothing is downloaded unless you open the Workshop." sections:sections footer:nil];
}
