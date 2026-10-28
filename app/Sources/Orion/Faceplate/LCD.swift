import AppKit
import SwiftUI

/// What the readout shows. Derived from the engine state plus the drag hover.
enum Readout {
    case idle
    case drop
    case working(stage: String, download: Bool)
    case result(Result, page: String?, download: Bool)
    case error(String, download: Bool)
    case doctor(DoctorReport)
}

/// The amber LCD: Artemis's `.lcd-hero` grown into the whole face.
struct LCD: View {
    let readout: Readout
    let highlighted: Bool
    var onPage: ((Int) -> Void)?

    private let r: CGFloat = 5

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        ZStack(alignment: .topLeading) {
            content
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // the glass
            Theme.vertical([(Color.white.opacity(0.07), 0), (Color.white.opacity(0), 0.45)])
                .allowsHitTesting(false)
        }
        .frame(height: 170)
        .background(Theme.vertical([(Theme.hex(0x0a0c09), 0), (Theme.hex(0x050604), 1)]))
        .clipShape(shape)
        .innerShadow(shape, Color.black.opacity(0.95), blur: 6, y: 2)
        .innerShadow(shape, Color.white.opacity(0.03), blur: 0, y: -1)
        .ring(radius: r, spread: 1, Theme.black)
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
        switch readout {
        case .idle: IdleReadout()
        case .drop: DropReadout()
        case let .working(stage, download): WorkingReadout(stage: stage, download: download)
        case let .result(r, page, _): ResultReadout(result: r, page: page, onPage: onPage)
        case let .error(m, download): ErrorReadout(message: m, download: download)
        case let .doctor(r): DoctorReadout(report: r)
        }
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
            }
            .accessibility(hidden: true)
        }
    }

    private var stepLights: [(String, Faceplate.Step)] {
        if Faceplate.isDoctorStage(stage) { return Faceplate.doctorSteps(stage) }
        return download ? Faceplate.steps(stage) : [("ANALYZE", .on)]
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
            }
        }
        .frame(height: 3)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Animation.timingCurve(0.4, 0, 0.2, 1, duration: 1.4).repeatForever(autoreverses: false)) {
                sweep = true
            }
        }
    }
}

struct ResultReadout: View {
    let result: Result

    let page: String?
    var onPage: ((Int) -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 30) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text.cap("BPM")
                        Text(result.bpm ?? "---.-").font(Theme.face(68).monospacedDigit()).tracking(68 * 0.02)
                            .foregroundColor(result.bpm == nil ? Theme.amber(0.12) : Theme.amber)
                            .modifier(GlowIf(on: result.bpm != nil))
                            .lineBox(68, 0.9)
                            .padding(.top, 6)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibility(label: Text(result.bpm.map { "BPM \($0)" } ?? "BPM not found"))

                    VStack(alignment: .leading, spacing: 0) {
                        Text.cap("KEY")
                        Text(result.keys.first?.0 ?? "--").font(Theme.face(34)).tracking(34 * 0.05)
                            .foregroundColor(result.keys.isEmpty ? Theme.amber(0.12) : Theme.amber)
                            .modifier(GlowIf(on: !result.keys.isEmpty))
                            .lineBox(34, 1)
                            .padding(.top, 6)
                        HStack(spacing: 14) {
                            ForEach(Array(result.keys.dropFirst().prefix(2).enumerated()), id: \.offset) { _, k in
                                Text("\(k.0) \(k.1)%").font(Theme.face(12).monospacedDigit()).tracking(12 * 0.08)
                                    .foregroundColor(Theme.amber(0.55))
                            }
                        }
                        .padding(.top, 9)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibility(label: Text(keyLabel))
                }
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    Text(Faceplate.fileLine(result)).font(Theme.face(10)).tracking(1.2)
                        .foregroundColor(Theme.amber(0.6))
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibility(label: Text(result.name))
                    Button(action: {
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
            }
            HStack(spacing: 7) {
                if let p = page {
                    HStack(spacing: 6) {
                        PageArrow(glyph: "‹", label: "Previous file") { onPage?(-1) }
                        Text.cap(p).accessibility(label: Text(p.lowercased()))
                        PageArrow(glyph: "›", label: "Next file") { onPage?(1) }
                    }
                    .padding(.trailing, 10)
                }
                if let period = Faceplate.tempoPeriod(result.bpm) {
                    Text.cap("TEMPO")
                    TempoLight(period: period)
                }
            }
            .offset(x: 2, y: 0)
        }
    }

    private var keyLabel: String {
        guard let first = result.keys.first else { return "Key not found" }
        let alts = result.keys.dropFirst().prefix(2).map { "\($0.0) \($0.1) percent" }
        return alts.isEmpty ? "Key \(first.0)" : "Key \(first.0), also \(alts.joined(separator: ", "))"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Faceplate.errorText(message)).font(Theme.face(15)).tracking(0.6)
                .foregroundColor(Theme.redText)
                .shadow(color: Theme.red.opacity(0.6), radius: 3)
                .shadow(color: Theme.red.opacity(0.3), radius: 8)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibility(label: Text(message))
            Text(Faceplate.failureHint(download: download))
                .font(Theme.face(9)).tracking(9 * 0.24)
                .foregroundColor(Theme.rgb(255, 106, 92, 0.6))
                .lineLimit(1)
                .padding(.top, 8)
        }
    }
}
