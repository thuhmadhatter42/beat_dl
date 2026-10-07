"""Shared harvest library (runs on Sofia with ~/pt-harvest/.venv).
Name rule (J 2026-10-06): sessions are known by number + sha1 only. Nothing printed, logged or
committed carries a song, artist, track or file name. redact() guards every free-text message."""
from __future__ import annotations
import hashlib, json, os, re, subprocess, sys, time
from pathlib import Path

HOME = Path.home()
H = HOME / "pt-harvest"
sys.path.insert(0, str(HOME / "ProTools SDK" / "stem-bouncer"))
from pt_stems.client import PtslClient, PtslError, _port_open  # noqa: E402

MANIFEST = H / "manifest.json"
_SET = {"TAState_SetExplicitly", "TAState_SetImplicitly", "TAState_SetExplicitlyAndImplicitly"}
# track names safe to print (structural, no song/artist content)
STRUCTURAL = {"beat buss", "master", "vocal stem", "all vox", "all fx", "click", "click 1", "beat",
              "printer", "print", "ny", "mod", "hall", "plate", "1/2", "1/4", "1/8"}
_secrets: set[str] = set()


def manifest():
    return json.load(open(MANIFEST))


def entry(n: int) -> dict:
    e = next(e for e in manifest() if e["n"] == n)
    register_secret_path(e["ptx"])
    return e


def register_secret_path(p: str):
    _secrets.add(p)
    for part in Path(p).parts:
        if len(part) > 3 and part not in ("/", "Volumes", "Users"):
            _secrets.add(part)
            _secrets.add(Path(part).stem)


def register_secret(s: str):
    if s and len(s.strip()) > 2:
        _secrets.add(s.strip())


def redact(s) -> str:
    s = str(s)
    for sec in sorted(_secrets, key=len, reverse=True):
        if sec and sec.lower() not in STRUCTURAL:
            s = s.replace(sec, "<name>")
    s = re.sub(r"/Volumes/[^\"'\n]*", "<path>", s)
    s = re.sub(r"[^\s\"']*\.(ptx|wav|aif|aiff|mp3)\b", "<file>", s, flags=re.I)
    return s


_STRUCT_RX = re.compile(r"^(beats?|instr?u?m?e?n?t?a?l?s?|music|vocals?|vox|all|fx|stem|bus{1,2}|aux|master|print(er)?"
                        r"|\s|[-_.0-9])+$", re.I)


def safe_track_name(name: str) -> str:
    n = name.strip()
    return n if (n.lower() in STRUCTURAL or (len(n) <= 24 and _STRUCT_RX.match(n))) else "<t>"


def is_beat_buss(name: str) -> bool:
    """J (spec §7.2): the beat folder is 'Beat Buss'. Accept spelling variants of beat + bus."""
    return bool(re.fullmatch(r"\s*beats?\s*bus{1,2}\s*", name, re.I))


def attr(t: dict, k: str) -> bool:
    v = (t.get("track_attributes") or {}).get(k)
    return v in _SET if isinstance(v, str) else bool(v)


def client() -> PtslClient:
    return PtslClient(autolaunch=False)


def tracks(c) -> list[dict]:
    tl = c.send("CId_GetTrackList", {"pagination_request": {"limit": 1000, "offset": 0},
                                     "track_filter_list": [{"filter": "TLFilter_All", "is_inverted": False}],
                                     "is_filter_list_additive": True}).get("track_list", [])
    for t in tl:
        register_secret(t.get("name", ""))
    return tl


def session_open(c) -> bool:
    try:
        r = c.send("CId_GetSessionName", timeout=20)
        return bool(r.get("session_name"))
    except PtslError:
        return False


def close_no_save(c, timeout=180):
    return c.status_of("CId_CloseSession", {"save_on_close": False}, timeout=timeout)[0]


def export_info(c, location_type: str | None = None) -> str:
    body = {"include_file_list": True, "include_clip_list": False, "include_markers": True,
            "include_plugin_list": True, "include_track_edls": True,
            "show_sub_frames": True, "include_user_timestamps": False,
            "track_list_type": "AllTracks", "fade_handling_type": "DontShowCrossfades",
            "text_as_file_format": "UTF8", "output_type": "ESI_String"}
    if location_type:
        body["location_type"] = location_type
    return c.send("CId_ExportSessionInfoAsText", body, timeout=600).get("session_info", "")


