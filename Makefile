APP_NAME    = WireGuardLite
VERSION     = 1.0.0
BUILD_DIR   = build
APP_BUNDLE  = $(BUILD_DIR)/$(APP_NAME).app
BINARY      = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
SOURCES     = Sources/WireGuardLite.swift

SWIFT_COMMON = -swift-version 5 -O -framework Cocoa
SWIFT_ARM64  = $(SWIFT_COMMON) -target arm64-apple-macosx12.0
SWIFT_X86    = $(SWIFT_COMMON) -target x86_64-apple-macosx12.0

SUDOERS_FILE  = /etc/sudoers.d/wireguard-lite
WG_QUICK      = $(shell command -v wg-quick 2>/dev/null || echo /opt/homebrew/bin/wg-quick)
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
	cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/" 2>/dev/null || true
	codesign --force --sign - "$(APP_BUNDLE)"

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
	@echo "$(shell whoami) ALL=(ALL) NOPASSWD: $(WG_QUICK)" | sudo tee $(SUDOERS_FILE) > /dev/null
	sudo chmod 0440 $(SUDOERS_FILE)
	@echo "Done. wg-quick now runs without a password prompt."

# ── Remove passwordless sudo ────────────────────────────
unsetup:
	sudo rm -f $(SUDOERS_FILE)
	@echo "Removed sudoers rule. Password will be required again."

# ── Auto-start on login ─────────────────────────────────
autostart:
	@mkdir -p "$(HOME)/Library/LaunchAgents"
	@echo '<?xml version="1.0" encoding="UTF-8"?>'                                        >  $(LAUNCH_AGENT)
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"'                           >> $(LAUNCH_AGENT)
	@echo '  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'                           >> $(LAUNCH_AGENT)
	@echo '<plist version="1.0">'                                                          >> $(LAUNCH_AGENT)
	@echo '<dict>'                                                                         >> $(LAUNCH_AGENT)
	@echo '    <key>Label</key>'                                                           >> $(LAUNCH_AGENT)
	@echo '    <string>com.local.wireguard-lite</string>'                                  >> $(LAUNCH_AGENT)
	@echo '    <key>ProgramArguments</key>'                                                >> $(LAUNCH_AGENT)
	@echo '    <array>'                                                                    >> $(LAUNCH_AGENT)
	@echo '        <string>/Applications/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)</string>' >> $(LAUNCH_AGENT)
	@echo '    </array>'                                                                   >> $(LAUNCH_AGENT)
	@echo '    <key>RunAtLoad</key>'                                                       >> $(LAUNCH_AGENT)
	@echo '    <true/>'                                                                    >> $(LAUNCH_AGENT)
	@echo '    <key>KeepAlive</key>'                                                       >> $(LAUNCH_AGENT)
	@echo '    <false/>'                                                                   >> $(LAUNCH_AGENT)
	@echo '</dict>'                                                                        >> $(LAUNCH_AGENT)
	@echo '</plist>'                                                                       >> $(LAUNCH_AGENT)
	@echo "Auto-start enabled. WireGuard Lite will launch on login."

# ── Remove auto-start ───────────────────────────────────
noautostart:
	rm -f $(LAUNCH_AGENT)
	@echo "Auto-start disabled."

# ── Clean ────────────────────────────────────────────────
clean:
	rm -rf $(BUILD_DIR)
