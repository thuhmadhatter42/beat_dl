import AppKit
import Combine
import CoreMIDI
import SwiftUI

// Beat Key Mini (J, 2026-11-09): "a mini button next to the keys button … the Beat Key keys show
// up as a mini device … and it plays those chords into MIDI, so someone can have an instrument
// live in their DAW and Beat Key can just play it." MINI (the chord strip's header) opens a small
// always-on-top panel with the current key's 7 + 4 chords as pads. Hold a pad (or keys 1-7,
// Q W E R) and its chord plays out of a CoreMIDI virtual source named "Beat Key"; let go and the
// notes stop. SOUND also plays them on the built-in piano. Pure pieces first (tested), then the
// MIDI port, the controller, the panel and its view.

// MARK: the pads and their keys (pure)

/// One pad: a diatonic chord (0...6, I to VII) or a borrowed one (0...3, left to right).
enum MiniPad: Hashable {
    case diatonic(Int)
    case borrowed(Int)
}

/// The computer keys while the panel is key: 1-7 play the row, Q W E R the borrowed chords.
enum MiniKeys {
    static let diatonic = ["1", "2", "3", "4", "5", "6", "7"]
    static let borrowed = ["q", "w", "e", "r"]

    /// The pad a key plays (`charactersIgnoringModifiers`, any case); nil = not a pad key.
    static func pad(for characters: String) -> MiniPad? {
        let c = characters.lowercased()
        if let i = diatonic.firstIndex(of: c) { return .diatonic(i) }
        if let i = borrowed.firstIndex(of: c) { return .borrowed(i) }
        return nil
    }

    /// The key printed on a pad: "1", "Q".
    static func hint(_ pad: MiniPad) -> String {
        switch pad {
        case .diatonic(let i): return diatonic.indices.contains(i) ? diatonic[i] : ""
        case .borrowed(let i): return borrowed.indices.contains(i) ? borrowed[i].uppercased() : ""
        }
    }
}

/// What the Mini shows for a key: the window's chord grid (seven chords; the borrowed row on
/// the same seven columns, each under the degree it stands in for).
struct MiniLayout: Equatable {
    let diatonic: [Chord]
    /// Seven slots (Harmony.borrowedRow); nil = an empty column.
    let borrowed: [Chord?]

    init(key: String?, quality: ChordQuality) {
        diatonic = key.map { Harmony.diatonic($0, quality: quality) } ?? []
        borrowed = key.map { Harmony.borrowedRow($0, quality: quality) } ?? []
    }

    var isEmpty: Bool { diatonic.isEmpty }

    /// Borrowed pad i = the i-th borrowed chord left to right.
    func chord(_ pad: MiniPad) -> Chord? {
        switch pad {
        case .diatonic(let i): return diatonic.indices.contains(i) ? diatonic[i] : nil
        case .borrowed(let i):
            let row = borrowed.compactMap { $0 }
            return row.indices.contains(i) ? row[i] : nil
        }
    }

    /// The pad a borrowed column holds; nil = empty column.
    func borrowedPad(column: Int) -> MiniPad? {
        guard borrowed.indices.contains(column), borrowed[column] != nil else { return nil }
        return .borrowed(borrowed[..<column].filter { $0 != nil }.count)
    }
}

// MARK: MIDI messages and the held-note book (pure)

/// One note starting or stopping.
enum NoteEvent: Equatable {
    case on(Int)
    case off(Int)
}

enum MidiMessage {
    /// The Mini plays at this velocity on channel 1.
    static let velocity: UInt8 = 100
    static let channel: UInt8 = 0

    /// The three MIDI 1.0 bytes: 0x9n note vel (on) / 0x8n note 0 (off), n = channel 0...15.
    static func bytes(_ e: NoteEvent, velocity: UInt8 = MidiMessage.velocity, channel: UInt8 = MidiMessage.channel) -> [UInt8] {
        let ch = channel & 0x0f
        switch e {
        case .on(let n): return [0x90 | ch, UInt8(clamping: max(0, min(127, n))), min(velocity, 127)]
        case .off(let n): return [0x80 | ch, UInt8(clamping: max(0, min(127, n))), 0]
        }
    }

