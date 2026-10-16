// SPDX-License-Identifier: MIT
// The Library's shelves (SGLibraryStore.h): plain files under Application Support, every one put there by
// the user through the page. Nothing here touches the network.
//
// CoreText and libcompression are reached through dlsym rather than linked: the tweak's Makefile links neither,
// and the two calls each needs are not worth a build change (link them and the pointers can go).
#import <dlfcn.h>
#import <stdio.h>
#import <os/lock.h>
#import <compression.h>
#import <CoreText/CoreText.h>
#import "Core/SGCore.h"
#import "Library.h"
#import "SGLibraryStore.h"

NSNotificationName const SGLibraryLooksDidChangeNotification = @"spotifyglass.library.looksChanged";
NSNotificationName const SGLibrarySingModelDidChangeNotification = @"spotifyglass.library.singModelChanged";
NSNotificationName const SGLibraryFontsDidChangeNotification = @"spotifyglass.library.fontsChanged";

static NSString *const SGLibraryErrorDomain = @"spotifyglass.library";

static NSError *libraryError(NSString *message) {
    return [NSError errorWithDomain:SGLibraryErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void postOnMain(NSNotificationName name) {
    dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:name object:nil]; });
}

// Application Support/spoti.pw/<path>, made when first asked for. Kept out of the iCloud backup: what is here
// came from the user's own files and can be brought in again.
static NSString *libraryDirectory(NSString *path) {
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *directory = [[support stringByAppendingPathComponent:@"spoti.pw"] stringByAppendingPathComponent:path];
    os_unfair_lock_lock(&lock);
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory) {
        NSError *error = nil;
        if ([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
            [[NSURL fileURLWithPath:directory] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        } else {
            SGLog(@"library: %@ could not be made: %@", path, error);
        }
    }
    os_unfair_lock_unlock(&lock);
    return directory;
}

// The plain files of a directory with one of the extensions (lowercase, no dot), sorted as Finder sorts.
static NSArray<NSString *> *filesIn(NSString *directory, NSArray<NSString *> *extensions) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil]) {
        if ([name hasPrefix:@"."] || ![extensions containsObject:name.pathExtension.lowercaseString]) continue;
        BOOL isDirectory = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:[directory stringByAppendingPathComponent:name] isDirectory:&isDirectory] && !isDirectory)
            [names addObject:name];
    }
    return [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

// A name that stays inside its directory: one path component, not hidden.
static BOOL plainName(NSString *name) {
    return name.length && [name.lastPathComponent isEqualToString:name] && ![name hasPrefix:@"."] && ![name containsString:@"/"];
}

// Reads a picked file whole; the picker's copies need no scope, a file still in its place does.
static NSData *readPicked(NSURL *url, NSError **error) {
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (scoped) [url stopAccessingSecurityScopedResource];
    return data;
}

#pragma mark - fonts

NSString *SGLibraryFontsDirectory(void) { return libraryDirectory(@"Library/Fonts"); }

NSArray<NSString *> *SGLibraryFontFiles(void) { return filesIn(SGLibraryFontsDirectory(), @[@"ttf", @"otf"]); }

// CoreText, by hand (see the top of the file).
static bool (*ct_register)(CFURLRef, CTFontManagerScope, CFErrorRef *);
static bool (*ct_unregister)(CFURLRef, CTFontManagerScope, CFErrorRef *);
static CFArrayRef (*ct_descriptors)(CFURLRef);
static CFTypeRef (*ct_attribute)(CTFontDescriptorRef, CFStringRef);

static BOOL coreText(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/Frameworks/CoreText.framework/CoreText", RTLD_LAZY);
        if (!handle) return;
        ct_register = dlsym(handle, "CTFontManagerRegisterFontsForURL");
        ct_unregister = dlsym(handle, "CTFontManagerUnregisterFontsForURL");
        ct_descriptors = dlsym(handle, "CTFontManagerCreateFontDescriptorsFromURL");
        ct_attribute = dlsym(handle, "CTFontDescriptorCopyAttribute");
    });
    return ct_register && ct_unregister && ct_descriptors && ct_attribute;
}

