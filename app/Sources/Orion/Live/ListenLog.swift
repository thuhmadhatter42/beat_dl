import Foundation

// What Listen writes to beatkey.log (J, 2026-11-09 23:22: "a missing log is a failure"; Studio D's
// dead meter left no trace of what it heard). Pure pieces, unit-tested: the once-a-second input
// level, the silence guard that widens System Audio to every app, and the on-change reading line.

/// One second of input, as the log prints it.
struct LevelSecond: Equatable {
    /// nil = no samples arrived at all (System Audio sends nothing while nothing plays).
    let peakDB: Float?
    let rmsDB: Float?

    /// Quieter than this peak counts as no signal.
    static let silentDB: Float = -70

    var silent: Bool { (peakDB ?? -.infinity) < LevelSecond.silentDB }

    /// "level -12.3 dBFS peak, -24.1 dBFS rms", "level silent (peak -83.0 dBFS)", "level silent (no audio arriving)".
    var text: String {
        guard let p = peakDB, let r = rmsDB else { return "level silent (no audio arriving)" }
        if silent { return "level silent (peak \(LevelSecond.db(p)) dBFS)" }
        return "level \(LevelSecond.db(p)) dBFS peak, \(LevelSecond.db(r)) dBFS rms"
    }

    static func db(_ v: Float) -> String { v.isFinite ? String(format: "%.1f", v) : "-inf" }

    /// dBFS of a linear amplitude (0 = -inf).
    static func dbfs(_ x: Double) -> Float { x > 0 ? Float(20 * log10(x)) : -.infinity }
}

/// Adds up a second of samples on the audio thread (one pass, no allocation), handed out once a
/// second by the meter's timer. The 20 Hz meter itself never logs.
struct LevelWindow {
    private(set) var peak: Float = 0
    private(set) var sumSquares: Double = 0
    private(set) var count = 0

    mutating func add(_ samples: [Float]) {
        add(samples, peak: samples.reduce(Float(0)) { max($0, abs($1)) })
    }

    /// `peak` = the piece's loudest |sample|, already worked out for the meter.
    mutating func add(_ samples: [Float], peak pk: Float) {
        var sq: Float = 0
        for s in samples { sq += s * s }
        peak = max(peak, pk); sumSquares += Double(sq); count += samples.count
    }

    /// The second so far, then empty.
    mutating func take() -> LevelSecond {
        defer { self = LevelWindow() }
        guard count > 0 else { return LevelSecond(peakDB: nil, rmsDB: nil) }
        return LevelSecond(peakDB: LevelSecond.dbfs(Double(peak)), rmsDB: LevelSecond.dbfs((sumSquares / Double(count)).squareRoot()))
    }
}

/// What a capture is hearing, once it knows (System Audio picks its filter asynchronously).
enum CaptureFilter: Equatable {
    /// System Audio with music players open: every listed non-player left out.
    case playersOnly([String])
    /// System Audio, every app.
    case allApps
    /// An input device (no other apps to widen to).
    case input(String)

    var label: String {
        switch self {
        case .playersOnly(let ids): return "players only (" + (ids.isEmpty ? "none listed" : ids.joined(separator: ", ")) + ")"
        case .allApps: return "all apps"
        case .input(let name): return "input \(name)"
        }
    }
}

/// A capture that can tell what it hears and be widened to every app (System Audio).
protocol FilteredCapture: AudioCapture {
    /// Set before start; may be called on any queue, more than once (each reopen).
    var onFilter: ((CaptureFilter) -> Void)? { get set }
    /// Reopen hearing every app, no exclusions, for the rest of this Listen.
    func hearAllApps()
}

/// The silence guard: never a dead meter with no explanation. Fed one LevelSecond a second.
/// Players-only System Audio silent for `seconds` → widen to all apps. Anything else silent that
/// long → a NO SOUND notice, which clears when sound comes back.
struct SilenceGuard {
    static let seconds = 5
    static let wideningNotice = "NO SOUND FROM PLAYERS · HEARING ALL APPS"
    static let noSoundNotice = "NO SOUND · CHECK SOURCE"

    enum Action: Equatable {
        case none
        /// Log, reopen System Audio with every app, show `wideningNotice`.
        case hearAllApps(from: String)
        /// Log, show `noSoundNotice` until sound returns.
        case noSound(from: String)
        /// The NO SOUND notice can go; `after` = silent seconds before it.
        case soundBack(after: Int)
    }

    private(set) var filter: CaptureFilter?
    private(set) var silentSeconds = 0
    private(set) var warned = false

    /// The capture said what it hears (again, after a reopen): the count starts over.
    mutating func filterChosen(_ f: CaptureFilter) {
        filter = f
        silentSeconds = 0
    }

    mutating func second(_ s: LevelSecond) -> Action {
        guard s.silent else {
            let was = silentSeconds
            silentSeconds = 0
            if warned { warned = false; return .soundBack(after: was) }
            return .none
        }
        silentSeconds += 1
        guard silentSeconds >= SilenceGuard.seconds, !warned else { return .none }
        let from = filter?.label ?? "system audio (no filter chosen yet)"
        if case .playersOnly? = filter {
            filter = .allApps      // the capture reports it again once reopened
            silentSeconds = 0
            return .hearAllApps(from: from)
        }
        warned = true
        return .noSound(from: from)
    }
}

/// A line only when it differs from the last one.
struct ChangeLine {
    private(set) var last: String?
    init(last: String? = nil) { self.last = last }
    mutating func next(_ line: String) -> String? {
        guard line != last else { return nil }
        last = line
        return line
    }
    mutating func clear() { last = nil }
}

extension Lamp {
    /// The log's word for the lamp.
    var logName: String {
        switch self {
        case .locked: return "green"
        case .unsure: return "amber"
        case .listening: return "red"
        }
    }
}
