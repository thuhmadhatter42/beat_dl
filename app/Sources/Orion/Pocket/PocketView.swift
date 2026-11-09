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
        VStack(spacing: Theme.S.l) {
            PocketHeader(state: state)
            PocketLCD(state: state, actions: actions)
            module
            footer
        }
        .padding(Theme.S.l)
        .frame(width: Pocket.width)
        .environment(\.helpMode, state.help)
        .helpTipLayer()
        .background(PocketPlate())
        .id(state.highContrast)   // Theme.highContrast is read while drawing
    }

    // MARK: module: download, listen, send (on the plate itself: no extra panel box)

    private var module: some View {
        let g = Theme.S.s
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: g) {
                LinkField(text: $url, focused: $fieldFocused, onSubmit: { actions.downloadPressed(state) })
                DownloadCap(state: state, action: { actions.downloadPressed(state) })
                    .frame(width: Pocket.downloadCapWidth)
            }
            HStack(spacing: g) {
                ListenCap(state: state, action: actions.toggleListen).frame(width: Pocket.listenCapWidth)
                SourceField(source: state.source, level: state.level, listening: state.listening,
                            action: actions.pickSource)
            }
            .padding(.top, g)
            if state.listening {
                // HOLD and the reset key sit under LISTEN, the pair as wide as LISTEN's cap
                HStack(spacing: Pocket.transportGap) {
                    HoldCap(state: state, height: Theme.H.md, action: actions.toggleHold)
                    NewSongCap(lit: true, keys: state.newSongKeys, height: Theme.H.md, action: actions.newSong)
                }
                .frame(width: Pocket.listenCapWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, g)
            }
            ModuleRule().padding(.vertical, Theme.S.l)
            VStack(spacing: g) {
                HStack(spacing: g) {
                    ActionCap(title: "ANALYZE FILE", ready: !state.busy, label: "Analyze a file", action: actions.analyzeFile)
                        .helpTip(HelpText.analyzeFile)
                    SendDAWCap(state: state, action: actions.sendDAW)
                }
                HStack(spacing: g) {
                    AutoTuneCap(state: state, send: actions.sendAutoTune)
                    ExportMidiCap(state: state, action: actions.exportMidi)
                }
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: Theme.S.l) {
            RecentLink(state: state, action: actions.showRecents)
            FooterLink(title: "WINDOW", label: "Show the Beat Key window", action: actions.openWindow)
                .helpTip(HelpText.window)
            FooterLink(title: "SETTINGS", label: "Settings", action: actions.settings).helpTip(HelpText.settings)
            HelpChip(on: state.help, action: actions.toggleHelp)
            Spacer()
            FooterLink(title: "QUIT", label: Brand.quit, action: actions.quit).helpTip(HelpText.quit)
        }
        .frame(height: Theme.H.xs)
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
        .buttonStyle(SSLCapStyle(lit: state.downloadLit || state.clipboardReady || (login && !state.busy),
                                 height: Theme.H.lg))
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
    var height: CGFloat = Theme.H.lg
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
        .buttonStyle(SSLCapStyle(lit: !state.listening && !state.busy, ready: state.listening, height: height))
        .accessibility(label: Text(state.listening ? "Stop listening" : "Start listening to \(state.source)"))
        .helpTip(HelpText.listen)
    }
}

/// NEW SONG · RESET as a square key beside HOLD: Listen drops what it heard and its lock, and
/// starts over. The icon is the legend; the words live in the tooltip and VoiceOver.
struct NewSongCap: View {
    let lit: Bool
    var keys: String? = nil
    /// Square: as wide as it is tall (H.lg in the window's field row, H.md under LISTEN).
    var height: CGFloat = Theme.H.lg
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: Theme.T.labelSize, weight: .bold))
                .frame(width: height - SSLCapStyle.ring * 2)
        }
        .buttonStyle(SSLCapStyle(lit: false, ready: lit, height: height, padding: 0))
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
    var height: CGFloat = Theme.H.lg
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "pause.fill").font(.system(size: 9, weight: .bold))
                SSLCapStyle.label("HOLD").lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SSLCapStyle(lit: state.held, ready: state.canHold && !state.held, height: height))
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
    /// The legend's side padding: the window's narrow send caps pass S.xs so SEND TO AUTO-TUNE fits.
    var padding: CGFloat = SSLCapStyle.sidePadding
    let action: () -> Void
    var body: some View {
        Button(action: { if ready { action() } }) {
            SSLCapStyle.label(title).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SSLCapStyle(lit: false, ready: ready, padding: padding))
        .accessibility(label: Text(label))
    }
}

