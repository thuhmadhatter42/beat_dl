import AppKit
import SwiftUI

/// What the popover's controls do. MenuBar.swift wires these to the engine, Listen, the DAW and
/// Auto-Tune senders and the MIDI export: the same calls the window and the menus make.
struct PocketActions {
    var setFactor: (TempoFactor) -> Void = { _ in }
    var page: (Int) -> Void = { _ in }
    var download: () -> Void = {}
    var pasteAndDownload: (String) -> Void = { _ in }
    var openLogin: () -> Void = {}
    var toggleListen: () -> Void = {}
    /// New Song: Listen drops what it heard and its lock, and starts over.
    var newSong: () -> Void = {}
    /// Hold / Release: freeze the reading on show (never automatic).
    var toggleHold: () -> Void = {}
    /// A click on the key: sharp <-> flat.
    var respellKey: () -> Void = {}
    /// MANUAL ⌄: the 24-key menu; the pick becomes THE key and is saved as a teach record.
    var teachKey: () -> Void = {}
    var pickSource: () -> Void = {}
    var analyzeFile: () -> Void = {}
    var sendDAW: () -> Void = {}
    /// False = the key could not be written (a beep, and the cap says so).
    var sendAutoTune: () -> Bool = { true }
    var exportMidi: () -> Void = {}
    var showRecents: () -> Void = {}
    /// Advanced mode (the window only): a click on a chord sounds it; a drag writes its MIDI clip
    /// and hands the file over (nil = it could not be written); the chord / MATCH TO choices.
    var playChord: (Chord) -> Void = { _ in }
    var chordFile: (Chord) -> URL? = { _ in nil }
    var setHarmony: (HarmonyPrefs) -> Void = { _ in }
    var pickMatchKey: () -> Void = {}
    /// MINI: Beat Key Mini's floating pad panel, open / closed.
    var toggleMini: () -> Void = {}
    var openWindow: () -> Void = {}
    var settings: () -> Void = {}
    var quit: () -> Void = {}
    /// HELP: help mode on / off (both surfaces).
    var toggleHelp: () -> Void = {}
}

enum Pocket {
    static let width: CGFloat = 376
    /// The download cap fits its longer legend (PASTE + DOWNLOAD) so the field never jumps.
    static let downloadCapWidth: CGFloat = 152
    static let listenCapWidth: CGFloat = 112
    /// HOLD and the square reset key: a tight pair.
    static let transportGap: CGFloat = 8
    /// The scale keyboard under the top keys (J 2026-11-09: taller, same width).
    static let keyboardHeight: CGFloat = 64
    /// Offscreen renders (tests): AppKit-backed pieces (the link field) draw a stand-in.
    static var snapshot = false
}

/// The menu-bar popover: a pocket Beat Key faceplate. Readout on top (dial + key, BPM, top three
/// keys, the scale on a keyboard), then download, listen and the send caps, then the small links.
struct PocketView: View {
    let state: PocketState
    @Binding var url: String
    var actions = PocketActions()
    @State private var fieldFocused = false

    var body: some View {
        VStack(spacing: 10) {
            PocketHeader(state: state)
            PocketLCD(state: state, actions: actions)
            module
            footer
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(width: Pocket.width)
        .environment(\.helpMode, state.help)
        .helpTipLayer()
        .background(PocketPlate())
        .id(state.highContrast)   // Theme.highContrast is read while drawing
    }

    // MARK: module: download, listen, send

    private var module: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                LinkField(text: $url, focused: $fieldFocused, onSubmit: { actions.downloadPressed(state) })
                DownloadCap(state: state, action: { actions.downloadPressed(state) })
                    .frame(width: Pocket.downloadCapWidth)
            }
            HStack(spacing: 10) {
                ListenCap(state: state, action: actions.toggleListen).frame(width: Pocket.listenCapWidth)
                SourceField(source: state.source, level: state.level, listening: state.listening,
                            action: actions.pickSource)
            }
            .padding(.top, 10)
            if state.listening {
                // HOLD and the reset key sit under LISTEN, the pair as wide as LISTEN's cap
                HStack(spacing: Pocket.transportGap) {
                    HoldCap(state: state, action: actions.toggleHold)
                    NewSongCap(lit: true, keys: state.newSongKeys, action: actions.newSong)
                }
                .frame(width: Pocket.listenCapWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
            }
            ModuleRule().padding(.vertical, 12)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ActionCap(title: "ANALYZE FILE", ready: !state.busy, label: "Analyze a file", action: actions.analyzeFile)
                        .helpTip(HelpText.analyzeFile)
                    SendDAWCap(state: state, action: actions.sendDAW)
                }
                HStack(spacing: 10) {
                    AutoTuneCap(state: state, send: actions.sendAutoTune)
                    ExportMidiCap(state: state, action: actions.exportMidi)
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .modulePanel()
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 16) {
            RecentLink(state: state, action: actions.showRecents)
            FooterLink(title: "WINDOW", label: "Show the Beat Key window", action: actions.openWindow)
                .helpTip(HelpText.window)
            FooterLink(title: "SETTINGS", label: "Settings", action: actions.settings).helpTip(HelpText.settings)
            HelpChip(on: state.help, action: actions.toggleHelp)
            Spacer()
            FooterLink(title: "QUIT", label: Brand.quit, action: actions.quit).helpTip(HelpText.quit)
        }
        .padding(.horizontal, 4)
    }
}

