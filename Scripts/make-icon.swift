// Draws the MenuKey app icon and writes Resources/AppIcon.icns + Resources/AppIcon.png.
// Usage: swift Scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func drawIcon(in ctx: CGContext) {
    // macOS icon grid: 824pt rounded square centred on a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

    // Drop shadow under the tile
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x3B2BD9).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Background gradient
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(colors: [color(0x7B6CFF), color(0x4A33E0), color(0x24137A)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: tile, angle: -90)
    // Soft top glow
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: 420, y: 900), radius: 0, toCenter: NSPoint(x: 420, y: 900), radius: 620, options: [])

    // Menu bar strip across the top of the tile
    let bar = CGRect(x: 100, y: 770, width: 824, height: 70)
    NSColor.white.withAlphaComponent(0.16).setFill()
    NSBezierPath(rect: bar).fill()
    for (i, w) in [70.0, 92, 64, 80].enumerated() {
        let x = 170 + CGFloat(i) * 130
        NSColor.white.withAlphaComponent(i == 1 ? 0.95 : 0.55).setFill()
        NSBezierPath(roundedRect: CGRect(x: x, y: 795, width: w, height: 20), xRadius: 10, yRadius: 10).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    // Dropdown menu card
    let card = CGRect(x: 280, y: 290, width: 420, height: 480)
    NSGraphicsContext.saveGraphicsState()
    let cardShadow = NSShadow()
    cardShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    cardShadow.shadowBlurRadius = 40
    cardShadow.shadowOffset = NSSize(width: 0, height: -18)
    cardShadow.set()
    NSColor.white.withAlphaComponent(0.96).setFill()
    let cardPath = NSBezierPath(roundedRect: card, xRadius: 48, yRadius: 48)
    cardPath.append(NSBezierPath(rect: CGRect(x: card.minX, y: card.maxY - 60, width: card.width, height: 60)))
    cardPath.windingRule = .nonZero
    cardPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Rows
    let rows: [(CGFloat, Bool)] = [(250, false), (300, true), (210, false), (270, false)]
    for (i, row) in rows.enumerated() {
        let y = card.maxY - 90 - CGFloat(i) * 100
        if row.1 {
            let hl = CGRect(x: card.minX + 24, y: y - 30, width: card.width - 48, height: 84)
            NSGradient(colors: [color(0x6F5CFF), color(0x4A33E0)])!
                .draw(in: NSBezierPath(roundedRect: hl, xRadius: 26, yRadius: 26), angle: -90)
            NSColor.white.setFill()
        } else {
            color(0x24137A, 0.22).setFill()
        }
        NSBezierPath(roundedRect: CGRect(x: card.minX + 60, y: y, width: row.0, height: 24), xRadius: 12, yRadius: 12).fill()
    }

    // Magnifying glass
    let center = CGPoint(x: 650, y: 340)
    let radius: CGFloat = 112
    NSGraphicsContext.saveGraphicsState()
    let glassShadow = NSShadow()
    glassShadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
    glassShadow.shadowBlurRadius = 30
    glassShadow.shadowOffset = NSSize(width: 0, height: -14)
    glassShadow.set()
    let handle = NSBezierPath()
    handle.move(to: CGPoint(x: center.x + radius * 0.8, y: center.y - radius * 0.8))
    handle.line(to: CGPoint(x: center.x + radius * 1.35, y: center.y - radius * 1.35))
    handle.lineWidth = 64
    handle.lineCapStyle = .round
    color(0xFFB43B).setStroke()
    handle.stroke()
    let ringRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    NSColor.white.withAlphaComponent(0.3).setFill()
    NSBezierPath(ovalIn: ringRect).fill()
    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = 46
    color(0xFFC85A).setStroke()
    ring.stroke()
    NSGraphicsContext.restoreGraphicsState()
    // Lens highlight
    let hi = NSBezierPath()
    hi.appendArc(withCenter: center, radius: radius - 52, startAngle: 110, endAngle: 170)
    hi.lineWidth = 18
    hi.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.85).setStroke()
    hi.stroke()
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let s = CGFloat(px) / size
    gc.cgContext.scaleBy(x: s, y: s)
    drawIcon(in: gc.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let res = root.appendingPathComponent("Resources")
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: res.appendingPathComponent("AppIcon.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", res.appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
print("Wrote Resources/AppIcon.icns and Resources/AppIcon.png")
