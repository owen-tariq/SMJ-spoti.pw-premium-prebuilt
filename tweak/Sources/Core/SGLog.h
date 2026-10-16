#import <Foundation/Foundation.h>
#import <os/log.h>

// %{public}s so idevicesyslog on the Mac sees the text instead of <private>.
#define SGLog(fmt, ...) os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "[spotifyglass] %{public}s", [NSString stringWithFormat:(fmt), ##__VA_ARGS__].UTF8String)

// Long dumps, split into numbered parts under the unified log's size cap.
void SGLogLong(NSString *tag, NSString *text);
// Logs every class of the list that this Spotify does not have; a feature calls it from its %ctor. Every
// name asked for is also kept, with whether it was found and the file that asked, for the Hook report
// page (App/About/HookReport.m): on a Spotify other than the supported one it says which hooks broke.
// Variadic: an @[...] literal's commas are not protected by its brackets.
#define SGRequireClasses(...) SGRequireClassesFrom((__VA_ARGS__), __FILE__)
void SGRequireClassesFrom(NSArray<NSString *> *names, const char *file);
// What was asked for so far, in the order asked: @{@"name", @"found" (NSNumber BOOL), @"requestedBy" (the
// asking file's name, or NSNull)}. Any thread; a copy.
NSArray<NSDictionary *> *SGRequiredClassReport(void);
