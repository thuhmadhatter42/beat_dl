import AppKit
import SwiftUI

// Advanced mode's harmony column (orra-parity §2.2-2.6): the key wheel and the notes heard, the
// chord strip (click = hear, drag = a MIDI clip) and MATCH TO, on the same amber-LCD glass as the
// readout. Plain values in (PocketState), PocketActions out, like the rest of the window.

/// Advanced mode's remembered choices, as plain values (DisplaySettings holds them).
struct HarmonyPrefs: Equatable {
    var quality: ChordQuality = .triad
    var voicing: Voicing = .root
    var bars = 1
    /// The project key MATCH TO compares with; nil = none picked.
    var matchKey: String? = nil

    init(quality: ChordQuality = .triad, voicing: Voicing = .root, bars: Int = 1, matchKey: String? = nil) {
        self.quality = quality; self.voicing = voicing; self.bars = bars; self.matchKey = matchKey
    }

    init(_ d: DisplaySettings) {
        self.init(quality: d.chordQuality, voicing: d.chordVoicing, bars: d.chordBars, matchKey: d.matchKey)
    }

    /// Writes the choices back.
    func apply(to d: DisplaySettings) {
        if d.chordQuality != quality { d.chordQuality = quality }
        if d.chordVoicing != voicing { d.chordVoicing = voicing }
        if d.chordBars != bars { d.chordBars = bars }
        if d.matchKey != matchKey { d.matchKey = matchKey }
    }
}

/// The key's Camelot code and relative key, beside the dial (Advanced mode).
struct CamelotBadge: View {
    let code: String
    let relative: String?

    var body: some View {
        VStack(spacing: 3) {
            Text(code).font(Theme.face(11).monospacedDigit()).tracking(0.4)
                .foregroundColor(Theme.amber)
                .frame(minWidth: 30).padding(.vertical, 2).padding(.horizontal, 3)
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Theme.amber(0.45), lineWidth: 1))
                .amberGlow()
            if let rel = relative {
                Text("REL \(rel)").font(Theme.face(7)).tracking(0.8).foregroundColor(Theme.amber(0.6))
                    .lineLimit(1).fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text("Camelot \(code)" + (relative.map { ", relative key \($0)" } ?? "")))
    }
}

/// The column right of the window's module: one LCD glass with the wheel and the notes heard,
/// the chords, and MATCH TO.
struct HarmonyPanel: View {
    let state: PocketState
    var actions = PocketActions()

    static let width: CGFloat = 432