    /// The same message as one Universal MIDI Packet word (type 2, MIDI 1.0 channel voice, group 0),
    /// what CoreMIDI's event lists carry.
    static func ump(_ bytes: [UInt8]) -> UInt32 {
        guard bytes.count == 3 else { return 0 }
        return 0x2000_0000 | UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2])
    }
}

/// Which pads are held and which notes are sounding. A note two held chords share starts once
/// and stops only when the last of them lets go, so every note-on gets exactly one note-off.
struct HeldNotes {
    private(set) var pads: [MiniPad: [Int]] = [:]
    private(set) var counts: [Int: Int] = [:]

    var sounding: Set<Int> { Set(counts.keys) }
    var isEmpty: Bool { pads.isEmpty }

    /// Holds `pad` with `notes`; a pad already held is let go first (its notes restart).
    mutating func press(_ pad: MiniPad, notes: [Int]) -> [NoteEvent] {
        var out = release(pad)
        let unique = Array(Set(notes.map { max(0, min(127, $0)) })).sorted()
        pads[pad] = unique
        for n in unique {
            let c = counts[n, default: 0]
            if c == 0 { out.append(.on(n)) }
            counts[n] = c + 1
        }
        return out
    }

    /// Lets go of `pad`: offs for the notes no other held pad still holds.
    mutating func release(_ pad: MiniPad) -> [NoteEvent] {
        guard let notes = pads.removeValue(forKey: pad) else { return [] }
        var out: [NoteEvent] = []
        for n in notes {
            let c = counts[n, default: 0] - 1
            if c <= 0 { counts[n] = nil; out.append(.off(n)) } else { counts[n] = c }
        }
        return out
    }

    /// Everything off (panel closed, key changed, app quitting).
    mutating func allOff() -> [NoteEvent] {
        let out = counts.keys.sorted().map { NoteEvent.off($0) }
        pads = [:]; counts = [:]
        return out
    }
}

// MARK: the MIDI port

/// The virtual MIDI source "Beat Key" every DAW lists as an input. Made the first time MINI
/// opens and kept for the app's life. Every CoreMIDI error is logged with its OSStatus; none
/// crashes (the Mini just stays silent on MIDI and says so).
final class MidiOut {
    static let shared = MidiOut()
    static let sourceName = "Beat Key"
    /// A fixed ID so DAWs remember the input across launches ("BeKy").
    static let uniqueID: MIDIUniqueID = 0x4265_4B79

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private(set) var ready = false

    /// Makes the client and the source (once); false = MIDI is unavailable (logged).
    @discardableResult
    func start() -> Bool {
        if ready { return true }
        var c = MIDIClientRef()
        var st = MIDIClientCreateWithBlock("Beat Key" as CFString, &c, nil)
        guard st == noErr else {
            AppLog.log("mini midi: MIDIClientCreate failed (OSStatus \(st))")
            return false
        }
        var s = MIDIEndpointRef()
        st = MIDISourceCreateWithProtocol(c, MidiOut.sourceName as CFString, ._1_0, &s)
        guard st == noErr else {
            AppLog.log("mini midi: MIDISourceCreate failed (OSStatus \(st))")
            let d = MIDIClientDispose(c)
            if d != noErr { AppLog.log("mini midi: MIDIClientDispose failed (OSStatus \(d))") }
            return false
        }
        st = MIDIObjectSetIntegerProperty(s, kMIDIPropertyUniqueID, MidiOut.uniqueID)
        if st != noErr { AppLog.log("mini midi: fixed unique ID not set (OSStatus \(st)); the DAW may list it as new") }
        client = c; source = s; ready = true
        AppLog.log("mini midi: virtual source \"\(MidiOut.sourceName)\" created")
        return true
    }

