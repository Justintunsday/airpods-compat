#include <assert.h>
#include "../tweak/Models/ListeningModePolicy.h"
int main(void) {
    assert(ACListeningModeAllowed(0x2036, 16, true, true, 6, 3, 2));
    assert(ACListeningModeAllowed(0x2036, 16, true, true, 6, 3, 3));
    assert(!ACListeningModeAllowed(0x2036, 16, true, true, 6, 3, 1));
    assert(!ACListeningModeAllowed(0x2036, 16, true, true, 14, 3, 4));
    assert(ACListeningModeAllowed(0x2036, 18, true, true, 14, 3, 4));
    assert(!ACListeningModeAllowed(0x2036, 16, false, true, 6, 3, 2));
    assert(!ACListeningModeAllowed(0x2036, 16, true, false, 6, 3, 2));
    assert(!ACListeningModeAllowed(0x2036, 16, true, true, 6, 0, 2));
    assert(!ACListeningModeAllowed(0x2036, 27, true, true, 6, 3, 2));
    assert(!ACListeningModeAllowed(0x2036, 16, true, true, 0x1006, 3, 2));
    for (uint32_t pid = 0; pid <= 0xffff; pid++) if (!ACIsAirPods5(pid))
        assert(!ACListeningModeAllowed(pid, 16, true, true, 6, 3, 2));
    return 0;
}
