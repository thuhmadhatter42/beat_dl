import AppKit
import Foundation

// Live listening (plan §3): the mic / an input device / system audio, read as it plays.
// Audio goes from the capture straight into one long-lived `bpm.py --stream` process as float32
// PCM on its stdin; nothing is ever written to disk. That process answers with a reading every 2 s.

/// One line from `bpm.py --stream`.
enum LiveEvent: Equatable {
    case ready
    case reading(Result)
    /// A silence longer than the gap: a new song starts over.
    case reset
    /// A new song with no pause (SongBoundary.swift): the analyzer has flushed, start over.
    case boundary(LiveBoundary)
    case error(String)

    static func parse(line: String) -> LiveEvent? {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let kind = obj["event"] as? String else { return nil }
        switch kind {
        case "ready": return .ready
        case "reset": return .reset
        case "boundary": return .boundary(LiveBoundary(json: obj))
        case "error": return .error((obj["message"] as? String) ?? "The analyzer stopped.")
        case "reading":
            guard let keys = Event.keyList(obj["keys"]) else { return nil }
            return .reading(Result(file: LiveSession.placeholderFile, name: "LIVE", bpm: obj["bpm"] as? String,
                                   keys: keys, bpmExact: (obj["bpm_exact"] as? NSNumber)?.doubleValue))
        default: return nil
        }
    }
}

enum LiveState: Equatable {
    case off
    /// Capture and analyzer starting, or running with nothing to say yet (or again, after a gap).
    case listening
    /// A reading that may still change: amber when unsure, green when the key is confident.
    case reading(Result)
    /// Green for `LiveSession.lockAfter` seconds with the same key and a BPM. Never frozen: the
    /// next reading still replaces it (J, 2026-11-01: songs change every two minutes, no hold).
    case locked(Result)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .listening, .reading, .locked: return true
        case .off, .failed: return false
        }
    }

    var result: Result? {
        switch self {
        case .reading(let r), .locked(let r): return r
        default: return nil
        }
    }

    /// The lamp: red while listening, then amber / green with the key's confidence.
    var lamp: Lamp? {
        switch self {
        case .listening: return .listening
        case .reading(let r): return Lamp.of(r.keys) ?? .listening
        case .locked: return .locked
        case .off, .failed: return nil
        }
    }

    /// The lamp's caption.
    func status(source: String, held: Bool = false) -> String? {
        let base: String?
        switch self {
        case .listening: base = "LISTENING · \(source.uppercased())"
        case .reading(let r): base = Faceplate.confidenceLine(r.keys) ?? "LISTENING · \(source.uppercased())"
        case .locked(let r): base = Faceplate.confidenceLine(r.keys) ?? "LOCKED"
        case .off, .failed: base = nil
        }
        guard held, let b = base, result != nil else { return base }
        return "HELD · " + b
    }
}

/// The readings as they come in: green-and-steady after `lockAfter` s of the same confident key
/// (with a BPM), always following the audio, and start over after a gap. Pure logic; the clock is passed in.
struct LiveSession {
    static let placeholderFile = URL(fileURLWithPath: "/")
    static let lockAfter: TimeInterval = 6

    /// What the audio says right now (it keeps following while Hold is on).
    private(set) var current: LiveState = .off
    /// Hold (J, 2026-11-01): a button, never automatic. While on, `state` is the reading that was
    /// shown when it went on; listening carries on underneath.
    private var frozen: LiveState?
    private var greenKey: String?
    private var greenSince: Date?
    var lockAfter = LiveSession.lockAfter

    /// What is shown: the frozen reading while held, else the current one.
    var state: LiveState { frozen ?? current }
    var isHeld: Bool { frozen != nil }
    /// Hold can go on only with a reading to hold.
    var canHold: Bool { frozen != nil || current.result != nil }

    mutating func begin() { current = .listening; frozen = nil; greenKey = nil; greenSince = nil }
    mutating func end() { current = .off; frozen = nil; greenKey = nil; greenSince = nil }
    mutating func fail(_ message: String) { current = .failed(message); frozen = nil; greenKey = nil; greenSince = nil }

