// Draws the app icon: a calendar page with a day number on a dark macOS squircle.
//   swift Tools/make-icon.swift Resources/AppIcon.icns
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    // macOS icon grid: 824 pt body centered in 1024, with a soft drop shadow.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 20 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.21, blue: 0.25, alpha: 1),
               ending: NSColor(srgbRed: 0.08, green: 0.08, blue: 0.10, alpha: 1))!.draw(in: squircle, angle: -90)

    // Calendar page: white sheet, blue header with binding rings, big day number.
    let page = NSRect(x: 262 * s, y: 262 * s, width: 500 * s, height: 500 * s)
    let pagePath = NSBezierPath(roundedRect: page, xRadius: 70 * s, yRadius: 70 * s)
    NSGraphicsContext.saveGraphicsState()
    let pageShadow = NSShadow()
    pageShadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
    pageShadow.shadowBlurRadius = 24 * s
    pageShadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    pageShadow.set()
    NSColor.white.setFill()
    pagePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor.white, ending: NSColor(srgbRed: 0.88, green: 0.89, blue: 0.92, alpha: 1))!
        .draw(in: pagePath, angle: -90)

    // Header band, clipped to the page's top rounded corners.
    NSGraphicsContext.saveGraphicsState()
    pagePath.addClip()
    let header = NSRect(x: page.minX, y: page.maxY - 140 * s, width: page.width, height: 140 * s)
    NSGradient(starting: NSColor(srgbRed: 0.38, green: 0.62, blue: 1.00, alpha: 1),
               ending: NSColor(srgbRed: 0.05, green: 0.38, blue: 0.95, alpha: 1))!
        .draw(in: header, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Binding rings through the header.
    for x in [page.minX + 130 * s, page.maxX - 130 * s] {
        let ring = NSBezierPath(roundedRect: NSRect(x: x - 16 * s, y: header.midY - 10 * s, width: 32 * s, height: 110 * s),
                                xRadius: 16 * s, yRadius: 16 * s)
        ring.lineWidth = 26 * s
        NSColor(srgbRed: 0.75, green: 0.78, blue: 0.83, alpha: 1).setStroke()
        ring.stroke()
    }

    // Day number, centered in the body of the page.
    let font = NSFont.systemFont(ofSize: 300 * s, weight: .bold)
    let text = NSAttributedString(string: "1", attributes: [.font: font,
        .foregroundColor: NSColor(srgbRed: 0.13, green: 0.15, blue: 0.19, alpha: 1)])
    let line = CTLineCreateWithAttributedString(text)
    let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let bodyCenter = NSPoint(x: page.midX, y: (page.minY + header.minY) / 2)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.textPosition = CGPoint(x: bodyCenter.x - ink.midX, y: bodyCenter.y - ink.midY)
    CTLineDraw(line, ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
if out.pathExtension == "png" {
    try! drawIcon(size: 1024).representation(using: .png, properties: [:])!.write(to: out)
} else {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
    try! p.run(); p.waitUntilExit()
}
