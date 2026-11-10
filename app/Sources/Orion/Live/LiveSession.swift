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
            // keys, bpm, bpm_exact, tuning_cents (null under 50 %), chroma: the same parser as files
            return Event.reading(obj, file: LiveSession.placeholderFile, name: "LIVE").map { .reading($0) }
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
    /// readout stands. `reference` = the A the tuning line is measured against (Settings), as for files.
    static func liveReadout(_ s: LiveState, source: String, factor: TempoFactor,
                            onCycleTempo: (() -> Void)? = nil, held: Bool = false,
                            spelling: KeySpelling? = nil, onToggleSpelling: (() -> Void)? = nil,
                            reference: Double = Tuning.defaultReference, notice: String? = nil) -> Readout? {
        switch s {
        case .off:
            return nil
        case .failed(let m):
            return .error(m, download: false, hint: liveRetryHint)
        case .listening:
            return .listening(status: notice ?? s.status(source: source) ?? "LISTENING")
        case .reading(let r), .locked(let r):
            let opts = ResultOptions(factor: factor, tuning: Tuning.meter(r.tuningCents, reference: reference),
                                     onCycleTempo: onCycleTempo,
                                     live: (s.lamp ?? .listening, notice ?? s.status(source: source, held: held) ?? "", source),
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

/// What Listen really opens for the saved source. A saved input device that isn't connected
/// (unplugged, renamed) falls back to Mac audio (System Audio) instead of failing; the saved
/// choice is left alone, so the device is used again once it is back (J, 2026-11-05 17:06).
enum LiveSourcePlan: Equatable {
    case use(LiveSource)
    /// The saved device (`missingUID`, channel) is gone: `source` (System Audio) instead.
    case fallback(LiveSource, missingUID: String, channel: Int)

    var source: LiveSource {
        switch self {
        case .use(let s), .fallback(let s, _, _): return s
        }
    }

    static let fallbackNotice = "SAVED INPUT MISSING · USING MAC AUDIO"
    /// How long the notice stands in for the lamp's caption.
    static let noticeSeconds: TimeInterval = 8

    /// Pure: `connectedUIDs` = the input devices Core Audio lists right now. Without System Audio
    /// (macOS 12) there is nothing to fall back to, and the input's own "not connected" error stands.
    static func plan(saved: LiveSource, connectedUIDs: Set<String>, systemAvailable: Bool) -> LiveSourcePlan {
        guard case .input(let uid?, let ch) = saved, !connectedUIDs.contains(uid), systemAvailable else {
            return .use(saved)
        }
        return .fallback(.system, missingUID: uid, channel: ch)
    }
}

final class LiveSettings: ObservableObject {
    static let sourceKey = "liveSource"
    static let gapKey = "liveGapSeconds"
    static let gaps: [Double] = [2, 3, 5, 10]
    static let defaultGap = 3.0
    private let defaults: UserDefaults
    let systemAvailable: Bool

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
    func sourceName(devices: [InputDevice]) -> String { LiveSettings.name(of: source, devices: devices) }

    static func name(of source: LiveSource, devices: [InputDevice]) -> String {
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
        process.standardError = AppLog.analyzerHandle(header: "bpm.py --stream") ?? FileHandle.nullDevice
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
            AppLog.log("analyzer exited: status \(self.process.terminationStatus) reason \(self.process.terminationReason.rawValue)" + (self.process.terminationStatus == 0 ? "" : "; its stderr: analyzer.log"))
            onExit(self.process.terminationStatus)
        }
    }

    func write(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }   // little-endian on every Mac
        writes.async { [self] in
            guard !closed else { return }
            do { try stdin.fileHandleForWriting.write(contentsOf: data) } catch {
                closed = true
                AppLog.log("analyzer pipe write failed (the analyzer is gone?): \(error)")
            }
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

/// Listen's input level, 0...1, on its own so its 20 Hz ticks redraw only the meter segments.
final class LiveLevel: ObservableObject {
    @Published var value: Float = 0
}

final class LiveController: ObservableObject {
    /// What is shown: the frozen reading while Hold is on.
    @Published private(set) var state: LiveState = .off
    /// Hold is on (a button, never automatic).
    @Published private(set) var isHeld = false
    @Published private(set) var sourceName = ""
    /// What this Listen hears ("all apps except Beat Key", "input Scarlett 4i4 · Ch 3"), for the log.
    private var hearingLabel = ""
    /// A short non-error line that stands in for the lamp's caption for a few seconds (the saved
    /// input is missing, Mac audio is used instead). nil = none.
    @Published private(set) var notice: String?
    /// The input's level while listening, 0...1 (peak, dB-scaled, falling back slowly), for the
    /// meters. 0 when Listen is off. Its own object, not a @Published here: it ticks 20 times a
    /// second, and every tick of the controller re-derived and redrew the whole face (12.6 ms of
    /// main thread per tick in the window), dropping frames from the readout's animations (0.1.50,
    /// J 2026-11-09: "very jerky clicky movements"). Only the meter segments observe it.
    let meter = LiveLevel()
    var level: Float { meter.value }
    let settings: LiveSettings
    /// New-song boundaries and one Recent Readings entry per song (SongBoundary.swift).
    let songs: SongTracker
    private var session = LiveSession()
    private let launch: LiveLauncher
    private let makeCapture: (LiveSource) -> AudioCapture?
    private let now: () -> Date
    private let devices: () -> [InputDevice]
    private var noticeWork: DispatchWorkItem?
    private var pipe: LivePipe?
    private var capture: AudioCapture?
    private var filler: SilenceFiller?
    private var fillTimer: Timer?
    private var levelTimer: Timer?
    private var peak: Float = 0
    /// This second's input, for the log's level line and the silence guard (fillLock guards it).
    private var window = LevelWindow()
    private var windowSince = Date.distantPast
    private var silence = SilenceGuard()
    private var stateLine = ChangeLine(last: LiveController.summary(.off))   // off at launch: nothing to say
    private var quitObserver: NSObjectProtocol?
    private let fillLock = NSLock()
    private var generation = 0
    /// The last minute heard, for a "Wrong, it's X" teach record (fillLock guards it).
    private var clip = ClipRing(seconds: 60, sampleRate: LiveProcess.sampleRate)

    init(settings: LiveSettings, launch: @escaping LiveLauncher,
         makeCapture: @escaping (LiveSource) -> AudioCapture? = LiveController.realCapture,
         now: @escaping () -> Date = Date.init, songs: SongTracker? = nil,
         devices: @escaping () -> [InputDevice] = InputDevice.all) {
        self.settings = settings
        self.songs = songs ?? SongTracker(now: now)
        self.launch = launch
        self.makeCapture = makeCapture
        self.now = now
        self.devices = devices
        // App quit: say Listen stopped because of it (the log's last word on the session).
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self = self, self.state.isActive else { return }
            self.stop(reason: "app quit")
            AppLog.flush()
        }
    }

    deinit { if let o = quitObserver { NotificationCenter.default.removeObserver(o) } }

    static func realCapture(_ s: LiveSource) -> AudioCapture? {
        switch s {
        case .system:
            if #available(macOS 13.0, *) { return SystemAudioCapture() }
            return nil
        case .input(let uid, let ch):
            return InputCapture(deviceUID: uid, channel: ch)
        }
    }

    func toggle() { state.isActive ? stop(reason: "user stop") : start() }

    /// New Song: drop everything heard and any lock, now, and keep listening to the same source.
    /// The analyzer's stdin carries only samples (no control channel), so the stream is started
    /// over: a fresh analyzer and capture, the lamp back to red LISTENING. Off = nothing to do.
    func reset() {
        guard state.isActive else { return }
        start(why: "new song")
    }

    /// `why` = why a running Listen is being started over (new song, source changed); it is
    /// logged as the old session's stop reason.
    func start(why: String = "restarted") {
        stop(reason: why)
        generation += 1
        let gen = generation
        let devs = devices()
        let plan = LiveSourcePlan.plan(saved: settings.source, connectedUIDs: Set(devs.map(\.uid)),
                                       systemAvailable: settings.systemAvailable)
        sourceName = LiveSettings.name(of: plan.source, devices: devs)
        AppLog.log("listen: start · source \(sourceName) (\(plan.source.stored)) · gap \(settings.gap) s")
        hearingLabel = LiveController.hearing(plan.source, name: sourceName)
        AppLog.log("listen: hearing \(hearingLabel)")
        silence = SilenceGuard()
        if case .fallback(_, let uid, let ch) = plan {
            AppLog.log("listen: saved input missing (uid \(uid), ch \(ch); connected: "
                       + (devs.isEmpty ? "none" : devs.map { "\($0.name) [\($0.uid)]" }.joined(separator: ", "))
                       + "), falling back to Mac audio (System Audio); saved choice kept")
            showNotice(LiveSourcePlan.fallbackNotice, gen: gen)
        }
        guard let cap = makeCapture(plan.source) else {
            AppLog.log("listen: no capture for \(plan.source.stored)")
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
        fillLock.lock(); filler = SilenceFiller(now: now()); clip.clear()
        window = LevelWindow(); windowSince = now(); fillLock.unlock()
        cap.start(onSamples: { [weak self, weak p] samples in
            guard let self = self else { return }
            let pk = samples.reduce(Float(0)) { max($0, abs($1)) }
            self.fillLock.lock(); self.filler?.heard(at: self.now()); self.peak = max(self.peak, pk)
            self.window.add(samples, peak: pk)
            self.clip.append(samples); self.fillLock.unlock()
            p?.write(samples)
        }, onError: { [weak self] message in
            DispatchQueue.main.async { self?.fail(message, gen: gen) }
        })
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.fillSilence() }
        RunLoop.main.add(t, forMode: .common)
        fillTimer = t
        let lt = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.tickLevel() }
        RunLoop.main.add(lt, forMode: .common)
        levelTimer = lt
    }

    /// The meter (20 Hz): the loudest sample since the last tick, falling back at most 20 % per
    /// tick. Once a second it also logs the level and runs the silence guard; never per tick.
    func tickLevel() {
        let t = now()
        fillLock.lock()
        let pk = peak; peak = 0
        var second: LevelSecond?
        if t.timeIntervalSince(windowSince) >= 1 { second = window.take(); windowSince = t }
        fillLock.unlock()
        let next = max(LevelMeter.scale(pk), level * 0.8)
        if abs(next - level) > 0.004 { meter.value = next < 0.01 ? 0 : next }
        if let s = second { levelSecond(s) }
    }

    private func levelSecond(_ s: LevelSecond) {
        guard state.isActive else { return }
        AppLog.log("listen: " + s.text)
        switch silence.second(s) {
        case .none:
            break
        case .noSound:
            AppLog.log("listen: no signal for \(SilenceGuard.seconds) s from \(hearingLabel); LCD says \"\(SilenceGuard.noSoundNotice)\"")
            showNotice(SilenceGuard.noSoundNotice, gen: generation, seconds: nil)
        case .soundBack(let after):
            AppLog.log("listen: signal back after \(after) s silent")
            if notice == SilenceGuard.noSoundNotice { noticeWork?.cancel(); noticeWork = nil; notice = nil }
        }
    }

    /// What a source hears, for the log: System Audio is every app but Beat Key itself.
    static func hearing(_ source: LiveSource, name: String) -> String {
        switch source {
        case .system: return "all apps except Beat Key"
        case .input: return "input \(name)"
        }
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

    /// `reason` lands in the log: user stop, new song, source changed, app quit, a download took
    /// the LCD... Nothing is logged when Listen was already off.
    func stop(reason: String = "user stop") {
        if state.isActive { AppLog.log("listen: stopped (\(reason))") }
        teardown()
        session.end()
        publish()
    }

    /// Logs each change of what Listen shows (key, %, BPM, lamp), never a repeat.
    private func publish() {
        let d = LiveController.summary(session.state) + (session.isHeld ? " (held)" : "")
        if let line = stateLine.next(d) { AppLog.log("listen: \(line) · source \(sourceName)") }
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

    /// The notice for `seconds`, then the lamp's own caption again; nil = until cleared.
    private func showNotice(_ text: String, gen: Int, seconds: TimeInterval? = LiveSourcePlan.noticeSeconds) {
        noticeWork?.cancel()
        noticeWork = nil
        notice = text
        guard let secs = seconds else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, gen == self.generation else { return }
            self.notice = nil
        }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: work)
    }

    private func teardown() {
        noticeWork?.cancel()
        noticeWork = nil
        if notice != nil { notice = nil }
        songs.end()
        fillTimer?.invalidate()
        fillTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        if level != 0 { meter.value = 0 }
        capture?.stop()
        capture = nil
        pipe?.close()
        pipe = nil
        fillLock.lock(); filler = nil; fillLock.unlock()
    }

    /// What took the LCD from Listen, for its stop reason ("download / analysis (downloading)").
    static func engineLabel(_ s: ViewState) -> String {
        switch s {
        case .idle: return "idle"
        case .working(let stage): return "a download or analysis (\(stage))"
        case .done: return "a download's result"
        case .analyzed: return "a file's result"
        case .failed: return "an error"
        case .needsLogin: return "a login prompt"
        case .doctor: return "Run Doctor"
        }
    }

    /// One log line's worth of Listen's state (the key list, not the whole Result), with the lamp.
    static func summary(_ s: LiveState) -> String {
        func keys(_ r: Result) -> String { r.keys.prefix(3).map { "\($0.0) \($0.1)%" }.joined(separator: ", ") }
        let lamp = s.lamp.map { " · lamp \($0.logName)" } ?? ""
        switch s {
        case .off: return "off"
        case .listening: return "listening" + lamp
        case .failed(let m): return "FAILED: \(m)"
        case .reading(let r): return "reading \(keys(r)) · bpm \(r.bpm ?? "-")" + lamp
        case .locked(let r): return "locked \(keys(r)) · bpm \(r.bpm ?? "-")" + lamp
        }
    }

    private func fail(_ message: String, gen: Int) {
        guard gen == generation else { return }
        AppLog.log("listen: stopped (error: \(message))")
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
