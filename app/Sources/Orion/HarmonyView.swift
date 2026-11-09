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

/// The column right of the window's module: one LCD glass with the wheel and the notes heard,
/// the chords, and MATCH TO. Its height follows the module beside it.
struct HarmonyPanel: View {
    let state: PocketState
    var actions = PocketActions()
    /// The menu-bar pocket's fit (its 344 pt column): the wheel on its own, centred, its head in
    /// the corner beside it (no notes heard: no room), the chord choices 8 apart, a tighter glass.
    /// The pocket grows taller, not wider.
    var compact = false

    static let width: CGFloat = 432

    private var key: String? { state.result?.keys.first?.0 }
    private var prefs: HarmonyPrefs { state.harmony }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            wheelAndNotes
            HarmonyRule().padding(.vertical, compact ? Theme.S.m : Theme.S.l)
            chords
            HarmonyRule().padding(.vertical, compact ? Theme.S.m : Theme.S.l)
            MatchToRow(key: key, target: prefs.matchKey, pick: actions.pickMatchKey)
            if !compact { Spacer(minLength: 0) }
        }
        .padding(.vertical, compact ? Theme.S.m : Theme.S.l)
        .padding(.horizontal, compact ? Theme.S.m : Theme.S.lcd)
        .frame(maxHeight: compact ? nil : .infinity, alignment: .top)
        .lcdGlass(radius: Theme.R.well)
    }

    // MARK: the wheel and the notes heard

    private var wheel: KeyWheel { HarmonyPanel.wheel(state) }

    /// The wheel: a click sets Manual Key Selection; a click on the white (manual) section clears it.
    static func wheel(_ state: PocketState, settings: SpellingSettings = .shared) -> KeyWheel {
        let r = state.result
        return KeyWheel(keys: r?.keys ?? [], manual: state.manualKey, spelling: settings.preference,
                        onChoose: r.map { r in { k in _ = settings.setManualKey(k, of: r, from: .wheel) } },
                        onClear: r.map { r in { _ = settings.clearManualKey(of: r, from: .wheelReset) } })
    }

    @ViewBuilder private var wheelAndNotes: some View {
        if compact {
            ZStack(alignment: .topLeading) {
                wheel
                    .frame(width: KeyWheel.side, height: KeyWheel.side)
                    .frame(maxWidth: .infinity)
                Text.cap("KEY WHEEL").helpTip(HelpText.keyWheel)
            }
        } else {
            wideWheelAndNotes
        }
    }

    private var wideWheelAndNotes: some View {
        HStack(alignment: .top, spacing: Theme.S.l) {
            VStack(alignment: .leading, spacing: Theme.S.s) {
                Text.cap("KEY WHEEL").helpTip(HelpText.keyWheel)
                wheel
                    .frame(width: KeyWheel.side, height: KeyWheel.side)
            }
            if let chroma = state.result?.chroma, chroma.count == 12 {
                VStack(alignment: .leading, spacing: Theme.S.s) {
                    Text.cap("NOTES HEARD")
                    NotesHeard(chroma: chroma, scale: state.scale).frame(height: KeyWheel.side)
                }
                .helpTip(HelpText.notesHeard)
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
        let borrowed = key.map { Harmony.borrowedRow($0, quality: quality) } ?? []
        return VStack(alignment: .leading, spacing: 0) {
            // "click = hear, drag = MIDI" lives in the chords' help tip (J, 2026-11-09: less text by
            // default); the key's name is already on the readout, so the head is just CHORDS
            HStack(spacing: Theme.S.m) {
                Text.cap("CHORDS").helpTip(HelpText.chords)
                Spacer(minLength: 0)
                HStack(spacing: Theme.S.s) {
                    SegmentedChips(options: ChordClip.barChoices.map { b in
                                       .init(value: b, title: "\(b)", spoken: "\(b) bar\(b == 1 ? "" : "s") long")
                                   },
                                   selected: prefs.bars, width: .fixed(24),
                                   onSelect: { b in var p = prefs; p.bars = b; actions.setHarmony(p) })
                    Text("BAR").captionStyle().foregroundColor(Theme.A.a3).accessibility(hidden: true)
                }
                .helpTip(HelpText.bars)
                LCDChip(title: "MINI", on: state.miniOpen, label: state.miniOpen ? "Close Beat Key Mini" : "Open Beat Key Mini",
                        action: actions.toggleMini)
                    .helpTip(HelpText.mini)
            }
            chordControls.padding(.top, Theme.S.m)
            // a new key crossfades the whole grid in place (Motion.swap)
            Crossfade(key ?? "", alignment: .top) { _ in
                if diatonic.isEmpty {
                    Text("No key yet").font(Theme.T.caption).foregroundColor(Theme.A.a3)
                        .frame(maxWidth: .infinity, minHeight: ChordFace.height * 2 + 28)
                } else {
                    ChordGrid(diatonic: diatonic, borrowed: borrowed) { c, tonic in
                        ChordCell(chord: c, tonic: tonic, actions: actions)
                    }
                    .padding(.top, Theme.S.m)
                }
            }
        }
    }

    /// TRIAD / 7TH / 9TH · ROOT / 1ST / 2ND / OPEN.
    private var chordControls: some View {
        HStack(spacing: compact ? Theme.S.s : Theme.S.m) { chordChoices; Spacer(minLength: 0) }
    }

    @ViewBuilder private var chordChoices: some View {
            SegmentedChips(options: ChordQuality.allCases.map { .init(value: $0, title: $0.label, spoken: "Chords as \($0.spoken)") },
                           selected: prefs.quality,
                           onSelect: { q in var p = prefs; p.quality = q; actions.setHarmony(p) })
                .helpTip(HelpText.quality)
            SegmentedChips(options: Voicing.allCases.map { .init(value: $0, title: $0.label, spoken: "Voicing: \($0.spoken)") },
                           selected: prefs.voicing,
                           onSelect: { v in var p = prefs; p.voicing = v; actions.setHarmony(p) })
                .helpTip(HelpText.voicing)
    }
}

/// The hairline between the harmony column's sections (the readout's KeyStrip rule).
struct HarmonyRule: View {
    var body: some View { Rectangle().fill(Theme.A.a4).frame(height: 1) }
}

/// The chord grid (J 2026-11-09, design audit F10): one 7-column grid for both rows. Row one is
/// the key's seven chords; row two, under a small BORROWED caption on the same left edge, holds
/// each borrowed chord in the column of the degree it stands in for, the other columns empty.
/// `cell` draws one chord (the window's click/drag cell, the Mini's press pad).
struct ChordGrid<Cell: View>: View {
    let diatonic: [Chord]
    /// Seven slots (Harmony.borrowedRow); nil = an empty column.
    let borrowed: [Chord?]
    var gap: CGFloat = Theme.S.xs
    var cellHeight: CGFloat = ChordFace.height
    var rowTip = HelpText.chords
    var borrowedTip = HelpText.borrowed
    let cell: (Chord, Bool) -> Cell

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: gap) {
                ForEach(Array(diatonic.enumerated()), id: \.offset) { i, c in cell(c, i == 0) }
            }
            .helpTip(rowTip)
            if borrowed.contains(where: { $0 != nil }) {
                Text("BORROWED").captionStyle().foregroundColor(Theme.A.a3)
                    .padding(.top, Theme.S.s).padding(.bottom, Theme.S.xs)
                    .accessibility(hidden: true)
                HStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { i in
                        if i < borrowed.count, let c = borrowed[i] {
                            cell(c, false)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: cellHeight)
                                .accessibility(hidden: true)
                        }
                    }
                }
                .helpTip(borrowedTip)
            }
        }
    }
}

