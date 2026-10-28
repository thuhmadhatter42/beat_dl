# Orion v1: beat_dl as a real Mac app with an installer (design)

**Date:** 2026-10-27 · **Status:** Approved by J 2026-10-27 ("beautiful! make it!"). Plan `docs/superpowers/plans/2026-10-27-orion-v1.md`; Tasks 1-2 built (runtime payload, app_run.py), Task 3 next. See PICKUP.md.
**Read §10 (Amendment 2026-10-28) first: it supersedes the name, macOS floor, delivery model and cookie policy below. Superseded rulings are tagged [SUPERSEDED 2026-10-28] in place.**

**Name: Orion** (J, 2026-10-27) [SUPERSEDED 2026-10-28 for the public name: Beat Key; Orion stays the internal/code name, see §10]. The downloader is Orion v1. The menu-bar listener from
`2026-09-12-menubar-key-bpm-listener-design.md` joins the same app later as a second feature. Build v1 so a
second mode can be added without restructuring (one app target, the readout as a shared component).

## 1. Why

[SUPERSEDED 2026-10-28: no longer a send-to-a-friend tool; it is the free product on fourletterrecords.com, see §10.] J's friend has no dev experience and wants to use beat_dl. Today that takes Terminal, git and
a double-click on `run.command` that macOS blocks the first time. J wants him to get **one
installer file, run it, open the app, and have it work**. J also asked for it to "look sexy".

**What success looks like:** the friend opens what J sends him, drags the app into Applications,
double-clicks it, pastes a YouTube link, clicks **Download**, and gets the same MP3 the Terminal
version makes. He never sees a warning dialog, Terminal, or a setup step he has to understand.

## 2. Goals, non-goals, anti-goals

