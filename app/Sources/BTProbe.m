#import "BTProbe.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *ACProbeStringValue(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        @try {
            id value = [object valueForKey:key];
            if (value != nil) {
                return [value description];
            }
        } @catch (NSException *exception) {
            (void)exception;
        }
        SEL sel = NSSelectorFromString(key);
        if ([object respondsToSelector:sel]) {
            @try {
                id value = ((id (*)(id, SEL))objc_msgSend)(object, sel);
                if (value != nil) {
                    return [value description];
                }
            } @catch (NSException *exception) {
                (void)exception;
            }
        }
    }
    return nil;
}

NSArray<NSString *> *ACProbeConnectedBluetoothDevices(void) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    void *handle = dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager",
                          RTLD_NOW);
    if (handle == NULL) {
        [lines addObject:@"私有 BluetoothManager 不可用（沙箱/未越狱限制）"];
        return lines;
    }

    Class managerClass = NSClassFromString(@"BluetoothManager");
    if (managerClass == Nil) {
        [lines addObject:@"BluetoothManager 类不存在"];
        return lines;
    }

    @try {
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if (![managerClass respondsToSelector:sharedSel]) {
            [lines addObject:@"BluetoothManager 无 sharedInstance"];
            return lines;
        }
        id manager = ((id (*)(id, SEL))objc_msgSend)((id)managerClass, sharedSel);

        SEL connectedSel = NSSelectorFromString(@"connectedDevices");
        if (![manager respondsToSelector:connectedSel]) {
            [lines addObject:@"BluetoothManager 无 connectedDevices"];
            return lines;
        }
        NSArray *devices = ((id (*)(id, SEL))objc_msgSend)(manager, connectedSel);
        if (![devices isKindOfClass:[NSArray class]] || devices.count == 0) {
            [lines addObject:@"connectedDevices 为空（无已连接设备或需蓝牙权限）"];
            return lines;
        }

        NSUInteger index = 0;
        for (id device in devices) {
            index++;
            NSString *name = ACProbeStringValue(device, @[ @"name" ]);
            NSString *address = ACProbeStringValue(device, @[ @"address", @"addressString" ]);
            NSString *productID = ACProbeStringValue(device, @[ @"productId", @"productID", @"productIdentifier" ]);
            NSString *vendorID = ACProbeStringValue(device, @[ @"vendorId", @"vendorID" ]);
            NSString *classString = NSStringFromClass([device class]);

            NSMutableArray<NSString *> *parts = [NSMutableArray array];
            [parts addObject:[NSString stringWithFormat:@"#%lu %@", (unsigned long)index,
                              name ?: @"(未知名称)"]];
            if (address.length) [parts addObject:[NSString stringWithFormat:@"addr=%@", address]];
            if (productID.length) [parts addObject:[NSString stringWithFormat:@"pid=%@", productID]];
            if (vendorID.length) [parts addObject:[NSString stringWithFormat:@"vid=%@", vendorID]];
            [parts addObject:[NSString stringWithFormat:@"cls=%@", classString]];
            [lines addObject:[parts componentsJoinedByString:@" "]];
        }
    } @catch (NSException *exception) {
        [lines addObject:[NSString stringWithFormat:@"枚举异常：%@", exception.reason ?: exception.name]];
    }

    return lines;
}
