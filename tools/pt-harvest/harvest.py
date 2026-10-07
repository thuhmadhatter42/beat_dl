"""PT BPM harvester (plan 2026-10-06 §2-§6). Runs on Sofia with ~/pt-harvest/.venv.

  harvest.py one N [--already-open] [--keep-open]   full pipeline for manifest #N
  harvest.py batch [--target 200] [--max-n 323]     resumable loop over the manifest until --target usable rows
  harvest.py status                                  counts from the DB

Per session: open (dialog_clicker.py runs alongside) -> toolbar OCR (Tempo/Meter) + crops ->
session info exported in Bars|Beats and Samples (EDL tempo + flatness) -> Beat Buss folder ->
8 s probe bounce -> full beat bounce to ~/pt-harvest/audio/NNNN.wav -> 11025 Hz mono copy ->
close WITHOUT saving (always, even on error) -> one DB row + one JSONL line.

Names rule (J 2026-10-06): sessions are NNNN + sha1 only. The sha1->path map is manifest.json on
Sofia. Nothing written to the DB, log or stdout carries a song/artist/track/file name.
Never saves a session. Never writes to the source drive (bounces go to ~/pt-harvest/audio).
"""
from __future__ import annotations
import json, os, signal, sqlite3, subprocess, sys, time, traceback
from collections import Counter
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib
from hlib import H

DB = H / "pt-ground-truth.sqlite3"
AUDIO = H / "audio"
AUDIO11 = H / "audio11k"
CROPS = H / "crops"
INFO = H / "info"
LOGDIR = H / "logs"
STOP = H / "STOP"
OPEN_TIMEOUT = 1500       # ARA restore alone took 607 s on the first session
USABLE = ("confirmed", "tempo-only")

SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (
    id                  INTEGER PRIMARY KEY,   -- manifest number N; bounce = audio/NNNN.wav
    ptx_sha1            TEXT NOT NULL UNIQUE,  -- sha1 of the .ptx path (map on Sofia only)
    artist              TEXT,                  -- opaque: sha1(artist folder name)[:10]
    checked_at          TEXT NOT NULL,         -- local time
    status              TEXT NOT NULL,         -- ok | skip-no-beat-buss | silent | error-*
    autotune_key        TEXT,
    autotune_scale_raw  TEXT,
    retune_speeds       TEXT,
    autotune_product    TEXT,
    reliable            INTEGER NOT NULL,      -- 1 = Auto-Tune key read reliable (spec §2.5)
    disagreement_detail TEXT,
    key                 TEXT,                  -- best key label ('D minor')
    key_source          TEXT,                  -- comment | autotune | comment+autotune
    bpm                 REAL,
    bpm_source          TEXT,
    bpm_confidence      TEXT,                  -- confirmed | tempo-only | excluded
    session_tempo       REAL,                  -- toolbar OCR
    tempo_raw           TEXT,
    meter               TEXT,
    edl_tempo           REAL,                  -- from EDL Bars|Beats vs Samples
    edl_points          INTEGER,
    edl_on_line         REAL,
    tempo_map_flat      INTEGER,
    beat_comment        TEXT,                  -- only when it parses strictly as key/BPM
    comment_bpm         REAL,
    comment_key         TEXT,
    producer_bpms       TEXT,                  -- JSON array, from beat clip names (never beat_dl's own '(NN.N BPM ..)')
    beat_wav_path       TEXT,                  -- audio/NNNN.wav on Sofia (11 kHz copy audio11k/NNNN.wav)
    beat_mean_db        REAL,
    probe_mean_db       REAL,
    beat_duration_s     REAL,
    screenshot_paths    TEXT,                  -- JSON array, crops/ on Sofia
    discovery_method    TEXT,
    elapsed_s           REAL,
    notes               TEXT
) STRICT;
"""


def db():
    con = sqlite3.connect(DB)
    con.executescript(SCHEMA)
    return con


def log_jsonl(rec: dict):
    LOGDIR.mkdir(parents=True, exist_ok=True)
    with open(LOGDIR / f"harvest-{time.strftime('%y-%-m-%-d')}.jsonl", "a") as f:
        f.write(json.dumps(rec) + "\n")


def say(*a):
    print(time.strftime("%H:%M:%S"), *[hlib.redact(x) for x in a], flush=True)


def blocked() -> str | None:
    return (H / "BLOCKED").read_text().strip() if (H / "BLOCKED").exists() else None


# ---------------------------------------------------------------- stages

def stage_open(c, e):
    if hlib.session_open(c):
        say("a session was already open: closing without saving")
        hlib.close_no_save(c)
    hlib.bring_pt_forward()
    t0 = time.time()
    st, body = c.status_of("CId_OpenSession", {"session_path": e["ptx"], "prompt_for_file_not_found": False},
                           timeout=OPEN_TIMEOUT)
    return st, round(time.time() - t0)


def stage_screen(n):
    """Toolbar OCR + crops. PT must be frontmost (activated, no click)."""
    CROPS.mkdir(parents=True, exist_ok=True)
    hlib.bring_pt_forward()
    time.sleep(2)
    full = H / "shots" / f"full-{n:04d}.png"
    full.parent.mkdir(exist_ok=True)
    img = hlib.screenshot(full)
    tb = hlib.read_toolbar(img)
    p1 = CROPS / f"{n:04d}-toolbar.png"
    p2 = CROPS / f"{n:04d}-rulers.png"
    hlib.crop(img, hlib.TOOLBAR, 1.0).save(p1)
    hlib.crop(img, hlib.RULERS, 1.0).save(p2)
    tb["front"] = hlib.frontmost()
    tb["shots"] = [str(p1.relative_to(H)), str(p2.relative_to(H))]
    return tb


def stage_info(c, n, beats_per_bar):
    INFO.mkdir(exist_ok=True)
    tbb = hlib.export_info(c, "TLType_BarsBeats")
    tsa = hlib.export_info(c, "TLType_Samples")
    (INFO / f"{n:04d}-bb.txt").write_text(tbb)
    (INFO / f"{n:04d}-samples.txt").write_text(tsa)
    bb, sa = hlib.parse_info(tbb), hlib.parse_info(tsa)
    sr = float(bb["header"].get("SAMPLE RATE", "0") or 0)
    pts = hlib.edl_points(bb, sa, beats_per_bar)
    tempo, flat, npts, on = hlib.edl_tempo(pts, sr)
    return {"bb": bb, "sa": sa, "sr": sr, "edl_tempo": tempo, "edl_flat": flat, "edl_points": npts, "edl_on_line": on}


def _base(name: str) -> str:
    for suf in (" (Stereo)", " (Mono)"):
        if name.endswith(suf):
            return name[: -len(suf)]
    return name


def stage_beat_meta(tl, info):
    """Beat folder + its tracks; comments and producer BPMs from the beat tracks only."""
    folder, kids = hlib.beat_tree(tl)
    if folder is None:
        return None
    kid_names = {k["name"] for k in kids}
    active_audio = {k["name"] for k in kids if k["type"] == "TType_Audio" and not hlib.attr(k, "is_inactive")
                    and not hlib.attr(k, "is_muted") and hlib.attr(k, "contains_clips")}
    comments, clipnames, max_end = [], [], 0
    for tb, ts in zip(info["bb"]["tracks"], info["sa"]["tracks"]):
        nm = _base(tb["name"])
        if nm not in kid_names and tb["name"] not in kid_names:
            continue
        if tb["comment"]:
            comments.append(tb["comment"])
        live = nm in active_audio or tb["name"] in active_audio
        for eb, es in zip(tb["edl"], ts["edl"]):
            if eb["state"].lower().startswith("unmuted") and live:
                clipnames.append(eb["clip"])
                try:
                    max_end = max(max_end, int(es["end"]))
                except ValueError:
                    pass
    parsed = [hlib.parse_comment(cm) for cm in comments]
    parsed = [p | {"raw": cm} for p, cm in zip(parsed, comments) if p["key"] or p["bpm"]]
    return {"folder": folder, "n_tracks": len(kids), "n_active_audio": len(active_audio),
            "comments": parsed, "producer_bpms": hlib.producer_bpms(clipnames), "max_end": max_end}


def stage_bounce(c, n, meta, sr):
    """Probe 8 s, then the full beat. Solo the Beat Buss folder by name, read back, restore."""
    AUDIO.mkdir(exist_ok=True); AUDIO11.mkdir(exist_ok=True)
    out = {"probe_db": None, "mean_db": None, "path": None, "dur": None, "note": None}
    srcs = hlib.export_sources(c)
    source = hlib.pick_source(srcs)
    if not source:
        out["note"] = f"no 1-2 style output among {len(srcs)} sources"
        return out
    tl = hlib.tracks(c)
    prior = [t["name"] for t in tl if hlib.attr(t, "is_soloed")]
    for p in prior:
        hlib.solo(c, p, False)
    fname = meta["folder"]["name"]
    try:
        hlib.solo(c, fname, True)
        soloed = hlib.attr(next(t for t in hlib.tracks(c) if t["id"] == meta["folder"]["id"]), "is_soloed")
        if not soloed:
            out["note"] = "Beat Buss solo did not read back"
            return out
        end = meta["max_end"]
        if end <= sr * 10:
            out["note"] = "beat clips end before 10 s"
            return out
        for frac in (0.5, 0.25):          # rule zero: probe before a full print; 2nd spot if the 1st is a gap
            a = int(end * frac)
            hlib.set_selection_samples(c, a, int(a + 8 * sr))
            st, body = hlib.export_mix(c, str(AUDIO), f"probe-{n:04d}", int(sr), source, timeout=600)
            pp = AUDIO / f"probe-{n:04d}.wav"
            out["probe_db"] = hlib.mean_db(pp) if pp.exists() else None
            if pp.exists():
                pp.unlink()
            if st != "Completed" or out["probe_db"] is None:
                out["note"] = f"probe export {st}"
                return out
            if out["probe_db"] > -50:
                break
        if out["probe_db"] <= -50:
            out["note"] = "silent probe (SSL session?)"
            return out
        hlib.set_selection_samples(c, 0, int(min(end + sr, end * 1.02)))
        st, body = hlib.export_mix(c, str(AUDIO), f"{n:04d}", int(sr), source, timeout=3600)
        wav = AUDIO / f"{n:04d}.wav"
        if st != "Completed" or not wav.exists():
            out["note"] = f"export {st}"
            return out
        out["mean_db"] = hlib.mean_db(wav)
        out["dur"] = hlib.duration_s(wav)
        if out["mean_db"] is None or out["mean_db"] <= -50:
            out["note"] = "silent bounce (SSL session?)"
            wav.unlink()
            return out
        out["path"] = f"audio/{n:04d}.wav"
        if not hlib.to_11k(wav, AUDIO11 / f"{n:04d}.wav"):
            out["note"] = "11k copy failed"
        return out
    finally:
        hlib.solo(c, fname, False)
        for p in prior:
            hlib.solo(c, p, True)


def stage_close(c):
    st = hlib.close_no_save(c)
    for _ in range(30):
        if not hlib.session_open(c):
            return st
        time.sleep(2)
    return st + "+still-open"


# ---------------------------------------------------------------- one session

def run_one(n, already_open=False, keep_open=False) -> dict:
    e = hlib.entry(n)
    t0 = time.time()
    rec = {"id": n, "ptx_sha1": e["sha1"], "artist": e["artist_hash"], "checked_at": hlib.now(),
           "status": "error", "reliable": 0, "discovery_method": "mdfind", "notes": []}
    c = hlib.client()
    opened = already_open
    try:
        if not already_open:
            st, secs = stage_open(c, e)
            rec["open_s"] = secs
            say(f"#{n:04d} open {st} {secs}s")
            if st != "Completed":
                rec["status"] = "error-open"; rec["notes"].append(f"open {st}")
                opened = hlib.session_open(c)
                return rec
            opened = True
        scr = stage_screen(n)
        rec.update(session_tempo=scr["tempo"], tempo_raw=scr["tempo_raw"], meter=scr["meter"],
                   screenshot_paths=json.dumps(scr["shots"]))
        if not scr["front"].startswith("Pro Tools"):
            rec["notes"].append("PT not frontmost at screenshot")
        bpb = int(scr["meter"].split("/")[0]) if scr["meter"] and scr["meter"].split("/")[1] == "4" else 4
        if scr["meter"] and scr["meter"] != "4/4":
            rec["notes"].append(f"meter {scr['meter']}")
        info = stage_info(c, n, bpb)
        rec.update(edl_tempo=info["edl_tempo"], edl_points=info["edl_points"], edl_on_line=info["edl_on_line"],
                   tempo_map_flat=info["edl_flat"])
        tl = hlib.tracks(c)
        meta = stage_beat_meta(tl, info)
        if meta is None:
            rec["status"] = "skip-no-beat-buss"
            return rec
        cm = next((p for p in meta["comments"] if p["bpm"] or p["key"]), None)
        if cm:
            rec.update(beat_comment=cm["raw"], comment_bpm=cm["bpm"], comment_key=cm["key"])
        if len(meta["comments"]) > 1:
            rec["notes"].append(f"{len(meta['comments'])} beat comments")
        rec["producer_bpms"] = json.dumps(meta["producer_bpms"])
        # tempo: OCR is the reading; the EDL must agree when it has enough points
        tempo = scr["tempo"]
        if tempo is None and info["edl_tempo"] and info["edl_flat"] == 1:
            tempo = round(info["edl_tempo"], 2); rec["notes"].append("tempo from EDL (OCR failed)")
        if tempo and info["edl_tempo"] and not hlib.agree(tempo, info["edl_tempo"], 0.002):
            rec["notes"].append("OCR tempo != EDL tempo")
            flat = 0
        else:
            flat = info["edl_flat"]
        bpm, src, conf = hlib.label(tempo, flat, rec.get("comment_bpm"), meta["producer_bpms"])
        rec.update(bpm=bpm, bpm_source=src, bpm_confidence=conf, tempo_map_flat=flat)
        if rec.get("comment_key"):
            rec.update(key=rec["comment_key"], key_source="comment")
        b = stage_bounce(c, n, meta, info["sr"])
        rec.update(beat_wav_path=b["path"], beat_mean_db=b["mean_db"], probe_mean_db=b["probe_db"],
                   beat_duration_s=b["dur"])
        if b["note"]:
            rec["notes"].append(b["note"])
        rec["status"] = "ok" if b["path"] else ("silent" if b["note"] and "silent" in b["note"] else "error-bounce")
        return rec
    except BaseException as ex:
        rec["status"] = f"error-{type(ex).__name__}"
        rec["notes"].append(hlib.redact(str(ex))[:200])
        say("EXC", hlib.redact(traceback.format_exc())[-600:])
        if isinstance(ex, KeyboardInterrupt):
            raise
        return rec
    finally:
        if opened and not keep_open:
            try:
                rec["close"] = stage_close(c)
            except BaseException as ex:
                rec["close"] = f"error {type(ex).__name__}"
        rec["elapsed_s"] = round(time.time() - t0, 1)
        try:
            w = source_writes(e["ptx"], t0 - 1)
            if w:
                rec["notes"].append(f"PT wrote {w} file(s) on the source drive (auto-backup/wavecache; listed on Sofia)")
        except Exception:
            pass
        rec["notes"] = "; ".join(rec["notes"]) if isinstance(rec["notes"], list) else rec["notes"]
        save(rec)


def source_writes(ptx: str, since: float) -> int:
    """Files PT itself wrote in the session's folder while we had it open (Session File Backups
    .ptx, WaveCache.wfm). Full paths go to ~/pt-harvest/source-drive-writes.txt (Sofia only) so J
    can trash them later; only the count leaves this function."""
    sd = os.path.dirname(ptx)
    hits = []
    for root, dirs, files in os.walk(sd):
        if "Audio Files" in root or "Bounced Files" in root:
            continue
        for f in files:
            p = os.path.join(root, f)
            try:
                if os.path.getmtime(p) >= since:
                    hits.append(p)
            except OSError:
                pass
    if hits:
        with open(H / "source-drive-writes.txt", "a") as fh:
            fh.write("".join(f"{hlib.now()}\t{p}\n" for p in hits))
    return len(hits)


COLS = None


def save(rec):
    global COLS
    con = db()
    if COLS is None:
        COLS = [r[1] for r in con.execute("PRAGMA table_info(sessions)")]
    row = {k: rec.get(k) for k in COLS}
    con.execute(f"INSERT OR REPLACE INTO sessions ({','.join(COLS)}) VALUES ({','.join('?' * len(COLS))})",
                [row[k] for k in COLS])
    con.commit(); con.close()
    log_jsonl({k: rec.get(k) for k in ("id", "ptx_sha1", "checked_at", "status", "bpm", "bpm_confidence",
                                        "bpm_source", "session_tempo", "edl_tempo", "edl_on_line", "tempo_map_flat",
                                        "comment_bpm", "comment_key", "key", "beat_mean_db", "probe_mean_db",
                                        "beat_duration_s", "open_s", "close", "elapsed_s", "notes")})
    say(f"#{rec['id']:04d} {rec['status']} tempo={rec.get('session_tempo')} edl={rec.get('edl_tempo')} "
        f"flat={rec.get('tempo_map_flat')} comment={rec.get('beat_comment')} -> bpm={rec.get('bpm')} "
        f"{rec.get('bpm_confidence')} ({rec.get('bpm_source')}) key={rec.get('key')} wav_dB={rec.get('beat_mean_db')} "
        f"{rec.get('elapsed_s')}s close={rec.get('close')} notes={rec.get('notes')}")


def usable_count(con):
    return con.execute(f"SELECT count(*) FROM sessions WHERE beat_wav_path IS NOT NULL AND bpm_confidence IN "
                       f"('confirmed','tempo-only')").fetchone()[0]


def relaunch_pt():
    say("killing Pro Tools (hung) and relaunching")
    subprocess.run(["pkill", "-9", "-f", "Pro Tools.app/Contents/MacOS/Pro Tools"])
    time.sleep(10)
    r = subprocess.run([str(H / ".venv/bin/python"), str(H / "pt_launch.py"), "100"], capture_output=True, text=True)
    say("relaunch:", r.stdout.strip().splitlines()[-1:] if r.stdout else r.returncode)
    time.sleep(20)


def batch(target=200, max_n=10**6):
    con = db()
    done = {r[0] for r in con.execute("SELECT id FROM sessions WHERE status NOT LIKE 'error%'")}
    tries = {r[0]: r[1] for r in con.execute("SELECT id, notes FROM sessions WHERE status LIKE 'error%'")}
    con.close()
    fails_in_row = 0
    say(f"batch start: {len(done)} done, target {target} usable")
    for e in hlib.manifest():
        n = e["n"]
        if n > max_n or n in done:
            continue
        if n in tries and "retried" in (tries[n] or ""):
            continue
        con = db(); u = usable_count(con); con.close()
        if u >= target:
            say(f"target reached: {u} usable rows"); return 0
        if STOP.exists():
            say("STOP file present: stopping"); return 0
        b = blocked()
        if b:
            say("BLOCKED:", b); return 3
        c = hlib.client()
        if hlib.session_open(c):
            hlib.close_no_save(c)
        rec = run_one(n)
        if n in tries:
            con = db()
            con.execute("UPDATE sessions SET notes = coalesce(notes,'') || '; retried' WHERE id=?", (n,))
            con.commit(); con.close()
        if rec["status"].startswith("error"):
            fails_in_row += 1
            if rec["status"] in ("error-open", "error-_InactiveRpcError", "error-PtslError") or "deadline" in str(rec.get("notes")).lower():
                shot = H / "shots" / f"error-{n:04d}.png"
                subprocess.run(["screencapture", "-x", str(shot)])
                if blocked():
                    say("BLOCKED after error:", blocked()); return 3
                relaunch_pt()
            if fails_in_row >= 4:
                say("4 errors in a row: stopping for a human look"); return 4
        else:
            fails_in_row = 0
    con = db(); u = usable_count(con); con.close()
    say(f"manifest exhausted: {u} usable rows"); return 0


def status():
    con = db()
    for r in con.execute("SELECT status, bpm_confidence, count(*) FROM sessions GROUP BY 1,2 ORDER BY 3 DESC"):
        print(r)
    print("usable", usable_count(con))
    r = con.execute("SELECT avg(elapsed_s), max(id) FROM sessions").fetchone()
    print("avg s/session", round(r[0] or 0), "last id", r[1])


if __name__ == "__main__":
    cmd = sys.argv[1]
    try:
        if cmd == "one":
            run_one(int(sys.argv[2]), "--already-open" in sys.argv, "--keep-open" in sys.argv)
        elif cmd == "batch":
            a = sys.argv
            rc = batch(int(a[a.index("--target") + 1]) if "--target" in a else 200,
                       int(a[a.index("--max-n") + 1]) if "--max-n" in a else 10**6)
            sys.stdout.flush(); os._exit(rc)
        elif cmd == "status":
            status()
    except BaseException as ex:
        print("ERR", type(ex).__name__, hlib.redact(ex)[:300])
    sys.stdout.flush(); os._exit(0)
