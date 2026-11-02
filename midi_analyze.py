"""
Key and tempo from a Standard MIDI File (.mid / .midi), pure Python (no libraries beyond what
bpm.py already needs: the key scoring is bpm.py's own).
Key: note durations summed per pitch class (drums, channel 10, left out), scored against the same
     'bgate' key profiles the audio path uses. Embedded key-signature meta events are ignored on
     purpose: they are often left at C major.
Tempo: the set-tempo meta event that covers the most ticks (a single tempo is the common case);
     120 BPM when the file has none (the SMF default).
"""

import struct

DRUM_CHANNEL = 9          # channel 10, zero-based
DEFAULT_TEMPO_US = 500000  # 120 BPM
MIN_NOTES = 4             # fewer pitched notes than this is not enough to name a key


class MidiError(ValueError):
    pass


def _vlq(data, i):
    v = 0
    for _ in range(4):
        if i >= len(data):
            raise MidiError("truncated MIDI file")
        b = data[i]
        i += 1
        v = (v << 7) | (b & 0x7F)
        if not b & 0x80:
            return v, i
    raise MidiError("bad variable-length number")


def parse(data):
    """-> (ticks_per_quarter | None for SMPTE time, notes [(start, end, pitch)], tempos [(tick, us)], last_tick).
    Tracks are merged; a note still sounding at the end of its track is closed there."""
    if data[:4] != b"MThd" or len(data) < 14:
        raise MidiError("not a MIDI file")
    hlen = struct.unpack(">I", data[4:8])[0]
    _fmt, ntrks, division = struct.unpack(">HHH", data[8:14])
    tpq = division if not division & 0x8000 else None
    pos = 8 + hlen
    notes, tempos, last = [], [], 0
    for _ in range(ntrks):
        if pos + 8 > len(data):
            break                                   # fewer tracks than the header promised
        if data[pos:pos + 4] != b"MTrk":
            raise MidiError("bad track header")
        tlen = struct.unpack(">I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + tlen]
        pos += 8 + tlen
        i, tick, status = 0, 0, 0
        on = {}                                      # (channel, pitch) -> start tick
        while i < len(body):
            dt, i = _vlq(body, i)
            tick += dt
            if i >= len(body):
                break
            b = body[i]
            if b == 0xFF:                            # meta
                if i + 1 >= len(body):
                    break
                mtype = body[i + 1]
                ln, j = _vlq(body, i + 2)
                payload = body[j:j + ln]
                i = j + ln
                if mtype == 0x51 and len(payload) == 3:
                    tempos.append((tick, int.from_bytes(payload, "big")))
                elif mtype == 0x2F:
                    break
                continue                             # 0x59 key signature and the rest: ignored
            if b in (0xF0, 0xF7):                    # sysex
                ln, j = _vlq(body, i + 1)
                i = j + ln
                continue
            if b & 0x80:
                status = b
                i += 1
            if not status:
                raise MidiError("data byte with no status")
            kind, ch = status & 0xF0, status & 0x0F
            n = 1 if kind in (0xC0, 0xD0) else 2
            args = body[i:i + n]
            i += n
            if len(args) < n:
                break
            if kind == 0x90 and args[1] > 0:
                on.setdefault((ch, args[0]), tick)
            elif kind in (0x80, 0x90):               # note off, or note on with velocity 0
                s = on.pop((ch, args[0]), None)
                if s is not None and ch != DRUM_CHANNEL:
                    notes.append((s, tick, args[0]))
        for (ch, p), s in on.items():
            if ch != DRUM_CHANNEL:
                notes.append((s, tick, p))
        last = max(last, tick)
    return tpq, notes, sorted(tempos), last


def tempo_us(tempos, last_tick):
    """The tempo (microseconds per quarter) in force for the most ticks."""
    if not tempos:
        return DEFAULT_TEMPO_US
    spans = {}
    cur_tick, cur = 0, DEFAULT_TEMPO_US
    for t, us in tempos:
        spans[cur] = spans.get(cur, 0) + (t - cur_tick)
        cur_tick, cur = t, us
    spans[cur] = spans.get(cur, 0) + max(last_tick - cur_tick, 0)
    return max(spans, key=lambda k: spans[k])


def pitch_class_profile(notes, lo=0, hi=None):
    """Duration-weighted 12-bin pitch-class histogram (bin 0 = C) of the notes starting in [lo, hi)."""
    import numpy as np
    pcp = np.zeros(12)
    for s, e, p in notes:
        if s >= lo and (hi is None or s < hi):
            pcp[p % 12] += max(e - s, 1)
    return pcp


def analyze_midi(path):
    """-> (bpm rounded to 0.1, [(key, percent), x3], extras {'bpm_exact': float}). Same shape as bpm.analyze_full."""
    import numpy as np
    import bpm as core
    with open(path, "rb") as f:
        _tpq, notes, tempos, last = parse(f.read())
    us = tempo_us(tempos, last)
    exact = 60_000_000 / us
    if len(notes) < MIN_NOTES:
        keys = [('C', 0.0), ('Am', 0.0), ('G', 0.0)]
    else:
        pcp = pitch_class_profile(notes)
        scores = core.key_scores(pcp / pcp.max(), core.BGATE)
        winner = max(scores, key=scores.get)
        # agreement over four equal slices of the piece, like the audio path's 10 s windows
        end = max(e for _, e, _ in notes)
        wins = []
        for k in range(4):
            seg = pitch_class_profile(notes, end * k / 4, end * (k + 1) / 4)
            if np.count_nonzero(seg) >= 3:
                s = core.key_scores(seg / seg.max(), core.BGATE)
                wins.append(max(s, key=s.get) == winner)
        keys = core.top3_with_confidence(scores, float(np.mean(wins)) if wins else 1.0)
    return round(exact, 1), keys, {"bpm_exact": round(exact, 2)}
