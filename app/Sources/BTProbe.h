#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Best-effort listing of Bluetooth devices via the private BluetoothManager
/// framework. Each entry may contain:
///   name (NSString), address (NSString), productID (NSNumber), vendorID (NSNumber),
///   connected (NSNumber), paired (NSNumber), className (NSString).
/// Returns an empty array when the framework cannot be used; see
/// ACProbeBluetoothStatus() for the reason.
FOUNDATION_EXPORT NSArray<NSDictionary<NSString *, id> *> *ACProbeBluetoothDevices(void);

/// nil when the private framework was usable, otherwise a human-readable reason.
FOUNDATION_EXPORT NSString *_Nullable ACProbeBluetoothStatus(void);

NS_ASSUME_NONNULL_END
