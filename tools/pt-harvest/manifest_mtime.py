"""Append the song folders the stem-bouncer picker dropped (J 2026-11-02 17:30).
That picker only accepts a .ptx whose FILE NAME has "mix N" or "MASTER"; 447 of 770 ARCH-1 song
folders had none, so the whole folder was dropped. Here every unrepresented song folder gets its
newest .ptx by modified date (acapella/instrumental-named files ranked below others).
ARCH-1 first, then ALL MIXES folders not mirrored on ARCH-1 (same folder name, name key or content key).
Existing numbers 1..N never change; new entries are numbered after the last one, recent (2023+)
round-robin across artists first, then older (seed 20261102). Names stay on Sofia: prints counts only.
Backup: archive/manifest-<time>.json. Idempotent."""
import hashlib, json, os, random, re, shutil, subprocess, time
from datetime import datetime
from pathlib import Path

H = Path.home() / "pt-harvest"
MAN = H / "manifest.json"
ROOTS = {"arch1": "/Volumes/ARCH-1/1 - MIXES", "allmixes": "/Volumes/ALL MIXES"}
VARIANT = re.compile(r"acap|a cap|instrumental|\binst\b|\bstems?\b", re.I)
sha = lambda s: hashlib.sha1(s.encode()).hexdigest()


def fsha(p):
    h = hashlib.sha1()
    try:
        with open(p, "rb") as f:
            for b in iter(lambda: f.read(1 << 20), b""):
                h.update(b)
        return h.hexdigest()
    except OSError:
        return None


def song_folders(root):
    r = subprocess.run(["mdfind", "-onlyin", root, "kMDItemFSName=*.ptx"], capture_output=True, text=True)
    out = {}
    for f in r.stdout.splitlines():
        if not f.strip() or "Session File Backups" in f:
            continue
        rel = Path(f).relative_to(root)
        if len(rel.parts) < 3:
            continue
        out.setdefault((rel.parts[0], rel.parts[1]), []).append(f)
    return out


def folder_of(ptx, root):
    rel = Path(ptx).relative_to(root)
    return (rel.parts[0], rel.parts[1])


man = json.load(open(MAN))
before = len(man)
shutil.copy(MAN, H / "archive" / f"manifest-{time.strftime('%y%m%d-%H%M%S')}.json")
have = {(e.get("drive", "arch1"), folder_of(e["ptx"], ROOTS[e.get("drive", "arch1")])) for e in man}
names = {e["name_key"] for e in man if e.get("name_key")}
contents = {e["content_key"] for e in man if e.get("content_key")}
arch_song_names = set()
new, counts = [], {}
for drive in ("arch1", "allmixes"):
    root = ROOTS[drive]
    folders = song_folders(root)
    if drive == "arch1":
        arch_song_names = {s for (_, s) in folders}
    c = counts[drive] = {"folders": len(folders), "already": 0, "mirror": 0, "added": 0, "unreadable": 0}
    for (artist, song), files in sorted(folders.items()):
        if (drive, (artist, song)) in have:
            c["already"] += 1; continue
        if drive == "allmixes" and song in arch_song_names:
            c["mirror"] += 1; continue
        st = []
        for f in files:
            try:
                st.append((not VARIANT.search(Path(f).stem), os.stat(f).st_mtime, f))
            except OSError:
                pass
        if not st:
            c["unreadable"] += 1; continue
        _, mt, ptx = max(st)
        nk, ck = sha(song + "\0" + Path(ptx).name), fsha(ptx)
        if nk in names or (ck and ck in contents):
            c["mirror"] += 1; continue
        names.add(nk); ck and contents.add(ck)
        new.append({"sha1": sha(ptx), "ptx": ptx, "artist_hash": sha(artist)[:10],
                    "year": datetime.fromtimestamp(mt).year % 100, "drive": drive,
                    "name_key": nk, "content_key": ck, "pick": "mtime"})
        c["added"] += 1
rng = random.Random(20261102)


def round_robin(pool):
    groups = {}
    for e in pool:
        groups.setdefault(e["artist_hash"], []).append(e)
    for g in groups.values():
        rng.shuffle(g)
    ks = sorted(groups); rng.shuffle(ks)
    out = []
    while any(groups.values()):
        for k in ks:
            if groups[k]:
                out.append(groups[k].pop())
    return out


ordered = round_robin([e for e in new if e["year"] >= 23]) + round_robin([e for e in new if e["year"] < 23])
last = max(e["n"] for e in man)
for i, e in enumerate(ordered, last + 1):
    e["n"] = i
man += ordered
tmp = MAN.with_suffix(".tmp")
json.dump(man, open(tmp, "w"))
os.replace(tmp, MAN)
print("before", before, "added", len(ordered), "after", len(man), "| recent(23+)", sum(e["year"] >= 23 for e in ordered))
print(counts)
