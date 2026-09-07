// Renders Resources/AppIcon.icns from the "headphones" SF Symbol, so the icon is
// reproducible instead of a binary blob nobody can regenerate.
//
//   swift Resources/make-icon.swift && Resources/make-icon.sh

import AppKit

let canvas: CGFloat = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS app icons sit inside a rounded square with a margin around it.
let margin: CGFloat = 100
let plate = NSRect(x: margin, y: margin, width: canvas - 2 * margin, height: canvas - 2 * margin)
let squircle = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)
NSGradient(
    starting: NSColor(srgbRed: 0.36, green: 0.40, blue: 0.92, alpha: 1),
    ending: NSColor(srgbRed: 0.13, green: 0.16, blue: 0.42, alpha: 1)
)?.draw(in: squircle, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 460, weight: .medium)
if let symbol = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    // Symbols are template images; paint it white before compositing.
    let white = NSImage(size: symbol.size)
    white.lockFocus()
    let bounds = NSRect(origin: .zero, size: symbol.size)
    symbol.draw(in: bounds)
    NSColor.white.set()
    bounds.fill(using: .sourceAtop)
    white.unlockFocus()

    let target = NSRect(
        x: (canvas - symbol.size.width) / 2,
        y: (canvas - symbol.size.height) / 2,
        width: symbol.size.width,
        height: symbol.size.height
    )
    white.draw(in: target)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
let out = URL(fileURLWithPath: "Resources/icon-1024.png")
try png.write(to: out)
print("wrote \(out.path)")
