import Foundation

/// Pro Tools over PTSL (gRPC, 127.0.0.1:31416).
/// Send: PTSL 2026.4 has no command that sets the tempo or key rulers (every CommandId in the
/// SDK's PTSL.proto was checked), so Pro Tools gets the MIDI file to import, plus the tempo the
/// session is at now, read through PTSL so the person can see whether it needs changing.
/// Analyze Selection: CId_ExportClipsAsFiles writes the selected clip(s) to a temp folder as WAV,
/// and those files are analysed like any other.
struct ProToolsDriver: DAWDriver {
    let daw = DAW.proTools
    var port: UInt16 = PTSLClient.port

    func send(_ p: SendPayload) throws -> String {
        let midi = try MidiFileDriver(daw: .proTools).send(p)
        guard let now = try? sessionTempo() else { return midi }
        return "The session is at \(String(format: "%.2f", now)) BPM now. " + midi
    }

    func selectionAudio() throws -> [URL] {
        let c = try connect()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BeatKey-PT-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try c.call(.exportClipsAsFiles, ProToolsDriver.exportBody(dir))
        } catch let PTSLClient.Failure.failed(_, e) {
            throw DAWError("Select a clip in the Pro Tools Edit window first (\(PTSLClient.errorText(e))).")
        }
        let files = ProToolsDriver.audioFiles(in: dir)
        guard !files.isEmpty else { throw DAWError("Pro Tools exported nothing. Select an audio clip (not MIDI) and try again.") }
        return files
    }

    static func exportBody(_ dir: URL) -> [String: Any] {
        ["file_path": dir.path.hasSuffix("/") ? dir.path : dir.path + "/",
         "format": "EFormat_Interleaved", "file_type": "EFType_WAV", "bit_depth": "BDepth_24",
         "duplicate_names": "RDNBy_AutoRenaming", "enforce_avid_compatibility": false]
    }

    static func audioFiles(in dir: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.filter { ["wav", "aif", "aiff"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The tempo at the session start: the length of beat 1 in samples (GetTimeAsType) against
    /// the sample rate. Assumes a quarter-note beat, as the MIDI tempo does.
    func sessionTempo() throws -> Double {
        let c = try connect()
        func samples(_ bb: String) throws -> Double {
            let r = try c.call(.getTimeAsType, ["location": ["location": bb, "time_type": "TLType_BarsBeats"], "time_type": "TLType_Samples"])
            guard let loc = (r["converted_location"] as? [String: Any])?["location"] as? String, let v = Double(loc) else {
                throw DAWError("Pro Tools gave no time for \(bb).")
            }
            return v
        }
        let beat = try samples("1|2|000") - samples("1|1|000")
        let sr = try sampleRate(c)
        guard beat > 0 else { throw DAWError("Pro Tools gave a zero-length beat.") }
        return ProToolsDriver.bpm(beatSamples: beat, sampleRate: sr)
    }

    static func bpm(beatSamples: Double, sampleRate: Double) -> Double { 60 * sampleRate / beatSamples }

    private func sampleRate(_ c: PTSLClient) throws -> Double {
        let r = try c.call(.getSessionSampleRate)
        guard let s = r["sample_rate"] as? String, let v = ProToolsDriver.parseRate(s) else { throw DAWError("Pro Tools gave no sample rate.") }
        return v
    }

    /// "SR_48000" -> 48000.
    static func parseRate(_ s: String) -> Double? { Double(s.replacingOccurrences(of: "SR_", with: "")) }

    private func connect() throws -> PTSLClient {
        let c = try PTSLClient(port: port)
        try c.register()
        return c
    }
}
