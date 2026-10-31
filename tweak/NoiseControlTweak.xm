#import "Core/Runtime.h"
#import <mach-o/dyld.h>
void ACInstallNoiseControlSettingsHooks(void);
static void ACNoiseImageAdded(const struct mach_header *image, intptr_t slide) {
    (void)image; (void)slide;
    dispatch_async(dispatch_get_main_queue(), ^{ ACInstallNoiseControlSettingsHooks(); });
}
%ctor {
    @autoreleasepool {
        ACLoadConfig();
        if (!gEnabled) return;
        ACInstallNoiseControlSettingsHooks();
        _dyld_register_func_for_add_image(ACNoiseImageAdded);
    }
}
