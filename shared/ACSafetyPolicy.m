#import "ACSafetyPolicy.h"
#import <objc/runtime.h>
#import <string.h>
#import <stdint.h>

static const char *ACUnqualifiedType(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}

BOOL ACBoolPreference(id preferences, NSString *key, BOOL defaultValue) {
    if (![preferences isKindOfClass:NSDictionary.class]) return NO;
    id value = preferences[key];
    if (!value) return defaultValue;
    if (![value isKindOfClass:NSNumber.class]) return NO;
    return [value isEqual:@YES];
}

BOOL ACFullModelScope(id preferences) {
    if (![preferences isKindOfClass:NSDictionary.class]) return NO;
    id scope = preferences[@"Scope"];
    return [scope isKindOfClass:NSString.class] && [scope isEqualToString:@"all"];
}

static BOOL ACModelNumberIsValid(id value) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *number = value;
    if (number.length != 5 && number.length != 8) return NO;
    if ([number characterAtIndex:0] != 'A') return NO;
    for (NSUInteger i = 1; i < 5; i++) {
        unichar character = [number characterAtIndex:i];
        if (character < '0' || character > '9') return NO;
    }
    return number.length == 5 || [[number substringFromIndex:5] isEqualToString:@"USB"];
}

static BOOL ACProductIDIsValid(id value) {
    if (![value isKindOfClass:NSNumber.class]) return NO;
    if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    double number = [value doubleValue];
    return number >= 1 && number <= UINT16_MAX && number == [value unsignedIntValue];
}

NSArray<NSDictionary *> *ACValidatedModels(id models) {
    if (![models isKindOfClass:NSArray.class] || [models count] > 64) return @[];
    NSSet *allowedBases = [NSSet setWithArray:@[
        @"UARPSupportedAccessoryAirPodsBud", @"UARPSupportedAccessoryAirPodsCase",
        @"UARPSupportedAccessoryAirPodsCaseUSB", @"UARPSupportedAccessoryBeatsBluetooth"
    ]];
    NSMutableSet *identifiers = [NSMutableSet set];
    NSMutableSet *productIDs = [NSMutableSet set];
    NSMutableArray *validated = [NSMutableArray array];
    for (id entry in models) {
        if (![entry isKindOfClass:NSDictionary.class]) return @[];
        id model = entry[@"model"], appleModel = entry[@"appleModelNumber"], pid = entry[@"productID"];
        id tier = entry[@"tier"], bases = entry[@"baseClasses"];
        if (!ACModelNumberIsValid(model) || !ACModelNumberIsValid(appleModel) || !ACProductIDIsValid(pid)
            || ![tier isKindOfClass:NSString.class]
            || ![@[@"core", @"extended"] containsObject:tier]
            || ![bases isKindOfClass:NSArray.class] || [bases count] == 0 || [bases count] > 8
            || [identifiers containsObject:model] || [productIDs containsObject:pid]) return @[];

        // The first entry must be a reviewed abstract base. Never fall back to
        // a sibling's concrete class, even if the abstract initializer fails.
        id base = bases[0];
        if (![base isKindOfClass:NSString.class] || ![allowedBases containsObject:base]) return @[];
        id alternatives = entry[@"alternativeAppleModelNumbers"];
        if (alternatives) {
            if (![alternatives isKindOfClass:NSArray.class] || [alternatives count] > 8) return @[];
            for (id alternative in alternatives) {
                if (!ACModelNumberIsValid(alternative)) return @[];
            }
        }
        id mobileAsset = entry[@"mobileAssetAppleModelNumber"];
        if (mobileAsset && !ACModelNumberIsValid(mobileAsset)) return @[];

        NSMutableDictionary *copy = [entry mutableCopy];
        copy[@"baseClasses"] = @[base];
        [validated addObject:[copy copy]];
        [identifiers addObject:model];
        [productIDs addObject:pid];
    }
    return [validated copy];
}

