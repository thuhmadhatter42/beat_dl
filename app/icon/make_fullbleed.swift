// Builds icon-fullbleed-1024.png (opaque square, no transparency) from source-golden-key.png.
// macOS 26+ masks the corners itself, so the art must fill the whole square.
// The key is nearly as wide as the plate, so the plate interior (just inside the bevel rim) is drawn
// at scale S, centred on the key, over a vertical gradient sampled from the plate's own metal; the
// crop edge is feathered so no seam shows. Run: swift app/icon/make_fullbleed.swift
import AppKit
let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let src = NSBitmapImageRep(data: try! Data(contentsOf: dir.appendingPathComponent("source-golden-key.png")))!.cgImage!
let N = 1024, S = 0.86, half = 490.0, feather = 110.0
let crop = CGRect(x: 635 - half, y: 607 - half, width: 2 * half, height: 2 * half)   // source px, y from top
let piece = src.cropping(to: crop)!
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

// average colour of a source band inside the plate (away from the key) for the gradient ends
func avg(_ r: CGRect) -> [CGFloat] {
    let c = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(src.cropping(to: r)!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    let p = c.data!.assumingMemoryBound(to: UInt8.self)
    return [CGFloat(p[0]) / 255, CGFloat(p[1]) / 255, CGFloat(p[2]) / 255]
}
let top = avg(CGRect(x: 300, y: 130, width: 600, height: 60)).map { $0 * 0.72 }
let bot = avg(CGRect(x: 300, y: 1020, width: 600, height: 60)).map { $0 * 0.72 }

let ctx = CGContext(data: nil, width: N, height: N, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let grad = CGGradient(colorSpace: cs, colorComponents: top + [1] + bot + [1], locations: [0, 1], count: 2)!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(N)), end: .zero, options: [])

// feathered mask for the crop (grey image: 255 inside, ramps to 0 at the crop edge)
let w = Int(2 * half * S) // output size of the crop
var m = [UInt8](repeating: 0, count: w * w)
let R = 230.0   // corner radius (source px) that keeps the rim's corner arcs out of the crop
for y in 0..<w { for x in 0..<w {
    let px = Double(x) / S, py = Double(y) / S, c = 2 * half
    // signed distance (inside positive) to a rounded rectangle
    let qx = abs(px - c / 2) - (c / 2 - R), qy = abs(py - c / 2) - (c / 2 - R)
    let out = (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot() + min(max(qx, qy), 0) - R
    let d = min(max(-out, 0), feather) / feather
    m[y * w + x] = UInt8((d * d * (3 - 2 * d)) * 255)
} }
let mask = CGImage(maskWidth: w, height: w, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                   provider: CGDataProvider(data: Data(m) as CFData)!, decode: [1, 0], shouldInterpolate: true)!
let o = (N - w) / 2
let rect = CGRect(x: o, y: o, width: w, height: w)
ctx.saveGState()
ctx.clip(to: rect, mask: mask)
ctx.interpolationQuality = .high
ctx.draw(piece, in: rect)
ctx.restoreGState()
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: dir.appendingPathComponent("icon-fullbleed-1024.png"))