extension PocketActions {
    /// DOWNLOAD (both surfaces): a login waiting = the login; the link in the field; with the
    /// field empty, the link on the clipboard (one click: PASTE + DOWNLOAD).
    func downloadPressed(_ state: PocketState) {
        if state.needsLogin { openLogin(); return }
        if !state.downloadLit, state.clipboardReady, let link = state.clipboardLink { pasteAndDownload(link); return }
        if !state.busy, state.fieldEmpty, state.clipboardLink == nil {
            AppLog.log("paste + download: the field is empty and the clipboard holds no link")
        }
        download()
    }
}

extension PocketState {
    /// The field holds nothing but spaces.
    var fieldEmpty: Bool { url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The download cap's legend (both surfaces): LOG IN… while a login waits; PASTE + DOWNLOAD
    /// with the field empty (the press takes the clipboard's link); DOWNLOAD once a link is
    /// typed (the typed link wins over the clipboard).
    static func downloadTitle(url: String, needsLogin: Bool = false) -> String {
        if needsLogin { return "LOG IN…" }
        return url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "PASTE + DOWNLOAD" : "DOWNLOAD"
    }
    var downloadTitle: String { PocketState.downloadTitle(url: url, needsLogin: needsLogin) }
}

/// DOWNLOAD / PASTE + DOWNLOAD: lit for a typed link or, with the field empty, a link on the
/// clipboard; dim when there is neither (a press beeps and logs).
struct DownloadCap: View {
    let state: PocketState
    let action: () -> Void
    var body: some View {
        let login = state.needsLogin
        Button(action: action) {
            SSLCapStyle.label(state.downloadTitle).lineLimit(1).frame(maxWidth: .infinity)
        }
        // not .disabled(): AppKit would grey the legend; an unlit cap only beeps
        .buttonStyle(SSLCapStyle(lit: state.downloadLit || state.clipboardReady || (login && !state.busy)))
        .nativeHelp(help)
        .accessibility(label: Text(login ? "Log in to YouTube" : state.fieldEmpty ? "Paste and download" : "Download"))
        .accessibility(hint: Text(hint))
        .helpTip(HelpText.download)
    }

    private var help: String {
        if state.needsLogin { return "Log in to YouTube" }
        if !state.fieldEmpty { return "Download the link as an MP3 and read its BPM and key" }
        if let link = state.clipboardLink { return "Paste \(PocketText.shortLink(link)) and download it" }
        return "Copy a YouTube link, or type one in the field"
    }
    private var hint: String {
        if state.needsLogin { return "Opens the YouTube login" }
        if !state.fieldEmpty { return "Downloads the link as an MP3 into Downloads and reads its BPM and key" }
        return state.clipboardLink == nil ? "Copy a YouTube link first"
                                          : "Pastes the link on the clipboard, downloads it and reads its BPM and key"
    }
}

// MARK: shared module parts (the pocket and the window draw these same views)

extension View {
    /// The module's recessed panel (the window's and the pocket's).
    func modulePanel() -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return background(Theme.vertical([(Theme.hex(0x1d1d20), 0), (Theme.hex(0x151517), 1)]).clipShape(shape))
            .innerShadow(shape, Color.white.opacity(0.06), blur: 0, y: 1)
            .ring(radius: 7, spread: 1, Theme.black)
            .dropShadow(radius: 7, Color.black.opacity(0.7), blur: 3, y: 1)
    }
}

/// The engraved line between the inputs and the send caps.
struct ModuleRule: View {
    var body: some View {
        Rectangle().fill(Color.black.opacity(0.7)).frame(height: 1)
            .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1).offset(y: 1))
    }
}

/// LISTEN / STOP: the red lamp while on.
struct ListenCap: View {
    let state: PocketState
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if state.listening {
                    LampShape(lamp: .listening).fill(Lamp.listening.color).frame(width: 7, height: 7)
                        .shadow(color: Theme.highContrast ? .clear : Theme.red.opacity(0.9), radius: 3)
                }
                SSLCapStyle.label(state.listening ? "STOP" : "LISTEN")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SSLCapStyle(lit: !state.listening && !state.busy, ready: state.listening))
        .accessibility(label: Text(state.listening ? "Stop listening" : "Start listening to \(state.source)"))
        .helpTip(HelpText.listen)
    }
}

/// NEW SONG · RESET as a square key beside HOLD: Listen drops what it heard and its lock, and
/// starts over. The icon is the legend; the words live in the tooltip and VoiceOver.
struct NewSongCap: View {
    let lit: Bool
    var keys: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 12, weight: .bold))
                .frame(width: SSLCapStyle.height)
        }
        .buttonStyle(SSLCapStyle(lit: false, ready: lit, padding: 0))
        .nativeHelp("New song · reset")
        .accessibility(label: Text("New song: reset listening"))
        .accessibility(hint: Text("Drops what was heard and the lock, and listens again"
                                  + (keys.map { ". Shortcut \($0)" } ?? "")))
        .helpTip(HelpText.reset)
    }
}

/// HOLD: freeze the reading on show (a button, never automatic).
struct HoldCap: View {
    let state: PocketState
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "pause.fill").font(.system(size: 9, weight: .bold))
                SSLCapStyle.label("HOLD").lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SSLCapStyle(lit: state.held, ready: state.canHold && !state.held))
        .nativeHelp(state.held ? "Release: follow the music again" : "Hold: freeze the reading on show")
        .accessibility(label: Text(state.held ? "Release hold" : "Hold reading"))
        .accessibility(hint: Text("Freezes the reading on show while listening carries on. Press again to follow the music"))
        .accessibility(addTraits: state.held ? .isSelected : [])
        .helpTip(HelpText.hold)
    }
}

