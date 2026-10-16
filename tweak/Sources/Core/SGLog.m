#import "SGLog.h"
#import <os/lock.h>

// The unified log cuts a message at about 1 KB, so long dumps go out as numbered parts.
void SGLogLong(NSString *tag, NSString *text) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (current.length && [current lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + [line lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 900) {
            [parts addObject:[current copy]];
            [current setString:@""];
        }
        [current appendFormat:@"%@\n", line];
    }
    if (current.length) [parts addObject:current];
    [parts enumerateObjectsUsingBlock:^(NSString *part, NSUInteger i, BOOL *stop) {
        SGLog(@"%@ %lu/%lu\n%@", tag, (unsigned long)i + 1, (unsigned long)parts.count, part);
    }];
}

// Every class asked for, for the Hook report. The %ctors ask from the main thread as the dylib loads, but
// a late caller may be on any thread, so the list is behind a lock.
static NSMutableArray<NSDictionary *> *sg_requiredClasses;
static os_unfair_lock sg_requiredLock = OS_UNFAIR_LOCK_INIT;

void SGRequireClassesFrom(NSArray<NSString *> *names, const char *file) {
    NSString *requestedBy = file ? @(file).lastPathComponent : nil;
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:names.count];
    for (NSString *name in names) {
        BOOL found = NSClassFromString(name) != nil;
        if (!found) SGLog(@"class %@ not found, its hooks are inactive", name);
        [entries addObject:@{@"name": name, @"found": @(found), @"requestedBy": requestedBy ?: NSNull.null}];
    }
    os_unfair_lock_lock(&sg_requiredLock);
    if (!sg_requiredClasses) sg_requiredClasses = [NSMutableArray array];
    [sg_requiredClasses addObjectsFromArray:entries];
    os_unfair_lock_unlock(&sg_requiredLock);
}

NSArray<NSDictionary *> *SGRequiredClassReport(void) {
    os_unfair_lock_lock(&sg_requiredLock);
    NSArray<NSDictionary *> *report = [sg_requiredClasses copy] ?: @[];
    os_unfair_lock_unlock(&sg_requiredLock);
    return report;
}
