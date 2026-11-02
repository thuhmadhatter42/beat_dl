import AppKit
import SwiftUI

/// Send Key to Waves Tune: Waves Tune Real-Time has no outside key hand-off (its Receive Key
/// link only listens to Waves' own Key Detector inside the DAW), so Beat Key writes a USER
/// PRESET, "Beat Key", into Waves' user-preset folder. Load it from the plug-in's preset menu
/// (Load > Beat Key) and it sets the root and scale only: every parameter is "R" (keep), the
/// trick Waves' own "Full Reset" preset uses to load only its Scale.
/// Format from the plug-in's factory presets (Resources/Presets/1000.xml) and scales
/// (Resources/XScl/1000): Scale Name "Major" / "Natural Minor", 12 notes root-relative in cents,
/// NoteStatus 0 = in the scale, x = out; Root = pitch class from C.
enum WavesTuneSend {
    static var presetURL: URL {
        URL(fileURLWithPath: "/Users/Shared/Waves/Plug-In Settings/Waves Tune Real-Time User Presets/Beat Key.xps")
    }

    /// Waves Tune Real-Time is installed (V14 or any version folder).
    static var installed: Bool {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: "/Applications/Waves") else { return false }
        return dirs.contains { fm.fileExists(atPath: "/Applications/Waves/\($0)/Waves Tune Real-Time.bundle") }
    }

    static let majorSteps: Set<Int> = [0, 2, 4, 5, 7, 9, 11]
    static let minorSteps: Set<Int> = [0, 2, 3, 5, 7, 8, 10]

    static func contents(pitchClass: Int, minor: Bool, keyName: String) -> String {
        let steps = minor ? minorSteps : majorSteps
        let notes = (0..<12).map { i in
            "                <Note NoteCents=\"\(i * 100)\" StatusIsForAllOctaves=\"true\">\n"
            + "                    <NoteStatus>\(steps.contains(i) ? "0" : "x")</NoteStatus>\n"
            + "                </Note>\n"
        }.joined()
        let keep = (0..<83).map { _ in "R" }.joined(separator: " ")
        return """
        <?xml version="1.0" standalone="yes"?>

        <PresetXMLTree version="1">
          <Preset Name="Beat Key - \(keyName)" GenericType="TNLV">
            <PresetHeader>
              <PluginName>Waves Tune Real-Time</PluginName>
              <ReadOnly>false</ReadOnly>
            </PresetHeader>
            <PresetData Setup="CURRENT">
              <Parameters>
                \(keep)
              </Parameters>
              <PluginSpecific DataType="XMLObject" TagID="0" TagName="Scale">
                <Data>
                  <Scale Name="\(minor ? "Natural Minor" : "Major")">
                    <NoteSegmentation>

        """ + notes + """
                    </NoteSegmentation>
                    <Root>\(pitchClass)</Root>
                    <ScaleHasChanged>false</ScaleHasChanged>
                  </Scale>
                </Data>
              </PluginSpecific>
            </PresetData>
          </Preset>
        </PresetXMLTree>

        """
    }

    @discardableResult
    static func write(key: String, to url: URL = presetURL) -> Bool {
        guard let k = AutoTuneSend.keyClass(key) else { return false }
        let text = contents(pitchClass: k.pitchClass, minor: k.minor, keyName: key)
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
            AppLog.log("sent \(key) to Waves Tune preset \(url.path)")
            return true
        } catch {
            AppLog.log("Waves Tune preset write failed: \(error)")
            return false
        }
    }
}

struct SendToWavesTuneMenuItem: View {
    @ObservedObject var engine: Engine
    var body: some View {
        let key = MidiExport.current(engine.state)?.keys.first?.0
        Button("Send Key to Waves Tune (preset “Beat Key”)") {
            if let key, !WavesTuneSend.write(key: key) { NSSound.beep() }
        }
        .disabled(key.flatMap(AutoTuneSend.keyClass) == nil)
    }
}
