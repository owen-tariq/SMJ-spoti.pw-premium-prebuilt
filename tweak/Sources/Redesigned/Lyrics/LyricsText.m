// What a line shows besides its words, as stored: the two switches of the lyrics menu and the order of
// sizes of the Lyrics page (LyricsText.h). The page itself is LyricsTextSettings.m.
#import "Core/SGCore.h"
#import "LyricsText.h"

NSNotificationName const SGRLyricsTextDidChangeNotification = @"spotifyglass.redesign.lyricsTextDidChange";

static NSString *keyOf(SGRLyricsText text) {
    switch (text) {
        case SGRLyricsTextLyrics: return @"lyrics";
        case SGRLyricsTextPronunciation: return @"pronunciation";
        case SGRLyricsTextTranslation: return @"translation";
    }
    return nil;
}

NSString *SGRLyricsTextName(SGRLyricsText text) {
    switch (text) {
        case SGRLyricsTextLyrics: return @"Lyrics";
        case SGRLyricsTextPronunciation: return @"Pronunciation";
        case SGRLyricsTextTranslation: return @"Translation";
    }
    return nil;
}

// A stored order is taken only as a full set of the three; anything else is Apple Music's.
NSArray<NSNumber *> *SGRLyricsTextOrder(void) {
    NSArray<NSNumber *> *fallback = @[@(SGRLyricsTextLyrics), @(SGRLyricsTextPronunciation), @(SGRLyricsTextTranslation)];
    id stored = [NSUserDefaults.standardUserDefaults arrayForKey:SGRKeyLyricsTextOrder];
    if (![stored isKindOfClass:NSArray.class] || [stored count] != fallback.count) return fallback;
    NSMutableArray<NSNumber *> *order = [NSMutableArray array];
    for (id key in stored) {
        for (NSNumber *text in fallback) {
            if ([key isEqual:keyOf(text.integerValue)] && ![order containsObject:text]) [order addObject:text];
        }
    }
    return order.count == fallback.count ? order : fallback;
}

void SGRSetLyricsTextOrder(NSArray<NSNumber *> *order) {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSNumber *text in order) [keys addObject:keyOf(text.integerValue)];
    [NSUserDefaults.standardUserDefaults setObject:keys forKey:SGRKeyLyricsTextOrder];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsTextDidChangeNotification object:nil];
}

void SGRSetLyricsTextShown(SGRLyricsText text, BOOL shown) {
    SGSetEnabled(text == SGRLyricsTextTranslation ? SGRKeyLyricsTranslation : SGRKeyLyricsPronunciation, shown);
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsTextDidChangeNotification object:nil];
}

#pragma mark - the font

NSString *SGRLyricsFontFamily(void) {
    NSString *family = [NSUserDefaults.standardUserDefaults stringForKey:SGRKeyLyricsFontFamily];
    return family.length ? family : nil;
}

void SGRSetLyricsFontFamily(NSString *family) {
    if (family.length) [NSUserDefaults.standardUserDefaults setObject:family forKey:SGRKeyLyricsFontFamily];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRKeyLyricsFontFamily];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsTextDidChangeNotification object:nil];
}

// The family is asked for by name through a descriptor, so the weight picks the nearest face the family has
// (a single-face family answers that face). A family UIFont has no faces for is the system font: the Library
// registered it once, and the file has gone since.
UIFont *SGRLyricsFont(CGFloat size, UIFontWeight weight) {
    NSString *family = SGRLyricsFontFamily();
    if (!family || ![UIFont fontNamesForFamilyName:family].count) return [UIFont systemFontOfSize:size weight:weight];
    UIFontDescriptor *descriptor = [UIFontDescriptor fontDescriptorWithFontAttributes:@{
        UIFontDescriptorFamilyAttribute: family,
        UIFontDescriptorTraitsAttribute: @{UIFontWeightTrait: @(weight)},
    }];
    return [UIFont fontWithDescriptor:descriptor size:size] ?: [UIFont systemFontOfSize:size weight:weight];
}
