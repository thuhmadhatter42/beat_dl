# Menu-Bar Key/BPM Listener — Design Spec

**Date:** 2026-09-12 · **Status:** Draft, for J's review — nothing built yet.

## 1. Goal

An always-on macOS menu-bar app that listens to whatever is playing through the current
interface's main outs, detects BPM and key the moment a new song starts, and shows a compact
readout ("140 · A min") in the menu bar. Clicking it opens a panel with key relations, a Camelot
code, and an Auto-Tune-EFX-style piano roll you can play against and narrow down by ear.

## 2. Architecture (text diagram)

```
main-outs audio (CoreAudio process tap, system-wide)
        v
   ring buffer (rolling N seconds, mono+stereo, stored for re-analysis)
        v
song-boundary detector (silence gap + spectral novelty; MediaRemote hint, optional/best-effort)
        v
   analyzer (BPM: Essentia TempoCNN | Key: Essentia HPCP+bgate) -- via persistent helper process
        v
   app state (current song: BPM, key top-3, confidence, Camelot; manual overrides)
        v
menu bar text  <-- click -->  panel (key relations, Camelot, piano roll + elimination)
```

## 3. Audio capture

**Mechanism — CoreAudio process tap, system-wide global tap, macOS 14.2+ (Sonoma).**
Confirmed by reading Artemis's own shipped, working code (not invented):

- `/Users/jshriver/artemis/app/src/taps/taps.m` (2012 lines) and
  `/Users/jshriver/artemis/app/apptap.m` (583 lines) both build real taps today with:
  `CATapDescription` (`#import <CoreAudio/CATapDescription.h>`, taps.m:32),
  `AudioHardwareCreateProcessTap` (taps.m:1421), `AudioHardwareCreateAggregateDevice`
  (taps.m:1501) with dict keys `kAudioAggregateDeviceTapListKey` / `kAudioSubTapUIDKey` /
  `kAudioSubTapDriftCompensationKey` / `kAudioAggregateDeviceMainSubDeviceKey` (taps.m:1482-1501),
  and `AudioHardwareDestroyProcessTap` / `AudioHardwareDestroyAggregateDevice` for teardown
  (taps.m:1140, 1145).
- Artemis's tap is **per-app**: `[[CATapDescription alloc] initStereoMixdownOfProcesses:...]`
  (taps.m:1355) — a named list of HAL process objects for one app, muted at the speakers.
  Listing apps uses `kAudioHardwarePropertyProcessObjectList` (cited in
  `/Users/jshriver/artemis/BUILD-LOG.md:246` and used through taps.m).

