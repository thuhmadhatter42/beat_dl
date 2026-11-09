import AppKit
import CryptoKit
import Foundation

// "Wrong, it's X": J picks the right key for a reading. It becomes THE key (KeyChoice, the one
// override path) and a teach record is saved for training the key model later:
// ~/Library/Application Support/Beat Key/teach/<timestamp>/label.json + the audio (a copy of the
// file under 50 MB, Listen's last minute as a WAV, else only the path or link). Every save and
// every failure goes to beatkey.log, with ids and hashes only, never a song or file name.

/// Where the reading came from.
enum TeachSource: String, Codable {
    case file, live, youtube
}

/// What the record holds of the audio.
enum TeachAudio {
    /// A file on disk (an analyzed file or a downloaded MP3): copied if under the limit, else its path.
    case file(URL, link: String?)
    /// Listen's recent samples (mono float32).
    case clip([Float], sampleRate: Int)
    /// Nothing to keep but a link (or nothing at all).
    case none(link: String?)
}

/// label.json.
struct TeachLabel: Codable, Equatable {
    struct Key: Codable, Equatable {
        let name: String
        let score: Int
    }
    struct Audio: Codable, Equatable {
        /// "copy" (file beside label.json), "path" (too big: where it is), "clip" (Listen's WAV
        /// beside label.json), "none" (only `link`, if any).
        let kind: String
        /// The file beside label.json ("audio.mp3", "clip.wav"); nil for path / none.
        var file: String? = nil
        /// The original file's path (copy and path kinds).
        var sourcePath: String? = nil
        /// The YouTube (or other) link it was downloaded from.
        var link: String? = nil
        var bytes: Int? = nil
        /// sha256 of the original file's path: the id the log uses.
        var pathHash: String? = nil
        var seconds: Double? = nil
    }
    let chosen: String
    let chosenPitchClass: Int
    let chosenMinor: Bool
    /// The analyzer's own top 3, in its order, with its scores (before any choice).
    let analyzerTop3: [Key]
    let bpm: String?
    let bpmExact: Double?
    let source: TeachSource
    let appVersion: String
    /// Local time, ISO 8601 with offset.
    let created: String
    let audio: Audio
}

enum TeachStore {
    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Beat Key/teach")
    }
    /// Files at or above this are not copied; the record keeps their path.
    static let copyLimit = 50 * 1024 * 1024

    enum Failure: Error, Equatable {
        case notAKey(String)
    }

    /// Folder names sort by time: 2026-11-05_14-03-22.418.
    static func folderName(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss.SSS"
        return f.string(from: d)
    }

    /// An error for the log without its message (Foundation's messages name the file).
    static func code(_ e: Error) -> String {
        if let f = e as? Failure { return "\(f)" }
        let n = e as NSError
        return "\(n.domain) \(n.code)"
    }

    static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    /// Writes one record and returns its folder. `raw` = the reading as the analyzer gave it.
    /// Throws when nothing could be written (the caller logs it); a failed audio copy still
    /// writes label.json, with the path instead.
    @discardableResult
    static func save(chosen: String, raw: Result, source: TeachSource, audio: TeachAudio,
                     root: URL = TeachStore.root, now: Date = Date(),
                     version: String = AppLog.version) throws -> URL {
        guard let k = AutoTuneSend.keyClass(chosen) else { throw Failure.notAKey(chosen) }
        let fm = FileManager.default
        var dir = root.appendingPathComponent(folderName(now))
        var n = 2
        while fm.fileExists(atPath: dir.path) {
            dir = root.appendingPathComponent("\(folderName(now))-\(n)"); n += 1
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let a: TeachLabel.Audio
        switch audio {
        case .file(let url, let link):
            let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue
            let ph = hash(url.path)
            if let size, size < copyLimit {
                let ext = url.pathExtension.isEmpty ? "audio" : url.pathExtension.lowercased()
                let name = "audio.\(ext)"
                do {
                    try fm.copyItem(at: url, to: dir.appendingPathComponent(name))
                    a = .init(kind: "copy", file: name, sourcePath: url.path, link: link, bytes: size, pathHash: ph)
                } catch {
                    AppLog.log("teach: audio copy failed (file \(ph)): \(TeachStore.code(error)); keeping the path")
                    a = .init(kind: "path", sourcePath: url.path, link: link, bytes: size, pathHash: ph)
                }
            } else {
                if size == nil { AppLog.log("teach: audio file \(ph) not readable; keeping the path") }
                a = .init(kind: "path", sourcePath: url.path, link: link, bytes: size, pathHash: ph)
            }
        case .clip(let samples, let rate):
            if samples.isEmpty {
                a = .init(kind: "none")
            } else {
                let data = Wav.mono16(samples, sampleRate: rate)
                do {
                    try data.write(to: dir.appendingPathComponent("clip.wav"))
                    a = .init(kind: "clip", file: "clip.wav", bytes: data.count,
                              seconds: (Double(samples.count) / Double(rate) * 10).rounded() / 10)
                } catch {
                    AppLog.log("teach: clip write failed: \(TeachStore.code(error))")
                    a = .init(kind: "none")
                }
            }
        case .none(let link):
            a = .init(kind: "none", link: link)
        }

        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let label = TeachLabel(chosen: KeyChoice.keyName(k.pitchClass, minor: k.minor),
                               chosenPitchClass: k.pitchClass, chosenMinor: k.minor,
                               analyzerTop3: raw.keys.prefix(3).map { .init(name: $0.0, score: $0.1) },
                               bpm: raw.bpm, bpmExact: raw.bpmExact, source: source, appVersion: version,
                               created: iso.string(from: now), audio: a)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(label).write(to: dir.appendingPathComponent("label.json"), options: .atomic)
        return dir
    }
}

