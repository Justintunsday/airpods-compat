#import "../Core/Runtime.h"

static id (*originalProductName)(id, SEL);
static id (*originalLoggingName)(id, SEL, unsigned);
static id ACDeviceProductName(id object, SEL selector) {
    NSNumber *hardware = ACOriginalProductIDForUIObject(object);
    if (!hardware && ACMethodMatches(object_getClass(object), @selector(productID), "I", @[], NO))
        hardware = @(((unsigned (*)(id, SEL))objc_msgSend)(object, @selector(productID)));
    return (hardware ? gDisplayNames[hardware] : nil) ?: originalProductName(object, selector);
}
static id ACLoggingName(id object, SEL selector, unsigned productID) {
    return gDisplayNames[@(productID)] ?: originalLoggingName(object, selector, productID);
}
void ACInstallDeviceIdentity(void) {
    // Names only. No Bluetooth PID setter, pairing, firmware or Find My hooks.
    Class device = objc_getClass("CBDevice");
    if (!originalProductName && ACMethodMatches(device, @selector(productName), "@", @[], NO))
        MSHookMessageEx(device, @selector(productName), (IMP)ACDeviceProductName, (IMP *)&originalProductName);
    Class logging = objc_getClass("CBAccessoryLogging");
    SEL selector = @selector(getProductNameFromProductID:);
    if (!originalLoggingName && ACMethodMatches(logging, selector, "@", @[@"I"], YES))
        MSHookMessageEx(object_getClass(logging), selector, (IMP)ACLoggingName, (IMP *)&originalLoggingName);
}