/// How one chord looks, in the window's grid and on the Mini. Diatonic: an A5 fill and an A4
/// hairline (the tonic one step brighter). Borrowed: no fill, the same solid hairline (never
/// dashed: dashed reads as an empty slot) and a small dot top-right as its mark. `lit` =
/// sounding (solid amber, dark ink); `hover` = an A4 wash.
struct ChordFace: View {
    let chord: Chord
    let tonic: Bool
    let lit: Bool
    /// The Mini's computer key ("1", "Q"), top-left; nil = none.
    var hint: String? = nil
    var height: CGFloat = ChordFace.height
    var hover = false

    static let height: CGFloat = 48
    static var ink: Color { Theme.A.ink }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.R.cap, style: .continuous)
        let b = chord.borrowed
        let fill: Color = lit ? Theme.A.a1 : hover ? Theme.A.a4 : b ? .clear : tonic ? Theme.A.a4 : Theme.A.a5
        return VStack(spacing: 2) {
            Text(chord.name).font(Theme.T.value)
                .foregroundColor(lit ? ChordFace.ink : tonic ? Theme.A.a1 : Theme.A.a2)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(chord.roman).font(Theme.T.caption)
                .foregroundColor(lit ? ChordFace.ink.opacity(0.8) : Theme.A.a3)
                .lineLimit(1)
        }
        .padding(.horizontal, 3)
        .padding(.top, hint == nil ? 0 : Theme.S.s)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(shape.fill(fill))
        .overlay(shape.stroke(lit ? Color.clear : tonic ? Theme.A.a3 : Theme.A.a4, lineWidth: 1))
        .overlay(mark, alignment: .topTrailing)
        .overlay(hintLabel, alignment: .topLeading)
    }

    @ViewBuilder private var mark: some View {
        if chord.borrowed {
            Circle().fill(lit ? ChordFace.ink.opacity(0.7) : Theme.A.a3).frame(width: 4, height: 4)
                .padding(Theme.S.xs).accessibility(hidden: true)
        }
    }

    @ViewBuilder private var hintLabel: some View {
        if let h = hint {
            Text(h).font(Theme.T.caption).foregroundColor(lit ? ChordFace.ink.opacity(0.7) : Theme.A.a3)
                .padding(.leading, Theme.S.xs).padding(.top, 2).accessibility(hidden: true)
        }
    }
}

