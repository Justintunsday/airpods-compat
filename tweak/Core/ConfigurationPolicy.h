#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

static inline bool ACConfigEquals(const char *value, const char *expected) {
    return value && !strcmp(value, expected);
}
// v1 Pro profiles are migrated on modern systems. No modern override can opt
// into a richer, unverified hardware feature set. An explicit off is preserved.
static inline const char *ACModernProfile(const char *stored) {
    return ACConfigEquals(stored, "off") ? "off" : "airpods4anc";
}
static inline uint32_t ACLegacySettingsPID(const char *stored) {
    if (ACConfigEquals(stored, "off")) return 0;
    if (ACConfigEquals(stored, "pro2") || ACConfigEquals(stored, "airpodspro2")) return 0x2014;
    if (ACConfigEquals(stored, "airpodspro3")) return 0x2027;
    if (ACConfigEquals(stored, "airpods4anc")) return 0x201b;
    return 0x2013; // Actual a30615d default; do not change it to README's old pro2 default.
}
