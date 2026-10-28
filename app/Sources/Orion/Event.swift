import Foundation

struct Result: Equatable {
    let file: URL
    let name: String
    let bpm: String?
    let keys: [(String, Int)]
    /// "permission" when macOS refused to let the helper read the file.
    var readError: String? = nil

    static func == (a: Result, b: Result) -> Bool {
        a.file == b.file && a.name == b.name && a.bpm == b.bpm && a.readError == b.readError
            && a.keys.count == b.keys.count
            && zip(a.keys, b.keys).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    }
}

enum Event: Equatable {
    case stage(String)
    case done(Result)
    case analyzed(Result)
    case error(String)
    /// A YouTube login would fix this: reason "age" | "bot" | "members"; tried = the browser
    /// whose cookie was already used (the cookie try failed again).
    case needsLogin(reason: String, message: String, tried: String?)
    /// macOS keeps the browser's data from Beat Key: Full Disk Access would fix it.
    case needsAccess(browser: String, message: String)

    /// One JSON line from app_run.py. app_run.py puts the event kind in "stage"
    /// ("downloading"... are progress, "done"/"analyzed"/"error" are terminal).
    /// A line with "event" as the kind key is accepted too. Garbage or unknown -> nil.
    static func parse(line: String) -> Event? {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let kind = (obj["event"] as? String) ?? (obj["stage"] as? String)
        guard let kind else { return nil }
        switch kind {
        case "done", "analyzed":
            guard let file = obj["file"] as? String, let name = obj["name"] as? String else { return nil }
            var keys: [(String, Int)] = []
            for item in (obj["keys"] as? [Any]) ?? [] {
                guard let pair = item as? [Any], pair.count == 2,
                      let k = pair[0] as? String, let p = (pair[1] as? NSNumber)?.intValue
                else { return nil }
                keys.append((k, p))
            }
            let r = Result(file: URL(fileURLWithPath: file), name: name,
                           bpm: obj["bpm"] as? String, keys: keys,
                           readError: obj["error"] as? String)
            return kind == "done" ? .done(r) : .analyzed(r)
        case "error":
            return .error((obj["message"] as? String) ?? "Unknown error.")
        case "needs_login":
            return .needsLogin(reason: (obj["reason"] as? String) ?? "bot",
                               message: (obj["message"] as? String) ?? "",
                               tried: obj["tried"] as? String)
        case "needs_access":
            guard let b = obj["browser"] as? String, !b.isEmpty else { return nil }
            return .needsAccess(browser: b, message: (obj["message"] as? String) ?? "")
        case "stage":
            guard let s = obj["stage"] as? String else { return nil }
            return .stage(s)
        case "downloading", "analyzing", "renaming", "updating":
            return .stage(kind)
        default:
            return nil
        }
    }
}
