import AppKit
import SwiftUI

/// What the readout shows. Derived from the engine state plus the drag hover.
enum Readout {
    case idle
    case drop
    case working(stage: String, download: Bool)
    case result(Result, page: String?, download: Bool, note: String? = nil, options: ResultOptions = ResultOptions())
    /// hint = the line under the error; nil = Run Doctor (or the link) as always.
    case error(String, download: Bool, hint: String? = nil)
    case doctor(DoctorReport)
    /// Amber next step, not a failure: (first line, second line).
    case login(String, String, caption: String?)
    /// Live listening with nothing to say yet: the red lamp and its caption.
    case listening(status: String)
}

/// How a result is dressed beyond the analyzer's numbers: the tempo factor the BPM click chose,
/// the tuning line (nil = none to show), and what a click on the BPM does.
struct ResultOptions {
    var factor: TempoFactor = .one
    var tuning: String? = nil
    var onCycleTempo: (() -> Void)? = nil
    /// Live listening: the lamp and caption it chose (instead of the key's own confidence), and
    /// the source in place of the file line (no Show in Finder: there is no file).
    var live: (lamp: Lamp, status: String, source: String)? = nil
    /// A click on the key switches its spelling (Ebm <-> D#m); nil = no click.
    var onToggleSpelling: (() -> Void)? = nil
}

/// The amber LCD: Artemis's `.lcd-hero` grown into the whole face. The top shows the state
/// (BPM and the key dial for a reading); under it the popover's own KeyStrip (TOP KEYS, the
/// scale on a keyboard, the scale line), fed the same PocketState.
struct LCD: View {
    let state: PocketState
    let highlighted: Bool
    var actions = PocketActions()

    /// The state area's height: the dial (112) beside the BPM, the file line under both.
    static let topHeight: CGFloat = 130
    private let r: CGFloat = 5

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: LCD.topHeight, alignment: .topLeading)
            KeyStrip(state: state, onTeach: actions.teachKey, keyboardHeight: FaceplateView.keyboardHeight).padding(.top, 8)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .lcdGlass(radius: r)
        .background(highlighted ? AnyView(dropRing(shape)) : AnyView(EmptyView()))
    }

    /// `0 0 0 2px amber, 0 0 22px rgba(amber,.35)` when a file hovers over the window.
    private func dropRing(_ shape: RoundedRectangle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: r + 2, style: .continuous).fill(Theme.amber(0.35))
                .padding(-2).blur(radius: 11)
            RoundedRectangle(cornerRadius: r + 2, style: .continuous).fill(Theme.amber).padding(-2)
        }
    }

    @ViewBuilder private var content: some View {
        switch state.readout {
        case .idle: IdleReadout()
        case .drop: DropReadout()
        case let .working(stage, download): WorkingReadout(stage: stage, download: download)
        case let .result(r, page, _, note, o):
            ResultReadout(result: r, page: page, note: note, options: o, state: state, actions: actions)
        case let .error(m, download, hint): ErrorReadout(message: m, download: download, hint: hint)
        case let .doctor(r): DoctorReadout(report: r)
        case let .login(a, b, c): LoginReadout(first: a, second: b, caption: c)
        case let .listening(status): ListeningReadout(status: status)
        }
    }
}

extension View {
    /// The window's amber-LCD glass: the near-black face, the sheen across its top, the recess
    /// shadow and the black ring (the readout's and Advanced mode's harmony display).
    func lcdGlass(radius r: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        return overlay(Theme.vertical([(Color.white.opacity(Theme.highContrast ? 0 : 0.07), 0), (Color.white.opacity(0), 0.45)])
            .allowsHitTesting(false))
        .background(Theme.highContrast ? Theme.vertical([(Theme.black, 0), (Theme.black, 1)])
                                       : Theme.vertical([(Theme.hex(0x0a0c09), 0), (Theme.hex(0x050604), 1)]))
        .clipShape(shape)
        .innerShadow(shape, Color.black.opacity(0.95), blur: 6, y: 2)
        .innerShadow(shape, Color.white.opacity(0.03), blur: 0, y: -1)
        .ring(radius: r, spread: 1, Theme.black)
    }
}

