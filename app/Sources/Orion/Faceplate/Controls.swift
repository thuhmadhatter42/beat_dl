import AppKit
import SwiftUI

/// The recessed `#050505` field (Artemis's plate) holding the link.
struct LinkField: View {
    @Binding var text: String
    @Binding var focused: Bool
    let onSubmit: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        URLTextField(text: $text, focused: $focused, onSubmit: onSubmit)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Theme.panelDeep.clipShape(shape))
            .innerShadow(shape, Color.black.opacity(0.9), blur: 5, y: 2)
            .ring(radius: 4, spread: 1, Theme.black)
            // `0 1px 0 rgba(255,255,255,.05)`: a lip of light under the recess
            .background(shape.fill(Color.white.opacity(0.05)).offset(y: 1).padding(-1))
            // the focus ring while the field waits for a link
            .overlay(shape.stroke(Theme.amber(0.55), lineWidth: 2).padding(-2)
                .opacity(focused && text.isEmpty ? 1 : 0))
    }
}

/// The second row's recessed field: "Open Audio..." until audio is picked, then its name.
/// Click (or Space / Return while it is focused and empty) opens the audio-only open panel.
/// Return with audio picked = FIND KEY/BPM.
struct AudioPickField: View {
    let label: String?
    @Binding var focused: Bool
    let onOpen: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        HStack(spacing: 8) {
            Text(label ?? "Open Audio...")
                .font(.custom("HelveticaNeue", size: 12)).tracking(label == nil ? 0.24 : 0)
                .foregroundColor(label == nil ? Theme.textFaint : Theme.textHi)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            // the field's own small affordance: a folder-open chevron in faint amber
            Text("···").font(Theme.face(11)).tracking(1)
                .foregroundColor(Theme.amber(label == nil ? 0.45 : 0.3))
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Theme.panelDeep.clipShape(shape))
        .innerShadow(shape, Color.black.opacity(0.9), blur: 5, y: 2)
        .ring(radius: 4, spread: 1, Theme.black)
        .background(shape.fill(Color.white.opacity(0.05)).offset(y: 1).padding(-1))
        .overlay(PickControl(focused: $focused, onOpen: onOpen, onSubmit: onSubmit))
        .overlay(shape.stroke(Theme.amber(0.55), lineWidth: 2).padding(-2).opacity(focused ? 1 : 0)
            .allowsHitTesting(false))
        .pointingHand()
    }
}

/// The picker field's input: a key-view NSView (Tab reaches it) that takes the click and keys.
struct PickControl: NSViewRepresentable {
    @Binding var focused: Bool
    let onOpen: () -> Void
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> PickNSView {
        let v = PickNSView()
        v.setAccessibilityElement(true)
        v.setAccessibilityRole(.button)
        v.setAccessibilityLabel("Open audio file")
        update(v)
        return v
    }
    func updateNSView(_ v: PickNSView, context: Context) { update(v) }

    private func update(_ v: PickNSView) {
        v.onOpen = onOpen
        v.onSubmit = onSubmit
        let binding = $focused
        v.onFocus = { f in if binding.wrappedValue != f { DispatchQueue.main.async { binding.wrappedValue = f } } }
    }
}

final class PickNSView: NSView {
    var onOpen: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onFocus: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override func becomeFirstResponder() -> Bool { onFocus?(true); return true }
    override func resignFirstResponder() -> Bool { onFocus?(false); return true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onOpen?()
    }
    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 36, 76: onSubmit?()        // Return / Enter
        case 49: onOpen?()              // Space
        default: super.keyDown(with: e)
        }
    }
    override func accessibilityPerformPress() -> Bool { onOpen?(); return true }
}

