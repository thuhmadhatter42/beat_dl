# Beat Key: SESSION Key feature parity (J, 2026-11-01: "every single one of those features is fire. We need all of them.")

Source of the list: SESSION Key (session.am/session-key, manual session.am/manuals/session-key), Tommy Rush / M.W.A.
Same features, our own UI (the faceplate) and our own code. Never copy their name, art, or text.

Defaults taken (decide list D-26b87e65f1, closed when J said "let's go"; J can flip any):
- macOS 12 stays supported; live system-audio listening needs 13+ and is hidden on 12.
- Window stays, plus a menu-bar readout.
- Quick wins first, then live listening, then DAW / Auto-Tune send.
- Licence feature skipped: Beat Key is free.

Standing order (J, 2026-11-01 20:14): build ALL of it, any order, any batching, until done, even overnight. Never stop to ask "next section?". Only real blockers (a password, a purchase, a hands-on step) go to J, batched in one message.

## 1. Quick wins (analysis)
1.1 Decimal BPM (e.g. 140.82) for files, alongside the rounded value.
1.2 Half / double tempo: click the BPM to cycle x0.5 / x1 / x2.
1.3 Tuning offset in cents vs reference pitch; presets 432 436 438 440 442 444 450 Hz + custom 400-480. Shown only when the offset is under 45 cents and confidence is enough.
1.4 More inputs: FLAC, OGG, CAF, M4A/AAC, and the audio track of MP4 / M4V / MOV (ffmpeg already decodes these; open the drop filter).
1.5 MIDI files in: key from note histogram, tempo from tempo events; ignore embedded key signatures.
1.6 Recent readings: last 30, persisted, clickable to reload.
1.7 Analyze a File… menu item + picker, and "Analyze with Beat Key" for a file selected in Finder (Services / Quick Action).
1.8 Confidence states on the LCD: locked (green) / unsure (amber, shows candidates) / listening (red). Top-3 keys stays the headline.

## 2. Menu bar
2.1 Menu-bar readout ("Ebm 128") with the confidence state.
2.2 Global shortcuts, re-recordable (start listening, analyze file, send to DAW).
2.3 Open at login (SMAppService on 13+, LaunchAgent on 12).

## 3. Live listening
3.1 System audio capture (ScreenCaptureKit audio, macOS 13+), no recording saved.
3.2 Mic / any input device and channel.
3.3 Streaming key + BPM with auto-lock after 6 s locked, "start over after a gap".

## 4. Send out
4.1 Export a standard MIDI file carrying tempo + key (works for any DAW).
4.2 Send key + tempo into the DAW: Pro Tools, Logic, Ableton 12, Studio One/Studio Pro, Bitwig; tempo only FL, Reason, Reaper; Cubase via MIDI Remote. Research each DAW's route first.
4.3 Analyze the selected clip in Pro Tools (PTSL, we already drive it), Ableton, Reaper.
4.4 Send key + scale to Auto-Tune "AutoKey Listen" instances. SESSION Key does it from outside Antares, so it is possible; research the transport (believed: local network, same as Antares Auto-Key Mobile), then implement.

## 5. Accessibility
5.1 Colour-blind shapes per state (octagon / triangle / circle) and a high-contrast readout.

## 6. Docs + release
6.1 README + friends page + FLR handoff list the new features; top-3 keys stays first.
6.2 Release per app/RELEASING.md (bump last number).
