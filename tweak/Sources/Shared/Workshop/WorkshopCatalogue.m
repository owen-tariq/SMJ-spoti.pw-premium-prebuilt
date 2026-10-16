// SPDX-License-Identifier: MIT
// The Workshop's fetch, validation, install and installed index (WorkshopCatalogue.h).
#import <CommonCrypto/CommonDigest.h>
#import <os/lock.h>
#import "Core/SGCore.h"
#import "Shared/AudioEffects/AudioEffects.h"
#import "Shared/AudioEffects/SGDSPFilters.h"
#import "Shared/Library/SGLibraryStore.h"
#import "WorkshopCatalogue.h"
#import "WorkshopValidate.h"

NSErrorDomain const SGWorkshopErrorDomain = @"spotifyglass.workshop";

static NSString *const kDefaultBase = @"https://raw.githubusercontent.com/owen-tariq/SMJ-spoti.pw-premium-prebuilt/crack/workshop/";

static NSError *failure(SGWorkshopErrorCode code, NSString *message) {
    return [NSError errorWithDomain:SGWorkshopErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

#pragma mark - the items

@implementation SGWorkshopItem
- (instancetype)initWithType:(SGWorkshopType)type id:(NSString *)itemID name:(NSString *)name author:(NSString *)author
                     summary:(NSString *)summary file:(NSString *)file sha:(NSString *)sha size:(NSUInteger)size {
    if (!(self = [super init])) return nil;
    _type = type; _itemID = [itemID copy]; _name = [name copy]; _author = [author copy]; _summary = [summary copy];
    _file = [file copy]; _sha256 = [sha.lowercaseString copy]; _size = size;
    return self;
}
@end

static NSString *extensionOf(SGWorkshopType type) { return type == SGWorkshopTypeCorrection ? @".txt" : @".json"; }

static BOOL typeFromString(NSString *s, SGWorkshopType *type) {
    if ([s isEqualToString:@"look"]) *type = SGWorkshopTypeLook;
    else if ([s isEqualToString:@"eq"]) *type = SGWorkshopTypeEQ;
    else if ([s isEqualToString:@"correction"]) *type = SGWorkshopTypeCorrection;
    else return NO;
    return YES;
}

static NSString *textOf(id value, NSUInteger limit) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *s = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return s.length && s.length <= limit ? s : nil;
}

#pragma mark - the address

NSString *SGWorkshopDefaultBaseURL(void) { return kDefaultBase; }

NSString *SGWorkshopBaseURL(void) {
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyWorkshopBaseURL];
    if (!stored.length || !sg_ws_base_url_ok(stored.UTF8String)) return kDefaultBase;
    return [stored hasSuffix:@"/"] ? stored : [stored stringByAppendingString:@"/"];
}

#pragma mark - the address (continued)

NSString *SGWorkshopSetBaseURL(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyWorkshopBaseURL];
        return nil;
    }
    if (!sg_ws_base_url_ok(trimmed.UTF8String)) return @"Use an https address with no query, up to 512 characters.";
    [NSUserDefaults.standardUserDefaults setObject:trimmed forKey:SGKeyWorkshopBaseURL];
    return nil;
}

BOOL SGWorkshopUsesDefaultBaseURL(void) {
    return ![NSUserDefaults.standardUserDefaults stringForKey:SGKeyWorkshopBaseURL].length;
}

#pragma mark - the index