    /// Sends the events now, on channel 1 at the Mini's velocity.
    func send(_ events: [NoteEvent]) {
        guard ready, !events.isEmpty else { return }
        let size = 64 + events.count * 16
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIEventList.self, capacity: 1)
        var packet: UnsafeMutablePointer<MIDIEventPacket>? = MIDIEventListInit(list, ._1_0)
        for e in events {
            guard let p = packet else { break }
            var word = MidiMessage.ump(MidiMessage.bytes(e))
            packet = MIDIEventListAdd(list, size, p, 0, 1, &word)
        }
        if packet == nil { AppLog.log("mini midi: event list full, \(events.count) events cut short") }
        let st = MIDIReceivedEventList(source, list)
        if st != noErr { AppLog.log("mini midi: MIDIReceived failed (OSStatus \(st))") }
    }
}

// MARK: the controller

/// What the Mini plays from: the window's reading and chord choices.
struct MiniFeed: Equatable {
    var key: String?
    var quality: ChordQuality
    var voicing: Voicing
}

/// What the Mini's view draws (plain values, so offscreen renders need no panel).
struct MiniViewState: Equatable {
    var key: String?
    var layout: MiniLayout
    var lit: Set<MiniPad> = []
    var sound = false
    var midiReady = true
    var help = false
}

/// Opens and closes the panel, follows the reading, holds the pads and sends their notes.
/// Main thread only.
final class MiniController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = MiniController()
    static let soundKey = "miniSound"

    @Published private(set) var isOpen = false
    @Published private(set) var view = MiniViewState(key: nil, layout: MiniLayout(key: nil, quality: .triad))

    private let defaults: UserDefaults
    private var panel: MiniPanel?
    private var held = HeldNotes()
    private var feed = MiniFeed(key: nil, quality: .triad, voicing: .root)
    private var source: (() -> MiniFeed)?
    private var watch: AnyCancellable?
    private var helpWatch: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        view.sound = defaults.bool(forKey: MiniController.soundKey)   // default off: MIDI is the point
    }

    /// MINI: open the panel (fed by `source`, re-read whenever `changes` fires) or close it.
    func toggle(source: @escaping () -> MiniFeed, changes: AnyPublisher<Void, Never>) {
        if isOpen { close(from: "MINI") } else { open(source: source, changes: changes) }
    }

    func open(source: @escaping () -> MiniFeed, changes: AnyPublisher<Void, Never>) {
        view.midiReady = MidiOut.shared.start()
        self.source = source
        // objectWillChange fires before the change lands: read on the next turn of the run loop
        watch = changes.receive(on: DispatchQueue.main).sink { [weak self] in self?.refresh() }
        helpWatch = HelpSettings.shared.$isOn.sink { [weak self] on in self?.view.help = on }
        refresh()
        let p = panel ?? makePanel()
        panel = p
        p.orderFrontRegardless()
        isOpen = true
        AppLog.log("mini: panel opened (\(feed.key ?? "no key"), midi \(view.midiReady ? "on" : "unavailable"))")
    }

    func close(from place: String) {
        panel?.close()   // windowWillClose does the rest
        if isOpen { didClose(place) }
    }

    func windowWillClose(_ n: Notification) { if isOpen { didClose("close button") } }

    private func didClose(_ place: String) {
        allOff("panel closed")
        isOpen = false
        watch = nil; helpWatch = nil; source = nil
        AppLog.log("mini: panel closed (\(place))")
    }

    /// The reading or the chord choices changed: new pads; a new key stops what was held.
    func refresh() {
        guard let f = source?() else { return }
        guard f != feed else { return }
        if f.key != feed.key, !held.isEmpty { allOff("key changed") }
        feed = f
        view.key = f.key
        view.layout = MiniLayout(key: f.key, quality: f.quality)
    }

    // MARK: playing

    func press(_ pad: MiniPad, via how: String) {
        guard let c = view.layout.chord(pad) else { return }
        emit(held.press(pad, notes: c.notes(feed.voicing)))
        view.lit = Set(held.pads.keys)
        AppLog.log("mini: \(c.asciiName) down (\(how))")
    }

    func release(_ pad: MiniPad) {
        emit(held.release(pad))
        view.lit = Set(held.pads.keys)
    }

    /// Every sounding note off (and logged when there were any).
    func allOff(_ why: String) {
        let offs = held.allOff()
        view.lit = []
        guard !offs.isEmpty else { return }
        emit(offs)
        AppLog.log("mini: all notes off (\(why), \(offs.count) notes)")
    }

    /// App quit: nothing left hanging in the DAW.
    func shutdown() { allOff("app quit") }

    func toggleSound() {
        if view.sound { NoteSynth.shared.held.forEach { NoteSynth.shared.noteOff($0) } }
        view.sound.toggle()
        defaults.set(view.sound, forKey: MiniController.soundKey)
        if view.sound { held.sounding.forEach { NoteSynth.shared.noteOn($0, velocity: MidiMessage.velocity) } }
        AppLog.log("mini: sound \(view.sound ? "on" : "off")")
    }

    private func emit(_ events: [NoteEvent]) {
        guard !events.isEmpty else { return }
        MidiOut.shared.send(events)
        guard view.sound else { return }
        for e in events {
            switch e {
            case .on(let n): NoteSynth.shared.noteOn(n, velocity: MidiMessage.velocity)
            case .off(let n): NoteSynth.shared.noteOff(n)
            }
        }
    }

    // MARK: the panel

    private func makePanel() -> MiniPanel {
        let host = FirstMouseHostingView(rootView: MiniHost(controller: self))
        let size = host.fittingSize
        let p = MiniPanel(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        p.title = "Beat Key Mini"
        p.contentView = host
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false            // it lives over the DAW
        p.becomesKeyOnlyIfNeeded = false        // a click makes it key so 1-7 / QWER work
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.appearance = NSAppearance(named: .darkAqua)
        p.backgroundColor = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1)
        p.delegate = self
        p.onKey = { [weak self] pad, down in
            guard let self else { return }
            if down { self.press(pad, via: "key") } else { self.release(pad) }
        }
        p.onResign = { [weak self] in self?.allOff("panel lost focus") }
        p.setFrameAutosaveName("BeatKeyMini")
        if !p.setFrameUsingName("BeatKeyMini") { p.center() }
        return p
    }
}

