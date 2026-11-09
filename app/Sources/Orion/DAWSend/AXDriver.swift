import AppKit
import ApplicationServices

// Accessibility (AX) automation for DAWs with no outside tempo/key API: Pro Tools (PTSL has no
// setter), Logic Pro, Studio One / Studio Pro. Plan §4.2. Elements are found by role + title /
// description / help / a neighbouring label, never by screen position. Every wait times out.
// The tree is behind `AXNode` so the path-finding is unit-tested against a fake tree.

/// One element of an app's accessibility tree.
protocol AXNode: AnyObject {
    var role: String? { get }
    var subrole: String? { get }
    var title: String? { get }
    var desc: String? { get }
    var help: String? { get }
    var identifier: String? { get }
    /// The value as text ("120.0000", "1", "C major"), nil if none.
    var valueText: String? { get }
    var children: [AXNode] { get }
    var parent: AXNode? { get }
    var isValueSettable: Bool { get }
    /// Windows (apps only); dialogs and sheets included.
    var windows: [AXNode] { get }
    var focusedWindow: AXNode? { get }
    var menuBar: AXNode? { get }
    var frame: CGRect? { get }
    /// Whether the element has keyboard focus; nil = it does not say.
    var isFocused: Bool? { get }
    func setValue(_ text: String) -> Bool
    func setBool(_ attribute: String, _ on: Bool) -> Bool
    @discardableResult func perform(_ action: String) -> Bool
}

extension AXNode {
    var allText: [String] { [title, desc, identifier, valueText].compactMap { $0 } }
}

/// Text compare that survives "…" vs "...", ♯/♭, case, trailing colons, doubled spaces.
enum AXText {
    static func norm(_ s: String) -> String {
        var t = s.lowercased()
            .replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix(":") { t.removeLast(); t = t.trimmingCharacters(in: .whitespaces) }
        return t.split(whereSeparator: { $0 == " " || $0 == "\u{a0}" }).joined(separator: " ")
    }
    static func same(_ a: String?, _ b: String) -> Bool { a.map { norm($0) == norm(b) } ?? false }
}

/// What to look for: roles (empty = any) and labels matched exactly (normalised) against
/// title / description / identifier, or as a substring of the help text.
struct AXMatch: CustomStringConvertible {
    var roles: Set<String> = []
    var labels: [String] = []
    var helps: [String] = []

    static func role(_ r: String...) -> AXMatch { AXMatch(roles: Set(r)) }
    func labelled(_ l: String...) -> AXMatch { var m = self; m.labels += l; return m }
    func helped(_ h: String...) -> AXMatch { var m = self; m.helps += h; return m }

    func hit(_ n: AXNode) -> Bool {
        if !roles.isEmpty { guard let r = n.role, roles.contains(r) else { return false } }
        if labels.isEmpty && helps.isEmpty { return true }
        for l in labels where [n.title, n.desc, n.identifier].contains(where: { AXText.same($0, l) }) { return true }
        if let h = n.help.map(AXText.norm) { for s in helps where h.contains(AXText.norm(s)) { return true } }
        return false
    }

    var description: String {
        let what = (labels + helps).first.map { "\"\($0)\"" } ?? "element"
        return roles.isEmpty ? what : "\(what) (\(roles.sorted().joined(separator: "/")))"
    }
}

enum AXRole {
    static let fields: Set<String> = ["AXTextField", "AXComboBox", "AXSlider", "AXIncrementor", "AXValueIndicator", "AXStaticText"]
    static let editable: Set<String> = ["AXTextField", "AXComboBox", "AXSlider", "AXIncrementor", "AXValueIndicator"]
}

/// Searches. Breadth-first with a node budget so a huge tree (a mixer) cannot stall a send.
enum AXFind {
    static let budget = 6000

    static func first(_ m: AXMatch, in root: AXNode, budget: Int = AXFind.budget) -> AXNode? {
        all(m, in: root, limit: 1, budget: budget).first
    }

