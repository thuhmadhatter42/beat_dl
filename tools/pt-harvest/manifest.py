"""Build the harvest order on Sofia. Names stay on Sofia (J 2026-10-06): the output
~/pt-harvest/manifest.json maps number -> sha1(ptx) -> path and is never committed or printed.
Order: the trial picks given as sha1 prefixes on argv first, then recent era (2023+) round-robin
across artists (random within artist, seed 20261006), then 2022 and earlier, then undated.
Prints counts only."""
import hashlib, json, os, random, sys
from pathlib import Path

HOME = Path.home()
src = json.load(open(HOME / "pt-harvest-trial" / "discover.json"))
first = sys.argv[1:]


def sha(p):
    return hashlib.sha1(p.encode()).hexdigest()


entries = [{"sha1": sha(p["ptx"]), "ptx": p["ptx"], "artist_hash": sha(p["artist"])[:10],
            "year": p["date"][0]} for p in src["picked"]]
by_sha = {e["sha1"]: e for e in entries}
order = []
for pre in first:
    hit = [e for e in entries if e["sha1"].startswith(pre)]
    assert len(hit) == 1, f"prefix {pre} matched {len(hit)}"
    order.append(hit[0])
rest = [e for e in entries if e not in order]
rng = random.Random(20261006)


def round_robin(pool):
    groups = {}
    for e in pool:
        groups.setdefault(e["artist_hash"], []).append(e)
    for g in groups.values():
        rng.shuffle(g)
    keys = sorted(groups); rng.shuffle(keys)
    out = []
    while any(groups.values()):
        for k in keys:
            if groups[k]:
                out.append(groups[k].pop())
    return out


for tier in (lambda e: e["year"] >= 23, lambda e: 1 <= e["year"] <= 22, lambda e: e["year"] == 0):
    order += round_robin([e for e in rest if tier(e)])
for i, e in enumerate(order, 1):
    e["n"] = i
out = HOME / "pt-harvest" / "manifest.json"
json.dump(order, open(out, "w"), indent=1)
print("manifest entries", len(order), "trial first", len(first),
      "recent", sum(1 for e in order if e["year"] >= 23),
      "artists", len({e["artist_hash"] for e in order}))
