// Renders Dozer's app icon (1024×1024 PNG): a dozing eye on violet.
// Usage: swift make-icon.swift out.png
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

let ctx = NSGraphicsContext.current!.cgContext
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.3).cgColor)
NSColor.black.setFill(); shape.fill()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

NSGradient(colors: [
    NSColor(srgbRed: 0.20, green: 0.12, blue: 0.42, alpha: 1),   // deep violet
    NSColor(srgbRed: 0.45, green: 0.30, blue: 0.85, alpha: 1),   // lavender
])!.draw(in: shape, angle: -90)

// Closed, dozing eye: a lower-lid curve with lashes.
let cx: CGFloat = 512, cy: CGFloat = 650, w: CGFloat = 280, depth: CGFloat = 250
NSColor.white.setStroke()
let lid = NSBezierPath()
lid.move(to: NSPoint(x: cx - w, y: cy))
lid.curve(to: NSPoint(x: cx + w, y: cy),
          controlPoint1: NSPoint(x: cx - w * 0.46, y: cy - depth),
          controlPoint2: NSPoint(x: cx + w * 0.46, y: cy - depth))
lid.lineWidth = 54; lid.lineCapStyle = .round; lid.stroke()
for dx in [-0.65, -0.22, 0.22, 0.65] as [CGFloat] {
    let x = cx + dx * w, y = cy - depth * 0.75 * (1 - dx * dx)
    let lash = NSBezierPath()
    lash.move(to: NSPoint(x: x, y: y))
    lash.line(to: NSPoint(x: x + dx * 60, y: y - 100))
    lash.lineWidth = 40; lash.lineCapStyle = .round; lash.stroke()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
