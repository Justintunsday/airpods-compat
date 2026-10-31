#import "../Core/Runtime.h"
#import <dlfcn.h>

BOOL ACMethodMatches(Class cls, SEL sel, const char *ret, NSArray<NSString *> *args, BOOL classMethod) {
    Method method = classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!method) return NO;
    const char *types = method_getTypeEncoding(method);
    if (!types) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:types];
    if (signature.numberOfArguments != args.count + 2 || strcmp(signature.methodReturnType, ret)) return NO;
    for (NSUInteger i = 0; i < args.count; i++) {
        const char *type = [signature getArgumentTypeAtIndex:i + 2];
        while (*type && strchr("rnNoORV", *type)) type++;
        if (strcmp(type, args[i].UTF8String)) return NO;
    }
    return YES;
}

BOOL ACClassOwnsSelector(Class cls, SEL sel) {
    unsigned count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned i = 0; i < count; i++) if (method_getName(methods[i]) == sel) { found = YES; break; }
    free(methods);
    return found;
}

void *ACResolveHeadphoneSymbol(const char *symbol) {
    // nm prints the Mach-O '_' prefix; dlsym expects the exported spelling.
    const char *lookup = symbol[0] == '_' ? symbol + 1 : symbol;
    void *address = dlsym(RTLD_DEFAULT, lookup);
    if (!address) return NULL;
    Dl_info info = {};
    if (!dladdr(address, &info) || !info.dli_fname ||
        !strstr(info.dli_fname, "/HeadphoneManager.framework/HeadphoneManager")) return NULL;
    return address;
}

BOOL ACNativeAirPods5FeatureContent(void) {
    return ACResolveHeadphoneSymbol("_$s16HeadphoneManager18B868FeatureContentCMa") != NULL ||
           NSClassFromString(@"_TtC16HeadphoneManager18B868FeatureContent") != Nil;
}

BOOL ACNativeProductRecord(uint32_t productID) {
    Class cls = objc_getClass("CBProductInfo");
    SEL lookup = @selector(productInfoWithProductID:);
    if (!ACMethodMatches(cls, lookup, "@", @[@"I"], YES) ||
        !ACMethodMatches(cls, @selector(productID), "I", @[], NO)) return NO;
    id record = ((id (*)(id, SEL, unsigned))objc_msgSend)(cls, lookup, productID);
    return record && ((unsigned (*)(id, SEL))objc_msgSend)(record, @selector(productID)) == productID;
}