# ---------- session-info text parsing ----------

def parse_info(text: str) -> dict:
    """-> {header:{}, files:[...], tracks:[{name, comment, state, plugins[], edl:[(start,end,clip,state)]}]}"""
    out = {"header": {}, "files": [], "tracks": [], "markers": []}
    lines = text.splitlines()
    sec = "header"; cur = None
    for ln in lines:
        s = ln.strip()
        if s.startswith("O N L I N E  F I L E S"):
            sec = "files"; continue
        if s.startswith("O F F L I N E  F I L E S") or s.startswith("O N L I N E  C L I P S"):
            sec = "other"; continue
        if s.startswith("T R A C K  L I S T I N G"):
            sec = "tracks"; continue
        if s.startswith("M A R K E R S"):
            sec = "markers"; continue
        if s.startswith("P L U G - I N S") :
            sec = "other"; continue
        if sec == "header" and ":" in ln:
            k, v = ln.split(":", 1); out["header"][k.strip()] = v.strip()
        elif sec == "files" and "\t" in ln and not ln.startswith("Filename"):
            out["files"].append(ln.split("\t")[0].strip())
        elif sec == "tracks":
            if ln.startswith("TRACK NAME:"):
                cur = {"name": ln.split("\t", 1)[1].strip() if "\t" in ln else ln[11:].strip(),
                       "comment": "", "state": "", "plugins": [], "edl": []}
                out["tracks"].append(cur)
            elif cur is None:
                continue
            elif ln.startswith("COMMENTS:"):
                cur["comment"] = ln[9:].strip()
            elif ln.startswith("STATE:"):
                cur["state"] = ln[6:].strip()
            elif ln.startswith("PLUG-INS:"):
                cur["plugins"] = [p.strip() for p in ln[9:].split("\t") if p.strip()]
            elif re.match(r"^\d+\s*\t\s*\d+\s*\t", ln):
                f = [x.strip() for x in ln.split("\t")]
                if len(f) >= 6:
                    cur["edl"].append({"ch": f[0], "ev": f[1], "clip": f[2], "start": f[3], "end": f[4],
                                       "state": f[-1]})
        elif sec == "markers" and "\t" in ln:
            out["markers"].append([x.strip() for x in ln.split("\t")])
    for t in out["tracks"]:
        register_secret(re.sub(r"\s*\((Stereo|Mono)\)$", "", t["name"]))
        register_secret(t["name"])
    for f in out["files"]:
        register_secret(f); register_secret(Path(f).stem)
    return out


def _bars_to_ticks(s: str):
    m = re.match(r"^\s*(\d+)\|\s*(\d+)\|\s*(\d+)\s*$", s)
    return (int(m[1]), int(m[2]), int(m[3])) if m else None


def edl_points(info_bb: dict, info_samples: dict, beats_per_bar: int) -> list[tuple[float, int]]:
    """(beat position, sample position) for every EDL clip boundary, from the same EDL exported in
    Bars|Beats|ticks (960 ticks per beat) and in Samples."""
    pts = set()
    for tb, ts in zip(info_bb["tracks"], info_samples["tracks"]):
        if len(tb["edl"]) != len(ts["edl"]):
            continue
        for eb, es in zip(tb["edl"], ts["edl"]):
            for k in ("start", "end"):
                bbt = _bars_to_ticks(eb[k])
                try:
                    sm = int(es[k])
                except ValueError:
                    continue
                if bbt:
                    bar, beat, tick = bbt
                    pts.add(((bar - 1) * beats_per_bar + (beat - 1) + tick / 960.0, sm))
    return sorted(pts)


