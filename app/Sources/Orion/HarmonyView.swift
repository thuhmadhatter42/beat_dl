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
    /// The minors' ring (the majors sit at side / 2 - 17).
    static let innerRadius: CGFloat = 50

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

    var body: some View {
        let r = KeyWheel.side / 2
        ZStack {
            let inner = KeyWheel.innerRadius
            Circle().stroke(Theme.amber(0.1), lineWidth: 1).frame(width: KeyWheel.side - 2, height: KeyWheel.side - 2)
            Circle().stroke(Theme.amber(0.08), lineWidth: 1).frame(width: (inner + 16) * 2, height: (inner + 16) * 2)
            Circle().stroke(Theme.amber(0.06), lineWidth: 1).frame(width: (inner - 15) * 2, height: (inner - 15) * 2)
            ForEach(0..<12, id: \.self) { i in
                slotView(i, minor: false).offset(position(i, radius: r - 17))
                slotView(i, minor: true).offset(position(i, radius: inner))
            }
            center
        }
        .frame(width: KeyWheel.side, height: KeyWheel.side)
        .accessibilityElement(children: .contain)
        .accessibility(label: Text("Key wheel"))
    }

    private func position(_ i: Int, radius: CGFloat) -> CGSize {
        let a = Double(i) * .pi / 6
        return CGSize(width: CGFloat(sin(a)) * radius, height: -CGFloat(cos(a)) * radius)
    }

    /// The key on show's Camelot code in the middle (the wheel's own numbering).
    @ViewBuilder private var center: some View {
        if let k = keys.first?.0, let code = Camelot.code(k) {
            VStack(spacing: 1) {
                Text(code).font(Theme.face(13)).foregroundColor(Theme.amber(0.85))
                Text("CAMELOT").font(Theme.face(5.5)).tracking(1).foregroundColor(Theme.amber(0.4))
            }
            .accessibility(hidden: true)
        }
    }

    private func slotView(_ i: Int, minor: Bool) -> some View {
        let s = KeyWheel.slot(i, minor: minor)
        let name = KeySpelling.respell(KeyChoice.keyName(s.pc, minor: minor), to: SpellingSettings.shared.preference)
        let rank = rank(s.pc, minor: minor)
        let d: CGFloat = minor ? 24 : 30
        let label = Text(name).font(Theme.face(minor ? 8 : 10)).lineLimit(1).minimumScaleFactor(0.7)
            .foregroundColor(rank == 0 ? Theme.hex(0x1a1206) : Theme.amber(rank == 1 ? 0.95 : (minor ? 0.4 : 0.5)))
            .frame(width: d, height: d)
            .background(Circle().fill(rank == 0 ? Theme.amber : Theme.amber(rank == 1 ? 0.14 : 0)))
            .overlay(Circle().stroke(Theme.amber(rank == 1 ? 0.7 : 0), lineWidth: 1))
            .shadow(color: rank == 0 && !Theme.highContrast ? Theme.amberGlow : .clear, radius: 4)
            .contentShape(Circle())
        let spoken = "\(KeyChoice.keyName(s.pc, minor: minor).replacingOccurrences(of: "m", with: "")) \(minor ? "minor" : "major")"
        return Group {
            if let choose = onChoose {
                Button(action: { choose(name) }) { label }
                    .buttonStyle(PlainButtonStyle())
                    .pointingHand()
                    .help("Use \(name) as the key")
                    .accessibility(label: Text(spoken + (rank == 0 ? ", the key" : rank == 1 ? ", a runner-up" : "")))
                    .accessibility(hint: Text("Makes it the key"))
                    .accessibility(addTraits: rank == 0 ? .isSelected : [])
            } else {
                label.accessibility(label: Text(spoken))
            }
        }
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
