import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import ScreenCaptureKit

/// Everything the Mac plays, through ScreenCaptureKit's audio (macOS 13+): the main display's
/// stream with audio on and the picture shrunk to 2 x 2 px at one frame a second (SCK has no
/// audio-only filter). Beat Key's own sound is left out. Needs the Screen (& System Audio)
/// Recording permission; nothing is saved.
@available(macOS 13.0, *)
final class SystemAudioCapture: NSObject, FilteredCapture, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    /// Told which filter each (re)opened stream uses: players only, or all apps.
    var onFilter: ((CaptureFilter) -> Void)?
    /// The silence guard widened this Listen to every app (queue only): no exclusions from now on.
    private var allApps = false
    private let queue = DispatchQueue(label: "com.jshriver.orion.system-audio")
    private var onSamples: (([Float]) -> Void)?
    private var onError: ((String) -> Void)?
    private var stopped = false
    /// SCK only delivers 8/16/24/48 kHz (asking for 44.1 kHz silently gets 48 kHz), so each
    /// buffer's real rate is read and resampled to the analyzer's 44.1 kHz. Unresampled 48 kHz
    /// audio read as 44.1 kHz puts every key ~1.5 semitones flat and every tempo 8 % slow.
    private var resampler: Resampler?
    private var resamplerRate: Double = 0
    /// SCK drops the stream when the display goes away (display sleep, lock, lid, monitor
    /// unplugged: error -3815 "Failed to find any displays or windows to capture"). That is not
    /// the user's problem, so Beat Key quietly reopens it: right away on screen wake, else after
    /// 2, 5, 10, then every 30 s. Only a permission refusal reaches the screen.
    private var retries = 0
    private var retryWork: DispatchWorkItem?
    private var wakeObserver: NSObjectProtocol?

    /// macOS 15 renamed the privacy pane.
    static var permissionText: String {
        let pane: String
        if #available(macOS 15.0, *) { pane = "SCREEN & SYSTEM AUDIO RECORDING" } else { pane = "SCREEN RECORDING" }
        return "ALLOW \(Brand.wordmark) IN SYSTEM SETTINGS › PRIVACY & SECURITY › \(pane)"
    }

    func start(onSamples: @escaping ([Float]) -> Void, onError: @escaping (String) -> Void) {
        self.onSamples = onSamples
        self.onError = onError
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.reopen(now: true, why: "screen woke") }
        }
        begin()
    }

    private func begin() {
        guard !stopped, let onError = onError else { return }
        // First time: macOS shows its own prompt and says no for now; the user allows it in
        // System Settings and starts again.
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            onError(SystemAudioCapture.permissionText); return
        }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            guard let self = self, !self.stopped else { return }
            guard let display = content?.displays.first else {
                AppLog.log("system audio: no display yet (\(error.map { "\($0)" } ?? "none")), retrying")
                self.queue.async { self.reopen(now: false, why: "no display") }
                return
            }
            // A music player open (Spotify, a browser, Music...) = hear only the players, so a mic
            // monitored through Artemis or a DAW never mixes into the key. None open = everything.
            // Done by LEAVING OUT every listed non-player, never by including the players: a
            // browser plays from helper processes SCK may not list (Studio D 2026-11-09: Chrome
            // listed alone, its audio helper absent, the stream heard silence).
            // The silence guard (ListenLog.swift) sets allApps when the players stayed silent.
            let apps = content?.applications ?? []
            let players = self.allApps ? [] : apps.filter { SystemAudioCapture.isPlayer($0.bundleIdentifier) }
            let others = players.isEmpty ? [] : apps.filter { !SystemAudioCapture.isPlayer($0.bundleIdentifier) }
            AppLog.log("system audio: " + (players.isEmpty ? "all apps\(self.allApps ? " (widened: no signal from players)" : "")"
                : "players open (\(players.map { $0.bundleIdentifier }.joined(separator: ", "))); leaving out \(others.count) other apps: "
                  + others.map { $0.bundleIdentifier }.filter { !$0.isEmpty }.prefix(12).joined(separator: ", ")))
            self.onFilter?(players.isEmpty ? .allApps : .playersOnly(players.map { $0.bundleIdentifier }))
            let filter = SCContentFilter(display: display, excludingApplications: others, exceptingWindows: [])
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
            s.startCapture { [weak self] err in
                guard let err = err else { return }
                if SystemAudioCapture.isPermission(err) { onError(SystemAudioCapture.text(err)); return }
                AppLog.log("system audio: start failed (\(err)), retrying")
                self?.queue.async { self?.reopen(now: false, why: "start failed") }
            }
            self.stream = s
        }
    }

    /// The silence guard: the players gave nothing for 5 s, so reopen hearing every app.
    func hearAllApps() {
        queue.async { [weak self] in
            guard let self = self, !self.stopped, !self.allApps else { return }
            self.allApps = true
            AppLog.log("system audio: reopening with all apps (no exclusions)")
            self.retryWork?.cancel()
            self.stream?.stopCapture { err in if let e = err { AppLog.log("system audio: stop before widening: \(e)") } }
            self.stream = nil
            self.begin()
        }
    }

    func stop() {
        stopped = true
        retryWork?.cancel()
        if let w = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(w); wakeObserver = nil }
        stream?.stopCapture { _ in }
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sb.isValid, let emit = onSamples else { return }
        if retries > 0 { AppLog.log("system audio: back after \(retries) retr\(retries == 1 ? "y" : "ies")"); retries = 0 }
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
        AppLog.log("system audio stopped: \(error)")
        if SystemAudioCapture.isPermission(error) { onError?(SystemAudioCapture.text(error)); return }
        queue.async { self.reopen(now: false, why: "stream stopped") }
    }

    /// Runs on `queue`. Drops the dead stream and opens a new one, now or after a backoff.
    private func reopen(now: Bool, why: String) {
        guard !stopped else { return }
        retryWork?.cancel()
        stream?.stopCapture { _ in }
        stream = nil
        let delays: [Double] = [2, 5, 10]
        let wait = now ? 0.5 : (retries < delays.count ? delays[retries] : 30)
        retries += 1
        AppLog.log("system audio: reopening in \(wait) s (\(why), try \(retries))")
        let w = DispatchWorkItem { [weak self] in self?.begin() }
        retryWork = w
        queue.asyncAfter(deadline: .now() + wait, execute: w)
    }

    static func isPermission(_ error: Error) -> Bool {
        let e = error as NSError
        return e.domain == SCStreamErrorDomain && e.code == SCStreamError.userDeclined.rawValue
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
