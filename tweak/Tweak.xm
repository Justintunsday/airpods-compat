// AirPodsCompat - backport AirPods 5 (A3531/A3532/A3533) support to older iOS.
//
// Hook targets located in the iOS 27.0 dyld_shared_cache:
//   CoreUARP          UARPSupportedAccessoryA3439/A3440/A3441/A3529/A3530/A3532/A3533
//                     (-[UARPSupportedAccessoryA3532 init], ivar hwID)
//   CoreBluetooth     "AirPods 5" / "AirPods 5 (Wireless Charging)" name mapping
//   HeadphoneManager  Swift B868FeatureContent (productIDs / B868FeatureContentType)
//
// v0.1: loads the external model table, logs the runtime environment and
// installs patches only when the target classes exist (safe no-op otherwise).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#if __has_include(<rootless.h>)
#import <rootless.h>
#else
#define ROOT_PATH_NS(p) (p)
#endif

#define AC_LOG(fmt, ...) NSLog(@"[AirPodsCompat] " fmt, ##__VA_ARGS__)

static NSDictionary *gModels;
static BOOL gEnabled = YES;

static NSString *ACModelsPath(void) {
    return ROOT_PATH_NS(@"/Library/Application Support/AirPodsCompat/AirPodsCompatModels.plist");
}

static NSString *ACPrefsPath(void) {
    return ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.justintunsday.airpodscompat.plist");
}

static void ACLoadConfig(void) {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:ACModelsPath()];
    gModels = plist[@"Models"] ?: @{};

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:ACPrefsPath()];
    if (prefs[@"Enabled"]) {
        gEnabled = [prefs[@"Enabled"] boolValue];
    }
    AC_LOG(@"models=%lu enabled=%d", (unsigned long)gModels.count, gEnabled);
}

static void ACLogEnvironment(void) {
    NSArray<NSString *> *classes = @[
        @"UARPSupportedAccessoryManager",
        @"UARPSupportedAccessory",
        @"UARPSupportedAccessoryA3532",
        @"UARPSupportedAccessoryA3533",
        @"UARPSupportedAccessoryA3063",
        @"UARPSupportedAccessoryA3454",
        @"CBDevice",
        @"HPDevice",
    ];
    for (NSString *name in classes) {
        AC_LOG(@"class %@ present=%d", name, objc_getClass(name.UTF8String) != nil);
    }
}

%ctor {
    @autoreleasepool {
        ACLoadConfig();
        ACLogEnvironment();
        if (!gEnabled) {
            AC_LOG(@"disabled via prefs");
            return;
        }
        // v0.2 wires the real patches here:
        //  1. register UARPSupportedAccessory subclasses for A3439/A3440/A3441/
        //     A3529/A3530/A3532/A3533 (template: UARPSupportedAccessoryA3063)
        //  2. extend the CoreBluetooth productID -> name mapping
        //  3. extend HeadphoneManager B868FeatureContent productIDs
    }
}
