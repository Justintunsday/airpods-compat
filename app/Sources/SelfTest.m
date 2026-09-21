#import "SelfTest.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <sys/utsname.h>

#pragma mark - model table (mirrors the tweak's AirPodsCompatModels.plist)

static NSArray<NSDictionary *> *ACTestModels(void) {
    NSArray *budBases = @[
        @"UARPSupportedAccessoryA3064", // AirPods Pro 3 (26+)
        @"UARPSupportedAccessoryA3048", // AirPods Pro 2 USB-C (17+)
        @"UARPSupportedAccessoryA3053", // AirPods 4 (18+)
        @"UARPSupportedAccessoryA2699", // AirPods Pro 2
        @"UARPSupportedAccessoryAirPodsBud",
    ];
    NSArray *caseBases = @[
        @"UARPSupportedAccessoryA3122", // AirPods Pro 3 case (26+)
        @"UARPSupportedAccessoryA3059", // AirPods 4 ANC case (18+)
        @"UARPSupportedAccessoryA2968", // AirPods Pro 2 USB-C case (17+)
        @"UARPSupportedAccessoryA2617",
        @"UARPSupportedAccessoryAirPodsCase",
    ];
    NSArray *caseUSBBases = @[
        @"UARPSupportedAccessoryA3122USB",
        @"UARPSupportedAccessoryA3059USB",
        @"UARPSupportedAccessoryA2968USB",
        @"UARPSupportedAccessoryA2617USB",
        @"UARPSupportedAccessoryAirPodsCaseUSB",
    ];

    return @[
        @{ @"model": @"A3532", @"pid": @0x2036, @"display": @"AirPods 5",
           @"alt": @[@"A3531"], @"bases": budBases },
        @{ @"model": @"A3533", @"pid": @0x2037, @"display": @"AirPods 5",
           @"bases": budBases },
        @{ @"model": @"A3440", @"pid": @0x2030, @"display": @"AirPods 5 (Wireless Charging)",
           @"alt": @[@"A3439"], @"bases": budBases },
        @{ @"model": @"A3441", @"pid": @0x2032, @"display": @"AirPods 5 (Wireless Charging)",
           @"bases": budBases },
        @{ @"model": @"A3529", @"pid": @0x2035, @"display": @"AirPods 5 (Charging Case)",
           @"bases": caseBases },
        @{ @"model": @"A3529USB", @"pid": @0x13a5, @"display": @"AirPods 5 (Charging Case)",
           @"bases": caseUSBBases },
        @{ @"model": @"A3530USB", @"pid": @0x13a4, @"display": @"AirPods 5 (Wireless Charging Case)",
           @"bases": caseUSBBases },
    ];
}

static NSArray<NSString *> *ACFrameworkPaths(void) {
    return @[
        @"/System/Library/PrivateFrameworks/CoreUARP.framework/CoreUARP",
        @"/System/Library/PrivateFrameworks/HeadphoneManager.framework/HeadphoneManager",
        @"/System/Library/PrivateFrameworks/HeadphoneSettingsUI.framework/HeadphoneSettingsUI",
        @"/System/Library/Frameworks/CoreBluetooth.framework/CoreBluetooth",
    ];
}

#pragma mark - runtime helpers

static BOOL ACClassRespondsToClassSelector(Class cls, NSString *selectorName) {
    if (!cls) return NO;
    return class_respondsToSelector(object_getClass(cls), NSSelectorFromString(selectorName));
}

static uint32_t ACCallProductID(Class cls) {
    return ((uint32_t (*)(id, SEL))objc_msgSend)((id)cls, NSSelectorFromString(@"productID"));
}

static NSString *ACCallModelNumber(Class cls) {
    return ((id (*)(id, SEL))objc_msgSend)((id)cls, NSSelectorFromString(@"appleModelNumber"));
}

static NSArray *ACCallAlternativeModelNumbers(Class cls) {
    return ((id (*)(id, SEL))objc_msgSend)((id)cls, NSSelectorFromString(@"alternativeAppleModelNumbers"));
}

