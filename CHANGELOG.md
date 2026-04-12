# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-04-12

### Security
- Fix command injection vulnerability in osascript privilege escalation
- Restrict sudoers rule to specific wg-quick up/down commands with known config paths
- Add sudoers syntax validation with `visudo -cf`

### Added
- Duplicate instance prevention via NSRunningApplication check
- Detailed error diagnostics: stderr output shown in failure alerts
- CI lint job with plist validation and Swift compilation warnings check
- Build artifact upload in CI pipeline
- Code signature verification in CI
- Configurable code-signing identity via `SIGN_IDENTITY` Makefile variable
- NSLog warning when no WireGuard paths are found on disk
- LaunchAgent plist template file (replaces inline Makefile generation)

### Changed
- Version now managed from single source of truth (Makefile `VERSION`)
- `Thread.sleep` replaced with `DispatchQueue.main.asyncAfter` to avoid blocking GCD threads
- `generate_icon.swift` modernized: replaced deprecated `lockFocus`/`unlockFocus` with drawing handler

### Fixed
- `findFirst` no longer fails silently when no candidate paths exist

## [1.0.0] - 2026-03-28

### Added
- Initial release
- macOS menu-bar app to toggle WireGuard VPN via wg-quick
- Universal binary support (arm64 + x86_64)
- Passwordless sudo setup via Makefile
- Auto-start on login via LaunchAgent
- Poll-based external state detection (5s interval)
- App icon generation script
