# Orra Key parity for Beat Key (J, 2026-11-08 21:49)

Source: Orra Key video https://www.youtube.com/watch?v=I4nfYoofxMg (description read via yt-dlp; no captions).
J picked all four missing pieces + asked about tuning. Version stays 0.1.x; every build bumps the last number.

## 1. Live tuning (agent A: `bpm.py`, `tests/test_bpm_stream.py`, `app/Sources/Orion/Live/LiveSession.swift`)
J's report: Spotify → Artemis → Beat Key live, Spotify pitched +7, +14, +50 cents: no tuning shown, sureness drops.
Verified cause (2026-11-08): `LiveAnalyzer.reading()` (bpm.py ~650) never computes tuning, and
`Faceplate.liveReadout` (LiveSession.swift:164) passes `tuning: nil`. Files do get `tuning_cents`
via `detect_tuning` (bpm.py:312) when key confidence >= 50. The live key confidence drop: HPCP is
fixed at referenceFrequency 440 with 36 bins (33 ¢ each); `hpcp_to_pcp12` only snaps the global
peak to a bin, so +14 / +50 ¢ smear energy and segment agreement falls.
1.1 Stream: keep spectral peaks for the key window (`hpcp_frames(..., peaks_out)`), estimate tuning
    each reading (essentia TuningFrequency, same folding as `detect_tuning`), emit `tuning_cents`.
    Estimate on all heard frames regardless of key confidence, but only emit when key conf >= 50
    (same rule as files) — reconsider: emit always with a separate flag if conf gate hides it.
1.2 Detune-robust key: once tuning is known (|c| >= 5), recompute HPCP for the key window with
    referenceFrequency = 440 * 2^(c/1200) (files and stream), so a 50 ¢ shift reads as confident
    as 0 ¢. Keep both paths sharing one function.
1.3 Swift: LiveSession passes `Tuning.line(r.tuningCents, reference:)` like FaceplateView:334;
    make sure stream events parse `tuning_cents` (Event.swift is agent B's file: coordinate by
    contract — B adds parsing for stream `reading` events if missing).
1.4 Test: synthesize a chord progression pitched 0/+7/+14/+50/-30 ¢ (numpy sines) in
    `tests/test_bpm_stream.py` and file tests; tuning within ±3 ¢, key conf within 10 points of 0 ¢.
1.5 Emit `chroma`: 12 floats C..B, 0..1, the pcp12 the key came from (files and stream) — for
    "Notes heard" in §2.

## 2. Advanced mode + Orra features (agent B: Swift UI, everything else under `app/Sources/Orion`, `app/Tests`)
J: "default mode that is more minimal and then an advanced mode that shows everything".
2.1 Mode: `DisplaySettings.advanced` (UserDefaults `advancedMode`, default false). View menu
    "Advanced Mode" ⌥⌘A (check for clash in Hotkeys/ShortcutStore first) + a toggle in Settings.
    Default mode = today's window, made more minimal where it has extras (keep key, BPM, lamp,
    send buttons). Advanced = everything below. Menu-bar pocket stays as is.
2.2 Camelot / DJ code (8A/8B) next to the key (advanced; KeySpelling-aware; relative key too).
2.3 Chord strip: 7 diatonic chords of the detected key + 4 borrowed colour chords (minor key:
    from parallel major and vice versa; pick the 4 standard ones: bVI bVII iv bIII for major;
    IV(maj) V(maj) bII ... document the choice). Triads / 7ths / 9ths, 4 voicings (root, 1st inv,
    2nd inv, open/spread), length 1 / 2 / 4 bars at the reading's BPM (4/4).
    Click = hear (AVAudioEngine + AVAudioUnitSampler, built-in GM piano / DLS, no bundled samples).
    Drag = a .mid clip (MidiExport writer, tempo + the chord held for the length) written to a temp
    dir and dragged as a file URL (NSItemProvider / onDrag) — works into Logic, Ableton, FL, Pro
    Tools, Finder.
2.4 Transpose "MATCH TO": pick a project key; row shows -6..+6 semitones with the one that maps
    the detected key onto it highlighted (relative major/minor counts as a match).
2.5 Key wheel: circle of fifths (12 major outer, 12 minor inner), detected key + runner-ups lit;
    click a key = choose it (same path as today's click-to-choose key, KeyChoice).
2.6 Notes heard: 12-bar chroma display from `Result.chroma` (Event.swift parses `chroma`), scale
    notes marked.
2.7 Tests in app/Tests/OrionTests: chord spelling per key/quality/voicing, borrowed set, Camelot
    table (24 keys), transpose math, MIDI clip bytes (tempo, length, notes), Event parsing of
    `chroma` and stream `tuning_cents`.

## 3. Integrate, build, install (main session)
3.1 Merge A then B into main, resolve, `swift test`, `python3 -m pytest tests`.
3.2 Bump VERSION, build via app/build.sh, install on MBP. Not published (J runs publish.sh).
3.3 J retests: Spotify pitched 7/14/50 ¢ live; advanced mode; drag a chord into Pro Tools/Logic.
