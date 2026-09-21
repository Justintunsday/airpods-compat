// AirPodsCompat - backport recent AirPods model support to older iOS.
//
// Safety model (v0.3):
//   * default scope is "core": only recent generations that older iOS lacks
//     (AirPods 4/5, AirPods Pro 3, AirPods Max 2 + their cases). The full
//     table can be enabled with Scope=all in the prefs.
//   * UARP registration only runs in processes that actually own the
//     accessory database (bluetoothd / uarpd / bluetoothuserd / bluetoothaudiod).
//   * abstract base classes are preferred (we must not inherit a sibling
//     model's concrete capabilities); concrete classes are only fallbacks.
//   * crash guard: a marker file is written before registration and removed
//     after. If it survives to the next launch, registration is skipped for
//     that launch so a bad model can never boot-loop the device.
//
// Hook targets (from the iOS 27.0 CoreUARP disassembly):
//   -[UARPSupportedAccessoryManager addSupportedAccessory:]
//   -[CBDevice productName]
//   +[CBAccessoryLogging getProductNameFromProductID:]

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
static BOOL gUARPEnabled = YES;
static BOOL gScopeAll = NO;
static BOOL gRegistrationCrashed = NO;
static NSMutableDictionary<NSString *, NSDictionary *> *gClassTable;
static NSDictionary<NSNumber *, NSString *> *gDisplayNames;

static NSString *ACSupportPath(NSString *name) {
    return [ROOT_PATH_NS(@"/Library/Application Support/AirPodsCompat") stringByAppendingPathComponent:name];
}

static NSString *ACPrefsPath(void) {
    return ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.justintunsday.airpodscompat.plist");
}

static NSString *ACProcessName(void) {
    return NSProcessInfo.processInfo.processName;
}

static void ACLoadConfig(void) {
    gConfig = [NSDictionary dictionaryWithContentsOfFile:ACSupportPath(@"AirPodsCompatModels.plist")] ?: @{};

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:ACPrefsPath()];
    if (prefs[@"Enabled"]) {
        gEnabled = [prefs[@"Enabled"] boolValue];
    }
    if (prefs[@"UARPEnabled"]) {
        gUARPEnabled = [prefs[@"UARPEnabled"] boolValue];
    }
    gScopeAll = [prefs[@"Scope"] isEqualToString:@"all"];

    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    [gConfig[@"DisplayNames"] enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *name, BOOL *stop) {
        names[@(key.intValue)] = name;
    }];
    gDisplayNames = names;
    gClassTable = [NSMutableDictionary dictionary];

    AC_LOG(@"config: uarp=%lu scope=%@ enabled=%d uarpEnabled=%d process=%@",
           (unsigned long)[gConfig[@"UARP"] count], gScopeAll ? @"all" : @"core",
           gEnabled, gUARPEnabled, ACProcessName());
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

// instance side: the inherited -init derives identifier/hwID from the base
// class statics, which would make all our accessories compare equal.
static NSString *ACInstModelNumber(id self, SEL _cmd) {
    NSDictionary *model = gClassTable[NSStringFromClass([self class])];
    return model[@"appleModelNumber"];
}

static NSString *ACInstIdentifier(id self, SEL _cmd) {
    return ACInstModelNumber(self, _cmd);
}

static NSArray *ACInstAlternativeModelNumbers(id self, SEL _cmd) {
    return gClassTable[NSStringFromClass([self class])][@"alternativeAppleModelNumbers"];
}

static BOOL ACProcessOwnsAccessoryDatabase(void) {
    NSString *name = ACProcessName();
    return [name isEqualToString:@"bluetoothd"] ||
           [name isEqualToString:@"bluetoothuserd"] ||
           [name isEqualToString:@"bluetoothaudiod"] ||
           [name isEqualToString:@"uarpd"];
}

static NSArray<NSDictionary *> *ACSelectedModels(void) {
    NSMutableArray *selected = [NSMutableArray array];
    for (NSDictionary *model in gConfig[@"UARP"]) {
        if (!gScopeAll && ![model[@"tier"] isEqualToString:@"core"]) {
            continue;
        }
        [selected addObject:model];
    }
    return selected;
}

