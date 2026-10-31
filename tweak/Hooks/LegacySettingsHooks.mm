#import "../Core/Runtime.h"
static NSMutableDictionary<NSString *, NSValue *> *gOriginalUIIconIMPs;
static NSMutableSet<NSString *> *gHookedUIIconClasses;
static NSMutableSet<NSNumber *> *gLoggedUIMappings;
static NSMutableDictionary<NSString *, NSValue *> *gOriginalUIProductIDIMPs;
static NSMutableDictionary<NSString *, NSValue *> *gOriginalUIProductNameIMPs;
static NSMutableDictionary<NSString *, NSValue *> *gOriginalUIModelNameIMPs;
static NSMutableSet<NSString *> *gHookedUIProductIDClasses;
static NSMutableSet<NSString *> *gHookedUIProductNameClasses;
static NSMutableSet<NSString *> *gHookedUIModelNameClasses;
static void *ACOriginalUIProductIDKey = &ACOriginalUIProductIDKey;
static BOOL ACIsUIProcess(void) {
    NSString *name = ACProcessName();
    return [name isEqualToString:@"Preferences"] || [name isEqualToString:@"SpringBoard"];
}

static uint32_t ACMapUIAccessoryProductID(uint32_t productID) {
    if (!gEnabled || ACInHardwareIdentityScope() || !gLegacyUIProfileEnabled || NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 18 || ![ACProcessName() isEqualToString:@"Preferences"]) {
        return productID;
    }
    ACCompatibilityEnvironment environment = {
        (unsigned)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        (bool)gEnabled, (bool)gLegacyUIProfileEnabled, false, true, gLegacyUIProductID
    };
    return ACCompatibilitySelect(productID, ACContextLegacySettings, environment).lookupProductID;
}

static uint32_t ACMapUIIconProductID(uint32_t productID) {
    static const uint32_t iconProductIDs[] = {
        0x2036, 0x2030, 0x2037, 0x2032, 0x2035, 0x13a5, 0x13a4
    };
    if (!gEnabled || !gLegacyIconProfileEnabled || NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 18 || !ACIsUIProcess()) {
        return productID;
    }
    for (size_t i = 0; i < sizeof(iconProductIDs) / sizeof(iconProductIDs[0]); i++) {
        if (iconProductIDs[i] == productID) {
            AC_LOG(@"legacy icon mapping 0x%x -> 0x%x", productID, gLegacyIconProductID);
            return gLegacyIconProductID;
        }
    }
    return productID;
}

static NSValue *ACOriginalIMPForObject(NSDictionary<NSString *, NSValue *> *map, id object) {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        NSValue *value = map[NSStringFromClass(cls)];
        if (value) {
            return value;
        }
    }
    return nil;
}

