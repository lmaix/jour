import AppKit

/// Menu bar icon: a small calendar glyph with the day number. Template image, so macOS tints it.
enum StatusIcon {
    static func image(day: Int) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            let body = NSRect(x: 1.5, y: 1.5, width: 17, height: 14)
            let path = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
            path.lineWidth = 1.5
            NSColor.black.setStroke()
            path.stroke()
            // Top band (the "binding" of the calendar)
            let band = NSBezierPath()
            band.appendRoundedRect(NSRect(x: 1.5, y: 12, width: 17, height: 3.5), xRadius: 3, yRadius: 3)
            band.appendRect(NSRect(x: 1.5, y: 12, width: 17, height: 1.5))
            NSColor.black.setFill()
            band.fill()
            // Day number
            let font = NSFont.systemFont(ofSize: 9, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let s = NSAttributedString(string: "\(day)", attributes: attrs)
            let sz = s.size()
            s.draw(at: NSPoint(x: body.midX - sz.width / 2, y: 2.5 + (9 - sz.height) / 2))
            return true
        }
        img.isTemplate = true
        return img
    }
}
