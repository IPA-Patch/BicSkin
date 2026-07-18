# ===========================================================================
# Theos tweak Makefile — template.
#
# Only $(TWEAK_NAME) (via control's `Name:`) and the target app knobs below
# should need editing per project. Everything downstream — source discovery,
# defines, filter plist lookup — is derived from it.
#
# Targets:
#   make            — JB rootless .deb (MSHookFunction via libsubstrate)
#   make package    — same, packaged
#   make install    — install .deb to $(THEOS_DEVICE_IP) (dpkg path);
#                     after-install kills $(TARGET_PROCESS) and relaunches
#                     $(TARGET_BUNDLE_ID) so the fresh tweak takes effect.
#   make jailed     — Dobby-static .dylib for Sideloadly / TrollStore.
#                     Requires vendor/dobby/{include,lib/libdobby.a}.
#   make ipa        — Assemble a patched IPA from $(DECRYPTED_IPA) by
#                     injecting the jailed dylib via LC_LOAD_DYLIB.
#   make deploy     — build ipa, scp it to the device, install via
#                     TrollStore's trollstorehelper, relaunch the app.
#                     Thin wrapper around shared/tools/deploy.sh.
#   make agent      — Compile frida/agent.ts → frida/dist/agent.js.
#   make attach     — Compile the agent, then run `frida -U -f
#                     $(TARGET_BUNDLE_ID) -l frida/dist/agent.js`.
#   make format     — clang-format every ObjC / C source under Sources/.
#   make format-check — dry-run clang-format; nonzero exit on any diff.
#   make hooks      — Point git core.hooksPath at scripts/.
# ===========================================================================

# ---------------------------------------------------------------------------
# PROJECT VARIABLES
# ---------------------------------------------------------------------------
# TWEAK_NAME is pulled from control's `Name:` field. Keep that value as a
# single identifier (CamelCase, no spaces) — it's used as the dylib name,
# the sources directory, and the filter plist basename.
TWEAK_NAME               := $(shell awk -F': *' '/^Name:/ {print $$2; exit}' control)
TWEAK_SOURCES_DIR        := Sources/$(TWEAK_NAME)

# The tweak filter lives at Tweak.plist for template hygiene, but Theos
# + MobileSubstrate both key off $(TWEAK_NAME).plist (Theos to stage it,
# MobileSubstrate to match it against the dylib basename). Recreate the
# symlink at parse time so it stays fresh across TWEAK_NAME changes.
# Skip when TWEAK_NAME is literally `Tweak` — self-symlinking would clobber
# the source file.
_PLIST_SYMLINK           := $(shell [ -f Tweak.plist ] && [ "$(TWEAK_NAME)" != "Tweak" ] \
                                    && ln -sfn Tweak.plist $(TWEAK_NAME).plist)

# TARGET_BUNDLE_ID: Tweak.plist の Filter > Bundles の最初の <string> を採用。
# 複数バンドルを対象にする場合は .env or CLI で override してね。
TARGET_BUNDLE_ID         ?= $(shell sed -n 's:.*<string>\([^<]*\)</string>.*:\1:p' Tweak.plist 2>/dev/null | head -1)
# TARGET_PROCESS: bundle id の末尾 component を採用 (多くの iOS App では
# CFBundleExecutable と一致する)。ずれる場合は .env or CLI で override。
TARGET_PROCESS           ?= $(notdir $(subst .,/,$(TARGET_BUNDLE_ID)))

