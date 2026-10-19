#include <assert.h>
#include "../tweak/LegacyResourcePolicy.h"

int main(void) {
    const uint32_t targets[] = {0x2036, 0x2037, 0x2030, 0x2032, 0x2035, 0x13a5, 0x13a4};
    for (unsigned i = 0; i < sizeof(targets)/sizeof(targets[0]); ++i) {
        assert(ACBatteryResourcePID(targets[i], 1, 3) == 0x2013);
        assert(ACBatteryResourcePID(targets[i], 76, 3) == targets[i]);
        assert(ACBatteryResourcePID(targets[i], 1, 2) == targets[i]);
    }
    for (uint32_t pid = 0; pid <= 0xffff; ++pid) {
        if (!ACIsAirPods5Resource(pid)) assert(ACBatteryResourcePID(pid, 1, 3) == pid);
    }
    assert(ACIsAirPods5RouteModel("BTHeadphones76,8246"));
    assert(ACIsAirPods5RouteModel("BTHeadphones76,8247"));
    assert(ACIsAirPods5RouteModel("BTHeadphones76,8240"));
    assert(ACIsAirPods5RouteModel("BTHeadphones76,8242"));
    assert(!ACIsAirPods5RouteModel(0));
    assert(!ACIsAirPods5RouteModel("AirPods 5"));
    assert(!ACIsAirPods5RouteModel("BTHeadphones75,8246"));
    assert(!ACIsAirPods5RouteModel("BTHeadphones76,8246suffix"));
    assert(!ACIsAirPods5RouteModel("BTHeadphones76,8211"));
    assert(!ACIsAirPods5RouteModel("BTHeadphones76,8245"));
    assert(!ACIsAirPods5RouteModel(""));
    return 0;
}
