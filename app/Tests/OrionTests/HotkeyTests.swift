import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Orion

final class HotkeyTests: XCTestCase {
    func defaults() -> UserDefaults {
        let name = "orion-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    // MARK: 2.2 global shortcuts

    func testDefaults() {
        XCTAssertEqual(HotkeyAction.listen.defaultShortcut.display, "⌃⌥⌘K")
        XCTAssertEqual(HotkeyAction.analyzeFile.defaultShortcut.display, "⌃⌥⌘F")
        XCTAssertEqual(HotkeyAction.listen.defaultShortcut.keyCode, UInt32(kVK_ANSI_K))
        let s = ShortcutStore(defaults: defaults())
        XCTAssertEqual(s.shortcut(.listen), HotkeyAction.listen.defaultShortcut)
    }

    func testRecordingNeedsACommandControlOrOptionKey() {
        XCTAssertNil(Shortcut.recorded(keyCode: UInt16(kVK_ANSI_K), flags: [], characters: "k"))
        XCTAssertNil(Shortcut.recorded(keyCode: UInt16(kVK_ANSI_K), flags: [.shift], characters: "K"))
        let s = Shortcut.recorded(keyCode: UInt16(kVK_ANSI_L), flags: [.command, .shift], characters: "L")
        XCTAssertEqual(s?.display, "⇧⌘L")
        XCTAssertEqual(s?.modifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(Shortcut.recorded(keyCode: UInt16(kVK_F5), flags: [.option], characters: "\u{F708}")?.display, "⌥F5")
        XCTAssertNil(Shortcut.recorded(keyCode: 200, flags: [.command], characters: "\u{F730}"))   // unnamed function key
    }

    func testStoreRemembersSetsAndClears() {
        let d = defaults()
        let s = ShortcutStore(defaults: d)
        let new = Shortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey | optionKey), key: "L")
        XCTAssertTrue(s.set(new, for: .listen))
        XCTAssertEqual(ShortcutStore(defaults: d).shortcut(.listen), new)
        s.set(nil, for: .analyzeFile)
        XCTAssertNil(ShortcutStore(defaults: d).shortcut(.analyzeFile))        // off stays off
        s.reset(.analyzeFile)
        XCTAssertEqual(ShortcutStore(defaults: d).shortcut(.analyzeFile), HotkeyAction.analyzeFile.defaultShortcut)
    }

    func testOneKeyDoesOneThing() {
        let s = ShortcutStore(defaults: defaults())
        XCTAssertFalse(s.set(HotkeyAction.analyzeFile.defaultShortcut, for: .listen))
        XCTAssertEqual(s.conflict(HotkeyAction.analyzeFile.defaultShortcut, for: .listen), .analyzeFile)
        XCTAssertEqual(s.shortcut(.listen), HotkeyAction.listen.defaultShortcut)
        // resetting to a default someone else now holds leaves it off rather than doubled
        s.set(nil, for: .analyzeFile)
        XCTAssertTrue(s.set(HotkeyAction.analyzeFile.defaultShortcut, for: .listen))
        s.reset(.analyzeFile)
        XCTAssertNil(s.shortcut(.analyzeFile))
    }

    func testMenuShortcutMirrorsTheGlobalOne() {
        let m = HotkeyAction.analyzeFile.defaultShortcut.menuShortcut
        XCTAssertEqual(m?.key, KeyEquivalentProxy.f)
        XCTAssertEqual(m?.modifiers, [.control, .option, .command])
        XCTAssertNil(Shortcut(keyCode: UInt32(kVK_F5), modifiers: UInt32(cmdKey), key: "F5").menuShortcut)
    }

    func testHotKeyIDsAreDistinct() {
        XCTAssertEqual(Set(HotkeyAction.allCases.map(\.hotKeyID)).count, HotkeyAction.allCases.count)
    }

    func testCarbonRegistrationSucceeds() {
        // an unlikely combination (⌃⌥⇧⌘F19) so the test never takes a key anyone uses
        let s = ShortcutStore(defaults: defaults())
        let all = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        s.set(Shortcut(keyCode: UInt32(kVK_F19), modifiers: all, key: "F19"), for: .listen)
        s.set(nil, for: .analyzeFile)
        HotkeyCenter.shared.apply(s)
        XCTAssertTrue(HotkeyCenter.shared.failed.isEmpty)
        HotkeyCenter.shared.unregisterAll()
    }

    func testFireRunsTheAction() {
        var ran = false
        HotkeyCenter.shared.actions[.listen] = { ran = true }
        defer { HotkeyCenter.shared.actions[.listen] = nil }
        HotkeyCenter.shared.fire(HotkeyAction.listen.hotKeyID)
        XCTAssertTrue(ran)
    }
}

import SwiftUI
enum KeyEquivalentProxy { static let f = KeyEquivalent("f") }
