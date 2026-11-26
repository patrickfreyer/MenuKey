// Draws the JumpKey app icon.
//   swift Scripts/make-icon.swift            -> Resources/AppIcon.icns + Resources/AppIcon.png (variant B)
//   swift Scripts/make-icon.swift A|B|C      -> same, for that variant
//   swift Scripts/make-icon.swift sheet <out.png>   -> side-by-side comparison of all variants
import AppKit

let canvas: CGFloat = 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)

// MARK: - Helpers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Apple-style continuous-corner squircle (superellipse, n = 5).
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * copysign(pow(abs(c), 2 / n), c)
        let y = cy + b * copysign(pow(abs(s), 2 / n), s)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil)
}

func fill(_ ctx: CGContext, _ path: CGPath, top: CGColor, bottom: CGColor, in rect: CGRect? = nil) {
    let r = rect ?? path.boundingBox
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: r.midX, y: r.maxY), end: CGPoint(x: r.midX, y: r.minY), options: [])
    ctx.restoreGState()
}

func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}

func shadow(_ ctx: CGContext, y: CGFloat, blur: CGFloat, alpha: CGFloat, _ body: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: y), blur: blur, color: rgb(0x000000, alpha))
    body()
    ctx.restoreGState()
}

func glow(_ ctx: CGContext, clip: CGPath, center: CGPoint, radius: CGFloat, alpha: CGFloat) {
    ctx.saveGState()
    ctx.addPath(clip)
    ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: [rgb(0xFFFFFF, alpha), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    ctx.restoreGState()
}

/// Thin bright rim along the top edge, like light catching glass.
func rim(_ ctx: CGContext, _ path: CGPath, alpha: CGFloat, width: CGFloat = 4) {
    let r = path.boundingBox
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(width)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: [rgb(0xFFFFFF, alpha), rgb(0xFFFFFF, 0), rgb(0xFFFFFF, alpha * 0.3)] as CFArray,
                       locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: r.midX, y: r.maxY), end: CGPoint(x: r.midX, y: r.minY), options: [])
    ctx.restoreGState()
}

func tileBase(_ ctx: CGContext, top: UInt32, bottom: UInt32, highlight: CGFloat) -> CGPath {
    let path = squircle(tile)
    shadow(ctx, y: -10, blur: 24, alpha: 0.30) { fill(ctx, path, rgb(bottom)) }
    fill(ctx, path, top: rgb(top), bottom: rgb(bottom))
    glow(ctx, clip: path, center: CGPoint(x: 380, y: 940), radius: 700, alpha: highlight)
    return path
}

// MARK: - Variant A: glass keycap

func drawA(_ ctx: CGContext) {
    let t = tileBase(ctx, top: 0x6E86FF, bottom: 0x3527C9, highlight: 0.30)
    rim(ctx, t, alpha: 0.5)

    // Keycap: darker skirt + lighter face, lit from above.
    let skirt = rounded(CGRect(x: 232, y: 226, width: 560, height: 590), 120)
    let face = rounded(CGRect(x: 262, y: 286, width: 500, height: 500), 96)
    shadow(ctx, y: -26, blur: 50, alpha: 0.40) { fill(ctx, skirt, rgb(0xC9CDEB)) }
    fill(ctx, skirt, top: rgb(0xF1F2FA), bottom: rgb(0xA9AED6))
    fill(ctx, face, top: rgb(0xFFFFFF), bottom: rgb(0xE6E8F4))
    rim(ctx, face, alpha: 0.9, width: 5)

    // Menu rows on the face, the middle one selected.
    fill(ctx, rounded(CGRect(x: 330, y: 640, width: 300, height: 30), 15), rgb(0x2A2350, 0.18))
    let sel = rounded(CGRect(x: 300, y: 488, width: 424, height: 96), 30)
    shadow(ctx, y: -6, blur: 14, alpha: 0.25) { fill(ctx, sel, rgb(0x3F5BFF)) }
    fill(ctx, sel, top: rgb(0x6E8BFF), bottom: rgb(0x3A4CF0))
    rim(ctx, sel, alpha: 0.6, width: 3)
    fill(ctx, rounded(CGRect(x: 340, y: 522, width: 250, height: 28), 14), rgb(0xFFFFFF))
    fill(ctx, rounded(CGRect(x: 330, y: 400, width: 240, height: 30), 15), rgb(0x2A2350, 0.18))
}

