# Send to DAW (plan 4.2, 4.3) and Auto-Tune AutoKey (plan 4.4): research

2026-11-01. Research only, no app code. Evidence tags: **[doc]** = a page fetched/searched this session; **[known]** = from prior knowledge, not re-verified here (verify before building); **[local]** = read on this Mac.
Web search was thin for several DAWs; every "[known]" row needs a doc check before implementation.

## 1. What every DAW can take today: the MIDI file (plan 4.1, built)

`MidiExport` writes a format-0 SMF with set-tempo (FF 51), 4/4 (FF 58) and key signature (FF 59). Importing it carries tempo in most DAWs but usually asks first:
- Logic: importing into an existing project skips tempo; opening the file as a new project, or answering the "import tempo" prompt, keeps it. [doc: Apple Community threads, discussions.apple.com/thread/2098750, discussions-jp-prz.apple.com/thread/251126695]
- FL Studio: Import MIDI dialog has an "import tempo" choice; dragging into an existing project may not change project BPM. [doc: image-line.com/fl-studio-learning/fl-studio-online-manual/html/automation_midiimport.htm]
- Pro Tools: Import MIDI offers tempo map import, and key signatures are importable/exportable with MIDI data. [doc: apps.avid.com/proToolsFirstHelp/version12.3/enu/Pro%20Tools%20First%20Help/sess7.import.17.20.html]
- Bitwig: reports that MIDI import ignores tempo in some cases; unconfirmed. [doc: forum/KVR threads only]
- Cubase: "Import tempo" exists for MIDI import ([doc: forums.steinberg.net/t/import-tempo-midi-to-template/755665]).

## 2. Per DAW: route for an outside Mac app to set tempo and key (plan 4.2)

| DAW | Best route | Sets tempo | Sets key | Doc | Confidence |
|---|---|---|---|---|---|
| Pro Tools | PTSL (gRPC on localhost, port 31416 [known]); the owner already drives it (protools-assistant / pt-stems). Tempo and key rulers are reachable: SoundFlow's RPD Utilities uses SDK commands that set tempo, time-signature and key rulers at the timeline selection. Exact CId names to be read from the PTSL .proto in the SDK (py-ptsl `--list` prints them against a live Pro Tools). Fallback: Import MIDI with tempo map. | yes | yes (key ruler) | https://developer.avid.com/audio/ptsl/ (SDK, login), https://py-ptsl.readthedocs.io/, https://soundflow.org/store/pkg/rpd-utilities | route exists [doc]; command names unverified |
| Logic Pro | No tempo/key scripting API [known; AppleScript dictionary has no project tempo]. Options: (a) Accessibility UI scripting of the Project Settings > Tempo / Key Signature (Logic 11+ has a project key/scale in the transport/LCD) ; (b) generate the .mid and open it as a new project; (c) Logic "Smart Tempo" off, then type into the LCD tempo field via AX. | via AX or MIDI open | via AX (fragile) | https://support.apple.com/guide/logicpro/ | AX route is a guess; MIDI route [doc] |
| Ableton Live 11/12 | Remote Script (Python, runs inside Live) exposing OSC: AbletonOSC listens on UDP 11000, replies 11001; `/live/song/set/tempo`. Live Object Model has `Song.tempo`, `Song.root_note` (0 to 11), `Song.scale_name` (Live 12). AbletonOSC lists getters for root_note/scale_name but no setters in its README, so a tiny fork or own Remote Script adds them (`song.root_note = n`, `song.scale_name = "Minor"`). Live 11 has no scale API: tempo only. Install into ~/Music/Ableton/User Library/Remote Scripts, enable in Preferences > Link/Tempo/MIDI. | yes | Live 12 only (own script) | https://github.com/ideoforms/AbletonOSC , https://docs.cycling74.com/max8/vignettes/live_object_model | tempo [doc]; key setter [doc: LOM lists props, setters unverified] |
| Studio One / Studio Pro | No public scripting for song tempo [known]. Route: MIDI file import (Studio One offers import tempo/time-signature), or AX scripting of the Tempo field in the transport bar. Key: Studio One 6.5+ has a Chord track / song key; no API, AX only. | MIDI import / AX | AX | https://support.presonus.com/ | unverified |
| Bitwig | Controller API (Java/JS extension, runs in Bitwig): `host.createTransport().tempo()` is a settable Parameter [doc: KVR thread, keithmcmillen tutorials]; scripts need an observer first (`markInterested`) and values arrive async. Controller extension receives commands from our app over local UDP/OSC (Bitwig ships an OSC example). Key/scale: no transport API found; Bitwig clips have scale in the note grid, not project key. | yes | no API found | https://keithmcmillen.com/blog/controller-scripting-in-bitwig-studio-part-3/ , https://www.kvraudio.com/forum/viewtopic.php?p=8084867 | tempo [doc]; key: none found |
| FL Studio | MIDI Scripting API (Python, device script): has transport functions; tempo setting is via `general`/`transport` module [known; official page found lists callbacks only]. Feed it from our app via a virtual MIDI port (CoreMIDI) carrying CC/sysex the script decodes. Key: none (FL has no project key). MIDI file import with "import tempo" is the zero-code route. | yes (script + virtual MIDI) | no | https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/midi_scripting.htm | partly [doc] |
| Reason | No scripting for project tempo [known]; Remote codecs map control surfaces only. Route: MIDI file import (Reason imports tempo from MIDI [known, unverified]) or AX on the transport tempo field. | MIDI / AX | no | https://www.reasonstudios.com/ | unverified |
| Reaper | Best-supported. ReaScript: `SetTempoTimeSigMarker(proj, ptidx=-1, ...)` adds/sets tempo markers (AddTempoTimeSigMarker deprecated); `SetCurrentBPM`. Reach from outside via (a) a ReaScript (Lua/Python) polling a watched JSON/file or UDP socket (reaper has the SWS/ReaImGui-free `reaper.defer` loop), (b) the OSC control surface (Preferences > Control Surfaces > OSC; pattern file Default.ReaperOSC; "allow binding messages to REAPER actions"; tempo patterns are in the pattern config), (c) the Web Remote (HTTP `GET /_/<action>`; can also run ReaScript-defined actions). No key signature API: write a marker/region or project note instead. | yes | no (marker/note) | https://reaper.fm/sdk/reascript/reascripthelp.html , https://www.reaper.fm/sdk/osc/osc.php | tempo [doc]; key: none |
| Cubase / Nuendo | MIDI Remote API (JS, runs in Cubase): `page.mHostAccess.mTransport` and DirectAccess (API 1.2/1.3) reach host objects; fed from our app by a virtual MIDI port. Tempo is reachable through the Transport/Tempo track objects only by DirectAccess; key signature is not exposed [unverified]. Fallback: MIDI import with tempo. | likely via DirectAccess | no | https://forums.steinberg.net/t/midi-remote-api-1-3-updated-docs/1028346 | partial [doc] |