// file name -> its families, for the files registered so far.
static NSMutableDictionary<NSString *, NSArray<NSString *> *> *sg_families;
static os_unfair_lock sg_familiesLock = OS_UNFAIR_LOCK_INIT;

// The families CoreText reads out of a file, without registering it (kCTFontFamilyNameAttribute's value).
static NSArray<NSString *> *familiesOfFile(NSURL *url) {
    if (!coreText()) return @[];
    NSMutableArray<NSString *> *families = [NSMutableArray array];
    CFArrayRef descriptors = ct_descriptors((__bridge CFURLRef)url);
    for (CFIndex i = 0; descriptors && i < CFArrayGetCount(descriptors); i++) {
        CFTypeRef family = ct_attribute((CTFontDescriptorRef)CFArrayGetValueAtIndex(descriptors, i), CFSTR("NSFontFamilyAttribute"));
        if (family && CFGetTypeID(family) == CFStringGetTypeID() && ![families containsObject:(__bridge NSString *)family])
            [families addObject:(__bridge NSString *)family];
        if (family) CFRelease(family);
    }
    if (descriptors) CFRelease(descriptors);
    return families;
}

// Registers one file for this process. Already registered (105) and a face another file already brought
// (305) are both fine: the family is there either way.
static BOOL registerFile(NSString *file, NSError **error) {
    if (!coreText()) {
        if (error) *error = libraryError(@"CoreText is not available.");
        return NO;
    }
    NSURL *url = [NSURL fileURLWithPath:[SGLibraryFontsDirectory() stringByAppendingPathComponent:file]];
    CFErrorRef cfError = NULL;
    bool registered = ct_register((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &cfError);
    NSError *failure = cfError ? CFBridgingRelease(cfError) : nil;   // ours to release: the call creates it
    if (!registered && failure) {
        registered = failure.code == kCTFontManagerErrorAlreadyRegistered || failure.code == kCTFontManagerErrorDuplicatedName;
        if (!registered && error) *error = failure;
    }
    if (!registered) {
        if (error && !*error) *error = libraryError(@"CoreText would not register the font.");
        return NO;
    }
    NSArray<NSString *> *families = familiesOfFile(url);
    os_unfair_lock_lock(&sg_familiesLock);
    if (!sg_families) sg_families = [NSMutableDictionary dictionary];
    sg_families[file] = families;
    os_unfair_lock_unlock(&sg_familiesLock);
    return YES;
}

void SGLibraryRegisterFonts(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSUInteger count = 0;
        for (NSString *file in SGLibraryFontFiles()) {
            NSError *error = nil;
            if (registerFile(file, &error)) count++;
            else SGLog(@"library: font %@ not registered: %@", file, error.localizedDescription);
        }
        if (count) SGLog(@"library: %lu font files registered", (unsigned long)count);
    });
}

// Registration at launch, off the main thread: nothing draws with these fonts before the lyrics do.
__attribute__((constructor)) static void registerFontsAtLaunch(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ SGLibraryRegisterFonts(); });
}

NSArray<NSString *> *SGLibraryFontFamiliesOf(NSString *file) {
    SGLibraryRegisterFonts();
    os_unfair_lock_lock(&sg_familiesLock);
    NSArray<NSString *> *families = sg_families[file];
    os_unfair_lock_unlock(&sg_familiesLock);
    return families ?: @[];
}

