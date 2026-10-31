TARGET := iphone:clang:16.5:15.0
ARCHS := arm64e arm64

# package scheme is chosen by the build command:
#   rootless: make package THEOS_PACKAGE_SCHEME=rootless   (Dopamine / ElleKit)
#   rootful:  make package                                 (legacy jailbreaks)
# no default here so both variants can be produced.

INSTALL_TARGET_PROCESSES := SpringBoard bluetoothd

include $(THEOS)/makefiles/common.mk

# Current Apple ld ignores this obsolete Theos default. Remove the option;
# duplicate definitions should remain errors instead of hiding linker warnings.
_THEOS_TARGET_LDFLAGS := $(filter-out -multiply_defined suppress,$(_THEOS_TARGET_LDFLAGS))

TWEAK_NAME := AirPodsCompat AirPodsCompatResources AirPodsCompatControls
AC_COMMON_FILES := Core/ConfigurationManager.mm Core/DiagnosticsManager.mm Platform/RuntimeSymbolResolver.mm
AirPodsCompat_FILES := Tweak.xm $(AC_COMMON_FILES) Core/CrashGuard.mm \
    Models/AirPodsModelRegistry.mm Bluetooth/AccessoryRegistration.mm \
    Bluetooth/DeviceIdentity.mm Bluetooth/IdentityBoundaries.mm Hooks/LegacySettingsHooks.mm \
    Hooks/HeadphoneFeatureHooks.mm Hooks/HeadphoneConfigHooks.mm
AirPodsCompat_CFLAGS := -fobjc-arc -fvisibility=hidden
AirPodsCompat_CCFLAGS := -std=c++14
AirPodsCompat_FRAMEWORKS := Foundation
AirPodsCompatResources_FILES := LegacyResourceTweak.xm $(AC_COMMON_FILES) SystemIntegration/ResourceResolver.mm
AirPodsCompatResources_CFLAGS := -fobjc-arc -fvisibility=hidden
AirPodsCompatResources_CCFLAGS := -std=c++14
AirPodsCompatResources_FRAMEWORKS := Foundation
AirPodsCompatControls_FILES := NoiseControlTweak.xm $(AC_COMMON_FILES) \
    SystemIntegration/NoiseControlAdapter.mm Hooks/NoiseControlSettingsHooks.mm
AirPodsCompatControls_CFLAGS := -fobjc-arc -fvisibility=hidden
AirPodsCompatControls_CCFLAGS := -std=c++14
AirPodsCompatControls_FRAMEWORKS := Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

TOOL_NAME := acprefs
acprefs_FILES := Tools/acprefs.m
acprefs_CFLAGS := -fobjc-arc
acprefs_FRAMEWORKS := Foundation
acprefs_INSTALL_PATH := /usr/bin
include $(THEOS_MAKE_PATH)/tool.mk

BUNDLE_NAME := AirPodsCompatNoiseControl
AirPodsCompatNoiseControl_BUNDLE_EXTENSION := bundle
AirPodsCompatNoiseControl_FILES := CCModule/NoiseControlModule.mm $(AC_COMMON_FILES) SystemIntegration/NoiseControlAdapter.mm
AirPodsCompatNoiseControl_CFLAGS := -fobjc-arc -fvisibility=hidden
AirPodsCompatNoiseControl_CCFLAGS := -std=c++14
AirPodsCompatNoiseControl_FRAMEWORKS := Foundation UIKit
AirPodsCompatNoiseControl_PRIVATE_FRAMEWORKS := ControlCenterUIKit
AirPodsCompatNoiseControl_RESOURCE_DIRS := CCModule/Resources
AirPodsCompatNoiseControl_INSTALL_PATH := /Library/ControlCenter/Bundles
include $(THEOS_MAKE_PATH)/bundle.mk
