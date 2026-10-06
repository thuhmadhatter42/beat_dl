# Old-Mac support — full beat_dl (download + BPM/key) on every Mac

J, 2026-10-06 15:47: "i need it for old macs too... you can test on sofia".
Target: Apple Silicon macOS 11.0+ and Intel macOS 10.15+, with the same BPM/key results as today.
Checklist: `2026-10-06-old-mac-support-TOC.md`.

## Measured starting point (2026-10-06)
| Component | arm64 floor | x86_64 floor | Blocker |
|---|---|---|---|
| yt-dlp_macos (universal) | 11.0 | 10.15 | none |
| ffmpeg/ffprobe arm64 9.0.2 (martin-riedl) | 12.0 | n/a | no static arm64 build below 12.0 exists anywhere |
| ffmpeg/ffprobe x86_64 7.1.1 (evermeet) | n/a | 10.9 | none (vendored 2026-10-06) |
| python-build-standalone 3.11.17 | 11.0 | 10.15 | none |
| essentia-tensorflow dev1110 | 13.1 | 12.1 | bundled libtensorflow; plain essentia wheels only reach 13.0 / 11.0 |

bpm.py uses these essentia pieces: AudioLoader, MonoMixer, Resample, **TempoCNN** (the only TensorFlow one), Windowing, Spectrum, SpectralPeaks, SpectralWhitening, HPCP, FrameGenerator. Model: `models/deeptemp-k16-3.pb`.

## §1. ffmpeg + ffprobe for arm64 macOS 11.0
Build static ffmpeg/ffprobe on the MBP with `MACOSX_DEPLOYMENT_TARGET=11.0`, `-arch arm64`. Use the same major version as the x86_64 tier (7.1.1) so old-Mac behaviour is uniform. Minimal config is enough: all audio decoders, demuxers for webm/mp4/m4a/ogg/mp3/wav, mp3 muxer, libmp3lame encoder (build lame 3.100 static with the same target), and the filters yt-dlp's audio extraction uses (aresample, aformat, anull, …; check `yt-dlp -x --audio-format mp3 -v` output for the exact ffmpeg command line). No SDL, no ffplay, no network libs.
- Build script committed: `tools/build-old-mac/ffmpeg-arm64.sh` (fetches sources with sha256 checks, builds in a scratch dir, writes `vendor/macos-arm64-legacy/{ffmpeg,ffprobe}.zip`).
- Verify: `vtool -show-build` minos ≤ 11.0 for both binaries; `otool -L` only /usr/lib + /System; `-encoders | grep mp3lame`; a yt-dlp download end to end with `--ffmpeg-location` pointing at it.
- Wire in: deps.sh `pick_builds` uses this zip on arm64 below `FFMPEG_ARM64_MIN` instead of the Rosetta x86_64 build (Rosetta isn't installed by default).

## §2. Essentia without TensorFlow, built for old macOS
Build essentia (same upstream commit as the dev1110 wheel, or the closest tag) from source, **without TensorFlow and without its ffmpeg dependency**, as a Python 3.11 extension for:
- arm64, `MACOSX_DEPLOYMENT_TARGET=11.0`
- x86_64, `MACOSX_DEPLOYMENT_TARGET=10.15`
using the vendored python-build-standalone 3.11 headers and numpy 1.26.4. Deps: eigen (headers), KissFFT (`--fft=KISS`) or fftw static, libsamplerate static (for Resample), libyaml only if the build insists. Everything static into the extension. Output wheels → `vendor/macos-{arm64,x86_64}/wheels-legacy/essentia-*.whl`.
- Build script committed: `tools/build-old-mac/essentia.sh <arch>`.
- Verify: max minos across every Mach-O in the wheel ≤ target; imports in the vendored python; the 9 non-TF algorithms above exist.

## §3. TempoCNN in numpy (no TensorFlow)
Extract the weights of `models/deeptemp-k16-3.pb` once (on the MBP, any tool: `tensorflow` pip in a scratch venv, or parse the GraphDef with `protobuf`) into `models/deeptemp-k16-3.npz`, committed. Implement the forward pass in numpy in `tempocnn_np.py`: same input as essentia's TempoCNN (TensorflowInputTempoCNN mel front end at 11025 Hz, its patch size/hop, its aggregation to the global BPM). Read essentia's `tempocnn.cpp` / `tensorflowinputtempocnn.cpp` for the exact parameters, don't guess.
- Verify: on every track in `docs/research/bpm-bench/audio/` the numpy global BPM equals essentia-tensorflow's TempoCNN result (exact match expected; report any track that differs and by how much).

## §4. bpm.py: one analyzer, two back ends
`analyze()` uses essentia-tensorflow when present (today's path, unchanged). When only the legacy build is present: decode with the bundled ffmpeg (`ffmpeg -i f -f f32le -ac 1 -ar <sr> -`) or essentia AudioLoader if the legacy build kept it, Resample/HPCP/key exactly as today, BPM via `tempocnn_np`.
- Verify: on `docs/research/key-bench` and `bpm-bench` audio, legacy path vs TF path: BPM identical, top-3 keys identical (report diffs).
- The librosa fallback stays only if nothing else is installable; it is not part of any tier.

## §5. deps.sh tiers
`pick_builds` gains: arm64 < 12.0 → legacy arm64 ffmpeg; analyzer → `tf` (≥ 13.1 arm64 / ≥ 12.1 x86_64) or `legacy` (everything from 11.0 arm64 / 10.15 x86_64 up). Drop the Rosetta route unless the legacy build fails somewhere. `.picks` records the tier. The ℹ️ "BPM/key needs…" line goes away (every supported Mac gets BPM/key).

## §6. Test
1. MBP fresh copies with forced MACOS/CPU (scratchpad `tiers.sh` pattern): native, arm64 12.5, arm64 11.7, x86_64 10.14 (refusal).
2. **Sofia** (Intel Mac Pro, macOS 12.7.6, `~/.claude/scripts/ssh-rc js-mac-pro '…'`): fresh clone in a scratch dir there, (a) natural tier (x86_64 TF, 12.1+), (b) forced legacy tier (`MACOS=11.7` override in the copy). Real Intel hardware for both. Trash downloads on Sofia after.
3. Test URL: https://www.youtube.com/watch?v=TL_EX-hDXfo (expect 77.0 BPM, D# D#m G#).
4. Not testable on hardware here: Apple Silicon macOS 11/12, Intel 10.15/11. Covered by minos headers + the forced-tier runs; say so in the report.

## §7. Ship
Commit build scripts + vendored legacy builds + code, push, update README (supported Macs table), PICKUP, tracker. Studio-E-2 picks it up on next `git pull`.
