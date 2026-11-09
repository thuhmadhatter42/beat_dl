import AppKit
import SwiftUI

// Help mode (J, 2026-11-09): a HELP chip in the window's and the pocket's footer (and View › Help
// Mode). Off = the faceplate as it is, no extra text. On = hovering anything explainable shows a
// short amber card, the key wheel's own hover card look. One table (HelpText) holds every line;
// one modifier (.helpTip) attaches them; one layer per surface (.helpTipLayer) draws the card
// above every other view, kept inside the surface and off the control it explains.

/// Help mode on / off, remembered between launches (UserDefaults `helpMode`, default off).
final class HelpSettings: ObservableObject {
    static let key = "helpMode"
    static let shared = HelpSettings()
    private let defaults: UserDefaults

    @Published var isOn: Bool {
        didSet {
            guard isOn != oldValue else { return }
            defaults.set(isOn, forKey: HelpSettings.key)
            AppLog.log("help mode \(isOn ? "on" : "off")")
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let v = defaults.object(forKey: HelpSettings.key), !(v is Bool) && !(v is NSNumber) {
            AppLog.log("help mode: stored value is not a switch; starting off")
            defaults.removeObject(forKey: HelpSettings.key)
        }
        isOn = defaults.bool(forKey: HelpSettings.key)
    }

    /// The HELP chip (window or pocket) or the View menu.
    func toggle(from place: String) {
        AppLog.log("help mode toggled from \(place)")
        isOn.toggle()
    }
}

/// One explanation: a short title (the control's legend) and one or two plain sentences.
struct HelpTip: Equatable {
    let title: String
    let body: String
    var id: String { title }

    /// The longest line a card holds comfortably (1-2 sentences).
    static let maxBody = 140
}

/// Every help line, in one place to edit and test (≤ 140 characters, about 20 words each).
enum HelpText {
    // the readout
    static let bpm = HelpTip(title: "BPM", body: "The beat's tempo in beats per minute. Click it to switch between normal, double and half time.")
    static let bpmRounded = HelpTip(title: "ROUNDED BPM", body: "The tempo rounded to a whole number, the way most DAW sessions are set.")
    static let tempoFactor = HelpTip(title: "×0.5 · ×1 · ×2", body: "Halve or double the BPM when the beat feels twice as fast or slow as the number shown.")
    static let keyDial = HelpTip(title: "KEY", body: "The key Beat Key hears; the ring and % show how sure it is. Click a sharp or flat key to swap its spelling.")
    static let confidence = HelpTip(title: "LOCKED · UNSURE", body: "How sure the key is. LOCKED = confident. UNSURE = a close call, so check the runner-up keys.")
    static let topKeys = HelpTip(title: "TOP KEYS", body: "The three likeliest keys and how sure Beat Key is of each. Click 2 or 3 to use that key instead.")
    static let manual = HelpTip(title: "MANUAL", body: "Pick the key by hand from all 24. Your pick becomes the key and helps teach Beat Key.")
    static let keyboard = HelpTip(title: "KEYBOARD", body: "The key's scale, root dotted. Play notes on your Mac keys A W S E D F T G Y H U J K: the last note is the root. Space flips major/minor.")
    static let scale = HelpTip(title: "SCALE", body: "The key's seven notes, spelled the way the key is written.")
    static let tuning = HelpTip(title: "TUNING", body: "How many cents the beat sits off standard pitch (100 = a semitone), from the A shown. Set A in Reading › Reference Pitch.")
    static let camelot = HelpTip(title: "CAMELOT · REL", body: "The key's Camelot code for DJ mixing: neighbouring codes blend well. REL is the relative key, same notes.")
    static let fileLine = HelpTip(title: "FILE", body: "The file that was read and its folder. While listening, the source being heard.")
    static let showInFinder = HelpTip(title: "SHOW IN FINDER", body: "Opens the file's folder in Finder with the file selected.")
    static let status = HelpTip(title: "STATUS", body: "READY = waiting. WORKING = downloading or reading. FAILED = see the readout. LIVE = listening.")

    // getting audio in
    static let linkField = HelpTip(title: "LINK", body: "Paste a YouTube link. Beat Key downloads it as an MP3 into Downloads and reads its BPM and key.")
    static let download = HelpTip(title: "DOWNLOAD", body: "Downloads the link as an MP3 and reads it. With the field empty, it takes the link on your clipboard.")
    static let openAudio = HelpTip(title: "OPEN AUDIO", body: "Choose audio files on your Mac, then press FIND KEY/BPM. You can also drop files on the window.")
    static let findKey = HelpTip(title: "FIND KEY/BPM", body: "Reads the BPM and key of the audio you chose. Several files? Page through them with the arrows.")
    static let analyzeFile = HelpTip(title: "ANALYZE FILE", body: "Pick an audio file on your Mac; the window opens and reads its BPM and key.")
    static let source = HelpTip(title: "SOURCE", body: "What LISTEN hears: System Audio or an input. The meter shows the level coming in.")
    static let listen = HelpTip(title: "LISTEN", body: "Reads BPM and key live from whatever is playing. Nothing is recorded or saved.")
    static let hold = HelpTip(title: "HOLD", body: "Freezes the reading on screen while listening carries on. Press again to follow the music.")
    static let reset = HelpTip(title: "NEW SONG", body: "Clears what Listen heard and starts fresh. Use it when the song changes.")

