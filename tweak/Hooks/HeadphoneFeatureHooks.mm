#import "../Core/Runtime.h"

// Swift Array is one native word. It is NOT an Objective-C id. Preserve the
// static metatype in swiftself (x20), the native device ref and array ownership.
// No existential, metadata object, conformance or witness table is constructed.
typedef __attribute__((swiftcall)) void *(*ACFeatureFactory)(
    uint32_t, void *, void * __attribute__((swift_context)));
static ACFeatureFactory originalFactory;

static void * __attribute__((swiftcall)) ACFeatureContents(
    uint32_t productID, void *device, void *context __attribute__((swift_context))) {
    ACCompatibilityEnvironment environment = {
        (unsigned)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        (bool)gEnabled, (bool)gBorrowEnabled, (bool)ACNativeAirPods5FeatureContent(), true, 0
    };
    auto decision = ACCompatibilitySelect(productID, ACContextFeatureContent, environment);
    if (decision.lookupProductID != productID) {
        AC_LOG(@"feature-content pid=0x%x lookup=0x%x; native device and Swift context retained", productID, decision.lookupProductID);
        ACRecordHookStatus(@"feature", @"borrowed-airpods4anc");
    }
    return originalFactory(decision.lookupProductID, device, context);
}

void ACInstallHeadphoneFeatureHooks(void) {
    if (originalFactory || !gBorrowEnabled || !ACProcessOwnsSettings(ACProcessName().UTF8String)) return;
    unsigned os = (unsigned)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
    if (ACNativeAirPods5FeatureContent()) { ACRecordHookStatus(@"feature", @"native"); return; }
    if (os != 26) return;
    if (!ACResolveHeadphoneSymbol("_$s16HeadphoneManager18B768FeatureContentCMa")) return;
    void *factory = ACResolveHeadphoneSymbol(
        "_$s16HeadphoneManager0A6DeviceC18allFeatureContents9productID6deviceSayAA0aE11ContentType_pSgGSo09CBProductH0V_ACtFZ");
    if (!factory) { ACRecordHookStatus(@"feature", @"factory-unavailable"); return; }
    MSHookFunction(factory, (void *)ACFeatureContents, (void **)&originalFactory);
    if (originalFactory) ACRecordHookStatus(@"feature", @"installed-airpods4anc");
    AC_LOG(@"B768/0x201b feature factory hook installed=%d (device verification required)", originalFactory != NULL);
}