def edl_tempo(points, sr: float, tol_beats=1 / 16):
    """Theil-Sen slope of samples vs beats -> tempo. Flat if >=90 % of points sit within a 16th
    note of the line (a real tempo change bends it by far more; PT's tick rounding and small
    wobbles do not). -> (tempo|None, flat 0/1/None, n_points, frac_on_line)"""
    import statistics
    pts = [p for p in points if p[0] > 0]
    if len(pts) < 4:
        return None, None, len(pts), None
    sub = pts if len(pts) <= 400 else pts[:: len(pts) // 400 + 1]
    slopes = [(b[1] - a[1]) / (b[0] - a[0]) for i, a in enumerate(sub) for b in sub[i + 1:] if b[0] - a[0] >= 4]
    if not slopes:
        return None, None, len(pts), None
    spb = statistics.median(slopes)                      # samples per beat
    icpt = statistics.median(s - spb * b for b, s in pts)
    on = sum(1 for b, s in pts if abs(s - (icpt + spb * b)) <= tol_beats * spb) / len(pts)
    tempo = 60.0 * sr / spb
    return round(tempo, 4), (1 if on >= 0.9 else 0), len(pts), round(on, 3)


# ---------- labels ----------
NOTE = r"([A-G](?:#|b|♯|♭)?)"
_BEATDL = re.compile(r"\(\s*\d{2,3}\.\d\s*BPM\s+[A-G][^)]*\)", re.I)  # our own estimate: never a label
# producer BPMs are whole numbers ("140bpm", "140 BPM"); a decimal ("134.7 bpm") is an estimate
# (beat_dl's style or similar) and never counts as an independent source
_PROD_BPM = re.compile(r"(?<![\d.])(\d{2,3})(?![\d.])\s*-?\s*bpm\b", re.I)


def producer_bpms(names: list[str]) -> list[float]:
    vals = []
    for nm in names:
        nm2 = _BEATDL.sub(" ", nm)
        for m in _PROD_BPM.finditer(nm2):
            v = float(m[1])
            if 50 <= v <= 220:
                vals.append(v)
    return sorted(set(vals))


def estimate_bpms(names: list[str]) -> list[float]:
    """Decimal 'NN.N BPM' tokens (beat_dl's estimate style) -> used only to FLAG a session tempo
    that was copied from an estimate, never as a label source."""
    vals = set()
    for nm in names:
        for m in re.finditer(r"(?<![\d.])(\d{2,3}\.\d+)\s*bpm\b", nm, re.I):
            vals.add(float(m[1]))
    return sorted(vals)


def parse_comment(c: str) -> dict:
    """'Dm152' -> {'key': 'D minor', 'bpm': 152.0}. Accepts 'D#m 140', '140 Dm', 'Gmaj 90', 'F# 128'."""
    out = {"key": None, "bpm": None}
    if not c:
        return out
    s = c.strip()
    KEY = NOTE + r"\s*(maj(?:or)?|min(?:or)?|m|M)?"
    BPM = r"(\d{2,3}(?:\.\d+)?)\s*(?:bpm)?"
    # the WHOLE comment must be key+bpm, bpm+key, key alone or bpm alone (strict: 'ECHOBOY' is no key)
    for pat, ki, bi in ((rf"^{KEY}\s*[-/,]?\s*{BPM}$", 1, 3), (rf"^{BPM}\s*[-/,]?\s*{KEY}$", 2, 1),
                        (rf"^{KEY}$", 1, None), (rf"^{BPM}$", None, 1)):
        m = re.match(pat, s, re.I if ki is None else 0)
        if not m:
            continue
        if ki:
            note = m[ki].replace("♯", "#").replace("♭", "b")
            q = m[ki + 1] or ""
            minor = q == "m" or q.lower().startswith("min")
            out["key"] = f"{note} {'minor' if minor else 'major'}"
        if bi and 50 <= float(m[bi]) <= 220:
            out["bpm"] = float(m[bi])
        break
    return out


def agree(a, b, tol=0.01):
    return a is not None and b is not None and abs(a - b) <= tol * max(a, b)


def label(session_tempo, flat, comment_bpm, prod_bpms):
    """-> (bpm, bpm_source, bpm_confidence)"""
    if session_tempo is None:
        return None, "none", "excluded"
    srcs = []
    if agree(session_tempo, comment_bpm):
        srcs.append("comment")
    if any(agree(session_tempo, p) for p in prod_bpms):
        srcs.append("producer-filename")
    if flat == 0:
        return session_tempo, "session+" + "+".join(srcs) if srcs else "session", "excluded"
    if srcs:
        return session_tempo, "session+" + "+".join(srcs), "confirmed"
    if abs(session_tempo - 120.0) < 1e-6:
        return session_tempo, "session", "excluded"
    return session_tempo, "session", "tempo-only"


def mean_db(path) -> float | None:
    r = subprocess.run(["/usr/local/bin/ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af",
                        "volumedetect", "-f", "null", "/dev/null"], capture_output=True, text=True).stderr
    m = re.search(r"mean_volume:\s*(-?[\d.]+) dB", r)
    return float(m[1]) if m else None


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


# ---------- beat bounce ----------

def beat_tree(tl: list[dict]):
    """-> (beat folder track | None, [descendant tracks])."""
    by_id = {t["id"]: t for t in tl}
    folders = [t for t in tl if is_beat_buss(t["name"]) and t["type"] in ("TType_RoutingFolder", "TType_BasicFolder")]
    if not folders:
        return None, []
    f = folders[0]

    def under(t):
        cur = t
        while cur.get("parent_folder_id") in by_id:
            cur = by_id[cur["parent_folder_id"]]
            if cur["id"] == f["id"]:
                return True
        return False
    return f, [t for t in tl if under(t)]


def export_sources(c) -> list[str]:
    st, b = c.status_of("CId_GetExportMixSourceList", {"type": "EMSType_Output"})
    return [s for s in (b.get("source_list") or [])] if st == "Completed" else []


def pick_source(srcs: list[str]) -> str | None:
    for want in ("1-2", "A 1-2", "Main Output L/R", "Out 1-2"):
        if want in srcs:
            return want
    return next((s for s in srcs if re.search(r"\b1-2\b", s)), None)


def set_selection_samples(c, a: int, b: int) -> str:
    c.status_of("CId_SetMainCounterFormat", {"location_type": "TLType_Samples"})
    st, body = c.status_of("CId_SetTimelineSelection", {
        "play_start_marker_time": str(a), "in_time": str(a), "out_time": str(b),
        "pre_roll_start_time": str(a), "post_roll_stop_time": str(b),
        "pre_roll_enabled": "TBool_False", "post_roll_enabled": "TBool_False",
        "update_video_to": "TUV_None", "propagate_to_satellites": "TBool_False",
        "location_type": "TLType_Samples"})
    c.status_of("CId_SetMainCounterFormat", {"location_type": "TLType_BarsBeats"})
    return st


def solo(c, name: str, on: bool):
    return c.status_of("CId_SetTrackSoloState", {"track_names": [name], "enabled": on})[0]


def export_mix(c, out_dir: str, stem: str, sr: int, source: str, timeout=3600) -> tuple[str, dict]:
    return c.status_of("CId_ExportMix", {
        "file_name": stem, "file_type": "EMFType_WAV",
        "audio_info": {"compression_type": "CT_PCM", "export_format": "EF_Interleaved", "bit_depth": "Bit24",
                       "sample_rate": "SR_None", "sample_rate_custom": int(sr),
                       "pad_to_frame_boundary": "TB_False", "delivery_format": "EM_DF_SingleFile"},
        "location_info": {"file_destination": "EMFDestination_Directory", "directory": out_dir.rstrip("/") + "/",
                          "import_after_bounce": "TBool_False"},
        "offline_bounce": "TBool_True",
        "mix_source_list": [{"source_type": "EMSType_Output", "name": source}],
        "audio_encoding_options": {}}, timeout=timeout)


def to_11k(src, dst) -> bool:
    r = subprocess.run(["/usr/local/bin/ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(src),
                        "-ac", "1", "-ar", "11025", "-sample_fmt", "s16", str(dst)], capture_output=True, text=True)
    return r.returncode == 0 and Path(dst).exists()


def duration_s(path) -> float | None:
    r = subprocess.run(["/usr/local/bin/ffprobe", "-v", "error", "-show_entries", "format=duration", "-of",
                        "default=nw=1:nk=1", str(path)], capture_output=True, text=True)
    try:
        return float(r.stdout.strip())
    except ValueError:
        return None


# ---------- screen + OCR (Sofia console; Quartz + Vision) ----------
TOOLBAR = (560, 58, 1360, 92)     # Edit window toolbar below the title bar (no names there)
RULERS = (420, 140, 1160, 130)    # ruler stack left of the clip list


def screenshot(path):
    from PIL import Image
    subprocess.run(["screencapture", "-x", str(path)], check=True)
    img = Image.open(path).convert("RGB")
    if img.size[0] != 1920:
        img = img.resize((1920, int(img.size[1] * 1920 / img.size[0])))
    return img


def crop(img, box, scale=2.0):
    from PIL import Image
    x, y, w, h = box
    return img.crop((x, y, x + w, y + h)).resize((int(w * scale), int(h * scale)), Image.LANCZOS)


def ocr(pil_img):
    """-> [(text, conf, x, y, w, h)] in crop pixel coords, y from top."""
    import io, Vision
    from Foundation import NSData
    buf = io.BytesIO(); pil_img.save(buf, "PNG")
    raw = buf.getvalue()
    data = NSData.dataWithBytes_length_(raw, len(raw))
    req = Vision.VNRecognizeTextRequest.alloc().init()
    req.setRecognitionLevel_(0)  # accurate
    req.setUsesLanguageCorrection_(False)
    h = Vision.VNImageRequestHandler.alloc().initWithData_options_(data, None)
    h.performRequests_error_([req], None)
    W, Hh = pil_img.size
    out = []
    for r in req.results() or []:
        cand = r.topCandidates_(1)[0]
        bb = r.boundingBox()
        out.append((str(cand.string()), float(cand.confidence()), bb.origin.x * W,
                    (1 - bb.origin.y - bb.size.height) * Hh, bb.size.width * W, bb.size.height * Hh))
    return out


def _right_of(toks, label, rx):
    for t in toks:
        if label.lower() in t[0].lower():
            m = re.search(label + r"\D*?(" + rx + r")", t[0], re.I)
            if m:
                return m[1]
            cy = t[3] + t[5] / 2
            cands = [u for u in toks if u is not t and u[2] > t[2] and abs((u[3] + u[5] / 2) - cy) < t[5] * 0.8
                     and re.search(rx, u[0])]
            if cands:
                u = min(cands, key=lambda u: u[2])
                return re.search(rx, u[0])[0]
    return None


def read_toolbar(img) -> dict:
    """'Tempo' and 'Meter' from the toolbar OCR: the value is the nearest numeric token to the
    right on the same line (or inside the same token)."""
    toks = ocr(crop(img, TOOLBAR, 2.0))
    tr = _right_of(toks, "Tempo", r"\d{2,3}\.\d{2,4}|\d{2,3}")
    mr = _right_of(toks, "Meter", r"\d{1,2}\s*/\s*\d{1,2}")
    return {"tempo": float(tr) if tr else None, "tempo_raw": tr,
            "meter": mr.replace(" ", "") if mr else None}


def ax_edit_tempo() -> dict:
    """Tempo straight from the Edit window's Accessibility tree (no screen needed):
    the 'Tempo value' text field, the 'Tempo' table (one row per tempo event) and the Meter value."""
    import dialog_clicker as dc
    out = {"ax_tempo": None, "ax_tempo_raw": None, "tempo_events": None, "tempo_event_values": [], "ax_meter": None,
           "edit_frame": None}
    edit = next((d for d in dc.windows() if d["title"].startswith("Edit:")), None)
    if edit is None:
        return out
    out["edit_frame"] = (*edit["pos"], *edit["size"])

    def kids(el):
        return dc._ax(el, "AXChildren") or []

    def walk(el, depth, maxd):
        yield el
        if depth < maxd:
            for k in kids(el):
                yield from walk(k, depth + 1, maxd)
    for el in walk(edit["el"], 0, 2):
        role = dc._ax(el, "AXRole"); title = str(dc._ax(el, "AXTitle") or "")
        if role == "AXTextField" and title.startswith("Tempo"):
            raw = str(dc._ax(el, "AXValue") or "").strip()
            m = re.search(r"\d{2,3}(?:\.\d+)?", raw)
            out["ax_tempo_raw"] = raw
            out["ax_tempo"] = float(m[0]) if m else None
            import ApplicationServices as AS
            p = dc._xy(dc._ax(el, "AXPosition"), AS.kAXValueCGPointType)
            s = dc._xy(dc._ax(el, "AXSize"), AS.kAXValueCGSizeType)
            if p and s:
                out["tempo_field_frame"] = (int(p.x), int(p.y), int(s.width), int(s.height))
        elif role == "AXButton" and title.startswith("Meter") and out["ax_meter"] is None:
            v = str(dc._ax(el, "AXValue") or "")
            m = re.search(r"\b(\d{1,2}/\d{1,2})\b", v)
            out["ax_meter"] = m[1] if m else None
        elif role == "AXTable" and title.startswith("Tempo"):
            rows = dc._ax(el, "AXRows") or []
            out["tempo_events"] = len(rows)
            vals = []
            for r in rows[:50]:
                for c in walk(r, 0, 3):
                    v = dc._ax(c, "AXValue")
                    if isinstance(v, str) and re.fullmatch(r"\s*\d{2,3}\.\d+\s*", v):
                        vals.append(float(v)); break
            out["tempo_event_values"] = vals
    return out


# ---------- Auto-Tune key read (spec §2.4) ----------
_NOTE_RX = re.compile(r"^([A-G])\s*([#♯b♭]?)$")
_SCALES = ("Major", "Minor", "Chromatic", "Dorian", "Phrygian", "Lydian", "Mixolydian", "Locrian", "Aeolian",
           "Ionian", "Harmonic Minor", "Melodic Minor", "Blues", "Pentatonic")


def _below(toks, label_rx, val_rx, max_dy=80, max_dx=70):
    labs = [t for t in toks if re.fullmatch(label_rx, t[0].strip(), re.I)]
    for L in labs:
        lx = L[2] + L[4] / 2; ly = L[3] + L[5]
        c = [t for t in toks if t is not L and 0 <= t[3] - ly <= max_dy and abs(t[2] + t[4] / 2 - lx) <= max_dx
             and re.search(val_rx, t[0].strip(), re.I)]
        if c:
            return min(c, key=lambda t: t[3])[0].strip()
    return None


def ocr_small(pil_img, scale=5):
    """OCR for 1-3 character values (Vision drops lone glyphs at native size): grayscale, invert to
    dark-on-light, upscale, pad. -> joined text."""
    from PIL import Image, ImageOps
    g = ImageOps.invert(pil_img.convert("L"))
    g = g.resize((g.width * scale, g.height * scale), Image.LANCZOS)
    pad = Image.new("L", (g.width + 200, g.height + 200), 255)
    pad.paste(g, (100, 100))
    return " ".join(t[0] for t in ocr(pad.convert("RGB"))).strip()


def _value_under(img, toks, label_rx, sc, dy=(4, 44), dx=50):
    """Value box under a label in the body crop (coords /sc back to the 1x body image)."""
    for L in toks:
        if re.fullmatch(label_rx, L[0].strip(), re.I):
            cx = (L[2] + L[4] / 2) / sc; by = (L[3] + L[5]) / sc
            box = (int(cx - dx), int(by + dy[0]), int(cx + dx), int(by + dy[1]))
            return ocr_small(img.crop(box))
    return None


def edit_strips():
    """-> {track name: [AX insert-assignment buttons whose value names Auto-Tune, with slot letter]}"""
    import dialog_clicker as dc
    edit = next((d for d in dc.windows() if d["title"].startswith("Edit:")), None)
    out = {}
    if edit is None:
        return out
    for s in dc._ax(edit["el"], "AXChildren") or []:
        if dc._ax(s, "AXRole") != "AXGroup":
            continue
        name = str(dc._ax(s, "AXTitle") or "")
        name = re.sub(r" - [A-Za-z ]*Track\s*$", "", name)      # strip title = "<track> - Audio Track "
        for g in dc._ax(s, "AXChildren") or []:
            if "Insert" not in str(dc._ax(g, "AXTitle") or ""):
                continue
            for b in dc._ax(g, "AXChildren") or []:
                t = str(dc._ax(b, "AXTitle") or ""); v = str(dc._ax(b, "AXValue") or "")
                if t.startswith("Insert Assignment") and re.search(r"Auto-?Tune", v, re.I):
                    out.setdefault(name, []).append((t[-1], v, b))
    return out


def plugin_window():
    import dialog_clicker as dc
    return next((d for d in dc.windows() if d["title"].startswith("Plug-in:")), None)


def close_plugin_window():
    import dialog_clicker as dc
    import ApplicationServices as AS
    for _ in range(3):
        w = plugin_window()
        if w is None:
            return True
        cb = dc._ax(w["el"], "AXCloseButton")
        if cb is not None:
            AS.AXUIElementPerformAction(cb, "AXPress")
        time.sleep(1)
    return plugin_window() is None


def read_autotune(button, shot_path) -> dict:
    """Open one Auto-Tune insert (AXPress on its insert-assignment button), read product, bypass,
    Key, Scale, Retune Speed from the plug-in window, close it. Returns a dict; values None when
    not read confidently (never guessed)."""
    import ApplicationServices as AS
    import dialog_clicker as dc
    res = {"product": None, "bypassed": None, "key": None, "scale": None, "retune": None, "ok": False}
    close_plugin_window()
    if AS.AXUIElementPerformAction(button, "AXPress") != 0:
        res["err"] = "press failed"; return res
    w = None
    for _ in range(10):
        time.sleep(0.5)
        w = plugin_window()
        if w:
            break
    if not w:
        res["err"] = "no plug-in window"; return res
    try:
        time.sleep(1.5)                       # let the GUI paint
        stack = [(w["el"], 0)]
        bypass_el = None
        while stack:
            el, d = stack.pop()
            t = str(dc._ax(el, "AXTitle") or "")
            if t.startswith("Plugin Selector"):
                res["product"] = str(dc._ax(el, "AXValue") or "")
            elif t == "Effect Bypass":
                bypass_el = el
            if d < 4:
                stack += [(k, d + 1) for k in (dc._ax(el, "AXChildren") or [])]
        img = screenshot(shot_path)
        x, y = int(w["pos"][0]), int(w["pos"][1])
        ww, wh = int(w["size"][0]), int(w["size"][1])
        if bypass_el is not None:
            p = dc._xy(dc._ax(bypass_el, "AXPosition"), AS.kAXValueCGPointType)
            s = dc._xy(dc._ax(bypass_el, "AXSize"), AS.kAXValueCGSizeType)
            if p and s and s.width > 4:
                px = img.crop((int(p.x) + 2, int(p.y) + 2, int(p.x + s.width) - 2, int(p.y + s.height) - 2)).resize((1, 1)).getpixel((0, 0))
                res["bypass_rgb"] = px
                # lit BYPASS is orange/yellow; unlit is grey
                res["bypassed"] = bool(px[0] > 150 and px[0] - px[2] > 60)
        body = (x, y + 75, ww, max(wh - 75, 10))
        bimg = crop(img, body, 1.0)
        toks = ocr(crop(img, body, 2.0))
        key = _below(toks, r"Key", r"^[A-G]\s*[#♯b♭]?$")
        if not key:
            raw = _value_under(bimg, toks, r"Key", 2.0, dy=(4, 30), dx=28) or ""
            m = re.match(r"^\s*([A-G])\s*([#♯b♭])?", raw)
            key = (m[1] + (m[2] or "")) if m else None
        scale = _below(toks, r"Scale", r"^(" + "|".join(_SCALES) + r")\b")
        rs = _below(toks, r"Retune\s*Speed", r"^\d{1,3}(\.\d)?$", max_dy=260, max_dx=90)
        if rs is None:
            raw = _value_under(bimg, toks, r"Retune\s*Speed", 2.0, dy=(95, 125), dx=30) or ""
            m = re.search(r"\d{1,3}", raw.replace("O", "0").replace("o", "0"))
            rs = m[0] if m else None
        if key:
            m = _NOTE_RX.match(key.replace(" ", ""))
            res["key"] = (m[1] + m[2].replace("♯", "#").replace("♭", "b")) if m else None
        res["scale"] = scale
        res["retune"] = float(rs) if rs else None
        res["ok"] = bool(res["key"] and res["scale"])
        crop(img, body, 1.0).save(shot_path)     # keep only the plug-in body (Sofia only)
        return res
    finally:
        close_plugin_window()


def key_label(note: str, scale: str):
    if not note or not scale:
        return None
    s = scale.lower()
    if s.startswith("major") or s == "ionian":
        return f"{note} major"
    if s.startswith("minor") or s == "aeolian":
        return f"{note} minor"
    return None                                  # modes etc.: kept raw, not a major/minor label


def bring_pt_forward():
    """Activate Pro Tools without a click (NSRunningApplication). True if PT is then frontmost."""
    from AppKit import NSWorkspace
    for a in NSWorkspace.sharedWorkspace().runningApplications():
        if str(a.localizedName() or "").startswith("Pro Tools"):
            a.activateWithOptions_(1 << 1)  # NSApplicationActivateIgnoringOtherApps
    time.sleep(1.0)
    return frontmost().startswith("Pro Tools")


def frontmost() -> str:
    from AppKit import NSWorkspace
    fa = NSWorkspace.sharedWorkspace().frontmostApplication()
    return str(fa.localizedName() or "") if fa else ""