    /// Hold on: freeze the reading on show. Hold off: jump to the current reading. False = nothing
    /// to hold (no reading yet, or not listening).
    @discardableResult
    mutating func setHold(_ on: Bool) -> Bool {
        if !on { frozen = nil; return true }
        guard current.isActive, current.result != nil else { return false }
        if frozen == nil { frozen = current }
        return true
    }

    @discardableResult
    mutating func toggleHold() -> Bool { setHold(!isHeld) }

    mutating func feed(_ e: LiveEvent, now: Date = Date()) {
        guard current.isActive else { return }
        switch e {
        case .ready:
            break
        case .reset, .boundary:
            begin()
        case .error(let m):
            fail(m)
        case .reading(let r):
            if Lamp.of(r.keys) == .locked, r.bpm != nil, let key = r.keys.first?.0 {
                if key != greenKey || greenSince == nil { greenKey = key; greenSince = now }
                if let since = greenSince, now.timeIntervalSince(since) >= lockAfter {
                    current = .locked(r)
                    return
                }
            } else {
                greenKey = nil
                greenSince = nil
            }
            current = .reading(r)
        }
    }
}

extension Faceplate {
    static let liveRetryHint = "READING › START LISTENING TO TRY AGAIN"

    /// What the LCD shows while Listen is on (or just failed); nil = Listen is off, the engine's
    /// readout stands.
    static func liveReadout(_ s: LiveState, source: String, factor: TempoFactor,
                            onCycleTempo: (() -> Void)? = nil, held: Bool = false,
                            spelling: KeySpelling? = nil, onToggleSpelling: (() -> Void)? = nil) -> Readout? {
        switch s {
        case .off:
            return nil
        case .failed(let m):
            return .error(m, download: false, hint: liveRetryHint)
        case .listening:
            return .listening(status: s.status(source: source) ?? "LISTENING")
        case .reading(let r), .locked(let r):
            let opts = ResultOptions(factor: factor, tuning: nil, onCycleTempo: onCycleTempo,
                                     live: (s.lamp ?? .listening, s.status(source: source, held: held) ?? "", source),
                                     onToggleSpelling: onToggleSpelling)
            return .result(r.respelled(spelling), page: nil, download: false, options: opts)
        }
    }
}

// MARK: settings

/// Where live audio comes from.
enum LiveSource: Equatable {
    /// Everything the Mac plays (ScreenCaptureKit, macOS 13+).
    case system
    /// An input device (nil uid = the system's default input). channel 0 = all channels mixed,
    /// n = channel n only.
    case input(uid: String?, channel: Int)

    static var systemAvailable: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static var defaultSource: LiveSource { systemAvailable ? .system : .input(uid: nil, channel: 0) }

    var stored: String {
        switch self {
        case .system: return "system"
        case .input(let uid, let ch): return "input:\(ch):\(uid ?? "")"
        }
    }

    static func from(stored s: String?) -> LiveSource? {
        guard let s = s else { return nil }
        if s == "system" { return .system }
        let parts = s.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "input", let ch = Int(parts[1]), ch >= 0 else { return nil }
        let uid = String(parts[2])
        return .input(uid: uid.isEmpty ? nil : uid, channel: ch)
    }
}

final class LiveSettings: ObservableObject {
    static let sourceKey = "liveSource"
    static let gapKey = "liveGapSeconds"
    static let gaps: [Double] = [2, 3, 5, 10]
    static let defaultGap = 3.0
    private let defaults: UserDefaults
    private let systemAvailable: Bool

    @Published var source: LiveSource { didSet { defaults.set(source.stored, forKey: LiveSettings.sourceKey) } }
    /// Seconds of silence that mean a new song: everything heard is dropped and it starts over.
    @Published var gap: Double { didSet { defaults.set(gap, forKey: LiveSettings.gapKey) } }