// MARK: - Variant B: light utility, a tiny JumpKey panel

func drawB(_ ctx: CGContext) {
    let t = tileBase(ctx, top: 0xFDFDFF, bottom: 0xD5DBE8, highlight: 0.0)
    // faint cool tint toward the bottom for depth
    ctx.saveGState(); ctx.addPath(t); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: [rgb(0x7FA4FF, 0.0), rgb(0x7FA4FF, 0.22)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 600), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()
    rim(ctx, t, alpha: 0.9)

    // The panel
    let panel = rounded(CGRect(x: 190, y: 238, width: 644, height: 548), 84)
    shadow(ctx, y: -24, blur: 60, alpha: 0.22) { fill(ctx, panel, rgb(0xFFFFFF)) }
    fill(ctx, panel, top: rgb(0xFFFFFF), bottom: rgb(0xF3F5FA))
    ctx.addPath(panel); ctx.setStrokeColor(rgb(0x1B2440, 0.07)); ctx.setLineWidth(3); ctx.strokePath()

    // Search field: lens + typed text + caret
    ctx.setStrokeColor(rgb(0x8A90A0)); ctx.setLineWidth(14); ctx.setLineCap(.round)
    ctx.strokeEllipse(in: CGRect(x: 250, y: 650, width: 64, height: 64))
    ctx.move(to: CGPoint(x: 304, y: 656)); ctx.addLine(to: CGPoint(x: 330, y: 630)); ctx.strokePath()
    fill(ctx, rounded(CGRect(x: 370, y: 666, width: 210, height: 34), 17), rgb(0x2B3040, 0.85))
    fill(ctx, rounded(CGRect(x: 596, y: 648, width: 10, height: 70), 5), rgb(0x2F6BFF))
    fill(ctx, CGPath(rect: CGRect(x: 190, y: 600, width: 644, height: 3), transform: nil), rgb(0x1B2440, 0.07))

    // Rows
    let sel = rounded(CGRect(x: 222, y: 470, width: 580, height: 104), 34)
    shadow(ctx, y: -6, blur: 16, alpha: 0.22) { fill(ctx, sel, rgb(0x2F6BFF)) }
    fill(ctx, sel, top: rgb(0x5A94FF), bottom: rgb(0x2C63F5))
    rim(ctx, sel, alpha: 0.5, width: 3)
    fill(ctx, rounded(CGRect(x: 262, y: 506, width: 270, height: 32), 16), rgb(0xFFFFFF))
    fill(ctx, rounded(CGRect(x: 676, y: 500, width: 92, height: 44), 22), rgb(0xFFFFFF, 0.3))
    fill(ctx, rounded(CGRect(x: 262, y: 392, width: 320, height: 28), 14), rgb(0x1B2440, 0.16))
    fill(ctx, rounded(CGRect(x: 262, y: 300, width: 230, height: 28), 14), rgb(0x1B2440, 0.16))
}

// MARK: - Variant C: graphite with a lens

