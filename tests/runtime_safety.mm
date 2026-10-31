#import <Foundation/Foundation.h>
#include <assert.h>
#import "../tweak/Core/Runtime.h"

@interface CBProductInfo : NSObject
@property unsigned productID;
+ (id)productInfoWithProductID:(unsigned)productID;
@end
@implementation CBProductInfo
+ (id)productInfoWithProductID:(unsigned)productID {
    CBProductInfo *info = [CBProductInfo new];
    info.productID = productID == 0x201b || productID == 0x2036 ? productID : 0;
    return info;
}
@end
@interface ACInheritedProductInfo : CBProductInfo
@end
@implementation ACInheritedProductInfo
@end

int main(void) {
    @autoreleasepool {
        Class cls = CBProductInfo.class;
        assert(ACMethodMatches(cls, @selector(productID), "I", @[], NO));
        assert(!ACMethodMatches(cls, @selector(productID), "Q", @[], NO));
        assert(!ACMethodMatches(cls, @selector(productID), "I", @[@"@"], NO));
        assert(!ACMethodMatches(Nil, @selector(productID), "I", @[], NO));
        assert(!ACMethodMatches(cls, NSSelectorFromString(@"missingRuntimeSelector"), "@", @[], NO));
        assert(ACMethodMatches(cls, @selector(productInfoWithProductID:), "@", @[@"I"], YES));
        assert(!ACMethodMatches(cls, @selector(productInfoWithProductID:), "@", @[@"Q"], YES));
        assert(ACClassOwnsSelector(cls, @selector(productID)));
        assert(!ACClassOwnsSelector(ACInheritedProductInfo.class, @selector(productID)));
        assert(ACNativeProductRecord(0x201b));
        assert(ACNativeProductRecord(0x2036));
        assert(!ACNativeProductRecord(0x9999));
        assert(!ACResolveHeadphoneSymbol("_$sAirPodsCompatMissingRuntimeSymbol"));
        puts("PASS actual runtime signature checks, inherited-method guards, native-record checks and missing symbol fallback");
    }
    return 0;
}
