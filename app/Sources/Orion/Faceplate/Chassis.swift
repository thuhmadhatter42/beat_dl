import SwiftUI

/// The mockup's `.plate`: noise-and-sheen chassis, black outer rings, four screws.
struct Plate<Content: View>: View {
    let content: Content
    /// FaceplateView.plateWidth: the default window's plate; Advanced mode widens it for the harmony column.
    var width: CGFloat
    init(width: CGFloat, @ViewBuilder content: () -> Content) { self.width = width; self.content = content() }

    private let r: CGFloat = 12


    var body: some View {
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        content
            .padding(12)
            .frame(width: width)
            .background(
                ZStack {
                    Theme.vertical([(Theme.hex(0x232326), 0), (Theme.hex(0x191a1c), 0.4), (Theme.hex(0x131315), 1)])
                    // 115deg sheen across the plate
                    LinearGradient(gradient: Gradient(stops: [
                        .init(color: Color.white.opacity(0), location: 0.32),
                        .init(color: Color.white.opacity(0.05), location: 0.46),
                        .init(color: Color.white.opacity(0), location: 0.60)]),
                        startPoint: UnitPoint(x: -0.036, y: 0.119), endPoint: UnitPoint(x: 1.036, y: 0.881))
                    Theme.vertical([(Color.white.opacity(0.06), 0), (Color.white.opacity(0), 0.04)])
                    if let n = Textures.noise {
                        Image(nsImage: n).resizable(resizingMode: .tile)
                    }
                }
                .clipShape(shape)
            )
            .innerShadow(shape, Color.white.opacity(0.07), blur: 0, y: 1)
            .overlay(screws)
            .ring(radius: r, spread: 1, Theme.black)
            .ring(radius: r, spread: 3, Theme.hex(0x0c0c0d))
            .ring(radius: r, spread: 4, Theme.black)
            .dropShadow(radius: r, Color.black.opacity(0.75), blur: 55, y: 26)
    }

    private var screws: some View {
        VStack {
            HStack { Screw(); Spacer(); Screw() }
            Spacer()
            HStack { Screw(); Spacer(); Screw() }
        }
        .padding(6)
    }
}

/// A silver corner screw with its slot at 32 degrees.
struct Screw: View {
    var body: some View {
        Circle()
            .fill(RadialGradient(gradient: Gradient(stops: [
                .init(color: Theme.hex(0xdcdce0), location: 0),
                .init(color: Theme.hex(0x85858a), location: 0.45),
                .init(color: Theme.hex(0x2e2e31), location: 1)]),
                center: UnitPoint(x: 0.34, y: 0.30), startRadius: 0, endRadius: 9.6))
            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.5).blur(radius: 0.5).clipShape(Circle()))
            .overlay(
                Rectangle().fill(Color.black.opacity(0.75))
                    .frame(width: 7.6, height: 1.1)
                    .rotationEffect(.degrees(32)))
            .frame(width: 10, height: 10)
            .background(Circle().fill(Color.white.opacity(0.03)).padding(-3))
            .background(Circle().fill(Color.black.opacity(0.55)).padding(-2))
            .shadow(color: Color.black.opacity(0.9), radius: 1, y: 1)
            .accessibility(hidden: true)
    }
}

/// The brushed header rail: chrome wordmark left, lamp + legend right.
struct Rail: View {
    let status: AppStatus

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.R.well, style: .continuous)
        HStack {
            Wordmark()
            Spacer()
            StatusLegend(status: status)
        }
        .padding(.horizontal, 22)
        .frame(height: 58)
        .background(
            ZStack {
                Theme.vertical([(Theme.hex(0x202023), 0), (Theme.hex(0x161618), 1)])
                if let b = Textures.brushed {
                    Image(nsImage: b).resizable(resizingMode: .tile)
                }
            }
            .clipShape(shape))
        .innerShadow(shape, Color.white.opacity(0.07), blur: 0, y: 1)
        .innerShadow(shape, Color.black.opacity(0.6), blur: 4, y: -2)
        .dropShadow(radius: Theme.R.well, Color.black.opacity(0.5), blur: 4, y: 2)
    }
}