func drawC(_ ctx: CGContext) {
    let t = tileBase(ctx, top: 0x51566A, bottom: 0x1C1F27, highlight: 0.18)
    rim(ctx, t, alpha: 0.35)

    // Faint menu list in the background
    for (i, w) in [380.0, 300, 420, 260, 340].enumerated() {
        fill(ctx, rounded(CGRect(x: 210, y: 760 - CGFloat(i) * 96, width: w, height: 30), 15), rgb(0xFFFFFF, 0.10))
    }

    let center = CGPoint(x: 470, y: 560), r: CGFloat = 222
    let lens = CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2), transform: nil)

    // Handle
    shadow(ctx, y: -18, blur: 36, alpha: 0.5) {
        ctx.setLineCap(.round); ctx.setLineWidth(96); ctx.setStrokeColor(rgb(0x2A2D36))
        ctx.move(to: CGPoint(x: center.x + r * 0.8, y: center.y - r * 0.8))
        ctx.addLine(to: CGPoint(x: 812, y: 222)); ctx.strokePath()
    }
    ctx.saveGState()
    ctx.setLineCap(.round); ctx.setLineWidth(96)
    ctx.move(to: CGPoint(x: center.x + r * 0.8, y: center.y - r * 0.8)); ctx.addLine(to: CGPoint(x: 812, y: 222))
    ctx.replacePathWithStrokedPath(); ctx.clip()
    let hg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [rgb(0xFFB547), rgb(0xF07B1F)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hg, start: CGPoint(x: 640, y: 420), end: CGPoint(x: 800, y: 220), options: [])
    ctx.restoreGState()

    // Lens glass with magnified rows inside
    shadow(ctx, y: -20, blur: 40, alpha: 0.45) { fill(ctx, lens, rgb(0xFFFFFF, 0.9)) }
    fill(ctx, lens, top: rgb(0xFFFFFF), bottom: rgb(0xE4E8F2))
    ctx.saveGState(); ctx.addPath(lens); ctx.clip()
    fill(ctx, rounded(CGRect(x: 300, y: 650, width: 300, height: 40), 20), rgb(0x1B2440, 0.16))
    let sel = rounded(CGRect(x: 250, y: 505, width: 460, height: 112), 36)
    fill(ctx, sel, top: rgb(0x5A94FF), bottom: rgb(0x2C63F5))
    fill(ctx, rounded(CGRect(x: 300, y: 544, width: 250, height: 36), 18), rgb(0xFFFFFF))
    fill(ctx, rounded(CGRect(x: 300, y: 430, width: 220, height: 40), 20), rgb(0x1B2440, 0.16))
    ctx.restoreGState()

    // Metal rim
    ctx.saveGState()
    ctx.addPath(lens); ctx.setLineWidth(44); ctx.replacePathWithStrokedPath(); ctx.clip()
    let rg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [rgb(0xFFFFFF), rgb(0xB7BDC9), rgb(0x8C93A3)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(rg, start: CGPoint(x: center.x, y: center.y + r), end: CGPoint(x: center.x, y: center.y - r), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Specular arc
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.9)); ctx.setLineWidth(16); ctx.setLineCap(.round)
    ctx.addArc(center: center, radius: r - 58, startAngle: .pi * 0.62, endAngle: .pi * 0.9, clockwise: false)
    ctx.strokePath()
}

// MARK: - Rendering

let variants: [String: (CGContext) -> Void] = ["A": drawA, "B": drawB, "C": drawC]

func render(_ draw: (CGContext) -> Void, px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / canvas, y: CGFloat(px) / canvas)
    draw(ctx)
    return ctx.makeImage()!
}

func png(_ img: CGImage) -> Data {
    NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
}

let args = Array(CommandLine.arguments.dropFirst())
let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)

if args.first == "sheet", args.count >= 2 {
    // Comparison: each variant big, plus Dock (128) and Finder-list (32) sizes, on light and dark.
    let w = 1500, h = 980
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(rgb(0xECEEF3)); ctx.fill(CGRect(x: 0, y: 490, width: w, height: 490))
    ctx.setFillColor(rgb(0x1E1F24)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: 490))
    for (i, key) in ["A", "B", "C"].enumerated() {
        let x = CGFloat(60 + i * 480)
        let big = render(variants[key]!, px: 1024)
        ctx.draw(big, in: CGRect(x: x, y: 560, width: 380, height: 380))
        ctx.draw(render(variants[key]!, px: 256), in: CGRect(x: x, y: 330, width: 128, height: 128))
        ctx.draw(render(variants[key]!, px: 128), in: CGRect(x: x + 160, y: 362, width: 64, height: 64))
        ctx.draw(render(variants[key]!, px: 64), in: CGRect(x: x + 250, y: 378, width: 32, height: 32))
        ctx.draw(render(variants[key]!, px: 32), in: CGRect(x: x + 300, y: 386, width: 16, height: 16))
        let label = NSAttributedString(string: key, attributes: [.font: NSFont.systemFont(ofSize: 44, weight: .bold),
                                                                .foregroundColor: NSColor.white])
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        label.draw(at: NSPoint(x: x + 170, y: 200))
        NSGraphicsContext.restoreGraphicsState()
    }
    try! png(ctx.makeImage()!).write(to: URL(fileURLWithPath: args[1]))
    print("Wrote \(args[1])")
    exit(0)
}

let key = args.first.map { $0.uppercased() } ?? "B"
guard let draw = variants[key] else { print("Unknown variant \(key)"); exit(1) }
let res = root.appendingPathComponent("Resources")
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try! fm.createDirectory(at: res, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(render(draw, px: base)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(render(draw, px: base * 2)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(render(draw, px: 1024)).write(to: res.appendingPathComponent("AppIcon.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", res.appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
print("Wrote Resources/AppIcon.icns and Resources/AppIcon.png (variant \(key))")