/// A pale send cap: full strength when it can act now, dim when there is nothing to send.
struct ActionCap: View {
    let title: String
    let ready: Bool
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: { if ready { action() } }) {
            SSLCapStyle.label(title).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SSLCapStyle(lit: false, ready: ready))
        .accessibility(label: Text(label))
    }
}

/// SEND TO <the DAW that is open>.
struct SendDAWCap: View {
    let state: PocketState
    let action: () -> Void
    var body: some View {
        let daw = state.daw.map { "SEND TO \($0.uppercased())" } ?? "SEND TO DAW"
        ActionCap(title: daw, ready: state.canSend, label: daw.capitalized, action: action)
            .helpTip(HelpText.sendDAW)
    }
}

/// SEND TO AUTO-TUNE: flashes SENT ✓ (or NO KEY) for a moment after the press.
struct AutoTuneCap: View {
    let state: PocketState
    let send: () -> Bool
    @State private var flash: String?
    var body: some View {
        ActionCap(title: flash ?? "SEND TO AUTO-TUNE", ready: state.canAutoTune, label: "Send key to Auto-Tune") {
            let ok = send()
            flash = ok ? "SENT TO AUTO-TUNE ✓" : "AUTO-TUNE: NO KEY"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { flash = nil }
        }
        .helpTip(HelpText.autoTune)
    }
}

struct ExportMidiCap: View {
    let state: PocketState
    let action: () -> Void
    var body: some View {
        ActionCap(title: "EXPORT MIDI", ready: state.canSend, label: "Export MIDI tempo and key file", action: action)
            .helpTip(HelpText.exportMidi)
    }
}

/// RECENT ▾: the recent readings as a menu (File › Recent Readings' list).
struct RecentLink: View {
    let state: PocketState
    let action: () -> Void
    var body: some View {
        FooterLink(title: "RECENT ▾", label: "Recent readings", enabled: !state.recents.isEmpty, action: action)
            .helpTip(HelpText.recent)
    }
}

enum PocketText {
    /// "youtube.com/watch?v=…" without the scheme and www.
    static func shortLink(_ s: String) -> String {
        var t = s
        for p in ["https://", "http://", "www.", "m."] where t.hasPrefix(p) { t.removeFirst(p.count) }
        return t
    }
}

struct FooterLink: View {
    let title: String
    let label: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title).font(Theme.face(8.5)).tracking(1.7)
                .foregroundColor(enabled ? Theme.textLo : Theme.textFaint)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHand()
        .accessibility(label: Text(label))
    }
}

// MARK: plate + header

/// The popover's chassis: the window plate's gradient, sheen and grain, edge to edge.
private struct PocketPlate: View {
    var body: some View {
        ZStack {
            Theme.vertical([(Theme.hex(0x232326), 0), (Theme.hex(0x191a1c), 0.4), (Theme.hex(0x131315), 1)])
            LinearGradient(gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0), location: 0.30),
                .init(color: Color.white.opacity(0.04), location: 0.45),
                .init(color: Color.white.opacity(0), location: 0.60)]),
                startPoint: UnitPoint(x: 0, y: 0.1), endPoint: UnitPoint(x: 1, y: 0.9))
            if let n = Textures.noise { Image(nsImage: n).resizable(resizingMode: .tile) }
        }
    }
}

private struct PocketHeader: View {
    let state: PocketState

    var body: some View {
        HStack(spacing: 8) {
            KeyGlyph().frame(width: 22, height: 13)
                .shadow(color: Theme.highContrast ? .clear : Theme.amber(0.45), radius: 3)
            let t = Text(Brand.wordmark).font(Theme.face(12)).tracking(12 * 0.24)
            t.foregroundColor(.clear)
                .overlay(Theme.vertical([(Theme.hex(0xf4f4f6), 0), (Theme.hex(0xababb0), 0.55), (Theme.hex(0xcbcbcf), 1)]).mask(t))
                .fixedSize()
                .accessibility(label: Text(Brand.name))
            Spacer()
            legend
        }
        .padding(.horizontal, 4)
        .frame(height: 20)
    }

    private var legend: some View {
        let (word, lamp, color): (String, Lamp?, Color) = {
            if state.listening { return ("LIVE · \(state.source.uppercased())", .listening, Theme.redText) }
            switch state.readout {
            case .working: return ("WORKING", .listening, Theme.amber)
            case .error: return ("FAILED", nil, Theme.redText)
            default: return ("READY", .locked, Theme.greenText)
            }
        }()
        return HStack(spacing: 6) {
            if let l = lamp {
                LampShape(lamp: l).fill(l == .listening && !state.listening ? Theme.amber : l.color).frame(width: 7, height: 7)
                    .shadow(color: Theme.highContrast ? .clear : l.color.opacity(0.7), radius: 3)
            } else {
                Circle().fill(Theme.red).frame(width: 7, height: 7)
            }
            Text(word).font(Theme.face(8.5)).tracking(1.7).foregroundColor(color).lineLimit(1)
                .truncationMode(.middle).frame(maxWidth: 190).fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text("Status: \(word.lowercased())"))
        .helpTip(HelpText.status)
    }
}

