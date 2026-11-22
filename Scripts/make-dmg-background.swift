// Renders the background for the Dozex.dmg window (660×400 pt, 1x and 2x).
// Usage: swift make-dmg-background.swift out-dir
// Icon centres must match Scripts/dmg-settings.py: Dozex (165, 190), Applications (495, 190).
import AppKit

let W: CGFloat = 660, H: CGFloat = 400
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)   // points, so 2x is marked retina
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    // Draw in a top-left coordinate space like Finder's.
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
    let flipped = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.current = flipped

    // Base: near-black with a violet glow behind the icons (matches the website).
    c(0.031, 0.035, 0.039).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    let glow = NSGradient(colors: [c(0.545, 0.424, 0.965, 0.30), c(0.545, 0.424, 0.965, 0.0)])!
    glow.draw(fromCenter: NSPoint(x: W / 2, y: 150), radius: 0, toCenter: NSPoint(x: W / 2, y: 150), radius: 340, options: [])
    let glow2 = NSGradient(colors: [c(0.96, 0.65, 0.14, 0.10), c(0.96, 0.65, 0.14, 0.0)])!
    glow2.draw(fromCenter: NSPoint(x: 495, y: 200), radius: 0, toCenter: NSPoint(x: 495, y: 200), radius: 200, options: [])

    // Subtle dot grid.
    c(1, 1, 1, 0.045).setFill()
    var y: CGFloat = 12
    while y < H { var x: CGFloat = 12; while x < W { NSBezierPath(ovalIn: NSRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)).fill(); x += 22 }; y += 22 }

    // Soft plates behind the two icons.
    for cx in [165.0, 495.0] as [CGFloat] {
        let r = NSRect(x: cx - 78, y: 190 - 78, width: 156, height: 156)
        let plate = NSBezierPath(roundedRect: r, xRadius: 34, yRadius: 34)
        c(1, 1, 1, 0.035).setFill(); plate.fill()
        c(1, 1, 1, 0.08).setStroke(); plate.lineWidth = 1; plate.stroke()
    }

    // Dashed arrow from Dozex to Applications.
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 262, y: 190)); arrow.line(to: NSPoint(x: 390, y: 190))
    arrow.lineWidth = 2.5; arrow.lineCapStyle = .round
    arrow.setLineDash([2, 9], count: 2, phase: 0)
    c(1, 1, 1, 0.55).setStroke(); arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 386, y: 180)); head.line(to: NSPoint(x: 398, y: 190)); head.line(to: NSPoint(x: 386, y: 200))
    head.lineWidth = 2.5; head.lineCapStyle = .round; head.lineJoinStyle = .round
    head.stroke()

    // Title and hint.
    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat, kern: CGFloat = 0) {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p, .kern: kern]
        NSAttributedString(string: s, attributes: attrs).draw(in: NSRect(x: 0, y: y, width: W, height: size * 1.4))
    }
    text("Install Dozex", size: 22, weight: .semibold, color: c(0.97, 0.97, 0.97), y: 34, kern: -0.4)
    text("Drag Dozex onto the Applications folder", size: 13, weight: .regular, color: c(0.54, 0.56, 0.60), y: 66)
    text("Then open it from Applications. The first time, click Open Anyway in System Settings → Privacy & Security.",
         size: 11, weight: .regular, color: c(0.42, 0.44, 0.47), y: 350)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] as [(CGFloat, String)] {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try! render(scale: scale).representation(using: .png, properties: [:])!.write(to: url)
}
print("wrote background.png and background@2x.png to \(outDir)")