    static func all(_ m: AXMatch, in root: AXNode, limit: Int = .max, budget: Int = AXFind.budget) -> [AXNode] {
        var out: [AXNode] = [], queue: [AXNode] = [root], seen = 0
        while !queue.isEmpty && seen < budget {
            let n = queue.removeFirst(); seen += 1
            if m.hit(n) { out.append(n); if out.count >= limit { break } }
            queue += n.children
        }
        return out
    }

    /// A value field for `label`: one whose own title/description is the label, else the first
    /// editable element right after a static-text label in the same container (Pro Tools style:
    /// "BPM:" then the field).
    /// The neighbour search never walks past another static-text label, so a "Location:" whose
    /// own field is not exposed can never hand back the "BPM:" field after it. `accept` refuses
    /// a candidate (a Location field that holds a tempo number).
    static func field(_ labels: [String], in root: AXNode, accept: (AXNode) -> Bool = { _ in true }) -> AXNode? {
        if let own = all(AXMatch(roles: AXRole.editable, labels: labels), in: root).first(where: accept) { return own }
        var queue: [AXNode] = [root], seen = 0
        while !queue.isEmpty && seen < budget {
            let n = queue.removeFirst(); seen += 1
            let kids = n.children
            for (i, k) in kids.enumerated() where k.role == "AXStaticText" && labels.contains(where: { l in k.allText.contains { AXText.same($0, l) } }) {
                for next in kids.dropFirst(i + 1).prefix(3) {
                    if next.role == "AXStaticText" { break }                  // the next label: stop
                    var hit: AXNode?
                    if let r = next.role, AXRole.editable.contains(r) { hit = next }
                    else { hit = first(AXMatch(roles: AXRole.editable), in: next, budget: 200) }
                    if let h = hit { if accept(h) { return h }; break }      // refused: never take a later one
                }
            }
            queue += kids
        }
        return nil
    }

    /// An element showing one of `texts` (a list row, a radio, a menu item); rows win over the
    /// static text inside them.
    static func choice(_ texts: [String], in root: AXNode, roles: Set<String> = ["AXRow", "AXCell", "AXStaticText", "AXButton", "AXRadioButton", "AXMenuItem", "AXCheckBox"]) -> AXNode? {
        for t in texts {   // texts are in preference order
            var queue: [AXNode] = [root], seen = 0
            while !queue.isEmpty && seen < budget {
                let n = queue.removeFirst(); seen += 1
                if let r = n.role, roles.contains(r), n.allText.contains(where: { AXText.same($0, t) }) { return n }
                queue += n.children
            }
        }
        return nil
    }

    /// The window/sheet/dialog with one of these titles (sheets hang off windows).
    static func window(_ titles: [String], in app: AXNode) -> AXNode? {
        for w in app.windows {
            if titles.contains(where: { AXText.same(w.title, $0) }) { return w }
            for s in w.children where s.role == "AXSheet" || s.role == "AXWindow" {
                if titles.isEmpty || titles.contains(where: { AXText.same(s.title, $0) }) { return s }
            }
        }
        return nil
    }

    /// A menu item by path, each level a list of acceptable titles.
    static func menuItem(_ path: [[String]], in app: AXNode) -> AXNode? {
        guard let bar = app.menuBar, !path.isEmpty else { return nil }
        var level: [AXNode] = bar.children
        var found: AXNode?
        for (depth, names) in path.enumerated() {
            guard let hit = level.first(where: { n in names.contains { AXText.same(n.title, $0) } }) else { return nil }
            found = hit
            if depth < path.count - 1 {
                // AXMenuBarItem / AXMenuItem → AXMenu → items
                level = hit.children.flatMap { $0.role == "AXMenu" ? $0.children : [$0] }
            }
        }
        return found
    }
}

/// Keystrokes into one app (CGEvent posted to its pid, so nothing else gets them).
protocol AXKeys {
    func type(_ text: String, pid: pid_t)
    func key(_ code: CGKeyCode, flags: CGEventFlags, pid: pid_t)
    func doubleClick(_ at: CGPoint)
}

enum KeyCode {
    static let `return`: CGKeyCode = 36, tab: CGKeyCode = 48, escape: CGKeyCode = 53, a: CGKeyCode = 0
}