/// Beat Key's key, drawn: the dial head of the app icon (ring, hub), the shaft and its teeth.
/// The status item draws the same path (MenuBarImage.key).
struct KeyGlyph: View {
    var color: Color = Theme.amber
    var body: some View {
        KeyGlyphShape().fill(color, style: FillStyle(eoFill: true))
    }
}

struct KeyGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let h = rect.height, w = rect.width
        let d = h                                    // head diameter = full height
        let head = CGRect(x: rect.minX, y: rect.minY, width: d, height: d)
        p.addEllipse(in: head)
        p.addEllipse(in: head.insetBy(dx: d * 0.17, dy: d * 0.17))      // the ring
        p.addEllipse(in: head.insetBy(dx: d * 0.36, dy: d * 0.36))      // the hub
        let shaftH = max(1.5, h * 0.2)
        let sy = rect.minY + h * 0.38
        let sx = rect.minX + d * 0.9
        p.addRect(CGRect(x: sx, y: sy, width: w - (sx - rect.minX) - h * 0.12, height: shaftH))
        // the tip
        p.move(to: CGPoint(x: rect.maxX - h * 0.14, y: sy))
        p.addLine(to: CGPoint(x: rect.maxX, y: sy + shaftH / 2))
        p.addLine(to: CGPoint(x: rect.maxX - h * 0.14, y: sy + shaftH))
        p.closeSubpath()
        // teeth: a short waveform under the shaft
        let tw = max(1, h * 0.12)
        let teeth: [CGFloat] = [0.30, 0.20, 0.36, 0.24]
        for (i, t) in teeth.enumerated() {
            let x = sx + (w - (sx - rect.minX)) * (0.22 + CGFloat(i) * 0.16)
            p.addRect(CGRect(x: x, y: sy + shaftH - 0.2, width: tw, height: h * t))
        }
        return p
    }
}

// MARK: the readout

private struct PocketLCD: View {
    let state: PocketState
    let actions: PocketActions

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                Dial(state: state, actions: actions).frame(width: 112, height: 112)
                right.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 118)
            KeyStrip(state: state, onTeach: actions.teachKey, keyboardHeight: Pocket.keyboardHeight).padding(.top, 8)
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
        .background(Theme.highContrast ? Theme.vertical([(Theme.black, 0), (Theme.black, 1)])
                                       : Theme.vertical([(Theme.hex(0x0b0d0a), 0), (Theme.hex(0x050604), 1)]))
        .overlay(Theme.vertical([(Color.white.opacity(Theme.highContrast ? 0 : 0.06), 0), (Color.white.opacity(0), 0.35)])
            .allowsHitTesting(false))
        .clipShape(shape)
        .innerShadow(shape, Color.black.opacity(0.95), blur: 6, y: 2)
        .ring(radius: 6, spread: 1, Theme.black)
        .background(shape.fill(Color.white.opacity(0.05)).offset(y: 1).padding(-1))
    }

    // MARK: right of the dial

    @ViewBuilder private var right: some View {
        switch state.readout {
        case .result(let r, let page, _, let note, let o):
            ResultSide(result: r, page: page, note: note, options: o, state: state, actions: actions)
        case .working(let stage, let download):
            VStack(alignment: .leading, spacing: 0) {
                Text(Faceplate.stageText(stage)).font(Theme.face(14)).tracking(0.7)
                    .foregroundColor(Theme.amber).amberGlow().lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                RunningBar().padding(.top, 12)
                HStack(spacing: 10) {
                    ForEach(steps(stage, download), id: \.0) { name, step in
                        Text(step == .done ? "✓ \(name)" : name).font(Theme.face(7.5)).tracking(1.4)
                            .lineLimit(1).fixedSize()
                            .foregroundColor(step == .on ? Theme.amber : step == .done ? Theme.amber(0.55) : Theme.textFaint)
                    }
                }
                .padding(.top, 10)
            }
            .accessibilityElement(children: .ignore)
            .accessibility(label: Text(Faceplate.stageText(stage).capitalized))
        case .listening(let status):
            VStack(alignment: .leading, spacing: 0) {
                Text("LISTENING").font(Theme.face(18)).tracking(0.9).foregroundColor(Theme.amber).amberGlow()
                RunningBar().padding(.top, 12)
            }
            .accessibilityElement(children: .ignore)
            .accessibility(label: Text("Listening. \(status.lowercased())"))
        case .error(let m, let download, let hint):
            VStack(alignment: .leading, spacing: 6) {
                Text(Faceplate.errorText(m)).font(Theme.face(12)).tracking(0.4)
                    .foregroundColor(Theme.redText).shadow(color: Theme.highContrast ? .clear : Theme.red.opacity(0.6), radius: 3)
                    .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                Text(hint ?? Faceplate.failureHint(download: download)).font(Theme.face(7.5)).tracking(1.2)
                    .foregroundColor(Theme.rgb(255, 106, 92, Theme.highContrast ? 1 : 0.65)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibility(label: Text(m))
        case .login(let a, let b, _):
            message(a, b)
        case .doctor(let r):
            message(r.title, r.line, red: r.outcome == .failed)
        case .idle, .drop:
            VStack(alignment: .leading, spacing: 0) {
                Text.cap("BPM")
                Text("---.--").font(Theme.face(38).monospacedDigit()).foregroundColor(Theme.amber(0.12))
                    .lineBox(38, 1).padding(.top, 5)
                Text("PASTE A LINK, OPEN A FILE OR LISTEN").font(Theme.face(7.5)).tracking(1.2)
                    .foregroundColor(Theme.amber(0.6)).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            }
            .accessibilityElement(children: .ignore)
            .accessibility(label: Text("No reading yet. Paste a link, analyze a file or listen."))
        }
    }

    private func message(_ a: String, _ b: String, red: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(a).font(Theme.face(13)).tracking(0.5).foregroundColor(red ? Theme.redText : Theme.amber)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Text(b).font(Theme.face(7.5)).tracking(1.2).foregroundColor(red ? Theme.redText : Theme.amber(0.7))
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text("\(a.capitalized). \(b.lowercased())"))
    }

    private func steps(_ stage: String, _ download: Bool) -> [(String, Faceplate.Step)] {
        if Faceplate.isDoctorStage(stage) { return Faceplate.doctorSteps(stage) }
        return download ? Faceplate.steps(stage) : [("ANALYZE", .on)]
    }
}