/// One chord: its name and numeral. Click = hear it; drag = its MIDI clip into a DAW or Finder.
struct ChordCell: View {
    let chord: Chord
    let tonic: Bool
    let actions: PocketActions
    @State private var flash = false
    @State private var hover = false

    var body: some View {
        ChordFace(chord: chord, tonic: tonic, lit: flash, hover: hover)
        .contentShape(RoundedRectangle(cornerRadius: Theme.R.cap, style: .continuous))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .onTapGesture(perform: play)
        .onDrag(drag)
        .pointingHand()
        .nativeHelp("\(chord.name): click to hear, drag into your DAW for a MIDI clip")
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

/// MATCH TO: the project key picker and the −6…+6 strip, the shift that fits lit.
struct MatchToRow: View {
    let key: String?
    let target: String?
    let pick: () -> Void

    private var shift: Int? {
        guard let k = key, let t = target else { return nil }
        return Transpose.shift(from: k, to: t)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.S.s) {
            HStack(spacing: Theme.S.s) {
                Text.cap("MATCH TO").helpTip(HelpText.matchTo)
                ChipMenuButton(title: target ?? "PICK KEY", tracked: target == nil, action: pick)
                    .accessibility(label: Text(target.map { "Project key \($0). Change it" } ?? "Pick your project's key"))
                    .helpTip(HelpText.matchTo)
                Spacer(minLength: Theme.S.xs)
                if let l = MatchToRow.line(target: target, shift: shift) {
                    Crossfade(l, alignment: .trailing) { l in
                        Text(l).font(Theme.T.value).foregroundColor(Theme.A.a1)
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .helpTip(HelpText.pitchToFit)
                }
            }
            .frame(height: Theme.H.sm)
            SegmentedChips(options: Transpose.range.map { .init(value: $0, title: Transpose.label($0), spoken: Transpose.label($0)) },
                           selected: nil, enabled: shift != nil, width: .fill, marked: 0,
                           lit: Set(Transpose.range.filter { Transpose.lit($0, shift: shift) }))
                .animation(Theme.Motion.swap, value: shift)
                .accessibilityElement(children: .ignore)
                .accessibility(label: Text(spoken))
                .helpTip(HelpText.matchShift)
        }
    }

    /// The result, as a sentence in mixed case (design pass F6); nil = nothing to say yet (no
    /// project key or no reading: the picker and the dim strip already say so).
    static func line(target: String?, shift: Int?) -> String? {
        guard let t = target, let s = shift else { return nil }
        return s == 0 ? "Already fits \(t)" : "Pitch the beat \(Transpose.label(s)) to fit \(t)"
    }

    private var spoken: String {
        guard let t = target else { return "Match to: no project key picked" }
        guard let s = shift else { return "Match to \(t): no key yet" }
        if s == 0 { return "Already fits \(t)" }
        return "Pitch the beat \(s > 0 ? "up" : "down") \(abs(s)) semitone\(abs(s) == 1 ? "" : "s") to fit \(t)"
    }
}

/// The circle of fifths: 12 majors outside, their relative minors inside. The key on show is
/// lit, the runner-ups washed, the keys that fit it (its fifths neighbours and its relative)
/// faintly outlined; a click makes a key THE key (SpellingSettings.choose, the same path as a
/// click on key 2 or 3).
struct KeyWheel: View {
    let keys: [(String, Int)]
    /// Manual Key Selection on show: its section is lit white (not the display colour), hovering
    /// it swaps its name for the reset arrow, and a click there clears it (`onClear`).
    var manual: ManualKey? = nil
    /// Reading > Spell Keys with Sharps (nil = the analyzer's own): the dial's and the top 3's
    /// spelling, for the keys the reading does not list (see `name`).
    var spelling: KeySpelling? = nil
    var onChoose: ((String) -> Void)? = nil
    var onClear: (() -> Void)? = nil

    static let side: CGFloat = 216
    /// Three circles (J, 2026-11-09): the centre holds the Camelot code, minors fill the ring between
    /// `innerRadius` and `middleRadius`, majors the ring between `middleRadius` and `outerRadius`.
    /// A line between every two keys splits each ring into 12 sections; a lit key lights its section.
    /// No MAJOR / MINOR ring labels (J 2026-11-09: the names already say C, Am).
    static let innerRadius: CGFloat = 34
    static let middleRadius: CGFloat = 70
    static let outerRadius: CGFloat = 100

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

    /// The keys that fit the key on show (KeyFit): outlined when they are not lit already.
    var fits: Set<WheelKey> { keys.first.map { KeyFit.keys($0.0) } ?? [] }

    /// The section under the mouse: slot index * 2 + (minor ? 1 : 0). nil = none.
    @State private var hovered: Int?
    /// Offscreen renders: "wheel" hovers the manual section.
    @Environment(\.manualHoverForced) private var forcedHover

    /// The manual section's id (slot index * 2 + minor); nil = no Manual Key Selection.
    var manualSection: Int? {
        guard let m = manual, let i = (0..<12).first(where: { KeyWheel.slot($0, minor: m.minor).pc == m.pitchClass })
        else { return nil }
        return i * 2 + (m.minor ? 1 : 0)
    }

    /// A click on section `id` (slot index * 2 + minor): the white (manual) section clears Manual
    /// Key Selection, any other makes its key the manual one. A section that does not resolve to a
    /// key is logged as an error and changes nothing.
    func click(_ id: Int) {
        guard (0..<24).contains(id) else {
            AppLog.log("ERROR manual key selection: key wheel section \(id) does not resolve to a key; unchanged")
            return
        }
        if id == manualSection, let clear = onClear { clear(); return }
        let s = KeyWheel.slot(id / 2, minor: id % 2 == 1)
        onChoose?(name(s.pc, minor: s.minor))
    }

    var body: some View {
        let fit = fits
        let hover = forcedHover == "wheel" ? manualSection : hovered
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                ForEach([false, true], id: \.self) { minor in
                    let s = KeyWheel.slot(i, minor: minor)
                    KeyWheelSection(index: i, minor: minor, name: name(s.pc, minor: minor),
                                    rank: rank(s.pc, minor: minor),
                                    fit: fit.contains(WheelKey(s.pc, minor: minor)),
                                    manual: manual?.isKey(s.pc, minor: minor) ?? false,
                                    hover: hover == i * 2 + (minor ? 1 : 0),
                                    onChoose: onChoose.map { _ in { _ in click(i * 2 + (minor ? 1 : 0)) } },
                                    onClear: onClear.map { _ in { click(i * 2 + (minor ? 1 : 0)) } })
                }
            }
            KeyWheelGrid().allowsHitTesting(false)
            center
            // SwiftUI's onHover tracks a view's whole frame (every section is the full square), so the
            // section under the mouse is worked out from the mouse position instead.
            if !Pocket.snapshot {   // offscreen renders draw AppKit views as a placeholder
                MouseTracker { p in
                    let id = p.flatMap(KeyWheel.section(at:))
                    if id != hovered { hovered = id }
                }
            }
        }
        .frame(width: KeyWheel.side, height: KeyWheel.side)
        // the hover card rides the surface's card layer, at the mouse (Help.swift)
        .hoverCard(hover.map(tip(for:)), width: 196)
        .accessibilityElement(children: .contain)
        .accessibility(label: Text("Key wheel"))
    }

