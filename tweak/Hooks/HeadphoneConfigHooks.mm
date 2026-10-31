#import "../Core/Runtime.h"

// iOS 18 has no allFeatureContents. Only synchronous feature/resource reads
// enter this scope. Broad lifecycle methods, command setters, firmware, Find My
// and pairing never enter it. Restrict productID borrowing to the exact device.
static __thread void *scopedDevice;
static __thread unsigned scopeDepth;
static unsigned (*originalPID)(id, SEL);
static id (*originalTransparency)(id, SEL);
static id (*originalOffModes)(id, SEL);
static bool (*originalConversation)(id, SEL);
static bool (*originalAdaptiveVolume)(id, SEL);
static bool (*originalANCStrength)(id, SEL);

static id ACControllerDevice(id controller) {
    if (!ACMethodMatches(object_getClass(controller), @selector(device), "@", @[], NO)) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(controller, @selector(device));
}
static unsigned ACScopedProductID(id device, SEL selector) {
    unsigned pid = originalPID(device, selector);
    if (!scopeDepth || ACInHardwareIdentityScope() || (__bridge void *)device != scopedDevice || !ACIsAirPods5(pid)) return pid;
    ACCompatibilityEnvironment environment = {
        (unsigned)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        (bool)gEnabled, (bool)gBorrowEnabled, (bool)ACNativeProductRecord(pid),
        (bool)ACNativeProductRecord(0x201b), 0
    };
    return ACCompatibilitySelect(pid, ACContextSettingsLookup, environment).lookupProductID;
}
template <typename Result>
static Result ACWithSettingsLookup(id controller, SEL selector, Result (*original)(id, SEL)) {
    id device = ACControllerDevice(controller);
    void *previousDevice = scopedDevice;
    unsigned previousDepth = scopeDepth;
    // Only the class with a saved, ABI-validated original is eligible.
    if (device && originalPID && [device isKindOfClass:NSClassFromString(@"BluetoothDevice")]) {
        scopedDevice = (__bridge void *)device;
        scopeDepth++;
    }
    @try { return original(controller, selector); }
    @finally { scopedDevice = previousDevice; scopeDepth = previousDepth; }
}
static id ACTransparency(id object, SEL selector) { return ACWithSettingsLookup(object, selector, originalTransparency); }
static id ACOffModes(id object, SEL selector) { return ACWithSettingsLookup(object, selector, originalOffModes); }
static bool ACConversation(id object, SEL selector) { return ACWithSettingsLookup(object, selector, originalConversation); }
static bool ACAdaptiveVolume(id object, SEL selector) { return ACWithSettingsLookup(object, selector, originalAdaptiveVolume); }
static bool ACANCStrength(id object, SEL selector) { return ACWithSettingsLookup(object, selector, originalANCStrength); }

void ACInstallHeadphoneConfigHooks(void) {
    unsigned os = (unsigned)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
    if (os != 18 || !gBorrowEnabled || ![ACProcessName() isEqualToString:@"Preferences"] ||
        ACNativeAirPods5FeatureContent() || !ACNativeProductRecord(0x201b)) return;
    Class device = NSClassFromString(@"BluetoothDevice");
    Class controller = NSClassFromString(@"BTSDeviceConfigController");
    if (!originalPID && ACMethodMatches(device, @selector(productID), "I", @[], NO))
        MSHookMessageEx(device, @selector(productID), (IMP)ACScopedProductID, (IMP *)&originalPID);
    if (!originalPID || !ACMethodMatches(controller, @selector(device), "@", @[], NO)) return;
    struct { const char *name; const char *result; IMP replacement; IMP *original; } hooks[] = {
        {"adaptiveTransparencySpecifier", "@", (IMP)ACTransparency, (IMP *)&originalTransparency},
        {"turnOffListeningModeSpecifiers", "@", (IMP)ACOffModes, (IMP *)&originalOffModes},
        {"conversationDetectSupported", "B", (IMP)ACConversation, (IMP *)&originalConversation},
        {"adaptiveVolumeSupported", "B", (IMP)ACAdaptiveVolume, (IMP *)&originalAdaptiveVolume},
        {"supportAutoAncStrength", "B", (IMP)ACANCStrength, (IMP *)&originalANCStrength},
    };
    for (auto &hook : hooks) {
        SEL selector = sel_registerName(hook.name);
        if (!*hook.original && ACMethodMatches(controller, selector, hook.result, @[], NO)) {
            MSHookMessageEx(controller, selector, hook.replacement, hook.original);
            if (*hook.original) ACRecordHookStatus(@"settings18", @"installed-partial-read-queries");
            AC_LOG(@"iOS18 scoped Settings lookup installed: %s (live verification required)", hook.name);
        }
    }
}
