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
    var tuning: TuningMeter? = nil
    var onCycleTempo: (() -> Void)? = nil
    /// Live listening: the lamp and caption it chose (instead of the key's own confidence), and
    /// the source in place of the file line (no Show in Finder: there is no file).
    var live: (lamp: Lamp, status: String, source: String)? = nil
}

/// The amber LCD: Artemis's `.lcd-hero` grown into the whole face. The top shows the state
/// (BPM and the key dial for a reading); under it the popover's own KeyStrip (TOP KEYS, the
/// scale on a keyboard, the scale line), fed the same PocketState.
struct LCD: View {
    let state: PocketState
    let highlighted: Bool
    var actions = PocketActions()

    /// The other states' box (idle, working, error, Doctor, login...): 16 in from the glass's top,
    /// this high, then 8 to the KeyStrip's hairline row.
    static let topHeight: CGFloat = 148
    /// The band a reading is centred in (J 2026-11-09 14:23, "center them between the line above
    /// them and the line below them"): from the glass's top edge to the KeyStrip's hairline. The
    /// same 182 pt the old layout spent there, so the window keeps its height.
    static let bandHeight: CGFloat = Theme.S.l + topHeight + Theme.S.s + KeyStrip.ruleRowHeight / 2
    private let r: CGFloat = Theme.R.well

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            top.frame(maxWidth: .infinity).frame(height: LCD.bandHeight, alignment: .topLeading)
            // the hairline sits mid-row: pull the strip up half a row so the line ends the band
            KeyStrip(state: state, onTeach: actions.teachKey, keyboardHeight: FaceplateView.keyboardHeight)
                .padding(.top, -KeyStrip.ruleRowHeight / 2)
        }
        .padding(.bottom, Theme.S.l)
        .padding(.horizontal, Theme.S.lcd)
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

    /// A reading fills the band and centres itself in it; every other state keeps its box.
    @ViewBuilder private var top: some View {
        if case .result = state.readout {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: LCD.topHeight, alignment: .topLeading)
                .padding(.top, Theme.S.l)
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
    /// The amber-LCD glass (the window's readout, Advanced mode's harmony display, the pocket's
    /// readout, the Mini): the near-black face, the sheen across its top, the recess shadow and
    /// the black ring.
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

/// The start state: an invitation, not a skeleton of missing numbers (design pass F11).
struct IdleReadout: View {
    var body: some View {
        Centered {
            Text("Drop a beat").font(Theme.T.title).foregroundColor(Theme.A.a2)
            Text("or paste a YouTube link, open a file or listen").font(Theme.T.caption)
                .foregroundColor(Theme.A.a3).padding(.top, Theme.S.s)
        }
        .accessibilityElement(children: .combine)
    }
}

struct DropReadout: View {
    var body: some View {
        Centered {
            Text("DROP TO GET BPM AND KEY").font(Theme.T.title).tracking(Theme.T.titleTracking)
                .foregroundColor(Theme.A.a1)
            Text("The file stays where it is").font(Theme.T.caption).foregroundColor(Theme.A.a2)
                .padding(.top, Theme.S.s)
        }
    }
}

struct LoginReadout: View {
    let first: String
    let second: String
    var caption: String?
    var body: some View {
        Centered {
            Text(first).font(Theme.T.title).tracking(Theme.T.titleTracking).multilineTextAlignment(.center)
                .foregroundColor(Theme.A.a1)
            Text(second).labelStyle().foregroundColor(Theme.A.a2).multilineTextAlignment(.center)
                .padding(.top, Theme.S.s)
            if let c = caption {
                Text(c).font(Theme.T.caption).foregroundColor(Theme.A.a3)
                    .padding(.top, Theme.S.m)
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
            Text(Faceplate.stageText(stage)).font(Theme.T.title).tracking(Theme.T.titleTracking)
                .foregroundColor(Theme.A.a1)
                .accessibility(label: Text(Faceplate.stageText(stage).capitalized))
            RunningBar().padding(.top, Theme.S.m)
            Spacer(minLength: 0)
            HStack(spacing: Theme.S.l) {
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
            Text("LISTENING").font(Theme.T.title).tracking(Theme.T.titleTracking)
                .foregroundColor(Theme.A.a1)
            RunningBar().padding(.top, Theme.S.m)
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
            Text(report.title).font(Theme.T.key).tracking(Theme.T.keySize * 0.03)
                .foregroundColor(failed ? Theme.redText : Theme.A.a1)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.top, Theme.S.s)
            Spacer(minLength: 0)
            Text(report.line).captionStyle()
                .foregroundColor(failed ? Theme.rgb(255, 106, 92, 0.85) : Theme.A.a2)
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
        let t = Text(step == .done ? "✓ \(name)" : name).captionStyle()
        switch step {
        case .done: t.foregroundColor(Theme.A.a2)
        case .on: t.foregroundColor(Theme.A.a1)
        case .off: t.foregroundColor(Theme.A.a3)
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
                Theme.A.a4
                Theme.A.a1.frame(width: w)
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
    /// The popover's state and controls: the dial (key, confidence, manual reset) and the factor chips.
    var state = PocketState()
    var actions = PocketActions()

    private var bpmShown: String? { Tempo.text(result, factor: options.factor) }

    /// The window's dial (J 2026-11-09 14:23, "make them both bigger"): 128 -> 152, the pocket
    /// keeps 112. With the 182 pt band that leaves 15 above and 15 below.
    static let dialSide: CGFloat = 152
    /// The key name in the window's dial, grown with it (34 * 152 / 128, on the 4 grid). The one
    /// size off the type scale besides `bpmSize`, both for this readout only.
    static let dialKeySize: CGFloat = 40
    /// The window's BPM, whole number (J 2026-11-09 14:23, "bigger"): 68 -> 80; the decimals
    /// stay T.keySize. Off the six-size scale for this readout only.
    static let bpmSize: CGFloat = 80
    /// BPM column to dial.
    static let groupGap: CGFloat = Theme.S.l
    /// The readout's inner width (the module less the glass's padding).
    static var innerWidth: CGFloat { FaceplateView.moduleWidth - Theme.S.lcd * 2 }
    /// The BPM column: from the glass's text edge (the top keys' left edge, J 2026-11-09 14:23
    /// "move BPM slightly to the left") to the dial, which ends on the right text edge (MANUAL's).
    static var bpmWidth: CGFloat { innerWidth - groupGap - dialSide }

    var body: some View {
        // J 2026-11-09 14:23: the BPM column and the dial as one group, the BPM centred on the
        // dial's height, the group centred in the band (LCD.bandHeight) from the glass's top edge
        // to the hairline. The file line folds into the BPM column, so a file and Listen (no
        // file) sit the group in the same place and neither leaves an empty strip.
        HStack(alignment: .center, spacing: ResultReadout.groupGap) {
            bpmColumn.frame(width: ResultReadout.bpmWidth, alignment: .leading)
            Dial(state: state, side: ResultReadout.dialSide, keySize: ResultReadout.dialKeySize)
                .frame(width: ResultReadout.dialSide, height: ResultReadout.dialSide)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// BPM, the beat light and the x0.5 / x1 / x2 chips, then the number: the whole BPM big,
    /// its decimals small (the rounded echo and the lamp line are gone: each fact once, F3).
    private var bpmColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.S.s) {
                Text.cap("BPM")
                if let period = Faceplate.tempoPeriod(bpmShown) {
                    TempoLight(period: period)
                }
                Spacer(minLength: Theme.S.xs)
                // Advanced mode: the x0.5 / x1 / x2 chips. Default: a click on the BPM cycles them
                // (and Reading › Half / Double Tempo); only a factor other than x1 is tagged.
                if state.advanced {
                    FactorChips(factor: options.factor, enabled: bpmShown != nil, set: actions.setFactor)
                } else if let tag = options.factor.label, bpmShown != nil {
                    Text(tag).font(Theme.T.caption.monospacedDigit()).foregroundColor(Theme.A.a2)
                        .accessibility(label: Text(options.factor == .double ? "Double time" : "Half time"))
                        .helpTip(HelpText.tempoFactor)
                }
            }
            .frame(height: Theme.H.sm)
            // J 2026-11-09 14:44: "slide this part up a tiny bit by itself" (the number stays put).
            .offset(y: -6)
            bpmNumber.padding(.top, Theme.S.s)
                .accessibilityElement(children: .ignore)
                .accessibility(label: Text(bpmLabel))
                .helpTip(HelpText.bpm)
            fileLines.padding(.top, Theme.S.m)
        }
    }

    /// Under the BPM: the file (yours, in its own case: name warm white, folder dimmer) or the
    /// note, then paging and Show in Finder. Nothing while listening: the rail already says LIVE
    /// and the source. Tallest case: 20 + 8 + 72 + 12 + 16 + 4 + 16 = 148, inside the 152 dial.
    @ViewBuilder private var fileLines: some View {
        if note != nil || options.live == nil {
            VStack(alignment: .leading, spacing: Theme.S.xs) {
                fileText
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Theme.H.xs)
                    .accessibility(label: Text(note ?? result.name))
                    .helpTip(HelpText.fileLine)
                if page != nil || options.live == nil {
                    HStack(spacing: Theme.S.m) {
                        if let p = page {
                            HStack(spacing: Theme.S.xs) {
                                PageArrow(glyph: "‹", label: "Previous file") { actions.page(-1) }
                                Text(p).captionStyle().foregroundColor(Theme.A.a2).accessibility(label: Text(p.lowercased()))
                                PageArrow(glyph: "›", label: "Next file") { actions.page(1) }
                            }
                        }
                        if options.live == nil { FinderLink(file: result.file) }
                    }
                    .frame(height: Theme.H.xs)
                }
            }
        }
    }

    private var fileText: Text {
        if let n = note { return Text(n).font(Theme.T.caption).foregroundColor(Theme.A.a2) }
        let p = Faceplate.fileParts(result)
        return Text(p.name).font(Theme.T.body).foregroundColor(Theme.textHi)
            + Text("  ·  \(p.folder)").font(Theme.T.body).foregroundColor(Theme.textLo)
    }

    /// The big BPM. A click cycles x1 / x2 / x0.5 when there is a BPM to cycle.
    @ViewBuilder private var bpmNumber: some View {
        let number = BPMNumber(text: bpmShown, whole: ResultReadout.bpmSize, fraction: Theme.T.keySize)
            .lineBox(ResultReadout.bpmSize, 0.9)
        if bpmShown != nil, let cycle = options.onCycleTempo {
            Button(action: cycle) { number.contentShape(Rectangle()) }
                .buttonStyle(PlainButtonStyle())
                .pointingHand()
        } else {
            number
        }
    }

    private var bpmLabel: String {
        guard let b = bpmShown else { return "BPM not found" }
        let time = options.factor == .double ? ", double time" : (options.factor == .half ? ", half time" : "")
        return "BPM \(b)\(time)" + (options.onCycleTempo == nil ? "" : ". Click to switch between normal, double and half time")
    }
}

/// SHOW IN FINDER ›: a text link, A2 brightening to A1 on hover.
private struct FinderLink: View {
    let file: URL
    @State private var hover = false

    var body: some View {
        Button(action: {
            AppLog.log("window: show in finder")
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }) {
            Text("SHOW IN FINDER ›").captionStyle()
                .foregroundColor(hover ? Theme.A.a1 : Theme.A.a2)
                .fixedSize()
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .pointingHand()
        .accessibility(label: Text("Show in Finder"))
        .helpTip(HelpText.showInFinder)
    }
}

/// A small lit lamp and a caption: green LOCKED, amber UNSURE, red ANALYZING / LISTENING.
struct StateLamp: View {
    let lamp: Lamp
    let text: String
    var body: some View {
        HStack(spacing: Theme.S.s) {
            // the shape says the state without the colour (octagon / triangle / circle)
            LampShape(lamp: lamp).fill(lamp.color).frame(width: 8, height: 8)
                .shadow(color: Theme.highContrast ? .clear : lamp.color.opacity(0.8), radius: 3)
            Text(text).captionStyle().foregroundColor(lamp.textColor).lineLimit(1)
        }
    }
}

extension View {
    /// The pointing-hand cursor over a clickable legend (CSS `cursor: pointer`).
    func pointingHand() -> some View {
        onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
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
            Text(Faceplate.errorText(message)).font(Theme.T.title)
                .foregroundColor(Theme.redText)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibility(label: Text(message))
            Text(hint ?? Faceplate.failureHint(download: download))
                .captionStyle()
                .foregroundColor(Theme.rgb(255, 106, 92, Theme.highContrast ? 1 : 0.75))
                .lineLimit(1)
                .padding(.top, Theme.S.s)
        }
    }
}