    private var key: String? { state.result?.keys.first?.0 }
    private var prefs: HarmonyPrefs { state.harmony }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            wheelAndNotes
            HarmonyRule().padding(.vertical, 14)
            chords
            HarmonyRule().padding(.vertical, 14)
            MatchToRow(key: key, target: prefs.matchKey, pick: actions.pickMatchKey)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .lcdGlass(radius: 5)
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 16, trailing: 14))
        .modulePanel()
    }

    // MARK: the wheel and the notes heard

    private var wheelAndNotes: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text.cap("KEY WHEEL")
                KeyWheel(keys: state.result?.keys ?? [],
                         onChoose: state.result.map { r in { k in SpellingSettings.shared.choose(k, of: r, from: "the key wheel") } })
                    .frame(width: KeyWheel.side, height: KeyWheel.side)
            }
            if let chroma = state.result?.chroma, chroma.count == 12 {
                VStack(alignment: .leading, spacing: 8) {
                    Text.cap("NOTES HEARD")
                    NotesHeard(chroma: chroma, scale: state.scale).frame(height: KeyWheel.side)
                }
                .frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: the chords

    private var chords: some View {
        let quality = prefs.quality
        let diatonic = key.map { Harmony.diatonic($0, quality: quality) } ?? []
        let borrowed = key.map { Harmony.borrowed($0, quality: quality) } ?? []
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text.cap(state.scale.map { "CHORDS · \($0.tonicName) \($0.minor ? "MINOR" : "MAJOR")" } ?? "CHORDS")
                Spacer(minLength: 4)
                Text("CLICK = HEAR · DRAG = MIDI").font(Theme.face(7)).tracking(1.1)
                    .foregroundColor(Theme.amber(key == nil ? 0.2 : 0.45)).fixedSize()
            }
            chordControls.padding(.top, 10)
            if diatonic.isEmpty {
                Text("NO KEY YET · PASTE, OPEN OR LISTEN").font(Theme.face(8)).tracking(1.4)
                    .foregroundColor(Theme.amber(0.3))
                    .frame(maxWidth: .infinity, minHeight: 106)
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(diatonic.enumerated()), id: \.offset) { i, c in
                        ChordCell(chord: c, tonic: i == 0, actions: actions)
                    }
                }
                .padding(.top, 10)
                HStack(spacing: 8) {
                    Text("BORROWED").font(Theme.face(7)).tracking(1.4).foregroundColor(Theme.amber(0.45))
                        .fixedSize().frame(width: 60, alignment: .leading)
                    HStack(spacing: 4) {
                        ForEach(Array(borrowed.enumerated()), id: \.offset) { _, c in
                            ChordCell(chord: c, tonic: false, actions: actions)
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    /// TRIAD / 7TH / 9TH · ROOT / 1ST / 2ND / OPEN · 1 / 2 / 4 BARS.
    private var chordControls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(ChordQuality.allCases, id: \.self) { q in
                    LCDChip(title: q.label, on: prefs.quality == q, label: "Chords as \(q.spoken)", width: 34) {
                        var p = prefs; p.quality = q; actions.setHarmony(p)
                    }
                }
            }
            HStack(spacing: 3) {
                ForEach(Voicing.allCases, id: \.self) { v in
                    LCDChip(title: v.label, on: prefs.voicing == v, label: "Voicing: \(v.spoken)", width: 32) {
                        var p = prefs; p.voicing = v; actions.setHarmony(p)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                ForEach(ChordClip.barChoices, id: \.self) { b in
                    LCDChip(title: "\(b)", on: prefs.bars == b, label: "\(b) bar\(b == 1 ? "" : "s") long", width: 18) {
                        var p = prefs; p.bars = b; actions.setHarmony(p)
                    }
                }
                Text("BAR").font(Theme.face(7)).tracking(1.1).foregroundColor(Theme.amber(0.45)).padding(.leading, 2)
                    .accessibility(hidden: true)
            }
        }
    }
}

/// The hairline between the harmony column's sections (the readout's KeyStrip rule).
struct HarmonyRule: View {
    var body: some View { Rectangle().fill(Theme.amber(0.12)).frame(height: 1) }
}

/// One chord: its name and numeral. Click = hear it; drag = its MIDI clip into a DAW or Finder.
struct ChordCell: View {
    let chord: Chord
    let tonic: Bool
    let actions: PocketActions
    @State private var flash = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        VStack(spacing: 3) {
            Text(chord.name).font(Theme.face(chord.name.count > 6 ? 9.5 : 11.5)).tracking(0.2)
                .foregroundColor(flash ? Theme.hex(0x1a1206) : Theme.amber(tonic ? 1 : 0.88))
                .lineLimit(1).minimumScaleFactor(0.6)
                .modifier(PocketGlow(on: tonic && !flash))
            Text(chord.roman).font(Theme.face(7.5)).tracking(0.6)
                .foregroundColor(flash ? Theme.hex(0x1a1206).opacity(0.8) : Theme.amber(chord.borrowed ? 0.5 : 0.6))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(shape.fill(flash ? Theme.amber : Theme.amber(tonic ? 0.12 : 0.06)))
        .overlay(shape.stroke(Theme.amber(chord.borrowed ? 0.32 : 0.18),
                              style: StrokeStyle(lineWidth: 1, dash: chord.borrowed ? [3, 2] : [])))
        .contentShape(shape)
        .onTapGesture(perform: play)
        .onDrag(drag)
        .pointingHand()
        .help("\(chord.name): click to hear, drag into your DAW for a MIDI clip")
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text("\(chord.name), \(chord.roman)\(chord.borrowed ? ", borrowed" : "")"))
        .accessibility(hint: Text("Plays the chord. Drag it into your DAW or Finder for a MIDI clip"))
        .accessibility(addTraits: .isButton)
        .accessibilityAction(.default, play)
    }

    private func play() {
        actions.playChord(chord)
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeOut(duration: 0.25)) { flash = false }
        }
    }

    private func drag() -> NSItemProvider {
        guard let url = actions.chordFile(chord) else { NSSound.beep(); return NSItemProvider() }
        let p = NSItemProvider(object: url as NSURL)
        p.suggestedName = url.lastPathComponent
        return p
    }
}

