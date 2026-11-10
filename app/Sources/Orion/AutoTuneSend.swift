import AppKit
import SwiftUI

/// Reading > Send Key to Auto-Tune: writes the handoff file Antares' Auto-Key plug-in writes and
/// Auto-Tune Pro watches (`~/Music/Audio Music Apps/Temp/Auto-Key.handoff`, JUCE XML, CRLF), so
/// every Auto-Tune Pro instance with Auto Key Detection on takes the key. Undocumented by Antares.
/// KeyClass = tonic pitch class 0...11 from C (the order of Auto-Key's own key list);
/// KeyType 0 = major, 1 = minor (from the one sample on disk, 11/1 = B minor; not yet confirmed live).
enum AutoTuneSend {
    static var handoffURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/Audio Music Apps/Temp/Auto-Key.handoff")
    }

    /// A key name as the analyzer writes it ("Cm", "Ebm", "F#", "Bb") to (pitch class, minor).
    static func keyClass(_ name: String) -> (pitchClass: Int, minor: Bool)? {
        var s = name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
        var minor = false
        if s.hasSuffix("m") { minor = true; s.removeLast() }
        let pcs: [String: Int] = ["C": 0, "B#": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "Fb": 4,
                                  "E#": 5, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9,
                                  "A#": 10, "Bb": 10, "B": 11, "Cb": 11]
        guard let pc = pcs[s] else { return nil }
        return (pc, minor)
    }

    /// The file's text, byte for byte as Auto-Key writes it. `tempo` nil = -1 (no tempo).
    static func contents(pitchClass: Int, minor: Bool, referencePitch: Double, tempo: Double? = nil) -> String {
        func num(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%g", v) }
        let t = tempo.map(num) ?? "-1"
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r\n\r\n<PROPERTIES>\r\n"
            + "  <VALUE name=\"KeyClass\" val=\"\(pitchClass)\"/>\r\n"
            + "  <VALUE name=\"KeyType\" val=\"\(minor ? 1 : 0)\"/>\r\n"
            + "  <VALUE name=\"ReferencePitch\" val=\"\(num(referencePitch))\"/>\r\n"
            + "  <VALUE name=\"TempoBPM\" val=\"\(t)\"/>\r\n"
            + "</PROPERTIES>\r\n"
    }

    /// Writes temp + rename in the same folder (the watcher never sees a half file).
    @discardableResult
    static func write(key: String, referencePitch: Double, to url: URL = handoffURL) -> Bool {
        guard let k = keyClass(key) else {
            AppLog.log("auto-tune hand-off: \"\(key)\" is not a key it can take; nothing written")
            return false
        }
        let text = contents(pitchClass: k.pitchClass, minor: k.minor, referencePitch: referencePitch)
        let dir = url.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".Auto-Key.handoff.\(ProcessInfo.processInfo.processIdentifier).tmp")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: tmp)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
            return true
        } catch {
            AppLog.log("auto-tune hand-off write failed (\(url.path)): \(error)")
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
    }
}

extension AutoTuneSend {
    /// "Send to Auto-Tune" = every pitch corrector at once: Antares Auto-Tune (Auto-Key hand-off)
    /// and Waves Tune Real-Time (the "Beat Key" preset), when installed. True = at least one took it.
    @discardableResult
    static func sendAll(key: String, referencePitch: Double) -> Bool {
        let antares = write(key: key, referencePitch: referencePitch)
        let waves = WavesTuneSend.installed ? WavesTuneSend.write(key: key) : false
        AppLog.log("send to auto-tune \(key): antares \(antares), waves tune \(waves)")
        return antares || waves
    }
}

struct SendToAutoTuneMenuItem: View {
    @ObservedObject var engine: Engine
    @ObservedObject var tuning: TuningSettings
    var body: some View {
        let key = MidiExport.current(engine.state)?.keys.first?.0
        Button("Send Key to Auto-Tune") {
            if let key, !AutoTuneSend.sendAll(key: key, referencePitch: tuning.reference) {
                AppLog.log("send to auto-tune \(key): nothing took it (beep)")
                NSSound.beep()
            }
        }
        .keyboardShortcut("a", modifiers: [.control, .option, .command])
        .disabled(key.flatMap(AutoTuneSend.keyClass) == nil)
    }
}