    /// The pop-up for the hovered section: how sure, and why it is lit (J, 2026-11-09: no extra text
    /// on screen by default; the explanation appears only on hover, at the mouse).
    func tip(for id: Int) -> HelpTip {
        let i = id / 2, minor = id % 2 == 1
        let s = KeyWheel.slot(i, minor: minor)
        let info = info(s.pc, minor: minor)
        return HelpTip(title: info.title, body: info.why)
    }

    /// The section (slot index * 2 + minor) under `p`, in the wheel's own square (y down); nil = the
    /// centre, outside the wheel, or no point.
    static func section(at p: CGPoint) -> Int? {
        let dx = Double(p.x - side / 2), dy = Double(p.y - side / 2)
        let r = CGFloat((dx * dx + dy * dy).squareRoot())
        guard r >= innerRadius, r <= outerRadius else { return nil }
        var a = atan2(dx, -dy) * 180 / .pi            // 0 = top, clockwise
        if a < 0 { a += 360 }
        let i = Int((a + 15) / 30) % 12
        return i * 2 + (r < middleRadius ? 1 : 0)
    }

    /// The name as the wheel spells it: exactly as the dial and the top 3 do (one key, one name
    /// across the window and the pocket). Labels, hover cards and VoiceOver all read this.
    func name(_ pc: Int, minor: Bool) -> String {
        KeyWheel.name(pc, minor: minor, keys: keys, spelling: spelling)
    }

