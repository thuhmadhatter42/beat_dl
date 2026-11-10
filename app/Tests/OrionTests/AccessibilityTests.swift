import AppKit
import SwiftUI
import XCTest
@testable import Orion

final class AccessibilityTests: XCTestCase {
    func defaults() -> UserDefaults {
        let name = "orion-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    // MARK: 5.1 a shape per state

    /// The corners of a polygon path (nil for curves).
    func corners(_ p: Path) -> [CGPoint]? {
        var pts: [CGPoint] = []
        var curved = false
        p.forEach { e in
            switch e {
            case .move(let to), .line(let to): pts.append(to)
            case .quadCurve, .curve: curved = true
            case .closeSubpath: break
            }
        }
        return curved ? nil : pts
    }

    func testShapePerState() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(Lamp.locked.sides, 8)
        XCTAssertEqual(Lamp.unsure.sides, 3)
        XCTAssertNil(Lamp.listening.sides)
        XCTAssertEqual(corners(LampShape(lamp: .locked).path(in: box))?.count, 8)
        XCTAssertNil(corners(LampShape(lamp: .listening).path(in: box)))           // a circle
        let tri = corners(LampShape(lamp: .unsure).path(in: box))!
        XCTAssertEqual(tri.count, 3)
        // points up (y grows downward, as in SwiftUI and the flipped menu-bar image) ...
        XCTAssertEqual(tri.min(by: { $0.y < $1.y })!.x, 50, accuracy: 0.01)
        // ... and sits centred in the box
        let ys = tri.map(\.y)
        XCTAssertEqual((ys.min()! + ys.max()!) / 2, 50, accuracy: 0.01)
        // the octagon has a flat top: its two highest corners share a y
        let oct = corners(LampShape(lamp: .locked).path(in: box))!.sorted { $0.y < $1.y }
        XCTAssertEqual(oct[0].y, oct[1].y, accuracy: 0.01)
    }

    /// Alpha of the pixel at (x, y) counted from the top-left of the drawn image.
    func alpha(_ img: NSImage, _ x: Int, _ y: Int) -> CGFloat {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(img.size.width), pixelsHigh: Int(img.size.height),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(origin: .zero, size: img.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    /// The menu-bar status is the key glyph in the lamp's colour (gold with no reading).
    func testMenuBarKeyTakesTheLampColour() {
        for lamp in [Lamp.locked, .unsure, .listening] {
            let img = MenuBarImage.make(lamp, side: 40, palette: Palette())!
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(img.size.width), pixelsHigh: Int(img.size.height),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            img.draw(in: NSRect(origin: .zero, size: img.size))
            NSGraphicsContext.restoreGraphicsState()
            var hit: NSColor?
            outer: for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
                if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.95 { hit = c; break outer }
            } }
            let want = lamp.nsColor(.amber).usingColorSpace(.deviceRGB)!, got = hit!.usingColorSpace(.deviceRGB)!
            XCTAssertEqual(got.redComponent, want.redComponent, accuracy: 0.08, "\(lamp)")
            XCTAssertEqual(got.greenComponent, want.greenComponent, accuracy: 0.08, "\(lamp)")
        }
    }

    // MARK: 5.1 high contrast

    func testHighContrastIsRemembered() {
        let d = defaults()
        let s = DisplaySettings(defaults: d)
        XCTAssertFalse(s.highContrast)
        s.highContrast = true
        XCTAssertTrue(DisplaySettings(defaults: d).highContrast)
    }

    func testHighContrastRaisesDimText() {
        XCTAssertEqual(Palette(highContrast: false).contrast(0.55), 0.55)
        let hc = Palette(highContrast: true)
        XCTAssertEqual(hc.contrast(0.55), 1)
        XCTAssertEqual(hc.contrast(0.7), 1)
        XCTAssertEqual(hc.contrast(0.12), 0.3)            // placeholders: still dim, now visible
        XCTAssertEqual(hc.contrast(0.35), 0.35)
    }
}