**Goals**
- One window: a field that says **"Enter YouTube link here"** and a **Download** button (J's words).
- Everything after the click works exactly like `run.sh` does today: MP3 (best quality) in
  `~/Downloads`, renamed `<title> (<bpm> BPM <k1> <k2> <k3>).mp3`, a line pair added to
  `~/Downloads/(YY-M-D) Youtube DL LINKS.txt`, yt-dlp upgraded and the download retried once if it fails.
- Drop an audio file on the window to get its BPM and key. The file isn't renamed, moved or
  logged (same as `dropped.py` today).
- Shipped as a signed and notarized `.dmg` (J's Developer ID, team `9WTFGV63S2`), so it opens on any
  Mac with no Gatekeeper warning.
- Looks beautiful and unlike a generic app (the `design` skill, §5 below).

**Non-goals (v1)**
- No queue, playlists, batch URLs, format picker, destination picker or settings pane.
- No auto-update of the app itself. Only yt-dlp updates itself (§4.4). A new app version = J sends a new DMG.
- No Windows or Linux.
- No changes to how BPM/key is detected. The app calls the same `bpm.py`.

**Anti-goals (would make it a failure even if it works)**
- A Gatekeeper "unidentified developer" / "damaged" dialog, or a step that needs Terminal.
- A Keychain password prompt or a "wants to access data from other apps" dialog the friend
  can't make sense of (see §4.5).
- A first launch that sits on a blank or frozen window with no sign it's working.
- Breaking the Terminal version. `run.command` keeps working for J and Studio-E-2.
- Song/artist/file names in logs, telemetry or test fixtures committed to the repo (J's standing rule).

## 3. What exists and is reused

- `downloader.py`: given a URL, it tries cookie/player-client strategies in order, prints the final MP3 path on
  stdout, prints errors on stderr, and exits non-zero on failure.
- `bpm.py <file>`: prints 4 lines: BPM, then the top 3 keys, each as `Key (NN%)`.
- `dropped.py`: path parsing for Terminal drops. The app gets real file URLs from the drop, so it doesn't need this.
- `deps.sh`: picks builds per CPU/macOS, unpacks the Python+Essentia analyzer, and runs the weekly `yt-dlp -U`.
- `vendor/`: yt-dlp (universal), ffmpeg/ffprobe per arch (arm64, arm64-legacy, x86_64),
  `python.tar.gz` + wheels per arch. 234 MB.
- `run.sh`: the flow the app has to reproduce (rename, log, retry-once-after-upgrade).

## 4. How it's made

### 4.1 App shell (builder's call within this frame)
- **Native SwiftUI app**, single window, built with Xcode 27 on the MBP. **My call:** SwiftUI over
  a web wrapper (Electron/Tauri), because it's smaller, it's native, and J has a native-app track (Orion).
- **Universal binary** (arm64 + x86_64). **My call:** the floor is **macOS 11** on both [SUPERSEDED 2026-10-28: floor is macOS 12, ruled in the ledger at Task 4, see §10]. Intel Macs on 10.15
  lose the app but keep `run.command`.
- The Swift layer drives the existing scripts as subprocesses. It doesn't re-implement them. One
  orchestration point. The cleanest version is a small `app_run.py` (or a mode of an existing script)
  that does download → analyze → rename → log and prints JSON-lines progress events
  (`{"stage":"downloading"}`, `{"stage":"done","file":…,"bpm":…,"keys":[…]}`, `{"stage":"error","message":…}`)
  for the Swift side to render. `run.sh` and the app then share the rename/log logic instead of copying it
  (the builder decides whether run.sh moves onto it too).
- App location: in the beat_dl repo under `app/`. Repo gets a `VERSION` file (starts `0.1.0`,
  last number +1 per edit, per J's rule). Build/sign/notarize/DMG is one script, e.g. `app/build.sh`.

### 4.2 What's inside the .app
- yt-dlp, ffmpeg/ffprobe (every per-arch variant), Python 3.11 + Essentia + numpy, `bpm.py`,
  `tempocnn_np.py`, `models/`, `downloader.py`. Nothing is downloaded on first launch.
- Builder decides: ship pre-extracted and signed inside the bundle (fast first launch, all Mach-O
  signed for notarization), or ship the archives and unpack on first launch the way `deps.sh` does now.
  **Constraint either way:** notarization must pass with **every** Mach-O in the bundle signed with
  hardened runtime, including the Python `.so` files and Essentia. Verify with `codesign --verify --deep --strict`,
  `spctl -a -vv`, and a notarization log with zero issues. Expected size 250–350 MB.
- Writable state lives in `~/Library/Application Support/Orion/` (the updated yt-dlp, the
  upgrade stamp, any unpacked runtime). The signed bundle is never written to.

### 4.3 Installer
- **`.dmg`** with the app and an Applications shortcut, a background showing "drag to Applications",
  signed, notarized, stapled. **My call:** a DMG over a `.pkg` wizard: it's the normal Mac way,
  with fewer screens and nothing for the friend to read.
- [SUPERSEDED 2026-10-28: ships as a download behind an FLR account, see §10] How it reaches the friend: J sends the file (AirDrop/Drive/link). Publishing it as a GitHub Release
  on the public repo is a separate ask that needs J's yes at that time.

### 4.4 yt-dlp freshness
YouTube breaks old yt-dlp builds every few weeks. Same policy as `deps.sh`: on launch, if the
stamp is older than 7 days, run `yt-dlp -U` against the copy in Application Support (seeded from
the bundle). If a download fails, upgrade once and retry. If the updated binary won't run, fall back
to the bundled one. This runs in the background and never blocks the window.

### 4.5 Cookies (needs care in an app) [SUPERSEDED 2026-10-28: cookies on demand only (J 2026-10-27 22:24), then in-app YouTube login replacing browser cookies and Full Disk Access (Task 14, in progress); see §10]
`downloader.py` tries `--cookies-from-browser firefox/safari/chrome` first. From a GUI app on a fresh
Mac this can trigger a Keychain prompt (Chrome "Safe Storage") or a macOS privacy prompt (Safari
container, Full Disk Access). Those are anti-goals. **Requirement:** in the app, the strategies that
need no permission (the plain and player-client ones) go first, and browser cookies are tried only
as a last resort. Testing this on a clean user account (§7) decides whether the cookie strategies
stay in the app at all.

## 5. Look and feel

Built with the `design` skill: `macos-app-design` first (HIG wins), then `impeccable` for the build
and the critique.

- **Concept (J, 2026-10-27: "make it look like Artemis kinda"):** Orion is Artemis's sibling, the same
  hardware family. Use Artemis's own faceplate material, taken from `~/artemis/app/src/faceplate/shared.css` +
  `faceplate.html`: the noise-and-sheen chassis (`#232326→#131315`, black outer rings), silver corner screws, the
  brushed header rail with the chrome-gradient wordmark **ORION** (Helvetica Neue 700, .22em tracking), a green
  status lamp + legend (READY / WORKING amber / FAILED red), the amber LCD (`--amber #ffb020`, glow, 8px .3em
  captions) as the hero, recessed `#050505` field, and pale SSL-style caps (DOWNLOAD lights amber when a link is in).
  Reference mockup: `orion-v1-mockup.html` next to this file.
- **Signature element:** the LCD readout. After a download, the BPM shows as a large amber numeral, the top
  key beside it, and keys 2 and 3 smaller under it. A TEMPO light blinks **at the detected BPM** (it's real
  data, and it stops when Reduce Motion is on).
- **Dark only**, like Artemis (no light mode).
- **Type:** Helvetica Neue throughout (Artemis's `--face-font`), tabular figures on numbers.
- **App icon:** v1 = Orion's constellation in amber on the Artemis chassis (my call, rendered by code). Later, if J supplies a render: in Artemis's icon style (a marble relief on a deep navy ground), showing Orion the hunter,
  Artemis's hunting companion in the myth.
- **States, all designed:** empty (placeholder "Enter YouTube link here"), link pasted (Download
  lit), downloading (readout shows stage text: "Downloading…", "Finding BPM and key…"), done
  (filename, BPM, keys, SHOW IN FINDER on the LCD), file dropped (drop highlight on the whole window → readout),
  error (plain English from `explain_error`, inline in the readout, never a modal), first-launch prep if any.
- Mac citizen: Return triggers Download, ⌘V pastes, standard menus, the window is resizable within limits,
  VoiceOver labels, Reduce Motion respected.
- **Gate:** before the full build, J sees a mockup of the main states (rendered screenshots) and
  says yes. Then build.

## 6. Left to the builder
Internal structure of the Swift app, the progress-event format, whether `run.sh` moves onto the shared
orchestrator, pre-extracted vs unpack-on-launch, the DMG background art, the app icon (in the gear concept,
no logos of anyone else's), and the exact sizes and spacing on a 4/8 grid.

## 6a. Settled after the builder check (my calls, J can override)
- **One universal DMG with every per-arch variant.** No hard size limit. Expect 400–550 MB. One file beats a
  "which Mac do you have?" step.
- [SUPERSEDED 2026-10-28: floor is macOS 12] **Floor macOS 11 on both chips.** The universal build covers whatever Mac the friend has, as long as it's on 11+.
- **The Python scripts may change** (paths found relative to the bundle, PATH set by the app,
  a strategy-order flag on `downloader.py`) as long as `run.command` behaves exactly as before.
- [SUPERSEDED 2026-10-28: see §10 login-on-demand] **Cookie order is app-only.** The app passes a flag that puts the no-permission strategies first.
  The Terminal order stays the same. If the clean-account test shows any prompt from the cookie strategies, the app drops them. Age-restricted
  videos may then fail in the app with a plain-English error.
- **Downloaded but analysis failed:** keep the original filename, log it (as run.sh does), and the readout says
  "Downloaded. Couldn't find BPM/key for this one." Give `bpm.py` a 120 s timeout, then treat it as failed.
- **yt-dlp self-update:** the updated binary runs as a child process from Application Support. Hardened runtime /
  library validation apply to code loaded into the app's own process, not to a child executable, and a
  self-written file isn't quarantined. Still, a risk to **verify** on the clean account (Done #5). If it's blocked,
  ad-hoc re-sign it after the update (`codesign -s - -f`) and re-test.
- **First-launch unpack** is fine if needed, with a progress state in the readout ("Setting up, one time…").
- **Bundle ID** `com.jshriver.orion` (still current: code, bundle ID and App Support stay Orion, J 2026-10-27 "leave all the code, say Orion"). Application Support folder `~/Library/Application Support/Orion/`.
- **Notarization profile:** `artemis-notary` (the `notarytool store-credentials` profile on the MBP that artemis and
  zeropoint already notarize with, same team). Signing identity `Developer ID Application: J Shriver (9WTFGV63S2)`.
- [SUPERSEDED 2026-10-28: audience is every FLR user, macOS 12+] **The friend's Mac** is assumed to be on macOS 11+ (J).
- **The code lives in this repo** under `app/` (the scripts it drives live here). No separate `~/dev/orion` repo.

## 7. Done means
1. `app/build.sh` produces a notarized, stapled `Orion-<version>.dmg` from a clean checkout.
2. On a **fresh macOS user account** on the MBP (no Homebrew in PATH, no browser logins): open the DMG,
   drag, launch, with no warning dialogs and no permission prompts. Paste a URL, Download, and the MP3 shows up in
   Downloads with the same name `run.sh` gives, and the log file gets its entry.
3. Same on an Intel Mac (Sofia is macOS 12, Intel: use it as the Intel test, over ssh/screen per the
   `sofia-screen` skill. Never restart it).
4. Drop a WAV and an MP3 → BPM + keys shown, files untouched.
5. A forced-stale yt-dlp (old binary in Application Support) → upgrade + retry happens by itself.
6. `run.command` still works from the repo.
7. Screenshots of every state from §5, critiqued with `impeccable`, fixes applied.

## 10. Amendment 2026-10-28 (current truth; wins over anything above)

Source: PICKUP.md CURRENT STATE 2026-10-28 12:30, ledger `.superpowers/sdd/2026-10-27-orion-v1/progress.md`, J 2026-10-28 12:20.

- **Name:** public name **Beat Key** (J 2026-10-27 19:56). Internal name Orion: code, `com.jshriver.orion`, `~/Library/Application Support/Orion/` and the Swift target stay Orion. UI wordmark, DMG (`Beat-Key-<version>.dmg`), installed app (`/Applications/Beat Key.app`) and README say Beat Key.
- **macOS 12+, not 11.** Xcode 27 / Swift 6.4 emits minos 12.0 even under `-target macos11`, there is no macOS 11 Mac to test, Sofia (12.7.6) is the oldest test machine. `LSMinimumSystemVersion` 12.0, `Package.swift` `.macOS(.v12)`. Universal (arm64 + x86_64) unchanged.
- **Open Audio row:** a second row under the link field with **Open Audio...** and **Find Key/BPM** (pick a file instead of dropping one). Icon = a music staff cut out as a key.
- **Run Doctor:** menu item Beat Key > Run Doctor checks the bundled tools (yt-dlp, ffmpeg, Python/Essentia, deno JS runtime) and reports plain-English results.
- **Login on demand:** browser cookies are never read automatically (J 2026-10-27 22:24). If YouTube blocks a video the LCD says so and offers a login-and-retry; plain downloads need no login.
- **Bundled deno** since 0.1.9 (yt-dlp EJS JS challenges need a JS runtime; absence caused the failed login retry at 00:27). DMG grew from about 296 MB to about 390 MB.
- **No Full Disk Access, in-app YouTube login (IN PROGRESS, Task 14, 0.1.13):** J called Full Disk Access "wildly invasive". Replacement: an in-app YouTube login window (WKWebView, its own cookie file passed with `--cookies-file`); fallback if it cannot work = "age-restricted, can't download". Spike note: Google's passkey step fails in WKWebView, password route via "Try another way" is being tested. Until Task 14 reports, treat §4.5 and the above as the plan, not as shipped.
- **Free FLR product:** J 2026-10-28 12:20: the free offer on fourletterrecords.com, downloaded behind an FLR account (like the Artemis installer), for all FLR users, not one friend. Page handoff: `handoff/TO-FLR-SITE-2026-10-28-beat-key-free-download.md`. Do not publish the download until beat_dl says go.
- **Release gate [Now]:** open-source licences (Essentia AGPL-3.0, ffmpeg build likely GPL, TempoCNN weights CC BY-NC-SA 4.0) need a licences file in the app and a source/licence link on the site before public release.
- **Version:** branch `orion-v1` at 0.1.12 (0.1.13 in Task 14). Merging to main and tagging needs J's OK.