NSArray<SGWorkshopItem *> *SGWorkshopParseIndex(NSData *data, NSUInteger *skipped, NSError **error) {
    if (skipped) *skipped = 0;
    if (!sg_ws_size_ok((long long)data.length, SG_WS_MAX_INDEX_BYTES)) {
        if (error) *error = failure(SGWorkshopErrorUnreadable, @"The catalogue could not be read.");
        return nil;
    }
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *list = [root isKindOfClass:NSDictionary.class] ? ((NSDictionary *)root)[@"items"] : nil;
    id version = [root isKindOfClass:NSDictionary.class] ? ((NSDictionary *)root)[@"version"] : nil;
    if (![version isKindOfClass:NSNumber.class] || [version integerValue] != 1 || ![list isKindOfClass:NSArray.class] || list.count > SG_WS_MAX_ITEMS) {
        if (error) *error = failure(SGWorkshopErrorUnreadable, @"The catalogue could not be read.");
        return nil;
    }
    NSMutableArray<SGWorkshopItem *> *items = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSUInteger dropped = 0;
    for (id entry in list) {
        NSDictionary *d = [entry isKindOfClass:NSDictionary.class] ? entry : nil;
        SGWorkshopType type = SGWorkshopTypeLook;
        NSString *typeName = textOf(d[@"type"], 16);
        NSString *itemID = textOf(d[@"id"], 64), *name = textOf(d[@"name"], 60), *file = textOf(d[@"file"], 128), *sha = textOf(d[@"sha256"], 64);
        NSNumber *size = [d[@"size"] isKindOfClass:NSNumber.class] ? d[@"size"] : nil;
        BOOL good = d && typeName && typeFromString(typeName, &type) && ![name containsString:@"/"] && ![name hasPrefix:@"."] && itemID && name && file && sha && size && !isnan(size.doubleValue) &&
            sg_ws_id_ok(itemID.UTF8String) && sg_ws_file_ok(file.UTF8String, extensionOf(type).UTF8String) &&
            sg_ws_sha_ok(sha.UTF8String) && sg_ws_size_ok(size.longLongValue, SG_WS_MAX_FILE_BYTES) && ![seen containsObject:itemID];
        if (!good) { dropped++; continue; }
        [seen addObject:itemID];
        [items addObject:[[SGWorkshopItem alloc] initWithType:type id:itemID name:name author:textOf(d[@"author"], 40) ?: @"Unknown"
                                                      summary:textOf(d[@"summary"], 200) ?: @"" file:file sha:sha size:(NSUInteger)size.longLongValue]];
    }
    if (skipped) *skipped = dropped;
    return items;
}

#pragma mark - checking a file

static BOOL colourListOK(id value) {
    if (![value isKindOfClass:NSArray.class] || [(NSArray *)value count] > SG_WS_MAX_COLOURS) return NO;
    for (id c in (NSArray *)value) if (![c isKindOfClass:NSString.class] || !sg_ws_colour_ok([(NSString *)c UTF8String])) return NO;
    return YES;
}

static BOOL numberIn(id value, bool (*ok)(double)) {
    return [value isKindOfClass:NSNumber.class] && ok([value doubleValue]);
}

BOOL SGWorkshopValidatePayload(SGWorkshopItem *item, NSData *data, id *payload, NSError **error) {
    NSError *refused = failure(SGWorkshopErrorRefused, [NSString stringWithFormat:@"“%@” failed a safety check and was not installed.", item.name]);
    if (!item || !data || data.length != item.size || !sg_ws_size_ok((long long)data.length, SG_WS_MAX_FILE_BYTES)) { if (error) *error = refused; return NO; }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    if (!sg_ws_hash_matches(item.sha256.UTF8String, digest)) { if (error) *error = refused; return NO; }

    if (item.type == SGWorkshopTypeCorrection) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        SGDSPGraphicCurve curve;
        if (!text.length || !sg_ws_graphiceq_ok(text.UTF8String) || !SGDSPParseGraphicEq(text.UTF8String, &curve)) { if (error) *error = refused; return NO; }
        if (payload) *payload = text;
        return YES;
    }
    NSDictionary *d = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![d isKindOfClass:NSDictionary.class]) { if (error) *error = refused; return NO; }
    if (item.type == SGWorkshopTypeEQ) {
        NSArray *gains = d[@"gains"];
        BOOL good = d.count == 1 && [gains isKindOfClass:NSArray.class] && gains.count == SG_WS_EQ_BANDS;
        for (id g in good ? gains : @[]) if (!numberIn(g, sg_ws_gain_ok)) { good = NO; break; }
        if (!good) { if (error) *error = refused; return NO; }
        if (payload) *payload = gains;
        return YES;
    }
    NSSet *known = [NSSet setWithObjects:@"intensity", @"motion", @"glowCount", @"colours", @"colors", nil];
    BOOL good = d.count > 0;
    for (NSString *key in d) {
        id v = d[key];
        if (![known containsObject:key]) good = NO;
        else if ([key isEqualToString:@"intensity"]) good = good && numberIn(v, sg_ws_intensity_ok);
        else if ([key isEqualToString:@"motion"]) good = good && numberIn(v, sg_ws_motion_ok);
        else if ([key isEqualToString:@"glowCount"]) good = good && numberIn(v, sg_ws_glow_ok);
        else good = good && colourListOK(v);
    }
    if (!good) { if (error) *error = refused; return NO; }
    if (payload) *payload = d;
    return YES;
}

#pragma mark - the network

