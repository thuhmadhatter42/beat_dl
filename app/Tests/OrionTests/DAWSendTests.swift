import XCTest
@testable import Orion

final class DAWSendTests: XCTestCase {
    private func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
    private func data(_ hex: String) -> Data {
        var d = Data(), s = Substring(hex)
        while !s.isEmpty { d.append(UInt8(s.prefix(2), radix: 16)!); s = s.dropFirst(2) }
        return d
    }

    // MARK: payload, detection

    func testParseKey() {
        XCTAssertEqual(SendPayload.parseKey("Cm")?.pc, 0); XCTAssertEqual(SendPayload.parseKey("Cm")?.minor, true)
        XCTAssertEqual(SendPayload.parseKey("F#")?.pc, 6); XCTAssertEqual(SendPayload.parseKey("F#")?.minor, false)
        XCTAssertEqual(SendPayload.parseKey("Ebm")?.pc, 3)
        XCTAssertEqual(SendPayload.parseKey("Cb")?.pc, 11)
        XCTAssertEqual(SendPayload.parseKey("B♭")?.pc, 10)
        XCTAssertNil(SendPayload.parseKey("H"))
        XCTAssertNil(SendPayload.parseKey(""))
    }

    func testPayloadFromResultUsesDecimalBPM() {
        let r = Result(file: URL(fileURLWithPath: "/x/beat.wav"), name: "beat.wav", bpm: "141", keys: [("Cm", 80), ("Eb", 10)], bpmExact: 140.82)
        let p = SendPayload(r)
        XCTAssertEqual(p.bpm, 140.82)
        XCTAssertEqual(p.key, "Cm")
        XCTAssertEqual(p.trackName, "beat")
        XCTAssertEqual(p.text, "140.82 BPM · C minor")
        XCTAssertNil(SendPayload(bpm: 0, key: nil).bpm)
    }

    func testDAWDetection() {
        XCTAssertEqual(DAW.from(bundleID: "com.avid.ProTools", name: "Pro Tools"), .proTools)
        XCTAssertEqual(DAW.from(bundleID: "com.ableton.live", name: "Live"), .ableton)
        XCTAssertEqual(DAW.from(bundleID: "com.apple.logic10", name: nil), .logic)
        XCTAssertEqual(DAW.from(bundleID: "com.steinberg.cubase14", name: nil), .cubase)
        XCTAssertEqual(DAW.from(bundleID: nil, name: "Studio One 6"), .studioOne)
        XCTAssertEqual(DAW.from(bundleID: "com.example.x", name: "REAPER"), .reaper)
        XCTAssertNil(DAW.from(bundleID: "com.apple.Safari", name: "Safari"))
        XCTAssertNil(DAW.from(bundleID: nil, name: "Liveliness"))
    }

    func testPickTarget() {
        XCTAssertEqual(DAWWatcher.pick(last: .ableton, running: [.proTools, .ableton]), .ableton)
        XCTAssertEqual(DAWWatcher.pick(last: .bitwig, running: [.proTools, .ableton]), .proTools)
        XCTAssertNil(DAWWatcher.pick(last: .bitwig, running: []))
    }

    // MARK: OSC

    func testOSCEncodeNoArgs() {
        XCTAssertEqual(hex(OSC.encode(OSC.Message("/beatkey/ping"))),
                       hex(Data("/beatkey/ping".utf8)) + "000000" + "2c000000")
    }

    func testOSCEncodeArgs() {
        let d = OSC.encode(OSC.Message("/a", [.float(140.82), .int(-1), .string("Minor")]))
        // "/a\0\0" ",fis\0\0\0\0" float int "Minor\0\0\0"
        XCTAssertEqual(hex(d), "2f610000" + "2c666973" + "00000000"
                       + String(format: "%08x", Float(140.82).bitPattern) + "ffffffff" + hex(Data("Minor".utf8)) + "000000")
        XCTAssertEqual(OSC.decode(d), OSC.Message("/a", [.float(140.82), .int(-1), .string("Minor")]))
    }

