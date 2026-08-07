ARCHS = arm64
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TOOL_NAME = WurstVintedBridge
WurstVintedBridge_FILES = Bridge.c
WurstVintedBridge_CFLAGS = -Wall -Wextra
WurstVintedBridge_CODESIGN_FLAGS = -SEntitlements.plist
WurstVintedBridge_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk

after-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/LaunchDaemons"
	@cp WurstVintedBridge.plist \
		"$(THEOS_STAGING_DIR)/Library/LaunchDaemons/de.akator.wurstvintedbridge.plist"