struct CGKeys: AXKeys {
    func type(_ text: String, pid: pid_t) {
        let src = CGEventSource(stateID: .hidSystemState)
        for ch in text.utf16 {
            var c = ch
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down) else { continue }
                e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
                e.postToPid(pid)
            }
            usleep(8000)
        }
    }

    func key(_ code: CGKeyCode, flags: CGEventFlags = [], pid: pid_t) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.postToPid(pid)
        }
        usleep(15000)
    }

    /// Double-click at an element's own centre (Logic's LCD tempo opens for typing on a double-click).
    func doubleClick(_ at: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        for clicks in [1, 2] {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: at, mouseButton: .left) else { continue }
                e.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
                e.post(tap: .cghidEventTap)
            }
        }
        usleep(150_000)
    }
}

/// Accessibility permission. The system prompt is shown at most once per launch.
enum AXTrust {
    private static var prompted = false
    static func isTrusted(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        guard prompt, !prompted else { return false }
        prompted = true
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Not trusted yet: shows the system prompt the first time; true if it was shown just now.
    static func promptOnce() -> Bool {
        guard !prompted else { return false }
        prompted = true
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        return true
    }
}

/// Accessibility is not allowed yet. Nothing was sent; the controller stays quiet if the
/// system prompt was just shown, else says the one line.
struct AXPermissionPending: Error, CustomStringConvertible {
    let promptShown: Bool
    var description: String { "Allow Beat Key in Accessibility, then send again" }
}

struct AXFailure: Error, CustomStringConvertible {
    let description: String
    init(_ s: String) { description = s }
}

/// What a value field must be, checked before typing and on the read-back after.
enum AXFieldKind: Equatable {
    case any
    /// A bars|beats|ticks location: never a field that holds a plain number (a tempo).
    case time
    /// A BPM: the read-back must parse within 0.01 of the value, and lie in 20…999.
    case tempo(Double)

    static let tempoRange: ClosedRange<Double> = 20...999
    static let tempoLabels = ["BPM", "Tempo", "Manual Tempo"]

    /// "120.0000", " 88.12 BPM" -> the number; "1|1|000" -> nil.
    static func number(_ s: String?) -> Double? {
        guard let s, !s.contains("|"), !s.contains(":") else { return nil }
        let t = s.trimmingCharacters(in: .whitespaces)
        let lead = t.prefix { $0.isNumber || $0 == "." }
        guard !lead.isEmpty, t.dropFirst(lead.count).allSatisfy({ !$0.isNumber }) else { return nil }
        return Double(lead)
    }
    static func digits(_ s: String) -> String { String(s.filter(\.isNumber)) }

    /// Before filling: is this the right kind of field?
    func accepts(_ n: AXNode) -> Bool {
        switch self {
        case .any: return true
        case .time:
            if AXFieldKind.number(n.valueText) != nil { return false }      // holds a tempo
            return ![n.title, n.desc].contains { t in AXFieldKind.tempoLabels.contains { AXText.same(t, $0) } }
        case .tempo:
            return !(n.valueText?.contains("|") ?? false)
        }
    }

    /// After filling: did the field take exactly this? nil = fine, else why not.
    func refusal(_ got: String?, typed: String) -> String? {
        switch self {
        case .any: return nil
        case .time:
            guard let g = got else { return nil }                            // field does not report a value
            if AXFieldKind.number(g) != nil { return "reads \(g), a number, not a location" }
            return AXFieldKind.digits(g) == AXFieldKind.digits(typed) ? nil : "reads \(g), not \(typed)"
        case .tempo(let want):
            guard let v = AXFieldKind.number(got) else { return "gave no tempo back (\(got ?? "nothing"))" }
            guard AXFieldKind.tempoRange.contains(v) else { return "reads \(v), outside 20-999 BPM" }
            return abs(v - want) <= 0.01 ? nil : String(format: "reads %.2f, not %.2f", v, want)
        }
    }
}

/// One step of a DAW route.
enum AXStep: CustomStringConvertible {
    case menu([[String]])                         // press a menu item by path
    case press(AXMatch)                           // press something in the scope (or any window)
    case window([String])                         // wait for a window/dialog; it becomes the scope
    case set([String], String, AXFieldKind = .any) // value field by label, checked
    case choose([String])                         // pick a row / radio / item showing one of these
    case check([String], Bool)                    // checkbox to a state
    case popup(AXMatch, [String])                 // open a pop-up, pick an item
    case typeInto(AXMatch, String)                // double-click the element, type, Return (Logic LCD)
    indirect case optional(AXStep)                         // not finding it is fine
    case waitClosed                               // the scope window goes away

