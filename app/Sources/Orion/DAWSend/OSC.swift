import Foundation

/// The small slice of OSC 1.0 Beat Key speaks with its own DAW scripts (Ableton Remote Script,
/// Bitwig controller script): int32, float32 and string arguments, big-endian, 4-byte padded.
/// Spec: https://opensoundcontrol.stanford.edu/spec-1_0.html
enum OSC {
    enum Arg: Equatable {
        case int(Int32)
        case float(Float)
        case string(String)

        var tag: Character {
            switch self {
            case .int: return "i"
            case .float: return "f"
            case .string: return "s"
            }
        }
    }

    struct Message: Equatable {
        let address: String
        let args: [Arg]
        init(_ address: String, _ args: [Arg] = []) { self.address = address; self.args = args }

        func string(_ i: Int) -> String? { if args.indices.contains(i), case .string(let s) = args[i] { return s }; return nil }
        func int(_ i: Int) -> Int? { if args.indices.contains(i), case .int(let v) = args[i] { return Int(v) }; return nil }
        func float(_ i: Int) -> Double? {
            guard args.indices.contains(i) else { return nil }
            switch args[i] {
            case .float(let v): return Double(v)
            case .int(let v): return Double(v)
            case .string: return nil
            }
        }
    }

    /// An OSC string: UTF-8, NUL-terminated, padded with NULs to a multiple of 4.
    static func padded(_ s: String) -> [UInt8] {
        var b = Array(s.utf8) + [0]
        while b.count % 4 != 0 { b.append(0) }
        return b
    }

    static func encode(_ m: Message) -> Data {
        var out = padded(m.address) + padded("," + String(m.args.map(\.tag)))
        for a in m.args {
            switch a {
            case .int(let v): out += be32(UInt32(bitPattern: v))
            case .float(let v): out += be32(v.bitPattern)
            case .string(let s): out += padded(s)
            }
        }
        return Data(out)
    }

    /// nil = not a well-formed message (bundles are not used here).
    static func decode(_ data: Data) -> Message? {
        let b = [UInt8](data)
        var i = 0
        func str() -> String? {
            guard let end = b[i...].firstIndex(of: 0) else { return nil }
            let s = String(decoding: b[i..<end], as: UTF8.self)
            i = (end + 4) & ~3
            return i <= b.count ? s : nil
        }
        func word() -> UInt32? {
            guard i + 4 <= b.count else { return nil }
            defer { i += 4 }
            return UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
        }
        guard let address = str(), address.hasPrefix("/") else { return nil }
        if i >= b.count { return Message(address) }
        guard let tags = str(), tags.hasPrefix(",") else { return nil }
        var args: [Arg] = []
        for t in tags.dropFirst() {
            switch t {
            case "i": guard let w = word() else { return nil }; args.append(.int(Int32(bitPattern: w)))
            case "f": guard let w = word() else { return nil }; args.append(.float(Float(bitPattern: w)))
            case "s": guard let s = str() else { return nil }; args.append(.string(s))
            default: return nil
            }
        }
        return Message(address, args)
    }

    private static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    }
}

/// One UDP request and its reply on localhost, blocking with a timeout. Runs off the main thread.
enum UDP {
    enum Failure: Error, Equatable { case socket(String), noReply }

    /// Sends `payload` to 127.0.0.1:`port` and waits up to `timeout` s for one datagram back.
    /// `replyPort` 0 = any free port (the script answers the sender); else bind that port
    /// (Bitwig's script cannot see the sender and answers a fixed port).
    static func request(_ payload: Data, port: UInt16, replyPort: UInt16 = 0, timeout: TimeInterval = 1.5) throws -> Data {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw Failure.socket("socket: \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var local = loopback(replyPort)
        let bound = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw Failure.socket("bind \(replyPort): \(String(cString: strerror(errno)))") }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var dest = loopback(port)
        let sent = payload.withUnsafeBytes { buf in
            withUnsafePointer(to: &dest) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == payload.count else { throw Failure.socket("send: \(String(cString: strerror(errno)))") }
        var buf = [UInt8](repeating: 0, count: 65_536)
        let n = recv(fd, &buf, buf.count, 0)
        guard n > 0 else { throw Failure.noReply }
        return Data(buf[0..<n])
    }

    /// OSC in, OSC out.
    static func request(_ m: OSC.Message, port: UInt16, replyPort: UInt16 = 0, timeout: TimeInterval = 1.5) throws -> OSC.Message {
        let reply = try request(OSC.encode(m), port: port, replyPort: replyPort, timeout: timeout)
        guard let msg = OSC.decode(reply) else { throw Failure.socket("unreadable reply") }
        return msg
    }

    static func loopback(_ port: UInt16) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        a.sin_addr.s_addr = inet_addr("127.0.0.1")
        return a
    }
}
