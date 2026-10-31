#pragma once
#include <stdbool.h>
#include <string.h>

static inline bool ACProcessIs(const char *name, const char *expected) {
    return name && !strcmp(name, expected);
}
static inline bool ACProcessOwnsRegistry(const char *name) {
    return ACProcessIs(name, "bluetoothd") || ACProcessIs(name, "bluetoothuserd") ||
           ACProcessIs(name, "bluetoothaudiod") || ACProcessIs(name, "uarpd");
}
static inline bool ACProcessOwnsSettings(const char *name) {
    return ACProcessIs(name, "Preferences") || ACProcessIs(name, "HeadphoneProxService");
}
static inline bool ACProcessOwnsSystemResources(const char *name) {
    return ACProcessIs(name, "SpringBoard") || ACProcessIs(name, "MusicUIService");
}
// Explicit Apple UI clients retain the device-tested iOS 16 presentation path.
// Custom/third-party clients require a separately installed opt-in filter.
static inline bool ACProcessIsResourceClient(const char *name) {
    return ACProcessOwnsSystemResources(name) || ACProcessIs(name, "Music") ||
           ACProcessIs(name, "Podcasts") || ACProcessIs(name, "PosterBoard");
}
static inline bool ACValidOptInResourceClient(const char *name) {
    return name && name[0] && strlen(name) <= 128 && !strpbrk(name, "/\\*?[]") &&
           strcmp(name, ".") && strcmp(name, "..");
}
