"""Smart beat finder (plan §6 v2, J 2026-10-07 01:06: "you should be able to figure out where the beat bus is").

Works on any session from three kinds of evidence, scored per live audio track:
  routing/folders  CId_GetTrackList folders + CId_GetTrackMainOutputAssignments (tracks sharing an output
                   bus form a group; a group inherits the beat/vocal evidence of its members)
  names            beat-ish folder/aux/track names (Beat, Inst, Instrumental, 2trk, Music, Track, Prod, any
                   case/spacing), tracked-out stem names (drums, 808, kick ...) vs vocal names (vox, vocal,
                   lead, hook, verse, adlib, bg, dbl, harm ...)
  plug-ins         Auto-Tune / Melodyne / de-esser / vocal chains on a track => vocal
  clips            beat = stereo, spans most of the song in a few long clips; vocal = mono, many short clips
Priority: the legacy 'Beat Buss' folder (proven on the first sessions) -> another beat-named folder ->
beat-named tracks / bus groups -> inferred from clips. The bounce stage then LISTENS (audiocheck.py):
the beat probe must be beat-like (sub-bass + onset pulse) and, for every source except the legacy folder,
the complement (beat muted) must not be silent and must not be beat-like.

Calibration (2026-10-07, ids only): 6 harvested beat bounces x 3 windows: sub-share 0.57-0.97 (one quiet
break 0.04), pulse 0.28-0.71; a VOCAL STEM probe: sub 0.000-0.0003, voice-band 0.93-0.95.

find(tl, info_sa, outputs) -> dict (no names leave this module except via 'solo'/'mute' lists, which the
caller only hands to PTSL)."""
from __future__ import annotations
import re
from collections import Counter

FINDER_VERSION = 7   # 3: vocal ancestry = vocal FOLDER names only; 4: v1 Beat/Instrumental tracks first;
                     # 5: fallback sets (non-vocal tracks) tried by ear when the first set fails
                     # 6: a silent complement is accepted when the beat probes are vocal-free
                     # 7: a folder whose solo prints silence is retried by muting everything else


def norm(s: str) -> str:
    s = re.sub(r"\s*\((Stereo|Mono)\)$", "", s or "")
    s = re.sub(r"([a-z])([A-Z])", r"\1 \2", s)          # BeatBuss -> Beat Buss
    s = re.sub(r"[_\-.+/]+", " ", s.lower())
    return re.sub(r"\s+", " ", s).strip()


def _w(words):
    return re.compile(r"(?:^|[^a-z])(?:" + words + r")(?:[^a-z]|$)")


BEAT_FOLDER = _w(r"beats?|beat ?bus+|bt bus+|inst|insts|instr|instrumentals?|2 ?tr(?:ac)?ks?|2 ?trk|two ?tracks?|music|prod|production|tracks?|riddim")
BEAT_TRACK = _w(r"beats?|inst|insts|instr|instrumentals?|2 ?tr(?:ac)?ks?|2 ?trk|two ?tracks?|music|prod|riddim|stereo ?beat")
STEM = _w(r"drums?|drm|kick|kik|kck|snare|snr|clap|claps|hats?|hh|hi ?hats?|oh|perc|percs|percussion|808s?|bass|sub|keys|piano|pno|synths?|pads?|melody|melodies|mel|loops?|samples?|smpl|guitars?|gtrs?|strings?|bells?|chords?|pluck|brass|horns?|flute|organ|rhodes|riser|crash|cymbals?|toms?|rim|shaker|tamb|choir|vox ?chop|chops?|arp")
VOCAL = _w(r"vox|vocals?|voc|vcl|lead|leads|ld|lv|hook|hooks|hk|verse|verses|vrs|vs|ad ?libs?|adlib|adlibs|ads?|bgs?|bgv|bgvs|backing|backgrounds?|dbl|dbls|double|doubles|dub|dubs|harm|harms|harmony|harmonies|stack|stacks|rap|sing|main|ref|vo|chant|whisper|resp|acapella|acap|punch|punches|bridge|pre ?hook|chorus|outro ?vox|intro ?vox|feature|feat|ft|interlude ?vox")
VOCAL_FOLDER = _w(r"vox|vocals?|vocal ?stem|all ?vox|leads?|hooks?|verses?|ad ?libs?|bgs?|bgv|harms?")
VOCAL_PLUGIN = re.compile(r"auto-?tune|melodyne|waves tune|tune real|de-?ess|sibil|vocal|nectar|vocalign|revoice|alterboy|"
                          r"rvox|r-vox|renaissance vox|cla vocals|doubler|vocal rider|evo channel|pitch ?correct", re.I)
CLICK = _w(r"click|clik|metronome|cue")


