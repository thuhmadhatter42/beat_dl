import AppKit

/// The MIDI-file hand-off for DAWs nothing outside can set tempo in (FL Studio, Reason, Cubase);
/// not used by the Accessibility DAWs (Pro Tools, Logic, Studio One).
/// Writes "<track> (<bpm> BPM <key>).mid" with set-tempo + key-signature (MidiExport) to
/// ~/Library/Application Support/Beat Key/DAW/MIDI, shows it in Finder, and says how this DAW
/// imports tempo from it.
struct MidiFileDriver: DAWDriver {
    let daw: DAW
    var folder: URL = DAWFiles.support.appendingPathComponent("MIDI", isDirectory: true)
    var reveal: (URL) -> Void = { url in DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([url]) } }

    func send(_ p: SendPayload) throws -> String {
        let url = try write(p)
        reveal(url)
        return "Beat Key put \(url.lastPathComponent) in Finder. \(MidiFileDriver.howTo(daw))"
    }

    func write(_ p: SendPayload) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = MidiExport.suggestedName(track: p.trackName, bpm: p.bpm.map { String(format: "%.2f", $0) }, key: p.key)
        let url = folder.appendingPathComponent(name)
        try MidiExport.data(bpm: p.bpm, key: p.key, trackName: p.trackName).write(to: url, options: .atomic)
        return url
    }

    /// Per-DAW import steps; sources in docs/research/send-to-daw.md §1.
    static func howTo(_ d: DAW) -> String {
        switch d {
        case .proTools:
            return "In Pro Tools choose File › Import › MIDI…, pick it, and tick Import Tempo Map and Import Key Signature."
        case .logic:
            return "Logic keeps a MIDI file's tempo when it is opened as a new project (File › Open). Importing into an open project skips the tempo unless Logic asks and you say yes."
        case .flStudio:
            return "In FL Studio choose File › Import › MIDI file and turn on the tempo option in the import dialog (a plain drag may not change the project BPM)."
        case .cubase:
            return "In Cubase choose File › Import › MIDI File; turn on Import Tempo if it asks."
        case .studioOne:
            return "Drag it into the Studio One song and accept the tempo when it asks."
        case .reason:
            return "In Reason choose File › Import MIDI File."
        case .ableton, .reaper, .bitwig:
            return "Drag it into \(d.name)."
        }
    }
}
