ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WurstSecure
WurstSecure_FILES = Tweak.xm
WurstSecure_CFLAGS = -fobjc-arc
WurstSecure_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

# Linux's linker emits the pre-iOS-14 arm64e ABI. Convert the final fat dylib
# before packaging so it can load in arm64e system processes on Dopamine.
after-WurstSecure-stage::
	@tweak="$$(find "$(THEOS_STAGING_DIR)" -name WurstSecure.dylib -print -quit)"; \
	test -n "$$tweak"; \
	allemande "$$tweak"; \
	"$(THEOS)/toolchain/linux/iphone/bin/ldid" -S "$$tweak"