    var description: String {
        switch self {
        case .menu(let p): return "menu " + p.compactMap(\.first).joined(separator: " › ")
        case .press(let m): return "button \(m)"
        case .window(let t): return "window \"\(t.first ?? "")\""
        case .set(let l, _, _): return "field \"\(l.first ?? "")\""
        case .choose(let t): return "item \"\(t.first ?? "")\""
        case .check(let l, _): return "checkbox \"\(l.first ?? "")\""
        case .popup(let m, _): return "pop-up \(m)"
        case .typeInto(let m, _): return "display \(m)"
        case .optional(let s): return s.description
        case .waitClosed: return "dialog closing"
        }
    }
}

/// Runs steps against one app. `timeout` bounds each wait; the whole route is bounded by the
/// steps' count times that.
final class AXRunner {
    let app: AXNode
    let pid: pid_t
    let keys: AXKeys
    let timeout: TimeInterval
    let poll: TimeInterval
    private(set) var scope: AXNode
    let start: AXNode
    private(set) var log: [String] = []

    init(app: AXNode, pid: pid_t, keys: AXKeys = CGKeys(), timeout: TimeInterval = 3, poll: TimeInterval = 0.1) {
        self.app = app; self.pid = pid; self.keys = keys; self.timeout = timeout; self.poll = poll
        scope = app.focusedWindow ?? app
        start = scope
    }

    /// Every step's outcome goes to the run's log and to beatkey.log (values only, no names).
    func note(_ line: String) {
        log.append(line)
        AppLog.log("daw send: " + line)
    }

    /// The dialog is still on screen.
    func isOpen(_ w: AXNode) -> Bool {
        app.windows.contains(where: { $0 === w || ($0.title != nil && $0.title == w.title && $0.role == w.role) })
    }

    /// A route failed: if it opened a dialog, press its Cancel (else Escape) so the DAW is never
    /// left inside it. Returns false if the dialog is still open after that.
    @discardableResult func cancelDialog() -> Bool {
        let w = scope
        guard w !== start, isOpen(w) else { return true }
        if let c = AXFind.first(AXMatch(roles: ["AXButton"], labels: ["Cancel"]), in: w), c.perform(kAXPressAction) {
            note("pressed Cancel in \"\(w.title ?? "dialog")\"")
        } else {
            keys.key(KeyCode.escape, flags: [], pid: pid)
            note("pressed Escape in \"\(w.title ?? "dialog")\"")
        }
        if wait({ isOpen(w) ? nil : true }) != nil { note("dialog cancelled"); scope = app.focusedWindow ?? app; return true }
        keys.key(KeyCode.escape, flags: [], pid: pid)
        note("dialog still open after Cancel; pressed Escape")
        if wait({ isOpen(w) ? nil : true }) != nil { note("dialog cancelled"); scope = app.focusedWindow ?? app; return true }
        note("dialog STILL open: stopping")
        return false
    }

