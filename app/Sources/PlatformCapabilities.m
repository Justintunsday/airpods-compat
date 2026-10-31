#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static BOOL ACAppRecordPresent(unsigned productID) {
    Class cls = NSClassFromString(@"CBProductInfo");
    Method lookup = class_getClassMethod(cls, @selector(productInfoWithProductID:));
    Method getter = class_getInstanceMethod(cls, @selector(productID));
    if (!lookup || !getter) return NO;
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(lookup)];
    NSMethodSignature *getSig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(getter)];
    if (sig.numberOfArguments != 3 || strcmp(sig.methodReturnType, "@") ||
        strcmp([sig getArgumentTypeAtIndex:2], "I") || getSig.numberOfArguments != 2 ||
        strcmp(getSig.methodReturnType, "I")) return NO;
    id value = ((id (*)(id, SEL, unsigned))objc_msgSend)(cls, @selector(productInfoWithProductID:), productID);
    return value && ((unsigned (*)(id, SEL))objc_msgSend)(value, @selector(productID)) == productID;
}

NSDictionary<NSString *, id> *ACReadPlatformCapabilities(void) {
    // Process-local inventory only; no system hooks are installed by this app.
    dlopen("/System/Library/PrivateFrameworks/HeadphoneManager.framework/HeadphoneManager", RTLD_LAZY);
    dlopen("/System/Library/Frameworks/CoreBluetooth.framework/CoreBluetooth", RTLD_LAZY);
    return @{
        @"factory": @(dlsym(RTLD_DEFAULT, "$s16HeadphoneManager0A6DeviceC18allFeatureContents9productID6deviceSayAA0aE11ContentType_pSgGSo09CBProductH0V_ACtFZ") != NULL),
        @"b768": @(dlsym(RTLD_DEFAULT, "$s16HeadphoneManager18B768FeatureContentCMa") != NULL),
        @"b868": @(dlsym(RTLD_DEFAULT, "$s16HeadphoneManager18B868FeatureContentCMa") != NULL),
        @"airpods4ancRecord": @(ACAppRecordPresent(0x201b)),
        @"airpods5Record": @(ACAppRecordPresent(0x2036))
    };
}
