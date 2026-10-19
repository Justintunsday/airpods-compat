#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

static inline bool ACIsAirPods5Bud(uint32_t pid) {
    return pid == 0x2036 || pid == 0x2037 || pid == 0x2030 || pid == 0x2032;
}

static inline bool ACIsAirPods5Resource(uint32_t pid) {
    return ACIsAirPods5Bud(pid) || pid == 0x2035 || pid == 0x13a5 || pid == 0x13a4;
}

// Exact Apple vendor + decimal product identifiers observed on iOS 16.
// Never infer identity from a user-editable device name.
static inline bool ACIsAirPods5RouteModel(const char *model) {
    return model && (!strcmp(model, "BTHeadphones76,8246") ||
                     !strcmp(model, "BTHeadphones76,8247") ||
                     !strcmp(model, "BTHeadphones76,8240") ||
                     !strcmp(model, "BTHeadphones76,8242"));
}

static inline uint32_t ACBatteryResourcePID(uint32_t pid, long vendor, long transport) {
    return vendor == 1 && transport == 3 && ACIsAirPods5Resource(pid) ? 0x2013 : pid;
}

static inline unsigned long ACBatteryResourceParts(uint32_t pid, long vendor,
                                                  long transport, unsigned long parts) {
    if (ACBatteryResourcePID(pid, vendor, transport) == pid || parts) return parts;
    // Legacy glyph factories have no model-specific image for Single (parts 0).
    // Select a combined earbud glyph, or a case glyph only for a known case PID.
    return ACIsAirPods5Bud(pid) ? 3 : 4;
}
