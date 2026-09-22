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
//     after. Each accessory daemon has its own marker. A marker left by a
//     crash disables registration until it is removed explicitly.
//
// Hook targets (from the iOS 27.0 CoreUARP disassembly):
//   -[UARPSupportedAccessoryManager addSupportedAccessory:]
//   -[CBDevice productName]
//   +[CBAccessoryLogging getProductNameFromProductID:]
//
// Hook targets (v0.4, from the iOS 26.6.2/27.0 HeadphoneManager analysis):
//   HeadphoneDevice.allFeatureContents(productID:device:) - on iOS < 27
//     substitute the AirPods 5 PIDs with a borrowed model PID so the existing,
//     genuine FeatureContent class + witness tables drive the UI. Profile is
//     selectable via the BorrowProfile pref:
//       airpods4anc (default, B768 0x201b) / airpodspro2 (B698 0x2014) /
//       airpodspro3 (B788 0x2027) / off
//     On iOS 27+ the native B868FeatureContent already handles these PIDs,
//     so the hook is not installed (version-gated via dlsym).
//     See docs/ANALYSIS.md 11.12-11.16 for the call-chain evidence.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <errno.h>
#import <unistd.h>

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

// Feature-content borrowing (v0.4, iOS 26.x only - see ACInstallFeatureContentBorrowing):
// borrow targets available in the FeatureContent chain and their accepted PIDs.
static const uint32_t kAirPods5ProductIDs[] = { 0x2036, 0x2030, 0x2037, 0x2032 };
static const uint32_t kAirPods4AncProductID = 0x201b;
static const uint32_t kAirPodsPro2ProductID = 0x2014;
static const uint32_t kAirPodsPro3ProductID = 0x2027;
static BOOL gHasB868FeatureContent = NO;
static BOOL gBorrowEnabled = YES;
static uint32_t gBorrowProductID = 0x201b;
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

    NSString *borrow = prefs[@"BorrowProfile"];
    if ([borrow isEqualToString:@"off"]) {
        gBorrowEnabled = NO;
    } else if ([borrow isEqualToString:@"airpodspro2"]) {
        gBorrowProductID = kAirPodsPro2ProductID;
    } else if ([borrow isEqualToString:@"airpodspro3"]) {
        gBorrowProductID = kAirPodsPro3ProductID;
    } else {
        gBorrowProductID = kAirPods4AncProductID;
    }

    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    [gConfig[@"DisplayNames"] enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *name, BOOL *stop) {
        names[@(key.intValue)] = name;
    }];
    gDisplayNames = names;
    gClassTable = [NSMutableDictionary dictionary];

    AC_LOG(@"config: uarp=%lu scope=%@ enabled=%d uarpEnabled=%d borrow=%@ process=%@",
           (unsigned long)[gConfig[@"UARP"] count], gScopeAll ? @"all" : @"core",
           gEnabled, gUARPEnabled,
           gBorrowEnabled ? [NSString stringWithFormat:@"0x%x", gBorrowProductID] : @"off",
           ACProcessName());
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

#pragma mark - AirPods 5 -> borrowed feature content (v0.4)

// HeadphoneDevice.allFeatureContents(productID:device:) is the single factory
// behind HeadphoneDevice.featureContent and every UI that consumes it
// (HeadphoneSettingsUI in Preferences, HeadphoneProxService pairing cards).
// iOS 26.6.2 has no B868FeatureContent for the AirPods 5 PIDs, so those
// devices fall back to the generic content. By feeding the factory the
// AirPods 4 (ANC) PID we get the real B768FeatureContent object - no witness
// table is faked and no B768 UI code is shipped in the tweak.
// Borrow targets available on iOS 26.x (class = accepted PIDs):
//   B768 AirPods 4 / 4 (ANC)  : 0x2019, 0x201b  (closest form factor, default)
//   B698 AirPods Pro 2        : 0x2014, 0x2024  (ANC + adaptive features)
//   B788 AirPods Pro 3        : 0x2027, 0x2028  (richest, some rows unsupported)
// There is no AirPods 3 FeatureContent class, and one device resolves to exactly
// one content (featureContent is a singular getter), so profiles are exclusive.
static id (*orig_allFeatureContents)(uint32_t productID, id device);

static id AC_allFeatureContents(uint32_t productID, id device) {
    if (gBorrowEnabled && !gHasB868FeatureContent) {
        for (size_t i = 0; i < sizeof(kAirPods5ProductIDs) / sizeof(kAirPods5ProductIDs[0]); i++) {
            if (productID == kAirPods5ProductIDs[i]) {
                AC_LOG(@"borrowing feature content 0x%x for productID=0x%x", gBorrowProductID, productID);
                return orig_allFeatureContents(gBorrowProductID, device);
            }
        }
    }
    return orig_allFeatureContents(productID, device);
}

static void ACInstallFeatureContentBorrowing(void) {
    gHasB868FeatureContent =
        dlsym(RTLD_DEFAULT, "_$s16HeadphoneManager18B868FeatureContentCMa") != NULL;
    if (!gHasB868FeatureContent) {
        // belt and braces: if dlsym cannot see the shared-cache export, fall
        // back to the OS major version (iOS 27 introduced B868FeatureContent).
        gHasB868FeatureContent =
            NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27;
    }
    if (gHasB868FeatureContent) {
        AC_LOG(@"native AirPods 5 feature content present; hook skipped");
        return;
    }
    void *factory = dlsym(RTLD_DEFAULT,
        "_$s16HeadphoneManager0A6DeviceC18allFeatureContents9productID6deviceSayAA0aE11ContentType_pSgGSo09CBProductH0V_ACtFZ");
    if (!factory) {
        AC_LOG(@"allFeatureContents not present in %@; skipping", ACProcessName());
        return;
    }
    MSHookFunction(factory, (void *)AC_allFeatureContents, (void **)&orig_allFeatureContents);
    AC_LOG(@"installed AirPods 4 (ANC) feature-content borrowing hook");
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

        ACInstallFeatureContentBorrowing();

        if (!gUARPEnabled) {
            AC_LOG(@"UARP registration disabled via prefs");
            return;
        }
        if (!ACProcessOwnsAccessoryDatabase()) {
            AC_LOG(@"not an accessory-database process; skipping UARP registration");
            return;
        }
        NSString *guard = ACSupportPath([@".registration-in-progress." stringByAppendingString:ACProcessName()]);
        NSFileManager *fm = [NSFileManager defaultManager];
        NSError *directoryError = nil;
        if (![fm createDirectoryAtPath:[guard stringByDeletingLastPathComponent]
            withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
            AC_LOG(@"cannot create registration guard directory: %@", directoryError);
            return;
        }
        int marker = open(guard.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL, 0644);
        if (marker < 0) {
            AC_LOG(@"registration guard exists or cannot be created for %@ (errno=%d); skipping registration until guard is removed",
                   ACProcessName(), errno);
            return;
        }
        close(marker);
        ACRegisterUARPAccessories();
        if (![fm removeItemAtPath:guard error:nil]) {
            AC_LOG(@"could not clear registration guard %@", guard);
        }
        AC_LOG(@"registration finished cleanly");
    }
}