// One request: https only (a redirect elsewhere is refused), a 200, the body held to `cap` as it arrives, no cookies and
// no cache. The session keeps this object as its delegate until it is invalidated, which is when the task ends.
@interface SGWorkshopFetch : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, copy) void (^done)(NSData *data, NSError *error);
@property (nonatomic) NSUInteger cap;
@property (nonatomic) NSMutableData *body;
@property (nonatomic) NSError *failure;
@end

@implementation SGWorkshopFetch
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
    if (!http || http.statusCode != 200 || ![http.URL.scheme.lowercaseString isEqualToString:@"https"] ||
        (response.expectedContentLength > 0 && (unsigned long long)response.expectedContentLength > self.cap)) {
        self.failure = failure(SGWorkshopErrorUnreadable, @"The catalogue could not be read.");
        completionHandler(NSURLSessionResponseCancel);
        return;
    }
    completionHandler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (!self.body) self.body = [NSMutableData data];
    if (self.body.length + data.length > self.cap) {
        self.failure = failure(SGWorkshopErrorRefused, @"A file was larger than the Workshop allows and was not installed.");
        [task cancel];
        return;
    }
    [self.body appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    if (![request.URL.scheme.lowercaseString isEqualToString:@"https"]) {
        self.failure = failure(SGWorkshopErrorRefused, @"The catalogue redirected somewhere that is not https and was not followed.");
        completionHandler(nil);
        return;
    }
    completionHandler(request);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSError *result = self.failure;
    if (!result && error) {
        BOOL offline = error.code == NSURLErrorNotConnectedToInternet || error.code == NSURLErrorNetworkConnectionLost || error.code == NSURLErrorDataNotAllowed;
        result = failure(offline ? SGWorkshopErrorOffline : SGWorkshopErrorNetwork, offline ? @"You're offline." : @"The catalogue could not be reached.");
    }
    NSData *data = result ? nil : (self.body ?: [NSData data]);
    void (^done)(NSData *, NSError *) = self.done;
    self.done = nil;
    [session finishTasksAndInvalidate];
    dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(data, result); });
}
@end

static void fetchURL(NSString *address, NSUInteger cap, void (^done)(NSData *data, NSError *error)) {
    NSURL *url = sg_ws_https_ok(address.UTF8String) ? [NSURL URLWithString:address] : nil;
    if (!url) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, failure(SGWorkshopErrorRefused, @"That address can't be used.")); });
        return;
    }
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.HTTPCookieStorage = nil;
    config.HTTPShouldSetCookies = NO;
    config.URLCache = nil;
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.timeoutIntervalForRequest = 20;
    config.timeoutIntervalForResource = 40;
    SGWorkshopFetch *fetch = [SGWorkshopFetch new];
    fetch.cap = cap;
    fetch.done = done;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:fetch delegateQueue:nil];
    [[session dataTaskWithURL:url] resume];
}

void SGWorkshopFetchIndex(void (^done)(NSArray<SGWorkshopItem *> *items, NSUInteger skipped, NSError *error)) {
    fetchURL([SGWorkshopBaseURL() stringByAppendingString:@"index.json"], SG_WS_MAX_INDEX_BYTES, ^(NSData *data, NSError *error) {
        if (error) { done(nil, 0, error); return; }
        NSUInteger skipped = 0;
        NSError *parseError = nil;
        NSArray *items = SGWorkshopParseIndex(data, &skipped, &parseError);
        done(items, skipped, items ? nil : parseError);
    });
}

#pragma mark - what is installed

static NSURL *libraryFolder(void) {
    NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [base URLByAppendingPathComponent:@"spoti.pw/Library" isDirectory:YES];
}
static NSURL *shelfFolder(void) { return [libraryFolder() URLByAppendingPathComponent:@"Workshop" isDirectory:YES]; }
static NSString *shelfFile(SGWorkshopItem *item) {
    NSString *suffix = item.type == SGWorkshopTypeEQ ? @".eq.json" : @".geq.txt";
    return [shelfFolder() URLByAppendingPathComponent:[item.itemID stringByAppendingString:suffix]].path;
}
static NSURL *installedURL(void) { return [libraryFolder() URLByAppendingPathComponent:@"workshop-installed.plist"]; }

static NSMutableDictionary<NSString *, NSDictionary *> *readInstalled(void) {
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfURL:installedURL()];
    return d ?: [NSMutableDictionary dictionary];
}
static void writeInstalled(NSDictionary *d) {
    [NSFileManager.defaultManager createDirectoryAtURL:libraryFolder() withIntermediateDirectories:YES attributes:nil error:nil];
    [d writeToURL:installedURL() atomically:YES];
}

