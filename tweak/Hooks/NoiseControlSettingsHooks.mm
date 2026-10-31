#import "../Core/Runtime.h"
#import "../SystemIntegration/NoiseControlAdapter.h"
#import <UIKit/UIKit.h>

static id (*originalSpecifiers)(id, SEL);
static const void *deviceKey = &deviceKey;

static void ACNoiseAction(id controller, unsigned mode) {
    id device = objc_getAssociatedObject(controller, deviceKey);
    NSString *reason = nil;
    if (!ACNoiseControlSetMode(device, mode, &reason)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Noise Control unavailable"
            message:reason preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [(UIViewController *)controller presentViewController:alert animated:YES completion:nil];
        ACRecordHookStatus(@"noise-control", @"native-command-rejected");
        return;
    }
    ACRecordHookStatus(@"noise-control", @"native-command-accepted-awaiting-readback");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSDictionary *snapshot = ACNoiseControlSnapshot(device);
        ACRecordHookStatus(@"noise-control", [snapshot[@"currentMode"] unsignedIntValue] == mode
            ? @"native-mode-readback-matched" : @"native-mode-readback-not-confirmed");
        if (ACMethodMatches(object_getClass(controller), @selector(reloadSpecifiers), "v", @[], NO))
            ((void (*)(id, SEL))objc_msgSend)(controller, @selector(reloadSpecifiers));
    });
}
static void ACNoiseANC(id self, SEL cmd) { (void)cmd; ACNoiseAction(self, 2); }
static void ACNoiseTransparency(id self, SEL cmd) { (void)cmd; ACNoiseAction(self, 3); }
static void ACNoiseOff(id self, SEL cmd) { (void)cmd; ACNoiseAction(self, 1); }

static id ACNoiseSpecifiers(id controller, SEL selector) {
    id original = originalSpecifiers(controller, selector);
    if (![original isKindOfClass:NSArray.class]) return original;
    id device = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(device));
    NSDictionary *snapshot = ACNoiseControlSnapshot(device);
    if (!device || ![snapshot[@"available"] boolValue]) return original;
    objc_setAssociatedObject(controller, deviceKey, device, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    Class specifier = NSClassFromString(@"PSSpecifier");
    NSMutableArray *result = [NSMutableArray array];
    // Drop only our own previous rows when a native controller caches its array.
    for (id entry in original) {
        if (![entry isKindOfClass:specifier]) { [result addObject:entry]; continue; }
        id identifier = ((id (*)(id, SEL, id))objc_msgSend)(entry, @selector(propertyForKey:), @"id");
        if ([identifier isKindOfClass:NSString.class] && [identifier hasPrefix:@"AirPodsCompat.Noise."]) continue;
        [result addObject:entry];
    }
    id group = ((id (*)(id, SEL, id))objc_msgSend)(specifier, @selector(groupSpecifierWithName:), @"AirPods Noise Control");
    ((void (*)(id, SEL, id, id))objc_msgSend)(group, @selector(setProperty:forKey:), @"AirPodsCompat.Noise.Group", @"id");
    NSString *footer = [NSString stringWithFormat:@"Device-reported mode: %@. Rejected commands leave the current mode unchanged.", snapshot[@"currentMode"]];
    ((void (*)(id, SEL, id, id))objc_msgSend)(group, @selector(setProperty:forKey:), footer, @"footerText");
    [result addObject:group];
    struct { unsigned mode; NSString *name; const char *action; } modes[] = {
        {2, @"Noise Cancellation", "ac_compatNoiseANC"},
        {3, @"Transparency", "ac_compatNoiseTransparency"},
        {1, @"Off", "ac_compatNoiseOff"}
    };
    for (auto &mode : modes) {
        if (![snapshot[@"allowedModes"] containsObject:@(mode.mode)]) continue;
        id row = ((id (*)(id, SEL, id, id, SEL, SEL, Class, NSInteger, Class))objc_msgSend)(specifier,
            @selector(preferenceSpecifierNamed:target:set:get:detail:cell:edit:),
            mode.name, controller, NULL, NULL, Nil, 13 /* PSButtonCell */, Nil);
        ((void (*)(id, SEL, SEL))objc_msgSend)(row, @selector(setButtonAction:), sel_registerName(mode.action));
        NSString *identifier = [NSString stringWithFormat:@"AirPodsCompat.Noise.%u", mode.mode];
        ((void (*)(id, SEL, id, id))objc_msgSend)(row, @selector(setProperty:forKey:), identifier, @"id");
        [result addObject:row];
    }
    return result;
}

void ACInstallNoiseControlSettingsHooks(void) {
    unsigned os = (unsigned)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
    if (originalSpecifiers || os < 16 || os > 18 || ![ACProcessName() isEqualToString:@"Preferences"]) return;
    Class cls = NSClassFromString(@"BTSDeviceConfigController");
    Class specifier = NSClassFromString(@"PSSpecifier");
    if (!ACMethodMatches(cls, @selector(specifiers), "@", @[], NO) ||
        !ACMethodMatches(cls, @selector(device), "@", @[], NO) ||
        !ACMethodMatches(specifier, @selector(groupSpecifierWithName:), "@", @[@"@"], YES) ||
        !ACMethodMatches(specifier, @selector(propertyForKey:), "@", @[@"@"], NO) ||
        !ACMethodMatches(specifier, @selector(setProperty:forKey:), "v", @[@"@", @"@"], NO) ||
        !ACMethodMatches(specifier, @selector(setButtonAction:), "v", @[@":"], NO) ||
        !ACMethodMatches(specifier, @selector(preferenceSpecifierNamed:target:set:get:detail:cell:edit:),
                         "@", @[@"@", @"@", @":", @":", @"#", @"q", @"#"], YES)) return;
    if (class_getInstanceMethod(cls, sel_registerName("ac_compatNoiseANC"))) return;
    class_addMethod(cls, sel_registerName("ac_compatNoiseANC"), (IMP)ACNoiseANC, "v@:");
    class_addMethod(cls, sel_registerName("ac_compatNoiseTransparency"), (IMP)ACNoiseTransparency, "v@:");
    class_addMethod(cls, sel_registerName("ac_compatNoiseOff"), (IMP)ACNoiseOff, "v@:");
    MSHookMessageEx(cls, @selector(specifiers), (IMP)ACNoiseSpecifiers, (IMP *)&originalSpecifiers);
    if (originalSpecifiers) ACRecordHookStatus(@"noise-control", @"settings-controls-installed");
}