/// SEND TO <the DAW that is open>.
struct SendDAWCap: View {
    let state: PocketState
    var padding: CGFloat = SSLCapStyle.sidePadding
    let action: () -> Void
    var body: some View {
        let daw = state.daw.map { "SEND TO \($0.uppercased())" } ?? "SEND TO DAW"
        ActionCap(title: daw, ready: state.canSend, label: daw.capitalized, padding: padding, action: action)
            .helpTip(HelpText.sendDAW)
    }
}

/// SEND TO AUTO-TUNE: flashes SENT ✓ (or NO KEY) for a moment after the press.
struct AutoTuneCap: View {
    let state: PocketState
    var padding: CGFloat = SSLCapStyle.sidePadding
    let send: () -> Bool
    @State private var flash: String?
    var body: some View {
        ActionCap(title: flash ?? "SEND TO AUTO-TUNE", ready: state.canAutoTune, label: "Send key to Auto-Tune",
                  padding: padding) {
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
            Text(title).captionStyle()
                .foregroundColor(!enabled ? Theme.textFaint : hover ? Theme.textHi : Theme.textLo)
                .frame(height: Theme.H.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover = $0 }
        .pointingHand()
        .accessibility(label: Text(label))
    }
    @State private var hover = false
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
        HStack(spacing: Theme.S.s) {
            KeyGlyph().frame(width: 22, height: 13)
            let t = Text(Brand.wordmark).font(Theme.T.label).tracking(Theme.T.labelSize * 0.24)
            t.foregroundColor(.clear)
                .overlay(Theme.vertical([(Theme.hex(0xf4f4f6), 0), (Theme.hex(0xababb0), 0.55), (Theme.hex(0xcbcbcf), 1)]).mask(t))
                .fixedSize()
                .accessibility(label: Text(Brand.name))
            Spacer()
            legend
        }
        .frame(height: Theme.H.sm)
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
            Text(word).labelStyle().foregroundColor(color).lineLimit(1)
                .truncationMode(.middle).frame(maxWidth: 200).fixedSize(horizontal: true, vertical: false)
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
        let shape = RoundedRectangle(cornerRadius: Theme.R.well, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Theme.S.l) {
                Dial(state: state, actions: actions).frame(width: Dial.side, height: Dial.side)
                right.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Dial.side)
            KeyStrip(state: state, onTeach: actions.teachKey, keyboardHeight: Pocket.keyboardHeight).padding(.top, Theme.S.s)
        }
        .padding(Theme.S.l)
        .lcdGlass(radius: Theme.R.well)
        .background(shape.fill(Color.white.opacity(0.05)).offset(y: 1).padding(-1))
    }

    // MARK: right of the dial

    @ViewBuilder private var right: some View {
        switch state.readout {
        case .result(let r, let page, _, let note, let o):
            ResultSide(result: r, page: page, note: note, options: o, state: state, actions: actions)
        case .working(let stage, let download):
            VStack(alignment: .leading, spacing: 0) {
                Text(Faceplate.stageText(stage)).font(Theme.T.title).tracking(Theme.T.titleTracking)
                    .foregroundColor(Theme.A.a1).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                RunningBar().padding(.top, Theme.S.m)
                HStack(spacing: Theme.S.s) {
                    ForEach(steps(stage, download), id: \.0) { name, step in
                        Text(step == .done ? "✓ \(name)" : name).captionStyle()
                            .lineLimit(1).fixedSize()
                            .foregroundColor(step == .on ? Theme.A.a1 : step == .done ? Theme.A.a2 : Theme.A.a3)
                    }
                }
                .padding(.top, Theme.S.m)
            }
            .accessibilityElement(children: .ignore)
            .accessibility(label: Text(Faceplate.stageText(stage).capitalized))
        case .listening(let status):
            VStack(alignment: .leading, spacing: 0) {
                Text("LISTENING").font(Theme.T.title).tracking(Theme.T.titleTracking).foregroundColor(Theme.A.a1)
                RunningBar().padding(.top, Theme.S.m)
            }
            .accessibilityElement(children: .ignore)
            .accessibility(label: Text("Listening. \(status.lowercased())"))
        case .error(let m, let download, let hint):
            VStack(alignment: .leading, spacing: Theme.S.s) {
                Text(Faceplate.errorText(m)).font(Theme.T.value)
                    .foregroundColor(Theme.redText)
                    .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                Text(hint ?? Faceplate.failureHint(download: download)).captionStyle()
                    .foregroundColor(Theme.rgb(255, 106, 92, Theme.highContrast ? 1 : 0.75)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibility(label: Text(m))
        case .login(let a, let b, _):
            message(a, b)
        case .doctor(let r):
            message(r.title, r.line, red: r.outcome == .failed)
        case .idle, .drop:
            // the empty state: an invitation, not a skeleton of missing numbers (F11)
            VStack(alignment: .leading, spacing: Theme.S.s) {
                Text("Drop a beat").font(Theme.T.title).foregroundColor(Theme.A.a2)
                Text("or paste a YouTube link, open a file or listen").font(Theme.T.caption)
                    .foregroundColor(Theme.A.a3).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibility(label: Text("No reading yet. Paste a link, analyze a file or listen."))
        }
    }

    private func message(_ a: String, _ b: String, red: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.S.s) {
            Text(a).font(Theme.T.value).foregroundColor(red ? Theme.redText : Theme.A.a1)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Text(b).captionStyle().foregroundColor(red ? Theme.redText : Theme.A.a2)
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
            HStack(spacing: Theme.S.m) {
                Rectangle().fill(Theme.A.a4).frame(height: 1)
                if let teach = onTeach {
                    ManualKeyMenu(enabled: state.result != nil, action: teach).helpTip(HelpText.manual)
                }
            }
            .frame(height: Theme.H.sm)
            TopKeys(keys: state.result?.keys ?? [],
                    onChoose: state.result.map { r in { k in SpellingSettings.shared.choose(k, of: r, from: "top keys") } })
                .helpTip(HelpText.topKeys)
                .padding(.top, Theme.S.s)
            NoteKeyboard(scale: state.scale).frame(height: keyboardHeight).helpTip(HelpText.keyboard)
                .padding(.top, Theme.S.m)
            scaleLine.padding(.top, Theme.S.s)
            TuningMeterRow(meter: state.options?.tuning).padding(.top, Theme.S.s)
        }
    }

    /// "C minor  C D E♭ F G A♭ B♭": the key's name and its notes (nothing until there is a key).
    private var scaleLine: some View {
        // a new key crossfades in place (Motion.swap)
        Crossfade(state.scale.map { "\($0.tonicName)\($0.minor ? "m" : "")" } ?? "", alignment: .leading) { _ in
            HStack(alignment: .firstTextBaseline, spacing: Theme.S.m) {
                if let s = state.scale {
                    Text("\(s.tonicName) \(s.minor ? "minor" : "major")").font(Theme.T.value)
                        .foregroundColor(Theme.A.a2)
                    Text(s.spelled.joined(separator: "  ")).font(Theme.T.body)
                        .foregroundColor(Theme.A.a3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 16)
        .helpTip(HelpText.scale)
        .accessibilityElement(children: .combine)
    }
}

/// TUNING (J 2026-11-09, Orra's meter in Beat Key's amber): a thin −50 ¢ … +50 ¢ track with a
/// centre tick and a marker at the offset (green within ±5 ¢), then "+0.1 ct  A4 = 440.0 Hz".
/// Always drawn, so the readout never jumps: no reading = a dim track and a dash.
/// J 2026-11-09: the track's centre tick (0 ct) sits on the panel's centre line; TUNING ends 12 pt
/// left of the track, the reading starts 12 pt right of it (so the row as a whole sits left of centre).
struct TuningMeterRow: View {
    let meter: TuningMeter?

    static let height: CGFloat = 12
    static let markerWidth: CGFloat = 4
    /// TUNING to the track, the track to the reading.
    static let gap: CGFloat = Theme.S.m
    /// Room for the reading: "−50.0 ct  A4 = 452.9 Hz" is 106.5 pt at the caption size.
    static let textWidth: CGFloat = 108
    /// TUNING at the caption size and tracking (44 pt).
    static let labelWidth: CGFloat = 44

    /// Where the row's three parts go in a row `width` wide (x from the row's left edge): the track
    /// is centred on width / 2 and as long as the wider side (label or reading) allows.
    struct Layout: Equatable {
        /// TUNING's right edge.
        let labelRight: CGFloat
        let trackX: CGFloat
        let trackWidth: CGFloat
        let textX: CGFloat
        var trackCentre: CGFloat { trackX + trackWidth / 2 }
    }

    static func layout(width: CGFloat) -> Layout {
        let side = max(textWidth, labelWidth) + gap
        let half = max(0, (width / 2 - side).rounded(.down))
        let x = width / 2 - half
        return Layout(labelRight: x - gap, trackX: x, trackWidth: half * 2, textX: x + half * 2 + gap)
    }

    var body: some View {
        GeometryReader { g in
            let l = TuningMeterRow.layout(width: g.size.width)
            let h = TuningMeterRow.height
            ZStack(alignment: .topLeading) {
                Text("TUNING").captionStyle().foregroundColor(Theme.A.a3).lineLimit(1).fixedSize()
                    .frame(width: max(0, l.labelRight), height: h, alignment: .trailing)
                track.frame(width: l.trackWidth, height: h).offset(x: l.trackX)
                Text(meter?.text ?? "—").font(Theme.T.caption.monospacedDigit())
                    .foregroundColor(meter == nil ? Theme.A.a3 : Theme.A.a2).lineLimit(1).fixedSize()
                    .frame(height: h).offset(x: l.textX)
            }
        }
        .frame(height: TuningMeterRow.height)
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text(meter?.spoken ?? "Tuning: no reading"))
        .helpTip(HelpText.tuning)
    }

    private var track: some View {
        GeometryReader { g in
            let w = g.size.width, mid = g.size.height / 2
            ZStack(alignment: .topLeading) {
                Capsule().fill(Theme.A.a4).frame(width: w, height: 2).offset(y: mid - 1)
                // −25 / +25 ticks faint, the centre brighter
                ForEach([0.25, 0.5, 0.75], id: \.self) { f in
                    Rectangle().fill(f == 0.5 ? Theme.A.a3 : Theme.A.a4)
                        .frame(width: 1, height: f == 0.5 ? 8 : 4)
                        .offset(x: (w * CGFloat(f)).rounded() - 0.5, y: mid - (f == 0.5 ? 4 : 2))
                }
                if let m = meter {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(m.inTune ? Theme.green : Theme.amber)
                        .frame(width: TuningMeterRow.markerWidth, height: g.size.height)
                        .offset(x: TuningMeterRow.markerX(m.fraction, width: w))
                        .animation(Theme.Motion.value, value: m.cents)
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

/// MANUAL ⌄: set the key by hand. The LCD's one chip recipe with a chevron that says it drops a
/// list: the 24 keys; the pick becomes THE key and the reading is saved to teach Beat Key. Dim
/// with no reading.
struct ManualKeyMenu: View {
    let enabled: Bool
    let action: () -> Void
    static let height: CGFloat = Theme.H.sm

    var body: some View {
        ChipMenuButton(title: "MANUAL", enabled: enabled, action: action)
            .nativeHelp("Set the key by hand: pick it from all 24 keys. It becomes the key, and the reading is saved to teach Beat Key")
            .accessibility(label: Text("Manual key"))
            .accessibility(hint: Text("Opens a menu of all 24 keys. The pick becomes the key and teaches Beat Key"))
    }
}

/// A chip that opens a menu (MANUAL ⌄, MATCH TO's key): the segmented chips' recipe, one segment,
/// a chevron 4 pt after the text.
struct ChipMenuButton: View {
    let title: String
    var enabled = true
    /// UPPERCASE legends are tracked; a key name ("Am") is not.
    var tracked = true
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.R.cap, style: .continuous)
        Button(action: { if enabled { action() } }) {
            HStack(spacing: Theme.S.xs) {
                Text(title).font(Theme.T.caption).tracking(tracked ? Theme.T.captionTracking : 0)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(enabled ? Theme.A.a2 : Theme.A.a3)
            .padding(.horizontal, Theme.S.s)
            .frame(height: Theme.H.sm)
            .background(shape.fill(hover && enabled ? Theme.A.a4 : Theme.A.a5))
            .overlay(shape.stroke(Theme.A.a4, lineWidth: 1))
            .contentShape(shape)
            .fixedSize()
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .pointingHand()
    }
}

/// The confidence dial around the key: twelve ticks (the icon's dial), a track, and an arc in
/// the lamp's colour as long as the top key's confidence. The key sits in the middle, the lamp's
/// shape and word under it, so the state reads without colour. The percentage itself is in the
/// top keys (each fact once, design pass F3).
struct Dial: View {
    let state: PocketState
    var actions = PocketActions()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    /// The pocket's dial; the window's is `ResultReadout.dialSide`.
    static let side: CGFloat = 112
    /// The box the dial fills: the ticks sit on its edge, the ring 12 inside it.
    var side: CGFloat = Dial.side

    var body: some View {
        let lamp = state.lamp
        let color = isWorking ? Theme.amber : (lamp.map { $0.color } ?? Theme.amber)
        let key = state.result?.keys.first?.0
        ZStack {
            // ticks
            ForEach(0..<12, id: \.self) { i in
                Capsule().fill(i % 3 == 0 ? Theme.A.a3 : Theme.A.a4)
                    .frame(width: i % 3 == 0 ? 2 : 1.5, height: i % 3 == 0 ? 7 : 5)
                    .offset(y: -(side / 2 - 4.5))
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            Circle().stroke(Theme.A.a5, lineWidth: 5).padding(12)
            if let c = state.confidence {
                // the arc eases to each new confidence; its colour crossfades with the lamp
                Circle().trim(from: 0, to: CGFloat(c))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .animation(Theme.Motion.swap, value: lamp)
                    .rotationEffect(.degrees(-90))
                    .padding(12)
                    .shadow(color: Theme.highContrast ? .clear : color.opacity(0.7), radius: 4)
                    .animation(Theme.Motion.value, value: c)
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
            VStack(spacing: Theme.S.xs) {
                keyButton(key)
                // LOCKED / UNSURE / HELD crossfade (Motion.swap)
                Crossfade(key != nil ? lamp.map { state.held ? "HELD" : $0.spoken.uppercased() } ?? "KEY" : "KEY") { _ in
                    if let l = lamp, key != nil {
                        HStack(spacing: Theme.S.xs) {
                            LampShape(lamp: l).fill(l.color).frame(width: 7, height: 7)
                            Text(state.held ? "HELD" : l.spoken.uppercased()).captionStyle()
                                .foregroundColor(l.textColor).lineLimit(1).fixedSize()
                        }
                        .helpTip(HelpText.confidence)
                    } else {
                        Text("KEY").captionStyle().foregroundColor(Theme.A.a3)
                    }
                }
            }
            .frame(width: side - 32)
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
        // a new key crossfades over the old one in the same spot (Motion.swap)
        let text = Crossfade(key ?? "--") { k in
            Text(k).font(Theme.T.key)
                .foregroundColor(key == nil ? Theme.A.a4 : Theme.A.a1)
                .lineLimit(1).minimumScaleFactor(0.6)
                .modifier(PocketGlow(on: key != nil))
        }
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

/// The BPM as the readout draws it (J 2026-11-09, "decimals small"): the whole number big and
/// glowing, the decimals smaller and one step dimmer, on one baseline. No BPM = dim dashes.
struct BPMNumber: View {
    let text: String?
    let whole: CGFloat
    let fraction: CGFloat

    /// Each part crossfades on its own (Motion.swap): 120.4 → 120.5 fades only the decimals, the
    /// whole number stays put; no counting, so a wobbling live tempo never looks busy.
    var body: some View {
        Crossfade(text == nil, alignment: .leading) { _ in
            if let t = text {
                let p = Tempo.split(t)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Crossfade(p.whole, alignment: .trailing) { w in
                        Text(w).font(Theme.face(whole).monospacedDigit()).tracking(whole * 0.02)
                            .foregroundColor(Theme.A.a1).amberGlow()
                    }
                    if let f = p.fraction {
                        Crossfade(f, alignment: .leading) { f in
                            Text(f).font(Theme.face(fraction).monospacedDigit())
                                .foregroundColor(Theme.A.a2)
                        }
                    }
                }
                .lineLimit(1)
                .fixedSize()
            } else {
                Text("---").font(Theme.face(whole).monospacedDigit()).foregroundColor(Theme.A.a4)
                    .lineLimit(1).fixedSize()
            }
        }
    }
}

/// BPM (clickable, x0.5 / x1 / x2 chips) and the file line beside the dial.
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
            HStack(spacing: Theme.S.s) {
                Text.cap("BPM")
                Spacer(minLength: Theme.S.xs)
                FactorChips(factor: options.factor, enabled: bpm != nil, set: actions.setFactor)
            }
            .frame(height: Theme.H.sm)
            Button(action: { options.onCycleTempo?() }) {
                BPMNumber(text: bpm, whole: Theme.T.keySize, fraction: Theme.T.titleSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .pointingHand()
            .padding(.top, Theme.S.s)
            .accessibility(label: Text(bpm.map { "BPM \($0)" } ?? "BPM not found"))
            .accessibility(hint: Text("Click to switch between normal, double and half time"))
            .helpTip(HelpText.bpm)
            if showsFileRow {
                Spacer(minLength: 0)
                fileRow
            }
        }
    }

    /// No file line while listening (the header already says LIVE and the source): the BPM then
    /// sits centred beside the dial.
    private var showsFileRow: Bool { note != nil || options.live == nil }

    /// The file's name (yours: warm white, its own case) or the note; nothing while listening
    /// (the header already says LIVE and the source).
    @ViewBuilder private var fileRow: some View {
        if note != nil || options.live == nil {
            HStack(spacing: Theme.S.xs) {
                Text(note ?? (result.name as NSString).deletingPathExtension)
                    .font(note == nil ? Theme.T.body : Theme.T.caption)
                    .foregroundColor(note == nil ? Theme.textHi : Theme.A.a2)
                    .lineLimit(1).truncationMode(.middle)
                    .helpTip(HelpText.fileLine)
                if let p = page {
                    Spacer(minLength: 2)
                    PageArrow(glyph: "‹", label: "Previous file") { actions.page(-1) }
                    Text(p).captionStyle().foregroundColor(Theme.A.a2).fixedSize()
                    PageArrow(glyph: "›", label: "Next file") { actions.page(1) }
                }
            }
        }
    }
}

/// ×0.5 / ×1 / ×2 as one segmented control.
struct FactorChips: View {
    let factor: TempoFactor
    let enabled: Bool
    let set: (TempoFactor) -> Void

    var body: some View {
        SegmentedChips(options: [TempoFactor.half, .one, .double].map { f in
                           .init(value: f, title: f.label ?? "×1",
                                 spoken: f == .one ? "Normal time" : f == .double ? "Double time" : "Half time")
                       },
                       selected: factor, enabled: enabled, width: .fixed(34), onSelect: set)
            .helpTip(HelpText.tempoFactor)
    }
}

/// How wide a chip's segments are.
enum ChipWidth: Equatable {
    /// The legend plus 8 pt each side.
    case fit
    /// Every segment this wide.
    case fixed(CGFloat)
    /// The segments share the width they are given.
    case fill
}

/// The LCD's one segmented control (design pass F9): one object, 20 pt high, radius 3, an A4
/// outline with A4 dividers and no gaps. Unselected = A2 legend on an A5 fill; selected = an A1
/// fill with dark ink; hover = an A4 wash. The BPM factor, the chord choices, the transpose
/// strip and every single chip (MINI, SOUND) are this control.
struct SegmentedChips<V: Hashable>: View {
    struct Option {
        let value: V
        let title: String
        let spoken: String
    }

    let options: [Option]
    let selected: V?
    var enabled = true
    var width: ChipWidth = .fit
    /// A small tick under this option (the transpose strip's 0).
    var marked: V? = nil
    /// nil = a display, not a control (the transpose strip).
    var onSelect: ((V) -> Void)? = nil
    /// More than one lit at once (a tritone lights −6 and +6); nil = just `selected`.
    var lit: Set<V>? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.R.cap, style: .continuous)
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                if i > 0 { Rectangle().fill(Theme.A.a4).frame(width: 1) }
                ChipSegment(title: o.title, spoken: o.spoken, on: lit?.contains(o.value) ?? (o.value == selected), enabled: enabled,
                            marked: marked == o.value, width: width,
                            action: onSelect.map { f in { f(o.value) } })
            }
        }
        .frame(height: Theme.H.sm)
        .background(Theme.A.a5)
        .clipShape(shape)
        .overlay(shape.stroke(Theme.A.a4, lineWidth: 1))
        .fixedSize(horizontal: width != .fill, vertical: false)
    }
}

private struct ChipSegment: View {
    let title: String
    let spoken: String
    let on: Bool
    let enabled: Bool
    let marked: Bool
    let width: ChipWidth
    let action: (() -> Void)?
    @State private var hover = false

    var body: some View {
        let lit = on && enabled
        let face = Text(title).font(Theme.T.caption.monospacedDigit())
            .tracking(title.count > 2 && title.uppercased() == title ? Theme.T.captionTracking : 0)
            .foregroundColor(lit ? Theme.A.ink : enabled ? Theme.A.a2 : Theme.A.a3)
            .lineLimit(1)
            .padding(.horizontal, width == .fit ? Theme.S.s : 0)
            .frame(width: fixed, height: Theme.H.sm)
            .frame(maxWidth: width == .fill ? .infinity : nil)
            .background(lit ? Theme.A.a1 : on ? Theme.A.a4 : (hover && enabled && action != nil ? Theme.A.a4 : Color.clear))
            .overlay(marked ? Rectangle().fill(lit ? Theme.A.ink : Theme.A.a3).frame(width: 10, height: 2)
                                .padding(.bottom, 2) : nil, alignment: .bottom)
        if let act = action {
            Button(action: { if enabled { act() } }) { face.contentShape(Rectangle()) }
                .buttonStyle(PlainButtonStyle())
                .onHover { hover = $0 }
                .animation(.easeOut(duration: 0.12), value: hover)
                .pointingHand()
                .accessibility(label: Text(spoken))
                .accessibility(addTraits: on ? .isSelected : [])
        } else {
            face
        }
    }

    private var fixed: CGFloat? {
        if case .fixed(let w) = width { return w }
        return nil
    }
}

/// A single chip (MINI, SOUND): the segmented control with one segment, lit when on.
struct LCDChip: View {
    let title: String
    let on: Bool
    var enabled = true
    let label: String
    var width: CGFloat? = nil
    let action: () -> Void
    var body: some View {
        SegmentedChips(options: [.init(value: 0, title: title, spoken: label)], selected: on ? 0 : nil,
                       enabled: enabled, width: width.map { .fixed($0) } ?? .fit, onSelect: { _ in action() })
    }
}

/// A small amber chevron that pages through dropped files (the arrow keys do the same).
struct PageArrow: View {
    let glyph: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(glyph).font(Theme.T.value).foregroundColor(Theme.A.a2)
                .frame(width: 16, height: 16).contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHand()
        .accessibility(label: Text(label))
    }
}

/// Beat Key's headline: the three likeliest keys with their percentages and a bar each. A click
/// on key 2 or 3 makes it THE key: it moves to the front, the dial and the sends use it.
/// No reading = the row keeps its height but draws nothing (an empty state, not a skeleton).
///
/// J 2026-11-09 03:42 ("the certainty percent is so far away from its key; it's closer to the next
/// key than to the key it's talking about"): each key is one group, `1 Ab 85%`, the percent right
/// after its name on the same baseline, a size smaller and one amber step dimmer, the bar under
/// the group. Groups sit `groupGap` apart, far more than anything inside a group (proximity).
struct TopKeys: View {
    let keys: [(String, Int)]
    var onChoose: ((String) -> Void)? = nil

    /// Between the three groups.
    static let groupGap: CGFloat = Theme.S.xl
    /// Rank to name, inside a group.
    static let rankGap: CGFloat = Theme.S.xs
    /// Name to its percent, inside a group.
    static let percentGap: CGFloat = Theme.S.s

    var body: some View {
        HStack(alignment: .top, spacing: TopKeys.groupGap) {
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
        // percentages count and bars ease between readings; the first reading lands at once
        .liveAnimation(Theme.Motion.value, value: keys.prefix(3).map { $0.1 }, live: !keys.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text(keys.isEmpty ? "No keys yet"
            : "Top keys: " + keys.prefix(3).map { "\($0.0) \($0.1) percent" }.joined(separator: ", ")))
    }

    private func cell(_ i: Int, _ k: (String, Int)?) -> some View {
        let first = i == 0
        return VStack(alignment: .leading, spacing: Theme.S.s) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(i + 1)").font(Theme.T.caption.monospacedDigit()).foregroundColor(Theme.A.a3)
                    .padding(.trailing, TopKeys.rankGap)
                Crossfade(k?.0 ?? " ", alignment: .leading) { name in
                    Text(name).font(Theme.T.title)
                        .foregroundColor(first ? Theme.A.a1 : Theme.A.a2)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.trailing, TopKeys.percentGap)
                Color.clear.frame(width: 0, height: 0)
                    .modifier(CountingNumber(value: Double(k?.1 ?? 0), suffix: "%"))
                    .font(Theme.T.value.monospacedDigit())
                    .foregroundColor(first ? Theme.A.a2 : Theme.A.a3)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            // a name of another width: its percent slides along with the crossfade (Motion.swap)
            .animation(Theme.Motion.swap, value: k?.0)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.A.a5)
                    Capsule().fill(first ? Theme.A.a1 : Theme.A.a3)
                        .frame(width: g.size.width * CGFloat(min(100, max(0, k?.1 ?? 0))) / 100)
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .opacity(k == nil ? 0 : 1)   // keeps its height: the readout never jumps
    }

    // MARK: layout, measured (pure; the tests hold the proximity rule to it)

    /// Where each group's pieces land in a strip `width` wide, measured with the row's own fonts:
    /// `own` = the gap from a name's end to its percent, `next` = from that percent's end to the
    /// next group's rank (nil for the last group).
    static func gaps(width: CGFloat, keys: [(String, Int)]) -> [(own: CGFloat, next: CGFloat?)] {
        let cell = (width - groupGap * 2) / 3
        func w(_ s: String, _ size: CGFloat, _ face: String) -> CGFloat {
            let f = NSFont(name: face, size: size) ?? NSFont.boldSystemFont(ofSize: size)
            return ceil((s as NSString).size(withAttributes: [.font: f]).width)
        }
        return keys.prefix(3).enumerated().map { i, k in
            let used = w("\(i + 1)", Theme.T.captionSize, "HelveticaNeue-Medium") + rankGap
                + w(k.0, Theme.T.titleSize, "HelveticaNeue-Bold") + percentGap
                + w("\(k.1)%", Theme.T.valueSize, "HelveticaNeue-Bold")
            return (own: percentGap, next: i < 2 ? max(0, cell - used) + groupGap : nil)
        }
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
        // lit keys, the tonic and its dot crossfade to the new key (Motion.swap)
        .animation(Theme.Motion.swap, value: scale)
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text(scale.map { "Scale: " + $0.spelled.joined(separator: ", ") } ?? "No scale yet"))
    }

    private func key(_ pc: Int, black: Bool) -> some View {
        let on = scale?.notes.contains(pc) ?? false
        let tonic = scale?.tonic == pc
        let shape = RoundedRectangle(cornerRadius: Theme.R.cap, style: .continuous)
        // tonic A1, the scale's other notes A3, the rest an A5 body with an A4 edge
        let fill: Color = tonic ? Theme.A.a1 : on ? Theme.A.a3 : (black ? Theme.hex(0x070806) : Theme.A.a5)
        return ZStack(alignment: .bottom) {
            shape.fill(fill)
            shape.stroke(on ? Color.clear : Theme.A.a4, lineWidth: 1)
            if !black, let s = scale, on {
                Text(s.name(pc)).font(Theme.T.caption).foregroundColor(Theme.A.ink)
                    .padding(.bottom, Theme.S.xs)
            }
            if tonic {
                Circle().fill(Theme.A.ink).frame(width: 4, height: 4)
                    .padding(.bottom, black ? 6 : 18)
            }
        }
        // black keys sit on the white ones: a dark gap around them
        .background(black ? shape.fill(Theme.hex(0x050604)).padding(-1.5) : nil)
    }
}

/// The source picker as a recessed field: the source's name, a ▾, and the input meter.
struct SourceField: View {
    let source: String
    let level: Float
    let listening: Bool
    /// The gap between the meter's segments: the window's narrower field passes 1.
    var meterGap: CGFloat = 2
    let action: () -> Void
    static let segments = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.R.well, style: .continuous)
        Button(action: action) {
            // 8 between the name and the meter and between the meter and the chevron (the spacer
            // takes no gap of its own on either side)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("SOURCE").captionStyle().foregroundColor(Theme.textLo).lineLimit(1).fixedSize()
                    Text(source).font(Theme.T.body).foregroundColor(Theme.textHi)
                        .lineLimit(1).truncationMode(.middle).layoutPriority(1)
                }
                Spacer(minLength: Theme.S.s)
                meter
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(Theme.A.a2)
                    .padding(.leading, Theme.S.s)
            }
            .padding(.horizontal, Theme.S.m)
            .frame(height: Theme.H.lg)
            .background(Theme.panelDeep.clipShape(shape))
            .innerShadow(shape, Color.black.opacity(0.9), blur: 5, y: 2)
            .ring(radius: Theme.R.well, spread: 1, Theme.black)
            .background(shape.fill(Color.white.opacity(0.05)).offset(y: 1).padding(-1))
            .contentShape(shape)
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHand()
        .accessibility(label: Text("Listen to: \(source)"))
        .accessibility(hint: Text("Choose System Audio or an input"))
        .helpTip(HelpText.source)
    }

    /// Listen's own level object when the app put one in the environment (the window and the
    /// popover): only the segments observe it, so its 20 Hz ticks never redraw the rest of the
    /// face. nil = `level` (offscreen renders and tests).
    @Environment(\.liveLevel) private var liveLevel

    @ViewBuilder private var meter: some View {
        if let l = liveLevel {
            LiveMeterSegments(meter: l, listening: listening, gap: meterGap)
        } else {
            MeterSegments(level: level, listening: listening, gap: meterGap)
        }
    }
}

/// The meter's segments fed by Listen's level object (redrawn alone on each tick).
private struct LiveMeterSegments: View {
    @ObservedObject var meter: LiveLevel
    let listening: Bool
    let gap: CGFloat
    var body: some View { MeterSegments(level: meter.value, listening: listening, gap: gap) }
}

private struct LiveLevelKey: EnvironmentKey {
    static let defaultValue: LiveLevel? = nil
}

extension EnvironmentValues {
    /// Listen's input level for the source field's meter (LiveController.meter).
    var liveLevel: LiveLevel? {
        get { self[LiveLevelKey.self] }
        set { self[LiveLevelKey.self] = newValue }
    }
}

/// Twelve LED segments: green, then amber, then red at the top.
private struct MeterSegments: View {
    let level: Float
    let listening: Bool
    let gap: CGFloat

    var body: some View {
        let n = LevelMeter.lit(listening ? level : 0, count: SourceField.segments)
        return HStack(spacing: gap) {
            ForEach(0..<SourceField.segments, id: \.self) { i in
                let c: Color = i >= 10 ? Theme.red : i >= 7 ? Theme.amber : Theme.green
                RoundedRectangle(cornerRadius: 1)
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