    init(defaults: UserDefaults = .standard, systemAvailable: Bool = LiveSource.systemAvailable) {
        self.defaults = defaults
        self.systemAvailable = systemAvailable
        var s = LiveSource.from(stored: defaults.string(forKey: LiveSettings.sourceKey))
            ?? (systemAvailable ? .system : .input(uid: nil, channel: 0))
        if s == .system && !systemAvailable { s = .input(uid: nil, channel: 0) }   // macOS 12
        source = s
        let g = defaults.object(forKey: LiveSettings.gapKey) as? Double
        gap = g.map { min(max($0, 1), 30) } ?? LiveSettings.defaultGap
    }

    /// "System Audio", "MacBook Pro Microphone", "Scarlett 4i4 · Ch 3".
    func sourceName(devices: [InputDevice]) -> String {
        switch source {
        case .system: return "System Audio"
        case .input(let uid, let ch):
            let dev = uid.flatMap { u in devices.first { $0.uid == u } }
            let name = dev?.name ?? (uid == nil ? "Default Input" : "Missing Input")
            return ch > 0 ? "\(name) · Ch \(ch)" : name
        }
    }
}

// MARK: the analyzer process

/// Where the capture's samples go. write is called from audio threads.
protocol LivePipe: AnyObject {
    func write(_ samples: [Float])
    func close()
}

/// Starts the analyzer; nil = could not start. onLine / onExit may arrive on any queue.
typealias LiveLauncher = (_ gap: Double, _ onLine: @escaping (String) -> Void,
                          _ onExit: @escaping (Int32) -> Void) -> LivePipe?

/// `python bpm.py --stream` with the bundle's runtime, float32 PCM written to its stdin.
final class LiveProcess: LivePipe {
    static let sampleRate = 44100
    let process = Process()   // SongBoundary.swift signals it (newSong)
    private let stdin = Pipe()
    private let writes = DispatchQueue(label: "com.jshriver.orion.live-pipe")
    private var closed = false   // writes queue only

    static func launcher(runtime: Runtime) -> LiveLauncher {
        return { gap, onLine, onExit in
            LiveProcess(executable: runtime.python,
                        arguments: [runtime.analyzer.path, "--stream", "--rate", String(sampleRate),
                                    "--gap", String(gap)],
                        environment: runtime.environment(), onLine: onLine, onExit: onExit)
        }
    }

    init?(executable: URL, arguments: [String], environment: [String: String],
          onLine: @escaping (String) -> Void, onExit: @escaping (Int32) -> Void) {
        signal(SIGPIPE, SIG_IGN)   // a dead analyzer must fail a write, not kill the app
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment.merging(["HOME": NSHomeDirectory()]) { a, _ in a }
        let out = Pipe()
        process.standardInput = stdin
        process.standardOutput = out
        process.standardError = AppLog.analyzerHandle() ?? FileHandle.nullDevice
        AppLog.log("analyzer start: \(arguments.dropFirst().joined(separator: " "))")
        do { try process.run() } catch { AppLog.log("analyzer failed to start: \(error)"); return nil }
        DispatchQueue.global(qos: .userInitiated).async {
            var buf = Data()
            let h = out.fileHandleForReading
            while true {
                let chunk = h.availableData
                if chunk.isEmpty { break }
                buf.append(chunk)
                while let nl = buf.firstIndex(of: 0x0A) {
                    onLine(String(decoding: buf[buf.startIndex..<nl], as: UTF8.self))
                    buf.removeSubrange(buf.startIndex...nl)
                }
            }
            // exit only after every line is out
            self.process.waitUntilExit()
            AppLog.log("analyzer exited: status \(self.process.terminationStatus) reason \(self.process.terminationReason.rawValue)")
            onExit(self.process.terminationStatus)
        }
    }

    func write(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }   // little-endian on every Mac
        writes.async { [self] in
            guard !closed else { return }
            do { try stdin.fileHandleForWriting.write(contentsOf: data) } catch { closed = true }
        }
    }

    /// EOF on stdin ends the analyzer; it is stopped outright if it lingers past `grace` s
    /// (Stop Listening wants it gone, not its last reading).
    func close() { close(grace: 2) }

    func close(grace: TimeInterval) {
        writes.async { [self] in
            guard !closed else { return }
            closed = true
            try? stdin.fileHandleForWriting.close()
        }
        let p = process
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) { if p.isRunning { p.terminate() } }
    }
}