static id ACCallClass(id target, NSString *selectorName) {
    SEL sel = NSSelectorFromString(selectorName);
    if (!target || ![target respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, sel);
}

static NSString *ACDeviceIdentifier(void) {
    struct utsname info;
    uname(&info);
    return [NSString stringWithFormat:@"%s", info.machine];
}

#pragma mark - registration dry run (same approach as the tweak)

static NSMutableDictionary<NSString *, NSDictionary *> *gDryRunTable;

static uint32_t ACDryProductID(Class self, SEL _cmd) {
    return (uint32_t)[gDryRunTable[NSStringFromClass(self)][@"pid"] unsignedIntValue];
}

static id ACDryAppleModelNumber(Class self, SEL _cmd) {
    return gDryRunTable[NSStringFromClass(self)][@"model"];
}

static id ACDryMobileAssetModelNumber(Class self, SEL _cmd) {
    return gDryRunTable[NSStringFromClass(self)][@"model"];
}

static id ACDryAlternativeModelNumbers(Class self, SEL _cmd) {
    return gDryRunTable[NSStringFromClass(self)][@"alt"];
}

static Class ACFirstAvailableClass(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        Class cls = NSClassFromString(name);
        if (!cls) continue;
        if ([name containsString:@"AirPods"]) {
            // abstract base: inherit from a concrete sibling so -init works
            unsigned int count = 0;
            Class *classes = objc_copyClassList(&count);
            Class concrete = Nil;
            for (unsigned int i = 0; i < count; i++) {
                Class candidate = classes[i];
                if (class_getSuperclass(candidate) != cls) continue;
                if (![NSStringFromClass(candidate) hasPrefix:@"UARPSupportedAccessoryA"]) continue;
                concrete = candidate;
                break;
            }
            free(classes);
            if (concrete) return concrete;
        }
        return cls;
    }
    return Nil;
}

static void ACRunRegistrationDryRun(NSMutableString *out) {
    Class managerClass = NSClassFromString(@"UARPSupportedAccessoryManager");
    if (!managerClass) {
        [out appendString:@"  [skip] UARPSupportedAccessoryManager 不可用（CoreUARP 未加载）\n"];
        return;
    }

    id manager = ACCallClass((id)managerClass, @"defaultManager");
    if (!manager) {
        [out appendString:@"  [skip] +[UARPSupportedAccessoryManager defaultManager] 返回 nil\n"];
        return;
    }

    NSSet *before = ACCallClass(manager, @"setOfAccessories");
    [out appendFormat:@"  注册前 setOfAccessories 数量: %lu\n", (unsigned long)before.count];

    gDryRunTable = [NSMutableDictionary dictionary];
    NSUInteger registered = 0;

    for (NSDictionary *model in ACTestModels()) {
        NSString *realName = [@"UARPSupportedAccessory" stringByAppendingString:model[@"model"]];
        if (NSClassFromString(realName)) {
            [out appendFormat:@"  [native] %@ 已由系统提供，跳过\n", model[@"model"]];
            continue;
        }

        Class base = ACFirstAvailableClass(model[@"bases"]);
        if (!base) {
            [out appendFormat:@"  [fail] %@ 找不到可用的基类\n", model[@"model"]];
            continue;
        }

        NSString *clsName = [@"AirPodsCompat_" stringByAppendingString:model[@"model"]];
        Class cls = NSClassFromString(clsName);
        if (!cls) {
            cls = objc_allocateClassPair(base, clsName.UTF8String, 0);
            if (!cls) {
                [out appendFormat:@"  [fail] %@ objc_allocateClassPair 失败（基类 %@）\n",
                     model[@"model"], NSStringFromClass(base)];
                continue;
            }
            Class meta = object_getClass(cls);
            class_addMethod(meta, NSSelectorFromString(@"productID"), (IMP)ACDryProductID, "I@:");
            class_addMethod(meta, NSSelectorFromString(@"appleModelNumber"), (IMP)ACDryAppleModelNumber, "@@:");
            class_addMethod(meta, NSSelectorFromString(@"mobileAssetAppleModelNumber"), (IMP)ACDryMobileAssetModelNumber, "@@:");
            class_addMethod(meta, NSSelectorFromString(@"alternativeAppleModelNumbers"), (IMP)ACDryAlternativeModelNumbers, "@@:");
            gDryRunTable[clsName] = model;
            objc_registerClassPair(cls);
        }

        id accessory = ((id (*)(id, SEL))objc_msgSend)((id)[cls alloc], NSSelectorFromString(@"init"));
        if (!accessory) {
            [out appendFormat:@"  [fail] %@ 实例化失败\n", model[@"model"]];
            continue;
        }

        @try {
            ((void (*)(id, SEL, id))objc_msgSend)(manager,
                NSSelectorFromString(@"addSupportedAccessory:"), accessory);
            registered++;
            [out appendFormat:@"  [ok] %@ (productID=0x%x, base=%@)\n",
                 model[@"model"], [model[@"pid"] unsignedIntValue], NSStringFromClass(base)];
            NSString *found = nil;
            @try {
                id result = ((id (*)(id, SEL, id))objc_msgSend)(manager,
                    NSSelectorFromString(@"findByIdentifier:"), model[@"model"]);
                found = result ? @"命中" : @"未命中";
            } @catch (__unused NSException *e) {
                found = @"查询异常";
            }
            [out appendFormat:@"       findByIdentifier: %@ %@\n", model[@"model"], found];
        } @catch (NSException *e) {
            [out appendFormat:@"  [fail] %@ 注册异常: %@\n", model[@"model"], e.reason];
        }
    }

    NSSet *after = ACCallClass(manager, @"setOfAccessories");
    [out appendFormat:@"  注册后 setOfAccessories 数量: %lu（新增 %lu）\n",
        (unsigned long)after.count, (unsigned long)(after.count - before.count)];
    [out appendFormat:@"  干跑结果: %@\n", (registered > 0 && after.count > before.count) ? @"PASS ✅" : @"FAIL ❌"];
}

