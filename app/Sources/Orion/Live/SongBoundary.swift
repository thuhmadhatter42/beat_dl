import AppKit
import Foundation

// New-song detection for live listening (J, 2026-11-01: ten beats back to back with no pause held
// one reading for 30 minutes). Two signals, one event:
//  - the analyzer hears a break (`bpm.py --stream` BoundaryDetector: the old song's sustained parts
//    vanish AND its beat grid breaks / the harmony jumps) and prints {"event":"boundary"};
//  - the player says so: Spotify's track or a YouTube tab's title changed (NowPlayingWatcher). Beat
//    Key then tells the analyzer to start over (SIGUSR1) and it answers with a "title" boundary.
// Either way the analyzer has flushed and the reading rebuilds from scratch. Each song heard long
// enough becomes its own Recent Readings entry (SongTracker).

/// A new song started: what the UI consumes (`SongTracker.lastBoundary`).
struct LiveBoundary: Equatable {
    enum Reason: String {
        /// The analyzer heard a break in the music.
        case audio
        /// The player's track / tab title changed.
        case title
    }
    let reason: Reason
    /// The new song's title when the player told us (Spotify, a YouTube tab); nil = not known.
    var title: String? = nil

    /// From the analyzer's line {"event":"boundary","reason":"audio"|"title", ...}.
    init(json obj: [String: Any]) {
        reason = Reason(rawValue: (obj["reason"] as? String) ?? "") ?? .audio
        title = nil
    }

    init(reason: Reason, title: String? = nil) {
        self.reason = reason
        self.title = title
    }
}

/// Something that can tell the analyzer "new song, start over" without restarting it.
protocol SongSignal: AnyObject {
    func newSong()
}

extension LiveProcess: SongSignal {
    /// bpm.py --stream flushes on SIGUSR1 and answers {"event":"boundary","reason":"title"}.
    func newSong() {
        if process.isRunning { kill(process.processIdentifier, SIGUSR1) }
    }
}

// MARK: one song's log

/// What was read of the song playing now. Pure; the clock is passed in.
struct SongLog {
    /// A song becomes a Recent Readings entry when it was green at some point or was read this long.
    static let minSecs: TimeInterval = 15

    private(set) var title: String?
    private(set) var started: Date
    private(set) var best: Result?
    private(set) var wasGreen = false
    private(set) var lastSecs: Double = 0

    init(title: String? = nil, started: Date) {
        self.title = title
        self.started = started
    }

    mutating func name(_ t: String) { title = t }

    /// A reading of this song (`secs` = audio behind it). The last green reading wins; until there
    /// is one, the latest reading stands.
    mutating func feed(_ r: Result, secs: Double) {
        lastSecs = max(lastSecs, secs)
        let green = Lamp.of(r.keys) == .locked
        if green || !wasGreen { best = r }
        if green { wasGreen = true }
    }

    /// The Recent Readings entry for this song, or nil when it was too short / unsure to keep.
    func entry() -> Result? {
        guard let r = best, wasGreen || lastSecs >= SongLog.minSecs,
              r.bpm != nil || !r.keys.isEmpty else { return nil }
        return Result(file: SongLog.file(started), name: displayName, bpm: r.bpm, keys: r.keys,
                      bpmExact: r.bpmExact, tuningCents: r.tuningCents, chroma: r.chroma)
    }

    /// The title, else "Live 10:42 PM".
    var displayName: String {
        if let t = title, !t.isEmpty { return t }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return "Live \(f.string(from: started))"
    }

    /// Each song its own entry (RecentStore keeps one per path).
    static func file(_ started: Date) -> URL {
        URL(fileURLWithPath: "/live/\(Int(started.timeIntervalSince1970 * 1000))")
    }
}

// MARK: the tracker LiveController owns

/// Follows songs while Listen is on: closes the current one into Recent Readings at every boundary
/// (and when Listen stops), and turns a player title change into an analyzer flush.
final class SongTracker: ObservableObject {
    /// The latest boundary while listening (nil before the first one / when Listen is off).
    @Published private(set) var lastBoundary: LiveBoundary?
    /// The title of what is playing, when the player told us.
    @Published private(set) var title: String?
    /// Where finished songs go; set by the app (nil = not kept, e.g. tests).
    var recents: RecentStore?

    /// A title that arrives this soon after an audio boundary names that song instead of
    /// starting another (the analyzer usually hears the change first by a few seconds).
    static let titleJoinWindow: TimeInterval = 10

