import Foundation

// What Listen writes to beatkey.log (J, 2026-11-09 23:22: "a missing log is a failure"; Studio D's
// dead meter left no trace of what it heard). Pure pieces, unit-tested: the once-a-second input
// level and the on-change reading line. Whether it is silence is the analyzer's call, not this
// file's: its "silence" / "sound" events put up and clear NO SOUND (LiveController.handle).

/// One second of input, as the log prints it: a measurement, never a verdict.
struct LevelSecond: Equatable {
    /// nil = no samples arrived at all (System Audio sends nothing while nothing plays).
    let peakDB: Float?
    let rmsDB: Float?

    /// "level -12.3 dBFS peak, -24.1 dBFS rms", "level none (no audio arriving)".
    var text: String {
        guard let p = peakDB, let r = rmsDB else { return "level none (no audio arriving)" }
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