static Class ACCreateClassForModel(NSDictionary *model, Class base, NSUInteger index) {
    NSString *clsName = index == 0
        ? [NSString stringWithFormat:@"AirPodsCompat_%@", model[@"model"]]
        : [NSString stringWithFormat:@"AirPodsCompat_%@_b%lu", model[@"model"], (unsigned long)index];

    Class cls = NSClassFromString(clsName);
    if (!cls) {
        cls = objc_allocateClassPair(base, clsName.UTF8String, 0);
        if (!cls) {
            return Nil;
        }
        Class meta = object_getClass(cls);
        class_addMethod(meta, sel_registerName("productID"), (IMP)AC_productID, "I@:");
        class_addMethod(meta, sel_registerName("appleModelNumber"), (IMP)AC_appleModelNumber, "@@:");
        class_addMethod(meta, sel_registerName("mobileAssetAppleModelNumber"), (IMP)AC_mobileAssetAppleModelNumber, "@@:");
        class_addMethod(meta, sel_registerName("alternativeAppleModelNumbers"), (IMP)AC_alternativeAppleModelNumbers, "@@:");
        class_addMethod(cls, sel_registerName("appleModelNumber"), (IMP)ACInstModelNumber, "@@:");
        class_addMethod(cls, sel_registerName("identifier"), (IMP)ACInstIdentifier, "@@:");
        class_addMethod(cls, sel_registerName("mobileAssetAppleModelNumber"), (IMP)ACInstModelNumber, "@@:");
        class_addMethod(cls, sel_registerName("alternativeAppleModelNumbers"), (IMP)ACInstAlternativeModelNumbers, "@@:");
        objc_registerClassPair(cls);
    }
    // always (re)bind the table: preexisting classes must resolve too
    gClassTable[clsName] = model;
    return cls;
}

static void ACRegisterUARPAccessories(void) {
    Class managerClass = objc_getClass("UARPSupportedAccessoryManager");
    if (!managerClass) {
        AC_LOG(@"UARPSupportedAccessoryManager not present in %@", ACProcessName());
        return;
    }
    id manager = ((id (*)(id, SEL))objc_msgSend)((id)managerClass, sel_registerName("defaultManager"));
    if (!manager) {
        return;
    }
    SEL addSel = sel_registerName("addSupportedAccessory:");

    NSUInteger registered = 0;
    for (NSDictionary *model in ACSelectedModels()) {
        NSString *nativeName = [@"UARPSupportedAccessory" stringByAppendingString:model[@"model"]];
        if (NSClassFromString(nativeName)) {
            continue; // this iOS already knows the model
        }

        id accessory = nil;
        NSArray<NSString *> *bases = model[@"baseClasses"];
        for (NSUInteger i = 0; i < bases.count && !accessory; i++) {
            Class base = NSClassFromString(bases[i]);
            if (!base) {
                continue;
            }
            Class cls = ACCreateClassForModel(model, base, i);
            if (!cls) {
                continue;
            }
            accessory = ((id (*)(id, SEL))objc_msgSend)((id)[cls alloc], sel_registerName("init"));
            if (accessory) {
                AC_LOG(@"registered %@ productID=0x%x base=%@", model[@"model"],
                       [model[@"productID"] unsignedIntValue], bases[i]);
            }
        }
        if (accessory) {
            ((void (*)(id, SEL, id))objc_msgSend)(manager, addSel, accessory);
            registered++;
        } else {
            AC_LOG(@"could not build accessory for %@", model[@"model"]);
        }
    }
    AC_LOG(@"registered %lu accessor(ies)", (unsigned long)registered);
}

#pragma mark - CoreBluetooth display names

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

        NSString *guard = ACSupportPath(@".registration-in-progress");
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:guard]) {
            gRegistrationCrashed = YES;
            [fm removeItemAtPath:guard error:nil];
            AC_LOG(@"previous registration attempt did not finish - skipping registration this launch");
        }

        if (!gUARPEnabled) {
            AC_LOG(@"UARP registration disabled via prefs");
            return;
        }
        if (!ACProcessOwnsAccessoryDatabase()) {
            AC_LOG(@"not an accessory-database process; skipping UARP registration");
            return;
        }
        if (gRegistrationCrashed) {
            return;
        }

        [@"" writeToFile:guard atomically:YES encoding:NSUTF8StringEncoding error:nil];
        ACRegisterUARPAccessories();
        [fm removeItemAtPath:guard error:nil];
        AC_LOG(@"registration finished cleanly");
    }
}
