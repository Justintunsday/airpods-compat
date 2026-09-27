#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Unknown types never enable a capability. Missing values use the stated default.
FOUNDATION_EXPORT BOOL ACBoolPreference(id _Nullable preferences, NSString *key, BOOL defaultValue);
FOUNDATION_EXPORT BOOL ACFullModelScope(id _Nullable preferences);
FOUNDATION_EXPORT NSArray<NSDictionary *> *ACValidatedModels(id _Nullable models);
FOUNDATION_EXPORT NSDictionary<NSNumber *, NSString *> *ACValidatedDisplayNames(id _Nullable names);

// Only direct Objective-C methods with the expected ABI are callable.
FOUNDATION_EXPORT BOOL ACMethodMatches(id _Nullable target, SEL selector,
                                      char returnType, NSUInteger argumentCount,
                                      char argumentType);
FOUNDATION_EXPORT id _Nullable ACReadNoArgumentValue(id _Nullable target, SEL selector);
FOUNDATION_EXPORT NSNumber * _Nullable ACProbeUnsignedNumber(id _Nullable value);

NS_ASSUME_NONNULL_END
