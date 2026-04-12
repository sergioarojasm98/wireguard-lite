import Cocoa

// MARK: - StatusBarController

class StatusBarController: NSObject {

    static let version = "1.0.0"

    private let statusItem: NSStatusItem
    private var isConnected: Bool = false
    private var isProcessing: Bool = false
    private var timer: Timer?

    private let configPath: String
    private let wgQuickPath: String
    private let stateFile = "/var/run/wireguard/wg0.name"

    /// Finds the first existing path from a list of candidates.
    private static func findFirst(_ candidates: [String]) -> String {
        candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
    }

    override init() {
        wgQuickPath = Self.findFirst([
            "/opt/homebrew/bin/wg-quick",   // Homebrew (Apple Silicon)
            "/usr/local/bin/wg-quick",      // Homebrew (Intel)
            "/usr/bin/wg-quick",            // System
        ])
        configPath = Self.findFirst([
            "/opt/homebrew/etc/wireguard/wg0.conf",  // Homebrew (Apple Silicon)
            "/usr/local/etc/wireguard/wg0.conf",     // Homebrew (Intel)
            "/etc/wireguard/wg0.conf",                // System
        ])
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        refreshStatus()
        updateIcon()
        buildMenu()

        // Poll every 5 seconds to catch external changes (e.g. terminal)
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }

        // Alert if config file is missing
        if !FileManager.default.fileExists(atPath: configPath) {
            showConfigMissing()
        }
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Status detection

    /// Checks if the WireGuard tunnel is up by looking for the state file
    /// that wg-quick creates at /var/run/wireguard/wg0.name
    private func refreshStatus() {
        let connected = FileManager.default.fileExists(atPath: stateFile)
        if connected != isConnected {
            isConnected = connected
            updateUI()
        }
    }

    // MARK: - Icon

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let symbolName = isConnected ? "lock.shield.fill" : "lock.shield"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "WireGuard") {
            image.isTemplate = true
            button.image = image
        }
        button.appearsDisabled = !isConnected
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        // Status label (non-interactive)
        let statusMenuItem = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        // Toggle connect/disconnect
        let toggleItem = NSMenuItem(title: toggleText(), action: #selector(toggleVPN), keyEquivalent: "t")
        toggleItem.tag = 200
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateUI() {
        updateIcon()
        updateMenuItems()
    }

    private func updateMenuItems() {
        guard let menu = statusItem.menu else { return }
        menu.item(withTag: 100)?.title = statusText()
        let toggle = menu.item(withTag: 200)
        toggle?.title = toggleText()
        toggle?.isEnabled = !isProcessing
    }

    private func statusText() -> String {
        if isProcessing {
            return isConnected ? "Disconnecting..." : "Connecting..."
        }
        return isConnected ? "WireGuard: Connected" : "WireGuard: Disconnected"
    }

    private func toggleText() -> String {
        if isProcessing { return "Please wait..." }
        return isConnected ? "Disconnect" : "Connect"
    }

    // MARK: - VPN toggle

    @objc private func toggleVPN() {
        guard !isProcessing else { return }

        isProcessing = true
        updateUI()

        let action = isConnected ? "down" : "up"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let success = self.runWgQuick(action: action)

            // Give wg-quick a moment to create/remove state files
            Thread.sleep(forTimeInterval: 1.0)

            DispatchQueue.main.async {
                self.isProcessing = false
                self.refreshStatus()
                self.updateUI()

                if !success {
                    self.showToggleError()
                }
            }
        }
    }

    /// Runs wg-quick via sudo (passwordless if sudoers is configured via `make setup`).
    /// Falls back to osascript admin-privilege prompt if sudo fails.
    private func runWgQuick(action: String) -> Bool {
        // Homebrew paths so wg-quick can find wg, wireguard-go, bash, etc.
        let env: [String: String] = [
            "PATH": "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]

        // 1) Try passwordless sudo first (works after `make setup`)
        if runProcess("/usr/bin/sudo", args: ["-n", wgQuickPath, action, configPath], env: env) {
            return true
        }

        // 2) Fallback: osascript privilege prompt (shows password dialog)
        let command = "PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \(wgQuickPath) \(action) \(configPath)"
        return runOsascriptPrivileged(command)
    }

    /// Runs an executable with optional environment.  Returns true on exit-code 0.
    private func runProcess(_ path: String, args: [String], env: [String: String]? = nil) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let env = env { process.environment = env }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Asks for the admin password via the native macOS dialog (osascript fallback).
    private func runOsascriptPrivileged(_ command: String) -> Bool {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return runProcess("/usr/bin/osascript", args: ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
    }

    // MARK: - Alerts

    private func showToggleError() {
        let alert = NSAlert()
        alert.messageText = "WireGuard Error"
        alert.informativeText = "Failed to toggle the VPN connection.\n\nMake sure wg-quick is installed and the config file exists at:\n\(configPath)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showConfigMissing() {
        let alert = NSAlert()
        alert.messageText = "Config Not Found"
        alert.informativeText = "WireGuard config file not found at:\n\(configPath)\n\nPlease create it before connecting."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusBarController()
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // hide from Dock, menu-bar only
let delegate = AppDelegate()
app.delegate = delegate
app.run()