    /// Polls `find` until it returns something or the timeout passes.
    func wait<T>(_ find: () -> T?) -> T? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if let v = find() { return v }
            Thread.sleep(forTimeInterval: poll)
        } while Date() < end
        return find()
    }

    /// The scope first, then every window (a control can sit in the transport, not the front window).
    private func locate(_ find: (AXNode) -> AXNode?) -> AXNode? {
        if let n = find(scope) { return n }
        for w in app.windows where w !== scope { if let n = find(w) { return n } }
        return nil
    }

    func run(_ steps: [AXStep]) throws {
        for s in steps { try step(s) }
    }

    func step(_ s: AXStep) throws {
        switch s {
        case .optional(let inner):
            do { try step(inner) } catch { note("skipped \(inner): \(error)") }
        case .menu(let path):
            guard let item = wait({ AXFind.menuItem(path, in: app) }) else { throw AXFailure("no \(s)") }
            item.perform(kAXPressAction)
            note("pressed \(s)")
        case .press(let m):
            guard let b = wait({ locate { AXFind.first(m, in: $0) } }) else { throw AXFailure("no \(s)") }
            b.perform(kAXPressAction)
            note("pressed \(s)")
        case .window(let titles):
            guard let w = wait({ AXFind.window(titles, in: app) }) else { throw AXFailure("no \(s)") }
            scope = w
            note("found \(s)")
        case .set(let labels, let text, let kind):
            if case .tempo(let v) = kind, !AXFieldKind.tempoRange.contains(v) {
                throw AXFailure(String(format: "tempo %.2f is outside 20-999 BPM", v))
            }
            guard let f = wait({ AXFind.field(labels, in: scope, accept: kind.accepts) }) else { throw AXFailure("no \(s)") }
            note("found \(s) (holds \(f.valueText ?? "nothing"))")
            try fill(f, text, kind: kind, what: s.description)
        case .choose(let texts):
            guard let n = wait({ AXFind.choice(texts, in: scope) }) else { throw AXFailure("no \(s)") }
            select(n)
            note("chose \(n.allText.first ?? texts[0])")
        case .check(let labels, let on):
            guard let c = wait({ AXFind.first(AXMatch(roles: ["AXCheckBox"], labels: labels), in: scope) }) else { throw AXFailure("no \(s)") }
            if (c.valueText == "1") != on { c.perform(kAXPressAction) }
            note("\(s) \(on ? "on" : "off")")
        case .popup(let m, let options):
            guard let p = wait({ locate { AXFind.first(m, in: $0) } }) else { throw AXFailure("no \(s)") }
            if !p.perform(kAXShowMenuAction) { p.perform(kAXPressAction) }
            guard let item = wait({ AXFind.choice(options, in: p, roles: ["AXMenuItem"]) ?? app.windows.lazy.compactMap({ AXFind.choice(options, in: $0, roles: ["AXMenuItem"]) }).first })
            else {
                keys.key(KeyCode.escape, flags: [], pid: pid)
                throw AXFailure("no \"\(options.first ?? "")\" in \(s)")
            }
            item.perform(kAXPressAction)
            note("picked \(item.title ?? options[0]) in \(s)")
        case .typeInto(let m, let text):
            guard let n = wait({ locate { AXFind.first(m, in: $0) } }) else { throw AXFailure("no \(s)") }
            if n.isValueSettable, n.setValue(text) { note("set \(s) = \(text)"); return }
            guard let f = n.frame, f.width > 0 else { throw AXFailure("\(s) has no frame") }
            keys.doubleClick(CGPoint(x: f.midX, y: f.midY))
            keys.key(KeyCode.a, flags: .maskCommand, pid: pid)
            keys.type(text, pid: pid)
            keys.key(KeyCode.return, flags: [], pid: pid)
            note("typed \(text) into \(s)")
        case .waitClosed:
            let w = scope
            let gone = wait({ isOpen(w) ? nil : true })
            guard gone != nil else { throw AXFailure("the dialog stayed open") }
            scope = app.focusedWindow ?? app
            note("dialog closed")
        }
    }

    /// Sets a field: the AX value if the field takes it, else focus it and type. Keys are only
    /// sent once the found field says it has focus (never into whatever else is focused), and the
    /// value is read back and checked against `kind`.
    private func fill(_ f: AXNode, _ text: String, kind: AXFieldKind, what: String) throws {
        if f.isValueSettable, f.setValue(text) {
            note("set \(what) = \(text)")
        } else {
            guard f.setBool(kAXFocusedAttribute, true) else { throw AXFailure("\(what) would not take focus") }
            guard f.isFocused == true else { throw AXFailure("\(what) did not report focus; nothing typed") }
            keys.key(KeyCode.a, flags: .maskCommand, pid: pid)
            keys.type(text, pid: pid)
            keys.key(KeyCode.tab, flags: [], pid: pid)
            note("typed \(what) = \(text)")
        }
        let got = f.valueText
        note("read back \(what) = \(got ?? "nothing")")
        if let why = kind.refusal(got, typed: text) { throw AXFailure("\(what) \(why)") }
    }

    private func select(_ n: AXNode) {
        var row: AXNode? = n
        while let r = row, r.role != "AXRow" { row = r.parent; if row === app { row = nil } }
        if let r = row, r.setBool(kAXSelectedAttribute, true) { return }
        if !n.perform(kAXPressAction) { _ = n.setBool(kAXSelectedAttribute, true) }
    }
}