/// The lower half of both readouts: a hairline ending in the MANUAL key menu, TOP KEYS (a click
/// picks the key), the scale on a one-octave keyboard, and the scale line with the tuning.
struct KeyStrip: View {
    let state: PocketState
    /// MANUAL ⌄: the 24-key menu (nil = not shown).
    var onTeach: (() -> Void)? = nil
    var keyboardHeight: CGFloat = Pocket.keyboardHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // the hairline runs into the menu at the strip's right edge (the % column's edge)
            HStack(spacing: 10) {
                Rectangle().fill(Theme.amber(0.12)).frame(height: 1)
                if let teach = onTeach {
                    ManualKeyMenu(enabled: state.result != nil, action: teach).helpTip(HelpText.manual)
                }
            }
            .frame(height: ManualKeyMenu.height)
            TopKeys(keys: state.result?.keys ?? [],
                    onChoose: state.result.map { r in { k in SpellingSettings.shared.choose(k, of: r, from: "top keys") } })
                .helpTip(HelpText.topKeys)
                .padding(.top, 8)
            NoteKeyboard(scale: state.scale).frame(height: keyboardHeight).helpTip(HelpText.keyboard).padding(.top, 12)
            scaleLine.padding(.top, 7)
            TuningMeterRow(meter: state.options?.tuning).padding(.top, 7)
        }
    }

    /// "E♭ MINOR · E♭ F G♭ A♭ B♭ B D♭" left, the tuning right.
    private var scaleLine: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                if let s = state.scale {
                    Text("\(s.tonicName) \(s.minor ? "MINOR" : "MAJOR")").font(Theme.face(8.5)).tracking(1.4)
                        .foregroundColor(Theme.amber(0.85))
                    Text(s.spelled.joined(separator: "  ")).font(.custom("HelveticaNeue", size: 9)).tracking(0.4)
                        .foregroundColor(Theme.amber(0.55)).lineLimit(1)
                } else {
                    Text("SCALE").font(Theme.face(8.5)).tracking(1.4).foregroundColor(Theme.amber(0.25))
                }
            }
            .helpTip(HelpText.scale)
            Spacer(minLength: 4)
        }
        .accessibilityElement(children: .combine)
    }
}

/// TUNING (J 2026-11-09, Orra's meter in Beat Key's amber): a thin −50 ¢ … +50 ¢ track with a
/// centre tick and a marker at the offset (green within ±5 ¢), then "+0.1 ct  A4 = 440.0 Hz".
/// Always drawn, so the readout never jumps: no reading = a dim track and a dash.
struct TuningMeterRow: View {
    let meter: TuningMeter?

    static let height: CGFloat = 12
    static let markerWidth: CGFloat = 4

    var body: some View {
        HStack(spacing: 10) {
            Text("TUNING").font(Theme.face(7)).tracking(1.4).foregroundColor(Theme.amber(meter == nil ? 0.25 : 0.45))
                .fixedSize()
            track.frame(height: TuningMeterRow.height)
            Text(meter?.text ?? "—").font(Theme.face(8.5).monospacedDigit()).tracking(0.4)
                .foregroundColor(Theme.amber(meter == nil ? 0.25 : 0.8)).lineLimit(1).fixedSize()
                .frame(minWidth: 128, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text(meter?.spoken ?? "Tuning: no reading"))
        .helpTip(HelpText.tuning)
    }

    private var track: some View {
        GeometryReader { g in
            let w = g.size.width, mid = g.size.height / 2
            ZStack(alignment: .topLeading) {
                Capsule().fill(Theme.amber(meter == nil ? 0.06 : 0.1)).frame(width: w, height: 2).offset(y: mid - 1)
                // −25 / +25 ticks faint, the centre brighter
                ForEach([0.25, 0.5, 0.75], id: \.self) { f in
                    Rectangle().fill(Theme.amber(f == 0.5 ? (meter == nil ? 0.2 : 0.4) : 0.14))
                        .frame(width: 1, height: f == 0.5 ? 8 : 4)
                        .offset(x: (w * CGFloat(f)).rounded() - 0.5, y: mid - (f == 0.5 ? 4 : 2))
                }
                if let m = meter {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(m.inTune ? Theme.green : Theme.amber)
                        .frame(width: TuningMeterRow.markerWidth, height: g.size.height)
                        .shadow(color: Theme.highContrast ? .clear : (m.inTune ? Theme.greenGlow : Theme.amberGlow), radius: 3)
                        .offset(x: TuningMeterRow.markerX(m.fraction, width: w))
                        .animation(.easeOut(duration: 0.35), value: m.cents)
                }
            }
        }
    }

    /// The marker's left edge for `fraction` (0...1) on a track `width` wide, kept on the track.
    static func markerX(_ fraction: Double, width: CGFloat) -> CGFloat {
        let f = CGFloat(min(max(fraction, 0), 1))
        return min(max(f * width - markerWidth / 2, 0), max(0, width - markerWidth))
    }
}

/// MANUAL ⌄: set the key by hand. A bordered LCD menu button (the x0.5 / x1 / x2 chips'
/// language) whose chevron says it drops a list: the 24 keys; the pick becomes THE key and the
/// reading is saved to teach Beat Key. Dim with no reading.
struct ManualKeyMenu: View {
    let enabled: Bool
    let action: () -> Void
    static let height: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        Button(action: { if enabled { action() } }) {
            HStack(spacing: 5) {
                Text("MANUAL").font(Theme.face(8.5)).tracking(1.1)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .heavy))
            }
            .foregroundColor(Theme.amber(enabled ? 0.85 : 0.25))
            .padding(.leading, 8).padding(.trailing, 7)
            .frame(height: ManualKeyMenu.height)
            .background(shape.fill(Theme.amber(enabled ? 0.08 : 0.03)))
            .overlay(shape.stroke(Theme.amber(enabled ? 0.45 : 0.15), lineWidth: 1))
            .contentShape(shape)
            .fixedSize()
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHand()
        .nativeHelp("Set the key by hand: pick it from all 24 keys. It becomes the key, and the reading is saved to teach Beat Key")
        .accessibility(label: Text("Manual key"))
        .accessibility(hint: Text("Opens a menu of all 24 keys. The pick becomes the key and teaches Beat Key"))
    }
}

