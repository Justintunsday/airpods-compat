#import "BTProbe.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *gProbeStatus = nil;

static id ACProbeValue(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        @try {
            id value = [object valueForKey:key];
            if (value != nil) {
                return value;
            }
        } @catch (NSException *exception) {
            (void)exception;
        }
        SEL sel = NSSelectorFromString(key);
        if ([object respondsToSelector:sel]) {
            @try {
                id value = ((id (*)(id, SEL))objc_msgSend)(object, sel);
                if (value != nil) {
                    return value;
                }
            } @catch (NSException *exception) {
                (void)exception;
            }
        }
    }
    return nil;
}

static NSString *ACProbeString(id object, NSArray<NSString *> *keys) {
    id value = ACProbeValue(object, keys);
    return value ? [value description] : nil;
}

static NSNumber *ACProbeNumber(id object, NSArray<NSString *> *keys) {
    id value = ACProbeValue(object, keys);
    if ([value isKindOfClass:[NSNumber class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSString class]]) {
        unsigned int parsed = 0;
        if ([[NSScanner scannerWithString:value] scanHexInt:&parsed]) {
            return @(parsed);
        }
    }
    return nil;
}

NSString *ACProbeBluetoothStatus(void) {
    return gProbeStatus;
}

static void ACProbeAppendDevices(NSArray *devices, NSMutableArray<NSDictionary *> *out, BOOL fromConnectedList) {
    if (![devices isKindOfClass:[NSArray class]]) {
        return;
    }
    for (id device in devices) {
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"className"] = NSStringFromClass([device class]);
        NSString *name = ACProbeString(device, @[ @"name" ]);
        if (name.length) entry[@"name"] = name;
        NSString *address = ACProbeString(device, @[ @"address", @"addressString" ]);
        if (address.length) entry[@"address"] = address;
        NSNumber *productID = ACProbeNumber(device, @[ @"productId", @"productID", @"productIdentifier" ]);
        if (productID) entry[@"productID"] = productID;
        NSNumber *vendorID = ACProbeNumber(device, @[ @"vendorId", @"vendorID" ]);
        if (vendorID) entry[@"vendorID"] = vendorID;
        NSNumber *connected = ACProbeNumber(device, @[ @"connected", @"isConnected" ]);
        entry[@"connected"] = fromConnectedList ? @YES : (connected ?: @NO);
        NSNumber *paired = ACProbeNumber(device, @[ @"paired", @"isPaired" ]);
        if (paired) entry[@"paired"] = paired;
        [out addObject:entry];
    }
}

NSArray<NSDictionary<NSString *, id> *> *ACProbeBluetoothDevices(void) {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    gProbeStatus = nil;

    void *handle = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager",
                          RTLD_NOW);
    if (handle == NULL) {
        gProbeStatus = @"私有 BluetoothManager 不可用（沙箱/未越狱限制）";
        return out;
    }

    Class managerClass = NSClassFromString(@"BluetoothManager");
    if (managerClass == Nil) {
        gProbeStatus = @"BluetoothManager 类不存在";
        return out;
    }

    @try {
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if (![managerClass respondsToSelector:sharedSel]) {
            gProbeStatus = @"BluetoothManager 无 sharedInstance";
            return out;
        }
        id manager = ((id (*)(id, SEL))objc_msgSend)((id)managerClass, sharedSel);
        if (!manager) {
            gProbeStatus = @"BluetoothManager.sharedInstance 为 nil";
            return out;
        }

        NSUInteger before = out.count;
        SEL connectedSel = NSSelectorFromString(@"connectedDevices");
        if ([manager respondsToSelector:connectedSel]) {
            ACProbeAppendDevices(((id (*)(id, SEL))objc_msgSend)(manager, connectedSel), out, YES);
        }
        NSUInteger connectedCount = out.count - before;

        SEL pairedSel = NSSelectorFromString(@"pairedDevices");
        if ([manager respondsToSelector:pairedSel]) {
            NSMutableArray *paired = [NSMutableArray array];
            ACProbeAppendDevices(((id (*)(id, SEL))objc_msgSend)(manager, pairedSel), paired, NO);
            // keep paired-only entries for context, connected first
            for (NSDictionary *entry in paired) {
                NSString *address = entry[@"address"];
                BOOL duplicate = NO;
                for (NSDictionary *existing in out) {
                    if (address.length && [existing[@"address"] isEqual:address]) {
                        duplicate = YES;
                        break;
                    }
                }
                if (!duplicate) {
                    [out addObject:entry];
                }
            }
        }

        if (out.count == 0) {
            gProbeStatus = @"connectedDevices/pairedDevices 为空（无已配对设备或需蓝牙权限）";
        } else {
            gProbeStatus = [NSString stringWithFormat:@"已连接 %lu，条目共 %lu",
                            (unsigned long)connectedCount, (unsigned long)out.count];
        }
    } @catch (NSException *exception) {
        gProbeStatus = [NSString stringWithFormat:@"枚举异常：%@", exception.reason ?: exception.name];
    }

    return out;
}