/// An NSTextField so the caret is amber, the placeholder is Artemis's faint grey and Return
/// submits, on macOS 11 (SwiftUI's TextField has none of these there).
struct URLTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> AmberCaretField {
        let f = AmberCaretField()
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = Theme.nsFace(12)
        f.textColor = NSColor(srgbRed: 238 / 255, green: 238 / 255, blue: 242 / 255, alpha: 0.9)
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.cell?.lineBreakMode = .byClipping
        f.placeholderAttributedString = NSAttributedString(string: "Enter YouTube link here", attributes: [
            .font: Theme.nsFace(12),
            .foregroundColor: NSColor(srgbRed: 235 / 255, green: 235 / 255, blue: 240 / 255, alpha: 0.28),
            .kern: 0.24,
        ])
        f.delegate = context.coordinator
        f.onFocus = { context.coordinator.setFocused(true) }
        f.setAccessibilityLabel("YouTube link")
        f.unregisterDraggedTypes()   // a dropped file goes to the window (analyze), not into the field
        return f
    }

    func updateNSView(_ f: AmberCaretField, context: Context) {
        context.coordinator.parent = self
        if f.stringValue != text { f.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: URLTextField
        init(_ p: URLTextField) { parent = p }

        func setFocused(_ v: Bool) {
            if parent.focused != v { DispatchQueue.main.async { self.parent.focused = v } }
        }
        func controlTextDidChange(_ n: Notification) {
            guard let f = n.object as? NSTextField else { return }
            parent.text = f.stringValue
        }
        func controlTextDidEndEditing(_ n: Notification) { setFocused(false) }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

final class AmberCaretField: NSTextField {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            (currentEditor() as? NSTextView)?.insertionPointColor =
                NSColor(srgbRed: 1, green: 176 / 255, blue: 32 / 255, alpha: 1)
            onFocus?()
        }
        return ok
    }
}

/// The pale SSL-style key cap. Lit = amber; dim = 45% when there is nothing to do.
struct SSLCapStyle: ButtonStyle {
    let lit: Bool

    /// The cap's legend: 9 pt bold, .16em (Text-only tracking is the macOS 11 way).
    static func label(_ s: String, size: CGFloat = 9) -> Text { Text(s).font(Theme.face(size)).tracking(size * 0.16) }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
        let pressed = configuration.isPressed
        return configuration.label   // a Text set in Theme.face(9), .16em (see SSLCapStyle.label)
            .foregroundColor(lit ? Theme.hex(0x3a2a06) : Theme.hex(0x4a463c))
            .shadow(color: Color.white.opacity(lit ? 0.35 : 0.5), radius: 0, y: 1)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(
                ZStack(alignment: .top) {
                    lit
                        ? Theme.vertical([(Theme.hex(0xffe4a6), 0), (Theme.hex(0xf7b32b), 0.45), (Theme.hex(0xc07f12), 1)])
                        : Theme.vertical([(Theme.hex(0xefede4), 0), (Theme.hex(0xd6d3c6), 0.45), (Theme.hex(0xb3b0a2), 1)])
                    // ::before, the cap's top shine
                    GeometryReader { g in
                        Theme.vertical([(Color.white.opacity(0.55), 0), (Color.white.opacity(0), 1)])
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .frame(width: g.size.width * 0.84, height: g.size.height * 0.36)
                            .offset(x: g.size.width * 0.08, y: 2)
                    }
                }
                .clipShape(shape))
            .innerShadow(shape, Color.white.opacity(lit ? 0.6 : 0.85), blur: lit ? 2 : 1, y: 1)
            .innerShadow(shape, Color.black.opacity(lit ? 0.2 : 0.28), blur: 7, y: -5)
            .brightness(pressed ? -0.08 : 0)
            .offset(y: pressed ? 1 : 0)
            .ring(radius: 2.5, spread: 1, Theme.hex(0x0a0a0b))
            .ring(radius: 2.5, spread: 3, Theme.hex(0x17181a))
            .ring(radius: 2.5, spread: 4, Theme.black)
            .background(Group {
                if lit {
                    shape.fill(Theme.amberGlow).padding(-2).blur(radius: 5.5)
                } else {
                    shape.fill(Color.black.opacity(0.7)).offset(y: 2).blur(radius: 1.5)
                }
            })
            .compositingGroup()   // CSS opacity fades the cap as one layer
            .opacity(lit ? 1 : 0.45)
    }
}
