#import "../Core/Runtime.h"
static NSMutableDictionary<NSString *, NSDictionary *> *gClassTable;
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
    return ACProcessOwnsRegistry(ACProcessName().UTF8String);
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
    if (!ACMethodMatches(managerClass, @selector(defaultManager), "@", @[], YES) ||
        !ACMethodMatches(managerClass, @selector(addSupportedAccessory:), "v", @[@"@"], NO)) return;
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

void ACInstallAccessoryRegistration(void) {
    if (!gUARPEnabled || !ACProcessOwnsAccessoryDatabase()) return;
    gClassTable = [NSMutableDictionary dictionary];
    ACWithRegistrationGuard(^{ ACRegisterUARPAccessories(); });
}