/// MATCH TO: the project key picker and the -6...+6 row, the shift that fits lit.
struct MatchToRow: View {
    let key: String?
    let target: String?
    let pick: () -> Void

    private var shift: Int? {
        guard let k = key, let t = target else { return nil }
        return Transpose.shift(from: k, to: t)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text.cap("MATCH TO")
                Button(action: pick) {
                    Text((target ?? "PICK KEY") + " ▾").font(Theme.face(8)).tracking(0.8)
                        .foregroundColor(Theme.amber(target == nil ? 0.6 : 1))
                        .padding(.horizontal, 6).frame(height: 15)
                        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Theme.amber(0.35), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .pointingHand()
                .accessibility(label: Text(target.map { "Project key \($0). Change it" } ?? "Pick your project's key"))
                Spacer(minLength: 4)
                Text(line).font(Theme.face(7.5)).tracking(1).foregroundColor(Theme.amber(shift == nil ? 0.35 : 0.75))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            HStack(spacing: 3) {
                ForEach(Array(Transpose.range), id: \.self) { n in cell(n) }
            }
            .accessibilityElement(children: .ignore)
            .accessibility(label: Text(spoken))
        }
    }

    private var line: String {
        guard let t = target else { return "PICK YOUR PROJECT'S KEY" }
        guard let s = shift else { return "NO KEY YET" }
        return s == 0 ? "ALREADY FITS \(t)" : "PITCH THE BEAT \(Transpose.label(s)) TO FIT \(t)"
    }

    private var spoken: String {
        guard let t = target else { return "Match to: no project key picked" }
        guard let s = shift else { return "Match to \(t): no key yet" }
        if s == 0 { return "Already fits \(t)" }
        return "Pitch the beat \(s > 0 ? "up" : "down") \(abs(s)) semitone\(abs(s) == 1 ? "" : "s") to fit \(t)"
    }

    private func cell(_ n: Int) -> some View {
        let on = Transpose.lit(n, shift: shift)
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return Text(Transpose.label(n)).font(Theme.face(8.5).monospacedDigit())
            .foregroundColor(on ? Theme.hex(0x1a1206) : Theme.amber(n == 0 ? 0.6 : 0.4))
            .frame(maxWidth: .infinity).frame(height: 20)
            .background(shape.fill(on ? Theme.amber : Theme.amber(0.05)))
            .overlay(shape.stroke(Theme.amber(on ? 0 : (n == 0 ? 0.3 : 0.14)), lineWidth: 1))
            .shadow(color: on && !Theme.highContrast ? Theme.amberGlow : .clear, radius: 3)
    }
}

/// The circle of fifths: 12 majors outside, their relative minors inside. The key on show is
/// lit, the runner-ups outlined; a click makes a key THE key (SpellingSettings.choose, the
/// same path as a click on key 2 or 3).
struct KeyWheel: View {
    let keys: [(String, Int)]
    var onChoose: ((String) -> Void)? = nil

