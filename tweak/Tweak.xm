// Conservative compatibility layer: UARP is opt-in and uses abstract bases
// only. FeatureContent borrowing is suspended pending Swift ABI verification.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <fcntl.h>
#import <errno.h>
#import <unistd.h>
#import "../shared/ACSafetyPolicy.h"

#if __has_include(<rootless.h>)
#import <rootless.h>
#else
#define ROOT_PATH_NS(p) (p)
#endif

#define AC_LOG(fmt, ...) NSLog(@"[AirPodsCompat] " fmt, ##__VA_ARGS__)

static BOOL gEnabled = YES;
static BOOL gUARPEnabled = NO;
static BOOL gScopeAll = NO;
static NSArray<NSDictionary *> *gModels;
static NSMutableDictionary<NSString *, NSDictionary *> *gClassTable;
static NSDictionary<NSNumber *, NSString *> *gDisplayNames;

static NSString *ACSupportPath(NSString *name) {
    return [ROOT_PATH_NS(@"/Library/Application Support/AirPodsCompat") stringByAppendingPathComponent:name];
}

static NSString *ACPrefsPath(void) {
    return ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.justintunsday.airpodscompat.plist");
}

static NSString *ACProcessName(void) { return NSProcessInfo.processInfo.processName; }

static NSDictionary *ACReadDictionary(NSString *path) {
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (!attributes || [attributes fileSize] > 512 * 1024) return nil;
    return [NSDictionary dictionaryWithContentsOfFile:path];
}

static void ACLoadConfig(void) {
    NSDictionary *config = ACReadDictionary(ACSupportPath(@"AirPodsCompatModels.plist"));
    gModels = ACValidatedModels(config[@"UARP"]);
    gDisplayNames = ACValidatedDisplayNames(config[@"DisplayNames"]);
    gClassTable = [NSMutableDictionary dictionary];
    NSString *path = ACPrefsPath();
    NSDictionary *prefs = ACReadDictionary(path);
    if (!prefs && [NSFileManager.defaultManager fileExistsAtPath:path]) {
        gEnabled = NO;
        AC_LOG(@"preferences unreadable; compatibility hooks disabled");
        return;
    }
    prefs = prefs ?: @{};
    gEnabled = ACBoolPreference(prefs, @"Enabled", YES);
    gUARPEnabled = ACBoolPreference(prefs, @"UARPEnabled", NO);
    gScopeAll = ACFullModelScope(prefs);
    AC_LOG(@"models=%lu scope=%@ enabled=%d uarp=%d process=%@; feature borrowing suspended",
           (unsigned long)gModels.count, gScopeAll ? @"all" : @"core", gEnabled, gUARPEnabled, ACProcessName());
}

#pragma mark - Opt-in CoreUARP registration

