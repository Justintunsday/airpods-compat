#import "Core/Runtime.h"
#import "LegacyResources.h"
#import <mach-o/dyld.h>
BOOL gRouteResourcesEnabled = YES;
BOOL gBatteryResourcesEnabled = YES;
static void ACResourceImageAdded(const struct mach_header *image, intptr_t slide) {
    (void)image; (void)slide;
    dispatch_async(dispatch_get_main_queue(), ^{ ACInstallLegacyResources(); });
}
%ctor {
    @autoreleasepool {
        ACLoadConfig();
        unsigned os = (unsigned)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
        if (!gEnabled || !ACProcessIsResourceClient(ACProcessName().UTF8String) ||
            (os != 16 && os != 18 && os != 26)) return;
        NSDictionary *prefs = ACReadPreferences();
        if (prefs[@"LegacyRouteResourcesEnabled"])
            gRouteResourcesEnabled = [prefs[@"LegacyRouteResourcesEnabled"] boolValue];
        if (prefs[@"LegacyBatteryResourcesEnabled"])
            gBatteryResourcesEnabled = [prefs[@"LegacyBatteryResourcesEnabled"] boolValue];
        if (!gRouteResourcesEnabled && !gBatteryResourcesEnabled) return;
        ACInstallLegacyResources();
        _dyld_register_func_for_add_image(ACResourceImageAdded);
    }
}