/// A capture that has gone quiet (system audio sends nothing while nothing plays) still has to
/// read as silence, or the gap would never be seen. Counts the zeros to send.
struct SilenceFiller {
    let rate: Int
    let tick: TimeInterval
    private(set) var lastSamples: Date

    init(rate: Int = LiveProcess.sampleRate, tick: TimeInterval = 0.5, now: Date = Date()) {
        self.rate = rate; self.tick = tick; lastSamples = now
    }

    mutating func heard(at now: Date) { lastSamples = now }

    /// Zeros to write at `now`: one tick's worth once nothing has come for longer than a tick.
    mutating func zeros(at now: Date) -> Int {
        guard now.timeIntervalSince(lastSamples) > tick else { return 0 }
        lastSamples = now
        return Int(Double(rate) * tick)
    }
}

// MARK: the controller

/// Captured audio, as 44.1 kHz mono float32 in pieces of any length.
protocol AudioCapture: AnyObject {
    /// Errors are LCD sentences ("ALLOW ..."). Either callback may arrive on any queue.
    func start(onSamples: @escaping ([Float]) -> Void, onError: @escaping (String) -> Void)
    func stop()
}

final class LiveController: ObservableObject {
    /// What is shown: the frozen reading while Hold is on.
    @Published private(set) var state: LiveState = .off
    /// Hold is on (a button, never automatic).
    @Published private(set) var isHeld = false
    @Published private(set) var sourceName = ""
    /// The input's level while listening, 0...1 (peak, dB-scaled, falling back slowly), for the
    /// popover's meter. 0 when Listen is off.
    @Published private(set) var level: Float = 0
    let settings: LiveSettings
    /// New-song boundaries and one Recent Readings entry per song (SongBoundary.swift).
    let songs: SongTracker
    private var session = LiveSession()
    private let launch: LiveLauncher
    private let makeCapture: (LiveSource) -> AudioCapture?
    private let now: () -> Date
    private var pipe: LivePipe?
    private var capture: AudioCapture?
    private var filler: SilenceFiller?
    private var fillTimer: Timer?
    private var levelTimer: Timer?
    private var peak: Float = 0
    private let fillLock = NSLock()
    private var generation = 0
    /// The last minute heard, for a "Wrong, it's X" teach record (fillLock guards it).
    private var clip = ClipRing(seconds: 60, sampleRate: LiveProcess.sampleRate)

    init(settings: LiveSettings, launch: @escaping LiveLauncher,
         makeCapture: @escaping (LiveSource) -> AudioCapture? = LiveController.realCapture,
         now: @escaping () -> Date = Date.init, songs: SongTracker? = nil) {
        self.settings = settings
        self.songs = songs ?? SongTracker(now: now)
        self.launch = launch
        self.makeCapture = makeCapture
        self.now = now
    }

    static func realCapture(_ s: LiveSource) -> AudioCapture? {
        switch s {
        case .system:
            if #available(macOS 13.0, *) { return SystemAudioCapture() }
            return nil
        case .input(let uid, let ch):
            return InputCapture(deviceUID: uid, channel: ch)
        }
    }

    func toggle() { state.isActive ? stop() : start() }

    /// New Song: drop everything heard and any lock, now, and keep listening to the same source.
    /// The analyzer's stdin carries only samples (no control channel), so the stream is started
    /// over: a fresh analyzer and capture, the lamp back to red LISTENING. Off = nothing to do.
    func reset() {
        guard state.isActive else { return }
        start()
    }

