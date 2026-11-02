# Beat Key Remote Script for Ableton Live 11 / 12.
# Installed by Beat Key as  ~/Music/Ableton/User Library/Remote Scripts/BeatKey/__init__.py
# and turned on in Live: Settings > Link, Tempo & MIDI > Control Surface > BeatKey.
#
# Listens on UDP 127.0.0.1:11041 for OSC from Beat Key and answers the sender:
#   /beatkey/ping                      -> /beatkey/pong  ,sii  version, has_scale(0/1), live_major
#   /beatkey/set  ,fis tempo root scale -> /beatkey/ok   ,fis  tempo, root_note, scale_name (read back)
#        tempo <= 0, root < 0 or scale "" leave that value alone
#   /beatkey/selection                 -> /beatkey/selection ,s file  (audio clip in the Detail View)
#   any failure                        -> /beatkey/error ,s message
# Live Object Model: Song.tempo, Song.root_note (0-11), Song.scale_name (Live 12),
# Song.View.detail_clip, Clip.is_audio_clip, Clip.file_path.

import socket
import struct

VERSION = "1"
PORT = 11041


# ---- OSC 1.0, the int / float / string subset -------------------------------------------

def _pad(b):
    b += b"\0"
    return b + b"\0" * (-len(b) % 4)


def osc_encode(address, args=()):
    tags = ","
    body = b""
    for a in args:
        if isinstance(a, bool):
            a = int(a)
        if isinstance(a, int):
            tags += "i"
            body += struct.pack(">i", a)
        elif isinstance(a, float):
            tags += "f"
            body += struct.pack(">f", a)
        else:
            tags += "s"
            body += _pad(str(a).encode("utf-8"))
    return _pad(address.encode("utf-8")) + _pad(tags.encode("utf-8")) + body


def _read_str(data, i):
    end = data.index(b"\0", i)
    return data[i:end].decode("utf-8", "replace"), (end + 4) & ~3


def osc_decode(data):
    """(address, [args]) or None."""
    try:
        address, i = _read_str(data, 0)
        if not address.startswith("/"):
            return None
        if i >= len(data):
            return address, []
        tags, i = _read_str(data, i)
        args = []
        for t in tags[1:]:
            if t == "i":
                args.append(struct.unpack(">i", data[i:i + 4])[0])
                i += 4
            elif t == "f":
                args.append(struct.unpack(">f", data[i:i + 4])[0])
                i += 4
            elif t == "s":
                s, i = _read_str(data, i)
                args.append(s)
            else:
                return None
        return address, args
    except (ValueError, struct.error, IndexError):
        return None


# ---- what each message does (pure: takes the Live song, returns the reply) --------------

def has_scale(song):
    return hasattr(song, "scale_name") and hasattr(song, "root_note")


def handle(song, address, args, live_major=0):
    """The reply packet for one request."""
    try:
        if address == "/beatkey/ping":
            return osc_encode("/beatkey/pong", [VERSION, int(has_scale(song)), int(live_major)])
        if address == "/beatkey/set":
            tempo = float(args[0]) if len(args) > 0 else 0.0
            root = int(args[1]) if len(args) > 1 else -1
            scale = str(args[2]) if len(args) > 2 else ""
            if tempo > 0:
                song.tempo = max(20.0, min(999.0, tempo))
            if has_scale(song):
                if 0 <= root <= 11:
                    song.root_note = root
                if scale:
                    song.scale_name = scale
                return osc_encode("/beatkey/ok", [float(song.tempo), int(song.root_note), str(song.scale_name)])
            return osc_encode("/beatkey/ok", [float(song.tempo), -1, ""])
        if address == "/beatkey/selection":
            clip = song.view.detail_clip
            if clip is None:
                return osc_encode("/beatkey/error", ["No clip is open in the Detail View. Click an audio clip first."])
            if not getattr(clip, "is_audio_clip", False):
                return osc_encode("/beatkey/error", ["The selected clip is MIDI. Select an audio clip."])
            path = clip.file_path
            if not path:
                return osc_encode("/beatkey/error", ["Live gave no file for this clip."])
            return osc_encode("/beatkey/selection", [str(path)])
        return osc_encode("/beatkey/error", ["Unknown request " + address])
    except Exception as e:  # never let a bad packet take the script down
        return osc_encode("/beatkey/error", [str(e)])


# ---- the Remote Script --------------------------------------------------------------------

try:
    from _Framework.ControlSurface import ControlSurface
except ImportError:  # outside Live (tests)
    ControlSurface = object


class BeatKey(ControlSurface):
    def __init__(self, c_instance):
        ControlSurface.__init__(self, c_instance)
        self._sock = None
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(("127.0.0.1", PORT))
            s.setblocking(False)
            self._sock = s
            self.log_message("Beat Key listening on 127.0.0.1:%d" % PORT)
        except Exception as e:
            self.log_message("Beat Key could not open port %d: %s" % (PORT, e))
        try:
            import Live
            self._major = int(Live.Application.get_application().get_major_version())
        except Exception:
            self._major = 0

    def update_display(self):
        # Live calls this about every 100 ms on its main thread: safe to change the song here.
        ControlSurface.update_display(self)
        if self._sock is None:
            return
        for _ in range(16):
            try:
                data, addr = self._sock.recvfrom(65536)
            except (BlockingIOError, socket.error):
                return
            msg = osc_decode(data)
            if msg is None:
                continue
            try:
                self._sock.sendto(handle(self.song(), msg[0], msg[1], self._major), addr)
            except Exception as e:
                self.log_message("Beat Key reply failed: %s" % e)

    def disconnect(self):
        if self._sock is not None:
            self._sock.close()
            self._sock = None
        ControlSurface.disconnect(self)


def create_instance(c_instance):
    return BeatKey(c_instance)
