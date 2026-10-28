import Foundation
import UniformTypeIdentifiers

/// The faceplate's own logic, kept out of the views so it can be tested.
enum Faceplate {
    /// DOWNLOAD lights when the field holds a link and nothing is running.
    static func isLit(_ text: String, busy: Bool) -> Bool {
        !busy && text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http")
    }

    /// FIND KEY/BPM lights when audio is picked and nothing is running (DOWNLOAD's rule).
    static func isFindLit(_ picked: [URL], busy: Bool) -> Bool { !busy && !picked.isEmpty }

    /// The picker field's text: nil = the "Open Audio..." placeholder, else "x.wav" / "3 files".
    static func pickLabel(_ picked: [URL]) -> String? {
        switch picked.count {
        case 0: return nil
        case 1: return picked[0].lastPathComponent
        default: return "\(picked.count) files"
        }
    }

    /// The TEMPO light's period in seconds: one flash per beat. nil = no light.
    static func tempoPeriod(_ bpm: String?) -> TimeInterval? {
        guard let s = bpm, let v = Double(s), v.isFinite, v > 0 else { return nil }
        return 60 / v
    }

    /// The LCD line for a progress stage from app_run.py.
    static func stageText(_ stage: String) -> String {
        switch stage {
        case "downloading": return "DOWNLOADING"
        case "updating": return "UPDATING THE DOWNLOADER"
        case "allow-downloads": return "ALLOW DOWNLOADS ACCESS"
        case "analyzing": return "FINDING BPM AND KEY"
        case "renaming": return "RENAMING THE FILE"
        case "doctor-ytdlp": return "DOCTOR · YT-DLP"
        case "doctor-ffmpeg": return "DOCTOR · FFMPEG"
        case "doctor-js": return "DOCTOR · JS"
        case "doctor-python": return "DOCTOR · PYTHON"
        case "doctor-downloads": return "DOCTOR · DOWNLOADS"
        default: return stage.uppercased()
        }
    }

    // MARK: a video YouTube wants a login for (Beat Key has no login)

    static let cantDownloadLine = "\(Brand.wordmark) CAN'T DOWNLOAD IT"

    /// The readout to show: only while the link in the field is the one that was refused.
    static func loginPrompt(_ state: ViewState, url: String) -> LoginPrompt? {
        guard case .needsLogin(let p) = state,
              url.trimmingCharacters(in: .whitespacesAndNewlines) == p.url else { return nil }
        return p
    }

    /// The two amber LCD lines. No button: there is nothing to press.
    static func blockedLines(_ p: LoginPrompt) -> (String, String) {
        switch p.reason {
        case "bot": return ("YOUTUBE BLOCKED THIS DOWNLOAD", "TRY AGAIN LATER")
        case "members": return ("THIS VIDEO IS FOR MEMBERS", cantDownloadLine)
        default: return ("THIS VIDEO IS AGE-RESTRICTED", cantDownloadLine)
        }
    }

    enum Step: Equatable { case done, on, off }

    /// DOWNLOAD / ANALYZE / RENAME lights for a download in progress.
    static func steps(_ stage: String) -> [(String, Step)] {
        let order = ["DOWNLOAD", "ANALYZE", "RENAME"]
        let at: Int
        switch stage {
        case "analyzing": at = 1
        case "renaming": at = 2
        default: at = 0
        }
        return order.enumerated().map { i, n in (n, i < at ? .done : (i == at ? .on : .off)) }
    }

    /// The doctor's five lights, done / on / off, for a doctor stage.
    static func doctorSteps(_ stage: String) -> [(String, Step)] {
        let names = ["YT-DLP", "FFMPEG", "JS", "PYTHON", "DOWNLOADS"]
        let at = Doctor.stages.firstIndex(of: stage) ?? 0
        return names.enumerated().map { i, n in (n, i < at ? .done : (i == at ? .on : .off)) }
    }

    static func isDoctorStage(_ stage: String) -> Bool { stage.hasPrefix("doctor-") }

    /// macOS said no to the Downloads folder (the user clicked Don't Allow): EPERM.
    static func isPermissionError(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("operation not permitted") || m.contains("eperm") || m.contains("[errno 1]")
    }

    /// The one-line hint under every red FAILED readout.
    static func failureHint(download: Bool) -> String { download ? Brand.downloadHint : Brand.doctorHint }

    /// The caption under a partial analysis: some files read, the helper then stopped.
    static func partialNote(_ unread: Int) -> String {
        "\(unread) \(unread == 1 ? "FILE" : "FILES") COULDN'T BE READ · \(Brand.doctorHint)"
    }

    /// An error sentence from explain_error, as the LCD shows it. A permission refusal becomes
    /// the place to allow it.
    static func errorText(_ message: String) -> String {
        if isPermissionError(message) { return Doctor.permissionHint.uppercased() }
        var m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        while m.hasSuffix(".") { m.removeLast() }
        return m.uppercased()
    }

    static let audioExtensions: Set<String> = ["mp3", "wav", "aif", "aiff", "flac", "m4a", "aac", "ogg"]

