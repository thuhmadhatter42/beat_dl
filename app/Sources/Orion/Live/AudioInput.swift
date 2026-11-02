import AVFoundation
import CoreAudio
import Foundation

/// An audio input device (Core Audio), for Settings › Listen To.
struct InputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let channels: Int

    /// Every device with at least one input channel.
    static func all() -> [InputDevice] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            let ch = inputChannels(id)
            guard ch > 0, let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return InputDevice(id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? uid, channels: ch)
        }
    }

    static func deviceID(uid: String) -> AudioDeviceID? { all().first { $0.uid == uid }?.id }

    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }
}

/// Mono mixing and resampling to the analyzer's 44.1 kHz.
enum PCM {
    /// Channel `channel` (1-based) of a deinterleaved buffer, or all channels averaged (0, or a
    /// channel the device doesn't have).
    static func mono(_ channels: [UnsafeBufferPointer<Float>], channel: Int) -> [Float] {
        guard let first = channels.first else { return [] }
        if channel >= 1 && channel <= channels.count { return Array(channels[channel - 1]) }
        if channels.count == 1 { return Array(first) }
        let n = channels.map(\.count).min() ?? 0
        var out = [Float](repeating: 0, count: n)
        let scale = 1 / Float(channels.count)
        for c in channels { for i in 0..<n { out[i] += c[i] * scale } }
        return out
    }

    static func mono(_ buffer: AVAudioPCMBuffer, channel: Int) -> [Float] {
        guard let data = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        let fmt = buffer.format
        if fmt.isInterleaved {
            let ch = Int(fmt.channelCount)
            let all = UnsafeBufferPointer(start: data[0], count: frames * ch)
            if channel >= 1 && channel <= ch { return stride(from: channel - 1, to: all.count, by: ch).map { all[$0] } }
            return (0..<frames).map { f in (0..<ch).reduce(Float(0)) { $0 + all[f * ch + $1] } / Float(ch) }
        }
        let chans = (0..<Int(fmt.channelCount)).map { UnsafeBufferPointer(start: data[$0], count: frames) }
        return mono(chans, channel: channel)
    }
}

/// Mono float32 at any rate -> 44.1 kHz (AVAudioConverter keeps its filter state between calls,
/// so the pieces join without clicks). Pass-through when the rate already matches.
final class Resampler {
    private let converter: AVAudioConverter?
    private let inFormat: AVAudioFormat
    private let outFormat: AVAudioFormat

    init?(from rate: Double, to target: Double = Double(LiveProcess.sampleRate)) {
        guard let i = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let o = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: target, channels: 1, interleaved: false)
        else { return nil }
        inFormat = i; outFormat = o
        converter = rate == target ? nil : AVAudioConverter(from: i, to: o)
        if rate != target && converter == nil { return nil }
    }

    func process(_ samples: [Float]) -> [Float] {
        guard let conv = converter, !samples.isEmpty else { return samples }
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(samples.count)) else { return [] }
        inBuf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { inBuf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let cap = AVAudioFrameCount(Double(samples.count) * outFormat.sampleRate / inFormat.sampleRate) + 64
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) else { return [] }
        var fed = false
        var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return inBuf
        }
        guard err == nil, let d = outBuf.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: d[0], count: Int(outBuf.frameLength)))
    }
}

/// The mic or any input device (and one of its channels) through AVAudioEngine. Asks for
/// microphone access first (NSMicrophoneUsageDescription). Nothing is recorded: each tap buffer is
/// mixed to mono, resampled and handed on.
final class InputCapture: AudioCapture {
    let deviceUID: String?
    let channel: Int
    private let engine = AVAudioEngine()
    private var running = false

    static let deniedText = "ALLOW MICROPHONE ACCESS IN SYSTEM SETTINGS › PRIVACY & SECURITY › MICROPHONE"

    init(deviceUID: String?, channel: Int) {
        self.deviceUID = deviceUID
        self.channel = channel
    }

    func start(onSamples: @escaping ([Float]) -> Void, onError: @escaping (String) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            begin(onSamples, onError)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { ok ? self.begin(onSamples, onError) : onError(InputCapture.deniedText) }
            }
        default:
            onError(InputCapture.deniedText)
        }
    }

    private func begin(_ onSamples: @escaping ([Float]) -> Void, _ onError: @escaping (String) -> Void) {
        let input = engine.inputNode
        if let uid = deviceUID {
            guard var id = InputDevice.deviceID(uid: uid), let unit = input.audioUnit else {
                onError("THAT INPUT IS NOT CONNECTED · PICK ANOTHER IN SETTINGS"); return
            }
            let st = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard st == noErr else { onError("COULDN'T OPEN THAT INPUT (\(st))"); return }
        }
        let fmt = input.inputFormat(forBus: 0)
        guard fmt.channelCount > 0, fmt.sampleRate > 0, let resampler = Resampler(from: fmt.sampleRate) else {
            onError("NO AUDIO INPUT FOUND"); return
        }
        let ch = channel
        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { buf, _ in
            onSamples(resampler.process(PCM.mono(buf, channel: ch)))
        }
        engine.prepare()
        do {
            try engine.start()
            running = true
        } catch {
            input.removeTap(onBus: 0)
            onError("COULDN'T START THE INPUT: \(error.localizedDescription.uppercased())")
        }
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
