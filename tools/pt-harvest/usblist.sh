#!/bin/bash
# Sofia: USB device names only (hardware), to see whether an iLok key is attached.
system_profiler SPUSBDataType 2>/dev/null | grep -E '^ {8,}[^ ].*:$' | sed 's/^ *//' | sort | uniq -c | head -40
