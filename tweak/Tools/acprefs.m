#import <Foundation/Foundation.h>
#import <unistd.h>
#import <sys/stat.h>
#include "../Core/ConfigurationPolicy.h"
#include "../Core/ProcessPolicy.h"

static NSString *const path = @"/var/mobile/Library/Preferences/com.justintunsday.airpodscompat.plist";

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc == 2 && !strcmp(argv[1], "show")) {
            NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:preferences format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
            fwrite(data.bytes, 1, data.length, stdout);
            return 0;
        }
        if (argc != 3 || strcmp(argv[1], "import")) {
            fprintf(stderr, "Usage: acprefs show | acprefs import /absolute/path/config.plist\nRun as mobile (or root). No privileged app helper or daemon is installed.\n");
            return 2;
        }
        if (getuid() != 0 && getuid() != 501) { fprintf(stderr, "Run as mobile or root.\n"); return 1; }
        NSDictionary *input = [NSDictionary dictionaryWithContentsOfFile:@(argv[2])];
        if (!input) { fprintf(stderr, "Input must be a valid property-list dictionary.\n"); return 1; }
        NSMutableDictionary *preferences = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy] ?: [NSMutableDictionary dictionary];
        NSSet *booleans = [NSSet setWithArray:@[@"Enabled", @"UARPEnabled", @"DiagnosticsEnabled", @"LegacyRouteResourcesEnabled", @"LegacyBatteryResourcesEnabled", @"NoiseControlsEnabled"]];
        NSDictionary *strings = @{
            @"Scope": @[@"core", @"all"],
            @"BorrowProfile": @[@"airpods4anc", @"airpodspro2", @"airpodspro3", @"off"],
            @"LegacyUIProfile": @[@"airpods3", @"pro2", @"airpodspro2", @"airpods4anc", @"airpodspro3", @"off"],
            @"LegacyIconProfile": @[@"airpods3", @"pro2", @"airpodspro2", @"airpods4anc", @"off"]
        };
        for (NSString *key in input) {
            id value = input[key];
            if ([booleans containsObject:key] && [value isKindOfClass:NSNumber.class] &&
                ([value isEqual:@YES] || [value isEqual:@NO])) preferences[key] = value;
            else if ([key isEqualToString:@"ExtraResourceClientProcesses"] &&
                     [value isKindOfClass:NSArray.class] && [value count] <= 4) {
                for (id name in value) {
                    if (![name isKindOfClass:NSString.class] || !ACValidOptInResourceClient([name UTF8String])) {
                        fprintf(stderr, "Client allowlist requires exact process names without wildcards or paths.\n"); return 1;
                    }
                }
                preferences[key] = value;
            }
            else if ([strings[key] containsObject:value]) preferences[key] = value;
            else if (![key isEqualToString:@"ConfigurationVersion"]) {
                fprintf(stderr, "Rejected unknown key or invalid value: %s\n", key.UTF8String); return 1;
            }
        }
        preferences[@"ConfigurationVersion"] = @2;
        NSString *borrow = [preferences[@"BorrowProfile"] isKindOfClass:NSString.class] ? preferences[@"BorrowProfile"] : nil;
        preferences[@"BorrowProfile"] = @(ACModernProfile(borrow.UTF8String));
        if (![preferences writeToFile:path atomically:YES] ||
            ![[NSDictionary dictionaryWithContentsOfFile:path] isEqual:preferences]) {
            fprintf(stderr, "Shared preference write/readback failed.\n"); return 1;
        }
        if (getuid() == 0) { chown(path.fileSystemRepresentation, 501, 501); chmod(path.fileSystemRepresentation, 0644); }
        puts("Shared configuration saved and verified. Restart affected processes to apply.");
        return 0;
    }
}
