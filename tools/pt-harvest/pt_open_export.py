"""Open one session via PTSL (with the known-dialog watchdog), run ONLY
CId_ExportSessionInfoAsText with every include flag on, write the raw text.
Does NOT close the session. usage: pt_open_export.py <ptx> <out.txt> [--no-open]
--no-open: session already (still) loading/open; skip CId_OpenSession."""
import sys, os, pathlib, traceback, time
sys.path.insert(0, str(pathlib.Path.home() / "ProTools SDK" / "stem-bouncer"))
from pt_stems.client import PtslClient
from pt_stems.dialog_watch import DialogWatch

ptx, out = sys.argv[1], sys.argv[2]
w = DialogWatch().start()
try:
    c = PtslClient(autolaunch=False)
    if "--no-open" not in sys.argv:
        print("open:", c.open_session(ptx, timeout=600), flush=True)
    body = {"include_file_list": True, "include_clip_list": True, "include_markers": True,
            "include_plugin_list": True, "include_track_edls": True,
            "show_sub_frames": True, "include_user_timestamps": True,
            "track_list_type": "AllTracks", "fade_handling_type": "ShowCrossfades",
            "text_as_file_format": "UTF8", "output_type": "ESI_String"}
    r = c.send("CId_ExportSessionInfoAsText", body, timeout=600)
    pathlib.Path(out).write_text(r.get("session_info", ""), encoding="utf-8")
    print("wrote", out, len(r.get("session_info", "")), "chars", flush=True)
except BaseException:
    traceback.print_exc()
finally:
    w.stop()
    print("unknown dialogs seen:", w.unknown, flush=True)
    os._exit(0)