    private(set) var song: SongLog?
    private weak var signal: SongSignal?
    private var watcher: NowPlayingWatching?
    private let makeWatcher: () -> NowPlayingWatching?
    private let now: () -> Date
    private var lastAudioBoundary: Date?
    /// Readings between asking the analyzer to flush and its "title" boundary are the old song's.
    private(set) var awaitingFlush = false
    private var analyzerReady = false

    init(makeWatcher: @escaping () -> NowPlayingWatching? = { NowPlayingWatcher.inApp ? NowPlayingWatcher() : nil },
         now: @escaping () -> Date = Date.init) {
        self.makeWatcher = makeWatcher
        self.now = now
    }

    /// Listen started (the analyzer is `signal`).
    func begin(signal: SongSignal?) {
        self.signal = signal
        song = SongLog(started: now())
        lastBoundary = nil
        title = nil
        awaitingFlush = false
        analyzerReady = false
        lastAudioBoundary = nil
        let w = makeWatcher()
        watcher = w
        w?.start(onCurrent: { [weak self] t in self?.nameCurrent(t) },
                 onChange: { [weak self] t in self?.titleChanged(t) })
    }

    /// Listen stopped or failed: the song so far is kept if it was long or sure enough.
    func end() {
        watcher?.stop()
        watcher = nil
        close()
        song = nil
        signal = nil
        title = nil
        awaitingFlush = false
    }

    /// Every analyzer event, before LiveSession sees it.
    func observe(_ e: LiveEvent) {
        guard song != nil else { return }
        switch e {
        case .reading(let r):
            guard !awaitingFlush else { return }
            if let s = song { song?.feed(r, secs: now().timeIntervalSince(s.started)) }
        case .reset:                                   // a silent gap: a new song, title unknown
            close()
            song = SongLog(started: now())
            title = nil
        case .boundary(let b):
            if b.reason == .title && awaitingFlush {   // our own flush came back
                awaitingFlush = false
                lastBoundary = LiveBoundary(reason: .title, title: title)
                return
            }
            close()
            song = SongLog(started: now())
            if b.reason == .audio { lastAudioBoundary = now() }
            lastBoundary = LiveBoundary(reason: b.reason, title: nil)
            title = nil
        case .ready:
            analyzerReady = true
        case .error:
            break
        }
    }

    /// The player's title of what is playing at the start (no change, just a name).
    func nameCurrent(_ t: String) {
        guard song != nil, song?.title == nil else { return }
        song?.name(t)
        title = t
    }

    /// The player moved to another track: close this song now and have the analyzer start over,
    /// unless the analyzer already did a moment ago (then this title names that new song).
    func titleChanged(_ t: String) {
        guard song != nil else { return }
        if let a = lastAudioBoundary, now().timeIntervalSince(a) < SongTracker.titleJoinWindow, song?.title == nil {
            song?.name(t)
            title = t
            lastBoundary = LiveBoundary(reason: .audio, title: t)
            lastAudioBoundary = nil
            return
        }
        close()
        song = SongLog(title: t, started: now())
        title = t
        lastAudioBoundary = nil
        if let s = signal, analyzerReady {             // before "ready" it has heard nothing to flush
            awaitingFlush = true
            s.newSong()
        } else {
            lastBoundary = LiveBoundary(reason: .title, title: t)
        }
    }

    private func close() {
        if let r = song?.entry() { recents?.record(r, now: song?.started ?? now()) }
    }
}

// MARK: the player titles

/// Watches the players' "now playing" titles. Callbacks arrive on the main queue.
protocol NowPlayingWatching: AnyObject {
    /// onCurrent: the title playing when watching starts (once, if known). onChange: a new track.
    func start(onCurrent: @escaping (String) -> Void, onChange: @escaping (String) -> Void)
    func stop()
}

/// One player entry: `key` names the slot (Spotify, one browser tab), `identity` changes when the
/// track does, `title` is what to show.
struct NowPlayingEntry: Equatable {
    let key: String
    let identity: String
    let title: String
}

/// Which slot changed between polls. Pure.
struct TitleTracker {
    private var seen: [String: String] = [:]   // key -> identity, kept while a slot is absent (paused)

    /// The new title when a slot that was already there shows another track (Spotify first);
    /// a slot appearing for the first time (a new tab, Spotify starting) is not a change.
    mutating func update(_ entries: [NowPlayingEntry]) -> String? {
        var changed: String?
        for e in entries {
            if let old = seen[e.key], old != e.identity, changed == nil || e.key == "spotify" {
                changed = e.title
            }
            seen[e.key] = e.identity
        }
        return changed
    }

