APP_NAME    = WireGuardLite
VERSION     = 1.1.1
BUILD_DIR   = build
APP_BUNDLE  = $(BUILD_DIR)/$(APP_NAME).app
BINARY      = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
SOURCES     = Sources/WireGuardLite.swift

SWIFT_COMMON = -swift-version 5 -O -framework Cocoa
SWIFT_ARM64  = $(SWIFT_COMMON) -target arm64-apple-macosx12.0
SWIFT_X86    = $(SWIFT_COMMON) -target x86_64-apple-macosx12.0

SUDOERS_FILE  = /etc/sudoers.d/wireguard-lite
WG_QUICK      = $(shell for p in /opt/homebrew/bin/wg-quick /usr/local/bin/wg-quick /usr/bin/wg-quick; do [ -x "$$p" ] && echo "$$p" && break; done || echo /opt/homebrew/bin/wg-quick)

# Code-signing identity (use '-' for ad-hoc; override with Developer ID for distribution)
SIGN_IDENTITY ?= -

# All three standard config locations
WG_CONFIGS = /opt/homebrew/etc/wireguard/wg0.conf /usr/local/etc/wireguard/wg0.conf /etc/wireguard/wg0.conf
LAUNCH_AGENT  = $(HOME)/Library/LaunchAgents/com.local.wireguard-lite.plist

.PHONY: all run install uninstall setup unsetup autostart noautostart clean

# ── Build (universal binary: arm64 + x86_64) ───────────
all: $(APP_BUNDLE)
	@echo ""
	@echo "  Built  →  $(APP_BUNDLE) (v$(VERSION), universal)"
	@echo "  Run    →  make run"
	@echo "  Install→  make install"
	@echo "  Setup  →  make setup   (passwordless sudo)"
	@echo ""

$(APP_BUNDLE): $(SOURCES) Resources/Info.plist
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	swiftc $(SWIFT_ARM64) $(SOURCES) -o "$(BUILD_DIR)/$(APP_NAME)-arm64"
	swiftc $(SWIFT_X86)   $(SOURCES) -o "$(BUILD_DIR)/$(APP_NAME)-x86_64"
	lipo -create "$(BUILD_DIR)/$(APP_NAME)-arm64" "$(BUILD_DIR)/$(APP_NAME)-x86_64" -output "$(BINARY)"
	@rm -f "$(BUILD_DIR)/$(APP_NAME)-arm64" "$(BUILD_DIR)/$(APP_NAME)-x86_64"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" "$(APP_BUNDLE)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(APP_BUNDLE)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/" 2>/dev/null || true
	codesign --force --sign "$(SIGN_IDENTITY)" "$(APP_BUNDLE)"

# ── Run (from build dir) ────────────────────────────────
run: $(APP_BUNDLE)
	open "$(APP_BUNDLE)"

# ── Install to /Applications ────────────────────────────
install: $(APP_BUNDLE)
	cp -R "$(APP_BUNDLE)" /Applications/
	@echo "Installed → /Applications/$(APP_NAME).app"

# ── Uninstall ────────────────────────────────────────────
uninstall:
	rm -rf "/Applications/$(APP_NAME).app"
	@echo "Uninstalled $(APP_NAME)"

# ── Setup passwordless sudo for wg-quick ────────────────
setup:
	@echo "Creating sudoers rule for $(WG_QUICK)..."
	@{ \
		for conf in $(WG_CONFIGS); do \
			echo "$(shell whoami) ALL=(ALL) NOPASSWD: $(WG_QUICK) up $$conf"; \
			echo "$(shell whoami) ALL=(ALL) NOPASSWD: $(WG_QUICK) down $$conf"; \
		done; \
	} | sudo tee $(SUDOERS_FILE) > /dev/null
	sudo chmod 0440 $(SUDOERS_FILE)
	sudo visudo -cf $(SUDOERS_FILE) || { sudo rm -f $(SUDOERS_FILE); echo "ERROR: invalid sudoers syntax"; exit 1; }
	@echo "Done. wg-quick up/down restricted to known config paths."

# ── Remove passwordless sudo ────────────────────────────
unsetup:
	sudo rm -f $(SUDOERS_FILE)
	@echo "Removed sudoers rule. Password will be required again."

# ── Auto-start on login ─────────────────────────────────
autostart:
	@mkdir -p "$(HOME)/Library/LaunchAgents"
	sed 's/__APP_NAME__/$(APP_NAME)/g' Resources/LaunchAgent.plist.template > $(LAUNCH_AGENT)
	launchctl load $(LAUNCH_AGENT) 2>/dev/null || true
	@echo "Auto-start enabled and agent loaded."

# ── Remove auto-start ───────────────────────────────────
noautostart:
	launchctl unload $(LAUNCH_AGENT) 2>/dev/null || true
	rm -f $(LAUNCH_AGENT)
	@echo "Auto-start disabled and agent unloaded."

# ── Clean ────────────────────────────────────────────────
clean:
	rm -rf $(BUILD_DIR)
