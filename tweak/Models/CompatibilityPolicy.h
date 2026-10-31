#pragma once
#include <stdbool.h>
#include <stdint.h>

// Hardware identity is never an output of this policy. Only lookup arguments
// in the named contexts may be adapted; all other paths are identity sensitive.
typedef enum {
    ACContextIdentity,
    ACContextLegacySettings,
    ACContextSettingsLookup,
    ACContextFeatureContent,
    ACContextRouteResource,
    ACContextBatteryResource
} ACCompatibilityContext;

typedef enum { ACProfileNative, ACProfileLegacy, ACProfileAirPods4ANC, ACProfileUnavailable } ACProfile;

typedef struct {
    unsigned osMajor;
    bool enabled;
    bool profileEnabled;
    bool nativeSupport;         // Evidence for THIS lookup, not a display name.
    bool targetAvailable;       // Verified runtime target and ABI, never version alone.
    uint32_t legacyProductID;
} ACCompatibilityEnvironment;

typedef struct {
    uint32_t hardwareProductID;
    uint32_t lookupProductID;
    ACProfile profile;
} ACCompatibilityDecision;

static inline bool ACIsAirPods5(uint32_t pid) {
    return pid == 0x2036 || pid == 0x2030 || pid == 0x2037 || pid == 0x2032;
}

static inline ACCompatibilityDecision ACCompatibilitySelect(
    uint32_t pid, ACCompatibilityContext context, ACCompatibilityEnvironment environment) {
    ACCompatibilityDecision decision = {pid, pid, ACProfileNative};
    if (!environment.enabled || !environment.profileEnabled || !ACIsAirPods5(pid) ||
        environment.nativeSupport || context == ACContextIdentity) return decision;
    if (context == ACContextLegacySettings && environment.osMajor >= 16 && environment.osMajor <= 17) {
        if (environment.targetAvailable && environment.legacyProductID) {
            decision.lookupProductID = environment.legacyProductID;
            decision.profile = ACProfileLegacy;
        }
        return decision;
    }
    if (environment.osMajor < 18 || environment.osMajor > 26) return decision;
    if (context != ACContextSettingsLookup && context != ACContextFeatureContent &&
        context != ACContextRouteResource && context != ACContextBatteryResource) return decision;
    if (!environment.targetAvailable) {
        decision.profile = ACProfileUnavailable;
        return decision;
    }
    decision.lookupProductID = 0x201b;
    decision.profile = ACProfileAirPods4ANC;
    return decision;
}