Reading the table: tempo has a real programmatic route in Pro Tools, Ableton, Bitwig, Reaper; key has one in Pro Tools and Live 12 only. Everything else is "export MIDI and let the user import it" (shipped) or Accessibility scripting (fragile, needs the Accessibility permission, breaks across DAW versions). Recommendation for build order: Pro Tools (PTSL, already in house), Reaper (ReaScript + UDP), Ableton (Remote Script, own setters), then Bitwig; leave the rest on the MIDI file.

## 3. Reading the selected clip's audio (plan 4.3)

- Pro Tools: PTSL has selection and export commands (export selected / consolidate and bounce to a path, and "get selection" for the timeline range); the app then analyses the exported file. Same machinery as pt-stems. [known; confirm CId names in the SDK .proto]
- Ableton: AbletonOSC `/live/clip/get/file_path` takes track_id, clip_id and returns the source audio path of an audio clip (`/live/clip/get/is_audio_clip` checks the type). Selected clip: `Song.view.detail_clip` in the LOM gives the clip in the Detail view. Warp markers/offset are not applied by the path, so analyse the source file or accept that. [doc: AbletonOSC README]
- Reaper: ReaScript `GetSelectedMediaItem` -> `GetActiveTake` -> `GetMediaItemTake_Source` -> `GetMediaSourceFileName` gives the path; `CreateTakeAudioAccessor` / `GetAudioAccessorSamples` gives the processed samples including item offset and fades. [doc for CreateTakeAudioAccessor: reaper.fm/sdk/reascript/reascripthelp.html; other names known]

## 4. Auto-Tune "AutoKey Listen" (plan 4.4)

### Finding: the local route is a file, not a network port

Strongest evidence (all [local], read-only, nothing launched):

1. Both the Auto-Key plug-in and Auto-Tune Pro contain the literal path `~/Music/Audio Music Apps/Temp/Auto-Key.handoff` (`strings` on `/Library/Audio/Plug-Ins/VST3/Auto-Key.vst3/Contents/MacOS/Auto-Key` and `.../Auto-Tune Pro.vst3/Contents/MacOS/Auto-Tune Pro`; also in the AU components).
2. Auto-Tune Pro links the class `AntaresCommon::FileSystemWatcher::Listener` (a directory watcher) next to the string `Auto-Key.handoff`; Auto-Key carries the property names `KeyClass`, `KeyType`, `ReferencePitch`, `TempoBPM` right before the path string.
3. The file exists on this Mac, written 2026-10-14 22:42 (so a "send" click happened then), 224 bytes, CRLF XML:
   ```
   <?xml version="1.0" encoding="UTF-8"?>

   <PROPERTIES>
     <VALUE name="KeyClass" val="11"/>
     <VALUE name="KeyType" val="1"/>
     <VALUE name="ReferencePitch" val="450"/>
     <VALUE name="TempoBPM" val="-1"/>
   </PROPERTIES>
   ```
   This is JUCE `XmlElement` PROPERTIES/VALUE format (JUCE `NamedValueSet` XML). `TempoBPM -1` = no tempo; `ReferencePitch` is the detected Hz.