    /// The dropped items worth analyzing: regular audio files. Folders, PDFs and the rest are
    /// left out, so they never show up as empty rows or inflate "N OF M".
    static func audioFiles(_ urls: [URL]) -> [URL] {
        urls.filter { u in
            guard u.isFileURL,
                  (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { return false }
            let ext = u.pathExtension.lowercased()
            if audioExtensions.contains(ext) { return true }
            return UTType(filenameExtension: ext)?.conforms(to: .audio) ?? false
        }
    }

    /// "NAME · FOLDER", the LCD's file line.
    static func fileLine(_ r: Result) -> String {
        "\(r.name) · \(r.file.deletingLastPathComponent().lastPathComponent)".uppercased()
    }
}

/// "1 of N" paging through several dropped files.
struct Pager: Equatable {
    private(set) var count: Int = 0
    private(set) var index: Int = 0

    /// A new set of results opens on the last one.
    mutating func reset(count: Int) {
        self.count = max(0, count)
        index = max(0, self.count - 1)
    }
    mutating func next() { if index + 1 < count { index += 1 } }
    mutating func previous() { if index > 0 { index -= 1 } }
    var caption: String? { count > 1 ? "\(index + 1) OF \(count)" : nil }
}

enum LastAction { case download, analyze }

/// UI state that is not the engine's: the field, focus, drag hover, paging.
final class FaceplateModel: ObservableObject {
    @Published var url = ""
    @Published var fieldFocused = false
    /// Audio chosen with the Open Audio... field, waiting for FIND KEY/BPM.
    @Published var picked: [URL] = []
    @Published var pickFocused = false
    @Published var dropTargeted = false
    @Published var pager = Pager()
    @Published var lastAction: LastAction = .download
    /// ORION_FAKE_STATE=drop pins the drag highlight for screenshots.
    @Published var pinnedDrop = false
}

/// ORION_FAKE_STATE=needs-login|needs-login-bot|idle|working|done|drop|error|lit|multi|picked|picked-multi|eperm|
/// analyze-error|doctor-working|doctor-ok|doctor-fixed|doctor-failed pins the faceplate for screenshots (no Python).
enum FakeState {
    static func apply(_ name: String, engine: Engine, model: FaceplateModel) {
        let dl = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        switch name {
        case "idle":
            engine.state = .idle
        case "working":
            model.url = "https://www.youtube.com/watch?v=xxxxxxxxxxx"
            engine.state = .working(stage: "analyzing")
        case "done":
            let name = "Track Title (142.0 BPM Cm Eb Gm).mp3"
            engine.state = .done(Result(file: dl.appendingPathComponent(name), name: name, bpm: "142.0",
                                        keys: [("Cm", 64), ("Eb", 18), ("Gm", 9)]))
        case "drop":
            model.pinnedDrop = true
        case "error":
            model.url = "https://youtu.be/xxxxxxxxxxx"
            engine.state = .failed("That video is private or was removed.")
        case "multi":   // three dropped files, paged with the arrow keys
            model.lastAction = .analyze
            let rs = [("Beat A.wav", "90.0", "Am"), ("Beat B.wav", "120.0", "F#m"), ("Beat C.wav", "142.0", "Cm")]
                .map { n, b, k in Result(file: dl.appendingPathComponent(n), name: n, bpm: b,
                                         keys: [(k, 61), ("Eb", 18), ("Gm", 9)]) }
            engine.state = .analyzed(rs)
        case "needs-login", "needs-login-bot":
            model.url = "https://www.youtube.com/watch?v=xxxxxxxxxxx"
            engine.state = .needsLogin(LoginPrompt(url: model.url, reason: name == "needs-login" ? "age" : "bot"))
        case "lit":
            model.url = "https://www.youtube.com/watch?v=xxxxxxxxxxx"
        case "picked":
            model.picked = [dl.appendingPathComponent("Beat A.wav")]
        case "picked-multi":
            model.picked = ["Beat A.wav", "Beat B.wav", "Beat C.wav"].map { dl.appendingPathComponent($0) }
        case "eperm":
            model.url = "https://youtu.be/xxxxxxxxxxx"
            engine.state = .failed("Download failed: [Errno 1] Operation not permitted: '/Users/x/Downloads'")
        case "analyze-error":
            model.lastAction = .analyze
            engine.state = .failed("The helper stopped unexpectedly (exit 9).")
        case "doctor-working":
            engine.state = .working(stage: "doctor-ffmpeg")
        case "doctor-ok":
            engine.state = .doctor(DoctorReport(outcome: .ok, title: "DOCTOR OK",
                                                line: "YT-DLP 2026.10.26 · ALL CHECKS PASSED"))
        case "doctor-fixed":
            engine.state = .doctor(DoctorReport(outcome: .fixed, title: "DOCTOR FIXED IT",
                                                line: "RESTORED YT-DLP · YT-DLP 2026.10.26"))
        case "doctor-failed":
            engine.state = .doctor(DoctorReport(outcome: .failed, title: "DOCTOR FOUND A PROBLEM",
                                                line: Doctor.permissionHint.uppercased()))
        default:
            break
        }
    }
}
