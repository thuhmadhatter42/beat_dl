"""PT BPM harvester (plan 2026-10-06 §2-§6). Runs on Sofia with ~/pt-harvest/.venv.

  harvest.py one N [--already-open] [--keep-open]   full pipeline for manifest #N
  harvest.py batch [--target 200] [--max-n 323]     resumable loop over the manifest until --target usable rows
  harvest.py mix N                                   back-fill: print only the full mix of a done row
  harvest.py status                                  counts from the DB

Per session: open (dialog_clicker.py runs alongside) -> toolbar OCR (Tempo/Meter) + crops ->
session info exported in Bars|Beats and Samples (EDL tempo + flatness) -> beat finder v2 (beatfind.py:
folders, output buses, names, plug-ins, clips) -> 8 s probes LISTENED to (audiocheck.py: beat probe +
complement) -> full beat bounce to ~/pt-harvest/audio/NNNN.wav -> full mix (nothing soloed) to
audio/NNNN_mix.wav -> 11025 Hz mono copies ->
close WITHOUT saving (always, even on error) -> one DB row + one JSONL line.

Names rule (J 2026-10-06): sessions are NNNN + sha1 only. The sha1->path map is manifest.json on
Sofia. Nothing written to the DB, log or stdout carries a song/artist/track/file name.
Never saves a session. Never writes to the source drive (bounces go to ~/pt-harvest/audio).
"""
from __future__ import annotations
import json, os, re, signal, sqlite3, subprocess, sys, time, traceback
from collections import Counter
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audiocheck
import beatfind
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
KEY_READ = "--no-key" not in sys.argv
MIX = "--no-mix" not in sys.argv          # J 01:08: also print the full mix of every usable session

SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (
    id                  INTEGER PRIMARY KEY,   -- manifest number N; bounce = audio/NNNN.wav
    ptx_sha1            TEXT NOT NULL UNIQUE,  -- sha1 of the .ptx path (map on Sofia only)
    artist              TEXT,                  -- opaque: sha1(artist folder name)[:10]
    checked_at          TEXT NOT NULL,         -- local time
    status              TEXT NOT NULL,         -- ok | excluded-checked | skip-no-beat | skip-beat-unsure | silent | error-* (v1: skip-no-beat-buss)
    autotune_key        TEXT,
    autotune_scale_raw  TEXT,
    retune_speeds       TEXT,
    autotune_product    TEXT,
    autotune_reads      TEXT,                  -- JSON: per instance slot/product/bypass rgb/key/scale/retune
    reliable            INTEGER NOT NULL,      -- 1 = Auto-Tune key read reliable (spec §2.5)
    disagreement_detail TEXT,
    key                 TEXT,                  -- best key label ('D minor')
    key_source          TEXT,                  -- comment | autotune | comment+autotune
    bpm                 REAL,
    bpm_source          TEXT,
    bpm_confidence      TEXT,                  -- confirmed | tempo-only | excluded
    session_tempo       REAL,                  -- Edit window AX Tempo field
    tempo_raw           TEXT,                  -- AX Tempo field text
    ocr_tempo           REAL,                  -- OCR of the on-screen Tempo field (cross-check)
    tempo_events        INTEGER,               -- rows in the AX Tempo table
    meter               TEXT,
    edl_tempo           REAL,                  -- from EDL Bars|Beats vs Samples
    edl_points          INTEGER,
    edl_on_line         REAL,
    tempo_map_flat      INTEGER,
    beat_comment        TEXT,                  -- only when it parses strictly as key/BPM
    comment_bpm         REAL,
    comment_key         TEXT,
    producer_bpms       TEXT,                  -- JSON array, from beat clip names (never beat_dl's own '(NN.N BPM ..)')
    beatdl_estimate     REAL,                  -- decimal 'NN.N BPM' estimate in the beat clip names, if any
    tempo_from_estimate INTEGER,               -- 1 = session tempo equals that estimate (J set the grid from it: circular for training)
    beat_source         TEXT,                  -- v2: folder | name | bus | inferred (v1: 'Beat Buss' / 'Beat track')
    beat_wav_path       TEXT,                  -- audio/NNNN.wav on Sofia (11 kHz copy audio11k/NNNN.wav)
    beat_mean_db        REAL,
    probe_mean_db       REAL,
    beat_duration_s     REAL,
    screenshot_paths    TEXT,                  -- JSON array, crops/ on Sofia
    discovery_method    TEXT,
    elapsed_s           REAL,
    notes               TEXT,
    finder_version      INTEGER,               -- beatfind.FINDER_VERSION that decided this row (NULL = name-only v1)
    beat_confidence     TEXT,                  -- high | medium | low (beat finder, after the listening checks)
    beat_check          TEXT,                  -- JSON: audiocheck verdicts of the beat probes + the complement
    old_rule            INTEGER,               -- 1 = the v1 name-only rule would also have found a beat
    mix_wav_path        TEXT,                  -- audio/NNNN_mix.wav on Sofia (full mix, nothing soloed; 11k copy audio11k/NNNN_mix.wav)
    mix_mean_db         REAL,
    mix_duration_s      REAL,
    mix_note            TEXT,
    mix_resid_db        REAL,                  -- level of (mix - beat) on the 11k copies; < mix_mean_db - 40 = mix is just the beat
    drive               TEXT                   -- arch1 | allmixes
) STRICT;
"""


def db():
    con = sqlite3.connect(DB)
    con.executescript(SCHEMA)
    have = {r[1] for r in con.execute("PRAGMA table_info(sessions)")}
    for m in re.finditer(r"^\s{4}(\w+)\s+(TEXT|REAL|INTEGER)\b", SCHEMA, re.M):   # additive migration
        if m[1] not in have:
            con.execute(f"ALTER TABLE sessions ADD COLUMN {m[1]} {m[2]}")
    con.commit()
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
    """Tempo from the Edit window's AX tree (primary), cross-checked by OCR of the on-screen Tempo
    field. The evidence crop is the Tempo field alone (no names in it)."""
    CROPS.mkdir(parents=True, exist_ok=True)
    hlib.bring_pt_forward()
    time.sleep(2)
    ax = hlib.ax_edit_tempo()
    full = H / "shots" / f"full-{n:04d}.png"       # Sofia only (has names in it)
    full.parent.mkdir(exist_ok=True)
    img = hlib.screenshot(full)
    ax["ocr_tempo"] = None
    ax["shots"] = []
    fr = ax.get("tempo_field_frame")
    if fr and fr[2] > 10 and 0 <= fr[0] < 1920 and 0 <= fr[1] < 1080:
        box = (max(fr[0] - 70, 0), max(fr[1] - 4, 0), fr[2] + 80, fr[3] + 8)
        crop = hlib.crop(img, box, 3.0)
        p = CROPS / f"{n:04d}-tempo.png"
        crop.save(p)
        ax["shots"].append(str(p.relative_to(H)))
        toks = hlib.ocr(crop)
        nums = [re.search(r"\d{2,3}\.\d{2,4}", t[0]) for t in toks]
        nums = [float(m[0]) for m in nums if m]
        ax["ocr_tempo"] = nums[0] if nums else None
    ax["front"] = hlib.frontmost()
    return ax


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


def stage_beat_meta(c, tl, info):
    """Beat finder v2 (beatfind.py): which tracks are the beat; comments and producer BPMs from them.
    -> (meta | None, finder result)"""
    outs = hlib.track_outputs(c, tl)
    res = beatfind.find(tl, info["sa"], outs, info["sr"] or 48000.0)
    if not res.get("found"):
        return None, res
    kid_names = set(res["comment_names"]) | {t["name"] for t in res["tracks"]}
    active_audio = {t["name"] for t in res["tracks"]}
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
    return {"solo": res["solo"], "method": res["method"], "beat_source": res["beat_source"],
            "confidence": res["confidence"], "legacy": res.get("legacy", False), "finder": res,
            "n_tracks": len(res["tracks"]), "n_active_audio": len(active_audio),
            "comments": parsed, "producer_bpms": hlib.producer_bpms(clipnames), "max_end": max_end,
            "estimates": hlib.estimate_bpms(clipnames)}, res


_LEAD = re.compile(r"hook|verse|\bld\b|\blead\b|\bmain\b|\blv\b", re.I)
_NOT_LEAD = re.compile(r"\b(ad|ads|adlib|ad ?libs?|bg|bgv|bgs|dbl|dub|dubs|harm|harmony|harmonies|ref|fx|vrb|verb)\b", re.I)


def stage_autotune(n, tl, c=None) -> dict:
    """Spec §2.4/§2.5: read Key/Scale/Retune from up to 3 active Auto-Tune instances on live lead
    vocal tracks. Reliable = >=2 reads, none bypassed, none effectively off, all agree.
    Closed folders hide their tracks' strips from the Edit window (and its AX tree), so closed
    folders are opened first (view state only; the session is never saved) and closed again after."""
    opened = []
    if c is not None:
        closed = [t["name"] for t in tl if t["type"] in ("TType_RoutingFolder", "TType_BasicFolder")
                  and not hlib.attr(t, "is_open")]
        if closed:
            st, _ = c.status_of("CId_SetTrackOpenState", {"track_names": closed, "enabled": True})
            if st == "Completed":
                opened = closed
                time.sleep(1.5)
    try:
        return _stage_autotune(n, tl)
    finally:
        if opened:
            c.status_of("CId_SetTrackOpenState", {"track_names": opened, "enabled": False})


def _stage_autotune(n, tl) -> dict:
    by_name = {t["name"]: t for t in tl}
    by_id = {t["id"]: t for t in tl}

    def in_vocals(t):
        cur = t
        while cur.get("parent_folder_id") in by_id:
            cur = by_id[cur["parent_folder_id"]]
            if re.search(r"vocal\s*stem|all\s*vox", cur["name"], re.I):
                return True
        return False
    strips = hlib.edit_strips()
    cands = []
    why = Counter()
    for name, btns in strips.items():
        t = by_name.get(name)
        if not t:
            why["no-track-match"] += 1; continue
        off = next((k for k in ("is_inactive", "is_muted", "is_hidden") if hlib.attr(t, k)), None)
        if off:
            why[off] += 1; continue
        if t["type"] != "TType_Audio" or not hlib.attr(t, "contains_clips"):
            why["not-audio-or-no-clips"] += 1; continue
        if _NOT_LEAD.search(name):
            why["not-lead-name"] += 1; continue
        why["candidate"] += 1
        rank = (0 if _LEAD.search(name) else 1, 0 if in_vocals(t) else 1, t.get("index", 999))
        cands.append((rank, name, btns[0]))
    cands.sort()
    out = {"n_candidates": len(cands), "reads": [], "filter": dict(why), "n_strips": len(strips)}
    for i, (rank, name, (slot, val, b)) in enumerate(cands[:8]):    # up to 3 active instances, 8 tries
        r = hlib.read_autotune(b, CROPS / f"{n:04d}-autotune-{i}.png")
        r["slot"] = slot; r["lead_named"] = rank[0] == 0
        out["reads"].append(r)
        if sum(1 for x in out["reads"] if not x.get("inactive")) >= 3:
            break
        if sum(1 for x in out["reads"] if x.get("inactive")) >= 3 and not any(x.get("ok") for x in out["reads"]):
            break                                           # J: untuned songs have their Auto-Tunes inactive
    reads = [r for r in out["reads"] if r.get("ok")]
    out["products"] = [r.get("product") for r in out["reads"]]
    out["speeds"] = [r.get("retune") for r in out["reads"]]
    keys = {(r["key"], (r["scale"] or "").lower()) for r in reads}
    off = [r for r in reads if r.get("bypassed") or (r.get("product") and "Pro" in r["product"] and (r.get("retune") or 0) >= 100)]
    n_inactive = sum(1 for r in out["reads"] if r.get("inactive"))
    out["reliable"] = int(len(reads) >= 2 and not off and len(keys) == 1)
    if keys and len(keys) == 1:
        k, s = next(iter(keys))
        out["key"] = hlib.key_label(k, s); out["scale_raw"] = f"{k} {s}"
    else:
        out["key"] = None; out["scale_raw"] = "; ".join(f"{k} {s}" for k, s in sorted(keys)) or None
    det = []
    if len(keys) > 1:
        det.append("keys disagree: " + ", ".join(f"{k} {s}" for k, s in sorted(keys)))
    if off:
        det.append(f"{len(off)} bypassed/off")
    if n_inactive:
        det.append(f"{n_inactive} inactive")
    if len(reads) + n_inactive < len(out["reads"]):
        det.append(f"{len(out['reads']) - len(reads) - n_inactive} unread")
    if len(out["reads"]) < 2:
        det.append(f"only {len(out['reads'])} lead Auto-Tune instance(s) "
                   f"({out['n_strips']} strips with Auto-Tune; {out['filter']})")
    out["detail"] = "; ".join(det) or None
    return out


def _probe(c, n, src, a, sr, tempo, tag="probe"):
    """8 s offline print at sample a on output src -> (status, mean_db, audiocheck features)."""
    hlib.set_selection_samples(c, a, int(a + 8 * sr))
    st, body = hlib.export_mix(c, str(AUDIO), f"{tag}-{n:04d}", int(sr), src, timeout=600)
    pp = AUDIO / f"{tag}-{n:04d}.wav"
    fe = None
    if pp.exists():
        try:
            fe = audiocheck.features(pp, tempo)
        except Exception as ex:
            fe = {"mean_db": hlib.mean_db(pp), "err": type(ex).__name__}
        pp.unlink()
    db_ = fe.get("mean_db") if fe else None
    return st, db_, fe


def _brief(fe):
    if not fe:
        return None
    v = audiocheck.verdict(fe) if fe.get("mean_db") is not None and "sub" in fe else ("silent", 0, "")
    return {"v": v[0], "s": v[1], "db": fe.get("mean_db"), "sub": fe.get("sub"), "voice": fe.get("voice"),
            "pulse": fe.get("pulse", fe.get("pulse_any"))}


def stage_bounce(c, n, meta, sr, tempo=None, probe_only=False):
    """Isolate the beat (solo the folder / solo the beat tracks / fallback: mute everything else), LISTEN
    to 8 s probes (audiocheck) and to the complement (beat muted), then print the full beat. Restores
    every solo/mute it touched. -> dict"""
    AUDIO.mkdir(exist_ok=True); AUDIO11.mkdir(exist_ok=True)
    out = {"probe_db": None, "mean_db": None, "path": None, "dur": None, "note": None, "source": None,
           "sel": None, "check": {}, "confidence": meta["confidence"], "skip": None}
    srcs = hlib.export_sources(c)
    source = hlib.pick_source(srcs) or (srcs[0] if srcs else None)
    if not source:
        out["note"] = "no output sources listed"
        return out
    tl = hlib.tracks(c)
    prior = [t["name"] for t in tl if hlib.attr(t, "is_soloed")]
    fin = meta["finder"]
    muted_by_us = []
    soloed = []
    for p in prior:
        hlib.solo(c, p, False)
    end = meta["max_end"]
    try:
        if end <= sr * 10:
            out["note"] = "beat clips end before 10 s"
            return out

        def isolate(mode):
            nonlocal muted_by_us, soloed
            for nm in soloed:
                hlib.solo(c, nm, False)
            soloed = []
            if muted_by_us:
                hlib.mute(c, muted_by_us, False); muted_by_us = []
            if mode == "none":
                return True
            if mode == "mute-others":
                names = list(dict.fromkeys(fin.get("others_live", []) + fin.get("click_aux", [])))
                if names and hlib.mute(c, names, True) == "Completed":
                    muted_by_us = names
                return True
            for nm, _ in meta["solo"]:
                hlib.solo(c, nm, True); soloed.append(nm)
            now_tl = {t["id"]: t for t in hlib.tracks(c)}
            return all(hlib.attr(now_tl.get(i, {}), "is_soloed") for _, i in meta["solo"])

        modes = ["solo"] if meta["legacy"] else ["solo", "mute-others"]
        tried, ok_mode = [], None
        for mode in modes:
            if not isolate(mode):
                tried.append(f"{mode}:no-readback"); continue
            for src in [source] + [x for x in srcs if x != source][:4]:
                for frac in (0.5, 0.25):
                    st, db_, fe = _probe(c, n, src, int(end * frac), sr, tempo)
                    tried.append(f"{mode}/{frac}:{db_}")
                    out["probe_db"] = db_
                    if st == "Completed" and db_ is not None and db_ > -50:
                        out["check"]["probe_a"] = _brief(fe)
                        break
                if out["probe_db"] is not None and out["probe_db"] > -50:
                    if src != source:
                        out["note"] = f"beat printed on output '{src}' (not '{source}')"
                    source = src
                    break
            if out["probe_db"] is not None and out["probe_db"] > -50:
                ok_mode = mode
                break
        out["source"] = source
        if ok_mode is None:
            isolate("none")
            st, mix_db, _ = _probe(c, n, source, int(end * 0.5), sr, None)
            out["note"] = f"silent probe (SSL session?); probes {tried}; unsoloed mix probe {mix_db} dB on '{source}'"
            return out
        out["check"]["mode"] = ok_mode
        # listening checks: a 2nd beat window + the complement (beat tracks muted, nothing soloed)
        st, db_, fe = _probe(c, n, source, int(end * 0.75), sr, tempo)
        out["check"]["probe_b"] = _brief(fe)
        beat_ids = [t["name"] for t in fin["tracks"]]
        isolate("none")
        comp = None
        if hlib.mute(c, beat_ids, True) == "Completed":
            muted_by_us = list(beat_ids)
            st, db_, fe = _probe(c, n, source, int(end * 0.5), sr, tempo)
            comp = _brief(fe) or {"v": "silent"}
            if comp.get("db") is None or comp["db"] <= -50:
                comp["v"] = "silent"
            out["check"]["complement"] = comp
            hlib.mute(c, muted_by_us, False); muted_by_us = []
        vs = [out["check"].get(k, {}) and out["check"][k]["v"] for k in ("probe_a", "probe_b")]
        cand_ok = "beat" in vs and "vocal" not in vs
        cv = comp["v"] if comp else None
        conf = meta["confidence"]
        if not meta["legacy"]:
            if not cand_ok:
                out["skip"] = f"beat probes not beat-like ({vs})"
            elif conf == "low":
                if cv == "vocal":
                    conf = "medium"
                else:
                    out["skip"] = f"low-confidence beat set and complement {cv}"
            elif conf == "medium" and cv in ("silent", "beat", None):
                out["skip"] = f"inferred beat set, complement {cv}"
            elif conf == "high" and cv in ("silent", "beat"):
                out["note"] = (out["note"] + "; " if out["note"] else "") + f"complement {cv}"
        elif "vocal" in vs:
            out["note"] = (out["note"] + "; " if out["note"] else "") + "legacy beat probe vocal-like"
        out["confidence"] = conf
        if out["skip"] or probe_only:
            return out
        isolate(ok_mode)
        sel = (0, int(min(end + sr, end * 1.02)))
        out["sel"] = sel
        hlib.set_selection_samples(c, *sel)
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
        try:
            for nm in soloed:
                hlib.solo(c, nm, False)
            if muted_by_us:
                hlib.mute(c, muted_by_us, False)
        finally:
            for p in prior:
                hlib.solo(c, p, True)


def mix_resid_db(n) -> float | None:
    """Level of (mix - beat) on the 11 kHz copies (both printed from sample 0 over one span): what the
    beat lacks, i.e. the vocals. Near silence = the mix is just the beat (vocals muted/absent)."""
    try:
        import numpy as np
        a, b = AUDIO11 / f"{n:04d}_mix.wav", AUDIO11 / f"{n:04d}.wav"
        if not (a.exists() and b.exists()):
            return None
        xm, xb = audiocheck.load(a), audiocheck.load(b)
        L = min(len(xm), len(xb))
        r = xm[:L] - xb[:L]
        return round(float(20 * np.log10(np.sqrt(np.mean(r * r)) + 1e-12)), 1)
    except Exception:
        return None


def stage_mix(c, n, sr, sel, source=None) -> dict:
    """J 01:08: the FULL MIX of the same span, nothing soloed, the session's normal main output.
    The session's own solo state is restored afterwards. -> {path, mean_db, dur, note}"""
    out = {"path": None, "mean_db": None, "dur": None, "note": None, "resid_db": None}
    srcs = hlib.export_sources(c)
    cand = [s for s in ([source] if source else []) + [hlib.pick_source(srcs)] + srcs if s]
    cand = list(dict.fromkeys(cand))
    if not cand:
        out["note"] = "mix: no output sources"; return out
    prior = [t["name"] for t in hlib.tracks(c) if hlib.attr(t, "is_soloed")]
    for p in prior:
        hlib.solo(c, p, False)
    notes = [f"session had {len(prior)} solo(s): mix printed unsoloed"] if prior else []
    try:
        if any(hlib.attr(t, "is_soloed") for t in hlib.tracks(c)):
            out["note"] = "mix: a solo would not clear"; return out
        use = None
        for src in cand[:5]:
            st, db_, _ = _probe(c, n, src, int((sel[0] + sel[1]) / 2), sr, None, tag="mixprobe")
            if st == "Completed" and db_ is not None and db_ > -50:
                use = src; break
        if use is None:
            out["note"] = "mix: silent probe on every output"; return out
        if source and use != source:
            notes.append(f"mix printed on output '{use}'")
        hlib.set_selection_samples(c, *sel)
        st, _ = hlib.export_mix(c, str(AUDIO), f"{n:04d}_mix", int(sr), use, timeout=3600)
        wav = AUDIO / f"{n:04d}_mix.wav"
        if st != "Completed" or not wav.exists():
            out["note"] = f"mix export {st}"; return out
        out["mean_db"] = hlib.mean_db(wav); out["dur"] = hlib.duration_s(wav)
        if out["mean_db"] is None or out["mean_db"] <= -50:
            wav.unlink(); out["note"] = "mix: silent bounce"; return out
        out["path"] = f"audio/{n:04d}_mix.wav"
        if not hlib.to_11k(wav, AUDIO11 / f"{n:04d}_mix.wav"):
            notes.append("mix 11k copy failed")
        out["resid_db"] = mix_resid_db(n)
        if out["resid_db"] is not None and out["resid_db"] < out["mean_db"] - 40:
            notes.append("mix == beat (no vocals heard: residual < -40 dB)")
        return out
    finally:
        for p in prior:
            hlib.solo(c, p, True)
        if notes:
            out["note"] = "; ".join(([out["note"]] if out["note"] else []) + notes)


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
           "status": "error", "reliable": 0, "discovery_method": "mdfind", "notes": [],
           "drive": e.get("drive", "arch1")}
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
        meter = scr["ax_meter"]
        rec.update(session_tempo=scr["ax_tempo"], tempo_raw=scr["ax_tempo_raw"], meter=meter,
                   ocr_tempo=scr["ocr_tempo"], tempo_events=scr["tempo_events"],
                   screenshot_paths=json.dumps(scr["shots"]))
        if not scr["front"].startswith("Pro Tools"):
            rec["notes"].append("PT not frontmost at screenshot")
        bpb = int(meter.split("/")[0]) if meter and meter.split("/")[1] == "4" else 4
        if meter and meter != "4/4":
            rec["notes"].append(f"meter {meter}")
        info = stage_info(c, n, bpb)
        rec.update(edl_tempo=info["edl_tempo"], edl_points=info["edl_points"], edl_on_line=info["edl_on_line"])
        tl = hlib.tracks(c)
        meta, fres = stage_beat_meta(c, tl, info)
        rec.update(finder_version=beatfind.FINDER_VERSION, old_rule=int(bool(fres.get("old_rule"))))
        say(f"#{n:04d} finder: " + " ".join(beatfind.table(fres)))
        if meta is None or meta["confidence"] == "low":
            log_jsonl({"id": n, "kind": "finder-rows", "checked_at": hlib.now(), "why": fres.get("why"),
                       "rows": fres.get("rows")})
        if meta is None:
            rec["status"] = "skip-no-beat"
            rec["notes"].append(f"finder: {fres.get('why')}")
            return rec
        rec["beat_source"] = meta["beat_source"]
        rec["beat_confidence"] = meta["confidence"]
        cm = next((p for p in meta["comments"] if p["bpm"] or p["key"]), None)
        if cm:
            rec.update(beat_comment=cm["raw"], comment_bpm=cm["bpm"], comment_key=cm["key"])
        if len(meta["comments"]) > 1:
            rec["notes"].append(f"{len(meta['comments'])} beat comments")
        rec["producer_bpms"] = json.dumps(meta["producer_bpms"])
        if meta["estimates"]:
            rec["beatdl_estimate"] = meta["estimates"][0]
        if scr["ax_tempo"] and any(hlib.agree(scr["ax_tempo"], e_, 0.001) for e_ in meta["estimates"]):
            rec["tempo_from_estimate"] = 1
        # tempo: the AX Tempo field is the reading (else the single row of the AX Tempo table, else OCR).
        # Flat = the AX Tempo table has exactly one event. The EDL line is a cross-check: its slope must
        # agree with the tempo; points off the line with one tempo event mean a meter change (bars|beats
        # are counted as 4/4), not a tempo change, so that is only noted.
        tempo = scr["ax_tempo"]
        vals = scr.get("tempo_event_values") or []
        if tempo is None and scr["tempo_events"] == 1 and vals:
            tempo = vals[0]; rec["notes"].append("tempo from AX tempo table (field missing)")
        if tempo is None and scr["ocr_tempo"]:
            tempo = scr["ocr_tempo"]; rec["notes"].append("tempo from OCR (AX field missing)")
        if scr["ocr_tempo"] is not None and tempo is not None and not hlib.agree(tempo, scr["ocr_tempo"], 0.0005):
            rec["notes"].append("OCR tempo != AX tempo")
        flat = None
        if scr["tempo_events"] is not None:
            flat = 1 if scr["tempo_events"] == 1 else 0
        elif info["edl_flat"] is not None:
            flat = info["edl_flat"]
        if info["edl_flat"] == 0:
            rec["notes"].append("EDL points off one 4/4 tempo line (meter change?)")
        if tempo and info["edl_tempo"] and not hlib.agree(tempo, info["edl_tempo"], 0.004):
            flat = 0; rec["notes"].append("EDL tempo != session tempo")
        bpm, src, conf = hlib.label(tempo, flat, rec.get("comment_bpm"), meta["producer_bpms"])
        rec.update(bpm=bpm, bpm_source=src, bpm_confidence=conf, tempo_map_flat=flat)
        if KEY_READ and conf in USABLE:          # excluded rows: no key read, no prints (time)
            try:
                at = stage_autotune(n, tl, c)
                rec.update(autotune_key=at["key"], autotune_scale_raw=at["scale_raw"], reliable=at["reliable"],
                           retune_speeds=json.dumps(at["speeds"]), autotune_product=json.dumps(at["products"]),
                           disagreement_detail=at["detail"],
                           autotune_reads=json.dumps([{k: r.get(k) for k in ("slot", "product", "bypassed", "bypass_rgb", "key",
                                                       "scale", "retune", "ok", "lead_named", "err", "inactive", "key_votes")} for r in at["reads"]]))
            except Exception as ex:
                rec["notes"].append(f"autotune read error {type(ex).__name__}")
                hlib.close_plugin_window()
        ck, ak = rec.get("comment_key"), (rec.get("autotune_key") if rec.get("reliable") else None)
        if ck and ak:
            if ck == ak:
                rec.update(key=ck, key_source="comment+autotune")
            else:
                rec["notes"].append("comment key != Auto-Tune key")
        elif ck:
            rec.update(key=ck, key_source="comment")
        elif ak:
            rec.update(key=ak, key_source="autotune")
        b = stage_bounce(c, n, meta, info["sr"], tempo, probe_only=conf not in USABLE)
        rec.update(beat_wav_path=b["path"], beat_mean_db=b["mean_db"], probe_mean_db=b["probe_db"],
                   beat_duration_s=b["dur"], beat_confidence=b["confidence"], beat_check=json.dumps(b["check"]))
        say(f"#{n:04d} listen: {json.dumps(b['check'])}")
        if b["note"]:
            rec["notes"].append(b["note"])
        if b["skip"]:
            rec["status"] = "skip-beat-unsure"; rec["notes"].append(b["skip"])
            return rec
        if conf not in USABLE and b["check"].get("probe_a"):
            rec["status"] = "excluded-checked"          # beat found + listened to; BPM label unusable: no print
            return rec
        rec["status"] = "ok" if b["path"] else ("silent" if b["note"] and "silent" in b["note"] else "error-bounce")
        if b["path"] and conf in USABLE and MIX:
            m = stage_mix(c, n, info["sr"], b["sel"], b["source"])
            rec.update(mix_wav_path=m["path"], mix_mean_db=m["mean_db"], mix_duration_s=m["dur"], mix_note=m["note"],
                       mix_resid_db=m.get("resid_db"))
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


