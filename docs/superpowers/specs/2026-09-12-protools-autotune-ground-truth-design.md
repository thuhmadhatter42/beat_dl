# Pro Tools Auto-Tune Ground-Truth Harvester — Design

**Date:** 2026-09-12
**Status:** Draft — read-only design, nothing built or run against Pro Tools.

## 1. Goal + why

J has thousands of mixed PT sessions where the artist ran Antares Auto-Tune on the lead vocal.
Auto-Tune's Key+Scale and the session tempo are already-labelled ground truth sitting inside
sessions J owns — free, and closer to his actual catalog (hip-hop/R&B) than the EDM-only public
sets (`docs/research/key-bench/`, `docs/research/bpm-bench/`) currently grading `bpm.py`.
Harvesting them into `(beat-only WAV, key, BPM)` triples grows the benchmark with in-domain data.

## 2. Pipeline

**Proto** = `/Users/jshriver/ProTools SDK/stem-bouncer/pt_stems/proto/PTSL.proto` — the only
authoritative PTSL command/field list (the compiled `PTSL_pb2.py` doesn't surface plain command
names as text, so the `.proto` was checked directly, not assumed from `client.py` usage).

### 2.0 Discovery (offline, no PT)
`mdfind "kMDItemFSName=*.ptx"` per J's spec. Spotlight can be disabled on an external volume —
check `mdutil -s /Volumes/<vol>` before trusting a zero-result `mdfind`; fall back to
`find /Volumes/<vol> -iname '*.ptx'`. Not run against any real drive yet (would touch drives).

### 2.1 De-dup — newest .ptx per song (offline)
**PROVEN, reuse verbatim:** `pt_stems/session_picker.py:pick_latest_ptx()` already ranks by the
`(YY-M-D)` filename token then `mixNa` version (`mix7a` > `mix6a` > bare `MASTER`) and excludes
`Session File Backups/`. `pt_stems/naming.py:parse_song_artist()` pulls `(title, artist)` from the
`"(YY-M-D) Title (Artist)"` folder convention (same one `artist_latest` bounce filenames use).
Where a drive isn't one-folder-per-song, fall back to `~/.claude/skills/artist_latest/SKILL.md`'s
model: song-named folder = song (complete); generic/dated folder = session (demo per song inside).
That skill's known bug applies here too — an artist-named folder (`(23-8-18) WOE`) must not be
read as a song called "WOE".