4. Auto-Tune Pro's own tooltip says the Detune (reference pitch) is **not** transmitted automatically, and that Auto-Key "can send the key and scale to multiple instances of Auto-Tune with a single click": one file watched by every instance fits that, a network port would not need a temp file. The Pro preference "Auto Key Detection" (`AutoKeyDetectPref_ID`, tooltip `TT PrefsAutoKey`) is the switch that makes an instance accept it.
5. Antares Central (`com.antarestech.antares-central`, `/Applications/Antares Audio Technologies/Antares Central.app`, plus `Auto-Tune Central.app` Electron and a LaunchAgent `com.antares.antares-central-service`) contains no `_tcp` service, no localhost/127.0.0.1, no "handoff" or "AutoKey" strings: Central is account/licence/updater, not in the key path. No Bonjour types, OSC addresses, XPC names or distributed-notification names for AutoKey were found in either plug-in.

Likely mapping (to confirm): KeyClass = tonic pitch class 0..11 (11 = B, C = 0), KeyType = scale (1 plausibly Minor, 0 Major, maybe higher values for other scales). The sample (11, 1) = B minor, 450 Hz.

Implementation sketch once confirmed: write the same XML to `~/Music/Audio Music Apps/Temp/Auto-Key.handoff` (atomic write, CRLF) while the user has Auto-Tune's "Auto Key Detection" enabled; Auto-Tune instances in any DAW pick it up via the file watcher. SESSION Key most likely does exactly this, which fits "works from outside Antares".

Mobile route (for contrast): Auto-Key Mobile -> Antares account/internet -> Antares Central -> plug-in (help.antarestech.com article 41113047035796). Not needed for a local app.

### What to capture live to confirm (no sudo needed for most)

1. Value mapping: with Auto-Key open, set known keys (C major, then A minor, F# major, Eb minor, a non-major/minor scale) and click "send"; after each, `cat "$HOME/Music/Audio Music Apps/Temp/Auto-Key.handoff"` and note KeyClass/KeyType. This is the whole mapping.
2. Does Auto-Tune react to a hand-written file? Edit the file manually (touch after edit) while an Auto-Tune Pro instance has Auto Key Detection on; watch the Key/Scale fields change. Also test: does it need the file's mtime to change, does it delete the file after reading, does it work if the file is created fresh.
3. Confirm no network side channel: `sudo fs_usage -w -f filesys <Auto-Key host pid>` shows the write (needs sudo, hand to J), or without sudo `fswatch "$HOME/Music/Audio Music Apps/Temp"` / `log stream --predicate 'process == "<DAW>"'` while clicking send; `lsof -i -P -n | grep -i <DAW>` before and after for any listening socket; `nettop -p <pid>`.
4. Optional if anything networked turns up: `sudo tcpdump -i lo0` and `dns-sd -B _services._dns-sd._udp` during a send.
5. Check what the ARA / mobile path writes into `~/Music/Audio Music Apps/Temp/Antares*` (AntaresData, AntaresAnalytics folders exist, currently empty).

### Risks
- Undocumented, Antares can change the filename/format in any update (re-check on Auto-Tune version bumps; ship a Doctor line).
- The path is under ~/Music: a sandboxed Beat Key would need the right entitlement; the app is not sandboxed today (verify in app/entitlements.plist).
- Reference pitch is not applied by Auto-Tune from the file (per its tooltip); Beat Key's tuning offset would remain a manual Detune step.

## 5. Checked while building (2026-11-01, plan 4.2 / 4.3)

- **Pro Tools: PTSL has no tempo or key setter.** Every CommandId in the SDK 2026.04 `PTSL.proto` (0 to 165) was read: tempo/key appear only as track types, as `SessionDataImport.tempo_meter_map` / `key_signature_choed_map` (import from another session), and in time conversion. So the table's "sets tempo/key: yes" for Pro Tools was wrong; Beat Key gives Pro Tools the MIDI file plus the current session tempo read back with `CId_GetTimeAsType` (beat 1 in samples vs `CId_GetSessionSampleRate`). Analyze Selection uses `CId_ExportClipsAsFiles` (selected clips, WAV, temp folder). [doc: PTSL.proto]
- **Ableton:** LOM `Song.tempo` (20-999), `Song.root_note` (0-11), `Song.scale_name` are get/set/observe; `Song.View.detail_clip`; `Clip.file_path` (audio clips only). [doc: docs.cycling74.com/apiref/lom/song, song_view, clip]
- **REAPER:** Lua signatures for `SetCurrentBPM`, `Get/SetTempoTimeSigMarker`, `GetSelectedMediaItem`, `GetActiveTake`, `TakeIsMIDI`, `GetMediaItemTake_Source`, `GetMediaSourceParent`, `GetMediaSourceFileName`, `Master_GetTempo`, `reaper.defer` read from reascripthelp.html. `__startup.lua` auto-run is not in the official ReaScript pages, so Beat Key asks the person to run the listener from the Action list. [doc]
- **Bitwig:** `host.addDatagramPacketObserver(name, port, fn)`, `host.sendDatagramPacket(host, port, bytes)`, `transport.tempo().value().setRaw(bpm)` confirmed from API stubs and working public scripts (no official page reachable). [code: github justlep/bitwig api stubs, remymazmanian/bitwig-control-deck]