/// The confidence dial around the key: twelve ticks (the icon's dial), a track, and an arc in
/// the lamp's colour as long as the top key's confidence. The key sits in the middle, the lamp's
/// shape and the percentage under it, so the state reads without colour.
struct Dial: View {
    let state: PocketState
    var actions = PocketActions()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        let lamp = state.lamp
        let color = isWorking ? Theme.amber : (lamp.map { $0.color } ?? Theme.amber)
        let key = state.result?.keys.first?.0
        ZStack {
            // ticks
            ForEach(0..<12, id: \.self) { i in
                Capsule().fill(Theme.amber(i % 3 == 0 ? 0.55 : 0.28))
                    .frame(width: i % 3 == 0 ? 2 : 1.5, height: i % 3 == 0 ? 7 : 5)
                    .offset(y: -51.5)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            Circle().stroke(Theme.amber(0.09), lineWidth: 5).padding(12)
            if let c = state.confidence {
                Circle().trim(from: 0, to: CGFloat(c))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(12)
                    .shadow(color: Theme.highContrast ? .clear : color.opacity(0.7), radius: 4)
            } else if lamp == .listening {
                // listening / working with no key yet: a short arc going round
                Circle().trim(from: 0, to: 0.18)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 270 : -90))
                    .animation(spin ? Animation.linear(duration: 1.6).repeatForever(autoreverses: false) : nil, value: spin)
                    .padding(12)
                    .shadow(color: Theme.highContrast ? .clear : color.opacity(0.7), radius: 4)
                    .onAppear { if !reduceMotion && !Pocket.snapshot { DispatchQueue.main.async { spin = true } } }
            }
            VStack(spacing: 3) {
                keyButton(key)
                if let l = lamp, let c = state.confidence {
                    HStack(spacing: 4) {
                        LampShape(lamp: l).fill(l.color).frame(width: 7, height: 7)
                        Text("\(Int((c * 100).rounded()))%").font(Theme.face(10).monospacedDigit())
                            .foregroundColor(l.textColor)
                    }
                } else {
                    Text("KEY").font(Theme.face(7.5)).tracking(1.8).foregroundColor(Theme.amber(key == nil ? 0.35 : 0.6))
                }
            }
            .frame(width: 76)
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text(dialLabel))
        .helpTip(HelpText.keyDial)
    }

    private var isWorking: Bool {
        if case .working = state.readout { return true }
        return false
    }

    /// The big key; a click on a black-key tonic switches sharp / flat.
    @ViewBuilder private func keyButton(_ key: String?) -> some View {
        let text = Text(key ?? "--").font(Theme.face(key.map { $0.count > 3 ? 24 : 30 } ?? 30))
            .tracking(0.6)
            .foregroundColor(key == nil ? Theme.amber(0.14) : Theme.amber)
            .lineLimit(1).minimumScaleFactor(0.6)
            .modifier(PocketGlow(on: key != nil))
        if state.canRespell {
            Button(action: actions.respellKey) { text.contentShape(Rectangle()) }
                .buttonStyle(PlainButtonStyle())
                .pointingHand()
        } else {
            text
        }
    }


    private var dialLabel: String {
        guard let k = state.result?.keys.first else { return state.lamp == .listening ? "Listening" : "No key yet" }
        return "Key \(k.0), \(k.1) percent" + (state.lamp.map { ", \($0.spoken)" } ?? "")
            + (state.held ? ", held" : "")
            + (state.canRespell ? ". Click to switch between sharp and flat spelling" : "")
    }
}

/// BPM (clickable, x0.5 / x1 / x2 chips), the lamp's word, the file or source line.
private struct ResultSide: View {
    let result: Result
    let page: String?
    let note: String?
    let options: ResultOptions
    let state: PocketState
    let actions: PocketActions