/// The floating panel: keys 1-7 and Q W E R press pads while it is key (repeats ignored);
/// losing key lets everything go (a key-up may never arrive).
final class MiniPanel: NSPanel {
    var onKey: ((MiniPad, Bool) -> Void)?
    var onResign: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with e: NSEvent) {
        if let pad = pad(e) { if !e.isARepeat { onKey?(pad, true) } } else if e.keyCode == 53 { performClose(nil) } else { super.keyDown(with: e) }
    }

    override func keyUp(with e: NSEvent) {
        if let pad = pad(e) { onKey?(pad, false) } else { super.keyUp(with: e) }
    }

    override func resignKey() {
        super.resignKey()
        onResign?()
    }

    private func pad(_ e: NSEvent) -> MiniPad? {
        guard e.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        return MiniKeys.pad(for: e.charactersIgnoringModifiers ?? "")
    }
}

/// The first click on a pad plays it even though the panel is not key (the DAW keeps focus).
final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct MiniHost: View {
    @ObservedObject var controller: MiniController

    var body: some View {
        MiniView(state: controller.view,
                 press: { controller.press($0, via: "pad") },
                 release: { controller.release($0) },
                 toggleSound: { controller.toggleSound() })
    }
}

// MARK: the view

/// The Mini's face: the key and SOUND on top, then the pads (the window's chord grid, with the
/// computer key on each), on Beat Key's amber LCD glass.
struct MiniView: View {
    let state: MiniViewState
    var press: (MiniPad) -> Void = { _ in }
    var release: (MiniPad) -> Void = { _ in }
    var toggleSound: () -> Void = {}

