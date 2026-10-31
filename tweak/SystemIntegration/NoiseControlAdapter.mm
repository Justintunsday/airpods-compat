#import "../Core/Runtime.h"
#import "NoiseControlAdapter.h"
#include "../Models/ListeningModePolicy.h"
#import <dlfcn.h>

static id ACNoiseDevice(id preferredDevice) {
    static void *framework;
    if (!framework) framework = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_LAZY);
    if (!framework) return nil;
    // HeadphoneConfigs' BTSDeviceClassic wraps BluetoothDevice on iOS 16.
    // Its classicDevice getter is an object-returning API verified on device.
    if (preferredDevice && ACMethodMatches(object_getClass(preferredDevice), @selector(classicDevice), "@", @[], NO)) {
        preferredDevice = ((id (*)(id, SEL))objc_msgSend)(preferredDevice, @selector(classicDevice));
        if (!preferredDevice) return nil;
    }
    Class managerClass = NSClassFromString(@"BluetoothManager");
    if (!ACMethodMatches(managerClass, @selector(sharedInstance), "@", @[], YES) ||
        !ACMethodMatches(managerClass, @selector(connectedDevices), "@", @[], NO)) return nil;
    id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, @selector(sharedInstance));
    id connected = ((id (*)(id, SEL))objc_msgSend)(manager, @selector(connectedDevices));
    if (![connected isKindOfClass:NSArray.class]) return nil;
    id selected = nil;
    for (id device in connected) {
        if (preferredDevice && device != preferredDevice) {
            // HeadphoneConfigs may wrap a native BluetoothDevice. Match only a
            // verified address getter on both objects; never compare names or
            // spoof a product ID. Addresses remain transient and are not logged.
            if (!ACMethodMatches(object_getClass(preferredDevice), @selector(address), "@", @[], NO) ||
                !ACMethodMatches(object_getClass(device), @selector(address), "@", @[], NO)) continue;
            id lhs = ((id (*)(id, SEL))objc_msgSend)(preferredDevice, @selector(address));
            id rhs = ((id (*)(id, SEL))objc_msgSend)(device, @selector(address));
            if (![lhs isKindOfClass:NSString.class] || ![rhs isKindOfClass:NSString.class] ||
                ![lhs length] || [lhs caseInsensitiveCompare:rhs] != NSOrderedSame) continue;
        }
        Class cls = object_getClass(device);
        // productId (lowercase d) is the unmodified hardware getter. Never use
        // the legacy presentation productID alias or a name to select hardware.
        if (!ACMethodMatches(cls, @selector(productId), "I", @[], NO) ||
            !ACMethodMatches(cls, @selector(vendorId), "I", @[], NO) ||
            !ACMethodMatches(cls, @selector(listeningMode), "I", @[], NO) ||
            !ACMethodMatches(cls, @selector(listeningModeConfigs), "I", @[], NO) ||
            !ACMethodMatches(cls, @selector(setListeningMode:), "B", @[@"I"], NO)) continue;
        unsigned pid = ((unsigned (*)(id, SEL))objc_msgSend)(device, @selector(productId));
        unsigned vendor = ((unsigned (*)(id, SEL))objc_msgSend)(device, @selector(vendorId));
        if (!ACIsAirPods5(pid) || vendor != 0x004c) continue;
        if (selected) return nil; // ambiguous: never choose the wrong headphones
        selected = device;
    }
    return selected;
}

static NSDictionary *ACNoiseSnapshot(id device) {
    if (!device) return @{@"available": @NO, @"reason": @"No single connected AirPods 5 with a supported control API."};
    unsigned pid = ((unsigned (*)(id, SEL))objc_msgSend)(device, @selector(productId));
    unsigned vendor = ((unsigned (*)(id, SEL))objc_msgSend)(device, @selector(vendorId));
    unsigned current = ((unsigned (*)(id, SEL))objc_msgSend)(device, @selector(listeningMode));
    unsigned mask = ((unsigned (*)(id, SEL))objc_msgSend)(device, @selector(listeningModeConfigs));
    unsigned os = (unsigned)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
    NSMutableArray *allowed = [NSMutableArray array];
    for (unsigned mode = 1; mode <= 4; mode++)
        if (ACListeningModeAllowed(pid, vendor, os, true, true, mask, current, mode)) [allowed addObject:@(mode)];
    return @{@"available": @(allowed.count > 0), @"hardwareProductID": @(pid),
             @"vendorID": @(vendor),
             @"currentMode": @(current), @"reportedModeConfigs": @(mask), @"allowedModes": allowed};
}

NSDictionary *ACNoiseControlSnapshot(id preferredDevice) {
    NSDictionary *preferences = ACReadPreferences();
    if (!gEnabled || (preferences[@"NoiseControlsEnabled"] &&
                     ![preferences[@"NoiseControlsEnabled"] boolValue]))
        return @{@"available": @NO, @"reason": @"Noise controls are disabled."};
    return ACNoiseSnapshot(ACNoiseDevice(preferredDevice));
}

BOOL ACNoiseControlSetMode(id preferredDevice, unsigned mode, NSString **reason) {
    id device = ACNoiseDevice(preferredDevice);
    NSDictionary *snapshot = device ? ACNoiseControlSnapshot(device) : @{@"available": @NO};
    if (![snapshot[@"available"] boolValue] || ![snapshot[@"allowedModes"] containsObject:@(mode)]) {
        if (reason) *reason = snapshot[@"reason"] ?: @"The device/OS has not reported this listening mode.";
        return NO;
    }
    if ([snapshot[@"currentMode"] unsignedIntValue] == mode) return YES;
    // Native BluetoothManager dispatches AACP control setting 0x0d. The on-device
    // instruction trace matches LibrePods' independently documented protocol ID.
    // Keep iOS in charge of transport, authorization and physical-earbud limits.
    bool accepted = ((bool (*)(id, SEL, unsigned))objc_msgSend)(device, @selector(setListeningMode:), mode);
    if (!accepted && reason) *reason = @"iOS rejected the listening-mode command. Check the earbuds and connection.";
    return accepted;
}
