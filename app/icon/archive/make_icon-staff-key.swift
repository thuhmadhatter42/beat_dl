// Renders Beat Key's app icon and packs app/icon/Orion.icns (the file name stays internal).
//
//   swift app/icon/make_icon.swift                 the drawn key-staff icon
//   swift app/icon/make_icon.swift <source.png>    any square PNG masked into the same squircle
//
// The drawn icon: a music staff cut out in the shape of a key. The five staff lines are the key's
// blade; the teeth are notches cut into the lower lines; a thick barline is the shoulder; the bow
// is a ring with a treble clef inside (Apple Symbols U+1D11E). Artemis amber with a glow, on the
// Artemis chassis (the mockup's #232326 -> #131315 gradient, its sheen and noise.png grain) inside
// a macOS squircle with a thin silver bezel. Every iconset size is drawn from vectors: at 64 px
// and under the blade turns solid (staff lines would blur to mush) and grows, so 16/32 px read
// as a key; from 128 px up the five lines and the clef read as a music staff.
// CoreGraphics, not Python: no PIL on this Mac, and antialiasing comes for free.
import AppKit
import Foundation

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()           // app/icon
let noiseURL = here.deletingLastPathComponent().appendingPathComponent("Sources/Orion/Resources/noise.png")
let source: NSImage? = CommandLine.arguments.count > 1 ? NSImage(contentsOfFile: CommandLine.arguments[1]) : nil
if CommandLine.arguments.count > 1 && source == nil { fatalError("cannot read \(CommandLine.arguments[1])") }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
let amber = (CGFloat(255), CGFloat(176), CGFloat(32))

/// macOS-style squircle (superellipse, n = 5) in `r`.
func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath(), n = 5.0, steps = 720
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / n) * (c < 0 ? -1 : 1), y = pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        let pt = CGPoint(x: r.midX + CGFloat(x) * r.width / 2, y: r.midY + CGFloat(y) * r.height / 2)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

func linear(_ ctx: CGContext, _ stops: [(CGColor, CGFloat)], from a: CGPoint, to b: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: stops.map { $0.0 } as CFArray, locations: stops.map { $0.1 })!
    ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func radial(_ ctx: CGContext, _ stops: [(CGColor, CGFloat)], at c: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: stops.map { $0.0 } as CFArray, locations: stops.map { $0.1 })!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius, options: [])
}

/// Draws the icon into a `px` x `px` canvas. 1024-unit geometry, scaled.
func drawIcon(_ ctx: CGContext, px: Int) {
    let s = CGFloat(px) / 1024
    let small = px <= 64, tiny = px <= 32
    ctx.scaleBy(x: s, y: s)
    // Apple's grid: the body is 824 x 824 centred, leaving room for the shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = squircle(body)

    // drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.55))
    ctx.addPath(bodyPath); ctx.setFillColor(rgb(20, 20, 22)); ctx.fillPath()
    ctx.restoreGState()

    // silver bezel
    ctx.saveGState(); ctx.addPath(bodyPath); ctx.clip()
    linear(ctx, [(rgb(232, 232, 236), 0), (rgb(150, 150, 156), 0.35), (rgb(96, 96, 101), 0.6), (rgb(186, 186, 191), 1)],
           from: CGPoint(x: 0, y: 924), to: CGPoint(x: 0, y: 100))
    ctx.restoreGState()

    let bez: CGFloat = tiny ? 34 : 16
    let face = body.insetBy(dx: bez, dy: bez)
    let facePath = squircle(face)
    ctx.saveGState(); ctx.addPath(facePath); ctx.clip()
    if let src = source, let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.draw(cg, in: face)
    } else {
        drawChassis(ctx, face, small: small)
        drawKey(ctx, small: small)
    }
    // inner ring: the face sits a hair below the bezel
    ctx.addPath(facePath); ctx.setStrokeColor(rgb(0, 0, 0, 0.8)); ctx.setLineWidth(tiny ? 10 : 5); ctx.strokePath()
    ctx.restoreGState()
}

