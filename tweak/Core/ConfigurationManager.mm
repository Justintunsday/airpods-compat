#import "Runtime.h"
#import <rootless.h>
BOOL gDiagnosticLogs = NO;
NSDictionary *gConfig;
BOOL gEnabled = YES, gUARPEnabled = YES, gScopeAll = NO;
BOOL gBorrowEnabled = YES;
uint32_t gBorrowProductID = 0x201b;
BOOL gLegacyUIProfileEnabled = NO, gLegacyIconProfileEnabled = NO;
uint32_t gLegacyUIProductID = 0x2013, gLegacyIconProductID = 0x2013;
NSDictionary<NSNumber *, NSString *> *gDisplayNames;
NSDictionary *ACReadPreferences(void) {
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:ACPrefsPath()];
    NSMutableDictionary *valid = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"Enabled", @"UARPEnabled", @"DiagnosticsEnabled",
                            @"LegacyRouteResourcesEnabled", @"LegacyBatteryResourcesEnabled"]) {
        if ([stored[key] isKindOfClass:NSNumber.class]) valid[key] = stored[key];
    }
    for (NSString *key in @[@"Scope", @"BorrowProfile", @"LegacyUIProfile", @"LegacyIconProfile"]) {
        if ([stored[key] isKindOfClass:NSString.class]) valid[key] = stored[key];
    }
    return valid;
}
NSString *ACSupportPath(NSString *name) {
    return [ROOT_PATH_NS(@"/Library/Application Support/AirPodsCompat") stringByAppendingPathComponent:name];
}

NSString *ACPrefsPath(void) {
    // User data is outside the jailbreak installation prefix.
    return @"/var/mobile/Library/Preferences/com.justintunsday.airpodscompat.plist";
}

NSString *ACProcessName(void) {
    return NSProcessInfo.processInfo.processName;
}

void ACLoadConfig(void) {
    gConfig = [NSDictionary dictionaryWithContentsOfFile:ACSupportPath(@"AirPodsCompatModels.plist")] ?: @{};

    NSDictionary *prefs = ACReadPreferences();
    gDiagnosticLogs = [prefs[@"DiagnosticsEnabled"] boolValue];
    if (prefs[@"Enabled"]) {
        gEnabled = [prefs[@"Enabled"] boolValue];
    }
    if (prefs[@"UARPEnabled"]) {
        gUARPEnabled = [prefs[@"UARPEnabled"] boolValue];
    }
    gScopeAll = [prefs[@"Scope"] isEqualToString:@"all"];

    NSString *borrow = @(ACModernProfile([prefs[@"BorrowProfile"] UTF8String]));
    if ([borrow isEqualToString:@"off"]) {
        gBorrowEnabled = NO;
    } else if ([borrow isEqualToString:@"airpodspro2"]) {
        gBorrowProductID = kAirPodsPro2ProductID;
    } else if ([borrow isEqualToString:@"airpodspro3"]) {
        gBorrowProductID = kAirPodsPro3ProductID;
    } else {
        gBorrowProductID = kAirPods4AncProductID;
    }

    gLegacyUIProductID = 0x2013;
    gLegacyUIProfileEnabled =
        NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 18;
    NSString *legacyUI = prefs[@"LegacyUIProfile"];
    if ([legacyUI isEqualToString:@"off"]) {
        gLegacyUIProfileEnabled = NO;
    } else if ([legacyUI isEqualToString:@"airpods4anc"]) {
        gLegacyUIProfileEnabled = YES;
        gLegacyUIProductID = kAirPods4AncProductID;
    } else if ([legacyUI isEqualToString:@"airpods3"]) {
        gLegacyUIProfileEnabled = YES;
        gLegacyUIProductID = 0x2013;
    } else if ([legacyUI isEqualToString:@"airpodspro2"] || [legacyUI isEqualToString:@"pro2"]) {
        gLegacyUIProfileEnabled = YES;
        gLegacyUIProductID = kAirPodsPro2ProductID;
    } else if ([legacyUI isEqualToString:@"airpodspro3"]) {
        gLegacyUIProfileEnabled = YES;
        gLegacyUIProductID = kAirPodsPro3ProductID;
    }

    gLegacyIconProductID = 0x2013;
    gLegacyIconProfileEnabled =
        NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 18;
    NSString *legacyIcon = prefs[@"LegacyIconProfile"];
    if ([legacyIcon isEqualToString:@"off"]) {
        gLegacyIconProfileEnabled = NO;
    } else if ([legacyIcon isEqualToString:@"pro2"] ||
               [legacyIcon isEqualToString:@"airpodspro2"]) {
        gLegacyIconProfileEnabled = YES;
        gLegacyIconProductID = kAirPodsPro2ProductID;
    } else if ([legacyIcon isEqualToString:@"airpods3"] ||
               [legacyIcon isEqualToString:@"airpods4anc"]) {
        gLegacyIconProfileEnabled = YES;
        gLegacyIconProductID = 0x2013;
    }

    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    [gConfig[@"DisplayNames"] enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *name, BOOL *stop) {
        names[@(key.intValue)] = name;
    }];
    gDisplayNames = names;

    AC_LOG(@"config: uarp=%lu scope=%@ enabled=%d uarpEnabled=%d borrow=%@ legacyUI=%@ legacyIcon=%@ process=%@",
           (unsigned long)[gConfig[@"UARP"] count], gScopeAll ? @"all" : @"core",
           gEnabled, gUARPEnabled,
           gBorrowEnabled ? [NSString stringWithFormat:@"0x%x", gBorrowProductID] : @"off",
           gLegacyUIProfileEnabled ? [NSString stringWithFormat:@"0x%x", gLegacyUIProductID] : @"off",
           gLegacyIconProfileEnabled ? [NSString stringWithFormat:@"0x%x", gLegacyIconProductID] : @"off",
           ACProcessName());
}