    var body: some View {
        let bpm = Tempo.text(result, factor: options.factor)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text.cap("BPM")
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    ForEach([TempoFactor.half, .one, .double], id: \.self) { f in
                        FactorChip(factor: f, on: f == options.factor, enabled: bpm != nil) { actions.setFactor(f) }
                    }
                }
                .helpTip(HelpText.tempoFactor)
            }
            Button(action: { options.onCycleTempo?() }) {
                Text(bpm ?? "---.--").font(Theme.face(bpm.map { $0.count > 6 ? 32 : 38 } ?? 38).monospacedDigit())
                    .tracking(0.4)
                    .foregroundColor(bpm == nil ? Theme.amber(0.12) : Theme.amber)
                    .modifier(PocketGlow(on: bpm != nil))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .lineBox(38, 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .pointingHand()
            .padding(.top, 6)
            .accessibility(label: Text(bpm.map { "BPM \($0)" } ?? "BPM not found"))
            .accessibility(hint: Text("Click to switch between normal, double and half time"))
            .helpTip(HelpText.bpm)
            if let l = state.lamp, let w = state.lampWord {
                HStack(spacing: 6) {
                    LampShape(lamp: l).fill(l.color).frame(width: 8, height: 8)
                        .shadow(color: Theme.highContrast ? .clear : l.color.opacity(0.8), radius: 3)
                    Text(w).font(Theme.face(8.5)).tracking(1.4).foregroundColor(l.textColor)
                }
                .helpTip(HelpText.confidence)
                .padding(.top, 10)
            }
            HStack(spacing: 6) {
                Text(lineText).font(Theme.face(7.5)).tracking(1.1).foregroundColor(Theme.amber(0.55))
                    .lineLimit(1).truncationMode(.middle)
                    .helpTip(HelpText.fileLine)
                if let p = page {
                    Spacer(minLength: 2)
                    Button(action: { actions.page(-1) }) { Text("‹").font(Theme.face(11)).foregroundColor(Theme.amber(0.7)) }
                        .buttonStyle(PlainButtonStyle()).accessibility(label: Text("Previous file"))
                    Text(p).font(Theme.face(7.5)).tracking(1).foregroundColor(Theme.amber(0.7)).fixedSize()
                    Button(action: { actions.page(1) }) { Text("›").font(Theme.face(11)).foregroundColor(Theme.amber(0.7)) }
                        .buttonStyle(PlainButtonStyle()).accessibility(label: Text("Next file"))
                }
            }
            .padding(.top, 7)
        }
    }

    private var lineText: String {
        if let n = note { return n }
        if let l = options.live { return "LIVE · \(l.source.uppercased())" }
        return (result.name as NSString).deletingPathExtension.uppercased()
    }
}

struct FactorChip: View {
    let factor: TempoFactor
    let on: Bool
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        LCDChip(title: factor.label ?? "×1", on: on, enabled: enabled,
                label: factor == .one ? "Normal time" : factor == .double ? "Double time" : "Half time",
                action: action)
    }
}

