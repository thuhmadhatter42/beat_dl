# From the FLR site session: /beat-key rewritten for 0.1.57 (2026-11-09 ~18:45)

**Status: on preview, waiting for J's review, then the live swap.** (Release 0.1.57 is public: Sofia `beat-key-latest.json` = 0.1.57, DMG `Beat-Key-0.1.57.dmg` present.)

Preview: https://preview.fourletterrecords.com/beat-key (Sofia ~/fourletterrecords commit cdd7c05, site preview VERSION 0.0.36).

## Sections
1. Hero: unchanged (J's "YouTube to MP3 / with the BPM/Key", icon).
2. Three keys, not one (shot: window-default): file name, 92% GiantSteps+, LOCKED/UNSURE, pick key 2/3 or any of 24 from MANUAL, **"or right-click it in Finder" back**.
3. It listens, too (shot: panel): HOLD + reset, falls back to Mac audio when the interface is unplugged, menu bar, lamp shapes, decimal BPM, tuning meter + A4, key holds when detuned.
4. Straight into your session (text): DAW list unchanged; "can't confirm a value → sends nothing"; Analyze Selection "give it a shortcut in Settings"; Auto-Tune; ⌃⌥⌘K.
5. Advanced, when you want it (shots: window-advanced + mini): ⌥⌘A, Camelot, notes heard, key wheel, chords (triad to 9th, inversions, click/drag MIDI), MINI (track MIDI input = Beat Key), Match to.
6. Free, and it keeps working: new trio Play it (A S D F…, space flips) / Help on hover / Any colour (COLOR), then the old trio, permissions, licences link.
7. Get: DMG size ~390 → ~400 MB (0.1.57 DMG is 396.7 MB).

## Checked against
README "Beat Key app", Help.swift HelpText, Hotkeys.swift defaults (⌃⌥⌘K listen; Analyze Selection nil), DAWSend.swift DAW list, the 0.1.57 renders, Sofia DMG size.

## Not verified by me (from your notes only)
- Finder right-click works in 0.1.57 (your PICKUP: J's test 2026-11-03 on 0.1.34).
- Lamp shapes in the menu bar (your handoff + README; the renders don't show the menu-bar item).
- Interface-missing → Mac audio fallback (your PICKUP: "not tried by hand").
- "Key holds when a track is detuned" (your tuning tests, PICKUP 2026-11-08).
- MINI into a real DAW (your PICKUP: untested by hand).
Not on the page: README's "Pro Tools/Logic/Studio One fall back to a MIDI file" — your 0.1.36 notes say that fallback was removed; README still says it.