NSDictionary<NSNumber *, NSString *> *ACValidatedDisplayNames(id names) {
    if (![names isKindOfClass:NSDictionary.class] || [names count] > 64) return @{};
    NSMutableDictionary *validated = [NSMutableDictionary dictionary];
    for (id key in names) {
        id name = names[key];
        if (![key isKindOfClass:NSString.class] || [key length] == 0 || [key length] > 5
            || ![name isKindOfClass:NSString.class] || [name length] == 0 || [name length] > 128) return @{};
        NSUInteger value = 0;
        for (NSUInteger i = 0; i < [key length]; i++) {
            unichar character = [key characterAtIndex:i];
            if (character < '0' || character > '9') return @{};
            value = value * 10 + character - '0';
        }
        if (value == 0 || value > UINT16_MAX || validated[@(value)]) return @{};
        validated[@(value)] = name;
    }
    return [validated copy];
}

BOOL ACMethodMatches(id target, SEL selector, char returnType, NSUInteger argumentCount, char argumentType) {
    if (!target || (argumentCount != 2 && argumentCount != 3)) return NO;
    Method method = class_getInstanceMethod(object_getClass(target), selector);
    if (!method || method_getNumberOfArguments(method) != argumentCount) return NO;
    char result[128] = {0};
    method_getReturnType(method, result, sizeof(result));
    if (*ACUnqualifiedType(result) != returnType) return NO;
    if (argumentCount == 3) {
        char argument[128] = {0};
        method_getArgumentType(method, 2, argument, sizeof(argument));
        if (*ACUnqualifiedType(argument) != argumentType) return NO;
    }
    return YES;
}

id ACReadNoArgumentValue(id target, SEL selector) {
    if (!target) return nil;
    Method method = class_getInstanceMethod(object_getClass(target), selector);
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    @try {
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (!signature || signature.numberOfArguments != 2) return nil;
        const char *type = ACUnqualifiedType(signature.methodReturnType);
        if (!strchr("@BcCsSiIlLqQ", *type) || !*type) return nil;
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.selector = selector;
        [invocation invokeWithTarget:target];
        if (*type == '@') {
            __unsafe_unretained id value = nil;
            [invocation getReturnValue:&value];
            return value;
        }
        // Scalars are boxed using their declared widths; they are never read
        // as object pointers (e.g. isConnected returning BOOL).
#define AC_BOX_RETURN(code, scalarType) \
        case code: { scalarType value = 0; [invocation getReturnValue:&value]; return @(value); }
        switch (*type) {
            AC_BOX_RETURN('B', BOOL)
            AC_BOX_RETURN('c', signed char)
            AC_BOX_RETURN('C', unsigned char)
            AC_BOX_RETURN('s', short)
            AC_BOX_RETURN('S', unsigned short)
            AC_BOX_RETURN('i', int)
            AC_BOX_RETURN('I', unsigned int)
            AC_BOX_RETURN('l', long)
            AC_BOX_RETURN('L', unsigned long)
            AC_BOX_RETURN('q', long long)
            AC_BOX_RETURN('Q', unsigned long long)
        }
#undef AC_BOX_RETURN
    } @catch (__unused NSException *exception) {}
    return nil;
}

NSNumber *ACProbeUnsignedNumber(id value) {
    if ([value isKindOfClass:NSNumber.class]) {
        double number = [value doubleValue];
        if (number >= 0 && number <= UINT32_MAX && number == [value unsignedIntValue]) return value;
        return nil;
    }
    if (![value isKindOfClass:NSString.class] || [value length] == 0 || [value length] > 12) return nil;
    NSString *text = value;
    NSScanner *scanner = [NSScanner scannerWithString:text];
    scanner.charactersToBeSkipped = nil;
    if ([text hasPrefix:@"0x"] || [text hasPrefix:@"0X"]) {
        unsigned long long parsed = 0;
        if ([scanner scanHexLongLong:&parsed] && scanner.isAtEnd && parsed <= UINT32_MAX) return @(parsed);
    } else {
        for (NSUInteger i = 0; i < text.length; i++) {
            unichar character = [text characterAtIndex:i];
            if (character < '0' || character > '9') return nil;
        }
        unsigned long long parsed = text.longLongValue;
        if (parsed <= UINT32_MAX) return @(parsed);
    }
    return nil;
}