    /// The title to name the current song with when listening starts: Spotify playing, else the
    /// only YouTube tab open.
    static func current(_ entries: [NowPlayingEntry]) -> String? {
        if let s = entries.first(where: { $0.key == "spotify" }) { return s.title }
        let tabs = entries.filter { $0.key != "spotify" }
        return tabs.count == 1 ? tabs[0].title : nil
    }

    /// "(3) Some Beat [140 BPM] - YouTube" -> "Some Beat [140 BPM]".
    static func cleanTabTitle(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) { t.removeSubrange(r) }
        for suffix in [" - YouTube Music", " - YouTube"] where t.hasSuffix(suffix) {
            t.removeLast(suffix.count)
            break
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Lines "key<TAB>identity<TAB>title" from the AppleScripts -> entries (tab titles cleaned).
    static func parse(_ out: String, prefix: String) -> [NowPlayingEntry] {
        out.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, !parts[2].isEmpty else { return nil }
            if prefix == "spotify" { return NowPlayingEntry(key: "spotify", identity: parts[1], title: parts[2]) }
            let title = cleanTabTitle(parts[2])
            guard !title.isEmpty, title != "YouTube", title != "YouTube Music" else { return nil }
            return NowPlayingEntry(key: "\(prefix):\(parts[0])", identity: title, title: title)
        }
    }
}

/// Polls Spotify and the browsers' YouTube tabs once a second with read-only AppleScript queries,
/// whether the apps are in front, behind other windows or hidden. Only apps already running are
/// asked (a `tell` would launch one that isn't). macOS asks the user once per app (Automation;
/// NSAppleEventsUsageDescription + the apple-events entitlement on the signed app).
final class NowPlayingWatcher: NowPlayingWatching {
    static let interval: TimeInterval = 1
    /// Only the real app asks the players (never `swift test` / `swift run`: no Automation prompts there).
    static var inApp: Bool { Bundle.main.bundleIdentifier == "com.jshriver.orion" }

    /// bundle id, slot prefix, script. Every script returns lines "key<TAB>identity<TAB>title".
    static let players: [(id: String, prefix: String, script: String)] = [
        ("com.spotify.client", "spotify", """
        tell application id "com.spotify.client"
            if player state is playing then
                set t to current track
                return "spotify" & tab & (id of t) & tab & (artist of t) & " - " & (name of t)
            end if
        end tell
        return ""
        """),
        ("com.brave.Browser", "brave", chromiumScript("com.brave.Browser")),
        ("com.google.Chrome", "chrome", chromiumScript("com.google.Chrome")),
        ("com.apple.Safari", "safari", """
        set out to ""
        tell application id "com.apple.Safari"
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    set u to URL of t
                    if u is not missing value and (u contains "youtube.com/watch" or u contains "music.youtube.com") then
                        set out to out & (id of w) & "." & i & tab & "-" & tab & (name of t) & linefeed
                    end if
                end repeat
            end repeat
        end tell
        return out
        """),
    ]

    static func chromiumScript(_ id: String) -> String {
        """
        set out to ""
        tell application id "\(id)"
            repeat with w in windows
                repeat with t in tabs of w
                    set u to URL of t
                    if u contains "youtube.com/watch" or u contains "music.youtube.com" then
                        set out to out & (id of t) & tab & "-" & tab & (title of t) & linefeed
                    end if
                end repeat
            end repeat
        end tell
        return out
        """
    }

    private let queue = DispatchQueue(label: "com.jshriver.orion.now-playing")
    private var timer: DispatchSourceTimer?
    private var tracker = TitleTracker()     // queue only
    private var first = true                 // queue only

    func start(onCurrent: @escaping (String) -> Void, onChange: @escaping (String) -> Void) {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: NowPlayingWatcher.interval, leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            let entries = NowPlayingWatcher.poll()
            if self.first {
                self.first = false
                _ = self.tracker.update(entries)
                if let c = TitleTracker.current(entries) { DispatchQueue.main.async { onCurrent(c) } }
            } else if let changed = self.tracker.update(entries) {
                DispatchQueue.main.async { onChange(changed) }
            }
        }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// One poll of every running player.
    static func poll() -> [NowPlayingEntry] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        var out: [NowPlayingEntry] = []
        for p in players where running.contains(p.id) {
            var err: NSDictionary?
            guard let s = NSAppleScript(source: p.script),
                  let text = s.executeAndReturnError(&err).stringValue else { continue }
            out += TitleTracker.parse(text, prefix: p.prefix)
        }
        return out
    }
}
