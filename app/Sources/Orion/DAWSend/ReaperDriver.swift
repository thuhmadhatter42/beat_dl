import Foundation

/// REAPER through Beat Key's ReaScript (Resources/BeatKeyReaper.lua), which polls a mailbox
/// folder with reaper.defer: request.txt in, reply.txt out (Lua in REAPER has no sockets without
/// extensions). Tempo only: REAPER has no project key. Analyze Selection = the selected item's
/// source file (GetSelectedMediaItem › GetActiveTake › GetMediaItemTake_Source).
struct ReaperDriver: DAWDriver {
    let daw = DAW.reaper
    var mailbox: URL = DAWFiles.support.appendingPathComponent("REAPER", isDirectory: true)
    var resourcePath: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/REAPER", isDirectory: true)
    var timeout: TimeInterval = 2.0

    static let scriptName = "Beat Key Listener.lua"
    var installedScript: URL { resourcePath.appendingPathComponent("Scripts/\(ReaperDriver.scriptName)") }

    static func encode(_ fields: [String: String]) -> String {
        fields.keys.sorted().map { "\($0)=\(fields[$0]!.replacingOccurrences(of: "\n", with: " "))" }.joined(separator: "\n") + "\n"
    }

    static func decode(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            out[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        return out
    }

    func send(_ p: SendPayload) throws -> String {
        guard let bpm = p.bpm else { return "No tempo to send (REAPER has no project key)." }
        let r = try ask(["cmd": "set", "bpm": String(format: "%.4f", bpm)])
        guard r["ok"] == "1" else { throw DAWError(r["error"] ?? "REAPER said no.") }
        let got = Double(r["bpm"] ?? "") ?? 0
        let tempo = abs(got - bpm) < 0.01 ? String(format: "Tempo %.2f", got) : String(format: "Tempo is %.2f (asked %.2f)", got, bpm)
        return tempo + (p.key != nil ? " · key not sent (REAPER has no project key)." : ".")
    }

    func selectionAudio() throws -> [URL] {
        let r = try ask(["cmd": "selection"])
        guard r["ok"] == "1", let f = r["file"], !f.isEmpty else { throw DAWError(r["error"] ?? "REAPER gave no file.") }
        return [URL(fileURLWithPath: f)]
    }

    /// One request through the mailbox; waits for the reply with the same id.
    func ask(_ fields: [String: String]) throws -> [String: String] {
        let id = UUID().uuidString
        var f = fields; f["id"] = id
        let reply = mailbox.appendingPathComponent("reply.txt")
        try DAWFiles.write(ReaperDriver.encode(f), to: mailbox.appendingPathComponent("request.txt"))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = try? String(contentsOf: reply, encoding: .utf8) {
                let r = ReaperDriver.decode(text)
                if r["id"] == id { return r }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw setupStep()
    }

    func setupStep() -> SetupNeeded {
        let run = "In REAPER choose Actions › Show action list › New action › Load ReaScript…, pick “\(ReaperDriver.scriptName)” and click Run. It stays on until REAPER quits (run it again after each restart)."
        if FileManager.default.fileExists(atPath: installedScript.path) {
            return SetupNeeded(title: "Start Beat Key's listener in REAPER", message: "REAPER is not answering. " + run,
                               button: "Try Again", install: nil)
        }
        return SetupNeeded(title: "Install Beat Key's ReaScript for REAPER?",
                           message: "REAPER takes the tempo from a small ReaScript. Beat Key will put it in \(installedScript.deletingLastPathComponent().path).\n\nThen: " + run,
                           button: "Install") { try install() }
    }

    func install() throws {
        guard let src = DAWFiles.script("BeatKeyReaper", ext: "lua") else { throw DAWError("The ReaScript is missing from Beat Key.") }
        try DAWFiles.write(src, to: installedScript)
    }
}