static NSDictionary *ACModelForClass(Class cls) {
    @synchronized (gClassTable) { return gClassTable[NSStringFromClass(cls)]; }
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
static NSString *ACInstModelNumber(id self, SEL _cmd) {
    return ACModelForClass([self class])[@"appleModelNumber"];
}
static NSString *ACInstMobileAssetModelNumber(id self, SEL _cmd) {
    NSDictionary *model = ACModelForClass([self class]);
    return model[@"mobileAssetAppleModelNumber"] ?: model[@"appleModelNumber"];
}
static NSArray *ACInstAlternativeModelNumbers(id self, SEL _cmd) {
    return ACModelForClass([self class])[@"alternativeAppleModelNumbers"];
}
static BOOL ACProcessOwnsAccessoryDatabase(void) {
    return [@[@"bluetoothd", @"bluetoothuserd", @"bluetoothaudiod", @"uarpd"] containsObject:ACProcessName()];
}

static Class ACCreateClassForModel(NSDictionary *model, Class base) {
    NSString *clsName = [@"AirPodsCompat_" stringByAppendingString:model[@"model"]];
    if (NSClassFromString(clsName)) return Nil; // never adopt another component's class
    Class cls = objc_allocateClassPair(base, clsName.UTF8String, 0);
    if (!cls) return Nil;
    Class meta = object_getClass(cls);
    BOOL complete = class_addMethod(meta, @selector(productID), (IMP)AC_productID, "I@:");
    complete &= class_addMethod(meta, @selector(appleModelNumber), (IMP)AC_appleModelNumber, "@@:");
    complete &= class_addMethod(meta, @selector(mobileAssetAppleModelNumber), (IMP)AC_mobileAssetAppleModelNumber, "@@:");
    complete &= class_addMethod(meta, @selector(alternativeAppleModelNumbers), (IMP)AC_alternativeAppleModelNumbers, "@@:");
    complete &= class_addMethod(cls, @selector(appleModelNumber), (IMP)ACInstModelNumber, "@@:");
    complete &= class_addMethod(cls, @selector(identifier), (IMP)ACInstModelNumber, "@@:");
    complete &= class_addMethod(cls, @selector(mobileAssetAppleModelNumber), (IMP)ACInstMobileAssetModelNumber, "@@:");
    complete &= class_addMethod(cls, @selector(alternativeAppleModelNumbers), (IMP)ACInstAlternativeModelNumbers, "@@:");
    if (!complete) { objc_disposeClassPair(cls); return Nil; }
    @synchronized (gClassTable) { gClassTable[clsName] = model; }
    objc_registerClassPair(cls);
    return cls;
}

static BOOL ACRegisterUARPAccessories(void) {
    @try {
        Class managerClass = NSClassFromString(@"UARPSupportedAccessoryManager");
        SEL defaultSelector = @selector(defaultManager), addSelector = @selector(addSupportedAccessory:);
        if (!ACMethodMatches((id)managerClass, defaultSelector, '@', 2, 0)) {
            AC_LOG(@"manager getter unavailable or ABI changed; skipping"); return NO;
        }
        id manager = ((id (*)(id, SEL))objc_msgSend)((id)managerClass, defaultSelector);
        if (!ACMethodMatches(manager, addSelector, 'v', 3, '@')) {
            AC_LOG(@"registration method unavailable or ABI changed; skipping"); return NO;
        }
        NSUInteger registered = 0;
        for (NSDictionary *model in gModels) {
            if (!gScopeAll && ![model[@"tier"] isEqualToString:@"core"]) continue;
            NSString *nativeName = [@"UARPSupportedAccessory" stringByAppendingString:model[@"model"]];
            if (NSClassFromString(nativeName)) continue;
            NSString *baseName = [model[@"baseClasses"] firstObject];
            Class base = NSClassFromString(baseName);
            if (!base || !ACMethodMatches((id)base, @selector(alloc), '@', 2, 0)) {
                AC_LOG(@"abstract base %@ unavailable; skipping %@", baseName, model[@"model"]); continue;
            }
            Class cls = ACCreateClassForModel(model, base);
            if (!cls) { AC_LOG(@"class creation failed; stopping registration"); return NO; }
            id allocated = [cls alloc];
            if (!ACMethodMatches(allocated, @selector(init), '@', 2, 0)) return NO;
            id accessory = [allocated init];
            if (!accessory) { AC_LOG(@"abstract initializer rejected %@; stopping", model[@"model"]); return NO; }
            ((void (*)(id, SEL, id))objc_msgSend)(manager, addSelector, accessory);
            registered++;
            AC_LOG(@"submitted %@ productID=0x%x abstractBase=%@", model[@"model"],
                   [model[@"productID"] unsignedIntValue], baseName);
        }
        AC_LOG(@"submitted %lu definitions; firmware support remains unverified", (unsigned long)registered);
        return YES;
    } @catch (NSException *exception) {
        AC_LOG(@"registration exception %@; stopped and guard retained", exception.name);
        return NO;
    }
}

#pragma mark - Missing display names only

@interface CBDevice : NSObject
@end
@interface CBAccessoryLogging : NSObject
@end

%group ACDeviceNames
%hook CBDevice
- (NSString *)productName {
    NSString *original = %orig;
    if (original && (![original isKindOfClass:NSString.class] || original.length)) return original;
    id productID = ACReadNoArgumentValue(self, @selector(productID));
    return [productID isKindOfClass:NSNumber.class] ? (gDisplayNames[productID] ?: original) : original;
}
%end
%end

%group ACLoggingNames
%hook CBAccessoryLogging
+ (NSString *)getProductNameFromProductID:(unsigned int)productID {
    NSString *original = %orig;
    if (original && (![original isKindOfClass:NSString.class] || original.length)) return original;
    return gDisplayNames[@(productID)] ?: original;
}
%end
%end

%ctor {
    @autoreleasepool {
        @try {
            ACLoadConfig();
            NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
            if (!gEnabled || version.majorVersion < 15 || version.majorVersion >= 27) return;
            if (gDisplayNames.count) {
                Class deviceClass = NSClassFromString(@"CBDevice");
                Method method = class_getInstanceMethod(deviceClass, @selector(productName));
                char returnType[128] = {0};
                if (method) method_getReturnType(method, returnType, sizeof(returnType));
                if (method && returnType[0] == '@' && method_getNumberOfArguments(method) == 2) {
                    %init(ACDeviceNames);
                }
                Class loggingClass = NSClassFromString(@"CBAccessoryLogging");
                if (ACMethodMatches((id)loggingClass, @selector(getProductNameFromProductID:), '@', 3, 'I')) {
                    %init(ACLoggingNames);
                }
            }
            // No allFeatureContents hook: its former C/ObjC prototype does not
            // establish Swift context parameters or native result ownership.
            if (!gUARPEnabled || !ACProcessOwnsAccessoryDatabase() || !gModels.count) return;
            NSString *guard = ACSupportPath([@".registration-in-progress." stringByAppendingString:ACProcessName()]);
            NSFileManager *fm = NSFileManager.defaultManager;
            if (![fm createDirectoryAtPath:guard.stringByDeletingLastPathComponent
              withIntermediateDirectories:YES attributes:nil error:nil]) return;
            int marker = open(guard.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL, 0644);
            if (marker < 0) { AC_LOG(@"guard exists or cannot be created (errno=%d); skipping", errno); return; }
            close(marker);
            if (ACRegisterUARPAccessories() && ![fm removeItemAtPath:guard error:nil]) {
                AC_LOG(@"could not clear guard %@", guard);
            }
        } @catch (NSException *exception) {
            AC_LOG(@"initialization exception %@; remaining work skipped", exception.name);
        }
    }
}
