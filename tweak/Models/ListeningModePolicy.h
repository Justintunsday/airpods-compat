#pragma once
#include "CompatibilityPolicy.h"

enum { ACListeningOff = 1, ACListeningANC = 2, ACListeningTransparency = 3, ACListeningAdaptive = 4 };

// These are device-reported cycle/configuration bits, not invented hardware
// capabilities. Restrict commands further by OS, exact hardware PID and ABI.
static inline bool ACListeningModeAllowed(uint32_t hardwarePID, unsigned os, bool connected,
                                          bool apiAvailable, unsigned reportedModes,
                                          unsigned currentMode, unsigned requestedMode) {
    unsigned maximum = os >= 18 ? 4 : 3;
    if (!ACIsAirPods5(hardwarePID) || os < 16 || os > 26 || !connected || !apiAvailable ||
        !currentMode || currentMode > maximum || !requestedMode || requestedMode > maximum) return false;
    if (reportedModes & ~((1u << maximum) - 1u)) return false; // unknown layout: fail closed
    return (reportedModes & (1u << (requestedMode - 1))) != 0;
}
