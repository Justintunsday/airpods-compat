#import <UIKit/UIKit.h>
#import <ControlCenterUIKit/CCUIToggleModule.h>
#import "../Core/Runtime.h"
#import "../SystemIntegration/NoiseControlAdapter.h"

@interface AirPodsCompatNoiseControl : CCUIToggleModule
@end
@implementation AirPodsCompatNoiseControl
- (instancetype)init {
    self = [super init];
    if (self) {
        ACLoadConfig();
        // BluetoothManager populates its cache asynchronously on first use.
        // Warm it before the first displayed state, then refresh from readback.
        (void)ACNoiseControlSnapshot(nil);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (ACMethodMatches(CCUIToggleModule.class, @selector(refreshState), "v", @[], NO)) [self refreshState];
        });
    }
    return self;
}
- (UIImage *)iconGlyph { return [UIImage systemImageNamed:@"ear.and.waveform"] ?: [UIImage systemImageNamed:@"headphones"]; }
- (UIColor *)selectedColor { return UIColor.systemGreenColor; }
- (BOOL)isSelected { return [ACNoiseControlSnapshot(nil)[@"currentMode"] unsignedIntValue] == 2; }
- (void)setSelected:(BOOL)selected {
    NSDictionary *status = ACNoiseControlSnapshot(nil);
    unsigned requested = selected ? 2 : ([status[@"allowedModes"] containsObject:@3] ? 3 : 1);
    NSString *reason = nil;
    BOOL accepted = ACNoiseControlSetMode(nil, requested, &reason);
    AC_LOG(@"CC noise command accepted=%d reason=%@", accepted, reason ?: @"none");
    if (!accepted) {
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback notificationOccurred:UINotificationFeedbackTypeError];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, reason ?: @"Noise control unavailable");
    }
    // Selected state always comes from native readback, never an optimistic bit.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (ACMethodMatches(CCUIToggleModule.class, @selector(refreshState), "v", @[], NO)) [self refreshState];
    });
}
@end
