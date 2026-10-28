import Foundation
import UniformTypeIdentifiers

/// The faceplate's own logic, kept out of the views so it can be tested.
enum Faceplate {
    /// DOWNLOAD lights when the field holds a link and nothing is running.
    static func isLit(_ text: String, busy: Bool) -> Bool {
        !busy && text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http")
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
        case "analyzing": return "FINDING BPM AND KEY"
        case "renaming": return "RENAMING THE FILE"
        default: return stage.uppercased()
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

    /// An error sentence from explain_error, as the LCD shows it.
    static func errorText(_ message: String) -> String {
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
    @Published var dropTargeted = false
    @Published var pager = Pager()
    @Published var lastAction: LastAction = .download
    /// ORION_FAKE_STATE=drop pins the drag highlight for screenshots.
    @Published var pinnedDrop = false
}

/// ORION_FAKE_STATE=idle|working|done|drop|error|lit pins the faceplate for screenshots (no Python).
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
        case "lit":
            model.url = "https://www.youtube.com/watch?v=xxxxxxxxxxx"
        default:
            break
        }
    }
}
