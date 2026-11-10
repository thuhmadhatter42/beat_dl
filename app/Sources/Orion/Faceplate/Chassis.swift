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
    let status: Status

    /// live = listening, with the source's name (the popover header's LIVE · SOURCE).
    enum Status: Equatable { case ready, working, failed, live(String) }

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

struct StatusLegend: View {
    @Environment(\.palette) private var palette
    let status: Rail.Status

    var body: some View {
        let (word, text, lamp, glow): (String, Color, Color, Color) = {
            switch status {
            case .ready: return ("READY", Theme.greenText, Theme.green, Theme.greenGlow)
            case .working: return ("WORKING", palette.amber, palette.amber, palette.amberGlow)
            case .failed: return ("FAILED", Theme.redText, Theme.red, Theme.red.opacity(0.7))
            case .live(let source): return ("LIVE · \(source)", Theme.redText, Theme.red, Theme.red.opacity(0.7))
            }
        }()
        return HStack(spacing: Theme.S.s) {
            Circle().fill(lamp)
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5).blur(radius: 0.5).clipShape(Circle()))
                .frame(width: 8, height: 8)
                .shadow(color: glow, radius: 4)
            Text(word).labelStyle().foregroundColor(text)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 250, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text("Status: \(word.lowercased())"))
        .helpTip(HelpText.status)
    }
}
