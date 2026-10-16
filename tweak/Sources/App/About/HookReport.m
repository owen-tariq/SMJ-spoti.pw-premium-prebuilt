// SPDX-License-Identifier: MIT
// Hook report (Mod Settings > Mod > Hook report): every Spotify class the mod's %ctors asked for through
// SGRequireClasses (Core/SGLog.h), found or not, under the Spotify and mod versions. A feature whose class is
// missing has its hooks inactive, so on a Spotify other than the supported one this page says exactly which
// parts broke, and Copy report puts the same as plain text on the pasteboard for an issue.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"

static NSString *spotifyVersion(void) {
    id version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [version isKindOfClass:NSString.class] ? version : @"unknown";
}

// Missing first, each group in the order asked. A class asked for by two files is listed once.
static NSArray<NSDictionary *> *sortedReport(NSUInteger *found, NSUInteger *missing) {
    NSMutableArray<NSDictionary *> *missingRows = [NSMutableArray array], *foundRows = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary *entry in SGRequiredClassReport()) {
        NSString *name = entry[@"name"];
        if (![name isKindOfClass:NSString.class] || [seen containsObject:name]) continue;
        [seen addObject:name];
        [([entry[@"found"] boolValue] ? foundRows : missingRows) addObject:entry];
    }
    if (found) *found = foundRows.count;
    if (missing) *missing = missingRows.count;
    return [missingRows arrayByAddingObjectsFromArray:foundRows];
}

static NSString *requestedBy(NSDictionary *entry) {
    id file = entry[@"requestedBy"];
    return [file isKindOfClass:NSString.class] ? file : nil;
}

static NSString *reportText(void) {
    NSUInteger found = 0, missing = 0;
    NSArray<NSDictionary *> *entries = sortedReport(&found, &missing);
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"spoti.pw hook report\nSpotify %@ (made for %@)\nMod %s\niOS %@\n%lu classes found, %lu missing\n\n",
        spotifyVersion(), SGSupportedSpotifyVersion, SG_VERSION, UIDevice.currentDevice.systemVersion, (unsigned long)found, (unsigned long)missing];
    for (NSDictionary *entry in entries) {
        NSString *file = requestedBy(entry);
        [text appendFormat:@"%@ %@%@\n", [entry[@"found"] boolValue] ? @"[ok]" : @"[missing]", entry[@"name"],
            file ? [NSString stringWithFormat:@" (%@)", file] : @""];
    }
    return text;
}

static void copyReport(void) {
    UIPasteboard.generalPasteboard.string = reportText();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Report copied"
                                                                   message:@"Paste it into a GitHub issue or a Discord message along with what is not working."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static SGModRow *classRow(NSDictionary *entry) {
    BOOL found = [entry[@"found"] boolValue];
    SGModRow *row = [SGModRow new];
    row.title = entry[@"name"];
    row.subtitle = requestedBy(entry);
    row.symbol = found ? @"checkmark.circle" : @"xmark.circle";
    row.color = found ? SGGreen() : SGRed();
    return row;
}

UIViewController *SGHookReportPage(void) {
    NSUInteger found = 0, missing = 0;
    NSArray<NSDictionary *> *entries = sortedReport(&found, &missing);
    NSString *spotify = spotifyVersion();
    NSMutableArray<SGModSection *> *sections = [NSMutableArray array];
    SGModRow *spotifyRow = SGStatRow(@"Spotify", ^NSString *{ return spotify; });
    if (![spotify isEqualToString:SGSupportedSpotifyVersion]) {
        spotifyRow.subtitle = [NSString stringWithFormat:@"The mod is made for %@", SGSupportedSpotifyVersion];
        spotifyRow.color = SGRed();
    }
    [sections addObject:SGSection(nil, @[
        spotifyRow,
        SGStatRow(@"Mod", ^NSString *{ return @(SG_VERSION); }),
        SGStatRow(@"Classes found", ^NSString *{ return @(found).stringValue; }),
        SGStatRow(@"Classes missing", ^NSString *{ return @(missing).stringValue; }),
        SGWithSymbol(SGActionRow(@"Copy report", @"Plain text, for an issue", ^{ copyReport(); }), @"doc.on.doc"),
    ])];
    if (!entries.count) {
        [sections addObject:SGNotedSection(nil, @[SGStatRow(@"No classes asked for yet", ^NSString *{ return @""; })],
                                           @"The features ask for their classes as Spotify starts.")];
    } else {
        NSMutableArray<SGModRow *> *missingRows = [NSMutableArray array], *foundRows = [NSMutableArray array];
        for (NSDictionary *entry in entries) [([entry[@"found"] boolValue] ? foundRows : missingRows) addObject:classRow(entry)];
        if (missingRows.count) [sections addObject:SGNotedSection(@"Missing", missingRows, @"The hooks on these classes are inactive: the feature under each file name does nothing or only part of its work.")];
        if (foundRows.count) [sections addObject:SGSection(@"Found", foundRows)];
    }
    NSString *intro = missing ? [NSString stringWithFormat:@"%lu of the classes the mod hooks are not in this Spotify.", (unsigned long)missing]
                              : @"Every class the mod hooks is in this Spotify.";
    return [[SGModPage alloc] initWithTitle:@"Hook report" intro:intro sections:sections footer:nil];
}
