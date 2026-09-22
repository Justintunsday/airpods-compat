#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Best-effort enumeration of connected Bluetooth devices via the private
/// BluetoothManager framework. Returns human-readable lines; never throws
/// (all private API access is guarded and reported inline).
FOUNDATION_EXPORT NSArray<NSString *> *ACProbeConnectedBluetoothDevices(void);

NS_ASSUME_NONNULL_END
