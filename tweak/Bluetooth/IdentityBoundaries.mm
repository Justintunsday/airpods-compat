#import "../Core/Runtime.h"

static __thread unsigned identityDepth;
static NSMutableDictionary<NSString *, NSValue *> *originals;
BOOL ACInHardwareIdentityScope(void) { return identityDepth != 0; }
static IMP ACIdentityOriginal(SEL selector) { return (IMP)originals[NSStringFromSelector(selector)].pointerValue; }
static void ACIdentityVoid(id object, SEL selector) {
    identityDepth++;
    @try { ((void (*)(id, SEL))ACIdentityOriginal(selector))(object, selector); }
    @finally { identityDepth--; }
}
static id ACIdentityObject(id object, SEL selector, id value) {
    identityDepth++;
    @try { return ((id (*)(id, SEL, id))ACIdentityOriginal(selector))(object, selector, value); }
    @finally { identityDepth--; }
}
static void ACIdentityAction(id object, SEL selector, id value) {
    identityDepth++;
    @try { ((void (*)(id, SEL, id))ACIdentityOriginal(selector))(object, selector, value); }
    @finally { identityDepth--; }
}
static void ACIdentitySetting(id object, SEL selector, id value, id specifier) {
    identityDepth++;
    @try { ((void (*)(id, SEL, id, id))ACIdentityOriginal(selector))(object, selector, value, specifier); }
    @finally { identityDepth--; }
}

void ACInstallIdentityBoundaries(void) {
    if (![ACProcessName() isEqualToString:@"Preferences"]) return;
    Class controller = NSClassFromString(@"BTSDeviceConfigController");
    if (!controller) return;
    if (!originals) originals = [NSMutableDictionary dictionary];
    for (NSString *name in @[@"loadAccessoryFirmwareInfo", @"loadAccessoryInfo", @"refreshFindMyStatus",
                             @"getFindMyUrl", @"presentFindMyLink", @"forgetDevice"]) {
        SEL selector = NSSelectorFromString(name);
        if (originals[name] || !ACClassOwnsSelector(controller, selector) ||
            !ACMethodMatches(controller, selector, "v", @[], NO)) continue;
        IMP original = NULL;
        MSHookMessageEx(controller, selector, (IMP)ACIdentityVoid, &original);
        if (original) originals[name] = [NSValue valueWithPointer:(void *)original];
    }
    for (NSString *name in @[@"getModelNumber:", @"getBudFirmwareVersion:", @"getCaseFirmwareVersion:",
                             @"getBudLeftSerialNumber:", @"getBudRightSerialNumber:",
                             @"getSystemSerialNumber:", @"getFindMyEnable:"]) {
        SEL selector = NSSelectorFromString(name);
        if (originals[name] || !ACClassOwnsSelector(controller, selector) ||
            !ACMethodMatches(controller, selector, "@", @[@"@"], NO)) continue;
        IMP original = NULL;
        MSHookMessageEx(controller, selector, (IMP)ACIdentityObject, &original);
        if (original) originals[name] = [NSValue valueWithPointer:(void *)original];
    }
    for (NSString *name in @[@"upgradeDevice:", @"forgetDeviceTapped:", @"disconnectDevice:"]) {
        SEL selector = NSSelectorFromString(name);
        if (originals[name] || !ACClassOwnsSelector(controller, selector) ||
            !ACMethodMatches(controller, selector, "v", @[@"@"], NO)) continue;
        IMP original = NULL;
        MSHookMessageEx(controller, selector, (IMP)ACIdentityAction, &original);
        if (original) originals[name] = [NSValue valueWithPointer:(void *)original];
    }
    SEL setting = @selector(setFindMyEnable:specifier:);
    NSString *key = NSStringFromSelector(setting);
    if (!originals[key] && ACClassOwnsSelector(controller, setting) &&
        ACMethodMatches(controller, setting, "v", @[@"@", @"@"], NO)) {
        IMP original = NULL;
        MSHookMessageEx(controller, setting, (IMP)ACIdentitySetting, &original);
        if (original) originals[key] = [NSValue valueWithPointer:(void *)original];
    }
}
