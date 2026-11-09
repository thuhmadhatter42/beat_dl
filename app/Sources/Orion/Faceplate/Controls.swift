import AppKit
import SwiftUI

/// The recessed `#050505` field (Artemis's plate) holding the link.
struct LinkField: View {
    @Binding var text: String
    @Binding var focused: Bool
    let onSubmit: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.R.well, style: .continuous)
        field
            .padding(.horizontal, 12)
            .frame(height: Theme.H.lg)
            .background(Theme.panelDeep.clipShape(shape))
            .innerShadow(shape, Color.black.opacity(0.9), blur: 5, y: 2)
            .ring(radius: Theme.R.well, spread: 1, Theme.black)
            // `0 1px 0 rgba(255,255,255,.05)`: a lip of light under the recess
            .background(shape.fill(Color.white.opacity(0.05)).offset(y: 1).padding(-1))
            // the focus ring while the field waits for a link
            .overlay(shape.stroke(Theme.A.a3, lineWidth: 2).padding(-2)
                .opacity(focused && text.isEmpty ? 1 : 0))
            .helpTip(HelpText.linkField)
    }

    @ViewBuilder private var field: some View {
        if Pocket.snapshot {
            // ImageRenderer cannot draw the NSTextField: the text drawn here, in the same recess
            Text(text.isEmpty ? "Enter YouTube link here" : text)
                .font(Theme.T.body)
                .foregroundColor(text.isEmpty ? Theme.textLo : Theme.textHi)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            URLTextField(text: $text, focused: $focused, onSubmit: onSubmit)
        }
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
        let shape = RoundedRectangle(cornerRadius: Theme.R.well, style: .continuous)
        HStack(spacing: 8) {
            Text(label ?? "Open Audio...")
                .font(Theme.T.body)
                .foregroundColor(label == nil ? Theme.textLo : Theme.textHi)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            // the field's own small affordance: a folder-open chevron in faint amber
            Text("···").labelStyle()
                .foregroundColor(Theme.A.a3)
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.H.lg)
        .background(Theme.panelDeep.clipShape(shape))
        .innerShadow(shape, Color.black.opacity(0.9), blur: 5, y: 2)
        .ring(radius: Theme.R.well, spread: 1, Theme.black)
        .background(shape.fill(Color.white.opacity(0.05)).offset(y: 1).padding(-1))
        .overlay(Pocket.snapshot ? nil : PickControl(focused: $focused, onOpen: onOpen, onSubmit: onSubmit))
        .overlay(shape.stroke(Theme.A.a3, lineWidth: 2).padding(-2).opacity(focused ? 1 : 0)
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
        f.font = Theme.nsFace(Theme.T.valueSize)
        f.textColor = NSColor(srgbRed: 238 / 255, green: 238 / 255, blue: 242 / 255, alpha: 0.9)
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.cell?.lineBreakMode = .byClipping
        f.placeholderAttributedString = NSAttributedString(string: "Enter YouTube link here", attributes: [
            .font: Theme.nsFace(Theme.T.valueSize),
            .foregroundColor: NSColor(srgbRed: 235 / 255, green: 235 / 255, blue: 240 / 255, alpha: 0.5),
            
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
            (currentEditor() as? NSTextView)?.insertionPointColor = Theme.amberNS
            onFocus?()
        }
        return ok
    }
}

/// The pale SSL-style key cap, three states (design pass F7): ready (cream, dark legend), lit
/// (amber) and unavailable: the same cream cap at full strength, a touch darker, no shine, its
/// legend dimmed. The cap never goes see-through (a faded cap reads as broken, not off).
struct SSLCapStyle: ButtonStyle {
    let lit: Bool
    /// A pale cap that can be pressed now (full strength, not lit): the popover's action caps.
    var ready = false
    /// The cap's outer height, its one ring included: H.lg beside a field, H.md for send caps.
    var height: CGFloat = SSLCapStyle.height
    /// Square caps (the icon-only reset key) drop the side padding.
    var padding: CGFloat = SSLCapStyle.sidePadding

    /// Send / action caps (J 2026-11-09: smaller caps, bigger legends); caps in a field's row
    /// pass Theme.H.lg so they stand as tall as the field.
    static let height: CGFloat = Theme.H.md
    static let legendSize: CGFloat = Theme.T.labelSize
    static let sidePadding: CGFloat = 10
    static let ring: CGFloat = 1

    /// The cap's legend: T.label, 11 pt bold, .08em (Text-only tracking is the macOS 11 way).
    static func label(_ s: String) -> Text { Text(s).labelStyle() }

    func makeBody(configuration: Configuration) -> some View {
        CapBody(label: configuration.label, pressed: configuration.isPressed, lit: lit, ready: ready,
                height: height, padding: padding)
    }
}

/// The cap itself (a view, so it can track the hover).
private struct CapBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    let lit: Bool
    let ready: Bool
    let height: CGFloat
    let padding: CGFloat
    @State private var hover = false

    var body: some View {
        let r = Theme.R.cap
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let on = lit || ready
        return label   // a Text set by SSLCapStyle.label, or an icon
            .foregroundColor(lit ? Theme.accent.litCap.legend.color : on ? Theme.hex(0x3a372f) : Theme.hex(0x4a463c, 0.45))
            .shadow(color: Color.white.opacity(lit ? 0.35 : on ? 0.5 : 0.2), radius: 0, y: 1)
            .padding(.horizontal, padding)
            .frame(height: height - SSLCapStyle.ring * 2)
            .background(
                ZStack(alignment: .top) {
                    if lit {
                        let c = Theme.accent.litCap   // the display colour (COLOR)
                        Theme.vertical([(c.top.color, 0), (c.mid.color, 0.45), (c.bottom.color, 1)])
                    } else if on {
                        Theme.vertical([(Theme.hex(0xefede4), 0), (Theme.hex(0xd6d3c6), 0.45), (Theme.hex(0xb3b0a2), 1)])
                    } else {
                        Theme.vertical([(Theme.hex(0xd8d5ca), 0), (Theme.hex(0xc1bdb0), 0.45), (Theme.hex(0xa9a698), 1)])
                    }
                    // the cap's top shine (an unavailable cap has none)
                    if on {
                        GeometryReader { g in
                            Theme.vertical([(Color.white.opacity(0.55), 0), (Color.white.opacity(0), 1)])
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                .frame(width: g.size.width * 0.84, height: g.size.height * 0.36)
                                .offset(x: g.size.width * 0.08, y: 2)
                        }
                    }
                }
                .clipShape(shape))
            .innerShadow(shape, Color.white.opacity(lit ? 0.6 : on ? 0.85 : 0.4), blur: lit ? 2 : 1, y: 1)
            .innerShadow(shape, Color.black.opacity(lit ? 0.2 : 0.28), blur: 7, y: -5)
            .brightness(pressed ? -0.08 : (hover && on ? 0.04 : 0))
            .offset(y: pressed ? 1 : 0)
            // one ring and one drop shadow (depth budget: chassis, wells, caps)
            .ring(radius: r, spread: SSLCapStyle.ring, Theme.hex(0x0a0a0b))
            .background(Group {
                if lit {
                    shape.fill(Theme.amberGlow).padding(-2).blur(radius: 5.5)
                } else {
                    shape.fill(Color.black.opacity(0.6)).padding(-SSLCapStyle.ring).offset(y: 2).blur(radius: 1.5)
                }
            })
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}