    func start() {
        stop()
        generation += 1
        let gen = generation
        sourceName = settings.sourceName(devices: InputDevice.all())
        guard let cap = makeCapture(settings.source) else {
            fail("SYSTEM AUDIO NEEDS MACOS 13 OR NEWER", gen: gen); return
        }
        let onLine: (String) -> Void = { [weak self] line in
            guard let e = LiveEvent.parse(line: line) else { return }
            DispatchQueue.main.async { self?.handle(e, gen: gen) }
        }
        let onExit: (Int32) -> Void = { [weak self] code in
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation, self.state.isActive else { return }
                self.fail("THE ANALYZER STOPPED (EXIT \(code))", gen: gen)
            }
        }
        guard let p = launch(settings.gap, onLine, onExit) else {
            fail("THE ANALYZER WOULDN'T START", gen: gen); return
        }
        pipe = p
        capture = cap
        session.begin()
        publish()
        songs.begin(signal: p as? SongSignal)
        fillLock.lock(); filler = SilenceFiller(now: now()); clip.clear(); fillLock.unlock()
        cap.start(onSamples: { [weak self, weak p] samples in
            guard let self = self else { return }
            let pk = samples.reduce(Float(0)) { max($0, abs($1)) }
            self.fillLock.lock(); self.filler?.heard(at: self.now()); self.peak = max(self.peak, pk)
            self.clip.append(samples); self.fillLock.unlock()
            p?.write(samples)
        }, onError: { [weak self] message in
            DispatchQueue.main.async { self?.fail(message, gen: gen) }
        })
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.fillSilence() }
        RunLoop.main.add(t, forMode: .common)
        fillTimer = t
        let lt = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.updateLevel() }
        RunLoop.main.add(lt, forMode: .common)
        levelTimer = lt
    }

    /// The meter: the loudest sample since the last tick, falling back at most 20 % per tick.
    private func updateLevel() {
        fillLock.lock(); let pk = peak; peak = 0; fillLock.unlock()
        let next = max(LevelMeter.scale(pk), level * 0.8)
        if abs(next - level) > 0.004 { level = next < 0.01 ? 0 : next }
    }

    /// Up to the last minute of audio heard since Listen (or New Song) started.
    func recentClip() -> [Float] {
        fillLock.lock(); defer { fillLock.unlock() }
        return clip.last
    }

    func fillSilence() {
        fillLock.lock()
        let n = filler?.zeros(at: now()) ?? 0
        fillLock.unlock()
        if n > 0 { pipe?.write([Float](repeating: 0, count: n)) }
    }

    func stop() {
        teardown()
        session.end()
        publish()
    }

    private func publish() {
        let d = LiveController.summary(session.state)
        if d != lastLogged { AppLog.log("listen: \(d)\(session.isHeld ? " (held)" : "") source \(sourceName)"); lastLogged = d }
        state = session.state
        if isHeld != session.isHeld { isHeld = session.isHeld }
    }

    /// Hold / Release. False = nothing to hold yet.
    @discardableResult
    func setHold(_ on: Bool) -> Bool {
        let ok = session.setHold(on)
        publish()
        return ok
    }

    @discardableResult
    func toggleHold() -> Bool { setHold(!session.isHeld) }
    var canHold: Bool { session.canHold }

    private func teardown() {
        songs.end()
        fillTimer?.invalidate()
        fillTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        if level != 0 { level = 0 }
        capture?.stop()
        capture = nil
        pipe?.close()
        pipe = nil
        fillLock.lock(); filler = nil; fillLock.unlock()
    }

    private var lastLogged = ""

    /// One log line's worth of Listen's state (the key list, not the whole Result).
    static func summary(_ s: LiveState) -> String {
        switch s {
        case .off: return "off"
        case .listening: return "listening"
        case .failed(let m): return "FAILED: \(m)"
        case .reading(let r): return "reading " + r.keys.prefix(3).map { "\($0.0) \($0.1)%" }.joined(separator: ", ") + " bpm \(r.bpm ?? "-")"
        case .locked(let r): return "locked " + r.keys.prefix(3).map { "\($0.0) \($0.1)%" }.joined(separator: ", ") + " bpm \(r.bpm ?? "-")"
        }
    }

    private func fail(_ message: String, gen: Int) {
        guard gen == generation else { return }
        AppLog.log("listen failed: \(message)")
        teardown()
        session.fail(message)
        publish()
    }

    func handle(_ e: LiveEvent, gen: Int? = nil) {
        if let g = gen, g != generation { return }
        if case .error(let m) = e { fail(m, gen: generation); return }
        songs.observe(e)
        session.feed(e, now: now())
        publish()
    }
}