    static let padWidth: CGFloat = 54
    static let padHeight: CGFloat = 46
    static let gap: CGFloat = 4
    static var gridWidth: CGFloat { padWidth * 7 + gap * 6 }

    private var scale: Scale? { state.key.flatMap(Scale.of) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if state.layout.isEmpty {
                Text("NO KEY YET · READ A BEAT IN THE WINDOW").font(Theme.face(8)).tracking(1.4)
                    .foregroundColor(Theme.amber(0.3))
                    .frame(width: MiniView.gridWidth, height: MiniView.padHeight * 2 + 26)
            } else {
                ChordGrid(diatonic: state.layout.diatonic, borrowed: state.layout.borrowed, gap: MiniView.gap,
                          cellHeight: MiniView.padHeight, rowTip: HelpText.miniPanel, borrowedTip: HelpText.miniPanel) { c, tonic in
                    pad(c, tonic: tonic)
                }
                .frame(width: MiniView.gridWidth)
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 12)
        .lcdGlass(radius: 5)
        .padding(10)
        .background(Theme.desk)
        .environment(\.helpMode, state.help)
        .helpTipLayer()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(scale.map { "\($0.tonicName) \($0.minor ? "MINOR" : "MAJOR")" } ?? "NO KEY")
                .font(Theme.face(13)).tracking(1).foregroundColor(Theme.amber(scale == nil ? 0.35 : 1))
                .modifier(PocketGlow(on: scale != nil))
                .helpTip(HelpText.miniPanel)
            Text(state.midiReady ? "MIDI OUT · \(MidiOut.sourceName.uppercased())" : "MIDI UNAVAILABLE · SEE LOG")
                .font(Theme.face(6.5)).tracking(1.4)
                .foregroundColor(state.midiReady ? Theme.amber(0.42) : Theme.redText)
                .lineLimit(1)
            Spacer(minLength: 0)
            LCDChip(title: "SOUND", on: state.sound, label: state.sound ? "Built-in sound on" : "Built-in sound off",
                    width: 40, action: toggleSound)
                .helpTip(HelpText.miniSound)
        }
    }

    private func pad(_ c: Chord, tonic: Bool) -> some View {
        let p: MiniPad? = c.borrowed
            ? state.layout.borrowed.firstIndex(where: { $0 == c }).flatMap { state.layout.borrowedPad(column: $0) }
            : state.layout.diatonic.firstIndex(of: c).map { MiniPad.diatonic($0) }
        return MiniPadView(chord: c, tonic: tonic, pad: p, lit: p.map { state.lit.contains($0) } ?? false,
                           press: press, release: release)
    }
}

/// One pad: down = play, up = stop (hold to sustain).
private struct MiniPadView: View {
    let chord: Chord
    let tonic: Bool
    let pad: MiniPad?
    let lit: Bool
    let press: (MiniPad) -> Void
    let release: (MiniPad) -> Void
    @State private var down = false

    var body: some View {
        ChordFace(chord: chord, tonic: tonic, lit: lit, hint: pad.map(MiniKeys.hint), height: MiniView.padHeight)
            .frame(width: MiniView.padWidth)
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !down, let p = pad else { return }
                    down = true; press(p)
                }
                .onEnded { _ in
                    guard down, let p = pad else { return }
                    down = false; release(p)
                })
            .accessibilityElement(children: .ignore)
            .accessibility(label: Text("\(chord.name), \(chord.roman)\(chord.borrowed ? ", borrowed" : "")"))
            .accessibility(hint: Text("Plays the chord into MIDI while held"))
            .accessibility(addTraits: .isButton)
            .accessibilityAction(.default) {
                guard let p = pad else { return }
                press(p)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { release(p) }
            }
    }
}
