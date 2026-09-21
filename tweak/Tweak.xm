// AirPodsCompat - backport AirPods 5 (A3531/A3532/A3533) support to older iOS.
//
// Hook targets located in the iOS 27.0 dyld_shared_cache / CoreUARP disassembly:
//   CoreUARP          UARPSupportedAccessoryA3440 (0x2030) / A3441 (0x2032)
//                     UARPSupportedAccessoryA3529 (0x2035) / A3529USB (0x13a5)
//                     UARPSupportedAccessoryA3530USB (0x13a4)
//                     UARPSupportedAccessoryA3532 (0x2036, alt A3531) / A3533 (0x2037)
//                     registration: -[UARPSupportedAccessoryManager addSupportedAccessory:]
//   CoreBluetooth     -[CBDevice productName] / +[CBAccessoryLogging getProductNameFromProductID:]
//   HeadphoneManager  Swift B868FeatureContent (productIDs) - not handled yet

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

#if __has_include(<rootless.h>)
#import <rootless.h>
#else
#define ROOT_PATH_NS(p) (p)
#endif

#define AC_LOG(fmt, ...) NSLog(@"[AirPodsCompat] " fmt, ##__VA_ARGS__)

static NSDictionary *gConfig;
static BOOL gEnabled = YES;
static NSMutableDictionary<NSString *, NSDictionary *> *gClassTable;
static NSDictionary<NSNumber *, NSString *> *gDisplayNames;

static NSString *ACDataPath(void) {
    return ROOT_PATH_NS(@"/Library/Application Support/AirPodsCompat/AirPodsCompatModels.plist");
}

static NSString *ACPrefsPath(void) {
    return ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.justintunsday.airpodscompat.plist");
}

static void ACLoadConfig(void) {
    gConfig = [NSDictionary dictionaryWithContentsOfFile:ACDataPath()] ?: @{};
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:ACPrefsPath()];
    if (prefs[@"Enabled"]) {
        gEnabled = [prefs[@"Enabled"] boolValue];
    }

    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    [gConfig[@"DisplayNames"] enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *name, BOOL *stop) {
        names[@(key.intValue)] = name;
    }];
    gDisplayNames = names;
    gClassTable = [NSMutableDictionary dictionary];

    AC_LOG(@"config: uarp=%lu names=%lu enabled=%d",
           (unsigned long)[gConfig[@"UARP"] count], (unsigned long)names.count, gEnabled);
}

#pragma mark - CoreUARP registration

static NSDictionary *ACModelForClass(Class cls) {
    return gClassTable[NSStringFromClass(cls)];
}

static uint32_t AC_productID(Class self, SEL _cmd) {
    return (uint32_t)[ACModelForClass(self)[@"productID"] unsignedIntValue];
}

static NSString *AC_appleModelNumber(Class self, SEL _cmd) {
    return ACModelForClass(self)[@"appleModelNumber"];
}

static NSString *AC_mobileAssetAppleModelNumber(Class self, SEL _cmd) {
    NSDictionary *model = ACModelForClass(self);
    return model[@"mobileAssetAppleModelNumber"] ?: model[@"appleModelNumber"];
}

static NSArray *AC_alternativeAppleModelNumbers(Class self, SEL _cmd) {
    return ACModelForClass(self)[@"alternativeAppleModelNumbers"];
}

static Class ACResolveBaseClass(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        Class cls = NSClassFromString(name);
        if (cls) return cls;
    }
    return Nil;
}

static void ACRegisterUARPAccessories(void) {
    Class managerClass = objc_getClass("UARPSupportedAccessoryManager");
    if (!managerClass) {
        AC_LOG(@"UARPSupportedAccessoryManager not present in this process");
        return;
    }

    id manager = ((id (*)(id, SEL))objc_msgSend)((id)managerClass, sel_registerName("defaultManager"));
    if (!manager) return;
    SEL addSel = sel_registerName("addSupportedAccessory:");

    for (NSDictionary *model in gConfig[@"UARP"]) {
        NSString *clsName = [NSString stringWithFormat:@"AirPodsCompat_%@", model[@"appleModelNumber"]];
        Class cls = NSClassFromString(clsName);

        if (!cls) {
            Class base = ACResolveBaseClass(model[@"baseClasses"]);
            if (!base) {
                AC_LOG(@"no base class available for %@", model[@"appleModelNumber"]);
                continue;
            }
            cls = objc_allocateClassPair(base, clsName.UTF8String, 0);
            if (!cls) continue;
            Class meta = object_getClass(cls);
            class_addMethod(meta, sel_registerName("productID"), (IMP)AC_productID, "I@:");
            class_addMethod(meta, sel_registerName("appleModelNumber"), (IMP)AC_appleModelNumber, "@@:");
            class_addMethod(meta, sel_registerName("mobileAssetAppleModelNumber"), (IMP)AC_mobileAssetAppleModelNumber, "@@:");
            class_addMethod(meta, sel_registerName("alternativeAppleModelNumbers"), (IMP)AC_alternativeAppleModelNumbers, "@@:");
            gClassTable[clsName] = model;
            objc_registerClassPair(cls);
        }

        id accessory = ((id (*)(id, SEL))objc_msgSend)((id)[cls alloc], sel_registerName("init"));
        if (!accessory) continue;
        ((void (*)(id, SEL, id))objc_msgSend)(manager, addSel, accessory);
        AC_LOG(@"registered %@ productID=0x%x", model[@"appleModelNumber"],
               [model[@"productID"] unsignedIntValue]);
    }
}

#pragma mark - CoreBluetooth display names

// private classes from the dyld_shared_cache (no on-disk headers)
@interface CBDevice : NSObject
@property (nonatomic) unsigned int productID;
@property (nonatomic, copy) NSString *productName;
@end

@interface CBAccessoryLogging : NSObject
@end

%hook CBDevice

- (NSString *)productName {
    NSString *original = %orig;
    NSString *name = gDisplayNames[@([self productID])];
    return name ?: original;
}

%end

%hook CBAccessoryLogging

+ (NSString *)getProductNameFromProductID:(unsigned int)productID {
    NSString *name = gDisplayNames[@(productID)];
    return name ?: %orig;
}

%end

%ctor {
    @autoreleasepool {
        ACLoadConfig();
        if (!gEnabled) {
            AC_LOG(@"disabled via prefs");
            return;
        }
        ACRegisterUARPAccessories();
    }
}