def run_mix_only(n) -> str:
    """Back-fill (J 01:08): re-open a done session and print ONLY its full mix over the beat's span
    (the beat bounce started at 0 and lasted beat_duration_s). Updates the mix_* columns of the row."""
    e = hlib.entry(n)
    con = db()
    dur, = con.execute("SELECT beat_duration_s FROM sessions WHERE id=?", (n,)).fetchone()
    con.close()
    c = hlib.client()
    t0 = time.time()
    m = {"path": None, "mean_db": None, "dur": None, "note": None}
    opened = False
    try:
        st, secs = stage_open(c, e)
        say(f"#{n:04d} mix-only open {st} {secs}s")
        if st != "Completed":
            m["note"] = f"mix-only: open {st}"
            opened = hlib.session_open(c)
            return "error-open"
        opened = True
        sr = float(hlib.parse_info(hlib.export_info(c, "TLType_Samples"))["header"].get("SAMPLE RATE", "0") or 0)
        if not sr or not dur:
            m["note"] = "mix-only: no sample rate / beat duration"; return "error"
        m = stage_mix(c, n, sr, (0, int(round(dur * sr))))
        return "ok" if m["path"] else "fail"
    except BaseException as ex:
        m["note"] = f"mix-only error {type(ex).__name__}: {hlib.redact(str(ex))[:120]}"
        say("EXC", hlib.redact(traceback.format_exc())[-600:])
        if isinstance(ex, KeyboardInterrupt):
            raise
        return "error"
    finally:
        if opened:
            try:
                stage_close(c)
            except BaseException:
                pass
        try:
            w = source_writes(e["ptx"], t0 - 1)
        except Exception:
            w = 0
        con = db()
        con.execute("UPDATE sessions SET mix_wav_path=?, mix_mean_db=?, mix_duration_s=?, mix_resid_db=?, mix_note=? "
                    "WHERE id=?",
                    (m["path"], m["mean_db"], m["dur"], m.get("resid_db"),
                     "; ".join(x for x in (m["note"], "back-filled", f"PT wrote {w} file(s) on the source drive" if w else None) if x),
                     n))
        con.commit(); con.close()
        log_jsonl({"id": n, "kind": "mix-backfill", "checked_at": hlib.now(), "mix_mean_db": m["mean_db"],
                   "mix_duration_s": m["dur"], "note": m["note"], "elapsed_s": round(time.time() - t0, 1)})
        say(f"#{n:04d} mix-only {m['path'] is not None} mix_dB={m['mean_db']} dur={m['dur']} {round(time.time() - t0)}s "
            f"note={m['note']}")


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
                                        "beat_duration_s", "open_s", "close", "elapsed_s", "notes", "drive",
                                        "finder_version", "beat_source", "beat_confidence", "beat_check", "old_rule",
                                        "mix_mean_db", "mix_duration_s", "mix_resid_db", "mix_note")})
    say(f"#{rec['id']:04d} {rec['status']} tempo={rec.get('session_tempo')} edl={rec.get('edl_tempo')} "
        f"flat={rec.get('tempo_map_flat')} comment={rec.get('beat_comment')} -> bpm={rec.get('bpm')} "
        f"{rec.get('bpm_confidence')} ({rec.get('bpm_source')}) key={rec.get('key')} "
        f"beat={rec.get('beat_source')}/{rec.get('beat_confidence')} wav_dB={rec.get('beat_mean_db')} "
        f"mix_dB={rec.get('mix_mean_db')} {rec.get('elapsed_s')}s close={rec.get('close')} notes={rec.get('notes')} "
        f"mix_note={rec.get('mix_note')}")


