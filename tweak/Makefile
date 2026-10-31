TARGET := iphone:clang:16.5:15.0
ARCHS := arm64e arm64

# package scheme is chosen by the build command:
#   rootless: make package THEOS_PACKAGE_SCHEME=rootless   (Dopamine / ElleKit)
#   rootful:  make package                                 (legacy jailbreaks)
# no default here so both variants can be produced.

INSTALL_TARGET_PROCESSES := SpringBoard bluetoothd

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AirPodsCompat AirPodsCompatResources
AC_COMMON_FILES := Core/ConfigurationManager.mm Platform/RuntimeSymbolResolver.mm
AirPodsCompat_FILES := Tweak.xm $(AC_COMMON_FILES) Core/CrashGuard.mm \
    Models/AirPodsModelRegistry.mm Bluetooth/AccessoryRegistration.mm \
    Bluetooth/DeviceIdentity.mm Hooks/LegacySettingsHooks.mm \
    Hooks/HeadphoneFeatureHooks.mm Hooks/HeadphoneConfigHooks.mm
AirPodsCompat_CFLAGS := -fobjc-arc -fvisibility=hidden
AirPodsCompat_CCFLAGS := -std=c++14
AirPodsCompat_FRAMEWORKS := Foundation
AirPodsCompatResources_FILES := LegacyResourceTweak.xm $(AC_COMMON_FILES) SystemIntegration/ResourceResolver.mm
AirPodsCompatResources_CFLAGS := -fobjc-arc -fvisibility=hidden
AirPodsCompatResources_CCFLAGS := -std=c++14
AirPodsCompatResources_FRAMEWORKS := Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
