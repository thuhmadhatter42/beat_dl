import AppKit
import UniformTypeIdentifiers

/// Files that reach the app from outside its window: Analyze a File… (File menu, ⌃⌥⌘F), the
/// Finder service "Analyze with Beat Key", and Open With / a drop on the Dock icon.
/// The faceplate installs `handler` when it appears (files that arrive while the app is still
/// launching wait for it); while a job runs the handler says no and the file is refused with a beep.
enum Intake {
    static var handler: (([URL]) -> Bool)? {
        didSet { if let go = handler, !waiting.isEmpty { _ = go(waiting); waiting = [] } }
    }
    private static var waiting: [URL] = []

    /// The audio among `urls`, handed to the faceplate. False = nothing was started.
    @discardableResult
    static func receive(_ urls: [URL], via: String = "other") -> Bool {
        let files = Faceplate.audioFiles(urls)
        // how files arrive (counts only, never names): proves the Finder service and Open With work
        AppLog.log("intake via \(via): \(urls.count) item(s), \(files.count) audio\(handler == nil ? ", queued until the window is up" : "")")
        guard !files.isEmpty else { NSSound.beep(); return false }
        guard let go = handler else { waiting = files; return true }
        NSApp?.activate(ignoringOtherApps: true)
        if go(files) { return true }
        NSSound.beep()
        return false
    }

    /// The audio-only open panel (the drop filter's allowlist), several files allowed.
    static func makePanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Faceplate.audioExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Choose"
        panel.message = "Choose a beat to find its BPM and key"
        return panel
    }

    /// File › Analyze a File…: pick, then read it straight away.
    static func analyzeAFile() {
        let panel = makePanel()
        panel.message = "Choose a beat, video or MIDI file to find its BPM and key"
        let pick = { (resp: NSApplication.ModalResponse) in
            guard resp == .OK else { return }
            receive(panel.urls, via: "analyze a file")
        }
        if let w = NSApp.keyWindow ?? NSApp.windows.first { panel.beginSheetModal(for: w, completionHandler: pick) }
        else { pick(panel.runModal()) }
    }
}

/// Finder › Services › "Analyze with Beat Key" (NSServices in Info.plist, message
/// `analyzeWithBeatKey`) and Open With.
final class ServiceProvider: NSObject {
    @objc func analyzeWithBeatKey(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self],
                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if urls.isEmpty { error.pointee = "Select an audio, video or MIDI file in Finder first." as NSString; return }
        if !Intake.receive(urls, via: "finder service") { error.pointee = "Beat Key is busy or found no audio in the selection." as NSString }
    }
}