USABLE_SQL = "beat_wav_path IS NOT NULL AND bpm_confidence IN ('confirmed','tempo-only')"


def usable_count(con):
    return con.execute(f"SELECT count(*) FROM sessions WHERE {USABLE_SQL}").fetchone()[0]


def relaunch_pt():
    say("killing Pro Tools (hung) and relaunching")
    subprocess.run(["pkill", "-9", "-f", "Pro Tools.app/Contents/MacOS/Pro Tools"])
    time.sleep(10)
    r = subprocess.run([str(H / ".venv/bin/python"), str(H / "pt_launch.py"), "100"], capture_output=True, text=True)
    say("relaunch:", r.stdout.strip().splitlines()[-1:] if r.stdout else r.returncode)
    time.sleep(20)


def _gate():
    """-> rc to stop with, or None to go on."""
    if STOP.exists():
        say("STOP file present: stopping"); return 0
    b = blocked()
    if b:
        say("BLOCKED:", b); return 3
    c = hlib.client()
    if hlib.session_open(c):
        hlib.close_no_save(c)
    return None


def _after_error(n, status, notes, fails_in_row):
    if status in ("error-open", "error-_InactiveRpcError", "error-PtslError") or "deadline" in str(notes).lower():
        shot = H / "shots" / f"error-{n:04d}.png"
        subprocess.run(["screencapture", "-x", str(shot)])
        if blocked():
            say("BLOCKED after error:", blocked()); return 3
        relaunch_pt()
    if fails_in_row >= 4:
        say("4 errors in a row: stopping for a human look"); return 4
    return None