private struct Centered<C: View>: View {
    let c: C
    init(@ViewBuilder _ c: () -> C) { self.c = c() }
    var body: some View {
        VStack(spacing: 0) { c }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct IdleReadout: View {
    var body: some View {
        Centered {
            Text("---.-").font(Theme.face(58).monospacedDigit()).tracking(58 * 0.06)
                .foregroundColor(Theme.amber(0.12))
                .accessibility(hidden: true)
            Text.cap("PASTE A LINK · OPEN OR DROP A BEAT").padding(.top, 10)
        }
    }
}

struct DropReadout: View {
    var body: some View {
        Centered {
            Text("DROP TO GET BPM AND KEY").font(Theme.face(18)).tracking(0.9)
                .foregroundColor(Theme.amber).amberGlow()
            Text.cap("THE FILE STAYS WHERE IT IS").padding(.top, 10)
        }
    }
}

struct LoginReadout: View {
    let first: String
    let second: String
    var caption: String?
    var body: some View {
        Centered {
            Text(first).font(Theme.face(18)).tracking(0.9).multilineTextAlignment(.center)
                .foregroundColor(Theme.amber).amberGlow()
            Text.cap(second).multilineTextAlignment(.center).padding(.top, 10)
            if let c = caption {
                Text(c).font(Theme.face(8)).tracking(0.4).foregroundColor(Theme.amber(0.45))
                    .padding(.top, 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text("\(first.capitalized). \(second.lowercased())"))
    }
}

struct WorkingReadout: View {
    let stage: String
    let download: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Faceplate.stageText(stage)).font(Theme.face(18)).tracking(0.9)
                .foregroundColor(Theme.amber).amberGlow()
                .accessibility(label: Text(Faceplate.stageText(stage).capitalized))
            RunningBar().padding(.top, 14)
            Spacer(minLength: 0)
            HStack(spacing: 20) {
                ForEach(stepLights, id: \.0) { name, step in
                    StepLabel(name: name, step: step)
                }
                if stage == "analyzing" {
                    Spacer(minLength: 0)
                    StateLamp(lamp: .listening, text: "ANALYZING")
                }
            }
            .accessibility(hidden: true)
        }
    }

    private var stepLights: [(String, Faceplate.Step)] {
        if Faceplate.isDoctorStage(stage) { return Faceplate.doctorSteps(stage) }
        return download ? Faceplate.steps(stage) : [("ANALYZE", .on)]
    }
}

/// Live listening before the first reading (and again after a gap): the empty readout, the
/// running bar, the red lamp.
struct ListeningReadout: View {
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LISTENING").font(Theme.face(18)).tracking(0.9)
                .foregroundColor(Theme.amber).amberGlow()
            RunningBar().padding(.top, 14)
            Spacer(minLength: 0)
            StateLamp(lamp: .listening, text: status)
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text("Listening. \(status.lowercased())"))
    }
}

/// Beat Key › Run Doctor's result: amber DOCTOR OK / DOCTOR FIXED IT, or red with the one thing to do.
struct DoctorReadout: View {
    let report: DoctorReport

    var body: some View {
        let failed = report.outcome == .failed
        VStack(alignment: .leading, spacing: 0) {
            Text.cap("DOCTOR")
            Group {
                if failed {
                    Text(report.title).font(Theme.face(26)).tracking(26 * 0.04)
                        .foregroundColor(Theme.redText)
                        .shadow(color: Theme.red.opacity(0.6), radius: 3)
                        .shadow(color: Theme.red.opacity(0.3), radius: 8)
                } else {
                    Text(report.title).font(Theme.face(34)).tracking(34 * 0.05)
                        .foregroundColor(Theme.amber).amberGlow()
                }
            }
            .lineLimit(1)
            .padding(.top, 8)
            Spacer(minLength: 0)
            Text(report.line).font(Theme.face(10)).tracking(1.2)
                .foregroundColor(failed ? Theme.rgb(255, 106, 92, 0.85) : Theme.amber(0.6))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text("\(report.title.capitalized). \(report.line.lowercased())"))
    }
}

private struct StepLabel: View {
    let name: String
    let step: Faceplate.Step
    var body: some View {
        let t = Text(step == .done ? "✓ \(name)" : name).font(Theme.face(8)).tracking(2.4)
        switch step {
        case .done: t.foregroundColor(Theme.amber(0.55))
        case .on: t.foregroundColor(Theme.amber).shadow(color: Theme.amberGlow, radius: 2.5)
        case .off: t.foregroundColor(Theme.rgb(235, 235, 240, 0.2))
        }
    }
}

