import AVFoundation
import AudioToolbox

/// Beat Key's one sound: the macOS General MIDI piano (the system's own DLS bank, no bundled
/// samples) through AVAudioUnitSampler. Play to find the key sounds single notes, the chord
/// strip whole chords. Output only, on its own AVAudioEngine: Listen's capture is a separate
/// engine (inputs) or ScreenCaptureKit with excludesCurrentProcessAudio (System Audio), so these
/// notes never reach the analyzer. The engine starts on the first note and stops after a few
/// idle seconds. Main thread only.
final class NoteSynth {
    static let shared = NoteSynth()

    /// The GM bank every Mac ships (CoreAudio's own).
    static let bankURL = URL(fileURLWithPath:
        "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
    /// One played key of Play to find the key.
    static let noteSeconds = 0.45
    static let volume: Float = 0.7
    static let idleSeconds = 5.0

    private var engine: AVAudioEngine?
    private var sampler: AVAudioUnitSampler?
    private var sounding: [UInt8] = []
    private var release: DispatchWorkItem?
    private var idle: DispatchWorkItem?
    private var failedOnce = false
    private var bankFailedOnce = false

    func play(midi: Int) { play([midi], seconds: NoteSynth.noteSeconds) }

    /// Sounds `notes` together for `seconds`; whatever was sounding stops first.
    func play(_ notes: [Int], seconds: Double, velocity: UInt8 = 90) {
        guard let s = ensureRunning() else { return }
        stopNotes()
        sounding = notes.map { UInt8(clamping: max(0, min(127, $0))) }
        for n in sounding { s.startNote(n, withVelocity: min(velocity, 127), onChannel: 0) }
        let rel = DispatchWorkItem { [weak self] in self?.stopNotes() }
        release = rel
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: rel)
        idle?.cancel()
        let stop = DispatchWorkItem { [weak self] in self?.stop() }
        idle = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + NoteSynth.idleSeconds, execute: stop)
    }

    private func stopNotes() {
        release?.cancel(); release = nil
        for n in sounding { sampler?.stopNote(n, onChannel: 0) }
        sounding = []
    }

    private func ensureRunning() -> AVAudioUnitSampler? {
        if let e = engine, e.isRunning, let s = sampler { return s }
        let e = AVAudioEngine()
        let s = AVAudioUnitSampler()
        e.attach(s)
        e.connect(s, to: e.mainMixerNode, format: nil)
        e.mainMixerNode.outputVolume = NoteSynth.volume
        do {
            try s.loadSoundBankInstrument(at: NoteSynth.bankURL, program: 0,
                                          bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                          bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        } catch {
            // the sampler's built-in tone still plays; say so once
            if !bankFailedOnce { AppLog.log("note synth: GM piano would not load (\(error.localizedDescription)), plain tone") }
            bankFailedOnce = true
        }
        do {
            try e.start()
        } catch {
            if !failedOnce { AppLog.log("note synth: audio engine would not start: \(error.localizedDescription)") }
            failedOnce = true
            return nil
        }
        engine = e; sampler = s
        return s
    }

    func stop() {
        idle?.cancel(); idle = nil
        stopNotes()
        engine?.stop()
        engine = nil; sampler = nil
    }
}
