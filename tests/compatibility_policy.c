#include <assert.h>
#include "../tweak/Models/CompatibilityPolicy.h"
#include "../tweak/Core/ConfigurationPolicy.h"
#include "../tweak/Core/ProcessPolicy.h"

int main(void) {
    const uint32_t targets[] = {0x2036, 0x2030, 0x2037, 0x2032};
    ACCompatibilityEnvironment env = {18, true, true, false, true, 0x2013};
    for (unsigned os = 16; os <= 28; os++) {
        env.osMajor = os;
        for (unsigned i = 0; i < 4; i++) {
            uint32_t pid = targets[i];
            assert(ACCompatibilitySelect(pid, ACContextIdentity, env).lookupProductID == pid);
            ACCompatibilityDecision d = ACCompatibilitySelect(pid, ACContextSettingsLookup, env);
            assert(d.hardwareProductID == pid);
            assert(d.lookupProductID == (os >= 18 && os <= 26 ? 0x201b : pid));
            d = ACCompatibilitySelect(pid, ACContextLegacySettings, env);
            assert(d.lookupProductID == (os <= 17 ? 0x2013 : pid));
        }
    }
    env.osMajor = 26;
    for (uint32_t pid = 0; pid <= 0xffff; pid++) {
        if (ACIsAirPods5(pid)) continue;
        for (unsigned context = ACContextIdentity; context <= ACContextBatteryResource; context++)
            assert(ACCompatibilitySelect(pid, (ACCompatibilityContext)context, env).lookupProductID == pid);
    }
    env.nativeSupport = true;
    assert(ACCompatibilitySelect(0x2036, ACContextFeatureContent, env).lookupProductID == 0x2036);
    env.nativeSupport = false;
    env.targetAvailable = false;
    ACCompatibilityDecision d = ACCompatibilitySelect(0x2036, ACContextFeatureContent, env);
    assert(d.lookupProductID == 0x2036 && d.profile == ACProfileUnavailable);
    env.targetAvailable = true;
    env.enabled = false;
    assert(ACCompatibilitySelect(0x2036, ACContextFeatureContent, env).lookupProductID == 0x2036);
    env.enabled = true;
    env.profileEnabled = false;
    assert(ACCompatibilitySelect(0x2036, ACContextFeatureContent, env).lookupProductID == 0x2036);
    assert(ACLegacySettingsPID(NULL) == 0x2013);
    assert(ACLegacySettingsPID("pro2") == 0x2014);
    assert(ACLegacySettingsPID("off") == 0);
    assert(!strcmp(ACModernProfile("airpodspro3"), "airpods4anc"));
    assert(!strcmp(ACModernProfile("off"), "off"));
    assert(!strcmp(ACModernProfile("corrupt"), "airpods4anc"));
    assert(ACProcessOwnsRegistry("bluetoothd"));
    assert(!ACProcessOwnsRegistry("SpringBoard"));
    assert(ACProcessOwnsSettings("Preferences"));
    assert(ACProcessIsResourceClient("Music"));
    assert(!ACProcessIsResourceClient("Safari"));
    assert(!ACProcessIsResourceClient("ThirdPartyAudio"));
    assert(!ACProcessIsResourceClient(NULL));
    assert(!ACProcessIsResourceClient("MusicHelper"));
    return 0;
}