/// A 16-bit PCM mono WAV, for Listen's clip.
enum Wav {
    static func mono16(_ samples: [Float], sampleRate: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        let dataBytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        var pcm = [Int16](repeating: 0, count: samples.count)
        for (i, s) in samples.enumerated() { pcm[i] = Int16(max(-1, min(1, s)) * 32767) }
        for i in pcm.indices { pcm[i] = pcm[i].littleEndian }
        pcm.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }
}

/// The last `seconds` of Listen's samples, for a teach record.
struct ClipRing {
    let capacity: Int
    private(set) var samples: [Float] = []

    init(seconds: Double, sampleRate: Int) { capacity = Int(seconds * Double(sampleRate)) }

    mutating func append(_ s: [Float]) {
        samples.append(contentsOf: s)
        // trim in chunks so a long listen is not a copy per callback
        if samples.count > capacity + capacity / 4 { samples.removeFirst(samples.count - capacity) }
    }

    var last: [Float] { samples.count > capacity ? Array(samples.suffix(capacity)) : samples }
    mutating func clear() { samples.removeAll(keepingCapacity: false) }
}

/// The "Wrong, it's X" action: choose the key, then save the record off the main thread.
enum KeyTeach {
    /// The reading as the analyzer gave it (no choice, no respelling): what the record labels.
    static func raw(_ state: ViewState, live: LiveState, page: Pager) -> Result? {
        if live.isActive { return live.result }
        switch state {
        case .done(let r): return r
        case .analyzed(let rs) where !rs.isEmpty: return rs[min(max(page.index, 0), rs.count - 1)]
        default: return nil
        }
    }

    static func teach(_ key: String, engine: Engine, live: LiveController, model: FaceplateModel) {
        guard let r = raw(engine.state, live: live.state, page: model.pager) else {
            AppLog.log("teach: no reading on show"); NSSound.beep(); return
        }
        guard SpellingSettings.shared.setManualKey(key, of: r, from: .dropdown) else { return }   // logged; nothing changes
        let source: TeachSource
        let audio: TeachAudio
        if live.state.isActive {
            source = .live
            audio = .clip(live.recentClip(), sampleRate: LiveProcess.sampleRate)
        } else if case .done = engine.state {
            source = .youtube
            let link = model.url.trimmingCharacters(in: .whitespacesAndNewlines)
            audio = FileManager.default.fileExists(atPath: r.file.path) ? .file(r.file, link: link.isEmpty ? nil : link)
                                                                       : .none(link: link.isEmpty ? nil : link)
        } else {
            source = .file
            audio = .file(r.file, link: nil)
        }
        let top = r.keys.first?.0 ?? "-"
        AppLog.log("teach: \(key) (analyzer said \(top)), source \(source.rawValue), saving")
        DispatchQueue.global(qos: .utility).async {
            do {
                let dir = try TeachStore.save(chosen: key, raw: r, source: source, audio: audio)
                AppLog.log("teach: saved \(dir.lastPathComponent)")
            } catch {
                AppLog.log("teach: SAVE FAILED: \(TeachStore.code(error))")
                DispatchQueue.main.async { NSSound.beep() }
            }
        }
    }
}