    /// Key (`pc`, `minor`) as reading `keys` (already respelled, the chosen key in front: what the
    /// dial and the top 3 draw) names it; a key the reading does not list gets the analyzer's
    /// name in `spelling` (KeySpelling.respell, the same rule the reading went through). A reading
    /// key whose name does not resolve is skipped and logged once (the fallback spelling stands).
    static func name(_ pc: Int, minor: Bool, keys: [(String, Int)], spelling: KeySpelling?) -> String {
        for k in keys {
            guard let c = AutoTuneSend.keyClass(k.0) else { logUnresolved(k.0); continue }
            if c.pitchClass == pc && c.minor == minor { return k.0.trimmingCharacters(in: .whitespaces) }
        }
        return KeySpelling.respell(KeyChoice.keyName(pc, minor: minor), to: spelling)
    }

    /// Names already logged as unresolved (one line per name, not one per redraw).
    private static var unresolvedLogged = Set<String>()
    private static let unresolvedLock = NSLock()

    private static func logUnresolved(_ name: String) {
        unresolvedLock.lock(); defer { unresolvedLock.unlock() }
        guard unresolvedLogged.insert(name).inserted else { return }
        AppLog.log("ERROR key wheel spelling: reading key \"\(name)\" does not resolve to a key; the wheel keeps its own spelling")
    }

    /// The scale's seven pitch classes.
    static func notes(_ pc: Int, minor: Bool) -> Set<Int> {
        Set((minor ? Scale.naturalMinor : Scale.major).map { ($0 + pc) % 12 })
    }

    /// How sure the reading is of this key (0-100), nil = not one of its top three.
    func percent(_ pc: Int, minor: Bool) -> Int? {
        // the manual key: the analyzer's own %, never the 0 it sits at when it was not detected
        if let m = manual, m.isKey(pc, minor: minor) { return m.detected }
        for k in keys.prefix(3) {
            if let c = AutoTuneSend.keyClass(k.0), c.pitchClass == pc, c.minor == minor { return k.1 }
        }
        return nil
    }

