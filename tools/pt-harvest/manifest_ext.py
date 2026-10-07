"""Append ALL MIXES to the harvest manifest (plan §6 v2): when ARCH-1's 1 - MIXES runs out before 200
usable rows, the batch continues onto /Volumes/ALL MIXES with the same discovery (discover.py ->
~/pt-harvest/discover-allmixes.json) and the same newest-per-song rule.

ALL MIXES partly mirrors ARCH-1, so a song is skipped when either
  name key     sha1(song folder name + NUL + newest .ptx file name), or
  content key  sha1(.ptx bytes)
matches an entry already in the manifest. Keys and paths live only in manifest.json on Sofia
(J 2026-10-06 names rule); this prints counts only. Idempotent: re-running adds nothing new.
Order of the new entries: recent era (2023+) round-robin across artists, then older, then undated
(seed 20261007), numbered after the last existing entry."""
import hashlib, json, os, random, shutil, time
from pathlib import Path

HOME = Path.home()
H = HOME / "pt-harvest"
MAN = H / "manifest.json"
ROOTS = {"arch1": "/Volumes/ARCH-1/1 - MIXES", "allmixes": "/Volumes/ALL MIXES"}


def sha(s):
    return hashlib.sha1(s.encode()).hexdigest()


def fsha(p):
    h = hashlib.sha1()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def keys(ptx, root):
    rel = Path(ptx).relative_to(root)
    song = rel.parts[1] if len(rel.parts) > 2 else ""
    k = {"name_key": sha(song + "\0" + Path(ptx).name)}
    try:
        k["content_key"] = fsha(ptx)
    except OSError:
        k["content_key"] = None
    return k


man = json.load(open(MAN))
shutil.copy(MAN, H / "archive" / f"manifest-{time.strftime('%y%m%d-%H%M%S')}.json") if (H / "archive").is_dir() else None
for e in man:
    e.setdefault("drive", "arch1")
    if "name_key" not in e:
        e.update(keys(e["ptx"], ROOTS[e["drive"]]))
names = {e["name_key"] for e in man}
contents = {e["content_key"] for e in man if e.get("content_key")}
have_paths = {e["ptx"] for e in man}
src = json.load(open(H / "discover-allmixes.json"))
new, dup_name, dup_content, dup_path = [], 0, 0, 0
for p in src["picked"]:
    if p["ptx"] in have_paths:
        dup_path += 1; continue
    k = keys(p["ptx"], ROOTS["allmixes"])
    if k["name_key"] in names:
        dup_name += 1; continue
    if k["content_key"] and k["content_key"] in contents:
        dup_content += 1; continue
    names.add(k["name_key"])
    if k["content_key"]:
        contents.add(k["content_key"])
    new.append({"sha1": sha(p["ptx"]), "ptx": p["ptx"], "artist_hash": sha(p["artist"])[:10],
                "year": p["date"][0], "drive": "allmixes", **k})
rng = random.Random(20261007)


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


order = []
for tier in (lambda e: e["year"] >= 23, lambda e: 1 <= e["year"] <= 22, lambda e: e["year"] == 0):
    order += round_robin([e for e in new if tier(e)])
nxt = max(e["n"] for e in man) + 1
for i, e in enumerate(order):
    e["n"] = nxt + i
man += order
json.dump(man, open(MAN, "w"), indent=1)
old_artists = {e["artist_hash"] for e in man if e["drive"] == "arch1"}
print(f"ALL MIXES picked {len(src['picked'])}: duplicates of ARCH-1 by name key {dup_name}, by content key "
      f"{dup_content}, same path {dup_path}; added {len(order)} (recent {sum(1 for e in order if e['year'] >= 23)}, "
      f"artists {len({e['artist_hash'] for e in order})}, of them already on ARCH-1 "
      f"{len({e['artist_hash'] for e in order} & old_artists)}); manifest now {len(man)} entries, n {nxt}..{len(man)}")
