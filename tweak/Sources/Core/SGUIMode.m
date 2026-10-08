#import "SGUIMode.h"
#import "SGLog.h"
#import "SGPrefs.h"

BOOL SGRedesignTested(void) {
    if (@available(iOS 16.0, *)) return YES;
    return NO;
}

BOOL SGRedesignedUI(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        on = SGRedesignedUIStored();
        // A switch left on from before the warning existed, so the row does not show a look that is not running.
        if (!on && SGFlag(SGKeyRedesign, YES)) SGSetEnabled(SGKeyRedesign, NO);
        SGLog(@"ui: %@%@", on ? @"redesigned" : @"native", SGRedesignTested() ? @"" : @" (untested below iOS 16)");
    });
    return on;
}

BOOL SGNativeUI(void) {
    return !SGRedesignedUI();
}

BOOL SGRedesignedUIStored(void) {
    return SGFlag(SGKeyRedesign, YES) && (SGRedesignTested() || SGFlag(SGKeyRedesignUntested, NO));
}
