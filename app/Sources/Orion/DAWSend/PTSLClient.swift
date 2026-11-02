import Foundation

// Pro Tools Scripting Library (PTSL) without a gRPC dependency.
// PTSL is gRPC over cleartext HTTP/2 on 127.0.0.1:31416, one RPC that matters:
// ptsl.PTSL/SendGrpcRequest(Request) -> Response, where both carry JSON bodies
// (PTSL.proto from the PTSL SDK 2026.04). URLSession only speaks HTTP/2 over TLS, so the few
// frames a unary call needs are written here: RFC 9113 framing, RFC 7541 literal headers
// (no Huffman, no dynamic table), gRPC length-prefixed messages, and hand-encoded protobuf.

/// Protobuf wire encoding for the two PTSL messages Beat Key sends and the one it reads.
enum PTSLProto {
    /// `RequestHeader { command=2 (enum), version=3, session_id=4, version_minor=5, version_revision=6 }`
    /// inside `Request { header=1, request_body_json=2 }`.
    static func request(command: Int, sessionID: String, bodyJSON: String,
                        version: (Int, Int, Int) = PTSLClient.version) -> Data {
        // proto3: fields at their default (0, "") are left out, as the official encoder does
        var header = Data()
        for (n, v) in [(2, command), (3, version.0)] where v != 0 { header += varintField(n, UInt64(v)) }
        if !sessionID.isEmpty { header += bytesField(4, Data(sessionID.utf8)) }
        for (n, v) in [(5, version.1), (6, version.2)] where v != 0 { header += varintField(n, UInt64(v)) }
        var out = bytesField(1, header)
        if !bodyJSON.isEmpty { out += bytesField(2, Data(bodyJSON.utf8)) }
        return out
    }

    struct Response: Equatable {
        var status = 0          // ResponseHeader.status (TaskStatus): 3 Completed, 4 Failed
        var body = ""           // response_body_json
        var error = ""          // response_error_json
    }

    /// `Response { header=1 { status=3 }, response_body_json=2, response_error_json=3 }`.
    static func response(_ data: Data) -> Response? {
        guard let top = fields(data) else { return nil }
        var r = Response()
        for (n, v) in top {
            switch (n, v) {
            case (1, .bytes(let h)):
                for (hn, hv) in fields(h) ?? [] { if hn == 3, case .varint(let s) = hv { r.status = Int(s) } }
            case (2, .bytes(let b)): r.body = String(decoding: b, as: UTF8.self)
            case (3, .bytes(let b)): r.error = String(decoding: b, as: UTF8.self)
            default: break
            }
        }
        return r
    }

    enum Value: Equatable { case varint(UInt64), bytes(Data), fixed }

    /// Top-level fields of a message; nil = malformed.
    static func fields(_ data: Data) -> [(Int, Value)]? {
        let b = [UInt8](data)
        var i = 0, out: [(Int, Value)] = []
        func varint() -> UInt64? {
            var v: UInt64 = 0, shift: UInt64 = 0
            while i < b.count {
                let c = b[i]; i += 1
                v |= UInt64(c & 0x7F) << shift
                if c & 0x80 == 0 { return v }
                shift += 7
                if shift > 63 { return nil }
            }
            return nil
        }
        while i < b.count {
            guard let key = varint() else { return nil }
            let n = Int(key >> 3)
            switch key & 7 {
            case 0: guard let v = varint() else { return nil }; out.append((n, .varint(v)))
            case 2:
                guard let len = varint(), i + Int(len) <= b.count else { return nil }
                out.append((n, .bytes(Data(b[i..<i + Int(len)])))); i += Int(len)
            case 1: i += 8; out.append((n, .fixed))
            case 5: i += 4; out.append((n, .fixed))
            default: return nil
            }
            if i > b.count { return nil }
        }
        return out
    }

    static func varint(_ v: UInt64) -> Data {
        var v = v, out = Data()
        repeat {
            var byte = UInt8(v & 0x7F); v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }
    static func varintField(_ n: Int, _ v: UInt64) -> Data { varint(UInt64(n << 3)) + varint(v) }
    static func bytesField(_ n: Int, _ d: Data) -> Data { varint(UInt64(n << 3 | 2)) + varint(UInt64(d.count)) + d }
}

/// HTTP/2 frames and HPACK literals, only what a gRPC unary call over h2c needs.
enum H2 {
    static let preface = Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)
    enum Kind: UInt8 { case data = 0, headers = 1, rstStream = 3, settings = 4, ping = 6, goAway = 7, windowUpdate = 8, continuation = 9 }
    static let endStream: UInt8 = 0x1, ack: UInt8 = 0x1, endHeaders: UInt8 = 0x4, padded: UInt8 = 0x8, priority: UInt8 = 0x20

    struct Frame: Equatable {
        let type: UInt8
        let flags: UInt8
        let stream: UInt32
        let payload: Data
    }