    // sending
    static let sendDAW = HelpTip(title: "SEND TO DAW", body: "Sends the BPM and key to the DAW that's open. What it can take depends on the DAW.")
    static let autoTune = HelpTip(title: "SEND TO AUTO-TUNE", body: "Sets the key and reference pitch in Auto-Tune (and Waves Tune Real-Time). Also ⇧⌘A while Beat Key is in front.")
    static let exportMidi = HelpTip(title: "EXPORT MIDI", body: "Saves a MIDI file with the tempo and key, to drag into any DAW.")

    // the footer
    static let recent = HelpTip(title: "RECENT", body: "Your recent readings. Pick one to put it back on the readout.")
    static let settings = HelpTip(title: "SETTINGS", body: "Display, listening source, global shortcuts and Open at Login.")
    static let window = HelpTip(title: "WINDOW", body: "Opens the full Beat Key window.")
    static let quit = HelpTip(title: "QUIT", body: "Quits Beat Key.")
    static let help = HelpTip(title: "HELP", body: "Help is on: hover anything to see what it does. Click again to turn it off.")

    // Advanced mode
    static let keyWheel = HelpTip(title: "KEY WHEEL", body: "Circle of fifths: majors outside, minors inside. The key is lit, runner-ups dim. Click any key to use it.")
    static let notesHeard = HelpTip(title: "NOTES HEARD", body: "How strongly each note was heard. Bright, dotted notes belong to the key's scale.")
    static let chords = HelpTip(title: "CHORDS", body: "The key's chords. Click one to hear it; drag it into your DAW or Finder for a MIDI clip.")
    static let quality = HelpTip(title: "TRIAD · 7TH · 9TH", body: "Chord size: three notes, add the 7th, or add the 7th and 9th.")
    static let voicing = HelpTip(title: "ROOT · 1ST · 2ND · OPEN", body: "Which chord note sits at the bottom. OPEN spreads the chord wider.")
    static let bars = HelpTip(title: "BAR", body: "How long each chord lasts when you drag it out as MIDI, in bars at the beat's BPM.")
    static let borrowed = HelpTip(title: "BORROWED", body: "Chords from the parallel major or minor key: outside the scale, but they add colour.")
    static let matchTo = HelpTip(title: "MATCH TO", body: "Pick your project's key. Beat Key shows how far to pitch this beat so it fits.")
    static let matchShift = HelpTip(title: "−6 … +6", body: "Semitones to pitch the beat up or down to land in your project's key. The lit one fits.")

    static let all: [HelpTip] = [
        bpm, bpmRounded, tempoFactor, keyDial, confidence, topKeys, manual, keyboard, scale, tuning, camelot,
        fileLine, showInFinder, status, linkField, download, openAudio, findKey, analyzeFile, source, listen,
        hold, reset, sendDAW, autoTune, exportMidi, recent, settings, window, quit, help, keyWheel, notesHeard,
        chords, quality, voicing, bars, borrowed, matchTo, matchShift,
    ]

    /// Lines that break the table's rules (empty, too long, a title used twice); logged at launch.
    static func problems(_ tips: [HelpTip] = all) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for t in tips {
            if t.title.isEmpty || t.body.trimmingCharacters(in: .whitespaces).isEmpty { out.append("empty: \(t.title)") }
            if t.body.count > HelpTip.maxBody { out.append("too long (\(t.body.count)): \(t.title)") }
            if !seen.insert(t.id).inserted { out.append("title used twice: \(t.title)") }
        }
        return out
    }

    static func checkAtLaunch() {
        for p in problems() { AppLog.log("help text: \(p)") }
    }
}

// MARK: the decision and the placement (pure, tested)

enum HelpTipLogic {
    /// A tip shows only in help mode, while hovered (or forced by an offscreen render).
    static func shows(helpOn: Bool, hovering: Bool, forced: Bool = false) -> Bool {
        helpOn && (hovering || forced)
    }

    static let gap: CGFloat = 6
    static let margin: CGFloat = 8

    /// Where the card goes for a control at `r` on a surface of `size`: its left edge (centred on
    /// the control, kept inside the margins) and whether it sits below the control (else above).
    /// Below unless the room there is short and there is more above.
    static func place(_ r: CGRect, in size: CGSize, width: CGFloat = HelpCard.width) -> (x: CGFloat, below: Bool) {
        let x = min(max(r.midX - width / 2, margin), max(margin, size.width - width - margin))
        let roomBelow = size.height - r.maxY - gap - margin
        let roomAbove = r.minY - gap - margin
        return (x, roomBelow >= 72 || roomBelow >= roomAbove)
    }
}