NSArray<NSString *> *SGLibraryFontFamilies(void) {
    SGLibraryRegisterFonts();
    NSMutableSet<NSString *> *all = [NSMutableSet set];
    os_unfair_lock_lock(&sg_familiesLock);
    for (NSArray<NSString *> *families in sg_families.allValues) [all addObjectsFromArray:families];
    os_unfair_lock_unlock(&sg_familiesLock);
    return [all.allObjects sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

NSString *SGLibraryImportFont(NSURL *url, NSError **error) {
    NSString *name = url.lastPathComponent;
    if (!plainName(name) || ![@[@"ttf", @"otf"] containsObject:name.pathExtension.lowercaseString]) {
        if (error) *error = libraryError([NSString stringWithFormat:@"%@ is not a .ttf or .otf font.", name ?: @"The file"]);
        return nil;
    }
    NSData *data = readPicked(url, error);
    if (!data) return nil;
    // A file is a sfnt: 0x00010000 or 'true' (TrueType), 'OTTO' (CFF OpenType), 'ttcf' (a collection).
    const char *bytes = data.bytes;
    if (data.length < 12 || !(!memcmp(bytes, "\0\1\0\0", 4) || !memcmp(bytes, "true", 4) || !memcmp(bytes, "OTTO", 4) || !memcmp(bytes, "ttcf", 4))) {
        if (error) *error = libraryError([NSString stringWithFormat:@"%@ is not a font file.", name]);
        return nil;
    }
    NSString *path = [SGLibraryFontsDirectory() stringByAppendingPathComponent:name];
    // A file of the same name already registered is let go of first, so the new one takes its place.
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) SGLibraryDeleteFont(name);
    if (![data writeToFile:path options:NSDataWritingAtomic error:error]) return nil;
    SGLibraryRegisterFonts();
    if (!registerFile(name, error)) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        return nil;
    }
    SGLog(@"library: font %@ imported (%@)", name, [SGLibraryFontFamiliesOf(name) componentsJoinedByString:@", "]);
    postOnMain(SGLibraryFontsDidChangeNotification);
    return name;
}

BOOL SGLibraryDeleteFont(NSString *file) {
    if (!plainName(file)) return NO;
    NSURL *url = [NSURL fileURLWithPath:[SGLibraryFontsDirectory() stringByAppendingPathComponent:file]];
    if (coreText()) ct_unregister((__bridge CFURLRef)url, kCTFontManagerScopeProcess, NULL);
    os_unfair_lock_lock(&sg_familiesLock);
    [sg_families removeObjectForKey:file];
    os_unfair_lock_unlock(&sg_familiesLock);
    NSError *error = nil;
    if (![NSFileManager.defaultManager removeItemAtURL:url error:&error]) {
        SGLog(@"library: font %@ could not be deleted: %@", file, error);
        return NO;
    }
    postOnMain(SGLibraryFontsDidChangeNotification);
    return YES;
}

#pragma mark - looks

NSString *SGLibraryLooksDirectory(void) { return libraryDirectory(@"Library/Looks"); }

NSArray<NSString *> *SGLibraryLookNames(void) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *file in filesIn(SGLibraryLooksDirectory(), @[@"json"])) [names addObject:file.stringByDeletingPathExtension];
    return names;
}

NSURL *SGLibraryLookURL(NSString *name) {
    if (!plainName(name)) return nil;
    return [NSURL fileURLWithPath:[SGLibraryLooksDirectory() stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"json"]]];
}

static NSDictionary *lookIn(NSData *data) {
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

NSDictionary<NSString *, id> *SGLibraryLook(NSString *name) {
    NSURL *url = SGLibraryLookURL(name);
    return url ? lookIn([NSData dataWithContentsOfURL:url]) : nil;
}

BOOL SGLibrarySaveLook(NSString *name, NSDictionary<NSString *, id> *look, NSError **error) {
    NSURL *url = SGLibraryLookURL(name);
    if (!url || ![look isKindOfClass:NSDictionary.class]) {
        if (error) *error = libraryError(@"A look needs a name and a dictionary.");
        return NO;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:look options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:error]) return NO;
    postOnMain(SGLibraryLooksDidChangeNotification);
    return YES;
}