def batch(target=200, max_n=10**6):
    con = db()
    done = {r[0] for r in con.execute("SELECT id FROM sessions WHERE status NOT LIKE 'error%'")}
    tries = {r[0]: r[1] for r in con.execute("SELECT id, notes FROM sessions WHERE status LIKE 'error%'")}
    backfill = [r[0] for r in con.execute(f"SELECT id FROM sessions WHERE {USABLE_SQL} AND mix_wav_path IS NULL "
                                          f"AND mix_note IS NULL ORDER BY id")]
    con.close()
    fails_in_row = 0
    man = hlib.manifest()
    say(f"batch start: {len(done)} done, target {target} usable; manifest {len(man)}; "
        f"mix back-fill {len(backfill) if MIX else 0}")
    # 1. J 01:08: full-mix back-fill for usable rows printed before the mix existed
    for n in (backfill if MIX else []):
        rc = _gate()
        if rc is not None:
            return rc
        r = run_mix_only(n)
        fails_in_row = fails_in_row + 1 if r.startswith("error") else 0
        if r.startswith("error"):
            rc = _after_error(n, "error-open" if r == "error-open" else "error", "", fails_in_row)
            if rc is not None:
                return rc
    # 2. the manifest in order; rows the v1 name-only rule skipped are re-run with the v2 finder
    for e in man:
        n = e["n"]
        if n > max_n:
            continue
        con = db()
        r = con.execute("SELECT status, notes, finder_version, bpm_confidence FROM sessions WHERE id=?", (n,)).fetchone()
        con.close()
        # rows an older finder skipped get one more look by a newer finder (unusable BPM labels excepted)
        requeue = bool(r and (r[2] or 0) < beatfind.FINDER_VERSION and
                       (r[0] in ("skip-no-beat-buss", "skip-no-beat") or
                        (r[0] == "skip-beat-unsure" and r[3] in USABLE)))
        if r and not r[0].startswith("error") and not requeue:
            continue                                   # done (re-read every time: rows may be dropped to redo)
        if n in tries and "retried" in (tries[n] or ""):
            continue
        con = db(); u = usable_count(con); con.close()
        if u >= target:
            say(f"target reached: {u} usable rows"); return 0
        rc = _gate()
        if rc is not None:
            return rc
        if requeue:
            say(f"#{n:04d} re-queued (an older finder skipped it: {r[0]})")
        rec = run_one(n)
        if n in tries:
            con = db()
            con.execute("UPDATE sessions SET notes = coalesce(notes,'') || '; retried' WHERE id=?", (n,))
            con.commit(); con.close()
        if rec["status"].startswith("error"):
            fails_in_row += 1
            rc = _after_error(n, rec["status"], rec.get("notes"), fails_in_row)
            if rc is not None:
                return rc
        else:
            fails_in_row = 0
    con = db(); u = usable_count(con); con.close()
    say(f"manifest exhausted: {u} usable rows"); return 0


