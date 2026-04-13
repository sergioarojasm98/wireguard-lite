#!/usr/bin/env swift
import Cocoa

// Generates an .iconset with the lock.shield.fill SF Symbol
// on a blue rounded-rect background, then converts to .icns.

let iconsetDir = "build/AppIcon.iconset"
let sizes: [(String, Int)] = [
    ("icon_16x16",       16),
    ("icon_16x16@2x",    32),
    ("icon_32x32",       32),
    ("icon_32x32@2x",    64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x",1024),
]

let fm = FileManager.default
do {
    try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
} catch {
    fputs("Error creating iconset directory: \(error.localizedDescription)\n", stderr)
    exit(1)
}

for (name, px) in sizes {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in

        // ── Rounded-rect background with blue gradient ──
        let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
        let gradient = NSGradient(
            starting: NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.95, alpha: 1),
            ending:   NSColor(calibratedRed: 0.12, green: 0.32, blue: 0.78, alpha: 1)
        )!
        gradient.draw(in: path, angle: -90)

        // ── White shield symbol centered ──
        if let symbol = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil) {
            let pointSize = s * 0.52
            let baseConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            let colorConfig = NSImage.SymbolConfiguration(hierarchicalColor: .white)
            let config = baseConfig.applying(colorConfig)

            if let tinted = symbol.withSymbolConfiguration(config) {
                let symW = tinted.size.width
                let symH = tinted.size.height
                let x = (s - symW) / 2
                let y = (s - symH) / 2
                tinted.draw(in: NSRect(x: x, y: y, width: symW, height: symH),
                            from: .zero, operation: .sourceOver, fraction: 1.0)
            }
        }

        return true
    }

    // ── Write PNG ──
    guard let tiff = img.tiffRepresentation,
          let rep  = NSBitmapImageRep(data: tiff),
          let png  = rep.representation(using: .png, properties: [:]) else {
        fputs("Error: failed to render \(name)\n", stderr)
        continue
    }
    let url = URL(fileURLWithPath: "\(iconsetDir)/\(name).png")
    do {
        try png.write(to: url)
    } catch {
        fputs("Error writing \(name): \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

print("Icon set generated at \(iconsetDir)")

// ── Convert .iconset to .icns ──
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", iconsetDir, "--output", "Resources/AppIcon.icns"]
do {
    try iconutil.run()
    iconutil.waitUntilExit()
    if iconutil.terminationStatus != 0 {
        fputs("Error: iconutil exited with status \(iconutil.terminationStatus)\n", stderr)
        exit(1)
    }
    print("Converted to Resources/AppIcon.icns")
} catch {
    fputs("Error running iconutil: \(error.localizedDescription)\n", stderr)
    exit(1)
}
