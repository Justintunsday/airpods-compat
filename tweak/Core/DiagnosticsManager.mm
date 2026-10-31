#import "Runtime.h"
#import <unistd.h>
#if __has_include("BuildVersion.h")
#include "BuildVersion.h"
#endif
#ifndef AC_BUILD_ID
#define AC_BUILD_ID "development"
#endif

void ACRecordHookStatus(NSString *module, NSString *state) {
    if (!gDiagnosticLogs || (!ACProcessIsResourceClient(ACProcessName().UTF8String) &&
        !ACProcessOwnsSettings(ACProcessName().UTF8String))) return;
    static NSMutableDictionary *states;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ states = [NSMutableDictionary dictionary]; });
    @synchronized (states) {
        if ([states[module] isEqualToString:state]) return;
        states[module] = state;
        NSString *directory = @"/var/mobile/Library/Caches/com.justintunsday.airpodscompat";
        NSFileManager *manager = NSFileManager.defaultManager;
        if (![manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]) return;
        NSString *filename = [NSString stringWithFormat:@"%@-%@.plist", ACProcessName(), module];
        NSDictionary *record = @{@"module": module, @"state": state, @"build": @AC_BUILD_ID,
            @"process": ACProcessName(), @"pid": @(getpid()), @"timestamp": NSDate.date,
            @"os": NSProcessInfo.processInfo.operatingSystemVersionString};
        [record writeToFile:[directory stringByAppendingPathComponent:filename] atomically:YES];
    }
}
