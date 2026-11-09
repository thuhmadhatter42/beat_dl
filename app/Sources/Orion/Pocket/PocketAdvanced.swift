import AppKit
import Combine
import SwiftUI

// Advanced mode on both surfaces (J 2026-11-09): an ADVANCED box at the right of each footer,
// the window's and the menu-bar pocket's own setting (DisplaySettings.advanced / pocketAdvanced;
// the first change each launch sets both), and the harmony wiring both share.

extension PocketActions {
    /// The harmony pieces' actions (chords heard and dragged, chord choices, MATCH TO, MINI), the
    /// same for the window's column and the pocket's. `surface` names the log lines.
    mutating func wireHarmony(surface: String, engine e: Engine, model m: FaceplateModel, live l: LiveController,
                              display d: DisplaySettings) {
        let shown = { PocketState.shown(e.state, live: l.state, page: m.pager) }
        playChord = { chord in
            let bpm = ChordClip.bpm(shown(), factor: m.tempoFactor)
            AppLog.log("\(surface): chord \(chord.asciiName) played (\(d.chordVoicing.rawValue), \(d.chordBars) bar)")
            NoteSynth.shared.play(chord.notes(d.chordVoicing), seconds: ChordClip.hearSeconds(bars: d.chordBars, bpm: bpm))
        }
        chordFile = { chord in
            let r = shown()
            let bpm = ChordClip.bpm(r, factor: m.tempoFactor)
            let url = ChordClip.write(chord, voicing: d.chordVoicing, bars: d.chordBars, bpm: bpm, key: r?.keys.first?.0)
            if url != nil { AppLog.log("\(surface): chord \(chord.asciiName) dragged as a MIDI clip") }
            else { AppLog.log("\(surface): chord \(chord.asciiName) MIDI clip could not be written") }
            return url
        }
        toggleMini = {
            let sp = SpellingSettings.shared
            let changes = Publishers.MergeMany([e.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                                                l.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                                                m.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                                                d.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                                                sp.objectWillChange.map { _ in () }.eraseToAnyPublisher()])
                .eraseToAnyPublisher()
            MiniController.shared.toggle(source: {
                MiniFeed(key: shown()?.keys.first?.0, quality: d.chordQuality, voicing: d.chordVoicing)
            }, changes: changes)
        }
        setHarmony = { p in
            AppLog.log("\(surface): chords \(p.quality.rawValue) \(p.voicing.rawValue) \(p.bars) bar")
            p.apply(to: d)
        }
        pickMatchKey = {
            AppLog.log("\(surface): match to menu")
            let items = KeyChoice.allKeys.enumerated().flatMap { i, k -> [PopupMenu.Item] in
                let item = PopupMenu.Item(title: k, checked: d.matchKey == k) {
                    AppLog.log("\(surface): match to \(k)")
                    d.matchKey = k
                }
                return i == 12 ? [.separator, item] : [item]
            }
            PopupMenu.show(items + [.separator, PopupMenu.Item(title: "None", checked: d.matchKey == nil) { d.matchKey = nil }])
        }
    }
}

/// The pocket's Advanced pieces: the window's harmony column in its compact fit, under the send
/// caps. The pocket grows taller; on a screen too short for all of it, this part scrolls so the
/// popover never runs off the screen.
struct PocketHarmony: View {
    let state: PocketState
    let actions: PocketActions
    /// The panel's own height, measured (an estimate until the first layout).
    @State private var natural: CGFloat = 560

    /// The pocket without the harmony part (readout, rows, caps, footer, padding) and the
    /// popover's arrow and a margin: what the screen must keep for them.
    static func available(screen: CGFloat, listening: Bool) -> CGFloat {
        screen - 622 - Theme.S.l - 28 - (listening ? 36 : 0)
    }

    var body: some View {
        if Pocket.snapshot {
            panel
        } else {
            let screen = NSScreen.main?.visibleFrame.height ?? 900
            let limit = max(200, PocketHarmony.available(screen: screen, listening: state.listening))
            if natural <= limit {
                panel.background(measure)
            } else {
                ScrollView(.vertical, showsIndicators: true) { panel.background(measure) }
                    .frame(height: limit)
            }
        }
    }

    private var panel: some View { HarmonyPanel(state: state, actions: actions, compact: true) }

    private var measure: some View {
        GeometryReader { g in
            Color.clear.onAppear { natural = g.size.height }
                .onChange(of: g.size.height) { natural = $0 }
        }
    }
}

/// ADVANCED at the right end of the footer: a small square box (ticked when on) and its label, the
/// footer's caption type and height, in the display colour so it follows COLOR.
struct AdvancedBox: View {
    let on: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.S.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(on ? Theme.amber : Color.clear)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(on ? Color.clear : hover ? Theme.A.a1 : Theme.A.a2, lineWidth: 1)
                    if on {
                        CheckMark().stroke(Theme.A.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                            .padding(2)
                    }
                }
                .frame(width: 10, height: 10)
                Text("ADVANCED").captionStyle()
                    .foregroundColor(on || hover ? Theme.A.a1 : Theme.A.a2)
                    .lineLimit(1).fixedSize()
            }
            .frame(height: Theme.H.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover = $0 }
        .pointingHand()
        .nativeHelp("Advanced mode: the key wheel, chords and MATCH TO")
        .helpTip(HelpText.advanced)
        .accessibility(label: Text("Advanced mode"))
        .accessibility(value: Text(on ? "on" : "off"))
        .accessibility(hint: Text(on ? "Hides the key wheel, chords and Match To" : "Shows the key wheel, chords and Match To"))
        .accessibility(addTraits: on ? .isSelected : [])
    }
}

private struct CheckMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY + r.height * 0.05))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.maxY - r.height * 0.1))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.1))
        return p
    }
}
