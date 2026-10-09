#!/usr/bin/env python3
"""
Turn what landed in the "URL/Beat:" prompt into audio file paths.

Dragging files into Terminal types their paths, shell-escaped
(/Users/j/My\\ Beat.mp3) and space-separated when several are dropped.
Prints one existing path per line. Exit 2 if the text isn't file paths
(a URL, say); exit 1 if it is but none of them is a file.
"""

import shlex
import sys
from pathlib import Path


def to_path(token):
    if token.startswith("file://"):
        from urllib.parse import unquote, urlparse
        token = unquote(urlparse(token).path)
    return Path(token).expanduser()


def main():
    text = sys.argv[1].strip()

    # A path pasted unescaped (Finder's Copy as Pathname) with spaces in it
    whole = to_path(text.strip("'\""))
    if whole.is_file():
        print(whole)
        return

    try:
        tokens = shlex.split(text)
    except ValueError:
        sys.exit(2)
    paths = [to_path(t) for t in tokens]
    if not paths or not all(p.is_absolute() for p in paths):
        sys.exit(2)

    found = False
    for p in paths:
        if p.is_file():
            print(p)
            found = True
        elif p.is_dir():
            print(f"That's a folder, drop the beat itself: {p.name}", file=sys.stderr)
        else:
            print(f"File not found: {p}", file=sys.stderr)
    sys.exit(0 if found else 1)


if __name__ == "__main__":
    main()