#pragma mark - entry point

NSString *ACRunSelfTest(void) {
    NSMutableString *out = [NSMutableString string];

    [out appendString:@"=== AirPods Compat 自检 ===\n\n"];

    // 1. environment
    UIDevice *device = [UIDevice currentDevice];
    [out appendString:@"[环境]\n"];
    [out appendFormat:@"  机型: %@ (%@)\n", ACDeviceIdentifier(), device.model];
    [out appendFormat:@"  系统: %@ (%@)\n", device.systemVersion, device.systemName];
    BOOL jb1 = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"];
    BOOL jb2 = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/Library/MobileSubstrate"];
    [out appendFormat:@"  越狱: %@ (/var/jb=%@ MobileSubstrate=%@)\n\n",
        (jb1 || jb2) ? @"是" : @"否", jb1 ? @"有" : @"无", jb2 ? @"有" : @"无"];

    // 2. frameworks
    [out appendString:@"[系统框架加载]\n"];
    for (NSString *path in ACFrameworkPaths()) {
        void *handle = dlopen(path.UTF8String, RTLD_LAZY);
        const char *err = dlerror();
        if (handle) {
            [out appendFormat:@"  [ok] %@\n", path.lastPathComponent];
        } else {
            [out appendFormat:@"  [--] %@ (%@)\n", path.lastPathComponent,
                 err ? @(err) : @"未找到"];
        }
    }
    [out appendString:@"\n"];

    // 3. native support inventory
    [out appendString:@"[系统原生 AirPods 5 支持]\n"];
    NSUInteger nativeCount = 0;
    for (NSDictionary *model in ACTestModels()) {
        NSString *clsName = [@"UARPSupportedAccessory" stringByAppendingString:model[@"model"]];
        Class cls = NSClassFromString(clsName);
        if (!cls) {
            [out appendFormat:@"  [缺] %@ (%@)\n", model[@"model"], model[@"display"]];
            continue;
        }
        nativeCount++;
        uint32_t pid = ACClassRespondsToClassSelector(cls, @"productID") ? ACCallProductID(cls) : 0;
        NSString *name = ACClassRespondsToClassSelector(cls, @"appleModelNumber") ? ACCallModelNumber(cls) : nil;
        NSArray *alts = ACClassRespondsToClassSelector(cls, @"alternativeAppleModelNumbers")
            ? ACCallAlternativeModelNumbers(cls) : nil;
        [out appendFormat:@"  [有] %@ pid=0x%x name=%@%@\n", model[@"model"], pid, name ?: @"-",
             alts.count ? [NSString stringWithFormat:@" alt=%@", [alts componentsJoinedByString:@","]] : @""];
    }
    [out appendFormat:@"  结论: 系统原生认识 %lu/%lu 个 AirPods 5 类\n\n",
        (unsigned long)nativeCount, (unsigned long)ACTestModels().count];

    // 4. HeadphoneManager / CoreBluetooth extras
    [out appendString:@"[功能类检查]\n"];
    NSArray<NSString *> *extra =
        @[ @"_TtC16HeadphoneManager18B868FeatureContent",
           @"_TtC16HeadphoneManager18B768FeatureContent",
           @"CBDevice", @"CBAccessoryLogging" ];
    for (NSString *name in extra) {
        Class cls = NSClassFromString(name);
        [out appendFormat:@"  [%@] %@\n", cls ? @"有" : @"缺", name];
    }
    [out appendString:@"\n"];

    // 5. dry run
    [out appendString:@"[动态注册干跑（与越狱 tweak 同逻辑）]\n"];
    @try {
        ACRunRegistrationDryRun(out);
    } @catch (NSException *e) {
        [out appendFormat:@"  [fail] 干跑崩溃: %@\n", e.reason];
    }

    [out appendString:@"\n[提示]\n"];
    [out appendString:@"  · 本自检只能验证“系统是否认识 + 注册逻辑是否可行”，\n"];
    [out appendString:@"    真正让蓝牙守护进程生效仍需越狱包（tweak）。\n"];
    [out appendString:@"  · 若原生支持全部为“缺”，说明需要越狱部署 tweak 才能补上。\n"];

    return out;
}