    static func frame(_ type: UInt8, flags: UInt8 = 0, stream: UInt32 = 0, _ payload: Data = Data()) -> Data {
        let n = payload.count
        var out = Data([UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF), type, flags])
        out += [UInt8(stream >> 24 & 0x7F), UInt8(stream >> 16 & 0xFF), UInt8(stream >> 8 & 0xFF), UInt8(stream & 0xFF)]
        return out + payload
    }

    /// The frame at the start of `buf`, and how many bytes it took; nil = not all there yet.
    static func parse(_ buf: Data) -> (Frame, Int)? {
        let b = [UInt8](buf.prefix(9))
        guard b.count == 9 else { return nil }
        let len = Int(b[0]) << 16 | Int(b[1]) << 8 | Int(b[2])
        guard buf.count >= 9 + len else { return nil }
        let stream = (UInt32(b[5]) << 24 | UInt32(b[6]) << 16 | UInt32(b[7]) << 8 | UInt32(b[8])) & 0x7FFF_FFFF
        let start = buf.startIndex + 9
        return (Frame(type: b[3], flags: b[4], stream: stream, payload: Data(buf[start..<start + len])), 9 + len)
    }

    /// RFC 7541 §5.1 integer with an n-bit prefix; `first` holds the bits above the prefix.
    static func integer(_ v: Int, prefixBits: Int, first: UInt8 = 0) -> [UInt8] {
        let max = (1 << prefixBits) - 1
        if v < max { return [first | UInt8(v)] }
        var out: [UInt8] = [first | UInt8(max)], rest = v - max
        while rest >= 128 { out.append(UInt8(rest & 0x7F) | 0x80); rest >>= 7 }
        out.append(UInt8(rest))
        return out
    }

    /// "Literal Header Field without Indexing, New Name" (RFC 7541 §6.2.2), raw (no Huffman).
    static func literal(_ name: String, _ value: String) -> [UInt8] {
        let n = Array(name.utf8), v = Array(value.utf8)
        return [0x00] + integer(n.count, prefixBits: 7) + n + integer(v.count, prefixBits: 7) + v
    }

    static func grpcHeaders(path: String, authority: String) -> Data {
        Data([(":method", "POST"), (":scheme", "http"), (":path", path), (":authority", authority),
              ("content-type", "application/grpc"), ("te", "trailers")].flatMap { literal($0.0, $0.1) })
    }

    /// gRPC length-prefixed message: compressed flag 0, big-endian length, bytes.
    static func grpcMessage(_ d: Data) -> Data {
        let n = d.count
        return Data([0, UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)]) + d
    }

    static func unwrapGRPC(_ d: Data) -> Data? {
        let b = [UInt8](d)
        guard b.count >= 5, b[0] == 0 else { return nil }
        let n = Int(b[1]) << 24 | Int(b[2]) << 16 | Int(b[3]) << 8 | Int(b[4])
        guard b.count >= 5 + n else { return nil }
        return Data(b[5..<5 + n])
    }

    /// A DATA or HEADERS payload without its padding / priority prefix.
    static func content(_ f: Frame) -> Data {
        var p = [UInt8](f.payload), start = 0, end = p.count
        if f.flags & padded != 0, let pad = p.first { start = 1; end -= Int(pad) }
        if f.type == Kind.headers.rawValue, f.flags & priority != 0 { start += 5 }
        guard start <= end else { return Data() }
        p = Array(p[start..<end])
        return Data(p)
    }
}

/// One TCP connection to PTSL, any number of calls (one HTTP/2 stream each).
final class PTSLClient {
    static let port: UInt16 = 31416
    /// The PTSL API version this client speaks (the SDK the proto came from).
    static let version = (2026, 4, 0)
    static let path = "/ptsl.PTSL/SendGrpcRequest"

    enum Failure: Error, CustomStringConvertible {
        case notRunning, connection(String), protocolError(String), failed(command: String, error: String)
        var description: String {
            switch self {
            case .notRunning: return "Pro Tools is not answering on port 31416 (is it open, with a session?)."
            case .connection(let s): return "Lost the connection to Pro Tools: \(s)"
            case .protocolError(let s): return "Pro Tools sent something Beat Key could not read: \(s)"
            case .failed(let c, let e): return "Pro Tools refused \(c): \(PTSLClient.errorText(e))"
            }
        }
    }

    // PTSL CommandId values (PTSL.proto, SDK 2026.04).
    enum Command: Int {
        case exportClipsAsFiles = 10, getSessionSampleRate = 35, getSessionName = 42, getSessionPath = 43, getPTSLVersion = 55
        case registerConnection = 70, getTimeAsType = 118, getEditSelection = 131
        var name: String { "\(self)" }
    }

    private let fd: Int32
    private var nextStream: UInt32 = 1
    private var buffer = Data()
    private(set) var sessionID = ""