### 2.2 Open session, check Auto-Tune active/inactive/bypassed
**Proven primitives:** `CId_OpenSession` (`client.py:open_session()`) with the existing
Session-Notes/UAD dialog watchdog and `_latest_pt_app()` auto-launch (never hardcode a PT version).
**Plugin presence, unverified but promising:** `CId_ExportSessionInfoAsText` (Proto line 1167,
`include_plugin_list=true`) dumps text Avid describes as documenting "the plugins used" — could
name, per track, which sessions even have Auto-Tune before any clicking. **Not confirmed:**
insert-slot position or bypass state — a third-party parser of this export
([fantopop/pro-tools-session-info](https://github.com/fantopop/pro-tools-session-info)) shows a
`plugins_listing` section with no bypass field, and Avid's own description (via [Learn Music
Production](https://learnmusicproduction.substack.com/p/exporting-a-pro-tools-session-as-text))
says the list is "not a complete text description of every plugin parameter" — consistent with
`LEARNED-2026-08-28.md`'s established fact that PTSL cannot read insert/plugin state. Treat this as
a cheap presence pre-screen only.
**Active/bypassed/inactive — proven technique, unproven target:** `LEARNED-2026-08-28.md`'s
Master-insert method (screenshot Edit window — Mix window unset up — read insert color: active =
light gray/lit, bypassed = blue, inactive = greyed/italic) was verified on L2+Limitless, every
session, always inserts F–J. A vocal track's Auto-Tune slot position is not guaranteed constant, so
the whole insert column must be read, not one assumed slot. Confirm on trial session 1.
**Failure handling:** Auto-Tune bypassed/inactive on all 3 shortlisted tracks → recorded as
unreliable/no-evidence, never silently dropped (open question 4).

### 2.3 Find the 3 lead-vocal tracks
**Folder hierarchy — PROVEN:** `CId_GetTrackList`'s `Track.parent_folder_id`/`parent_folder_name`
(Proto, since PT 2024.10) is already walked in production by
`pt_stems/folder_bounce.py:plan_stems()`'s `chain()`/`artist()` to find a track's artist-folder
under `ALL VOX`. Reuse that walk to scope candidates to the `ALL VOX`/`VOCAL STEM` subtree (its
`_VOX_ANCHORS` constant) and exclude background/ad-lib buses.
**Name-pattern shortlist**, J's order (`hook` → `verse` → `LD`/`LD 1`/`LEAD` → artist's name): a
small classifier in the same style as `pt_stems/classifier.py`'s existing regex-fuzzy bus-name
matcher — new module, not yet written.
**Clip COUNT per track — UNPROVEN, the single biggest risk here.** Checked every PTSL surface
against the `.proto`, not assumed:
- `Track.track_attributes.contains_clips` (line 6492) is a **boolean**, not a count — all
  `folder_bounce.py`/`preflight.py` currently use.
- `CId_GetClipList` (`Clip` message, line 13177) returns clips for the **whole session with no
  track_id/track_name field at all** — every one of its 14 fields checked (`file_id`, `clip_id`,
  `clip_full_name`, `clip_root_name`, `clip_type`, `start_point`, `end_point`, `sync_point`,
  `group_name`, `src_start_point`, `src_end_point`, `transpose_semitones`, `transpose_cents`,
  `is_online`) — none link a clip to a track.
- `CId_GetEditSelection` returns only `in_time`/`out_time`, no count.
- **Best remaining candidate, unverified:** `CId_ExportSessionInfoAsText` with
  `include_track_edls=true` produces a per-track EDL; the fantopop parser confirms real exports of
  this kind parse into `channel, event, clip_name, start_time, end_time, duration, timestamp, state`
  rows — counting rows per channel would give a real per-track count with no GUI. Never run by this
  investigation (needs an open session). **This is the first thing to test in the trial** — one
  PTSL call, inspect the text.
- If that fails: fall back to visually counting clips in the Edit window — slow, and the reason
  this stays a 1/day cron rather than a batch.

### 2.4 Per-track: open Auto-Tune, screenshot, read Key/Scale/Retune Speed
**Opening the plugin window — the click is UNPROVEN here.** Nothing in `pt_stems/` opens an
insert's editor; the dialog watchdog only clicks named AX buttons on real dialogs (proper
Accessibility elements). An insert slot is custom-drawn, not a standard AX button — confirmed by
the LEARNED doc's need for a **pixel clicker** (`~/xobaloo/stems_work/xo_clicker2.py`,
screencapture region signature + Quartz CGEvent click) on Sofia, where AppleScript is blind over
SSH. On the MacBook the same coordinate-click approach should work (same non-AX problem, just not
SSH-blind) but is unproven for an insert slot specifically. **Checked and ruled out:** a
menu-driven alternative — no built-in `Window > ...` shortcut opens a selected track's plugin; a
2016 Avid forum thread ([DUC #419590](https://duc.avid.com/showthread.php?t=419590)) requests
exactly this and describes only a per-instance custom keybind, which doesn't scale across sessions
with varying insert positions. Insert-slot click is the only path.
Once open, `pt_stems/dialog_watch.py`'s `IGNORE_PREFIX = ("Edit:", "Mix:", "Plug-in:")` confirms PT
names a plugin's floating window `"Plug-in: <name>"`, so the new window can be found and
window-targeted (`screencapture -l <windowID>`, no Space switch) by that prefix.
**Reading the UI, unverified per-product:** no screenshot found, only text. Auto-Tune Pro/Access:
Key + Scale dropdowns, piano-keyboard scale editor, Retune Speed described in 2026 marketing as a
continuous ~0–400ms parameter (low=fast/robotic, high≈off) — consistent with J's "100 = off". Older
Auto-Tune EFX/EFX+/Artist/8 material describes a 3-position Slow(3ms)/Medium(25ms)/Fast(65ms)
control instead, which wouldn't map to "100" at all. **Which product J has is unverified — open
question 1.** Read the plugin window's own titlebar/header first to confirm product before
trusting a layout.
**Failure handling:** any UI text the vision read can't parse confidently → don't guess, record
unread and flag (same posture as the watchdog's "unknown modal → stop and ask").

### 2.5 Reliability check
Reliable only if all 3 agree on key+scale and none is effectively-off by retune speed. Record
disagreement verbatim (which tracks, which values), not a bare flag.

### 2.6 Session tempo (BPM)
**Confirmed absent:** no `Get*Tempo*`/`Get*BPM*` command anywhere in the full `CId_*` enum (every
name dumped and checked against the `.proto`). The only tempo-adjacent field,
`SessionDataImport.tempo_meter_map` (line 7607), is a write-side **import** flag, not a getter.
`ptformat` (2.7) also never mentions tempo. **Candidates, both unverified, cheapest first:**
1. `CId_ExportSessionInfoAsText` — untested whether its header carries tempo; test in the same call
   used for 2.2/2.3 (one PTSL call could settle three open questions at once).
2. Screenshot the Transport/Main Counter tempo field (`CId_SetMainCounterFormat` to
   `TLType_BarsBeats` first, both Get/Set proven to exist) and vision-read the BPM — same
   screenshot+read pattern proven for the Master check, unproven for this field.
**Tempo maps:** a session with tempo changes mid-song has no single BPM; `bpm.py`'s benchmark
format assumes one constant value. No PTSL getter proves a flat vs. changing map either — until
proven otherwise, treat a non-authoritative-looking tempo display as excluded, not guessed (risk 3).

### 2.7 Offline pre-screen via ptformat (no PT, for scale)
[`ptformat`](https://github.com/zamaudio/ptformat) (Damien Zammit, C++, GPL) parses `.ptx`/`.ptf`
directly: audio/MIDI track/region/source info + MIDI note events, PT versions 5–12(+). Its README
never mentions tempo, plugin/insert state, or plugin automation, and explicitly says **"No
groups"** (routing-folder structure) for PT10+. That matters specifically for J: his whole workflow
(`ALL VOX`, `VOCAL STEM`, artist sub-folders) is routing-folder-built, and if `ptformat` can't see
folder membership on modern sessions it cannot replicate the `ALL VOX` walk PTSL does live. Usable
only as a cheap "does this .ptx have any audio, roughly how many tracks" pre-filter to skip
empty/tiny sessions before spending a PT-open on them — not a ground-truth source itself.

### 2.8 Solo beat bus, bounce
**PROVEN, direct reuse.** `folder_bounce.py:bounce_open_acapella()` is the same operation (solo one
named routing folder, `CId_ExportMix` offline to `1-2`, ffmpeg not-silent verify, restore solo,
never save) aimed at `"VOCAL STEM"` — `bounce_open_beat_only(client, beat_folder="Beat Buss")` is a
one-line variant aimed at the beat bus. **Caveat, already documented:** the beat bus isn't always
literally named `Beat Buss` across era/artist (`LEARNED-2026-08-28.md` Part 2) — discovery (2.3's
walk) must locate it per-session, never a hardcoded string.

## 3. Offline pre-screen vs. online pass

| | Offline (no PT) | Online (PT open) |
|---|---|---|
| What | Discovery (2.0), de-dup (2.1), rough `ptformat` triage (2.7) | Everything needing PTSL/a screenshot (2.2–2.6, 2.8) |
| Why | Thousands of sessions; opening PT is slow, one-at-a-time | Plugin state, clip counts, tempo, and the bounce itself need a live session or GUI pixels |
| Throughput | All drives, one cheap pass | Bounded to ~1/day per cron (no batch claim until the trial proves the single-call approach) |

## 4. Data schema + output layout

```
docs/research/pt-ground-truth/
  pt-ground-truth.sqlite3        # STRICT table, one row per harvested session
  audio/<YY-M-D>_<Song>_<Artist>_BEAT.wav
  screenshots/<slug>/<role>-autotune.png   # evidence, kept for audit
  logs/harvest-<YY-M-D>.jsonl    # one line per session, cron-appended
```

```sql
CREATE TABLE sessions (
    id                   INTEGER PRIMARY KEY,
    session_path         TEXT NOT NULL,     -- .ptx chosen by pick_latest_ptx
    song_folder           TEXT NOT NULL,
    artist                TEXT,
    checked_at             TEXT NOT NULL,   -- ISO local time, not UTC
    autotune_key           TEXT,            -- "<Note> major|minor", matches key-bench/ground_truth.json
    autotune_scale_raw     TEXT,            -- verbatim, may be non-diatonic (risk 6)
    retune_speeds          TEXT,            -- JSON array, e.g. "[12, 15, 100]"
    reliable               INTEGER NOT NULL,
    disagreement_detail    TEXT,
    bpm                    REAL,
    tempo_map_flat         INTEGER,         -- 0/1/NULL(unknown), see 2.6
    beat_wav_path          TEXT,
    screenshot_paths       TEXT,            -- JSON array
    discovery_method       TEXT,            -- 'mdfind' | 'find-fallback'
    notes                  TEXT
) STRICT;
```

## 5. Trial pass plan (5 sessions)

- **Machine:** Sofia (Mac Pro), per J's plan to plug the iLok in there; `pt_stems/` already synced,
  `.venv` built (`LEARNED-2026-08-28.md` Part 4).
- **J's hands, numbered, before any session runs:**
  1. Plug the iLok into Sofia.
  2. Launch Pro Tools once by hand if first run since an update (clears the password-gated helper
     prompt PTSL/osascript cannot).
  3. Confirm which Auto-Tune product(s) are actually licensed on that iLok (open question 1).
- **One short thing at a time (`protools-assistant`'s law):**
  1. Session 1: run ONLY `CId_ExportSessionInfoAsText` and inspect the raw text by hand — resolves
     plugin presence, clip counts, and tempo before any GUI-click automation is attempted.
  2. Session 1, continued: one insert-slot click + screenshot + read, one track. Verify by eye.
  3. Sessions 2–5: full pipeline, one at a time, each verified before the next starts.
- **Go/no-go after each session:** row inserted correctly, `beat_wav_path` not-silent (mean_volume
  > −50 dB, same threshold `folder_bounce.py` uses), screenshot legible without zooming. Any miss →
  stop, don't start session N+1.

## 6. Cron plan (later)

launchd on Sofia, one session/day, same shape as the existing supervisor pattern
(`scripts/supervise_watch.sh` auto-relaunches on exit) — not built yet. Report: append to
`logs/harvest-<date>.jsonl`; a daily email only if J asks (`agent-email` skill), default to the log
file. Stays one-song-at-a-time-verified even as a cron — "verify" just becomes automated (row +
not-silent WAV + screenshot present) instead of J's eyes, with failures queued for J rather than
silently retried.

## 7. J's decisions (2026-09-12 19:54, verbatim intent)

1. **Auto-Tune product:** J owns the full Antares bundle. Roughly half of sessions carry Auto-Tune
   Pro, half Auto-Tune EFX. The reader must handle both layouts; identify the product from the
   plugin window title/header before reading Key/Scale/Retune Speed. EFX's fixed-position speed
   control is read as-is; "100 = off" applies to Pro's continuous knob.
2. **Beat folder is always `Beat Buss`.** Match it by exact name (case-insensitive); no tree
   walk. Missing `Beat Buss` (~1 in 1000) → skip the session, log it. Sessions mixed for the SSL
   may carry a printed instrumental instead and bounce blank → the not-silent check catches it,
   row gets `beat_wav_path` NULL + note "silent bounce (SSL session?)".
3. **Discovery scope:** drive `Arc-1`, folder `1-mixes`, as many different artists as possible
   (spread across artists, random within artist). Not mounted on the MacBook as of 2026-09-12
   19:54; the trial runs on Sofia with Arc-1 attached there.
4. **Bypassed / inactive Auto-Tune = no evidence.** Auto-Tune is on essentially every session on
   the drive; J removes it when unused but ~5-10 % of sessions still carry a bypassed instance.
   Presence proves nothing. Only an ACTIVE instance with retune speed ≠ off on all 3 lead tracks,
   all agreeing, makes the key certain. Bypassed-on-all-3 → row kept with `reliable=0`, reason
   "autotune bypassed", never used as a label.
5. **Purpose, in J's words:** "a massive source of beats where we know for a 100 % fact what the
   BPM and key are" — the largest such resource he knows of. Every session that yields a label
   also contributes its FULL bounce (vocals + beat: the newest mix/demo bounce in that session's
   `Bounced Files/`, picked by the `artist_latest` rule) to a **review playlist** so J can listen
   through and catch any out-of-tune vocal (= wrong Auto-Tune key) by ear. Nothing is taken from
   the artists: the beat and the label stay in `docs/research/pt-ground-truth/`, never published.
6. **Tempo map** (not asked again): record start tempo, `tempo_map_flat=0` when the map has more
   than one tempo event; benchmark harness excludes those downstream.
7. Missing-iLok failure mode: not tested in the trial; iLok stays in Sofia throughout.

### 7.1 Review playlist (new step 2.9)
- Copy the full bounce to `docs/research/pt-ground-truth/review/<YY-M-D>_<Song>_<Artist>_MIX.<ext>`
  (mp3 or wav, whatever the newest bounce is; no transcoding).
- Add it to a Music.app playlist named `PT Ground Truth` via AppleScript (`add POSIX file … to
  playlist`), created on first run. Runs on whichever Mac J listens on — Sofia for the trial; the
  review folder syncs to the MacBook with the repo-adjacent research folder.
- Schema additions: `full_bounce_path TEXT`, `review_status TEXT` ('unreviewed' | 'ok' |
  'out-of-tune' | 'reject', set by J), `autotune_product TEXT` ('Pro' | 'EFX' | other, per track as
  JSON array).

## 8. Risk list — what could silently produce a wrong label

1. **Auto-Tune present but bypassed** — a presence-only pre-screen (plugin list) would still flag
   the track; the active/bypassed color read (2.2) must gate every record, never presence alone.
2. **Key changed mid-song via automation** — one screenshot captures one instant; no PTSL command
   reads plugin automation at all (checked the full `.proto`), so a modulating song silently yields
   a wrong single-key label. Out of scope for v1 — flag rather than guess.
3. **Tempo map with mid-song changes** — `bpm.py`'s benchmark assumes one constant BPM; no proven
   mechanism detects a non-flat map (2.6). Silent risk: a harvested BPM correct for only part of
   the track.
4. **Beat-bus name varies by era/artist** (already hit in production) — a hardcoded `"Beat Buss"`
   solo would silently solo nothing/the wrong folder, bouncing a wrong or empty "beat" file that
   can still pass the not-silent check if anything else was left soloed.
5. **Lead-vocal shortlist false positive** — an ad-lib/background track matching a candidate
   pattern (same bug class as the production `"IVY SUPRA IVY AD"` auto-naming miss) could out-rank
   the true lead by clip count if exclusions aren't applied before ranking.
6. **Auto-Tune's Scale isn't always major/minor** — its Scale dropdown includes modes (Dorian,
   Mixolydian, harmonic/melodic minor, Blues, Chromatic) `bpm.py` cannot predict (major/minor only).
   Store `autotune_scale_raw` verbatim so non-diatonic sessions are visibly excluded from grading,
   not silently mis-scored.
7. **Missing iLok → plugin "unavailable"** — Key/Scale on an unauthorized instance likely reads
   blank/default rather than erroring visibly; the bypassed/active check (2.2) must also catch an
   "unavailable"-looking header before trusting whatever it shows.
8. **Per-track clip count may not be obtainable at PTSL scale at all** (2.3) — every structured
   PTSL surface was checked against the `.proto` and none give it; the only unverified candidate is
   `ExportSessionInfoAsText`'s track-EDL text. If that also fails to associate clips to tracks, 2.3
   falls back to manual counting, which doesn't scale to "thousands of sessions" — the single
   biggest risk to this design's viability, and the first thing to resolve in the trial (§5).
