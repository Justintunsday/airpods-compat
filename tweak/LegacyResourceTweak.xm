#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>

static BOOL gRouteResourcesEnabled = YES;
static BOOL gBatteryResourcesEnabled = YES;
static NSString *ACProcessName(void) { return NSProcessInfo.processInfo.processName; }

#import "LegacyResources.h"

static void ACResourceImageAdded(const struct mach_header *image, intptr_t slide) {
    (void)image;
    (void)slide;
    dispatch_async(dispatch_get_main_queue(), ^{ ACInstallLegacyResources(); });
}

%ctor {
    @autoreleasepool {
        if (!ACIsResourceUIProcess() ||
            NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 16) return;
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
            @"/var/mobile/Library/Preferences/com.justintunsday.airpodscompat.plist"];
        if (prefs[@"Enabled"] && ![prefs[@"Enabled"] boolValue]) return;
        if (prefs[@"LegacyRouteResourcesEnabled"])
            gRouteResourcesEnabled = [prefs[@"LegacyRouteResourcesEnabled"] boolValue];
        if (prefs[@"LegacyBatteryResourcesEnabled"])
            gBatteryResourcesEnabled = [prefs[@"LegacyBatteryResourcesEnabled"] boolValue];
        if (!gRouteResourcesEnabled && !gBatteryResourcesEnabled) return;
        ACInstallLegacyResources();
        _dyld_register_func_for_add_image(ACResourceImageAdded);
    }
}