NSNumber *ACOriginalProductIDForUIObject(id object) {
    NSNumber *original = objc_getAssociatedObject(object, ACOriginalUIProductIDKey);
    if (original) {
        return original;
    }
    NSValue *value = ACOriginalIMPForObject(gOriginalUIProductIDIMPs, object);
    if (!value) {
        return nil;
    }
    unsigned int productID =
        ((unsigned int (*)(id, SEL))value.pointerValue)(object, sel_registerName("productID"));
    if (ACMapUIAccessoryProductID(productID) == productID) {
        return nil;
    }
    original = @(productID);
    objc_setAssociatedObject(object, ACOriginalUIProductIDKey, original,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return original;
}

static unsigned int AC_UIProductID(id self, SEL _cmd) {
    NSValue *value = ACOriginalIMPForObject(gOriginalUIProductIDIMPs, self);
    if (!value) {
        return 0;
    }
    unsigned int productID = ((unsigned int (*)(id, SEL))value.pointerValue)(self, _cmd);
    uint32_t mapped = ACMapUIAccessoryProductID(productID);
    if (mapped != productID) {
        objc_setAssociatedObject(self, ACOriginalUIProductIDKey, @(productID),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        objc_setAssociatedObject(self, ACOriginalUIProductIDKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return mapped;
}

static id AC_UIProductName(id self, SEL _cmd) {
    NSNumber *original = ACOriginalProductIDForUIObject(self);
    if (original) {
        NSString *name = gDisplayNames[original];
        if (name) {
            return name;
        }
    }
    NSValue *value = ACOriginalIMPForObject(gOriginalUIProductNameIMPs, self);
    if (!value) {
        return nil;
    }
    return ((id (*)(id, SEL))value.pointerValue)(self, _cmd);
}

static void ACHookUIProductIDClass(NSString *className) {
    if ([gHookedUIProductIDClasses containsObject:className]) {
        return;
    }
    Class cls = objc_getClass(className.UTF8String);
    if (!cls) {
        return;
    }
    SEL sel = sel_registerName("productID");
    Method method = class_getInstanceMethod(cls, sel);
    if (!method || !ACClassOwnsSelector(cls, sel)) {
        return;
    }
    if (!ACMethodMatches(cls, sel, "I", @[], NO) || !ACClassOwnsSelector(cls, sel)) return;
    IMP original = NULL;
    MSHookMessageEx(cls, sel, (IMP)AC_UIProductID, &original);
    if (original) {
        gOriginalUIProductIDIMPs[className] = [NSValue valueWithPointer:(void *)original];
        [gHookedUIProductIDClasses addObject:className];
        AC_LOG(@"hooked %@ productID", className);
    }
}

static void ACHookUIProductNameClass(NSString *className) {
    if ([gHookedUIProductNameClasses containsObject:className]) {
        return;
    }
    Class cls = objc_getClass(className.UTF8String);
    if (!cls) {
        return;
    }
    SEL sel = sel_registerName("productName");
    Method method = class_getInstanceMethod(cls, sel);
    if (!method || !ACClassOwnsSelector(cls, sel)) {
        return;
    }
    const char *types = method_getTypeEncoding(method);
    if (!types || types[0] != '@') {
        return;
    }
    IMP original = NULL;
    MSHookMessageEx(cls, sel, (IMP)AC_UIProductName, &original);
    if (original) {
        gOriginalUIProductNameIMPs[className] = [NSValue valueWithPointer:(void *)original];
        [gHookedUIProductNameClasses addObject:className];
        AC_LOG(@"hooked %@ productName", className);
    }
}

static id AC_UIModelName(id self, SEL _cmd, id device) {
    NSNumber *original = ACOriginalProductIDForUIObject(device);
    if (original) {
        NSString *name = gDisplayNames[original];
        if (name) {
            AC_LOG(@"getModelName mapped class=%@ device=%@ name=%@",
                   NSStringFromClass([self class]), NSStringFromClass([device class]), name);
            return name;
        }
    }
    NSValue *value = ACOriginalIMPForObject(gOriginalUIModelNameIMPs, self);
    if (!value) {
        return nil;
    }
    id name = ((id (*)(id, SEL, id))value.pointerValue)(self, _cmd, device);
    NSString *mappedName = nil;
    if ([name isKindOfClass:[NSString class]]) {
        NSString *key = (NSString *)name;
        if ([key isEqualToString:@"ACCESSORY_MODEL_NAME_54"] ||
            [key isEqualToString:@"ACCESSORY_MODEL_NAME_55"]) {
            mappedName = @"AirPods 5";
        } else if ([key isEqualToString:@"ACCESSORY_MODEL_NAME_48"] ||
                   [key isEqualToString:@"ACCESSORY_MODEL_NAME_50"]) {
            mappedName = @"AirPods 5 (Wireless Charging)";
        }
    }
    return mappedName ?: name;
}

static void ACHookUIModelNameClass(NSString *className) {
    if ([gHookedUIModelNameClasses containsObject:className]) {
        return;
    }
    Class cls = objc_getClass(className.UTF8String);
    if (!cls) {
        return;
    }
    SEL sel = sel_registerName("getModelName:");
    Method method = class_getInstanceMethod(cls, sel);
    if (!method || !ACClassOwnsSelector(cls, sel)) {
        return;
    }
    const char *types = method_getTypeEncoding(method);
    NSMethodSignature *signature = types ? [NSMethodSignature signatureWithObjCTypes:types] : nil;
    if (!signature || signature.numberOfArguments != 3 ||
        signature.methodReturnType[0] != '@' ||
        [signature getArgumentTypeAtIndex:2][0] != '@') {
        return;
    }
    IMP original = NULL;
    MSHookMessageEx(cls, sel, (IMP)AC_UIModelName, &original);
    if (original) {
        gOriginalUIModelNameIMPs[className] = [NSValue valueWithPointer:(void *)original];
        [gHookedUIModelNameClasses addObject:className];
        AC_LOG(@"hooked %@ getModelName:", className);
    }
}

static NSValue *ACOriginalUIIconIMPForObject(id object, SEL sel) {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        NSString *key = [NSString stringWithFormat:@"%@-%@", NSStringFromClass(cls), NSStringFromSelector(sel)];
        NSValue *value = gOriginalUIIconIMPs[key];
        if (value) {
            return value;
        }
    }
    return nil;
}

static id AC_UIIconProductID(id self, SEL _cmd, unsigned int productID) {
    NSValue *value = ACOriginalUIIconIMPForObject(self, _cmd);
    if (!value) {
        return nil;
    }
    unsigned int mapped = ACMapUIIconProductID(productID);
    id result = ((id (*)(id, SEL, unsigned int))value.pointerValue)(self, _cmd, mapped);
    return result;
}

static id (*orig_BatteryProductIDString)(id, SEL);

static id AC_BatteryProductIDString(id self, SEL _cmd) {
    id result = orig_BatteryProductIDString ? orig_BatteryProductIDString(self, _cmd) : nil;
    if (gLegacyIconProfileEnabled &&
        [result isKindOfClass:[NSString class]] &&
        [result isEqualToString:@"UNKNOWN"]) {
        NSString *mapped = (gLegacyIconProductID == kAirPodsPro2ProductID) ? @"B698" : @"B688";
        AC_LOG(@"HPSBatteryStatusView getProductIDString=%@ -> %@", result, mapped);
        return mapped;
    }
    return result;
}

static void ACHookUIIconClass(NSString *className) {
    if ([gHookedUIIconClasses containsObject:className]) {
        return;
    }
    Class cls = objc_getClass(className.UTF8String);
    if (!cls) {
        return;
    }
    BOOL hooked = NO;
    for (NSString *selName in @[@"getDeviceCaseIcon:", @"getAssetsDictionary:"]) {
        SEL sel = sel_registerName(selName.UTF8String);
        Method method = class_getInstanceMethod(cls, sel);
        if (!method || !ACClassOwnsSelector(cls, sel)) {
            continue;
        }
        const char *types = method_getTypeEncoding(method);
        NSMethodSignature *signature = types ? [NSMethodSignature signatureWithObjCTypes:types] : nil;
        if (!signature || signature.numberOfArguments != 3 ||
            signature.methodReturnType[0] != '@' ||
            [signature getArgumentTypeAtIndex:2][0] != 'I') {
            continue;
        }
        IMP original = NULL;
        MSHookMessageEx(cls, sel, (IMP)AC_UIIconProductID, &original);
        if (original) {
            NSString *key = [NSString stringWithFormat:@"%@-%@", className, selName];
            gOriginalUIIconIMPs[key] = [NSValue valueWithPointer:(void *)original];
            hooked = YES;
            AC_LOG(@"hooked %@ %@", className, selName);
        }
    }
    if ([className isEqualToString:@"HPSBatteryStatusView"]) {
        SEL sel = sel_registerName("getProductIDString");
        Method method = class_getInstanceMethod(cls, sel);
        if (method && ACMethodMatches(cls, sel, "@", @[], NO)) {
            IMP original = NULL;
            MSHookMessageEx(cls, sel, (IMP)AC_BatteryProductIDString, &original);
            if (original) {
                orig_BatteryProductIDString = (id (*)(id, SEL))original;
                hooked = YES;
                AC_LOG(@"hooked %@ getProductIDString", className);
            }
        }
    }
    if (hooked) {
        [gHookedUIIconClasses addObject:className];
    }
}

static void ACInstallLazyUIHooks(void) {
    ACHookUIIconClass(@"HPSBatteryStatusView");
    ACHookUIProductIDClass(@"CBDevice");
    ACHookUIProductIDClass(@"BluetoothDevice");
    ACHookUIProductIDClass(@"BTSDevice");
    ACHookUIProductIDClass(@"CUBluetoothDevice");
    ACHookUIProductNameClass(@"BluetoothDevice");
    ACHookUIProductNameClass(@"BTSDevice");
    ACHookUIProductNameClass(@"CUBluetoothDevice");
    ACHookUIModelNameClass(@"BTSDeviceConfigController");
    ACHookUIModelNameClass(@"BluetoothDevice");
    ACHookUIModelNameClass(@"BTSDevice");
}

static unsigned (*originalProximityPID)(id, SEL);
static id (*originalLegacyProductInfo)(id, SEL, unsigned);
static unsigned ACLegacyProximityPID(id object, SEL selector) {
    return ACMapUIAccessoryProductID(originalProximityPID(object, selector));
}
static id ACLegacyProductInfo(id object, SEL selector, unsigned productID) {
    return originalLegacyProductInfo(object, selector, ACMapUIAccessoryProductID(productID));
}
void ACInstallLegacySettingsHooks(void) {
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 18 || !ACIsUIProcess()) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gLoggedUIMappings = [NSMutableSet set];
        gOriginalUIProductIDIMPs = [NSMutableDictionary dictionary];
        gOriginalUIProductNameIMPs = [NSMutableDictionary dictionary];
        gOriginalUIModelNameIMPs = [NSMutableDictionary dictionary];
        gHookedUIProductIDClasses = [NSMutableSet set];
        gHookedUIProductNameClasses = [NSMutableSet set];
        gHookedUIModelNameClasses = [NSMutableSet set];
        gOriginalUIIconIMPs = [NSMutableDictionary dictionary];
        gHookedUIIconClasses = [NSMutableSet set];
    });
    ACInstallLazyUIHooks();
    ACInstallIdentityBoundaries();
    Class device = NSClassFromString(@"CBDevice");
    SEL proximity = @selector(proximityPairingProductID);
    if (!originalProximityPID && ACMethodMatches(device, proximity, "I", @[], NO))
        MSHookMessageEx(device, proximity, (IMP)ACLegacyProximityPID, (IMP *)&originalProximityPID);
    Class info = NSClassFromString(@"CBProductInfo");
    SEL lookup = @selector(productInfoWithProductID:);
    if (!originalLegacyProductInfo && ACMethodMatches(info, lookup, "@", @[@"I"], YES))
        MSHookMessageEx(object_getClass(info), lookup, (IMP)ACLegacyProductInfo, (IMP *)&originalLegacyProductInfo);
}