/// The real tree, through AXUIElement.
final class AXElement: AXNode {
    let el: AXUIElement
    init(_ el: AXUIElement) { self.el = el }

    static func app(pid: pid_t) -> AXElement {
        let e = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(e, 1.5)
        return AXElement(e)
    }

    private func attr(_ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
    private func string(_ name: String) -> String? { attr(name) as? String }
    private func element(_ name: String) -> AXNode? {
        guard let v = attr(name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return AXElement(v as! AXUIElement)
    }
    private func elements(_ name: String) -> [AXNode] {
        guard let arr = attr(name) as? [AnyObject] else { return [] }
        return arr.compactMap { o in CFGetTypeID(o) == AXUIElementGetTypeID() ? AXElement(o as! AXUIElement) : nil }
    }

    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var title: String? { string(kAXTitleAttribute) }
    var desc: String? { string(kAXDescriptionAttribute) }
    var help: String? { string(kAXHelpAttribute) }
    var identifier: String? { string(kAXIdentifierAttribute) }
    var valueText: String? {
        switch attr(kAXValueAttribute) {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
    var children: [AXNode] { elements(kAXChildrenAttribute) }
    var parent: AXNode? { element(kAXParentAttribute) }
    var windows: [AXNode] { elements(kAXWindowsAttribute) }
    var focusedWindow: AXNode? { element(kAXFocusedWindowAttribute) }
    var menuBar: AXNode? { element(kAXMenuBarAttribute) }
    var isFocused: Bool? { (attr(kAXFocusedAttribute) as? NSNumber)?.boolValue }
    var isValueSettable: Bool {
        var b = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &b) == .success && b.boolValue
    }
    var frame: CGRect? {
        guard let p = attr(kAXPositionAttribute), let s = attr(kAXSizeAttribute) else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pt), AXValueGetValue(s as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)
    }

    func setValue(_ text: String) -> Bool {
        let v: CFTypeRef = (attr(kAXValueAttribute) is NSNumber) ? (Double(text).map { NSNumber(value: $0) } ?? text as NSString) : text as NSString
        guard AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, v) == .success else { return false }
        _ = perform(kAXConfirmAction)
        return true
    }
    func setBool(_ attribute: String, _ on: Bool) -> Bool {
        AXUIElementSetAttributeValue(el, attribute as CFString, (on ? kCFBooleanTrue : kCFBooleanFalse)!) == .success
    }
    @discardableResult func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(el, action as CFString) == .success
    }
}

/// Brings the DAW forward for the route and puts things back after: the DAW's own window that
/// had focus is raised again, then the app that was in front (Beat Key) is reactivated.
struct AXFocus {
    let previous: NSRunningApplication?
    let window: AXNode?

    static func begin(_ daw: NSRunningApplication, app: AXNode) -> AXFocus {
        let f = AXFocus(previous: NSWorkspace.shared.frontmostApplication, window: app.focusedWindow)
        daw.activate(options: [])
        Thread.sleep(forTimeInterval: 0.25)
        return f
    }

    func end(_ daw: NSRunningApplication) {
        if let w = window {
            w.perform(kAXRaiseAction)
            _ = w.setBool(kAXMainAttribute, true)
        }
        if let p = previous, p.processIdentifier != daw.processIdentifier { p.activate(options: []) }
    }
}

/// The DAW's running app, if open.
enum AXApps {
    static func running(_ d: DAW) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { DAW.from(bundleID: $0.bundleIdentifier, name: $0.localizedName) == d }
    }
}
