// SPDX-License-Identifier: MIT
// Mod Settings > Library > Workshop: the catalogue's items by type, each with its state (Install, Installed,
// Update available), one tap to install, a tap on an installed one to use or remove it. The catalogue's
// address is changed or reset from the first section. WorkshopCatalogue.h has the rules a download passes.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "WorkshopCatalogue.h"
#import "Workshop.h"

static void tell(UIViewController *owner, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [(owner ?: SGTopController()) presentViewController:alert animated:YES completion:nil];
}

typedef NS_ENUM(NSInteger, SGWorkshopRow) {
    SGWorkshopRowStatus,
    SGWorkshopRowRefresh,
    SGWorkshopRowAddress,
    SGWorkshopRowReset,    // only while the address is not the default
};

@interface SGWorkshopPage : SGPage
@end

@implementation SGWorkshopPage {
    NSArray<SGWorkshopItem *> *_items;
    NSArray<NSNumber *> *_types;                 // the types that have items, in display order
    NSError *_error;
    NSUInteger _skipped;
    BOOL _loading, _loaded;
    NSMutableSet<NSString *> *_busy;             // "type:id" being installed
    UIView *_footer;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Workshop";
    _busy = [NSMutableSet set];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _footer = SGNote(@"The Workshop downloads small data files: looks, equalizer settings and GraphicEQ curves. Never code. "
                      "Each file is checked against the catalogue's checksum before it is installed.");
    self.tableView.tableFooterView = _footer;
    UIRefreshControl *refresh = [UIRefreshControl new];
    [refresh addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;
    [self refresh];
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
    [self.tableView reloadData];   // a look deleted from the Library's page reads Install again
}

#pragma mark - loading

- (void)refresh {
    if (_loading) {
        [self.refreshControl endRefreshing];
        return;
    }
    _loading = YES;
    _error = nil;
    [self.tableView reloadData];
    __weak SGWorkshopPage *weak = self;
    SGWorkshopFetchIndex(^(NSArray<SGWorkshopItem *> *items, NSUInteger skipped, NSError *error) {
        SGWorkshopPage *me = weak;
        if (!me) return;
        me->_loading = NO;
        me->_loaded = YES;
        me->_error = error;
        me->_skipped = skipped;
        me->_items = items ?: @[];
        NSMutableArray<NSNumber *> *types = [NSMutableArray array];
        for (NSNumber *type in @[@(SGWorkshopTypeLook), @(SGWorkshopTypeEQ), @(SGWorkshopTypeCorrection)]) {
            for (SGWorkshopItem *item in me->_items) if (item.type == type.integerValue) { [types addObject:type]; break; }
        }
        me->_types = types;
        [me.refreshControl endRefreshing];
        [me.tableView reloadData];
    });
}

- (NSArray<SGWorkshopItem *> *)itemsInSection:(NSInteger)section {
    SGWorkshopType type = (SGWorkshopType)_types[(NSUInteger)section - 1].integerValue;
    NSMutableArray *list = [NSMutableArray array];
    for (SGWorkshopItem *item in _items) if (item.type == type) [list addObject:item];
    return list;
}

static NSString *titleOf(SGWorkshopType type) {
    return type == SGWorkshopTypeLook ? @"Visualizer looks" : type == SGWorkshopTypeEQ ? @"Equalizer presets" : @"Headphone corrections";
}

static NSString *symbolOf(SGWorkshopType type) {
    return type == SGWorkshopTypeLook ? @"waveform" : type == SGWorkshopTypeEQ ? @"slider.horizontal.3" : @"headphones";
}

static NSString *busyKey(SGWorkshopItem *item) { return [NSString stringWithFormat:@"%ld:%@", (long)item.type, item.itemID]; }

#pragma mark - the table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 1 + (NSInteger)_types.count;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return SGWorkshopUsesDefaultBaseURL() ? SGWorkshopRowReset : SGWorkshopRowReset + 1;
    return (NSInteger)[self itemsInSection:section].count;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return section == 0 ? nil : SGSectionHeader(table, titleOf((SGWorkshopType)_types[(NSUInteger)section - 1].integerValue));
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? SGSectionGap : SGSectionHeaderHeight;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (NSString *)statusLine {
    if (_loading) return @"Loading…";
    if (_error) return _error.localizedDescription;
    if (!_loaded) return @"Not loaded";
    NSString *line = _items.count ? [NSString stringWithFormat:@"%lu items", (unsigned long)_items.count] : @"The catalogue is empty";
    return _skipped ? [line stringByAppendingFormat:@" (%lu skipped: failed a check)", (unsigned long)_skipped] : line;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, path.section == 0 ? @"control" : @"item");
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (path.section == 0) {
        switch (path.row) {
        case SGWorkshopRowStatus:
            SGFillCell(cell, @"Catalogue", [self statusLine], _error ? SGRed() : nil, @"shippingbox");
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            if (_loading) {
                UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
                [spinner startAnimating];
                cell.accessoryView = spinner;
            }
            break;
        case SGWorkshopRowRefresh:
            SGFillCell(cell, @"Refresh", @"Read the catalogue again", nil, @"arrow.clockwise");
            break;
        case SGWorkshopRowAddress:
            SGFillCell(cell, @"Catalogue address", SGWorkshopUsesDefaultBaseURL() ? @"Default" : SGWorkshopBaseURL(), nil, @"link");
            break;
        default:
            SGFillCell(cell, @"Reset", @"Back to the default catalogue", nil, @"arrow.uturn.backward");
            break;
        }
        return cell;
    }
    SGWorkshopItem *item = [self itemsInSection:path.section][(NSUInteger)path.row];
    SGFillCell(cell, item.name, [NSString stringWithFormat:@"%@ · %@", item.author, item.summary], nil, symbolOf(item.type));
    UILabel *state = [UILabel new];
    state.font = SGSubtitleFont();
    SGWorkshopState current = SGWorkshopStateOf(item);
    if ([_busy containsObject:busyKey(item)]) {
        state.text = @"Installing…";
        state.textColor = SGGrey();
    } else if (current == SGWorkshopStateInstalled) {
        state.text = @"Installed";
        state.textColor = SGGreen();
    } else if (current == SGWorkshopStateUpdate) {
        state.text = @"Update available";
        state.textColor = SGGreen();
    } else {
        state.text = @"Install";
        state.textColor = UIColor.whiteColor;
    }
    [state sizeToFit];
    cell.accessoryView = state;
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0) {
        if (path.row == SGWorkshopRowRefresh) [self refresh];
        else if (path.row == SGWorkshopRowAddress) [self askAddress];
        else if (path.row == SGWorkshopRowReset) {
            SGWorkshopSetBaseURL(@"");
            [self refresh];
        }
        return;
    }
    SGWorkshopItem *item = [self itemsInSection:path.section][(NSUInteger)path.row];
    if ([_busy containsObject:busyKey(item)]) return;
    SGWorkshopState state = SGWorkshopStateOf(item);
    if (state == SGWorkshopStateInstalled) [self manage:item];
    else [self install:item];
}

