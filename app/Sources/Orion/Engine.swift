import Foundation

enum ViewState: Equatable {
    case idle
    case working(stage: String)
    case done(Result)
    case analyzed([Result])
    case failed(String)
    case doctor(DoctorReport)

    var stageName: String? { if case .working(let s) = self { return s } else { return nil } }
    var isBusy: Bool { if case .working = self { return true } else { return false } }
}

/// Launches a process and streams stdout lines. Injected so tests never spawn Python.
protocol ProcessLauncher {
    /// onLine and onExit may be called from any queue; the Engine hops to main.
    func launch(executable: URL, arguments: [String], environment: [String: String],
                onLine: @escaping (String) -> Void, onExit: @escaping (Int32) -> Void)
}

final class RealLauncher: ProcessLauncher {
    func launch(executable: URL, arguments: [String], environment: [String: String],
                onLine: @escaping (String) -> Void, onExit: @escaping (Int32) -> Void) {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        p.environment = environment.merging(["HOME": NSHomeDirectory()]) { a, _ in a }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        DispatchQueue.global(qos: .userInitiated).async {
            do { try p.run() } catch { onExit(-1); return }
            var buf = Data()
            let h = out.fileHandleForReading
            while true {
                let chunk = h.availableData
                if chunk.isEmpty { break }
                buf.append(chunk)
                while let nl = buf.firstIndex(of: 0x0A) {
                    let line = String(decoding: buf[buf.startIndex..<nl], as: UTF8.self)
                    buf.removeSubrange(buf.startIndex...nl)
                    onLine(line)
                }
            }
            if !buf.isEmpty { onLine(String(decoding: buf, as: UTF8.self)) }
            p.waitUntilExit()
            onExit(p.terminationStatus)
        }
    }
}

final class Engine: ObservableObject {
    @Published var state: ViewState = .idle
    /// Caption under a partial analysis ("2 FILES COULDN'T BE READ · ..."); nil otherwise.
    @Published var note: String?
    private let runtime: Runtime
    private let launcher: ProcessLauncher
    private var results: [Result] = []
    private var expected = 0
    private var sawTerminal = false
    private var generation = 0
    private let makeDoctor: (Runtime) -> Doctor
    private let doctorQueue: DispatchQueue
    /// Touches the Downloads folder so macOS asks for access when DOWNLOAD is pressed, not after
    /// the download. nil = no probe (tests, and ORION_DOWNLOADS runs).
    private let downloadsProbe: (() -> Bool)?

    /// The app's probe: create and remove a hidden file in ~/Downloads. None when ORION_DOWNLOADS
    /// is set (a test/debug run that never touches the real folder).
    static func defaultProbe(env: [String: String] = ProcessInfo.processInfo.environment) -> (() -> Bool)? {
        if let d = env["ORION_DOWNLOADS"], !d.isEmpty { return nil }
        let dir = Doctor.downloadsFolder(env: env)
        return { Doctor.probeWritable(dir) }
    }

    init(runtime: Runtime = .appDefault(), launcher: ProcessLauncher = RealLauncher(),
         doctor: ((Runtime) -> Doctor)? = nil,
         doctorQueue: DispatchQueue = .global(qos: .userInitiated),
         downloadsProbe: (() -> Bool)? = nil) {
        self.downloadsProbe = downloadsProbe
        self.runtime = runtime
        self.launcher = launcher
        self.makeDoctor = doctor ?? { Doctor(runtime: $0) }
        self.doctorQueue = doctorQueue
    }

    /// Beat Key › Run Doctor. Off main; the LCD shows each step. Ignored while busy, and while it
    /// runs the state is .working, so downloads and analyses are ignored.
    func runDoctor() {
        runOnMain {
            guard !self.state.isBusy else { return }
            self.generation += 1
            let gen = self.generation
            self.state = .working(stage: Doctor.stages[0])
            let doctor = self.makeDoctor(self.runtime)
            self.doctorQueue.async {
                // waits its turn behind the launch seed / upgrade
                let report = Runtime.maintenanceQueue.sync {
                    doctor.run { stage in
                        DispatchQueue.main.async { if gen == self.generation { self.state = .working(stage: stage) } }
                    }
                }
                DispatchQueue.main.async { if gen == self.generation { self.state = .doctor(report) } }
            }
        }
    }

    func download(_ url: String) {
        start(["download", url], stage: "downloading", probe: downloadsProbe)
    }

    func analyze(_ files: [URL]) {
        guard !files.isEmpty else { return }
        start(["analyze"] + files.map { $0.path }, stage: "analyzing", expected: files.count)
    }

    private func start(_ args: [String], stage: String, expected: Int = 0, probe: (() -> Bool)? = nil) {
        runOnMain {
            guard !self.state.isBusy else { return }
            self.generation += 1
            let gen = self.generation
            self.state = .working(stage: probe == nil ? stage : "allow-downloads")
            self.results = []
            self.note = nil
            self.expected = expected
            self.sawTerminal = false
            guard let probe = probe else { self.launchHelper(args, gen: gen); return }
            // Touch ~/Downloads first so the macOS prompt shows now; the helper waits for the answer.
            DispatchQueue.global(qos: .userInitiated).async {
                let ok = probe()
                DispatchQueue.main.async {
                    guard gen == self.generation else { return }
                    if ok {
                        self.state = .working(stage: stage)
                        self.launchHelper(args, gen: gen)
                    } else {
                        self.state = .failed("Operation not permitted: Downloads")
                    }
                }
            }
        }
    }

    /// Starts the helper once yt-dlp is seeded and no maintenance (launch upgrade, doctor) is running.
    private func launchHelper(_ args: [String], gen: Int) {
        let rt = runtime
        let stage = state.stageName
        var launched = false   // main thread only
        if args.first == "download" {
            // Waiting behind a seed / upgrade for more than a moment: say so.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if !launched && gen == self.generation { self.state = .working(stage: "updating") }
            }
        }
        Runtime.maintenanceQueue.async {
            rt.ensureSeeded()
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                launched = true
                if let s = stage { self.state = .working(stage: s) }
                self.launcher.launch(
                    executable: rt.python,
                    arguments: [rt.script.path] + args,
                    environment: rt.environment(),
                    onLine: { line in
                        guard let e = Event.parse(line: line) else { return }
                        DispatchQueue.main.async { if gen == self.generation { self.handle(e) } }
                    },
                    onExit: { code in
                        DispatchQueue.main.async { if gen == self.generation { self.finish(code) } }
                    })
            }
        }
    }

    private func runOnMain(_ f: @escaping () -> Void) {
        if Thread.isMainThread { f() } else { DispatchQueue.main.async(execute: f) }
    }

    func handle(_ e: Event) {
        switch e {
        case .stage(let s): if !sawTerminal { state = .working(stage: s) }
        case .done(let r): sawTerminal = true; state = .done(r)
        case .analyzed(let r): results.append(r)
        case .error(let m): sawTerminal = true; state = .failed(m)
        }
    }

    private func finish(_ code: Int32) {
        guard !sawTerminal else { return }
        if !results.isEmpty {
            // Nothing readable and macOS refused it: say where to allow it, not a blank readout.
            if results.allSatisfy({ $0.bpm == nil && $0.readError == "permission" }) {
                state = .failed("Operation not permitted: \(results[0].name)")
                return
            }
            if code != 0 {
                note = Faceplate.partialNote(max(expected - results.count, 1))
            }
            state = .analyzed(results)
        } else if state.isBusy {
            state = .failed("The helper stopped unexpectedly (exit \(code)).")
        }
    }
}