# Decrypted IPA the ipa/deploy pipeline consumes. App Store IPAs ship
# FairPlay-encrypted; you need a frida-ios-dump-style decrypted copy.
# Never commit this file (see .gitignore).
DECRYPTED_IPA            ?= $(firstword $(wildcard $(CURDIR)/assets/*.ipa))

# ---------------------------------------------------------------------------
# Theos boilerplate.
# ---------------------------------------------------------------------------
TARGET                   := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES := $(TARGET_PROCESS)
ARCHS                    := arm64
THEOS_PACKAGE_SCHEME     := rootless
-include .env

# Devcontainer default: reach the host Mac's iproxy relay (usb-tethered
# device on port 22 → host port 2222). Override in .env for physical Wi-Fi
# deployments (e.g. THEOS_DEVICE_IP=192.168.x.x, THEOS_DEVICE_PORT=22).
THEOS_DEVICE_IP          ?= host.docker.internal
THEOS_DEVICE_PORT        ?= 2222

include $(THEOS)/makefiles/common.mk

# Auto-discover tweak sources under Sources/$(TWEAK_NAME)/.
$(TWEAK_NAME)_FILES      := $(shell find $(TWEAK_SOURCES_DIR) \
    \( -name '*.x' -o -name '*.xm' -o -name '*.m' -o -name '*.mm' \
       -o -name '*.c' -o -name '*.cpp' -o -name '*.swift' \))
# fishhook — 2-file drop-in for C-symbol rebinding. Vendored at
# vendor/fishhook/; no build system, just compile the .c alongside ours.
$(TWEAK_NAME)_FILES      += vendor/fishhook/fishhook.c

BUILD_COMMIT             ?= $(shell git rev-parse --short=7 HEAD 2>/dev/null || echo unknown)

_CONTROL_VERSION         := $(shell grep '^Version:' control | awk '{print $$2}')
# Theos sets DEBUG=1 by default; FINALPACKAGE=1 clears it for release builds.
ifneq ($(FINALPACKAGE),1)
PACKAGE_VERSION          := $(_CONTROL_VERSION)-dbg
else
PACKAGE_VERSION          := $(_CONTROL_VERSION)
endif
# `override` needed because Theos's package/deb.mk re-assigns
# THEOS_PACKAGE_BASE_VERSION from the control file's raw Version:
# without the -dbg suffix. Pinning it here keeps the debug suffix on
# the .deb filename for non-FINALPACKAGE builds.
ifneq ($(FINALPACKAGE),1)
override THEOS_PACKAGE_BASE_VERSION := $(_CONTROL_VERSION)-dbg
else
override THEOS_PACKAGE_BASE_VERSION := $(_CONTROL_VERSION)
endif

$(TWEAK_NAME)_CFLAGS     := -fobjc-arc -Wno-unused-function \
                            -DTWEAK_COMMIT=\"$(BUILD_COMMIT)\" \
                            -DTWEAK_VERSION=\"$(PACKAGE_VERSION)\" \
                            -Ivendor/fishhook -I$(TWEAK_SOURCES_DIR)

$(TWEAK_NAME)_FRAMEWORKS := Foundation UIKit

# ---------------------------------------------------------------------------
# Hook backend: substrate (JB) vs Dobby (jailed / Sideloadly / TrollStore).
# ---------------------------------------------------------------------------
ifeq ($(JAILED),1)
    # No substrate at runtime → strict-link so a stray MSHookMessageEx-style
    # call can't slip through and crash the injected app at dyld load.
    $(TWEAK_NAME)_CFLAGS     += -DIPA_JAILED=1 -Ivendor/dobby/include
    $(TWEAK_NAME)_LDFLAGS    := -Lvendor/dobby/lib -ldobby -lc++ -lc++abi \
                                -Wl,-undefined,error
else
    $(TWEAK_NAME)_LDFLAGS    := -lsubstrate
endif

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "chmod 755 /var/jb/Library/MobileSubstrate/DynamicLibraries/$(TWEAK_NAME).dylib"
	# INSTALL_TARGET_PROCESSES で kill 済み。フレッシュな tweak を反映するため relaunch。
	install.exec "sleep 1; (open $(TARGET_BUNDLE_ID) 2>/dev/null || uiopen $(TARGET_BUNDLE_ID):// 2>/dev/null || echo 'no launcher tool (uiopen/open); start $(TARGET_PROCESS) manually')"

# ---------------------------------------------------------------------------
# Sideload build — Dobby-static dylib, no libsubstrate dependency. Drops
# the artifact into packages/jailed/ and dumps otool -L so a stray dyld
# dependency is immediately visible.
# ---------------------------------------------------------------------------
.PHONY: jailed
jailed::
	$(MAKE) JAILED=1 clean
	$(MAKE) JAILED=1 all
	$(ECHO_NOTHING)mkdir -p packages/jailed$(ECHO_END)
	$(ECHO_NOTHING)cp $(THEOS_OBJ_DIR)/$(TWEAK_NAME).dylib packages/jailed/$(TWEAK_NAME).dylib$(ECHO_END)
	@echo "jailed dylib -> packages/jailed/$(TWEAK_NAME).dylib"
	@echo "--- otool -L (must NOT list libsubstrate or libdobby) ---"
	@$(THEOS)/toolchain/linux/iphone/bin/otool -L packages/jailed/$(TWEAK_NAME).dylib 2>/dev/null \
	  || otool -L packages/jailed/$(TWEAK_NAME).dylib 2>/dev/null \
	  || echo "(otool unavailable)"

# ---------------------------------------------------------------------------
# IPA assembly. Injects the jailed dylib into $(DECRYPTED_IPA) via
# LC_LOAD_DYLIB and repacks. Output goes to packages/ipa/.
# ---------------------------------------------------------------------------
JAILED_DYLIB             := $(CURDIR)/packages/jailed/$(TWEAK_NAME).dylib
IPA_OUT                  := $(CURDIR)/packages/ipa/$(TWEAK_NAME).ipa

.PHONY: ipa
ipa:: jailed
	@if [ ! -f "$(DECRYPTED_IPA)" ]; then \
	  echo "error: decrypted IPA missing at $(DECRYPTED_IPA)"; \
	  echo "       override with: make ipa DECRYPTED_IPA=/path/to/decrypted.ipa"; \
	  exit 1; \
	fi
	@echo "==> assembling patched IPA from $(DECRYPTED_IPA)"
	uv run python scripts/build_ipa.py \
	  --input  "$(DECRYPTED_IPA)" \
	  --dylib  "$(JAILED_DYLIB)" \
	  --output "$(IPA_OUT)"

# ---------------------------------------------------------------------------
# TrollStore-backed IPA deploy.
#   Thin wrapper around shared/tools/deploy.sh — the shell keeps
#   TrollStore Lite auto-discovery, ssh-255 tolerance, and the pre-install
#   killall away from the Makefile.
#
#   Kept separate from Theos's own `install::` (JB rootless .deb install)
#   so `make deploy` targets only the IPA path and doesn't drag in the
#   JB dpkg install as a side effect.
#
#   Override on the command line or in .env:
#     TROLLSTORE_HELPER        — pin trollstorehelper path (skips SSH discovery)
#     INSTALLED_IPA_BUNDLE_ID  — bundle id used to relaunch the app
#     DEVICE_USER              — SSH user (defaults to root)
# ---------------------------------------------------------------------------
TROLLSTORE_HELPER        ?=
INSTALLED_IPA_BUNDLE_ID  ?= $(TARGET_BUNDLE_ID)
DEVICE_USER              ?= root

.PHONY: deploy
deploy: ipa
	@./shared/tools/deploy.sh \
	    --ipa           "$(IPA_OUT)" \
	    --host          "$(THEOS_DEVICE_IP)" \
	    --port          "$(THEOS_DEVICE_PORT)" \
	    --user          "$(DEVICE_USER)" \
	    --bundle-id     "$(INSTALLED_IPA_BUNDLE_ID)" \
	    --process-name  "$(TARGET_PROCESS)" \
	    $(if $(TROLLSTORE_HELPER),--helper "$(TROLLSTORE_HELPER)",)

# ---------------------------------------------------------------------------
# Frida investigation agent. TypeScript source under frida/agent.ts is
# bundled by frida-compile into frida/dist/agent.js, then injected into
# the target by the Python frida CLI (`uv run frida ...`).
#
# The Frida controller side lives in Python (pyproject.toml pulls in
# frida + frida-tools); the agent side is TypeScript (package.json pulls
# in frida-compile + @types/frida-gum). Both toolchains ship in the
# devcontainer.
# ---------------------------------------------------------------------------
FRIDA_SRC                := frida/agent.ts
FRIDA_OUT                := frida/dist/agent.js

.PHONY: agent
agent:
	bunx frida-compile $(FRIDA_SRC) -o $(FRIDA_OUT)

.PHONY: attach
attach: agent
	@if [ -z "$(TARGET_BUNDLE_ID)" ]; then \
	  echo "TARGET_BUNDLE_ID required (set in .env or on the CLI)"; exit 1; \
	fi
	uv run frida -U -f $(TARGET_BUNDLE_ID) -l $(FRIDA_OUT) --no-pause

# ---------------------------------------------------------------------------
# clang-format runner. Formats tracked ObjC / C sources under Sources/.
# vendor/ is skipped so 3rd-party source stays byte-identical to upstream.
# ---------------------------------------------------------------------------
.PHONY: format
format:
	find Sources -type f \( -name '*.h' -o -name '*.m' -o -name '*.mm' \
	  -o -name '*.c' -o -name '*.cpp' \) -exec clang-format -i {} +

.PHONY: format-check
format-check:
	find Sources -type f \( -name '*.h' -o -name '*.m' -o -name '*.mm' \
	  -o -name '*.c' -o -name '*.cpp' \) -exec clang-format --dry-run --Werror {} +

# ---------------------------------------------------------------------------
# Developer hooks. Point core.hooksPath at scripts/ so scripts/pre-commit
# fires before every commit. Idempotent.
# ---------------------------------------------------------------------------
.PHONY: hooks
hooks::
	git config core.hooksPath scripts
	@echo "git hooks now resolve under scripts/"
