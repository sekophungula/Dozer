import AppKit

/// Dozex's eye, drawn in code so the menu bar matches the app icon.
/// - `awake`: half-open eye (keeping the Mac up for Claude)
/// - `dozing`: closed eye with lashes (watching, Mac may sleep)
/// - `off`: closed eye with a slash
enum EyeIcon {
    enum Style { case awake, dozing, off }

    /// Template image sized for the menu bar.
    static func menuBar(_ style: Style) -> NSImage { image(style, size: 18) }

    static func image(_ style: Style, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(style, in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(_ style: Style, in rect: NSRect) {
        let s = rect.width
        let line = s * 0.11
        let cx = rect.midX, cy = rect.minY + s * 0.62
        let w = s * 0.40, depth = s * 0.36
        NSColor.black.setStroke(); NSColor.black.setFill()

        // Lower lid: a downward curve from corner to corner.
        let lid = NSBezierPath()
        lid.move(to: NSPoint(x: cx - w, y: cy))
        lid.curve(to: NSPoint(x: cx + w, y: cy),
                  controlPoint1: NSPoint(x: cx - w * 0.46, y: cy - depth),
                  controlPoint2: NSPoint(x: cx + w * 0.46, y: cy - depth))
        lid.lineWidth = line; lid.lineCapStyle = .round

        if style == .awake {
            // Pupil peeking out under a flat upper lid.
            let opening = lid.copy() as! NSBezierPath; opening.close()
            NSGraphicsContext.saveGraphicsState(); opening.addClip()
            let r = depth * 0.5
            NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)).fill()
            NSGraphicsContext.restoreGraphicsState()
            let top = NSBezierPath()
            top.move(to: NSPoint(x: cx - w - line * 0.3, y: cy))
            top.line(to: NSPoint(x: cx + w + line * 0.3, y: cy))
            top.lineWidth = line * 1.1; top.lineCapStyle = .round; top.stroke()
        }
        lid.stroke()

        // Lashes.
        for dx in [-0.62, 0.0, 0.62] as [CGFloat] {
            let x = cx + dx * w, y = cy - depth * 0.75 * (1 - dx * dx)
            let lash = NSBezierPath()
            lash.move(to: NSPoint(x: x, y: y))
            lash.line(to: NSPoint(x: x + dx * s * 0.08, y: y - s * 0.16))
            lash.lineWidth = line * 0.85; lash.lineCapStyle = .round; lash.stroke()
        }

        if style == .off {
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX + s * 0.12, y: rect.minY + s * 0.1))
            slash.line(to: NSPoint(x: rect.maxX - s * 0.12, y: rect.maxY - s * 0.1))
            slash.lineWidth = line; slash.lineCapStyle = .round; slash.stroke()
        }
    }
}