def status():
    con = db()
    for r in con.execute("SELECT status, bpm_confidence, count(*) FROM sessions GROUP BY 1,2 ORDER BY 3 DESC"):
        print(r)
    u = usable_count(con)
    conf = con.execute(f"SELECT count(*) FROM sessions WHERE {USABLE_SQL} AND bpm_confidence='confirmed'").fetchone()[0]
    key = con.execute(f"SELECT count(*) FROM sessions WHERE {USABLE_SQL} AND key IS NOT NULL").fetchone()[0]
    mix = con.execute(f"SELECT count(*) FROM sessions WHERE {USABLE_SQL} AND mix_wav_path IS NOT NULL").fetchone()[0]
    print(f"usable {u} (confirmed {conf}, tempo-only {u - conf}, with key {key}); with full mix {mix}")
    for r in con.execute(f"SELECT coalesce(beat_source,'-'), coalesce(beat_confidence,'-'), count(*) FROM sessions "
                         f"WHERE {USABLE_SQL} GROUP BY 1,2 ORDER BY 3 DESC"):
        print("  beat source", r)
    for r in con.execute("SELECT coalesce(drive,'arch1'), count(*) FROM sessions GROUP BY 1"):
        print("  drive", r)
    r = con.execute("SELECT avg(elapsed_s), max(id) FROM sessions").fetchone()
    print("avg s/session", round(r[0] or 0), "last id", r[1])


