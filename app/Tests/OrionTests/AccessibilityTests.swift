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

    override func tearDown() { Theme.highContrast = false }

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

    func testMenuBarTriangleIsDrawnPointUp() {
        let img = MenuBarImage.make(.unsure, side: 40)!
        // bottom corners filled, top corners empty
        XCTAssertGreaterThan(alpha(img, 6, 31), 0.5)
        XCTAssertLessThan(alpha(img, 3, 3), 0.1)
        XCTAssertLessThan(alpha(img, 36, 3), 0.1)
        XCTAssertGreaterThan(alpha(img, 20, 6), 0.5)         // the apex, top centre
    }

    func testMenuBarShapesDiffer() {
        // the octagon is inscribed in the circle: just inside the circle on the 45° line, past
        // the octagon's diagonal edge, only the circle is filled
        let circle = MenuBarImage.make(.listening, side: 40)!
        let oct = MenuBarImage.make(.locked, side: 40)!
        XCTAssertLessThan(alpha(circle, 1, 1), 0.1)
        XCTAssertGreaterThan(alpha(circle, 33, 6), 0.5)
        XCTAssertLessThan(alpha(oct, 33, 6), 0.3)
        XCTAssertGreaterThan(alpha(oct, 20, 4), 0.5)        // both filled near the top centre
        XCTAssertGreaterThan(alpha(circle, 20, 4), 0.5)
    }

    // MARK: 5.1 high contrast

    func testHighContrastIsRemembered() {
        let d = defaults()
        let s = DisplaySettings(defaults: d)
        XCTAssertFalse(s.highContrast)
        XCTAssertFalse(Theme.highContrast)
        s.highContrast = true
        XCTAssertTrue(Theme.highContrast)
        XCTAssertTrue(DisplaySettings(defaults: d).highContrast)
    }

    func testHighContrastRaisesDimText() {
        Theme.highContrast = false
        XCTAssertEqual(Theme.contrast(0.55), 0.55)
        Theme.highContrast = true
        XCTAssertEqual(Theme.contrast(0.55), 1)
        XCTAssertEqual(Theme.contrast(0.7), 1)
        XCTAssertEqual(Theme.contrast(0.12), 0.3)            // placeholders: still dim, now visible
        XCTAssertEqual(Theme.contrast(0.35), 0.35)
    }
}