SGWorkshopState SGWorkshopStateOf(SGWorkshopItem *item) {
    NSDictionary *entry;
    @synchronized (SGWorkshopItem.class) { entry = readInstalled()[item.itemID]; }
    if (![entry isKindOfClass:NSDictionary.class]) return SGWorkshopStateAvailable;
    BOOL present = item.type == SGWorkshopTypeLook ? [SGLibraryLookNames() containsObject:entry[@"name"] ?: item.name]
                                                   : [NSFileManager.defaultManager fileExistsAtPath:shelfFile(item)];
    if (!present) return SGWorkshopStateAvailable;
    return [entry[@"sha"] isEqual:item.sha256] ? SGWorkshopStateInstalled : SGWorkshopStateUpdate;
}

BOOL SGWorkshopWouldReplaceOwnLook(SGWorkshopItem *item) {
    if (item.type != SGWorkshopTypeLook || ![SGLibraryLookNames() containsObject:item.name]) return NO;
    @synchronized (SGWorkshopItem.class) { return readInstalled()[item.itemID] == nil; }
}

void SGWorkshopInstall(SGWorkshopItem *item, void (^done)(NSError *error)) {
    fetchURL([SGWorkshopBaseURL() stringByAppendingString:item.file], SG_WS_MAX_FILE_BYTES, ^(NSData *data, NSError *error) {
        if (error) { done(error); return; }
        id payload = nil;
        NSError *checked = nil;
        if (!SGWorkshopValidatePayload(item, data, &payload, &checked)) { done(checked); return; }
        NSError *stored = nil;
        if (item.type == SGWorkshopTypeLook) {
            if (!SGLibrarySaveLook(item.name, payload, &stored)) {
                done(stored ?: failure(SGWorkshopErrorRefused, @"The look could not be saved."));
                return;
            }
        } else {
            NSFileManager *fm = NSFileManager.defaultManager;
            if (![fm createDirectoryAtURL:shelfFolder() withIntermediateDirectories:YES attributes:nil error:&stored] ||
                ![data writeToFile:shelfFile(item) options:NSDataWritingAtomic error:&stored]) {
                done(stored ?: failure(SGWorkshopErrorRefused, @"The file could not be saved."));
                return;
            }
        }
        @synchronized (SGWorkshopItem.class) {
            NSMutableDictionary *installed = readInstalled();
            installed[item.itemID] = @{@"sha": item.sha256, @"name": item.name, @"type": @(item.type)};
            writeInstalled(installed);
        }
        done(nil);
    });
}

BOOL SGWorkshopRemove(SGWorkshopItem *item) {
    NSDictionary *entry;
    @synchronized (SGWorkshopItem.class) { entry = readInstalled()[item.itemID]; }
    BOOL ok = YES;
    if (item.type == SGWorkshopTypeLook) ok = SGLibraryDeleteLook(entry[@"name"] ?: item.name);
    else if ([NSFileManager.defaultManager fileExistsAtPath:shelfFile(item)]) ok = [NSFileManager.defaultManager removeItemAtPath:shelfFile(item) error:nil];
    if (ok) @synchronized (SGWorkshopItem.class) {
        NSMutableDictionary *installed = readInstalled();
        [installed removeObjectForKey:item.itemID];
        writeInstalled(installed);
    }
    return ok;
}

BOOL SGWorkshopUse(SGWorkshopItem *item, NSError **error) {
    if (item.type == SGWorkshopTypeLook) return YES;   // the visualizer's Look picker uses it
    SGWorkshopState state = SGWorkshopStateOf(item);
    if (state == SGWorkshopStateAvailable) {
        if (error) *error = failure(SGWorkshopErrorRefused, @"The file is no longer installed.");
        return NO;
    }
    if (state == SGWorkshopStateUpdate) {
        if (error) *error = failure(SGWorkshopErrorRefused, @"An update is available: install it first.");
        return NO;
    }
    // The stored bytes go through the same checks again before they reach the sound.
    NSData *data = [NSData dataWithContentsOfFile:shelfFile(item)];
    id payload = nil;
    if (!SGWorkshopValidatePayload(item, data, &payload, error)) return NO;
    if (item.type == SGWorkshopTypeEQ) {
        SGDSPSetGains(SGKeyDSPEqualizerGains, payload);
        SGDSPSetSwitch(SGKeyDSPEqualizer, YES);
    } else {
        SGDSPSetString(SGKeyDSPGraphicEqNodes, payload);
        SGDSPSetSwitch(SGKeyDSPGraphicEq, YES);
    }
    return YES;
}