// MARK: the card (the key wheel's hover card: one look for every hover card)

struct HelpCard: View {
    let title: String
    let text: String
    var width: CGFloat = HelpCard.width

    static let width: CGFloat = 212

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Theme.face(11)).foregroundColor(Theme.amber)
            Text(text).font(.system(size: 10)).foregroundColor(Theme.amber(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hex(0x15100a).opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.amber(0.45), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.5), radius: 6, y: 2)
    }
}

// MARK: the modifier and the layer

private struct HelpModeKey: EnvironmentKey { static let defaultValue = false }
private struct HelpTipForcedKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    /// Help mode for this surface (the root sets it from PocketState.help).
    var helpMode: Bool {
        get { self[HelpModeKey.self] }
        set { self[HelpModeKey.self] = newValue }
    }
    /// Offscreen renders: the tip with this title shows as if hovered.
    var helpTipForced: String? {
        get { self[HelpTipForcedKey.self] }
        set { self[HelpTipForcedKey.self] = newValue }
    }
}

/// The hovered control's tip and where it is, handed up to the surface's layer.
struct HelpTipAnchor {
    let tip: HelpTip
    let anchor: Anchor<CGRect>
}

struct HelpTipKey: PreferenceKey {
    static var defaultValue: HelpTipAnchor? = nil
    static func reduce(value: inout HelpTipAnchor?, nextValue: () -> HelpTipAnchor?) {
        if let n = nextValue() { value = n }
    }
}

private struct HelpTipModifier: ViewModifier {
    let tip: HelpTip
    @Environment(\.helpMode) private var helpOn
    @Environment(\.helpTipForced) private var forced
    @State private var hovering = false

    func body(content: Content) -> some View {
        let active = HelpTipLogic.shows(helpOn: helpOn, hovering: hovering, forced: forced == tip.id)
        // the same view tree whether help is on or off (nothing inside resets on a toggle)
        return content
            .onHover { inside in if helpOn || !inside { hovering = inside } }
            .transformAnchorPreference(key: HelpTipKey.self, value: .bounds) { v, a in
                // an inner control's tip wins over the group around it
                if active && v == nil { v = HelpTipAnchor(tip: tip, anchor: a) }
            }
    }
}

private struct HelpTipLayer: ViewModifier {
    func body(content: Content) -> some View {
        content.overlayPreferenceValue(HelpTipKey.self) { v in
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    Color.clear
                    if let v = v {
                        card(v, in: g).id(v.tip.id).transition(.opacity)
                    }
                }
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            }
            .animation(.easeOut(duration: 0.12), value: v?.tip.id)
            .allowsHitTesting(false)
        }
    }

    private func card(_ v: HelpTipAnchor, in g: GeometryProxy) -> some View {
        let r = g[v.anchor]
        let p = HelpTipLogic.place(r, in: g.size)
        let m = HelpTipLogic.margin, gap = HelpTipLogic.gap
        let room = p.below ? g.size.height - r.maxY - gap - m : r.minY - gap - m
        return HelpCard(title: v.tip.title, text: v.tip.body)
            .frame(width: HelpCard.width, height: max(0, room), alignment: p.below ? .top : .bottom)
            .offset(x: p.x, y: p.below ? r.maxY + gap : m)
    }
}

extension View {
    /// In help mode, hovering this view shows `tip` on the shared amber card. Off = nothing.
    func helpTip(_ tip: HelpTip) -> some View { modifier(HelpTipModifier(tip: tip)) }

    /// The surface's card layer (the window's face, the pocket): above every view in it.
    func helpTipLayer() -> some View { modifier(HelpTipLayer()) }
}

// MARK: the HELP chip

/// HELP in the footer: dim like its neighbours when off, lit amber (the ×1 chip's lit look) when on.
struct HelpChip: View {
    let on: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        Button(action: action) {
            Text("HELP").font(Theme.face(8.5)).tracking(1.7)
                .foregroundColor(on ? Theme.hex(0x1a1206) : Theme.textLo)
                .padding(.horizontal, 6)
                .frame(height: 14)
                .background(shape.fill(on ? Theme.amber : Color.clear))
                .overlay(shape.stroke(on ? Color.clear : Theme.textFaint, lineWidth: 1))
                .shadow(color: on && !Theme.highContrast ? Theme.amberGlow : .clear, radius: 3)
                .contentShape(shape)
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHand()
        .help(on ? "Help mode is on" : "Help mode: hover anything to see what it does")
        .helpTip(HelpText.help)
        .accessibility(label: Text("Help mode"))
        .accessibility(hint: Text(on ? "Turns help mode off" : "Turns help mode on: hover anything to see what it does"))
        .accessibility(addTraits: on ? .isSelected : [])
    }
}