def _intervals(edl):
    out = []
    for e in edl:
        if not str(e.get("state", "")).lower().startswith("unmuted"):
            continue
        try:
            a, b = int(e["start"]), int(e["end"])
        except (ValueError, KeyError):
            continue
        if b > a:
            out.append((a, b))
    return out


def _union(iv):
    tot, cur = 0, None
    for a, b in sorted(iv):
        if cur is None or a > cur[1]:
            if cur:
                tot += cur[1] - cur[0]
            cur = [a, b]
        else:
            cur[1] = max(cur[1], b)
    if cur:
        tot += cur[1] - cur[0]
    return tot


def attr(t, k):
    v = (t.get("track_attributes") or {}).get(k)
    return v in {"TAState_SetExplicitly", "TAState_SetImplicitly", "TAState_SetExplicitlyAndImplicitly"} \
        if isinstance(v, str) else bool(v)


def find(tl: list[dict], info_sa: dict, outputs: list[str] | None = None, sr: float = 48000.0,
         use_folders: bool = True) -> dict:
    by_id = {t["id"]: t for t in tl}
    out_of = {t["id"]: o for t, o in zip(tl, outputs)} if outputs and len(outputs) == len(tl) else {}
    info_by = {}
    for it in info_sa.get("tracks", []):
        info_by.setdefault(norm(it["name"]), it)
        info_by.setdefault(it["name"], it)

    def ancestors(t):
        cur, seen = t, []
        while cur.get("parent_folder_id") in by_id and len(seen) < 12:
            cur = by_id[cur["parent_folder_id"]]
            seen.append(cur)
        return seen

    live = [t for t in tl if t["type"] in ("TType_Audio", "TType_Instrument") and attr(t, "contains_clips")
            and not attr(t, "is_inactive") and not attr(t, "is_muted")]
    # song span = union extent of all live audio clips
    ivs = {}
    for t in live:
        it = info_by.get(t["name"]) or info_by.get(norm(t["name"]))
        ivs[t["id"]] = _intervals(it["edl"]) if it else []
        t["_plugins"] = (it or {}).get("plugins", [])
    allv = [x for v in ivs.values() for x in v]
    if not allv:
        return {"found": False, "why": "no live audio clips", "finder_version": FINDER_VERSION}
    s0, s1 = min(a for a, _ in allv), max(b for _, b in allv)
    span = max(s1 - s0, 1)

    feats = {}
    for t in live:
        iv = ivs[t["id"]]
        lens = sorted(b - a for a, b in iv)
        anc = ancestors(t)
        n = norm(t["name"])
        f = {"stereo": t.get("format") == "TFormat_Stereo", "n_clips": len(iv),
             "cover": _union(iv) / span if iv else 0.0,
             "med_s": (lens[len(lens) // 2] / sr) if lens else 0.0,
             "beat_name": bool(BEAT_TRACK.search(n)), "stem_name": bool(STEM.search(n)),
             "vocal_name": bool(VOCAL.search(n)),
             "vocal_plugin": any(VOCAL_PLUGIN.search(p) for p in t["_plugins"]),
             "beat_anc": any(BEAT_FOLDER.search(norm(a["name"])) and not VOCAL_FOLDER.search(norm(a["name"])) for a in anc),
             "vocal_anc": any(VOCAL_FOLDER.search(norm(a["name"])) for a in anc),
             "out": out_of.get(t["id"])}
        feats[t["id"]] = f

    def scores(f, grp_beat=0.0, grp_voc=0.0):
        v = 3 * f["vocal_plugin"] + 3 * f["vocal_anc"] + 2 * (f["vocal_name"] and not f["beat_name"]) + 2 * grp_voc
        v += 1 if (not f["stereo"] and (f["n_clips"] >= 6 or f["med_s"] < 20)) else 0
        b = 3 * f["beat_name"] + 3 * f["beat_anc"] + 2 * (f["stem_name"] and not f["vocal_name"]) + 2 * grp_beat
        b += 1 * f["stereo"] + 1 * (f["cover"] >= 0.6) + 1 * (f["med_s"] >= 20) + 1 * (0 < f["n_clips"] <= 4)
        return b, v

    # first pass without groups, then let each output-bus group vote
    first = {i: scores(f) for i, f in feats.items()}
    groups = {}
    for i, f in feats.items():
        if f["out"]:
            groups.setdefault(f["out"], []).append(i)
    grp = {}
    for o, mem in groups.items():
        if len(mem) < 2:
            continue
        def is_b(i):
            return first[i][0] >= 4 and first[i][1] < 2

        def is_v(i):
            return first[i][1] >= 2 and first[i][1] >= first[i][0]
        nb = sum(1 for i in mem if is_b(i))
        nv = sum(1 for i in mem if is_v(i))
        for i in mem:
            others = len(mem) - 1
            ob = nb - is_b(i)
            ov = nv - is_v(i)
            grp[i] = (1.0 if ob / others >= 0.6 and ov == 0 else 0.0, 1.0 if ov / others >= 0.6 and ob == 0 else 0.0)
    final = {i: scores(f, *grp.get(i, (0.0, 0.0))) for i, f in feats.items()}

    vocal = [t for t in live if final[t["id"]][1] >= 2 and final[t["id"]][1] >= final[t["id"]][0]]
    beat = [t for t in live if t not in vocal and final[t["id"]][0] >= 4]
    weak = [t for t in live if t not in vocal and t not in beat]
    # no clear beat track: long-clip tracks with no vocal evidence at all (mono stems, odd names) are a
    # LOW-confidence beat set; only the listening checks can promote it
    loose = False
    if not beat:
        beat = [t for t in weak if final[t["id"]][1] == 0 and feats[t["id"]]["cover"] >= 0.5 and feats[t["id"]]["med_s"] >= 15]
        weak = [t for t in weak if t not in beat]
        loose = bool(beat)

    dead = Counter()
    for t in tl:
        if t["type"] in ("TType_Audio", "TType_Instrument") and t not in live:
            why = ("inactive" if attr(t, "is_inactive") else "muted" if attr(t, "is_muted")
                   else "no-clips" if not attr(t, "contains_clips") else "other")
            dead[f"{why}-{'st' if t.get('format') == 'TFormat_Stereo' else 'mono'}"] += 1
    res = {"dead": dict(dead)}
    res.update({"found": False, "finder_version": FINDER_VERSION, "n_live": len(live), "n_vocal": len(vocal),
           "n_beat": len(beat), "n_weak": len(weak), "n_groups": len(groups), "loose": loose,
           "old_rule": False, "vocal_names": [t["name"] for t in vocal],
           "rows": [{"st": int(feats[t["id"]]["stereo"]), "clips": feats[t["id"]]["n_clips"],
                     "cover": round(feats[t["id"]]["cover"], 2), "med_s": round(feats[t["id"]]["med_s"], 1),
                     "flags": "".join(k[0] for k, on in (("beat_name", feats[t["id"]]["beat_name"]),
                                                          ("stem_name", feats[t["id"]]["stem_name"]),
                                                          ("vocal_name", feats[t["id"]]["vocal_name"]),
                                                          ("plugin", feats[t["id"]]["vocal_plugin"]),
                                                          ("anc_beat", feats[t["id"]]["beat_anc"]),
                                                          ("Anc_vocal", feats[t["id"]]["vocal_anc"])) if on),
                     "b": final[t["id"]][0], "v": final[t["id"]][1],
                     "cls": "B" if t in beat else "V" if t in vocal else "-"} for t in live]})

    res["click_aux"] = [t["name"] for t in tl if t["type"] == "TType_Aux" and CLICK.search(norm(t["name"]))]

    def end_of(tracks):
        return max((b for t in tracks for _, b in ivs.get(t["id"], [])), default=0)

    def alt_sets(primary):
        """Fallback beat sets that only the listening checks can accept (beat_source 'audio'): everything
        not classed vocal, and that minus the primary set. Each needs one track spanning >= half the song
        (an album/compilation session of back-to-back songs never qualifies)."""
        pid = {t["id"] for t in primary}
        nonvoc = [t for t in live if t not in vocal]
        out, seen = [], set()
        for s in (nonvoc, [t for t in nonvoc if t["id"] not in pid]):
            key = frozenset(t["id"] for t in s)
            if not s or key in seen or key == frozenset(pid):
                continue
            if max(feats[t["id"]]["cover"] for t in s) < 0.5:
                continue
            seen.add(key)
            out.append({"tracks": [t["name"] for t in s], "solo": [(t["name"], t["id"]) for t in s],
                        "method": "solo-tracks", "beat_source": "audio", "confidence": "low", "legacy": False,
                        "others_live": [t["name"] for t in live if t["id"] not in key], "max_end": end_of(s)})
        return out

    def done(tracks, folder=None):
        ids = {t["id"] for t in tracks}
        res["others_live"] = [t["name"] for t in live if t["id"] not in ids]
        res["comment_names"] = [t["name"] for t in tl if t["type"] == "TType_Audio" and
                                (t["id"] in ids or (folder is not None and folder in ancestors(t)))]
        res["max_end"] = end_of(tracks)
        res["alts"] = alt_sets(tracks)
        return res

    # 1. legacy Beat Buss folder (proven path, solo the folder)
    fol = [t for t in tl if t["type"] in ("TType_RoutingFolder", "TType_BasicFolder")
           and re.fullmatch(r"\s*beats?\s*bus{1,2}\s*", t["name"], re.I)]
    legacy_tracks = [t for t in tl if t["type"] == "TType_Audio" and
                     re.fullmatch(r"\s*(beats?|instrumental|inst)(\s*[-_.]?\s*\d{1,2})?\s*", t["name"], re.I)
                     and not attr(t, "is_inactive") and not attr(t, "is_muted") and attr(t, "contains_clips")]
    res["old_rule"] = bool(fol) or bool(legacy_tracks)
    if fol and use_folders:
        f0 = fol[0]
        kids = [t for t in live if f0 in ancestors(t)]
        if kids:
            res.update(found=True, beat_source="folder", confidence="high", method="solo",
                       solo=[(f0["name"], f0["id"])], tracks=kids, legacy=True, why="Beat Buss folder")
            return done(kids, f0)
    # 1b. v1's second rule (live audio tracks named exactly Beat/Beats/Instrumental/Inst + number): proven
    #     on the first sessions, so it outranks every inference (no regression against v1)
    if legacy_tracks and use_folders:
        lt = [t for t in live if t in legacy_tracks]
        if lt:
            res.update(found=True, beat_source="name", confidence="high", method="solo-tracks",
                       solo=[(t["name"], t["id"]) for t in lt], tracks=lt, legacy=True,
                       why=f"{len(lt)} track(s) named Beat/Instrumental")
            return done(lt)
    # 2. any other beat-named folder whose live members carry no vocal evidence
    for f0 in (tl if use_folders else []):
        if f0["type"] not in ("TType_RoutingFolder", "TType_BasicFolder"):
            continue
        nf = norm(f0["name"])
        if not BEAT_FOLDER.search(nf) or VOCAL_FOLDER.search(nf):
            continue
        kids = [t for t in live if f0 in ancestors(t)]
        if kids and not any(t in vocal for t in kids):
            meth = "solo" if f0["type"] == "TType_RoutingFolder" else "solo-tracks"
            res.update(found=True, beat_source="folder", confidence="high", method=meth,
                       solo=[(f0["name"], f0["id"])] if meth == "solo" else [(t["name"], t["id"]) for t in kids],
                       tracks=kids, legacy=False, why="beat-named folder")
            return done(kids, f0)
    if not beat:
        res["why"] = f"no beat-like track ({len(live)} live, {len(vocal)} vocal, {len(weak)} weak)"
        alts = alt_sets([])
        if alts:            # nothing scored as beat, but non-vocal material spans the song: let the ears decide
            a0 = alts[0]
            ids = {i for _, i in a0["solo"]}
            tr = [t for t in live if t["id"] in ids]
            res.update(found=True, beat_source="audio", confidence="low", method="solo-tracks", solo=a0["solo"],
                       tracks=tr, legacy=False, why=res["why"] + "; trying the non-vocal tracks by ear")
            done(tr)
            res["alts"] = alts[1:]
        return res
    named = [t for t in beat if feats[t["id"]]["beat_name"]]
    via_bus = [t for t in beat if grp.get(t["id"], (0, 0))[0] > 0]
    via_anc = [t for t in beat if feats[t["id"]]["beat_anc"]]
    stems = [t for t in beat if feats[t["id"]]["stem_name"]]
    if named:
        src = "name"
    elif via_anc:
        src = "folder"
    elif via_bus:
        src = "bus"
    else:
        src = "inferred"
    # the beat set must look like a beat as a whole: something spanning most of the song
    best_cover = max(feats[t["id"]]["cover"] for t in beat)
    conf = "high" if src in ("name", "folder") else "medium"
    if best_cover < 0.5:
        conf = "low"
    if src == "inferred" and not any(feats[t["id"]]["stereo"] for t in beat) and not stems:
        conf = "low"
    if loose:
        conf = "low"
    res.update(found=True, beat_source=src, confidence=conf, method="solo-tracks",
               solo=[(t["name"], t["id"]) for t in beat], tracks=beat, legacy=False,
               why=f"{len(beat)} beat tracks ({len(named)} named, {len(stems)} stem-named, {len(via_bus)} via bus, "
                   f"{len(via_anc)} via folder), cover {best_cover:.2f}, {len(vocal)} vocal, {len(weak)} weak")
    return done(beat)


def table(res: dict, feats_only=False) -> list[str]:
    """Name-free summary lines for logs."""
    keys = ("found", "beat_source", "confidence", "method", "n_live", "n_beat", "n_vocal", "n_weak", "n_groups",
            "loose", "old_rule", "why")
    return [f"{k}={res.get(k)}" for k in keys]
