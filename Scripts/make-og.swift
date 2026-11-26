// Renders the website's link-preview card (1200×630 PNG): the app icon on
// the left, "Dozex" and a byline on the right, on a dark violet background.
// Usage: swift make-og.swift icon-1024.png out.png
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let icon = NSImage(contentsOfFile: args[1]) else {
    print("usage: make-og.swift icon-1024.png out.png"); exit(1)
}
let W: CGFloat = 1200, H: CGFloat = 630
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let full = NSRect(x: 0, y: 0, width: W, height: H)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Night sky: near-black at the top fading into the icon's violet.
NSGradient(colors: [rgb(11, 10, 18), rgb(24, 16, 52), rgb(52, 32, 112)])!.draw(in: full, angle: -90)
// A soft glow behind the icon.
NSGradient(colors: [rgb(139, 108, 246, 0.45), rgb(139, 108, 246, 0)])!
    .draw(fromCenter: NSPoint(x: 290, y: 315), radius: 0, toCenter: NSPoint(x: 290, y: 315), radius: 340, options: [])

// Faint grid, like the website's background.
ctx.setStrokeColor(rgb(255, 255, 255, 0.045).cgColor)
ctx.setLineWidth(1)
stride(from: CGFloat(0), through: W, by: 48).forEach { x in ctx.move(to: CGPoint(x: x + 0.5, y: 0)); ctx.addLine(to: CGPoint(x: x + 0.5, y: H)) }
stride(from: CGFloat(0), through: H, by: 48).forEach { y in ctx.move(to: CGPoint(x: 0, y: y + 0.5)); ctx.addLine(to: CGPoint(x: W, y: y + 0.5)) }
ctx.strokePath()

// A few stars.
for (x, y, r) in [(700.0, 560.0, 2.0), (1110, 520, 1.5), (960, 590, 1.2), (1150, 120, 1.6), (640, 90, 1.2), (1040, 70, 2.0)] as [(CGFloat, CGFloat, CGFloat)] {
    rgb(255, 255, 255, 0.55).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
}

// The app icon, offset to the left. The 1024 icon has ~100px of margin and
// a drop shadow built in, so draw it a little larger than the visible tile.
let iconSize: CGFloat = 420
icon.draw(in: NSRect(x: 80, y: (H - iconSize) / 2 - 6, width: iconSize, height: iconSize))

// Title and byline.
let textX: CGFloat = 560
let title = NSAttributedString(string: "Dozex", attributes: [
    .font: NSFont.systemFont(ofSize: 132, weight: .bold),
    .foregroundColor: NSColor.white,
    .kern: -4,
])
title.draw(at: NSPoint(x: textX - 6, y: 318))

let byline = NSMutableParagraphStyle(); byline.lineSpacing = 6
NSAttributedString(string: "Keeps your Mac awake while your\nwork runs, then lets it sleep.", attributes: [
    .font: NSFont.systemFont(ofSize: 38, weight: .medium),
    .foregroundColor: rgb(225, 218, 255, 0.86),
    .paragraphStyle: byline,
]).draw(in: NSRect(x: textX, y: 190, width: 600, height: 120))

NSAttributedString(string: "EXPORTS · RENDERS · DOWNLOADS · AI AGENTS", attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .medium),
    .foregroundColor: rgb(182, 164, 255),
    .kern: 1.5,
]).draw(at: NSPoint(x: textX, y: 140))

NSAttributedString(string: "dozer.shakatec.co.za", attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .regular),
    .foregroundColor: rgb(255, 255, 255, 0.45),
]).draw(at: NSPoint(x: textX, y: 64))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