func drawChassis(_ ctx: CGContext, _ face: CGRect, small: Bool) {
    // chassis gradient (CSS 180deg: top -> bottom; CG y is up)
    linear(ctx, [(rgb(35, 35, 38), 0), (rgb(25, 26, 28), 0.4), (rgb(19, 19, 21), 1)],
           from: CGPoint(x: 0, y: face.maxY), to: CGPoint(x: 0, y: face.minY))
    // a faint amber haze behind the key, so the face is not flat black
    radial(ctx, [(rgb(amber.0, amber.1, amber.2, 0.08), 0), (rgb(amber.0, amber.1, amber.2, 0), 1)],
           at: CGPoint(x: 512, y: 512), radius: 440)
    // 115deg sheen band
    linear(ctx, [(rgb(255, 255, 255, 0), 0.32), (rgb(255, 255, 255, 0.05), 0.46), (rgb(255, 255, 255, 0), 0.60)],
           from: CGPoint(x: face.minX, y: face.maxY), to: CGPoint(x: face.maxX, y: face.minY))
    // top lip highlight
    linear(ctx, [(rgb(255, 255, 255, 0.07), 0), (rgb(255, 255, 255, 0), 0.05)],
           from: CGPoint(x: 0, y: face.maxY), to: CGPoint(x: 0, y: face.minY))
    // grain
    if !small, let n = NSImage(contentsOf: noiseURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.saveGState(); ctx.setAlpha(1.4)
        ctx.draw(n, in: CGRect(x: 0, y: 0, width: 128, height: 128), byTiling: true)
        ctx.restoreGState()
    }
}


/// The key's parts in the 1024 canvas (CG y up), before the tilt.
struct KeyParts {
    var solid: CGPath          // the bow ring and the shoulder barline
    var blade: CGPath          // the key silhouette: shoulder to tip, teeth cut into its lower edge
    var lines: CGPath          // five staff lines, to be clipped by `blade`
    var clef: CGPath?          // treble clef in the bow (128 px and up)
}

func keyParts(small: Bool) -> KeyParts {
    let cy: CGFloat = 512
    let bowX: CGFloat = small ? 262 : 268
    let R: CGFloat = small ? 150 : 146             // bow outer radius
    let ring: CGFloat = small ? 64 : 46            // bow ring width
    let gap: CGFloat = small ? 46 : 40             // staff line spacing
    let th: CGFloat = 17                           // staff line thickness
    let ys = (0..<5).map { cy + CGFloat(2 - $0) * gap }    // top line first
    let x0 = bowX + R - 10                         // the blade starts inside the ring
    let tip: CGFloat = small ? 900 : 892
    let yT = ys[0] + th / 2, yB = ys[4] - th / 2

    let solid = CGMutablePath()
    let mid = R - ring / 2
    solid.addPath(CGPath(ellipseIn: CGRect(x: bowX - mid, y: cy - mid, width: 2 * mid, height: 2 * mid), transform: nil)
        .copy(strokingWithWidth: ring, lineCap: .butt, lineJoin: .miter, miterLimit: 10))
    // the shoulder: a thick barline standing a little proud of the blade
    let barW: CGFloat = small ? 30 : 28, proud: CGFloat = small ? 22 : 30
    solid.addRect(CGRect(x: x0, y: yB - proud, width: barW, height: yT - yB + 2 * proud))

    // silhouette: flat top, bevelled tip, teeth cut up into the lower edge (right to left)
    let b = CGMutablePath()
    b.move(to: CGPoint(x: x0, y: yT))
    b.addLine(to: CGPoint(x: tip - 70, y: yT))
    b.addLine(to: CGPoint(x: tip, y: cy + gap * 0.5))         // bevel down to the point
    b.addLine(to: CGPoint(x: tip, y: cy - gap * 0.9))
    // teeth: (x offset back from the tip, how deep the cut reaches up from yB)
    let d1 = gap * 1.35, d2 = gap * 0.6
    let profile: [(CGFloat, CGFloat)] = small
        ? [(30, 0), (70, d1 * 0.9), (110, 0), (150, 0), (190, d1), (230, 0), (290, 0)]
        : [(24, 0), (58, d1), (92, 0), (126, d2), (150, d2), (180, 0), (214, 0), (250, d1), (286, 0), (330, 0)]
    for (dx, depth) in profile { b.addLine(to: CGPoint(x: tip - dx, y: yB + depth)) }
    b.addLine(to: CGPoint(x: x0, y: yB))
    b.closeSubpath()

    let lines = CGMutablePath()
    if small {
        lines.addRect(CGRect(x: x0, y: yB, width: tip - x0, height: yT - yB))   // solid blade
    } else {
        for y in ys { lines.addRect(CGRect(x: x0, y: y - th / 2, width: tip - x0, height: th)) }
    }

    var clef: CGPath?
    if !small, let font = NSFont(name: "Apple Symbols", size: 300) {
        var u = Array("\u{1D11E}".utf16); var g = [CGGlyph](repeating: 0, count: u.count)
        if CTFontGetGlyphsForCharacters(font as CTFont, &u, &g, u.count),
           let gp = CTFontCreatePathForGlyph(font as CTFont, g[0], nil) {
            let bb = gp.boundingBoxOfPath
            let k = (R - ring) * 2 * 0.84 / bb.height                    // fills the bow's hole
            var t = CGAffineTransform(translationX: bowX, y: cy).scaledBy(x: k, y: k)
                .translatedBy(x: -bb.midX, y: -bb.midY)
            clef = gp.copy(using: &t)
        }
    }
    return KeyParts(solid: solid, blade: b, lines: lines, clef: clef)
}