/// A 3 pt track with a 40% amber slug sweeping across (static under Reduce Motion).
struct RunningBar: View {
    static let sweepAnimation = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 1.4).repeatForever(autoreverses: false)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width * 0.4
            ZStack(alignment: .leading) {
                Theme.amber(0.1)
                Theme.amber.frame(width: w)
                    .shadow(color: Theme.amberGlow, radius: 4)
                    .offset(x: reduceMotion ? 0 : (sweep ? w * 2.6 : -w))
                    // the repeat is scoped to the slug's offset alone
                    .animation(sweep ? RunningBar.sweepAnimation : nil, value: sweep)
            }
        }
        .frame(height: 3)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .onAppear {
            guard !reduceMotion else { return }
            // Not withAnimation(repeatForever) here: onAppear runs inside the parent's first layout
            // pass, and a repeating transaction there captures every frame change around it (the
            // 0.1.11 permission sheet replayed its own appearance every 1.4 s). Start the sweep a
            // turn later, once that layout has settled.
            DispatchQueue.main.async { sweep = true }
        }
        .onDisappear { sweep = false }
    }
}

struct ResultReadout: View {
    let result: Result

    let page: String?
    var note: String? = nil
    var options = ResultOptions()
    /// The popover's state and controls: the dial (key, confidence, respell) and the factor chips.
    var state = PocketState()
    var actions = PocketActions()

    private var bpmShown: String? { Tempo.text(result, factor: options.factor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 22) {
                bpmColumn
                Dial(state: state, actions: actions).frame(width: 112, height: 112)
                    .overlay(camelot, alignment: .leading)
            }
            .frame(height: 112)
            Spacer(minLength: 0)
            fileRow
        }
    }

    /// BPM, its rounded value, the beat light and the x0.5 / x1 / x2 chips; the confidence lamp.
    private var bpmColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text.cap("BPM")
                if let r = Tempo.rounded(result, factor: options.factor) {
                    Text(r).font(Theme.face(8)).tracking(1.6).foregroundColor(Theme.amber(0.45))
                }
                if let period = Faceplate.tempoPeriod(bpmShown) {
                    TempoLight(period: period).padding(.leading, 2)
                }
                Spacer(minLength: 4)
                // Advanced mode: the x0.5 / x1 / x2 chips. Default: a click on the BPM cycles them
                // (and Reading › Half / Double Tempo); only a factor other than x1 is tagged.
                if state.advanced {
                    HStack(spacing: 4) {
                        ForEach([TempoFactor.half, .one, .double], id: \.self) { f in
                            FactorChip(factor: f, on: f == options.factor, enabled: bpmShown != nil) { actions.setFactor(f) }
                        }
                    }
                } else if let tag = options.factor.label, bpmShown != nil {
                    Text(tag).font(Theme.face(8).monospacedDigit()).foregroundColor(Theme.amber(0.7))
                        .accessibility(label: Text(options.factor == .double ? "Double time" : "Half time"))
                }
            }
            .frame(height: 15)
            bpmNumber.padding(.top, 6)
                .accessibilityElement(children: .ignore)
                .accessibility(label: Text(bpmLabel))
            Spacer(minLength: 0)
            statusLine
        }
    }

    /// Advanced mode: the key's Camelot code and its relative key, just left of the dial (below
    /// the factor chips, clear of the BPM).
    @ViewBuilder private var camelot: some View {
        if state.advanced, let key = result.keys.first?.0, let code = Camelot.code(key) {
            CamelotBadge(code: code, relative: Camelot.relative(key)).frame(width: 40).offset(x: -46, y: 6)
        }
    }

    /// The file (or Listen's source, or the note), paging, Show in Finder: the readout's width.
    private var fileRow: some View {
        HStack(spacing: 10) {
            Text(lineText)
                .font(Theme.face(10)).tracking(1.2)
                .foregroundColor(Theme.amber(note == nil ? 0.6 : 0.8))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibility(label: Text(note ?? options.live.map { "Live, \($0.source)" } ?? result.name))
            if let p = page {
                HStack(spacing: 6) {
                    PageArrow(glyph: "‹", label: "Previous file") { actions.page(-1) }
                    Text.cap(p).accessibility(label: Text(p.lowercased()))
                    PageArrow(glyph: "›", label: "Next file") { actions.page(1) }
                }
            }
            if options.live == nil { finderButton }
        }
    }

    /// The note (a partial analysis), Listen's source, or the file and its folder.
    private var lineText: String {
        if let n = note { return n }
        if let l = options.live { return "LIVE · \(l.source.uppercased())" }
        return Faceplate.fileLine(result)
    }

    private var finderButton: some View {
        Button(action: {
            AppLog.log("window: show in finder")
            NSWorkspace.shared.activateFileViewerSelecting([result.file])
        }) {
            Text("SHOW IN FINDER ›").font(Theme.face(9)).tracking(1.8)
                .foregroundColor(Theme.amber)
                .shadow(color: Theme.amberGlow, radius: 2.5)
                .fixedSize()
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHand()
        .accessibility(label: Text("Show in Finder"))
    }

    /// The big BPM. A click cycles x1 / x2 / x0.5 when there is a BPM to cycle.
    @ViewBuilder private var bpmNumber: some View {
        let text = Text(bpmShown ?? "---.-").font(Theme.face(68).monospacedDigit()).tracking(68 * 0.02)
            .foregroundColor(bpmShown == nil ? Theme.amber(0.12) : Theme.amber)
            .modifier(GlowIf(on: bpmShown != nil))
            .lineBox(68, 0.9)
        if bpmShown != nil, let cycle = options.onCycleTempo {
            Button(action: cycle) { text.contentShape(Rectangle()) }
                .buttonStyle(PlainButtonStyle())
                .pointingHand()
        } else {
            text
        }
    }

    /// Confidence lamp (locked / unsure), one line above the file line. (The tuning is on the
    /// scale line under the keyboard.)
    @ViewBuilder private var statusLine: some View {
        if let c = options.live?.status ?? Faceplate.confidenceLine(result.keys),
           let lamp = options.live?.lamp ?? Lamp.of(result.keys) {
            StateLamp(lamp: lamp, text: c)
                .accessibilityElement(children: .ignore)
                .accessibility(label: Text(c.lowercased()))
        }
    }

    private var bpmLabel: String {
        guard let b = bpmShown else { return "BPM not found" }
        let time = options.factor == .double ? ", double time" : (options.factor == .half ? ", half time" : "")
        return "BPM \(b)\(time)" + (options.onCycleTempo == nil ? "" : ". Click to switch between normal, double and half time")
    }
}