    static let side: CGFloat = 200
    /// Three circles (J, 2026-11-09): the centre holds the Camelot code, minors fill the ring between
    /// `innerRadius` and `middleRadius`, majors the ring between `middleRadius` and `outerRadius`.
    /// A line between every two keys splits each ring into 12 sections; a lit key lights its section.
    static let innerRadius: CGFloat = 32
    static let middleRadius: CGFloat = 64
    static let outerRadius: CGFloat = side / 2 - 1

    /// Position `i` (0 = top, clockwise) of the circle: (pitch class, minor).
    static func slot(_ i: Int, minor: Bool) -> (pc: Int, minor: Bool) {
        let major = (i * 7) % 12
        return (minor ? (major + 9) % 12 : major, minor)
    }

    /// How a slot is lit: 0 = the key on show, 1 = a runner-up, nil = not in the reading.
    func rank(_ pc: Int, minor: Bool) -> Int? {
        for (i, k) in keys.prefix(3).enumerated() {
            if let c = AutoTuneSend.keyClass(k.0), c.pitchClass == pc, c.minor == minor { return i == 0 ? 0 : 1 }
        }
        return nil
    }

    /// The section under the mouse: slot index * 2 + (minor ? 1 : 0). nil = none.
    @State private var hovered: Int?

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                ForEach([false, true], id: \.self) { minor in
                    KeyWheelSection(index: i, minor: minor, rank: rank(KeyWheel.slot(i, minor: minor).pc, minor: minor),
                                    hover: hovered == i * 2 + (minor ? 1 : 0), onChoose: onChoose,
                                    onHover: { inside in
                                        let id = i * 2 + (minor ? 1 : 0)
                                        if inside { hovered = id } else if hovered == id { hovered = nil }
                                    })
                }
            }
            KeyWheelGrid().allowsHitTesting(false)
            center.allowsHitTesting(false)
            if let h = hovered { card(for: h).allowsHitTesting(false).transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .frame(width: KeyWheel.side, height: KeyWheel.side)
        .accessibilityElement(children: .contain)
        .accessibility(label: Text("Key wheel"))
    }

    /// The pop-up for the hovered section: how sure, and why it is lit (J, 2026-11-09: no extra text
    /// on screen by default; the explanation appears only on hover). Sits in the half of the wheel
    /// away from the section so it never covers it.
    private func card(for id: Int) -> some View {
        let i = id / 2, minor = id % 2 == 1
        let s = KeyWheel.slot(i, minor: minor)
        let info = info(s.pc, minor: minor)
        let top = cos(Double(i) * .pi / 6) > 0
        return VStack(alignment: .leading, spacing: 3) {
            Text(info.title).font(Theme.face(11)).foregroundColor(Theme.amber)
            Text(info.why).font(.system(size: 10)).foregroundColor(Theme.amber(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(width: 176, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hex(0x15100a).opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.amber(0.45), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.5), radius: 6, y: 2)
        .offset(y: top ? 52 : -52)
    }

    /// The name as the wheel spells it.
    static func name(_ pc: Int, minor: Bool) -> String {
        KeySpelling.respell(KeyChoice.keyName(pc, minor: minor), to: SpellingSettings.shared.preference)
    }

    /// The scale's seven pitch classes.
    static func notes(_ pc: Int, minor: Bool) -> Set<Int> {
        Set((minor ? Scale.naturalMinor : Scale.major).map { ($0 + pc) % 12 })
    }

    /// How sure the reading is of this key (0-100), nil = not one of its top three.
    func percent(_ pc: Int, minor: Bool) -> Int? {
        for k in keys.prefix(3) {
            if let c = AutoTuneSend.keyClass(k.0), c.pitchClass == pc, c.minor == minor { return k.1 }
        }
        return nil
    }

    /// What the hover card says: the key and how sure, then why it relates to the key on show.
    func info(_ pc: Int, minor: Bool) -> (title: String, why: String) {
        let name = KeyWheel.name(pc, minor: minor)
        let title = percent(pc, minor: minor).map { "\(name) · \($0)% SURE" } ?? name
        guard let k = keys.first?.0, let t = AutoTuneSend.keyClass(k) else {
            return (title, "Click to use it as the key.")
        }
        if t.pitchClass == pc && t.minor == minor {
            return (title, "Beat Key's pick: the closest match to what it heard.")
        }
        let topName = KeyWheel.name(t.pitchClass, minor: t.minor)
        let shared = KeyWheel.notes(pc, minor: minor).intersection(KeyWheel.notes(t.pitchClass, minor: t.minor)).count
        let mode = minor ? "minor" : "major"
        if shared == 7 {
            return (title, "The relative \(mode) of \(topName): the same seven notes, so the two are easy to mix up.")
        }
        if shared == 6 {
            return (title, "Next to \(topName) on the circle of fifths. They differ by one note, so they fit together.")
        }
        if pc == t.pitchClass {
            return (title, "Same root as \(topName), but \(mode). Three notes differ.")
        }
        return (title, "Shares \(shared) of 7 notes with \(topName)" + (shared <= 4 ? ", so it clashes." : "."))
    }

    /// The key on show's Camelot code in the middle (the wheel's own numbering).
    @ViewBuilder private var center: some View {
        if let k = keys.first?.0, let code = Camelot.code(k) {
            VStack(spacing: 1) {
                Text(code).font(Theme.face(13)).foregroundColor(Theme.amber(0.85))
                Text("CAMELOT").font(Theme.face(5.5)).tracking(1).foregroundColor(Theme.amber(0.4))
            }
            .animation(nil, value: code)
            .accessibility(hidden: true)
        }
    }
}

/// One ring section between two lines: centred on slot `index` (0 = top, clockwise), 30° wide,
/// from `inner` to `outer` radius, in the wheel's own square.
struct RingSector: Shape {
    let index: Int
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let mid = Double(index) * 30 - 90          // SwiftUI angles start at 3 o'clock, y down
        let a0 = Angle.degrees(mid - 15), a1 = Angle.degrees(mid + 15)
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// The three circles and the 12 lines between keys, drawn once over the sections.
private struct KeyWheelGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r0 = KeyWheel.innerRadius, r1 = KeyWheel.middleRadius, r2 = KeyWheel.outerRadius
            var circles = Path()
            for r in [r0, r1, r2] { circles.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
            ctx.stroke(circles, with: .color(Theme.amber(0.28)), lineWidth: 1)
            var lines = Path()
            for i in 0..<12 {
                let a = (Double(i) * 30 - 90 + 15) * .pi / 180
                lines.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * r0, y: c.y + CGFloat(sin(a)) * r0))
                lines.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r2, y: c.y + CGFloat(sin(a)) * r2))
            }
            ctx.stroke(lines, with: .color(Theme.amber(0.2)), lineWidth: 1)
        }
        .frame(width: KeyWheel.side, height: KeyWheel.side)
    }
}

