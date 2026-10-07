"""Name-free shape of a mix drive: entries per depth, .ptx depth histogram (counts only)."""
import collections, os, sys
root = sys.argv[1] if len(sys.argv) > 1 else "/Volumes/ALL MIXES"
top = [d for d in os.listdir(root) if not d.startswith(".")]
print("top entries", len(top), "dirs", sum(os.path.isdir(os.path.join(root, d)) for d in top))
r = os.popen(f"mdfind -onlyin '{root}' 'kMDItemFSName=*.ptx' | grep -v 'Session File Backups'").read().split("\n")
r = [x for x in r if x]
print("ptx (mdfind, no backups)", len(r))
print("depth histogram", sorted(collections.Counter(len(os.path.relpath(p, root).split(os.sep)) for p in r).items()))
