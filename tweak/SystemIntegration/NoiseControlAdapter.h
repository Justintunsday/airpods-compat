#pragma once
#import <Foundation/Foundation.h>
// Passing nil selects the sole connected AirPods 5. Multiple targets fail closed.
NSDictionary *ACNoiseControlSnapshot(id preferredDevice);
BOOL ACNoiseControlSetMode(id preferredDevice, unsigned mode, NSString **reason);
