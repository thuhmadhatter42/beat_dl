#!/bin/bash
# dev aid: list PTSL command ids known to the installed SDK proto (filter by regex $1)
find "$HOME/ProTools SDK" -maxdepth 5 -name "*.proto" | head -3
grep -rhoE "CId_[A-Za-z]+" "$HOME/ProTools SDK" --include=*.proto | sort -u | grep -iE "${1:-out|rout|bus|send|io|track|mem}" | tr "\n" " "
echo
