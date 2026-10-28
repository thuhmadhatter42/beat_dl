// Renders the DMG window background: app/dmg/background.png (600 x 380) and background@2x.png.
//   swift app/dmg/make_background.swift
// build.sh joins the two into one HiDPI background.tiff (tiffutil -cathidpicheck).
//
// The Artemis chassis (mockup gradient, sheen, noise.png grain, four screws), "Drag Orion to
// Applications" in Helvetica Neue, an amber arrow from the app to the Applications link, and two
// mid-grey label strips where Finder draws the icon names: Finder draws them black in Light mode
// and white in Dark mode, and the strip keeps both readable on a dark plate.
// Layout constants are shared with build.sh: icons centred at (160,190) and (440,190), 112 px.
import AppKit
import Foundation

let W: CGFloat = 600, H: CGFloat = 380
let appX: CGFloat = 160, linkX: CGFloat = 440, iconY: CGFloat = 190      // Finder coords (top-left)
let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let noiseURL = here.deletingLastPathComponent().appendingPathComponent("Sources/Orion/Resources/noise.png")

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
func grad(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map { $0.0 } as CFArray,
               locations: stops.map { $0.1 })!
}

func draw(_ ctx: CGContext) {
    // Work in top-left coordinates like Finder.
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
    let all = CGRect(x: 0, y: 0, width: W, height: H)
    ctx.drawLinearGradient(grad([(rgb(35, 35, 38), 0), (rgb(25, 26, 28), 0.4), (rgb(19, 19, 21), 1)]),
                           start: .zero, end: CGPoint(x: 0, y: H), options: [])
    ctx.drawLinearGradient(grad([(rgb(255, 255, 255, 0), 0.32), (rgb(255, 255, 255, 0.05), 0.46), (rgb(255, 255, 255, 0), 0.60)]),
                           start: .zero, end: CGPoint(x: W, y: H * 0.9), options: [])
    ctx.drawLinearGradient(grad([(rgb(255, 255, 255, 0.06), 0), (rgb(255, 255, 255, 0), 1)]),
                           start: .zero, end: CGPoint(x: 0, y: 16), options: [])
    if let n = NSImage(contentsOf: noiseURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.saveGState(); ctx.clip(to: all)
        ctx.draw(n, in: CGRect(x: 0, y: 0, width: 128, height: 128), byTiling: true)
        ctx.restoreGState()
    }

    // screws
    for (x, y) in [(14.0, 14.0), (W - 14, 14.0), (14.0, H - 14), (W - 14, H - 14)] {
        let c = CGPoint(x: x, y: y), r: CGFloat = 5
        ctx.setFillColor(rgb(0, 0, 0, 0.55)); ctx.fillEllipse(in: CGRect(x: x - r - 2, y: y - r - 2, width: 2 * r + 4, height: 2 * r + 4))
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)); ctx.clip()
        ctx.drawRadialGradient(grad([(rgb(220, 220, 224), 0), (rgb(133, 133, 138), 0.45), (rgb(46, 46, 49), 1)]),
                               startCenter: CGPoint(x: x - 1.6, y: y - 2), startRadius: 0, endCenter: c, endRadius: r * 1.3, options: [])
        ctx.restoreGState()
        ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.rotate(by: 32 * .pi / 180)
        ctx.setStrokeColor(rgb(0, 0, 0, 0.75)); ctx.setLineWidth(1.1)
        ctx.move(to: CGPoint(x: -r * 0.76, y: 0)); ctx.addLine(to: CGPoint(x: r * 0.76, y: 0)); ctx.strokePath()
        ctx.restoreGState()
    }

    // title
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let title = NSAttributedString(string: "Drag Orion to Applications", attributes: [
        .font: NSFont(name: "HelveticaNeue-Bold", size: 19)!, .kern: 0.6,
        .foregroundColor: NSColor(srgbRed: 238 / 255, green: 238 / 255, blue: 242 / 255, alpha: 0.9),
        .paragraphStyle: para])
    let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
    title.draw(in: CGRect(x: 0, y: 52, width: W, height: 30))
    NSGraphicsContext.restoreGraphicsState()
    // hairline under the title, Artemis-style engraving
    ctx.setFillColor(rgb(0, 0, 0, 0.6)); ctx.fill(CGRect(x: 200, y: 92, width: 200, height: 1))
    ctx.setFillColor(rgb(255, 255, 255, 0.06)); ctx.fill(CGRect(x: 200, y: 93, width: 200, height: 1))

    // icon wells: a soft recess behind each icon
    for x in [appX, linkX] {
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: x - 78, y: iconY - 78, width: 156, height: 156)); ctx.clip()
        ctx.drawRadialGradient(grad([(rgb(0, 0, 0, 0.35), 0), (rgb(0, 0, 0, 0), 1)]),
                               startCenter: CGPoint(x: x, y: iconY), startRadius: 0,
                               endCenter: CGPoint(x: x, y: iconY), endRadius: 78, options: [])
        ctx.restoreGState()
    }

    // label strips (Finder draws the names centred about 72 px under the icon centre)
    for (x, w) in [(appX, 96.0), (linkX, 120.0)] {
        let r = CGRect(x: x - w / 2, y: iconY + 62, width: w, height: 22)
        let p = CGPath(roundedRect: r, cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.addPath(p); ctx.setFillColor(rgb(122, 122, 128)); ctx.fillPath()
        ctx.saveGState(); ctx.addPath(p); ctx.clip()
        ctx.drawLinearGradient(grad([(rgb(255, 255, 255, 0.18), 0), (rgb(255, 255, 255, 0), 0.5), (rgb(0, 0, 0, 0.12), 1)]),
                               start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.maxY), options: [])
        ctx.restoreGState()
        ctx.addPath(p); ctx.setStrokeColor(rgb(0, 0, 0, 0.7)); ctx.setLineWidth(1); ctx.strokePath()
    }

    // amber arrow with glow
    let a0 = appX + 78, a1 = linkX - 78
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: a0, y: iconY)); arrow.addLine(to: CGPoint(x: a1 - 4, y: iconY))
    let head = CGMutablePath()
    head.move(to: CGPoint(x: a1, y: iconY))
    head.addLine(to: CGPoint(x: a1 - 18, y: iconY - 11)); head.addLine(to: CGPoint(x: a1 - 18, y: iconY + 11)); head.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 10, color: rgb(255, 176, 32, 0.6))
    ctx.addPath(arrow); ctx.setStrokeColor(rgb(255, 176, 32)); ctx.setLineWidth(4); ctx.setLineCap(.round); ctx.strokePath()
    ctx.addPath(head); ctx.setFillColor(rgb(255, 176, 32)); ctx.fillPath()
    ctx.restoreGState()
}

func render(scale: Int, to url: URL) throws {
    let w = Int(W) * scale, h = Int(H) * scale
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: W, height: H)                     // 72 dpi at 1x, 144 dpi at 2x
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

try render(scale: 1, to: here.appendingPathComponent("background.png"))
try render(scale: 2, to: here.appendingPathComponent("background@2x.png"))
print("wrote \(here.path)/background.png, background@2x.png")
