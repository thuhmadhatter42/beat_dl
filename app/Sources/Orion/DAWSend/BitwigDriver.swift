import Foundation

/// Bitwig Studio through Beat Key's controller script (Resources/BeatKeyBitwig.control.js):
/// OSC to UDP 11043, answers on 11044. Tempo only: the Controller API has no project key.
struct BitwigDriver: DAWDriver {
    let daw = DAW.bitwig
    static let port: UInt16 = 11043
    static let replyPort: UInt16 = 11044
    var port: UInt16 = BitwigDriver.port
    var replyPort: UInt16 = BitwigDriver.replyPort
    var scriptsFolder: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Bitwig Studio/Controller Scripts", isDirectory: true)

    var installedScript: URL { scriptsFolder.appendingPathComponent("Beat Key/BeatKey.control.js") }

    static func setMessage(_ bpm: Double) -> OSC.Message { OSC.Message("/beatkey/set", [.float(Float(bpm))]) }

    func send(_ p: SendPayload) throws -> String {
        guard let bpm = p.bpm else { return "No tempo to send (Bitwig has no project key)." }
        let r: OSC.Message
        do { r = try UDP.request(BitwigDriver.setMessage(bpm), port: port, replyPort: replyPort, timeout: 1.5) }
        catch UDP.Failure.noReply { throw setupStep() }
        guard r.address == "/beatkey/ok" else { throw DAWError(r.string(0) ?? "Bitwig said no.") }
        return String(format: "Tempo %.2f", r.float(0) ?? bpm) + (p.key != nil ? " · key not sent (Bitwig has no project key)." : ".")
    }

    func setupStep() -> SetupNeeded {
        let add = "In Bitwig open Settings › Controllers › Add Controller, choose Four Letter Records › Beat Key, then send again."
        if FileManager.default.fileExists(atPath: installedScript.path) {
            return SetupNeeded(title: "Add Beat Key in Bitwig", message: "Bitwig is not answering. " + add, button: "Try Again", install: nil)
        }
        return SetupNeeded(title: "Install Beat Key's controller script for Bitwig?",
                           message: "Bitwig takes the tempo from a small controller script. Beat Key will put it in \(installedScript.deletingLastPathComponent().path).\n\nThen: " + add,
                           button: "Install") { try install() }
    }

    func install() throws {
        guard let src = DAWFiles.script("BeatKeyBitwig.control", ext: "js") else { throw DAWError("The controller script is missing from Beat Key.") }
        try DAWFiles.write(src, to: installedScript)
    }
}
