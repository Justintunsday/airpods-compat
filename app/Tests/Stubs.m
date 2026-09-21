// Test stubs: the iOS Simulator does not ship the real CoreUARP accessory
// database, so we install minimal look-alike classes with the same names.
// This forces the registration dry-run through the full code path instead of
// skipping it.

#import <Foundation/Foundation.h>

@interface UARPSupportedAccessory : NSObject
@end

@implementation UARPSupportedAccessory
@end

@interface UARPSupportedAccessoryAirPodsBud : UARPSupportedAccessory
@end

@implementation UARPSupportedAccessoryAirPodsBud
@end

@interface UARPSupportedAccessoryAirPodsCase : UARPSupportedAccessory
@end

@implementation UARPSupportedAccessoryAirPodsCase
@end

@interface UARPSupportedAccessoryAirPodsCaseUSB : UARPSupportedAccessory
@end

@implementation UARPSupportedAccessoryAirPodsCaseUSB
@end

@interface UARPSupportedAccessoryBeatsBluetooth : UARPSupportedAccessory
@end

@implementation UARPSupportedAccessoryBeatsBluetooth
@end

@interface UARPSupportedAccessoryManager : NSObject
@end

@implementation UARPSupportedAccessoryManager {
    NSMutableSet *_accessories;
}

+ (instancetype)defaultManager {
    static UARPSupportedAccessoryManager *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        manager = [[UARPSupportedAccessoryManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    if ((self = [super init])) {
        _accessories = [NSMutableSet set];
    }
    return self;
}

- (void)addSupportedAccessory:(id)accessory {
    if (accessory) {
        [_accessories addObject:accessory];
    }
}

- (NSSet *)setOfAccessories {
    return [_accessories copy];
}

- (id)findByIdentifier:(id)identifier {
    for (id accessory in _accessories) {
        if ([[accessory valueForKey:@"identifier"] isEqual:identifier]) {
            return accessory;
        }
    }
    return nil;
}

@end

void ACInstallTestStubs(void) {
    // classes are registered by the ObjC runtime as soon as this bundle loads
}
