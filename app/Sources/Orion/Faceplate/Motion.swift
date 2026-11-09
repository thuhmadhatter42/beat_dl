import SwiftUI

// The pieces that make live readings move instead of snap (Theme.Motion has the timings).
// macOS 12 safe: AnimatableModifier for counting numbers, id + opacity transitions for swaps.

/// A number counting from one reading to the next (pure, so it can be tested).
enum NumberTween {
    /// The value `t` (0...1) of the way from `a` to `b`.
    static func interpolate(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let f = min(max(t, 0), 1)
        return a + (b - a) * f
    }

    /// What a counting number shows mid-flight: the nearest whole number (so 41.6 reads "42"), no
    /// "-0", never NaN.
    static func whole(_ v: Double) -> Int {
        guard v.isFinite else { return 0 }
        let r = v.rounded()
        return r == 0 ? 0 : Int(r)
    }

    static func text(_ v: Double, suffix: String = "") -> String { "\(whole(v))\(suffix)" }
}

/// A whole number that counts to its new value when the change is animated (the top keys'
/// percentages). SwiftUI interpolates `animatableData`; the body only formats it.
struct CountingNumber: AnimatableModifier {
    var value: Double
    var suffix: String = ""

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        Text(NumberTween.text(value, suffix: suffix))
    }
}

extension View {
    /// `animation` for changes of `value`, but only once the view has a reading: the first reading
    /// lands at once (no counting up from zero, no bars growing from nothing), the next ones move.
    func liveAnimation<V: Equatable>(_ animation: Animation?, value: V, live: Bool) -> some View {
        modifier(LiveAnimation(animation: animation, value: value, live: live))
    }
}

private struct LiveAnimation<V: Equatable>: ViewModifier {
    let animation: Animation?
    let value: V
    let live: Bool
    /// True once a reading is on show. Updated after the body that shows it, so the change that
    /// brings the first reading sees `false` and lands instantly.
    @State private var armed = false

    func body(content: Content) -> some View {
        content
            .animation(armed ? animation : nil, value: value)
            .onAppear { armed = live }
            .onChange(of: live) { armed = $0 }
    }
}

/// One thing replacing another (a key name, LOCKED / UNSURE, the chords): the old one fades out
/// as the new one fades in, in the same spot, so the layout never jumps. Keyed by `value`; any
/// other change inside just updates in place.
struct Crossfade<V: Hashable, Content: View>: View {
    let value: V
    var alignment: Alignment = .center
    let content: (V) -> Content

    init(_ value: V, alignment: Alignment = .center, @ViewBuilder content: @escaping (V) -> Content) {
        self.value = value
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        ZStack(alignment: alignment) {
            content(value).id(value).transition(.opacity)
        }
        .animation(Theme.Motion.swap, value: value)
    }
}
