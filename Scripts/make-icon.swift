// Renders Sleepable's app icon (1024×1024 PNG). Usage: swift make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824pt rounded square centred in 1024.
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

NSGraphicsContext.current?.cgContext.setShadow(offset: CGSize(width: 0, height: -12), blur: 30,
                                               color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill(); shape.fill()
NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.13, green: 0.11, blue: 0.33, alpha: 1),   // night indigo
    NSColor(srgbRed: 0.42, green: 0.22, blue: 0.55, alpha: 1),   // dusk violet
    NSColor(srgbRed: 0.98, green: 0.55, blue: 0.27, alpha: 1),   // ember orange
])!
gradient.draw(in: shape, angle: -90)

// Moon (night) top-left, cup (awake) centre.
func symbol(_ name: String, points: CGFloat, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: points, weight: .semibold)
        .applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}
let moon = symbol("moon.stars.fill", points: 150, color: NSColor.white.withAlphaComponent(0.85))
moon.draw(in: NSRect(x: 210, y: 610, width: moon.size.width, height: moon.size.height))
let cup = symbol("cup.and.heat.waves.fill", points: 330, color: .white)
let cupRect = NSRect(x: (size - cup.size.width) / 2 + 12, y: 230, width: cup.size.width, height: cup.size.height)
cup.draw(in: cupRect)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
