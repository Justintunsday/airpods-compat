#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs a full local self-test (no jailbreak required) and returns a
/// human-readable report:
///   1. environment (iOS version, device, jailbreak presence)
///   2. whether the system CoreUARP/CoreBluetooth/HeadphoneManager know the
///      AirPods 5 model classes (and what +productID / +appleModelNumber return)
/// Does not create or register accessories on a real device.
FOUNDATION_EXPORT NSString *ACRunSelfTest(void);

/// Simulator-only registration against test stubs, for automated tests:
/// modelCount, uniqueProductIDs, expected, registered, created, already,
/// grew, actualIdentifiers.
FOUNDATION_EXPORT NSDictionary *ACRunSelfTestSummary(void);

NS_ASSUME_NONNULL_END
