import AppKit
import SwiftUI

/// File > Export MIDI Tempo/Key File…: a standard MIDI file (format 0) with a set-tempo and a
/// key-signature meta event, for any DAW that imports tempo / key from MIDI. No notes.
enum MidiExport {
    static let ticksPerQuarter: UInt16 = 480

    /// A key name as the analyzer writes it ("Cm", "Ebm", "F#", "Bb", "C#m") to the key-signature
    /// bytes: sharps(+) / flats(-) -7...+7 and minor. nil = not a key name.
    static func keySignature(_ name: String) -> (sharps: Int, minor: Bool)? {
        var s = name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
        var minor = false
        if s.hasSuffix("m") { minor = true; s.removeLast() }
        let major: [String: Int] = ["C": 0, "G": 1, "D": 2, "A": 3, "E": 4, "B": 5, "F#": 6, "C#": 7,
                                    "F": -1, "Bb": -2, "Eb": -3, "Ab": -4, "Db": -5, "Gb": -6, "Cb": -7]
        let minors: [String: Int] = ["A": 0, "E": 1, "B": 2, "F#": 3, "C#": 4, "G#": 5, "D#": 6, "A#": 7,
                                     "D": -1, "G": -2, "C": -3, "F": -4, "Bb": -5, "Eb": -6, "Ab": -7]
        guard let n = (minor ? minors : major)[s] else { return nil }
        return (n, minor)
    }

    /// The file's bytes. `bpm` outside 1...1000 or nil writes no tempo event; an unknown key
    /// writes no key event.
    static func data(bpm: Double?, key: String?, trackName: String? = nil) -> Data {
        var t = [UInt8]()
        func event(_ bytes: [UInt8]) { t.append(0); t += bytes }   // every event at tick 0
        if let name = trackName, !name.isEmpty {
            let b = Array(name.utf8.prefix(120))
            event([0xFF, 0x03, UInt8(b.count)] + b)
        }
        if let bpm, (1...1000).contains(bpm) {
            let us = UInt32((60_000_000 / bpm).rounded())
            event([0xFF, 0x51, 0x03, UInt8(us >> 16 & 0xFF), UInt8(us >> 8 & 0xFF), UInt8(us & 0xFF)])
            event([0xFF, 0x58, 0x04, 4, 2, 24, 8])   // 4/4, so the DAW has a full meter
        }
        if let key, let k = keySignature(key) {
            event([0xFF, 0x59, 0x02, UInt8(bitPattern: Int8(k.sharps)), k.minor ? 1 : 0])
        }
        event([0xFF, 0x2F, 0x00])
        var out = Data("MThd".utf8)
        out += be32(6) + be16(0) + be16(1) + be16(ticksPerQuarter)
        out += Data("MTrk".utf8) + be32(UInt32(t.count)) + Data(t)
        return out
    }

    private static func be16(_ v: UInt16) -> Data { Data([UInt8(v >> 8), UInt8(v & 0xFF)]) }
    private static func be32(_ v: UInt32) -> Data {
        Data([UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)])
    }

    /// The reading's BPM as a number ("140.82" or "142.0"); nil when there is none.
    /// (Once Tempo.text lands from the readout work, pass its decimal text here.)
    static func bpmValue(_ r: Result) -> Double? { r.bpm.flatMap(Double.init) }

    /// "<track> (<bpm> BPM <key>).mid": the track name without its extension or an earlier
    /// "(142.0 BPM Cm Dm)" tag, and without characters a file name cannot hold.
    static func suggestedName(track: String, bpm: String?, key: String?) -> String {
        var base = (track as NSString).deletingPathExtension
        if let r = base.range(of: #" \([^()]*BPM[^()]*\)$"#, options: .regularExpression) { base.removeSubrange(r) }
        base = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let tag = [bpm.map { "\($0) BPM" }, key].compactMap { $0 }.joined(separator: " ")
        return (tag.isEmpty ? base : "\(base) (\(tag))") + ".mid"
    }

    /// The reading the window is showing: a finished download, or the first analysed file.
    static func current(_ state: ViewState) -> Result? {
        switch state {
        case .done(let r): return r
        case .analyzed(let rs): return rs.first
        default: return nil
        }
    }

    static func runPanel(for r: Result) {
        let key = r.keys.first?.0
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["mid"]
        panel.nameFieldStringValue = suggestedName(track: r.name, bpm: r.bpm, key: key)
        panel.directoryURL = r.file.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bytes = data(bpm: bpmValue(r), key: key, trackName: (r.name as NSString).deletingPathExtension)
        do { try bytes.write(to: url) } catch { NSAlert(error: error).runModal() }
    }
}

/// The File menu item. Disabled until there is a reading with a tempo or a key.
struct ExportMidiMenuItem: View {
    @ObservedObject var engine: Engine
    var body: some View {
        let r = MidiExport.current(engine.state)
        let usable = r.map { $0.bpm != nil || !$0.keys.isEmpty } ?? false
        Button("Export MIDI Tempo/Key File…") { if let r { MidiExport.runPanel(for: r) } }
            .keyboardShortcut("e", modifiers: [.control, .option, .command])
            .disabled(!usable)
    }
}
