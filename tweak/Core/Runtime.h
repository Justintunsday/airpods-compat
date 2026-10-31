#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dispatch/dispatch.h>
#include "ProcessPolicy.h"
#include "ConfigurationPolicy.h"
#include "../Models/CompatibilityPolicy.h"

enum : uint32_t { kAirPods4AncProductID = 0x201b, kAirPodsPro2ProductID = 0x2014, kAirPodsPro3ProductID = 0x2027 };
static const uint32_t kAirPods5ProductIDs[] = {0x2036, 0x2030, 0x2037, 0x2032};
extern BOOL gDiagnosticLogs, gEnabled, gUARPEnabled, gScopeAll, gBorrowEnabled;
extern BOOL gLegacyUIProfileEnabled, gLegacyIconProfileEnabled;
extern uint32_t gBorrowProductID, gLegacyUIProductID, gLegacyIconProductID;
extern NSDictionary *gConfig;
extern NSDictionary<NSNumber *, NSString *> *gDisplayNames;
extern BOOL gRouteResourcesEnabled, gBatteryResourcesEnabled;
#define AC_LOG(fmt, ...) do { if (gDiagnosticLogs) NSLog(@"[AirPodsCompat] " fmt, ##__VA_ARGS__); } while (0)

NSString *ACSupportPath(NSString *name);
NSString *ACPrefsPath(void);
NSString *ACProcessName(void);
NSDictionary *ACReadPreferences(void);
BOOL ACProcessCanUseResources(void);
void ACLoadConfig(void);
void ACWithRegistrationGuard(void (^work)(void));
void ACRecordHookStatus(NSString *module, NSString *state);
BOOL ACMethodMatches(Class cls, SEL sel, const char *ret, NSArray<NSString *> *args, BOOL classMethod);
BOOL ACClassOwnsSelector(Class cls, SEL sel);
void *ACResolveHeadphoneSymbol(const char *symbol);
BOOL ACNativeProductRecord(uint32_t productID);
BOOL ACNativeAirPods5FeatureContent(void);
void ACInstallAccessoryRegistration(void);
NSArray<NSDictionary *> *ACSelectedModels(void);
void ACInstallLegacySettingsHooks(void);
void ACInstallDeviceIdentity(void);
void ACInstallIdentityBoundaries(void);
BOOL ACInHardwareIdentityScope(void);
void ACInstallHeadphoneFeatureHooks(void);
void ACInstallHeadphoneConfigHooks(void);
NSNumber *ACOriginalProductIDForUIObject(id object);
