// Native resource factories only. The iOS 16 algorithm retains its tested target.
#import "../LegacyResourcePolicy.h"
#import "../Core/Runtime.h"
#import <objc/message.h>

static __thread unsigned int gACRouteResourceDepth;
static id (*orig_ACRouteModel)(id, SEL);
static id (*orig_ACResourceAssetInit)(id, SEL, id);
static id (*orig_ACBatteryGlyphName)(id, SEL, BOOL *);
static id (*orig_ACRouteSymbol)(id, SEL, id);
static id (*orig_ACRoutesSymbol)(id, SEL, id);
static id (*orig_ACRouteImage)(id, SEL, id);
static id (*orig_ACRoutesImage)(id, SEL, id);

static BOOL ACIsResourceUIProcess(void) {
    NSString *name = ACProcessName();
    if ([name isEqualToString:@"SpringBoard"]) return YES;
    NSString *path = NSBundle.mainBundle.bundlePath;
    return objc_getClass("UIApplication") &&
           ([path hasSuffix:@".app"] || [path hasSuffix:@".appex"]);
}

static id ACWithRouteResourceScope(id self, SEL cmd, id arg, id (*original)(id, SEL, id)) {
    gACRouteResourceDepth++;
    @try { return original(self, cmd, arg); }
    @finally { gACRouteResourceDepth--; }
}

static id ACRouteSymbol(id self, SEL cmd, id route) {
    return ACWithRouteResourceScope(self, cmd, route, orig_ACRouteSymbol);
}
static id ACRoutesSymbol(id self, SEL cmd, id routes) {
    return ACWithRouteResourceScope(self, cmd, routes, orig_ACRoutesSymbol);
}
static id ACRouteImage(id self, SEL cmd, id route) {
    return ACWithRouteResourceScope(self, cmd, route, orig_ACRouteImage);
}
static id ACRoutesImage(id self, SEL cmd, id routes) {
    return ACWithRouteResourceScope(self, cmd, routes, orig_ACRoutesImage);
}

static BOOL ACSignatureMatches(Class cls, SEL sel, const char *ret, NSArray<NSString *> *args,
                               BOOL classMethod) {
    Method method = classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!method) return NO;
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (sig.numberOfArguments != args.count + 2 || strcmp(sig.methodReturnType, ret)) return NO;
    for (NSUInteger i = 0; i < args.count; i++) {
        const char *type = [sig getArgumentTypeAtIndex:i + 2];
        // Direction qualifiers do not change pointer ABI (battery uses o^B).
        while (*type && strchr("rnNoORV", *type)) type++;
        if (strcmp(type, args[i].UTF8String)) return NO;
    }
    return YES;
}

static id ACResourceRouteModel(id self, SEL cmd) {
    id model = orig_ACRouteModel(self, cmd);
    if (gACRouteResourceDepth && [model isKindOfClass:NSString.class] &&
        ACIsAirPods5RouteModel([model UTF8String])) {
        unsigned os = (unsigned)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
        if (os == 16) return @"BTHeadphones76,8211";
        uint32_t pid = ACRouteModelProductID([model UTF8String]);
        ACCompatibilityEnvironment environment = {os, (bool)gEnabled, (bool)gBorrowEnabled,
            (bool)ACNativeProductRecord(pid), (bool)ACNativeProductRecord(0x201b), 0};
        auto decision = ACCompatibilitySelect(pid, ACContextRouteResource, environment);
        if (decision.lookupProductID != pid) return @"BTHeadphones76,8219";
    }
    return model;
}

static id ACResourceAssetInit(id self, SEL cmd, id route) {
    // The original factory queries each member's productIdentifier while constructing
    // native/composite symbols. Confine borrowing to that synchronous resource lookup.
    gACRouteResourceDepth++;
    @try {
        return orig_ACResourceAssetInit(self, cmd, route);
    } @finally {
        gACRouteResourceDepth--;
    }
}

