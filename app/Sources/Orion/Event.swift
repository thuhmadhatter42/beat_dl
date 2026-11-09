import Foundation

struct Result: Equatable {
    let file: URL
    let name: String
    let bpm: String?
    let keys: [(String, Int)]
    /// "permission" when macOS refused to let the helper read the file.
    var readError: String? = nil
    /// The BPM to 0.01 (bpm is the whole-number-ish value the file name carries); nil = not measured.
    var bpmExact: Double? = nil
    /// Tuning in cents against A = 440 Hz (+ = sharp); nil = not confident enough to say.
    var tuningCents: Double? = nil
    /// The 12 pitch-class strengths (C, C#, ... B; 0...1) the key was read from; nil = the
    /// analyzer sent none (older helper, MIDI file): Notes Heard is hidden.
    var chroma: [Double]? = nil

    static func == (a: Result, b: Result) -> Bool {
        a.file == b.file && a.name == b.name && a.bpm == b.bpm && a.readError == b.readError
            && a.bpmExact == b.bpmExact && a.tuningCents == b.tuningCents && a.chroma == b.chroma
            && a.keys.count == b.keys.count
            && zip(a.keys, b.keys).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    }
}

enum Event: Equatable {
    case stage(String)
    case done(Result)
    case analyzed(Result)
    case error(String)
    /// A YouTube login would fix this: reason "age" | "bot" | "members"; stale = the saved login
    /// was used and YouTube no longer takes it (the app deletes it and asks again).
    case needsLogin(reason: String, message: String, stale: Bool)

    /// One JSON line from app_run.py. app_run.py puts the event kind in "stage"
    /// ("downloading"... are progress, "done"/"analyzed"/"error" are terminal).
    /// A line with "event" as the kind key is accepted too. Garbage or unknown -> nil.
    /// `[["Cm", 80], ["Eb", 9], ...]` (app_run.py and bpm.py --stream). Missing = none; a
    /// malformed entry = nil (the whole line is ignored).
    static func keyList(_ any: Any?) -> [(String, Int)]? {
        var keys: [(String, Int)] = []
        for item in (any as? [Any]) ?? [] {
            guard let pair = item as? [Any], pair.count == 2,
                  let k = pair[0] as? String, let p = (pair[1] as? NSNumber)?.intValue
            else { return nil }
            keys.append((k, p))
        }
        return keys
    }

    /// `"chroma": [12 numbers]`; missing = nil. Anything else (wrong count, a non-number) is
    /// logged and dropped: the reading stands, Notes Heard is hidden.
    static func chroma(_ any: Any?) -> [Double]? {
        guard let any, !(any is NSNull) else { return nil }
        guard let list = any as? [Any], list.count == 12 else {
            AppLog.log("analyzer line: chroma is not 12 numbers, ignored")
            return nil
        }
        var out: [Double] = []
        for v in list {
            guard let n = v as? NSNumber, n.doubleValue.isFinite else {
                AppLog.log("analyzer line: chroma holds a non-number, ignored")
                return nil
            }
            out.append(n.doubleValue)
        }
        return out
    }

    /// The reading every analyzer line carries, from app_run.py's done / analyzed and from
    /// `bpm.py --stream`'s `reading` (LiveEvent.parse): keys, bpm, bpm_exact, tuning_cents,
    /// chroma, error. One parser for both, so a field added to one is read from both.
    /// nil = the keys are malformed (the whole line is ignored).
    static func reading(_ obj: [String: Any], file: URL, name: String) -> Result? {
        guard let keys = keyList(obj["keys"]) else { return nil }
        return Result(file: file, name: name, bpm: obj["bpm"] as? String, keys: keys,
                      readError: obj["error"] as? String,
                      bpmExact: (obj["bpm_exact"] as? NSNumber)?.doubleValue,
                      tuningCents: (obj["tuning_cents"] as? NSNumber)?.doubleValue,
                      chroma: chroma(obj["chroma"]))
    }

    static func parse(line: String) -> Event? {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let kind = (obj["event"] as? String) ?? (obj["stage"] as? String)
        guard let kind else { return nil }
        switch kind {
        case "done", "analyzed":
            guard let file = obj["file"] as? String, let name = obj["name"] as? String,
                  let r = reading(obj, file: URL(fileURLWithPath: file), name: name) else { return nil }
            return kind == "done" ? .done(r) : .analyzed(r)
        case "error":
            return .error((obj["message"] as? String) ?? "Unknown error.")
        case "needs_login":
            return .needsLogin(reason: (obj["reason"] as? String) ?? "bot",
                               message: (obj["message"] as? String) ?? "",
                               stale: (obj["stale"] as? Bool) ?? false)
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