func drawKey(_ ctx: CGContext, small: Bool) {
    let parts = keyParts(small: small)
    // a slight lean, up to the right, centred on the figure
    let tilt: CGFloat = 0.30                                  // about 17 degrees
    // centre the leaning figure on the face and size it to the grid (bigger when tiny)
    let all = CGMutablePath(); all.addPath(parts.solid); all.addPath(parts.blade)
    var rot = CGAffineTransform(rotationAngle: tilt)
    let bb = all.copy(using: &rot)!.boundingBoxOfPath
    let k = (small ? 760 : 700) / max(bb.width, bb.height)
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 512); ctx.scaleBy(x: k, y: k)
    ctx.translateBy(x: -bb.midX, y: -bb.midY); ctx.rotate(by: tilt)

    // the glow under everything
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: small ? 16 : 30, color: rgb(amber.0, amber.1, amber.2, 0.55))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    drawAmber(ctx, parts)
    ctx.endTransparencyLayer()
    ctx.restoreGState()
    ctx.restoreGState()
}

/// Fills the key's parts with the lit-cap amber gradient (lighter at the top).
func drawAmber(_ ctx: CGContext, _ k: KeyParts) {
    let stops: [(CGColor, CGFloat)] = [(rgb(255, 228, 166), 0), (rgb(255, 192, 70), 0.38),
                                       (rgb(amber.0, amber.1, amber.2), 0.62), (rgb(214, 136, 18), 1)]
    func fill(_ build: () -> Void) {
        ctx.saveGState(); build(); ctx.clip()
        linear(ctx, stops, from: CGPoint(x: 0, y: 700), to: CGPoint(x: 0, y: 330))
        ctx.restoreGState()
    }
    fill { ctx.addPath(k.solid) }
    // the staff, cut out in the key's shape
    ctx.saveGState()
    ctx.addPath(k.blade); ctx.clip()
    fill { ctx.addPath(k.lines) }
    ctx.restoreGState()
    if let c = k.clef { fill { ctx.addPath(c) } }
}

func render(_ px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    drawIcon(ctx, px: px)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orion-\(getpid()).iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(1024).write(to: here.appendingPathComponent("icon-1024.png"))
try render(32).write(to: here.appendingPathComponent("icon-32.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", here.appendingPathComponent("Orion.icns").path]
try p.run(); p.waitUntilExit()
guard p.terminationStatus == 0 else { fatalError("iconutil failed") }
try? fm.removeItem(at: iconset)
print("wrote \(here.path)/Orion.icns, icon-1024.png, icon-32.png")
