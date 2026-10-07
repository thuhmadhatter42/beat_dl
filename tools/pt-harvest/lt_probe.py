"""Which location_type values does ExportSessionInfoAsText accept? Prints first EDL start cells only."""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hlib
c = hlib.client()
for lt in ("TLType_Samples", "TLType_Ticks", "TLType_MinSecs", "TLType_Seconds", "TLType_TimeCode", "TLType_BarsBeats"):
    try:
        t = hlib.export_info(c, lt)
        rows = [ln.split("\t") for ln in t.splitlines() if re.match(r"^\d+\s*\t\s*\d+\s*\t", ln)]
        print(lt, "ok", [r[3].strip() for r in rows[2:5]], [r[4].strip() for r in rows[2:5]])
        (hlib.H / "info" / f"probe-{lt}.txt").write_text(t)
    except Exception as e:
        print(lt, "fail", str(e).split("command_error_message")[-1][:90])
sys.stdout.flush(); os._exit(0)
