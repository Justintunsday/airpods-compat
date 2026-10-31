// Process-filtered bootstrap; implementations are independent modules.
#import "Core/Runtime.h"
#import <mach-o/dyld.h>
static void ACImageAdded(const struct mach_header *image, intptr_t slide) {
    (void)image; (void)slide;
    dispatch_async(dispatch_get_main_queue(), ^{
        ACInstallLegacySettingsHooks();
        ACInstallDeviceIdentity();
        ACInstallHeadphoneFeatureHooks();
        ACInstallHeadphoneConfigHooks();
    });
}
%ctor {
    @autoreleasepool {
        ACLoadConfig();
        if (!gEnabled) return;
        ACInstallLegacySettingsHooks();
        ACInstallDeviceIdentity();
        ACInstallHeadphoneFeatureHooks();
        ACInstallHeadphoneConfigHooks();
        if (!ACProcessOwnsRegistry(ACProcessName().UTF8String))
            _dyld_register_func_for_add_image(ACImageAdded);
        ACInstallAccessoryRegistration();
    }
}