/// A small amber segment on the LCD (the BPM's x0.5 / x1 / x2, Advanced mode's chord choices):
/// filled when on, outlined when not, dim when there is nothing to act on.
struct LCDChip: View {
    let title: String
    let on: Bool
    var enabled = true
    let label: String
    var width: CGFloat = 26
    let action: () -> Void
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        Button(action: { if enabled { action() } }) {
            Text(title).font(Theme.face(8).monospacedDigit()).tracking(title.count > 2 ? 0.8 : 0)
                .foregroundColor(on && enabled ? Theme.hex(0x1a1206) : Theme.amber(enabled ? 0.5 : 0.2))
                .lineLimit(1)
                .frame(width: width, height: 15)
                .background(shape.fill(on && enabled ? Theme.amber : Theme.amber(0.06)))
                .overlay(shape.stroke(Theme.amber(on && enabled ? 0 : 0.18), lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHand()
        .accessibility(label: Text(label))
        .accessibility(addTraits: on ? .isSelected : [])
    }
}

/// Beat Key's headline: the three likeliest keys with their percentages and a bar each. A click
/// on key 2 or 3 makes it THE key: it moves to the front, the dial and the sends use it.
struct TopKeys: View {
    let keys: [(String, Int)]
    var onChoose: ((String) -> Void)? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<3, id: \.self) { i in
                if i > 0, i < keys.count, let choose = onChoose {
                    let name = keys[i].0
                    Button(action: { choose(name) }) { cell(i, keys[i]).contentShape(Rectangle()) }
                        .buttonStyle(PlainButtonStyle())
                        .pointingHand()
                        .nativeHelp("Use \(name) as the key")
                } else {
                    cell(i, i < keys.count ? keys[i] : nil)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text(keys.isEmpty ? "No keys yet"
            : "Top keys: " + keys.prefix(3).map { "\($0.0) \($0.1) percent" }.joined(separator: ", ")))
    }

    private func cell(_ i: Int, _ k: (String, Int)?) -> some View {
        let strength: Double = i == 0 ? 1 : 0.72
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(i + 1)").font(Theme.face(8).monospacedDigit()).foregroundColor(Theme.amber(0.4))
                Text(k?.0 ?? "--").font(Theme.face(i == 0 ? 19 : 17))
                    .foregroundColor(k == nil ? Theme.amber(0.14) : Theme.amber(strength))
                    .modifier(PocketGlow(on: k != nil && i == 0))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                Text(k.map { "\($0.1)%" } ?? "").font(Theme.face(11).monospacedDigit())
                    .foregroundColor(Theme.amber(i == 0 ? 0.9 : 0.6))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.amber(0.1))
                    Capsule().fill(Theme.amber(i == 0 ? 1 : 0.55))
                        .frame(width: g.size.width * CGFloat(min(100, max(0, k?.1 ?? 0))) / 100)
                        .shadow(color: Theme.highContrast || i != 0 ? .clear : Theme.amberGlow, radius: 2.5)
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One octave, C to B. The scale's notes are lit; the tonic is brightest and carries a dot.
struct NoteKeyboard: View {
    let scale: Scale?
    static let whites = [0, 2, 4, 5, 7, 9, 11]
    /// Black keys: pitch class and the white-key gap (1...6) they sit over.
    static let blacks: [(pc: Int, gap: Int)] = [(1, 1), (3, 2), (6, 4), (8, 5), (10, 6)]

    var body: some View {
        GeometryReader { g in
            let ww = g.size.width / 7, h = g.size.height
            ZStack(alignment: .topLeading) {
                ForEach(0..<7, id: \.self) { i in
                    let pc = NoteKeyboard.whites[i]
                    key(pc, black: false)
                        .frame(width: ww - 2, height: h)
                        .offset(x: CGFloat(i) * ww + 1)
                }
                ForEach(0..<5, id: \.self) { j in
                    let b = NoteKeyboard.blacks[j]
                    key(b.pc, black: true)
                        .frame(width: ww * 0.5, height: h * 0.6)
                        .offset(x: CGFloat(b.gap) * ww - ww * 0.25)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text(scale.map { "Scale: " + $0.spelled.joined(separator: ", ") } ?? "No scale yet"))
    }

    private func key(_ pc: Int, black: Bool) -> some View {
        let on = scale?.notes.contains(pc) ?? false
        let tonic = scale?.tonic == pc
        let shape = RoundedRectangle(cornerRadius: black ? 2 : 3, style: .continuous)
        // key fills are not text: raw amber, so High Contrast keeps tonic / scale / off apart
        let amber = { (a: Double) in Theme.rgb(255, 176, 32, a) }
        let fill: Color = tonic ? amber(1) : on ? amber(black ? 0.6 : 0.5)
                                           : (black ? Theme.hex(0x070806) : amber(Theme.highContrast ? 0.1 : 0.05))
        return ZStack(alignment: .bottom) {
            shape.fill(fill)
            shape.stroke(on ? Color.clear : amber(black ? 0.3 : (Theme.highContrast ? 0.35 : 0.16)), lineWidth: 1)
            if !black, let s = scale, on {
                Text(s.name(pc)).font(Theme.face(8)).foregroundColor(Theme.hex(0x1a1206).opacity(tonic ? 1 : 0.8))
                    .padding(.bottom, 3)
            }
            if tonic {
                Circle().fill(Theme.hex(0x1a1206)).frame(width: 4, height: 4)
                    .padding(.bottom, black ? 5 : 15)
            }
        }
        .shadow(color: tonic && !Theme.highContrast ? Theme.amberGlow : .clear, radius: 4)
        // black keys sit on the white ones: a dark gap around them
        .background(black ? shape.fill(Theme.hex(0x050604)).padding(-1.5) : nil)
    }
}

/// The source picker as a recessed field: the source's name, a ▾, and the input meter.
struct SourceField: View {
    let source: String
    let level: Float
    let listening: Bool
    let action: () -> Void
    static let segments = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SOURCE").font(Theme.face(6.5)).tracking(1.3).foregroundColor(Theme.textLo).lineLimit(1).fixedSize()
                    Text(source).font(.custom("HelveticaNeue", size: 11)).foregroundColor(Theme.textHi)
                        .lineLimit(1).truncationMode(.middle).layoutPriority(1)
                }
                Spacer(minLength: 0)
                meter
                Text("▾").font(Theme.face(9)).foregroundColor(Theme.amber(0.6))
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Theme.panelDeep.clipShape(shape))
            .innerShadow(shape, Color.black.opacity(0.9), blur: 5, y: 2)
            .ring(radius: 4, spread: 1, Theme.black)
            .background(shape.fill(Color.white.opacity(0.05)).offset(y: 1).padding(-1))
            .contentShape(shape)
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHand()
        .accessibility(label: Text("Listen to: \(source)"))
        .accessibility(hint: Text("Choose System Audio or an input"))
        .helpTip(HelpText.source)
    }

    /// Twelve LED segments: green, then amber, then red at the top.
    private var meter: some View {
        let n = LevelMeter.lit(listening ? level : 0, count: SourceField.segments)
        return HStack(spacing: 2) {
            ForEach(0..<SourceField.segments, id: \.self) { i in
                let c: Color = i >= 10 ? Theme.red : i >= 7 ? Theme.amber : Theme.green
                RoundedRectangle(cornerRadius: 0.8)
                    .fill(i < n ? c : c.opacity(Theme.highContrast ? 0.22 : 0.12))
                    .frame(width: 3, height: 6 + CGFloat(i) * 0.9)
            }
        }
        .frame(height: 18, alignment: .bottom)
        .accessibility(hidden: true)
    }
}

struct PocketGlow: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.amberGlow() } else { content }
    }
}