#pragma mark - actions

- (void)askAddress {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Catalogue address"
        message:@"The https folder that holds index.json. The default is this project's own workshop folder." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"https://example.com/workshop/";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.spellCheckingType = UITextSpellCheckingTypeNo;
        field.keyboardType = UIKeyboardTypeURL;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    // The alert holds its actions and an action holds its handler, so the handler must not hold the alert.
    __weak UIAlertController *weakAlert = alert;
    UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *problem = SGWorkshopSetBaseURL(weakAlert.textFields.firstObject.text);
        if (problem) { tell(self, @"Catalogue address", problem); return; }
        [self refresh];
    }];
    [alert addAction:save];
    alert.preferredAction = save;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)install:(SGWorkshopItem *)item {
    if (SGWorkshopWouldReplaceOwnLook(item)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Replace your look?"
            message:[NSString stringWithFormat:@"A look called \"%@\" is already in your Library. Installing %@ replaces it.", item.itemID, item.name]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Replace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self download:item];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self download:item];
}

- (void)download:(SGWorkshopItem *)item {
    [_busy addObject:busyKey(item)];
    [self.tableView reloadData];
    __weak SGWorkshopPage *weak = self;
    SGWorkshopInstall(item, ^(NSError *error) {
        SGWorkshopPage *me = weak;
        if (!me) return;
        [me->_busy removeObject:busyKey(item)];
        [me.tableView reloadData];
        if (error) tell(me, error.code == SGWorkshopErrorOffline ? @"You're offline" : @"Not installed", error.localizedDescription);
    });
}

- (void)manage:(SGWorkshopItem *)item {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:item.name message:item.summary preferredStyle:UIAlertControllerStyleActionSheet];
    if (item.type != SGWorkshopTypeLook) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSError *error = nil;
            if (SGWorkshopUse(item, &error)) {
                tell(self, item.name, item.type == SGWorkshopTypeEQ
                     ? @"It is the equalizer's setting now, and the equalizer is on. The effects' master switch is under Audio effects."
                     : @"It is the Graphic EQ's curve now, and the Graphic EQ is on. The effects' master switch is under Audio effects.");
            } else {
                tell(self, @"Not applied", error.localizedDescription);
            }
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if (!SGWorkshopRemove(item)) tell(self, @"Not removed", [NSString stringWithFormat:@"%@ could not be removed.", item.name]);
        [self.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

UIViewController *SGWorkshopPageController(void) {
    return [SGWorkshopPage new];
}
