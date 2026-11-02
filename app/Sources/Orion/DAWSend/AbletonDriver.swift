import Foundation

/// Ableton Live 11 / 12 through Beat Key's Remote Script (Resources/BeatKeyAbleton.py), OSC on
/// UDP 127.0.0.1:11041. Live 12: tempo + root note + scale (Song.root_note / Song.scale_name);
/// Live 11 has no song scale: tempo only. Analyze Selection = the Detail View clip's file.
struct AbletonDriver: DAWDriver {
    let daw = DAW.ableton
    static let port: UInt16 = 11041
    var port: UInt16 = AbletonDriver.port
    var userLibrary: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Music/Ableton/User Library", isDirectory: true)

    var scriptFolder: URL { userLibrary.appendingPathComponent("Remote Scripts/BeatKey", isDirectory: true) }
    var installedScript: URL { scriptFolder.appendingPathComponent("__init__.py") }

    struct Pong: Equatable { let version: String; let hasScale: Bool; let liveMajor: Int }

    static func setMessage(_ p: SendPayload) -> OSC.Message {
        let t = p.tonic
        return OSC.Message("/beatkey/set", [.float(Float(p.bpm ?? 0)), .int(Int32(t?.pc ?? -1)),
                                            .string(t.map { $0.minor ? "Minor" : "Major" } ?? "")])
    }

    func send(_ p: SendPayload) throws -> String {
        let pong = try ping()
        let reply = try request(AbletonDriver.setMessage(p))
        guard reply.address == "/beatkey/ok" else { throw DAWError(reply.string(0) ?? "Live said no.") }
        return AbletonDriver.report(p, reply: reply, pong: pong)
    }

    /// The result line, from what Live read back after the change.
    static func report(_ p: SendPayload, reply: OSC.Message, pong: Pong) -> String {
        var parts: [String] = []
        if let want = p.bpm, let got = reply.float(0) {
            parts.append(abs(got - want) < 0.01 ? String(format: "Tempo %.2f", got)
                                                 : String(format: "Tempo is %.2f (asked %.2f)", got, want))
        }
        if p.tonic != nil {
            if pong.hasScale, let root = reply.int(1), let scale = reply.string(2), root >= 0 {
                let names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
                parts.append("Key \(names[root % 12]) \(scale)")
            } else {
                parts.append("key not sent: Live \(pong.liveMajor > 0 ? String(pong.liveMajor) : "11") has no song key (Live 12 does)")
            }
        }
        return parts.joined(separator: " · ") + "."
    }

    func selectionAudio() throws -> [URL] {
        _ = try ping()
        let r = try request(OSC.Message("/beatkey/selection"))
        guard r.address == "/beatkey/selection", let path = r.string(0) else { throw DAWError(r.string(0) ?? "Live gave no clip.") }
        return [URL(fileURLWithPath: path)]
    }

    func ping() throws -> Pong {
        do {
            let r = try UDP.request(OSC.Message("/beatkey/ping"), port: port, timeout: 1.0)
            return Pong(version: r.string(0) ?? "?", hasScale: (r.int(1) ?? 0) == 1, liveMajor: r.int(2) ?? 0)
        } catch UDP.Failure.noReply {
            throw setupStep()
        }
    }

    private func request(_ m: OSC.Message) throws -> OSC.Message {
        do { return try UDP.request(m, port: port, timeout: 2.0) }
        catch UDP.Failure.noReply { throw DAWError("Live stopped answering.") }
    }

    /// Not installed: offer to install. Installed but silent: say where to turn it on.
    func setupStep() -> SetupNeeded {
        let turnOn = "In Live open Settings › Link, Tempo & MIDI and pick BeatKey as a Control Surface (Input and Output: None). Then send again."
        if FileManager.default.fileExists(atPath: installedScript.path) {
            return SetupNeeded(title: "Turn on Beat Key in Live", message: "Live is not answering. " + turnOn
                               + " If Live was open when the script was installed, restart Live first.",
                               button: "Try Again", install: nil)
        }
        return SetupNeeded(title: "Install Beat Key's Remote Script for Live?",
                           message: "Live takes tempo and key from a small Remote Script. Beat Key will put it in \(scriptFolder.path).\n\nAfter that: restart Live, then " + turnOn.prefix(1).lowercased() + turnOn.dropFirst(),
                           button: "Install") { try install() }
    }

    func install() throws {
        guard let src = DAWFiles.script("BeatKeyAbleton", ext: "py") else { throw DAWError("The Remote Script is missing from Beat Key.") }
        try DAWFiles.write(src, to: installedScript)
    }
}