    /// What the hover card says: the key and how sure, then why it relates to the key on show.
    func info(_ pc: Int, minor: Bool) -> (title: String, why: String) {
        let name = self.name(pc, minor: minor)
        let title = percent(pc, minor: minor).map { "\(name) · \($0)% SURE" } ?? name
        if let m = manual, m.isKey(pc, minor: minor) {
            // Manual Key Selection (J 2026-11-09 15:19): the lock line, then what a click does
            return (title, "\(HelpText.manualLocked) \(HelpText.manualWheelReset)")
        }
        guard let k = keys.first?.0, let t = AutoTuneSend.keyClass(k) else {
            return (title, "Click to use it as the key.")
        }
        if t.pitchClass == pc && t.minor == minor {
            return (title, "Beat Key's pick: the closest match to what it heard.")
        }
        let topName = self.name(t.pitchClass, minor: t.minor)
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

    /// The key on show's Camelot code in the middle (the wheel's own numbering; what it is lives
    /// in the help tip, not in a printed CAMELOT label).
    private var center: some View {
        ZStack {
            if let k = keys.first?.0, let code = Camelot.code(k) {
                Crossfade(code) { code in
                    Text(code).font(Theme.T.value).foregroundColor(Theme.A.a2)
                }
            }
        }
        .frame(width: KeyWheel.innerRadius * 2, height: KeyWheel.innerRadius * 2)
        .contentShape(Circle())
        .helpTip(HelpText.camelot)
        .accessibility(hidden: true)
    }
}

/// One ring section between two lines: centred on slot `index` (0 = top, clockwise), 30° wide,
/// from `inner` to `outer` radius, in the wheel's own square. `inset` pulls every edge in (the
/// fit outline sits inside the grid lines).
struct RingSector: Shape {
    let index: Int
    let inner: CGFloat
    let outer: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let mid = Double(index) * 30 - 90          // SwiftUI angles start at 3 o'clock, y down
        let r0 = inner + inset, r1 = outer - inset
        // the side edges move in by `inset` at each radius
        let d0 = Double(inset / r0) * 180 / .pi, d1 = Double(inset / r1) * 180 / .pi
        var p = Path()
        p.addArc(center: c, radius: r1, startAngle: .degrees(mid - 15 + d1), endAngle: .degrees(mid + 15 - d1), clockwise: false)
        p.addArc(center: c, radius: r0, startAngle: .degrees(mid + 15 - d0), endAngle: .degrees(mid - 15 + d0), clockwise: true)
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
            var lines = Path()
            for i in 0..<12 {
                let a = (Double(i) * 30 - 90 + 15) * .pi / 180
                lines.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * r0, y: c.y + CGFloat(sin(a)) * r0))
                lines.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r2, y: c.y + CGFloat(sin(a)) * r2))
            }
            ctx.stroke(circles, with: .color(Theme.A.a4), lineWidth: 1)
            ctx.stroke(lines, with: .color(Theme.A.a4), lineWidth: 1)
        }
        .frame(width: KeyWheel.side, height: KeyWheel.side)
    }
}

/// One key's section: lit whole when it is the key (solid, glowing), an A4 wash for a runner-up,
/// a faint inset outline for a key that fits (quieter than a runner-up), an A4 wash on hover; the
/// light eases in and out instead of jumping.
private struct KeyWheelSection: View {
    let index: Int
    let minor: Bool
    /// The key's name as the dial and the top 3 spell it (KeyWheel.name).
    let name: String
    let rank: Int?
    let fit: Bool
    /// The Manual Key Selection: lit white instead of the display colour.
    var manual = false
    let hover: Bool
    let onChoose: ((String) -> Void)?
    var onClear: (() -> Void)? = nil