static id ACBatteryGlyphName(id self, SEL cmd, BOOL *isImage) {
    id original = orig_ACBatteryGlyphName(self, cmd, isImage);
    NSInteger pid = ((NSInteger (*)(id, SEL))objc_msgSend)(self, @selector(productIdentifier));
    NSInteger vendor = ((NSInteger (*)(id, SEL))objc_msgSend)(self, @selector(vendor));
    NSInteger transport = ((NSInteger (*)(id, SEL))objc_msgSend)(self, @selector(transportType));
    unsigned os = (unsigned)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
    uint32_t mapped = (uint32_t)pid;
    if (pid >= 0 && pid <= UINT32_MAX) {
        if (os == 16) mapped = ACBatteryResourcePID((uint32_t)pid, vendor, transport);
        else if (vendor == 1 && transport == 3 &&
                 (!original || [original isEqual:@"headphones"])) {
            ACCompatibilityEnvironment environment = {os, (bool)gEnabled, (bool)gBorrowEnabled,
                (bool)ACNativeProductRecord((uint32_t)pid), (bool)ACNativeProductRecord(0x201b), 0};
            mapped = ACCompatibilitySelect((uint32_t)pid, ACContextBatteryResource, environment).lookupProductID;
        }
    }
    if (pid < 0 || pid > UINT32_MAX || mapped == (uint32_t)pid) return original;

    Class cls = objc_getClass("BCBatteryDevice");
    NSUInteger parts = ((NSUInteger (*)(id, SEL))objc_msgSend)(self, @selector(parts));
    // Modern part-enum semantics have no device evidence: preserve every part,
    // including Single, instead of extending the iOS 16 combined-glyph rule.
    NSUInteger resourceParts = os == 16 ? ACBatteryResourceParts((uint32_t)pid, vendor, transport, parts) : parts;
    // A disposable resource model: never replace/merge the live battery device.
    id resource = ((id (*)(id, SEL, id, NSInteger, NSInteger, NSUInteger, id))objc_msgSend)(
        cls, @selector(batteryDeviceWithIdentifier:vendor:productIdentifier:parts:matchIdentifier:),
        @"AirPodsCompat-resource", vendor, (NSInteger)mapped, resourceParts, @"AirPodsCompat-resource");
    if (!resource) return original;
    NSUInteger category = ((NSUInteger (*)(id, SEL))objc_msgSend)(self, @selector(accessoryCategory));
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(resource, @selector(setTransportType:), transport);
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(resource, @selector(setAccessoryCategory:), category);
    BOOL borrowedIsImage = NO;
    id borrowed = orig_ACBatteryGlyphName(resource, cmd, &borrowedIsImage);
    if (![borrowed isKindOfClass:NSString.class] || ![borrowed length] ||
        [borrowed isEqualToString:@"headphones"]) return original;
    if (isImage) *isImage = borrowedIsImage;
    ACRecordHookStatus(@"battery", @"borrowed-presentation-only");
    return borrowed;
}

void ACInstallLegacyResources(void) {
    unsigned os = (unsigned)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
    if (!ACIsResourceUIProcess() || (os != 16 && os != 18 && os != 26)) return;
    if (os >= 18 && (!gBorrowEnabled || !ACNativeProductRecord(0x201b))) return;
    Class route = objc_getClass("MPAVOutputDeviceRoute");
    Class asset = objc_getClass("MRUOutputDeviceAsset");
    if (gRouteResourcesEnabled && !orig_ACRouteModel &&
        ACSignatureMatches(route, @selector(productIdentifier), "@", @[], NO)) {
        MSHookMessageEx(route, @selector(productIdentifier), (IMP)ACResourceRouteModel,
                        (IMP *)&orig_ACRouteModel);
        if (orig_ACRouteModel) ACRecordHookStatus(@"route", @"installed-scoped-lookup");
    }
    if (gRouteResourcesEnabled && orig_ACRouteModel && !orig_ACResourceAssetInit &&
        ACSignatureMatches(asset, @selector(initWithOutputDeviceRoute:), "@", @[@"@"], NO)) {
        MSHookMessageEx(asset, @selector(initWithOutputDeviceRoute:), (IMP)ACResourceAssetInit,
                        (IMP *)&orig_ACResourceAssetInit);
    }
    Class controller = objc_getClass("MPAVRoutingController");
    if (gRouteResourcesEnabled && orig_ACRouteModel && controller) {
        struct { const char *sel; IMP replacement; id (**original)(id, SEL, id); } symbols[] = {
            {"_symbolNameForRoute:", (IMP)ACRouteSymbol, &orig_ACRouteSymbol},
            {"_symbolNameForRoutes:", (IMP)ACRoutesSymbol, &orig_ACRoutesSymbol},
            {"_symbolImageForRoute:", (IMP)ACRouteImage, &orig_ACRouteImage},
            {"_symbolImageForRoutes:", (IMP)ACRoutesImage, &orig_ACRoutesImage},
        };
        for (unsigned i = 0; i < sizeof(symbols)/sizeof(symbols[0]); i++) {
            SEL sel = sel_registerName(symbols[i].sel);
            if (!*symbols[i].original && ACSignatureMatches(controller, sel, "@", @[@"@"], YES)) {
                MSHookMessageEx(object_getClass(controller), sel, symbols[i].replacement,
                                (IMP *)symbols[i].original);
            }
        }
    }
    if (![ACProcessName() isEqualToString:@"SpringBoard"]) return;
    Class battery = objc_getClass("BCBatteryDevice");
    if (!gBatteryResourcesEnabled || orig_ACBatteryGlyphName || !battery) return;
    if (!ACSignatureMatches(battery, @selector(batteryWidgetGlyphName:), "@", @[@"^B"], NO) ||
        !ACSignatureMatches(battery,
          @selector(batteryDeviceWithIdentifier:vendor:productIdentifier:parts:matchIdentifier:),
          "@", @[@"@", @"q", @"q", @"Q", @"@"], YES)) return;
    for (NSString *getter in @[@"productIdentifier", @"vendor", @"transportType"]) {
        if (!ACSignatureMatches(battery, NSSelectorFromString(getter), "q", @[], NO)) return;
    }
    if (!ACSignatureMatches(battery, @selector(parts), "Q", @[], NO) ||
        !ACSignatureMatches(battery, @selector(accessoryCategory), "Q", @[], NO) ||
        !ACSignatureMatches(battery, @selector(setTransportType:), "v", @[@"q"], NO) ||
        !ACSignatureMatches(battery, @selector(setAccessoryCategory:), "v", @[@"Q"], NO)) return;
    MSHookMessageEx(battery, @selector(batteryWidgetGlyphName:), (IMP)ACBatteryGlyphName,
                    (IMP *)&orig_ACBatteryGlyphName);
}
