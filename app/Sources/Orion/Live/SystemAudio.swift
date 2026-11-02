import AVFoundation
import CoreGraphics
import CoreMedia
import ScreenCaptureKit

/// Everything the Mac plays, through ScreenCaptureKit's audio (macOS 13+): the main display's
/// stream with audio on and the picture shrunk to 2 x 2 px at one frame a second (SCK has no
/// audio-only filter). Beat Key's own sound is left out. Needs the Screen (& System Audio)
/// Recording permission; nothing is saved.
@available(macOS 13.0, *)
final class SystemAudioCapture: NSObject, AudioCapture, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "com.jshriver.orion.system-audio")
    private var onSamples: (([Float]) -> Void)?
    private var onError: ((String) -> Void)?
    private var stopped = false
    /// SCK only delivers 8/16/24/48 kHz (asking for 44.1 kHz silently gets 48 kHz), so each
    /// buffer's real rate is read and resampled to the analyzer's 44.1 kHz. Unresampled 48 kHz
    /// audio read as 44.1 kHz puts every key ~1.5 semitones flat and every tempo 8 % slow.
    private var resampler: Resampler?
    private var resamplerRate: Double = 0

    /// macOS 15 renamed the privacy pane.
    static var permissionText: String {
        let pane: String
        if #available(macOS 15.0, *) { pane = "SCREEN & SYSTEM AUDIO RECORDING" } else { pane = "SCREEN RECORDING" }
        return "ALLOW \(Brand.wordmark) IN SYSTEM SETTINGS › PRIVACY & SECURITY › \(pane)"
    }

    func start(onSamples: @escaping ([Float]) -> Void, onError: @escaping (String) -> Void) {
        self.onSamples = onSamples
        self.onError = onError
        // First time: macOS shows its own prompt and says no for now; the user allows it in
        // System Settings and starts again.
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            onError(SystemAudioCapture.permissionText); return
        }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            guard let self = self, !self.stopped else { return }
            guard let display = content?.displays.first else {
                onError(error.map(SystemAudioCapture.text) ?? "NO DISPLAY TO CAPTURE AUDIO FROM"); return
            }
            // A music player open (Spotify, a browser, Music...) = hear only the players, so a mic
            // monitored through Artemis or a DAW never mixes into the key. None open = everything.
            let players = (content?.applications ?? []).filter { SystemAudioCapture.isPlayer($0.bundleIdentifier) }
            LiveProcess.log("system audio: " + (players.isEmpty ? "all apps" : "players only: " + players.map { $0.bundleIdentifier }.joined(separator: ", ")))
            let filter = players.isEmpty
                ? SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                : SCContentFilter(display: display, including: players, exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.capturesAudio = true
            cfg.excludesCurrentProcessAudio = true
            cfg.sampleRate = SystemAudioCapture.captureRate
            cfg.channelCount = 2
            cfg.width = 2
            cfg.height = 2
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            cfg.showsCursor = false
            let s = SCStream(filter: filter, configuration: cfg, delegate: self)
            do {
                try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.queue)
                // a screen output too, or SCK logs a dropped frame every second
                try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
            } catch {
                onError(SystemAudioCapture.text(error)); return
            }
            s.startCapture { err in
                if let err = err { onError(SystemAudioCapture.text(err)) }
            }
            self.stream = s
        }
    }

    func stop() {
        stopped = true
        stream?.stopCapture { _ in }
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sb.isValid, let emit = onSamples else { return }
        guard let fd = CMSampleBufferGetFormatDescription(sb),
              let rate = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee.mSampleRate, rate > 0
        else { return }
        if rate != resamplerRate { resampler = Resampler(from: rate); resamplerRate = rate }
        guard let r = resampler else { return }
        let mono: [Float]? = try? sb.withAudioBufferList { list, _ in SystemAudioCapture.mono(list) }
        if let m = mono, !m.isEmpty { emit(r.process(m)) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard !stopped else { return }
        LiveProcess.log("system audio stopped: \(error)")
        onError?(SystemAudioCapture.text(error))
    }

    /// Apps that play songs (bundle id prefixes, so a browser's helper processes count too).
    static let playerIDs = ["com.spotify.client", "com.apple.Music", "com.apple.Safari", "com.apple.WebKit",
                            "com.brave.Browser", "com.google.Chrome", "company.thebrowser", "org.mozilla.firefox",
                            "com.microsoft.edgemac", "com.operasoftware", "com.vivaldi", "com.apple.TV",
                            "com.apple.QuickTimePlayerX", "org.videolan.vlc", "com.colliderli.iina",
                            "com.tidal.desktop", "com.amazon.music", "com.soundcloud", "com.deezer",
                            "com.google.android.youtube", "com.apple.podcasts"]

    static func isPlayer(_ bundleID: String) -> Bool {
        playerIDs.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
    }

    /// A rate SCK actually supports (8000, 16000, 24000, 48000).
    static let captureRate = 48000

    /// Float32 buffers (one per channel, or one interleaved) averaged to mono.
    static func mono(_ list: UnsafeMutableAudioBufferListPointer) -> [Float] {
        var chans: [UnsafeBufferPointer<Float>] = []
        for b in list {
            guard let p = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let ch = max(Int(b.mNumberChannels), 1)
            let frames = Int(b.mDataByteSize) / MemoryLayout<Float>.size / ch
            if ch == 1 {
                chans.append(UnsafeBufferPointer(start: p, count: frames))
            } else {
                let all = UnsafeBufferPointer(start: p, count: frames * ch)
                return (0..<frames).map { f in (0..<ch).reduce(Float(0)) { $0 + all[f * ch + $1] } / Float(ch) }
            }
        }
        return PCM.mono(chans, channel: 0)
    }

    static func text(_ error: Error) -> String {
        let e = error as NSError
        if e.domain == SCStreamErrorDomain && e.code == SCStreamError.userDeclined.rawValue { return permissionText }
        return "SYSTEM AUDIO STOPPED: \(e.localizedDescription.uppercased())"
    }
}
