#import "../Core/Runtime.h"

NSArray<NSDictionary *> *ACSelectedModels(void) {
    NSMutableArray *selected = [NSMutableArray array];
    for (id entry in gConfig[@"UARP"]) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *model = entry;
        if (![model[@"model"] isKindOfClass:NSString.class] ||
            ![model[@"productID"] isKindOfClass:NSNumber.class] ||
            ![model[@"baseClasses"] isKindOfClass:NSArray.class]) continue;
        if (!gScopeAll && ![model[@"tier"] isEqualToString:@"core"]) continue;
        [selected addObject:model];
    }
    return selected;
}