/// One key's section: lit whole when it is the key (solid) or a runner-up (dim), a faint wash on
/// hover, and the light eases in and out instead of jumping.
private struct KeyWheelSection: View {
    let index: Int
    let minor: Bool
    let rank: Int?
    let hover: Bool
    let onChoose: ((String) -> Void)?
    let onHover: (Bool) -> Void

    var body: some View {
        let s = KeyWheel.slot(index, minor: minor)
        let name = KeySpelling.respell(KeyChoice.keyName(s.pc, minor: minor), to: SpellingSettings.shared.preference)
        let inner = minor ? KeyWheel.innerRadius : KeyWheel.middleRadius
        let outer = minor ? KeyWheel.middleRadius : KeyWheel.outerRadius
        let shape = RingSector(index: index, inner: inner, outer: outer)
        let fill: Double = rank == 0 ? 1 : rank == 1 ? 0.22 : (hover && onChoose != nil ? 0.1 : 0)
        let mid = Double(index) * .pi / 6, r = (inner + outer) / 2
        let label = Text(name).font(Theme.face(minor ? 8 : 10)).lineLimit(1).minimumScaleFactor(0.6)
            .foregroundColor(rank == 0 ? Theme.hex(0x1a1206) : Theme.amber(rank == 1 ? 0.95 : (hover ? 0.8 : (minor ? 0.4 : 0.5))))
            .frame(width: minor ? 26 : 34)
            .offset(x: CGFloat(sin(mid)) * r, y: -CGFloat(cos(mid)) * r)
        let body = ZStack {
            shape.fill(Theme.amber(fill))
                .shadow(color: rank == 0 && !Theme.highContrast ? Theme.amberGlow : .clear, radius: 5)
            label
        }
        .frame(width: KeyWheel.side, height: KeyWheel.side)
        .contentShape(shape)
        .animation(.easeOut(duration: 0.18), value: rank)
        .animation(.easeOut(duration: 0.1), value: hover)
        let spoken = "\(KeyChoice.keyName(s.pc, minor: minor).replacingOccurrences(of: "m", with: "")) \(minor ? "minor" : "major")"
        return Group {
            if let choose = onChoose {
                Button(action: { choose(name) }) { body }
                    .buttonStyle(KeyWheelPress())
                    .onHover(perform: onHover)
                    .pointingHand()
                    .accessibility(label: Text(spoken + (rank == 0 ? ", the key" : rank == 1 ? ", a runner-up" : "")))
                    .accessibility(hint: Text("Makes it the key"))
                    .accessibility(addTraits: rank == 0 ? .isSelected : [])
            } else {
                body.onHover(perform: onHover).accessibility(label: Text(spoken))
            }
        }
    }
}

