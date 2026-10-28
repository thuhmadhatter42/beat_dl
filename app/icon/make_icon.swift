// Renders Orion's app icon and packs app/icon/Orion.icns.
//
//   swift app/icon/make_icon.swift                 the drawn constellation icon
//   swift app/icon/make_icon.swift <source.png>    any square PNG (e.g. a marble Orion render
//                                                  like Artemis's) masked into the same squircle
//
// The drawn icon: Orion's seven bright stars (Betelgeuse + Bellatrix shoulders, the three belt
// stars, Saiph + Rigel feet) in Artemis amber with a glow, on the Artemis chassis (the mockup's
// #232326 -> #131315 gradient, its sheen and noise.png grain) inside a macOS squircle with a thin
// silver bezel. Every iconset size is drawn from vectors, not downscaled: at 64 px and under the
// stars grow and the faint sky and lines drop out, so 16/32 px still read as the constellation.
// CoreGraphics, not Python: no PIL on this Mac, and Helvetica Neue / antialiasing come for free.
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

// The seven stars: (x, y) in degrees from the figure's centre (east left, north up; x stretched
// 1.25 so the figure fills the squircle), visual magnitude.
let stars: [(name: String, x: CGFloat, y: CGFloat, mag: CGFloat)] = [
    ("Betelgeuse", -5.1, 7.4, 0.5), ("Bellatrix", 2.4, 6.35, 1.64),
    ("Alnitak", -1.5, -1.94, 1.77), ("Alnilam", -0.35, -1.2, 1.69), ("Mintaka", 0.7, -0.3, 2.23),
    ("Saiph", -3.2, -9.67, 2.09), ("Rigel", 5.1, -8.2, 0.13),
]
let lines = [(0, 1), (0, 2), (1, 4), (2, 3), (3, 4), (2, 5), (4, 6)]

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
        drawChassis(ctx, face, small: small, tiny: tiny)
    }
    // inner ring: the face sits a hair below the bezel
    ctx.addPath(facePath); ctx.setStrokeColor(rgb(0, 0, 0, 0.8)); ctx.setLineWidth(tiny ? 10 : 5); ctx.strokePath()
    ctx.restoreGState()
}

func drawChassis(_ ctx: CGContext, _ face: CGRect, small: Bool, tiny: Bool) {
    // chassis gradient (CSS 180deg: top -> bottom; CG y is up)
    linear(ctx, [(rgb(35, 35, 38), 0), (rgb(25, 26, 28), 0.4), (rgb(19, 19, 21), 1)],
           from: CGPoint(x: 0, y: face.maxY), to: CGPoint(x: 0, y: face.minY))
    // a faint amber haze behind the figure, so the face is not flat black
    radial(ctx, [(rgb(amber.0, amber.1, amber.2, 0.07), 0), (rgb(amber.0, amber.1, amber.2, 0), 1)],
           at: CGPoint(x: 512, y: 512), radius: 420)
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

    // star positions in the 1024 canvas
    let k: CGFloat = 30, xs: CGFloat = 1.25, cy: CGFloat = 512 + 1.13 * k
    let pts = stars.map { CGPoint(x: 512 + $0.x * k * xs, y: cy + $0.y * k) }

    // faint field stars (fixed seed), only where there are pixels for them
    if !small {
        var seed: UInt64 = 0x0819_2026
        func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
        for _ in 0..<70 {
            let p = CGPoint(x: face.minX + rnd() * face.width, y: face.minY + rnd() * face.height)
            let r = 1.2 + rnd() * 2.2, a = 0.10 + rnd() * 0.22
            ctx.setFillColor(rgb(235, 235, 240, a)); ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        }
    }
    // the stick figure
    if !tiny {
        ctx.setStrokeColor(rgb(amber.0, amber.1, amber.2, small ? 0.35 : 0.28))
        ctx.setLineWidth(small ? 14 : 5); ctx.setLineCap(.round)
        for (a, b) in lines { ctx.move(to: pts[a]); ctx.addLine(to: pts[b]) }
        ctx.strokePath()
    }
    // the stars: glow, amber disc, hot core. Brighter star = bigger. Small sizes boost the disc.
    for (i, st) in stars.enumerated() {
        let p = pts[i]
        let bright = (2.6 - st.mag) / 2.5                         // 0 ... 1
        var core = 13 + 13 * bright
        if small { core *= tiny ? 2.6 : 1.9 }
        let glow = core * (tiny ? 2.2 : 4.2)
        radial(ctx, [(rgb(amber.0, amber.1, amber.2, 0.55), 0), (rgb(amber.0, amber.1, amber.2, 0.18), 0.35),
                     (rgb(amber.0, amber.1, amber.2, 0), 1)], at: p, radius: glow)
        if !small {   // four-point diffraction glint on the two brightest
            if st.mag < 0.6 {
                ctx.saveGState()
                ctx.setStrokeColor(rgb(255, 214, 140, 0.55)); ctx.setLineWidth(3); ctx.setLineCap(.round)
                let L = core * 2.8
                ctx.move(to: CGPoint(x: p.x - L, y: p.y)); ctx.addLine(to: CGPoint(x: p.x + L, y: p.y))
                ctx.move(to: CGPoint(x: p.x, y: p.y - L)); ctx.addLine(to: CGPoint(x: p.x, y: p.y + L))
                ctx.strokePath(); ctx.restoreGState()
            }
        }
        radial(ctx, [(rgb(255, 246, 222), 0), (rgb(255, 206, 110), 0.45), (rgb(amber.0, amber.1, amber.2), 0.8),
                     (rgb(amber.0, amber.1, amber.2, 0), 1)], at: p, radius: core)
    }
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