/// BEAT KEY (Brand.wordmark) in Helvetica Neue Bold, .22em tracking, chrome gradient.
struct Wordmark: View {
    var body: some View {
        let t = Text(Brand.wordmark).font(Theme.face(24)).tracking(24 * 0.22)
        t.foregroundColor(.clear)
            .overlay(
                Theme.vertical([(Theme.hex(0xf4f4f6), 0), (Theme.hex(0xababb0), 0.55), (Theme.hex(0xcbcbcf), 1)])
                    .mask(t))
            .lineBox(24, 1)
            .accessibility(label: Text(Brand.name))
    }
}

/// The app's status as both surfaces say it: the window's rail and the pocket's header draw the
/// same StatusLegend from this one derivation, word and colour.
enum AppStatus: Equatable {
    /// live = listening, with the source's name (LIVE · SOURCE).
    case ready, working, failed, live(String)

    /// LIVE · <source> while listening, else the readout's state; a failed Run Doctor is FAILED.
    static func of(_ s: PocketState) -> AppStatus {
        if s.listening { return .live(s.source.uppercased()) }
        switch s.readout {
        case .working: return .working
        case .error: return .failed
        case .doctor(let r): return r.outcome == .failed ? .failed : .ready
        default: return .ready
        }
    }

    var word: String {
        switch self {
        case .ready: return "READY"
        case .working: return "WORKING"
        case .failed: return "FAILED"
        case .live(let source): return "LIVE · \(source)"
        }
    }

    /// The lamp's outline (Lamp's colour-blind shapes): settled = the octagon, under way or
    /// failed = the circle.
    var shape: Lamp { self == .ready ? .locked : .listening }

    /// The word's colour, the lamp's fill and its glow (High Contrast: no glow, as everywhere).
    struct Look: Equatable {
        let text: Color
        let lamp: Color
        let glow: Color
    }

    func look(_ palette: Palette) -> Look {
        let l: Look = {
            switch self {
            case .ready: return Look(text: Theme.greenText, lamp: Theme.green, glow: Theme.greenGlow)
            case .working: return Look(text: palette.amber, lamp: palette.amber, glow: palette.amberGlow)
            case .failed, .live: return Look(text: Theme.redText, lamp: Theme.red, glow: Theme.red.opacity(0.7))
            }
        }()
        return palette.highContrast ? Look(text: l.text, lamp: l.lamp, glow: .clear) : l
    }
}

/// The status lamp and word (AppStatus), in the window's rail and the pocket's header; only the
/// sizes differ (Metrics).
struct StatusLegend: View {
    @Environment(\.palette) private var palette
    let status: AppStatus
    var metrics: Metrics = .regular

    struct Metrics: Equatable {
        let lampSide: CGFloat
        /// Lamp to word.
        let gap: CGFloat
        /// The word truncates in the middle past this (a long source name).
        let maxWidth: CGFloat
        let glowRadius: CGFloat

        /// The window's 58 pt rail.
        static let regular = Metrics(lampSide: 8, gap: Theme.S.s, maxWidth: 250, glowRadius: 4)
        /// The pocket's H.sm header.
        static let compact = Metrics(lampSide: 7, gap: 6, maxWidth: 200, glowRadius: 3)
    }

    var body: some View {
        let look = status.look(palette)
        let shape = LampShape(lamp: status.shape)
        return HStack(spacing: metrics.gap) {
            shape.fill(look.lamp)
                .overlay(shape.stroke(Color.white.opacity(0.6), lineWidth: 0.5).blur(radius: 0.5).clipShape(shape))
                .frame(width: metrics.lampSide, height: metrics.lampSide)
                .shadow(color: look.glow, radius: metrics.glowRadius)
            Text(status.word).labelStyle().foregroundColor(look.text)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: metrics.maxWidth, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text("Status: \(status.word.lowercased())"))
        .helpTip(HelpText.status)
    }
}