/// A press shows at once (brightens), so a click feels instant even before the key changes.
private struct KeyWheelPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.brightness(configuration.isPressed ? 0.12 : 0)
    }
}

/// The 12 pitch classes the analyzer heard, as LCD bars (strongest = full height). The key's
/// scale notes are bright and dotted, the rest dim.
struct NotesHeard: View {
    let chroma: [Double]
    let scale: Scale?

    /// 0...1 against the strongest note (all zero stays zero).
    static func levels(_ chroma: [Double]) -> [Double] {
        let m = chroma.map { max(0, $0) }.max() ?? 0
        return chroma.map { m > 0 ? max(0, $0) / m : 0 }
    }

    var body: some View {
        let lv = NotesHeard.levels(chroma)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<12, id: \.self) { pc in
                let inScale = scale?.notes.contains(pc) ?? false
                let tonic = scale?.tonic == pc
                VStack(spacing: 4) {
                    GeometryReader { g in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 1.5).fill(Theme.amber(0.05))
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Theme.rgb(255, 176, 32, tonic ? 1 : inScale ? 0.8 : (Theme.highContrast ? 0.35 : 0.25)))
                                .frame(height: max(2, g.size.height * CGFloat(lv[pc])))
                                .shadow(color: tonic && !Theme.highContrast ? Theme.amberGlow : .clear, radius: 3)
                        }
                    }
                    Text(scale?.name(pc) ?? Scale.sharpNames[pc]).font(Theme.face(7)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundColor(Theme.amber(inScale ? 0.85 : 0.35)).frame(height: 9)
                    Circle().fill(Theme.amber(inScale ? 0.8 : 0)).frame(width: 3, height: 3)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text(spoken(lv)))
    }

    private func spoken(_ lv: [Double]) -> String {
        let order = (0..<12).filter { lv[$0] > 0.05 }.sorted { lv[$0] > lv[$1] }.prefix(7)
        let names = order.map { scale?.name($0) ?? Scale.sharpNames[$0] }
        return names.isEmpty ? "Notes heard: none" : "Notes heard, strongest first: " + names.joined(separator: ", ")
    }
}