/// A small lit lamp and a caption: green LOCKED, amber UNSURE, red ANALYZING / LISTENING.
struct StateLamp: View {
    let lamp: Lamp
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            // the shape says the state without the colour (octagon / triangle / circle)
            LampShape(lamp: lamp).fill(lamp.color).frame(width: 8, height: 8)
                .shadow(color: Theme.highContrast ? .clear : lamp.color.opacity(0.8), radius: 3)
            Text(text).font(Theme.face(9)).tracking(1.4).foregroundColor(lamp.textColor).lineLimit(1)
        }
    }
}

/// A small amber chevron that pages through dropped files (the arrow keys do the same).
private struct PageArrow: View {
    let glyph: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(glyph).font(Theme.face(12)).foregroundColor(Theme.amber(0.7))
                .frame(width: 14, height: 14).contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHand()
        .accessibility(label: Text(label))
    }
}

extension View {
    /// The pointing-hand cursor over a clickable legend (CSS `cursor: pointer`).
    func pointingHand() -> some View {
        onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}

private struct GlowIf: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.amberGlow() } else { content }
    }
}

/// Flashes once per beat (20% on, `steps(1)`). Steady when Reduce Motion is on or the window
/// is not key.
struct TempoLight: View {
    let period: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var active
    @State private var lit = true
    @State private var timer: Timer?

    var body: some View {
        Circle().fill(Theme.amber)
            .frame(width: 7, height: 7)
            .shadow(color: Theme.amberGlow, radius: 4)
            .opacity(lit ? 1 : 0.15)
            .onAppear(perform: restart)
            .onDisappear(perform: stop)
            .onChange(of: reduceMotion) { _ in restart() }
            .onChange(of: active) { _ in restart() }
            .onChange(of: period) { _ in restart() }
            .accessibility(hidden: true)
    }

    private var running: Bool { !reduceMotion && active == .key }

    private func restart() {
        stop()
        lit = true
        guard running else { return }
        let p = period
        let t = Timer(timeInterval: p, repeats: true) { _ in
            lit = true
            DispatchQueue.main.asyncAfter(deadline: .now() + p * 0.2) { if timer != nil { lit = false } }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + p * 0.2) { if timer != nil { lit = false } }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}

struct ErrorReadout: View {
    let message: String
    let download: Bool
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Faceplate.errorText(message)).font(Theme.face(15)).tracking(0.6)
                .foregroundColor(Theme.redText)
                .shadow(color: Theme.red.opacity(0.6), radius: 3)
                .shadow(color: Theme.red.opacity(0.3), radius: 8)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibility(label: Text(message))
            Text(hint ?? Faceplate.failureHint(download: download))
                .font(Theme.face(9)).tracking(9 * 0.24)
                .foregroundColor(Theme.rgb(255, 106, 92, 0.6))
                .lineLimit(1)
                .padding(.top, 8)
        }
    }
}
