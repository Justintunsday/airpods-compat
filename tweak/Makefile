TARGET := iphone:clang:16.5:15.0
ARCHS := arm64e arm64
THEOS_PACKAGE_SCHEME := rootless

INSTALL_TARGET_PROCESSES := SpringBoard bluetoothd

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AirPodsCompat
AirPodsCompat_FILES := Tweak.xm
AirPodsCompat_CFLAGS := -fobjc-arc
AirPodsCompat_FRAMEWORKS := Foundation
AirPodsCompat_LIBRARIES := root

include $(THEOS_MAKE_PATH)/tweak.mk