if __name__ == "__main__":
    cmd = sys.argv[1]
    rc = 0
    try:
        if cmd == "one":
            run_one(int(sys.argv[2]), "--already-open" in sys.argv, "--keep-open" in sys.argv)
        elif cmd == "mix":
            run_mix_only(int(sys.argv[2]))
        elif cmd == "batch":
            a = sys.argv
            rc = batch(int(a[a.index("--target") + 1]) if "--target" in a else 200,
                       int(a[a.index("--max-n") + 1]) if "--max-n" in a else 10**6)
        elif cmd == "resid":                       # fill mix_resid_db where both 11k files exist
            con = db()
            for (n,) in con.execute("SELECT id FROM sessions WHERE mix_wav_path IS NOT NULL AND mix_resid_db IS NULL").fetchall():
                r = mix_resid_db(n)
                con.execute("UPDATE sessions SET mix_resid_db=? WHERE id=?", (r, n)); con.commit()
                print(f"#{n:04d} resid {r}")
            con.close()
        elif cmd == "status":
            status()
    except BaseException as ex:
        print("ERR", type(ex).__name__, hlib.redact(ex)[:300])
        rc = 1 if cmd == "batch" else 0          # a crashed batch is restarted by run_batch.sh (rc 0 = done)
    sys.stdout.flush(); os._exit(rc)