**What keybar needs is different: the whole main-outs mix, not one app.** That is the
*global* tap variant, `initStereoGlobalTapButExcludeProcesses:` — confirmed via WebSearch
(Apple's own `AudioHardwareCreateProcessTap(_:_:)` doc page, and the sample project
insidegui/AudioCap, https://github.com/insidegui/AudioCap) as a real `CATapDescription`
initializer: exclusive=false semantics, tap everything except the PIDs you name (pass keybar's
own pid, or none). It mixes down to stereo the same way Artemis's per-app tap does. Wrap it in a
private, unstacked `AudioHardwareCreateAggregateDevice` whose **main sub-device is the current
default output device** (the "interface"), same dict shape Artemis already uses, and read the
aggregate's input stream — this is the documented AudioCap pattern, not Artemis-specific.

One correction to the brief: the property for PID→process-object lookup is
`kAudioHardwarePropertyTranslatePIDToProcessObject` (confirmed via AudioCap's
`CoreAudioUtils.swift` and Apple forum threads) — **not** "TranslateUIDToProcess" as guessed in
the brief. Artemis's own code does the equivalent lookup differently (it walks
`kAudioHardwarePropertyProcessObjectList` and reads each object's pid), so this is the one API
name in this spec that comes from WebSearch, not from Artemis source — treat it as verified-but-external
until it's actually called in Xcode and the symbol resolves.

**Reuse verdict: pattern, not artifact.** Artemis has no library target, XPC service, or shared
framework around its tap code — `taps.m`/`apptap.m` are compiled straight into the monolithic
`artemis` binary (`app/build.sh`), with no public header meant for another process to link. There
is nothing to `import` or link from keybar. What transfers is the *proven pattern* (the exact
aggregate-device dictionary shape, the drift-compensation keys, the mixdown gain-compensation math
in `art_taps_makeup_gain`, taps.h:403-437, and the "first tap raises the System Audio Recording
prompt, signing identity must stay stable" lesson, taps.h:60-63) — copy and adapt the ~150 lines
of tap/aggregate setup, don't try to reuse a build product.

**Selecting "main outs of the current interface":** read the system default output device
(`kAudioHardwarePropertyDefaultOutputDevice`) and use it as the tap aggregate's main sub-device —
this naturally tracks whatever interface macOS currently has selected, with no per-app picking.
Per-app taps (Artemis's actual model, `initStereoMixdownOfProcesses:` + `kAudioHardwarePropertyProcessObjectList`
to list running apps) are deferred to phase 4 and would reuse the *pattern* from `taps.m`/`apptap.m`
directly, since at that point it is the same problem Artemis already solved.

**Permissions:** first tap creation raises the system "System Audio Recording" TCC prompt — same
one Artemis's users see (taps.h:60-63). Artemis's `Info.plist` carries
`NSAudioCaptureUsageDescription` (and `NSMicrophoneUsageDescription`) — confirmed at
`/Users/jshriver/artemis/app/build.sh:70-72` — keybar's Info.plist needs the same key with its own
usage string. No sandbox entitlement is involved: Artemis is not App-Sandboxed (it is
self-signed/Developer-ID style, see §7), and the permission is TCC-gated by a **stable signing
identity**, not an entitlement — an ad-hoc signature (`codesign -s -`) changes every build and
re-prompts the user every time (`app/build.sh:110-119`), which keybar must avoid the same way
Artemis does (a fixed self-signed cert in the login keychain, `app/build.sh:113`).

## 4. Analysis

**Engine: bundled Essentia (Python) as a persistent helper process — option (a).**
`bpm.py` (`/Users/jshriver/dev/beat_dl/bpm.py`) already implements the benchmarked pipeline:
Essentia `TempoCNN` (`deeptemp-k16-3.pb`) for BPM and Essentia HPCP (36-bin, spectral whitening,
detuning correction) correlated against Faraldo's `bgate` profiles for key. Per
`docs/research/bpm-detection-research.md`: 87.5% Acc1/100% Acc2 for BPM (vs 30%/55% for the old
librosa code); per `docs/research/key-detection-research.md`: 85.1 weighted/79.5% exact for key
(vs 55.4/43.6 old code). Both numbers are the reason to keep using this exact pipeline rather than
reinvent it.

Rejected alternatives, with reasons:
- **(b) Essentia C++ linked directly** — would drop the ~0.8 s Python interpreter/import cost per
  call, but still needs libtensorflow linked in for TempoCNN, so the bundle-size win is small,
  and building Essentia+TF from source with a Swift bridge is undocumented, unproven work with
  nothing in this repo to build on. Worth revisiting only if the Python helper's latency proves
  unacceptable in practice.
- **(c) Native Swift reimplementation** — the *key* half (HPCP + bgate correlation, `bpm.py:144-197`)
  is genuinely small DSP (windowing, FFT via vDSP, spectral peaks, whitening, 36-bin fold,
  correlation against two 12-value profile vectors) and could plausibly be ported without losing
  accuracy, since it's pure math with no learned model. The *BPM* half cannot be cheaply ported:
  TempoCNN is a trained CNN over mel-scaled 11025 Hz audio, and there is no verified path here to
  run that model natively (a Core ML conversion of `deeptemp-k16-3.pb` is unverified — not
  attempted, not benchmarked, flag as a real risk if pursued later). Splitting engines (native
  key, Python BPM) would mean shipping the Python helper anyway for BPM, so it buys little at
  phase 1-3.

**Recommendation:** ship the Python + `essentia-tensorflow` helper (a), run once and kept **warm**
(not re-launched per song — `bpm.py`'s own numbers show ~0.8 s import + ~0.8 s decode per fresh
process, `docs/research/bpm-detection-research.md`:9-10), talking to the Swift app over stdin/stdout
or a local Unix socket, fed raw PCM chunks from the ring buffer instead of a file path (a change to
`load_audio_essentia`, `bpm.py:122-131`, needed since the source is live audio, not a file).

**Latency to first readout — honest gap, not benchmarked for streaming audio.** Every accuracy
number in both research docs is for **whole-track, offline** analysis (`docs/research/key-detection-research.md`
line 116: "whole track, not loudest 60s: −8 to −17 points every time it was tried" — this is why
`bpm.py` no longer crops). Nobody has benchmarked what accuracy looks like on the first 15/30/60
seconds of a *playing* song, because bpm.py has only ever run after a full download. Recommend
(not measured): first pass at ~20-30 s of buffered audio (long enough for one verse), shown at a
capped/low confidence; re-analyze at 60 s and again at 120 s or song end, confidence rising each
time using the same `agree` metric `bpm.py` already computes (share of 10 s HPCP windows whose
own winner matches the running winner, `bpm.py:93-117`, `top3_with_confidence`). This needs its
own small bench before J trusts the number on screen — call it out as an open question (§8).

**Confidence display:** reuse `bpm.py`'s existing top-3 + percentage output as-is (`bpm.py:279-283`
format, e.g. "Am (74.2%)") — it is already calibrated against 39 EDM clips (measured bins in
`docs/research/key-detection-research.md` lines 231-235: ≥0.90 → 86% right, 0.85-0.90 → 85%,
0.75-0.85 → 76%).

## 5. UI

**Menu bar text:** `"<bpm> · <key>"`, e.g. `140 · A min` (major keys show no suffix, e.g.
`128 · C`). Matches the Claude usage-item pattern J named: small, static-looking text, no icon
needed beyond what's legible at menu-bar font size. Shows nothing (or "···") before the first
confident readout; updates in place as re-analysis raises confidence, never flickers between
different keys once one is shown — the LAST accepted reading stays until a genuinely new one
replaces it (per §5's manual-override rule, a user override sticks over this too).

**Panel (click target), top to bottom:**
1. Detected key (e.g. "A minor"), its **relative** (A minor → C major), a **fifth up** from the
   detected key (A minor → E minor), and a **fifth up from the relative** (C major → G major).
   Pitch-class arithmetic (12 = C, using `bpm.py`'s own `NOTES` order, `bpm.py:18`):
   - relative major of minor `pc`: `(pc + 3) % 12`, mode flips to major (A=9 → 9+3=12%12=0=C). ✓.
   - relative minor of major `pc`: `(pc - 3) % 12`, mode flips to minor.
   - fifth up (either mode, same mode): `(pc + 7) % 12`.
   So: detected A minor (pc=9) → relative C major (pc=0) → fifth-of-detected E minor (pc=4) →
   fifth-of-relative G major (pc=7).
2. **Camelot code** beside the key (§5b).
3. **Piano roll**, Auto-Tune-EFX-styled (per WebSearch on Antares' product pages — MusicTech and
   Sound on Sound reviews describe it: EFX+ ships a one-octave keyboard graphic at the bottom of
   the plug-in window, current detected pitch highlighted, and notes can be clicked on/off to
   build a custom scale; only the described behavior is used here, no screenshot was available to
   copy pixel-for-pixel — treat the visual as "one octave of piano keys, clickable, one highlighted"
   and design keybar's version to that description, not a traced image).
   - Starts **chromatic**: all 12 keys active/lit.
   - **Click** a key → play that pitch as a synth tone (AVAudioEngine + AVAudioUnitSampler or a
     simple oscillator node) so the user can play along with the song and by ear rule notes out.
   - **Cmd-click** → toggles that note's active/inactive state (no tone played on a deactivate
     click — pure toggle).
   - **Candidate-key ranking**: treat each of the 24 keys as its pitch-class set (7 of 12 notes).
     For each key, score = (count of active notes that ARE in the key) − (count of active notes
     that are NOT in the key). Rank all 24, show the top 3 by name (e.g. "C major, A minor, G
     major"). Recomputed on every click/Cmd-click.
   - The moment the detector (§4) reports its own confident key, the roll **auto-sets** to only
     that key's 7 notes active, overriding whatever manual state existed — this is the "auto-set
     roll on detection" behavior.
   - **Manual override sticks until next song**: if the user then clicks/Cmd-clicks after
     auto-set, their manual pattern is not overwritten again by a later re-analysis pass of the
     *same* song (§4's confidence-rising re-analysis) — only a genuinely new song boundary
     (§3 detector) resets the roll back to chromatic and lets auto-set fire again.

### 5b. Camelot code

Standard Camelot wheel (Mixed In Key's system; confirmed via WebSearch — vibesdj.io and
musicianwave.com both describe the ring: outer ring = major keys labeled "B", inner ring = minor
keys labeled "A", numbered around the circle of fifths). Mapping table (well-established, not
proprietary — this is the public convention MIK popularized):

| Camelot | Key | Camelot | Key |
|---|---|---|---|
| 1A | Ab minor | 1B | B major |
| 2A | Eb minor | 2B | F#/Gb major |
| 3A | Bb minor | 3B | Db major |
| 4A | F minor | 4B | Ab major |
| 5A | C minor | 5B | Eb major |
| 6A | G minor | 6B | Bb major |
| 7A | D minor | 7B | F major |
| 8A | A minor | 8B | C major |
| 9A | E minor | 9B | G major |
| 10A | B minor | 10B | D major |
| 11A | F# minor | 11B | A major |
| 12A | C# minor | 12B | E major |

Shown next to the key line in the panel, e.g. "A minor · 8A".

## 6. Project layout

Not a folder under `beat_dl` — this is a standalone macOS app with its own build/sign/release
cycle, unrelated to beat_dl's download pipeline; a sibling repo. Proposed names (J picks):
**`keybar`** or **`tonewatch`**. Version file `VERSION` at repo root, starting `0.1.0`, every edit
+1 on the last number per J's global scheme (`~/.claude/CLAUDE.md` — "0.x.y until the first real
ship... every edit is a new version").

## 7. Build phases

**Phase 1 — tap + readout only, no panel.** System-wide tap (§3) → ring buffer → Python helper
(§4) → menu bar text. Smallest thing J can hit play on a song and see "140 · A min" appear.
*Go/no-go:* play three known songs (different BPM/key), menu bar text matches what `bpm.py` prints
for the same file downloaded separately, within the confidence windows in §4.

**Phase 2 — panel + key relations.** Click opens the panel; relative/fifths math (§5.1) and
Camelot code (§5b) shown, static (no roll yet).
*Go/no-go:* for 5 known keys, relative/fifth/Camelot values match hand-computed pitch-class math.

**Phase 3 — piano roll + elimination.** Clickable/Cmd-clickable roll, tone playback, live
candidate-key ranking, auto-set on detection, manual-override persistence.
*Go/no-go:* deactivating notes not in the true key narrows the top-3 to include the true key
within 3-4 clicks on a test song; auto-set fires once, sticks until a genuinely new song plays.

**Phase 4 — per-app taps.** Swap the global exclude-tap for Artemis's actual per-app model
(`initStereoMixdownOfProcesses:` + app listing) so a specific app (e.g. just Spotify) can be
isolated from other system sound — directly reusing the pattern in
`/Users/jshriver/artemis/app/src/taps/taps.m` and `apptap.m`.
*Go/no-go:* isolate one app playing music while a second app plays unrelated noise; keybar reads
only the first app's audio.

## 8. Open questions for J

1. Which OS API path should phase 1 target first — global exclude-tap (simplest, matches "system
   output on outs 1-2" literally) or borrowing Artemis's per-app tap from day one? This spec
   assumes global-tap-first, per-app in phase 4 — confirm that ordering is right.
2. Should the BPM/key readout persist across songs (a history list) or always show only the
   current song? Changes whether state needs a store at all in phase 1.
3. Octave/latency tradeoff (§4): is a lower-confidence reading at ~20-30 s acceptable, or should
   the menu bar show nothing until a higher-confidence full-track-equivalent pass completes later
   (accurate but late)? This decides the whole re-analysis cadence.
4. Repo name — `keybar`, `tonewatch`, or something else?
5. Should Sofia (2013 Mac Pro, macOS 12.7 per `/Users/jshriver/artemis/.claude/rules/console-model.md`)
   be a target at all? It cannot run the tap API (needs 14.2+) or essentia-tensorflow's py3.14
   wheel (needs macOS ≥ 15) — this app may simply be MacBook-only.

## 9. Risks

- **TCC prompt + signing identity stability**: exactly Artemis's own lesson (`app/build.sh:110-119`)
  — ad-hoc signing re-asks the System Audio Recording permission every build; needs a stable
  self-signed (or real Developer ID) identity from day one, not "figure it out later."
- **Bundle size**: `essentia-tensorflow` unpacks to ~420 MB (bundled libtensorflow,
  `docs/research/bpm-detection-research.md`:146) — large for a menu-bar utility; a python
  interpreter framework adds more. This is the direct cost of choosing option (a) in §4.
- **Python bundling**: no py2app/PyInstaller work exists yet in this repo for beat_dl or Artemis;
  building a relocatable, signed, notarizable Python+Essentia bundle is new engineering, not proven
  anywhere in either project.
- **Apple Silicon vs Intel**: `essentia-tensorflow` needs macOS ≥ 15 for the py3.14 wheel on Intel,
  ≥ 14 for py3.13/3.12 (`docs/research/bpm-detection-research.md`:32-34); Sofia is 12.7 and would
  need an older Python + an older, less-tested wheel, or would not run this app's analysis path at
  all (see open question 5).
- **No notarization/Developer ID set up today**: Artemis itself ships self-signed
  ("Four Letter Records Artemis", `app/build.sh:113`) with ad-hoc as a fallback — there is no
  evidence in this repo of an actual Apple Developer ID / notarization pipeline anywhere in
  `/Users/jshriver/artemis` (installer/publish.sh signs the **update feed**, not the app itself,
  with `artemis-sign.crt`, a separate self-issued cert for update-pinning, not code signing). A
  `/Applications` app tapping system audio will draw more Gatekeeper scrutiny than a personal tool;
  budget for getting a real Developer ID if this is meant to be shared beyond J's own Macs.
- **MediaRemote is unreliable as even a hint**: confirmed via WebSearch — after macOS 15.4, Apple
  added entitlement checks in `mediaremoted` that deny unentitled clients Now Playing info; public
  workarounds exist (a perl-adapter trick using an already-entitled system binary, JXA, or SIP-off
  code injection) but are fragile and not something to build a permission-sensitive
  `/Applications` app around. Treat it as optional/best-effort only, never load-bearing, and expect
  it may simply not work on whatever OS version ships.