NSString *SGLibraryImportLook(NSURL *url, NSError **error) {
    NSString *file = url.lastPathComponent;
    if (!plainName(file) || ![file.pathExtension.lowercaseString isEqualToString:@"json"]) {
        if (error) *error = libraryError([NSString stringWithFormat:@"%@ is not a .json file.", file ?: @"The file"]);
        return nil;
    }
    NSData *data = readPicked(url, error);
    if (!data) return nil;
    NSDictionary *look = lookIn(data);
    if (!look) {
        if (error) *error = libraryError([NSString stringWithFormat:@"%@ is not a look: it should be a JSON object.", file]);
        return nil;
    }
    NSString *name = file.stringByDeletingPathExtension;
    if (!SGLibrarySaveLook(name, look, error)) return nil;
    SGLog(@"library: look %@ imported", name);
    return name;
}

BOOL SGLibraryDeleteLook(NSString *name) {
    NSURL *url = SGLibraryLookURL(name);
    NSError *error = nil;
    if (!url || ![NSFileManager.defaultManager removeItemAtURL:url error:&error]) {
        SGLog(@"library: look %@ could not be deleted: %@", name, error);
        return NO;
    }
    postOnMain(SGLibraryLooksDidChangeNotification);
    return YES;
}

#pragma mark - a zip, read by hand

// libcompression, by hand (see the top of the file). COMPRESSION_ZLIB is raw deflate, which is what a zip
// entry holds.
static compression_status (*cs_init)(compression_stream *, compression_stream_operation, compression_algorithm);
static compression_status (*cs_process)(compression_stream *, int);
static compression_status (*cs_destroy)(compression_stream *);

static BOOL inflater(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/usr/lib/libcompression.dylib", RTLD_LAZY);
        if (!handle) return;
        cs_init = dlsym(handle, "compression_stream_init");
        cs_process = dlsym(handle, "compression_stream_process");
        cs_destroy = dlsym(handle, "compression_stream_destroy");
    });
    return cs_init && cs_process && cs_destroy;
}

static uint16_t le16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }
static uint32_t le32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static uint64_t le64(const uint8_t *p) { return (uint64_t)le32(p) | (uint64_t)le32(p + 4) << 32; }

// Copies `size` bytes of `in` from where it is to `out`, inflating them when `deflated`.
static BOOL extractEntry(FILE *in, FILE *out, uint64_t size, BOOL deflated, NSString **problem) {
    enum { kChunk = 1 << 20 };
    uint8_t *src = malloc(kChunk), *dst = deflated ? malloc(kChunk) : NULL;
    BOOL ok = YES;
    if (!deflated) {
        uint64_t left = size;
        while (ok && left) {
            size_t n = fread(src, 1, (size_t)MIN(left, (uint64_t)kChunk), in);
            if (!n) { ok = NO; *problem = @"The archive ends early."; break; }
            ok = fwrite(src, 1, n, out) == n;
            if (!ok) *problem = @"The file could not be written.";
            left -= n;
        }
    } else if (!inflater()) {
        ok = NO;
        *problem = @"This archive is compressed and libcompression is not available.";
    } else {
        compression_stream stream;
        if (cs_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_OK) {
            ok = NO;
            *problem = @"The decompressor could not start.";
        } else {
            uint64_t left = size;
            stream.src_ptr = src;
            stream.src_size = 0;
            for (;;) {
                if (!stream.src_size && left) {
                    size_t n = fread(src, 1, (size_t)MIN(left, (uint64_t)kChunk), in);
                    if (!n) { ok = NO; *problem = @"The archive ends early."; break; }
                    left -= n;
                    stream.src_ptr = src;
                    stream.src_size = n;
                }
                stream.dst_ptr = dst;
                stream.dst_size = kChunk;
                compression_status status = cs_process(&stream, left || stream.src_size ? 0 : COMPRESSION_STREAM_FINALIZE);
                size_t produced = kChunk - stream.dst_size;
                if (produced && fwrite(dst, 1, produced, out) != produced) { ok = NO; *problem = @"The file could not be written."; break; }
                if (status == COMPRESSION_STATUS_END) break;
                if (status == COMPRESSION_STATUS_ERROR) { ok = NO; *problem = @"The archive's data is damaged."; break; }
                if (!produced && !stream.src_size && !left) { ok = NO; *problem = @"The archive ends early."; break; }
                // OK: either the output filled, or the input ran out; the loop reads more or drains more.
            }
            cs_destroy(&stream);
        }
    }
    free(src);
    free(dst);
    return ok;
}