    func testOSCDecodeRejectsGarbage() {
        XCTAssertNil(OSC.decode(Data([1, 2, 3])))
        XCTAssertNil(OSC.decode(OSC.encode(OSC.Message("/a", [.int(1)])).prefix(9)))
        XCTAssertEqual(OSC.decode(Data("/x\0\0".utf8)), OSC.Message("/x"))
    }

    // MARK: UDP + drivers against fake scripts

    /// Answers one datagram on `port` with `reply(request)`, sent back to the sender (or to
    /// `replyTo` when the real script answers a fixed port).
    private func fakeServer(port: UInt16, replyTo: UInt16? = nil, count: Int = 1, _ reply: @escaping (OSC.Message) -> OSC.Message) -> XCTestExpectation {
        let done = expectation(description: "server \(port)")
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        var a = UDP.loopback(port)
        let b = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        XCTAssertEqual(b, 0)
        Thread.detachNewThread {
            for _ in 0..<count {
                var buf = [UInt8](repeating: 0, count: 2048)
                var from = sockaddr_in(), len = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &from) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &len) } }
                guard n > 0, let m = OSC.decode(Data(buf[0..<n])) else { break }
                let out = OSC.encode(reply(m))
                if let r = replyTo { from = UDP.loopback(r) }
                _ = out.withUnsafeBytes { o in withUnsafePointer(to: &from) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, o.baseAddress, o.count, 0, $0, len) } } }
            }
            close(fd)
            done.fulfill()
        }
        return done
    }

    func testAbletonSetMessage() {
        XCTAssertEqual(AbletonDriver.setMessage(SendPayload(bpm: 140.82, key: "Cm")),
                       OSC.Message("/beatkey/set", [.float(140.82), .int(0), .string("Minor")]))
        XCTAssertEqual(AbletonDriver.setMessage(SendPayload(bpm: nil, key: "F#")),
                       OSC.Message("/beatkey/set", [.float(0), .int(6), .string("Major")]))
        XCTAssertEqual(AbletonDriver.setMessage(SendPayload(bpm: 90, key: nil)),
                       OSC.Message("/beatkey/set", [.float(90), .int(-1), .string("")]))
    }

    func testAbletonSendEndToEnd() throws {
        let port: UInt16 = 47_041
        var seen: [OSC.Message] = []
        let done = fakeServer(port: port, count: 2) { m in
            seen.append(m)
            if m.address == "/beatkey/ping" { return OSC.Message("/beatkey/pong", [.string("1"), .int(1), .int(12)]) }
            return OSC.Message("/beatkey/ok", [m.args[0], m.args[1], m.args[2]])
        }
        let line = try AbletonDriver(port: port).send(SendPayload(bpm: 140.82, key: "Ebm"))
        wait(for: [done], timeout: 3)
        XCTAssertEqual(line, "Tempo 140.82 · Key Eb Minor.")
        XCTAssertEqual(seen.map(\.address), ["/beatkey/ping", "/beatkey/set"])
    }

    func testAbletonLive11ReportsTempoOnly() {
        let line = AbletonDriver.report(SendPayload(bpm: 120, key: "Cm"),
                                        reply: OSC.Message("/beatkey/ok", [.float(120), .int(-1), .string("")]),
                                        pong: .init(version: "1", hasScale: false, liveMajor: 11))
        XCTAssertEqual(line, "Tempo 120.00 · key not sent: Live 11 has no song key (Live 12 does).")
    }

    func testAbletonNoScriptAsksToInstall() throws {
        let lib = FileManager.default.temporaryDirectory.appendingPathComponent("bk-ul-\(UUID().uuidString)")
        let d = AbletonDriver(port: 47_049, userLibrary: lib)   // nothing listens there
        XCTAssertThrowsError(try d.send(SendPayload(bpm: 120, key: nil))) { e in
            let s = e as? SetupNeeded
            XCTAssertEqual(s?.button, "Install")
            XCTAssertTrue(s?.message.contains("Remote Scripts/BeatKey") ?? false)
        }
    }

    func testAbletonSelection() throws {
        let port: UInt16 = 47_042
        let done = fakeServer(port: port, count: 2) { m in
            m.address == "/beatkey/ping" ? OSC.Message("/beatkey/pong", [.string("1"), .int(1), .int(12)])
                                         : OSC.Message("/beatkey/selection", [.string("/Users/x/Samples/loop.wav")])
        }
        XCTAssertEqual(try AbletonDriver(port: port).selectionAudio(), [URL(fileURLWithPath: "/Users/x/Samples/loop.wav")])
        wait(for: [done], timeout: 3)
    }

    func testBitwigSendAnswersFixedPort() throws {
        let done = fakeServer(port: 47_043, replyTo: 47_044) { m in OSC.Message("/beatkey/ok", [m.args[0]]) }
        let line = try BitwigDriver(port: 47_043, replyPort: 47_044).send(SendPayload(bpm: 128.5, key: "A"))
        wait(for: [done], timeout: 3)
        XCTAssertEqual(line, "Tempo 128.50 · key not sent (Bitwig has no project key).")
        XCTAssertEqual(BitwigDriver.setMessage(128.5), OSC.Message("/beatkey/set", [.float(128.5)]))
    }

    // MARK: REAPER mailbox

    func testReaperCodec() {
        XCTAssertEqual(ReaperDriver.encode(["id": "7", "cmd": "set", "bpm": "140.8200"]), "bpm=140.8200\ncmd=set\nid=7\n")
        XCTAssertEqual(ReaperDriver.decode("id=7\nok=1\nfile=/a/b=c.wav\n"), ["id": "7", "ok": "1", "file": "/a/b=c.wav"])
    }

    func testReaperSendThroughMailbox() throws {
        let box = FileManager.default.temporaryDirectory.appendingPathComponent("bk-reaper-\(UUID().uuidString)")
        let d = ReaperDriver(mailbox: box, resourcePath: box, timeout: 3)
        let answered = expectation(description: "reaper")
        Thread.detachNewThread {   // stands in for the Lua listener
            let req = box.appendingPathComponent("request.txt")
            for _ in 0..<100 {
                if let t = try? String(contentsOf: req, encoding: .utf8) {
                    let r = ReaperDriver.decode(t)
                    try? DAWFiles.write(ReaperDriver.encode(["id": r["id"]!, "ok": "1", "bpm": r["bpm"]!]), to: box.appendingPathComponent("reply.txt"))
                    answered.fulfill(); return
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        XCTAssertEqual(try d.send(SendPayload(bpm: 93.25, key: "Gm")), "Tempo 93.25 · key not sent (REAPER has no project key).")
        wait(for: [answered], timeout: 3)
    }

    func testReaperSilentAsksToInstall() {
        let box = FileManager.default.temporaryDirectory.appendingPathComponent("bk-reaper-\(UUID().uuidString)")
        let d = ReaperDriver(mailbox: box, resourcePath: box, timeout: 0.2)
        XCTAssertThrowsError(try d.send(SendPayload(bpm: 100, key: nil))) { e in
            XCTAssertEqual((e as? SetupNeeded)?.button, "Install")
        }
    }

    // MARK: MIDI hand-off

    func testMidiFileDriverWritesTheExportBytes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bk-midi-\(UUID().uuidString)")
        var revealed: URL?
        let d = MidiFileDriver(daw: .logic, folder: dir, reveal: { revealed = $0 })
        let p = SendPayload(bpm: 140.82, key: "Cm", trackName: "beat")
        let line = try d.send(p)
        let url = dir.appendingPathComponent("beat (140.82 BPM Cm).mid")
        XCTAssertEqual(revealed, url)
        XCTAssertEqual(try Data(contentsOf: url), MidiExport.data(bpm: 140.82, key: "Cm", trackName: "beat"))
        XCTAssertTrue(line.contains("File › Open"))
        for daw in DAW.allCases { XCTAssertFalse(MidiFileDriver.howTo(daw).isEmpty) }
    }

    // MARK: PTSL wire format (expected bytes from the official PTSL_pb2 encoder)

    func testPTSLRequestMatchesOfficialEncoder() {
        XCTAssertEqual(hex(PTSLProto.request(command: 70, sessionID: "", bodyJSON: #"{"a":1}"#)),
                       "0a07104618ea0f280412077b2261223a317d")
        XCTAssertEqual(hex(PTSLProto.request(command: 10, sessionID: "abc-123", bodyJSON: "")),
                       "0a10100a18ea0f22076162632d3132332804")
    }

    func testPTSLResponseDecode() {
        let ok = PTSLProto.response(data("0a0d0a02743110461803206428ea0f12147b2273657373696f6e5f6964223a22532d31227d"))
        XCTAssertEqual(ok?.status, 3)
        XCTAssertEqual(ok?.body, #"{"session_id":"S-1"}"#)
        let failed = PTSLProto.response(data("0a04100a18041a5b7b226572726f7273223a5b7b22636f6d6d616e645f6572726f725f74797065223a2250545f4e6f53656c656374696f6e222c22636f6d6d616e645f6572726f725f6d657373616765223a224e6f2073656c656374696f6e227d5d7d"))
        XCTAssertEqual(failed?.status, 4)
        XCTAssertEqual(PTSLClient.errorText(failed!.error), "No selection")
        XCTAssertNil(PTSLProto.response(Data([0x0a, 0x09, 0x01])))
    }

    func testHPACKIntegers() {   // RFC 7541 C.1
        XCTAssertEqual(H2.integer(10, prefixBits: 5), [10])
        XCTAssertEqual(H2.integer(1337, prefixBits: 5), [31, 154, 10])
        XCTAssertEqual(H2.integer(42, prefixBits: 8), [42])
        XCTAssertEqual(H2.literal("te", "trailers"), [0x00, 2] + Array("te".utf8) + [8] + Array("trailers".utf8))
    }

    func testH2FrameRoundTrip() {
        let f = H2.frame(1, flags: H2.endHeaders, stream: 3, Data([9, 8, 7]))
        XCTAssertEqual(hex(f), "000003010400000003090807")
        let (p, used) = H2.parse(f + Data([0xff]))!
        XCTAssertEqual(used, 12)
        XCTAssertEqual(p, H2.Frame(type: 1, flags: 4, stream: 3, payload: Data([9, 8, 7])))
        XCTAssertNil(H2.parse(f.prefix(10)))
        XCTAssertEqual(hex(H2.grpcMessage(Data([1, 2]))), "00000000020102")
        XCTAssertEqual(H2.unwrapGRPC(H2.grpcMessage(Data([1, 2]))), Data([1, 2]))
        let padded = H2.Frame(type: 0, flags: H2.padded, stream: 1, payload: Data([2, 5, 6, 0, 0]))
        XCTAssertEqual(H2.content(padded), Data([5, 6]))
    }

    /// A fake PTSL server speaking just enough HTTP/2: checks the preface and the request path,
    /// answers each stream with SETTINGS, HEADERS, DATA, trailers.
    func testPTSLClientAgainstFakeServer() throws {
        let port: UInt16 = 47_416
        let lfd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        var yes: Int32 = 1
        setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var a = UDP.loopback(port)
        XCTAssertEqual(withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(lfd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }, 0)
        listen(lfd, 1)
        var commands: [Int] = [], sessions: [String] = [], paths: [Bool] = []
        let done = expectation(description: "ptsl")
        Thread.detachNewThread {
            let fd = accept(lfd, nil, nil)
            defer { close(fd); close(lfd); done.fulfill() }
            var buf = Data()
            func fill() -> Bool {
                var c = [UInt8](repeating: 0, count: 4096)
                let n = recv(fd, &c, c.count, 0)
                if n <= 0 { return false }
                buf += c[0..<n]; return true
            }
            func put(_ d: Data) { _ = d.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) } }
            while buf.count < 24 { guard fill() else { return } }
            guard buf.prefix(24) == H2.preface else { return }
            buf.removeFirst(24)
            put(H2.frame(4, Data([0, 3, 0, 0, 0, 100])))   // server SETTINGS
            var body = Data()
            for _ in 0..<2 {
                while true {
                    guard let (f, used) = H2.parse(buf) else { guard fill() else { return }; continue }
                    buf.removeFirst(used)
                    if f.type == 1 { paths.append(String(decoding: f.payload, as: UTF8.self).contains("/ptsl.PTSL/SendGrpcRequest")) }
                    if f.type == 0 {
                        body += f.payload
                        if f.flags & H2.endStream != 0 {
                            let msg = H2.unwrapGRPC(body)!; body = Data()
                            let top = PTSLProto.fields(msg)!
                            if case .bytes(let h)? = top.first(where: { $0.0 == 1 })?.1 {
                                for (n, v) in PTSLProto.fields(h)! {
                                    if n == 2, case .varint(let c) = v { commands.append(Int(c)) }
                                    if n == 4, case .bytes(let s) = v { sessions.append(String(decoding: s, as: UTF8.self)) }
                                }
                            }
                            let json = commands.last == 70 ? #"{"session_id":"S-1"}"# : #"{"sample_rate":"SR_48000"}"#
                            let resp = PTSLProto.bytesField(1, PTSLProto.varintField(3, 3)) + PTSLProto.bytesField(2, Data(json.utf8))
                            put(H2.frame(1, flags: H2.endHeaders, stream: f.stream, Data(H2.literal(":status", "200"))))
                            put(H2.frame(0, stream: f.stream, H2.grpcMessage(resp)))
                            put(H2.frame(1, flags: H2.endHeaders | H2.endStream, stream: f.stream, Data(H2.literal("grpc-status", "0"))))
                            break
                        }
                    }
                }
            }
        }
        let c = try PTSLClient(port: port, timeout: 5)
        try c.register()
        XCTAssertEqual(c.sessionID, "S-1")
        XCTAssertEqual(try c.call(.getSessionSampleRate)["sample_rate"] as? String, "SR_48000")
        wait(for: [done], timeout: 5)
        XCTAssertEqual(commands, [70, 35])
        XCTAssertEqual(sessions, ["S-1"])   // register carries none, the next call carries the id
        XCTAssertEqual(paths, [true, true])
    }

    func testPTSLNotRunning() {
        XCTAssertThrowsError(try PTSLClient(port: 47_499)) { e in
            guard case PTSLClient.Failure.notRunning? = e as? PTSLClient.Failure else { return XCTFail("\(e)") }
        }
    }

    func testProToolsHelpers() {
        XCTAssertEqual(ProToolsDriver.parseRate("SR_48000"), 48000)
        XCTAssertEqual(ProToolsDriver.bpm(beatSamples: 24000, sampleRate: 48000), 120, accuracy: 1e-9)
        let body = ProToolsDriver.exportBody(URL(fileURLWithPath: "/tmp/x"))
        XCTAssertEqual(body["file_path"] as? String, "/tmp/x/")
        XCTAssertEqual(body["file_type"] as? String, "EFType_WAV")
        XCTAssertEqual(body["format"] as? String, "EFormat_Interleaved")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bk-pt-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for n in ["b.wav", "a.aif", "notes.txt"] { FileManager.default.createFile(atPath: dir.appendingPathComponent(n).path, contents: Data()) }
        XCTAssertEqual(ProToolsDriver.audioFiles(in: dir).map(\.lastPathComponent), ["a.aif", "b.wav"])
    }
}