    init(port: UInt16 = PTSLClient.port, timeout: TimeInterval = 30) throws {
        fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw Failure.connection("socket") }
        var addr = UDP.loopback(port)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard ok == 0 else { close(fd); throw Failure.notRunning }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        try write(H2.preface + H2.frame(H2.Kind.settings.rawValue))
    }

    deinit { close(fd) }

    /// CId_RegisterConnection: every later call carries the session id it returns.
    func register(company: String = "Four Letter Records", app: String = "Beat Key") throws {
        let r = try call(.registerConnection, ["company_name": company, "application_name": app])
        guard let id = r["session_id"] as? String, !id.isEmpty else { throw Failure.protocolError("no session_id") }
        sessionID = id
    }

    /// One command; the parsed response body. Throws on a Failed status.
    @discardableResult
    func call(_ command: Command, _ body: [String: Any] = [:]) throws -> [String: Any] {
        let json = body.isEmpty ? "" : String(decoding: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), as: UTF8.self)
        let raw = try unary(PTSLProto.request(command: command.rawValue, sessionID: sessionID, bodyJSON: json))
        guard let r = PTSLProto.response(raw) else { throw Failure.protocolError("bad Response message") }
        if r.status == 4 || r.status == 7 { throw Failure.failed(command: command.name, error: r.error) }
        guard !r.body.isEmpty, let d = r.body.data(using: .utf8) else { return [:] }
        return ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any]) ?? [:]
    }

    /// PTSL's error JSON (`{"errors":[{"command_error_type":"…","command_error_message":"…"}]}`) as text.
    static func errorText(_ json: String) -> String {
        guard let d = json.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let errs = o["errors"] as? [[String: Any]], let e = errs.first else { return json.isEmpty ? "no reason given" : json }
        let msg = (e["command_error_message"] as? String) ?? ""
        let type = (e["command_error_type"] as? String) ?? ""
        return msg.isEmpty ? type : msg
    }

    // MARK: HTTP/2 plumbing

    private func unary(_ message: Data) throws -> Data {
        let stream = nextStream; nextStream += 2
        try write(H2.frame(H2.Kind.headers.rawValue, flags: H2.endHeaders, stream: stream,
                           H2.grpcHeaders(path: PTSLClient.path, authority: "127.0.0.1:\(PTSLClient.port)")))
        let body = H2.grpcMessage(message)
        var off = 0
        repeat {   // 16 384 = the default SETTINGS_MAX_FRAME_SIZE
            let chunk = body.subdata(in: off..<min(off + 16_384, body.count)); off += chunk.count
            try write(H2.frame(H2.Kind.data.rawValue, flags: off >= body.count ? H2.endStream : 0, stream: stream, chunk))
        } while off < body.count
        var data = Data()
        while true {
            let f = try readFrame()
            switch H2.Kind(rawValue: f.type) {
            case .settings: if f.flags & H2.ack == 0 { try write(H2.frame(H2.Kind.settings.rawValue, flags: H2.ack)) }
            case .ping: if f.flags & H2.ack == 0 { try write(H2.frame(H2.Kind.ping.rawValue, flags: H2.ack, f.payload)) }
            case .goAway: throw Failure.connection("Pro Tools closed the connection")
            case .rstStream where f.stream == stream: throw Failure.connection("Pro Tools reset the request")
            case .data where f.stream == stream:
                let c = H2.content(f); data += c
                if !f.payload.isEmpty {   // give the window back so long replies keep coming
                    let n = UInt32(f.payload.count)
                    let inc = Data([UInt8(n >> 24), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)])
                    try write(H2.frame(H2.Kind.windowUpdate.rawValue, stream: 0, inc) + H2.frame(H2.Kind.windowUpdate.rawValue, stream: stream, inc))
                }
                if f.flags & H2.endStream != 0 { return try finish(data) }
            case .headers where f.stream == stream:
                if f.flags & H2.endStream != 0 { return try finish(data) }
            default: break
            }
        }
    }

    private func finish(_ data: Data) throws -> Data {
        guard let m = H2.unwrapGRPC(data) else {
            throw Failure.protocolError(data.isEmpty ? "the call ended with no answer (gRPC error)" : "bad gRPC frame")
        }
        return m
    }

    private func readFrame() throws -> H2.Frame {
        while true {
            if let (f, used) = H2.parse(buffer) { buffer.removeFirst(used); return f }
            var chunk = [UInt8](repeating: 0, count: 65_536)
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { throw Failure.connection(n == 0 ? "closed" : String(cString: strerror(errno))) }
            buffer += chunk[0..<n]
        }
    }

    private func write(_ d: Data) throws {
        try d.withUnsafeBytes { buf in
            var off = 0
            while off < buf.count {
                let n = send(fd, buf.baseAddress! + off, buf.count - off, 0)
                if n <= 0 { throw Failure.connection(String(cString: strerror(errno))) }
                off += n
            }
        }
    }
}