// Unpacks a zip into `into`. Reads the central directory at the end (zip64's too), then each entry from its
// local header: stored and deflated entries, no encryption, no spanning. Names that would leave `into`,
// Finder's __MACOSX folder and .DS_Store are skipped.
static BOOL unzip(NSURL *zip, NSURL *into, NSError **error) {
    NSString *problem = nil;
    FILE *in = fopen(zip.path.fileSystemRepresentation, "rb");
    if (!in) {
        if (error) *error = libraryError(@"The archive could not be opened.");
        return NO;
    }
    fseeko(in, 0, SEEK_END);
    off_t fileSize = ftello(in);
    // The end of central directory record: within the last 64 KB + 22 (its comment is at most 64 KB).
    size_t tailSize = (size_t)MIN(fileSize, (off_t)(65536 + 22));
    uint8_t *tail = malloc(tailSize);
    fseeko(in, fileSize - (off_t)tailSize, SEEK_SET);
    if (fread(tail, 1, tailSize, in) != tailSize) { free(tail); fclose(in); if (error) *error = libraryError(@"The archive could not be read."); return NO; }
    long eocd = -1;
    for (long i = (long)tailSize - 22; i >= 0; i--) if (le32(tail + i) == 0x06054b50) { eocd = i; break; }
    if (eocd < 0) { free(tail); fclose(in); if (error) *error = libraryError(@"This is not a zip archive."); return NO; }
    uint64_t entries = le16(tail + eocd + 10), cdSize = le32(tail + eocd + 12), cdOffset = le32(tail + eocd + 16);
    // Zip64: the locator sits right before the record and points at the real numbers.
    if ((entries == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF) && eocd >= 20 && le32(tail + eocd - 20) == 0x07064b50) {
        uint64_t zip64 = le64(tail + eocd - 20 + 8);
        uint8_t record[56];
        fseeko(in, (off_t)zip64, SEEK_SET);
        if (fread(record, 1, sizeof record, in) == sizeof record && le32(record) == 0x06064b50) {
            entries = le64(record + 32);
            cdSize = le64(record + 40);
            cdOffset = le64(record + 48);
        }
    }
    free(tail);
    if (cdSize > (64ull << 20) || (off_t)(cdOffset + cdSize) > fileSize) { fclose(in); if (error) *error = libraryError(@"The archive's directory is damaged."); return NO; }
    uint8_t *cd = malloc((size_t)cdSize);
    fseeko(in, (off_t)cdOffset, SEEK_SET);
    if (fread(cd, 1, (size_t)cdSize, in) != cdSize) { free(cd); fclose(in); if (error) *error = libraryError(@"The archive could not be read."); return NO; }

    NSFileManager *files = NSFileManager.defaultManager;
    BOOL ok = YES;
    NSUInteger extracted = 0;
    size_t at = 0;
    for (uint64_t n = 0; ok && n < entries && at + 46 <= cdSize; n++) {
        const uint8_t *h = cd + at;
        if (le32(h) != 0x02014b50) { problem = @"The archive's directory is damaged."; ok = NO; break; }
        uint16_t flags = le16(h + 8), method = le16(h + 10), nameLength = le16(h + 28), extraLength = le16(h + 30), commentLength = le16(h + 32);
        uint64_t compressed = le32(h + 20), uncompressed = le32(h + 24), localOffset = le32(h + 42);
        if (at + 46 + nameLength + extraLength + commentLength > cdSize) { problem = @"The archive's directory is damaged."; ok = NO; break; }
        NSString *name = [[NSString alloc] initWithBytes:h + 46 length:nameLength encoding:NSUTF8StringEncoding]
                         ?: [[NSString alloc] initWithBytes:h + 46 length:nameLength encoding:NSISOLatin1StringEncoding];
        // The zip64 extra field carries whichever of the three overflowed, in this order.
        const uint8_t *extra = h + 46 + nameLength;
        for (size_t e = 0; e + 4 <= extraLength;) {
            uint16_t tag = le16(extra + e), length = le16(extra + e + 2);
            if (tag == 0x0001) {
                size_t f = e + 4;
                if (uncompressed == 0xFFFFFFFF && f + 8 <= e + 4 + length) { uncompressed = le64(extra + f); f += 8; }
                if (compressed == 0xFFFFFFFF && f + 8 <= e + 4 + length) { compressed = le64(extra + f); f += 8; }
                if (localOffset == 0xFFFFFFFF && f + 8 <= e + 4 + length) { localOffset = le64(extra + f); }
            }
            e += 4 + length;
        }
        at += 46 + nameLength + extraLength + commentLength;

        // Where it goes, if anywhere.
        NSArray<NSString *> *parts = [name componentsSeparatedByString:@"/"];
        BOOL skip = !name.length || [name hasPrefix:@"/"] || [parts containsObject:@".."] || [parts.firstObject isEqualToString:@"__MACOSX"]
                    || [parts.lastObject isEqualToString:@".DS_Store"];
        if (skip) continue;
        NSURL *target = into;
        for (NSString *part in parts) if (part.length && ![part isEqualToString:@"."]) target = [target URLByAppendingPathComponent:part];
        if ([name hasSuffix:@"/"]) {
            [files createDirectoryAtURL:target withIntermediateDirectories:YES attributes:nil error:nil];
            continue;
        }
        if (flags & 1) { problem = @"The archive is encrypted."; ok = NO; break; }
        if (method != 0 && method != 8) { problem = [NSString stringWithFormat:@"The archive uses compression method %u, which cannot be read here.", method]; ok = NO; break; }
        // The local header before the data has its own name and extra field lengths.
        uint8_t local[30];
        fseeko(in, (off_t)localOffset, SEEK_SET);
        if (fread(local, 1, sizeof local, in) != sizeof local || le32(local) != 0x04034b50) { problem = @"The archive is damaged."; ok = NO; break; }
        fseeko(in, (off_t)(localOffset + 30 + le16(local + 26) + le16(local + 28)), SEEK_SET);
        [files createDirectoryAtURL:target.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        FILE *out = fopen(target.path.fileSystemRepresentation, "wb");
        if (!out) { problem = @"A file could not be written."; ok = NO; break; }
        ok = extractEntry(in, out, method == 8 ? compressed : uncompressed, method == 8, &problem);
        fclose(out);
        if (ok) extracted++;
    }
    free(cd);
    fclose(in);
    if (!ok && error) *error = libraryError(problem ?: @"The archive could not be read.");
    if (ok && !extracted) {
        ok = NO;
        if (error) *error = libraryError(@"The archive is empty.");
    }
    return ok;
}

#pragma mark - the custom Sing model

NSURL *SGLibraryCustomSingModelFolder(void) {
    return [NSURL fileURLWithPath:[libraryDirectory(@"Sing/Custom") stringByAppendingPathComponent:@"separator.mlmodelc"] isDirectory:YES];
}

BOOL SGLibraryLooksLikeModel(NSURL *url) {
    NSFileManager *files = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if (!url || ![files fileExistsAtPath:url.path isDirectory:&isDirectory] || !isDirectory) return NO;
    return [files fileExistsAtPath:[url URLByAppendingPathComponent:@"model.mil"].path]
        || [files fileExistsAtPath:[url URLByAppendingPathComponent:@"coremldata.bin"].path];
}

BOOL SGLibraryHasCustomSingModel(void) { return SGLibraryLooksLikeModel(SGLibraryCustomSingModelFolder()); }

NSURL *SGLibraryCustomSingModelURL(void) {
    if (!SGFlag(SGKeySingCustomModel, NO)) return nil;
    NSURL *folder = SGLibraryCustomSingModelFolder();
    return SGLibraryLooksLikeModel(folder) ? folder : nil;
}

int64_t SGLibraryCustomSingModelSize(void) {
    NSURL *folder = SGLibraryCustomSingModelFolder();
    if (!SGLibraryLooksLikeModel(folder)) return 0;
    int64_t total = 0;
    NSDirectoryEnumerator<NSURL *> *walk = [NSFileManager.defaultManager enumeratorAtURL:folder includingPropertiesForKeys:@[NSURLFileSizeKey]
                                                                                 options:0 errorHandler:nil];
    for (NSURL *url in walk) {
        NSNumber *size = nil;
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        total += size.longLongValue;
    }
    return total;
}

// The model inside what came in: the folder itself when it is one, else the first *.mlmodelc (or any folder
// holding model.mil) within three levels, so a zip of a folder of the model is found too.
static NSURL *findModel(NSURL *root) {
    if (SGLibraryLooksLikeModel(root)) return root;
    NSDirectoryEnumerator<NSURL *> *walk = [NSFileManager.defaultManager enumeratorAtURL:root includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                                 options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    for (NSURL *url in walk) {
        if (walk.level > 3) { [walk skipDescendants]; continue; }
        NSNumber *isDirectory = nil;
        [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if (isDirectory.boolValue && SGLibraryLooksLikeModel(url)) return url;
    }
    return nil;
}

BOOL SGLibraryImportSingModel(NSURL *url, NSError **error) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *scratch = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[@"spotifyglass.library." stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    if (![files createDirectoryAtURL:scratch withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    BOOL isDirectory = NO;
    BOOL exists = [files fileExistsAtPath:url.path isDirectory:&isDirectory];
    BOOL unpacked = NO;
    if (!exists) {
        if (error) *error = libraryError(@"The picked item could not be read.");
    } else if (isDirectory) {
        unpacked = [files copyItemAtURL:url toURL:[scratch URLByAppendingPathComponent:url.lastPathComponent] error:error];
    } else if ([url.pathExtension.lowercaseString isEqualToString:@"zip"]) {
        unpacked = unzip(url, scratch, error);
    } else if (error) {
        *error = libraryError(@"Pick the separator.mlmodelc folder, or a .zip holding it.");
    }
    if (scoped) [url stopAccessingSecurityScopedResource];
    NSURL *model = unpacked ? findModel(scratch) : nil;
    if (unpacked && !model && error) *error = libraryError(@"No model in it: a compiled Core ML model is a folder holding model.mil or coremldata.bin.");
    BOOL placed = NO;
    if (model) {
        NSURL *destination = SGLibraryCustomSingModelFolder();
        [files removeItemAtURL:destination error:nil];
        placed = [files moveItemAtURL:model toURL:destination error:error];
        if (placed) {
            [destination setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
            SGLog(@"library: custom Sing model imported, %lld bytes", SGLibraryCustomSingModelSize());
        }
    }
    [files removeItemAtURL:scratch error:nil];
    if (placed) postOnMain(SGLibrarySingModelDidChangeNotification);
    return placed;
}

void SGLibraryRemoveCustomSingModel(void) {
    [NSFileManager.defaultManager removeItemAtURL:SGLibraryCustomSingModelFolder() error:nil];
    SGLog(@"library: custom Sing model removed");
    postOnMain(SGLibrarySingModelDidChangeNotification);
}
