"""The scripts Beat Key installs into DAWs (app/Sources/Orion/Resources), run outside the DAW:
the Ableton Remote Script under Python with a fake Song, the REAPER ReaScript under `lua` with a
fake reaper table, the Bitwig controller script under `node`. Lua / node missing = skipped."""
import importlib.util
import json
import pathlib
import shutil
import struct
import subprocess
import unittest

RES = pathlib.Path(__file__).resolve().parent.parent / "app" / "Sources" / "Orion" / "Resources"


def load_ableton():
    spec = importlib.util.spec_from_file_location("beatkey_ableton", RES / "BeatKeyAbleton.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Clip:
    def __init__(self, audio=True, path="/Samples/loop.wav"):
        self.is_audio_clip = audio
        self.file_path = path


class View:
    detail_clip = None


class Song12:
    def __init__(self):
        self.tempo = 120.0
        self.root_note = 0
        self.scale_name = "Major"
        self.view = View()


class Song11:
    def __init__(self):
        self.tempo = 120.0
        self.view = View()


class AbletonScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m = load_ableton()

    def test_osc_bytes_match_the_swift_encoder(self):
        # Same bytes as DAWSendTests.testOSCEncodeArgs
        b = self.m.osc_encode("/a", [140.82, -1, "Minor"])
        self.assertEqual(b, b"/a\0\0,fis\0\0\0\0" + struct.pack(">f", 140.82) + b"\xff\xff\xff\xff" + b"Minor\0\0\0")
        self.assertEqual(self.m.osc_decode(b)[0], "/a")
        self.assertEqual(self.m.osc_decode(b)[1][1:], [-1, "Minor"])
        self.assertAlmostEqual(self.m.osc_decode(b)[1][0], 140.82, places=4)
        self.assertEqual(self.m.osc_decode(b"/beatkey/ping\0\0\0,\0\0\0"), ("/beatkey/ping", []))
        self.assertIsNone(self.m.osc_decode(b"\x01\x02"))

    def test_set_live12_tempo_and_key(self):
        s = Song12()
        reply = self.m.osc_decode(self.m.handle(s, "/beatkey/set", [140.82, 3, "Minor"], 12))
        self.assertAlmostEqual(s.tempo, 140.82, places=4)
        self.assertEqual((s.root_note, s.scale_name), (3, "Minor"))
        self.assertEqual(reply[0], "/beatkey/ok")
        self.assertEqual(reply[1][1:], [3, "Minor"])

    def test_set_leaves_alone_what_is_not_sent(self):
        s = Song12()
        self.m.handle(s, "/beatkey/set", [0.0, -1, ""])
        self.assertEqual((s.tempo, s.root_note, s.scale_name), (120.0, 0, "Major"))

    def test_live11_tempo_only(self):
        s = Song11()
        ping = self.m.osc_decode(self.m.handle(s, "/beatkey/ping", [], 11))
        self.assertEqual(ping, ("/beatkey/pong", ["1", 0, 11]))
        reply = self.m.osc_decode(self.m.handle(s, "/beatkey/set", [95.5, 3, "Minor"]))
        self.assertEqual(s.tempo, 95.5)
        self.assertFalse(hasattr(s, "root_note"))
        self.assertEqual(reply[1][1:], [-1, ""])

    def test_selection(self):
        s = Song12()
        self.assertEqual(self.m.osc_decode(self.m.handle(s, "/beatkey/selection", []))[0], "/beatkey/error")
        s.view.detail_clip = Clip(audio=False)
        self.assertIn("MIDI", self.m.osc_decode(self.m.handle(s, "/beatkey/selection", []))[1][0])
        s.view.detail_clip = Clip()
        self.assertEqual(self.m.osc_decode(self.m.handle(s, "/beatkey/selection", [])), ("/beatkey/selection", ["/Samples/loop.wav"]))

    def test_tempo_clamped_to_live_range(self):
        s = Song12()
        self.m.handle(s, "/beatkey/set", [5000.0, -1, ""])
        self.assertEqual(s.tempo, 999.0)


LUA_HARNESS = r"""
BEATKEY_TEST = true
local calls = {}
local markers = @MARKERS@
reaper = {
  CountTempoTimeSigMarkers = function() return markers end,
  GetTempoTimeSigMarker = function(p, i) return true, 0.0, 0, 0.0, 120.0, 4, 4, false end,
  SetTempoTimeSigMarker = function(p, i, t, m, b, bpm) calls[#calls+1] = "marker:" .. bpm; tempo = bpm; return true end,
  SetCurrentBPM = function(p, bpm, undo) calls[#calls+1] = "bpm:" .. bpm; tempo = bpm end,
  Master_GetTempo = function() return tempo or 120 end,
  UpdateTimeline = function() end,
  Undo_OnStateChange = function() end,
  GetSelectedMediaItem = function() return item end,
  GetActiveTake = function() return "take" end,
  TakeIsMIDI = function() return midi end,
  GetMediaItemTake_Source = function() return "section" end,
  GetMediaSourceParent = function(s) if s == "section" then return "root" end return nil end,
  GetMediaSourceFileName = function(s) if s == "root" then return "/Audio/loop.wav" end return "" end,
  defer = function() end,
}
dofile(@PATH@)
local out = {}
out[1] = BeatKeySerialize(BeatKeyHandle({id = "1", cmd = "set", bpm = "140.82"}))
out[2] = BeatKeySerialize(BeatKeyHandle({id = "2", cmd = "selection"}))
item = "item"
out[3] = BeatKeySerialize(BeatKeyHandle({id = "3", cmd = "selection"}))
midi = true
out[4] = BeatKeySerialize(BeatKeyHandle({id = "4", cmd = "selection"}))
out[5] = table.concat(calls, ",")
out[6] = BeatKeySerialize(BeatKeyParse("id=9\ncmd=ping\n"))
print(table.concat(out, "|"))
"""


@unittest.skipUnless(shutil.which("lua"), "lua not installed")
class ReaperScriptTests(unittest.TestCase):
    def run_lua(self, markers):
        code = LUA_HARNESS.replace("@MARKERS@", str(markers)).replace("@PATH@", json.dumps(str(RES / "BeatKeyReaper.lua")))
        out = subprocess.run(["lua", "-"], input=code, capture_output=True, text=True, timeout=20)
        self.assertEqual(out.returncode, 0, out.stderr)
        return out.stdout.strip().split("|")

    def test_set_tempo_without_markers(self):
        r = self.run_lua(0)
        self.assertEqual(r[0], "bpm=140.8200\nid=1\nok=1\nversion=1\n")
        self.assertEqual(r[4], "bpm:140.82")

    def test_set_tempo_changes_marker_zero_when_project_has_markers(self):
        r = self.run_lua(2)
        self.assertEqual(r[4], "marker:140.82")
        self.assertIn("bpm=140.8200", r[0])

    def test_selection(self):
        r = self.run_lua(0)
        self.assertIn("ok=0", r[1])
        self.assertIn("Select an audio item", r[1])
        self.assertEqual(r[2], "file=/Audio/loop.wav\nid=3\nok=1\nversion=1\n")   # parent source, not the section
        self.assertIn("MIDI", r[3])
        self.assertEqual(r[5], "cmd=ping\nid=9")   # .strip() took the last newline


NODE_HARNESS = r"""
const m = require(process.argv[1]);
let tempo = 120;
const enc = (addr, f) => {   // the Swift encoder's bytes for /beatkey/set ,f
  const b = [];
  const pad = a => { a.push(0); while (a.length %% 4) a.push(0); };
  for (const c of addr) b.push(c.charCodeAt(0)); pad(b);
  b.push(44, 102); pad(b);
  const buf = Buffer.alloc(4); buf.writeFloatBE(f); b.push(...buf);
  return b.map(x => x > 127 ? x - 256 : x);
};
const toBuf = a => Buffer.from(a.map(x => x & 255));
const out = {};
const r1 = m.beatKeyHandle(enc("/beatkey/set", 140.82), v => { tempo = v; }, () => tempo);
out.tempo = tempo;
out.reply = m.oscDecode(r1);
out.replyHex = toBuf(r1).toString("hex");
out.ping = m.oscDecode(m.beatKeyHandle(m.oscEncode("/beatkey/ping", []), () => {}, () => tempo));
out.bits = [m.bitsFromFloat(140.82) >>> 0, m.bitsFromFloat(0.5) >>> 0, m.bitsFromFloat(-2) >>> 0];
console.log(JSON.stringify(out));
"""


@unittest.skipUnless(shutil.which("node"), "node not installed")
class BitwigScriptTests(unittest.TestCase):
    def test_set_and_ping(self):
        out = subprocess.run(["node", "-e", NODE_HARNESS.replace("%%", "%"), str(RES / "BeatKeyBitwig.control.js")],
                             capture_output=True, text=True, timeout=20)
        self.assertEqual(out.returncode, 0, out.stderr)
        r = json.loads(out.stdout)
        self.assertAlmostEqual(r["tempo"], 140.82, places=4)
        self.assertEqual(r["reply"]["address"], "/beatkey/ok")
        self.assertAlmostEqual(r["reply"]["args"][0], 140.82, places=4)
        f = struct.unpack(">I", struct.pack(">f", 140.82))[0]
        self.assertEqual(r["bits"], [f, 0x3F000000, 0xC0000000])
        # reply bytes: "/beatkey/ok\0" ",f\0\0" float
        self.assertEqual(r["replyHex"], (b"/beatkey/ok\0,f\0\0" + struct.pack(">f", 140.82)).hex())
        self.assertEqual(r["ping"], {"address": "/beatkey/pong", "args": ["1"]})


if __name__ == "__main__":
    unittest.main()