    var body: some View {
        let inner = minor ? KeyWheel.innerRadius : KeyWheel.middleRadius
        let outer = minor ? KeyWheel.middleRadius : KeyWheel.outerRadius
        let shape = RingSector(index: index, inner: inner, outer: outer)
        let fill: Color = manual ? ManualLook.white
            : rank == 0 ? Theme.A.a1 : (rank == 1 || (hover && onChoose != nil)) ? Theme.A.a4 : .clear
        let mid = Double(index) * .pi / 6, r = (inner + outer) / 2
        let ink: Color = manual ? ManualLook.ink
            : rank == 0 ? Theme.A.ink : (rank == 1 || hover) ? Theme.A.a1 : fit ? Theme.A.a2 : Theme.A.a3
        let glow: Color = manual ? ManualLook.glow : rank == 0 && !Theme.highContrast ? Theme.amberGlow : .clear
        // Manual Key Selection hovered: the name gives way to the reset arrow (Motion.hover)
        let resetting = manual && hover && onClear != nil
        let label = ZStack {
            Text(name).font(Theme.face(minor ? Theme.T.captionSize : Theme.T.valueSize))
                .lineLimit(1).minimumScaleFactor(0.8)
                .opacity(resetting ? 0 : 1)
            Image(systemName: ManualLook.resetSymbol)
                .font(.system(size: minor ? 10 : 13, weight: .bold))
                .opacity(resetting ? 1 : 0)
        }
            .foregroundColor(ink)
            .frame(width: minor ? 30 : 36)
            .offset(x: CGFloat(sin(mid)) * r, y: -CGFloat(cos(mid)) * r)
            .animation(Theme.Motion.hover, value: resetting)
        let body = ZStack {
            shape.fill(fill)
                .shadow(color: glow, radius: 5)
            if fit && rank == nil {
                RingSector(index: index, inner: inner, outer: outer, inset: 2.5)
                    .stroke(Theme.A.a3, lineWidth: 1)
            }
            label
        }
        .frame(width: KeyWheel.side, height: KeyWheel.side)
        .contentShape(shape)
        .animation(Theme.Motion.swap, value: rank)
        .animation(Theme.Motion.swap, value: manual)
        .animation(Theme.Motion.swap, value: fit)
        .animation(Theme.Motion.hover, value: hover)
        let spoken = "\(minor ? String(name.dropLast()) : name) \(minor ? "minor" : "major")"
        let role = manual ? ", the key, selected manually" : rank == 0 ? ", the key" : rank == 1 ? ", a runner-up" : fit ? ", fits the key" : ""
        return Group {
            if manual, let clear = onClear {
                // a click on the white section clears Manual Key Selection
                Button(action: clear) { body }
                    .buttonStyle(KeyWheelPress())
                    .pointingHand()
                    .accessibility(label: Text(spoken + role))
                    .accessibility(hint: Text("Resets the manual selection: Beat Key detects the key again"))
                    .accessibility(addTraits: .isSelected)
            } else if let choose = onChoose {
                Button(action: { choose(name) }) { body }
                    .buttonStyle(KeyWheelPress())
                    .pointingHand()
                    .accessibility(label: Text(spoken + role))
                    .accessibility(hint: Text("Makes it the key"))
                    .accessibility(addTraits: rank == 0 ? .isSelected : [])
            } else {
                body.accessibility(label: Text(spoken))
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
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<12, id: \.self) { pc in
                let inScale = scale?.notes.contains(pc) ?? false
                let tonic = scale?.tonic == pc
                VStack(spacing: Theme.S.xs) {
                    GeometryReader { g in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 1.5).fill(Theme.A.a5)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(tonic ? Theme.A.a1 : inScale ? Theme.A.a2 : Theme.A.a4)
                                .frame(height: max(2, g.size.height * CGFloat(lv[pc])))
                                .animation(Theme.Motion.value, value: lv[pc])
                        }
                    }
                    .padding(.horizontal, 1)
                    Crossfade(scale?.name(pc) ?? Scale.sharpNames[pc]) { n in
                        Text(n).font(Theme.T.caption).fixedSize()
                            .foregroundColor(inScale ? Theme.A.a2 : Theme.A.a3)
                    }
                    .frame(height: 12)
                    Circle().fill(inScale ? Theme.A.a2 : .clear).frame(width: 3, height: 3)
                }
                .frame(maxWidth: .infinity)
            }
        }
        // in-scale / not-in-scale colours crossfade with the key (heights ease per bar above)
        .animation(Theme.Motion.swap, value: scale)
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text(spoken(lv)))
    }

    private func spoken(_ lv: [Double]) -> String {
        let order = (0..<12).filter { lv[$0] > 0.05 }.sorted { lv[$0] > lv[$1] }.prefix(7)
        let names = order.map { scale?.name($0) ?? Scale.sharpNames[$0] }
        return names.isEmpty ? "Notes heard: none" : "Notes heard, strongest first: " + names.joined(separator: ", ")
    }
}

/// Reports the mouse position (view coordinates, y down) while it moves over this view, nil when it
/// leaves. Lets clicks through (hitTest nil); the tracking area still gets the moves.
struct MouseTracker: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackView {
        let v = TrackView()
        v.onMove = onMove
        return v
    }

    func updateNSView(_ v: TrackView, context: Context) { v.onMove = onMove }

    final class TrackView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }

        override func mouseEntered(with e: NSEvent) { onMove?(convert(e.locationInWindow, from: nil)) }
        override func mouseMoved(with e: NSEvent) { onMove?(convert(e.locationInWindow, from: nil)) }
        override func mouseExited(with e: NSEvent) { onMove?(nil) }
    }
}
