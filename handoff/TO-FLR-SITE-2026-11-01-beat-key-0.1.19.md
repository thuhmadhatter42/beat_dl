# To the FLR site session: Beat Key 0.1.19 features for the /beat-key page

[SUPERSEDED 2026-11-10: the page was rewritten for 0.1.57 and is live, FROM-FLR-SITE-2026-11-09-beat-key-page.md]

From: beat_dl session (MBP `~/dev/beat_dl`), 2026-11-01.

## Status
0.1.19 is built but **not released**. Do not change the download or the version on the page yet. You get a GO note (`TO-FLR-SITE-...-beat-key-0.1.19-GO.md`) when the DMG is live. Prepare the copy now, publish on GO.

## Headline stays the same
"Three keys, not one": top 3 keys with a confidence score each, all three in the filename, the right key in the three on 92% of the GiantSteps+ benchmark. Everything below goes under it as a short "also" section, not above it.

## New in 0.1.19 (facts exact, wording yours)
- **Live listening.** Reads the BPM and key of whatever is playing, as it plays. Sources: everything the Mac plays (macOS 13 or newer), the default input, or a chosen microphone or interface (one channel or all). Nothing is recorded or saved.
- **Menu-bar readout.** The reading (e.g. `Ebm 128`) and its lamp sit in the menu bar.
- **Confidence lamps with shapes.** Green octagon = locked, amber triangle = unsure, red circle = listening. A High Contrast Readout switch is in Settings and the View menu.
- **Decimal BPM**, with a click on the BPM to switch between normal, double and half time.
- **Tuning** in cents against a reference pitch (A = 432, 436, 438, 440, 442, 444, 450, or custom 400 to 480 Hz).
- **More file types:** MP3, WAV, AIFF, FLAC, M4A, AAC, OGG, CAF, MP4, M4V, MOV and MIDI. Video files are read by their audio.
- **Analyze a File** from the File menu, a global shortcut, Open With, a drop on the Dock icon, or Finder right-click > Services > Analyze with Beat Key. Recent readings are kept in the File menu.
- **Send to DAW** (sends the decimal BPM and the top key to the DAW you used last, or to all open ones):
  - Ableton Live 12: tempo and key (Live 11: tempo only).
  - REAPER and Bitwig Studio: tempo (neither has a project key).
  - Pro Tools, Logic Pro, Studio One: tempo and key, through Accessibility; if that fails, a MIDI file with tempo and key.
  - FL Studio, Reason, Cubase: a MIDI file with tempo and key to import.
- **Analyze Selection:** reads the selected clip in Pro Tools, Ableton Live or REAPER.
- **Send Key to Auto-Tune:** gives the top key and reference pitch to Auto-Tune Pro (instances with Auto Key Detection on). Antares doesn't document the handoff, so say "works with Auto-Tune Pro's Auto Key", not "official".
- **Export MIDI Tempo/Key file** for any DAW.
- **Global shortcuts** (change or turn off in Settings): listen ⌃⌥⌘K, analyze a file ⌃⌥⌘F, send to DAW ⌃⌥⌘S, send to all ⌃⌥⌘D, analyze selection ⌃⌥⌘L, key to Auto-Tune ⌃⌥⌘A, export MIDI ⌃⌥⌘E. **Open at Login** is in Settings.

## Permissions (say so on the page)
macOS asks only when the feature is used:
- Microphone: listening to a mic or interface.
- Screen & System Audio Recording: listening to everything the Mac plays (sound only).
- Accessibility: Send to DAW for Pro Tools, Logic Pro, Studio One.

## Unchanged
macOS 12 or newer for the app (system-audio listening needs 13), Apple Silicon and Intel, free, updates itself. The full list is in the repo README, "What else Beat Key does".

Reply to `~/dev/beat_dl/handoff/FROM-FLR-SITE-*.md`.
