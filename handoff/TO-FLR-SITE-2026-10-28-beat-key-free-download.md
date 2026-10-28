# To the FLR site session: Beat Key, the free download

From: beat_dl session (MBP `~/dev/beat_dl`), 2026-10-28 12:25. Owner of the page: `02-4lr/infrastructure/flr-site/`.

## What J decided (his words, 2026-10-28 12:20)
"I wanna make it the free offer on the Four Letter Records website. People can get it for free, but they have to make an account and all that ... like how normal plug-in companies do it, where they have paid software and then they always have at least one free item. This is our free item."
It is for all Four Letter Records users, not one person.

## The product
- **Beat Key**: a Mac app. Paste a YouTube link → it downloads the audio as an MP3 named with its BPM and key. Or drop/open audio files → it finds the key and BPM. One window, FLR-style hardware faceplate.
- Mac only. **macOS 12 or later**, one universal installer (Apple Silicon + Intel; macOS picks the right half). Signed + notarized with Developer ID J Shriver (9WTFGV63S2), so it opens with the normal "downloaded from the Internet" prompt only.
- Installer: a DMG, ~390 MB (it carries its own Python, audio analysis, ffmpeg, yt-dlp and a JS engine, so nothing else has to be installed).
- File name pattern: `Beat-Key-<version>.dmg`. Version is still 0.1.x (pre-1.0). The beat_dl session will hand over the final DMG path and sha256 when it ships; it is NOT final yet (in-app YouTube login being finished).
- No auto-updater. A new version = a new DMG. The app updates its own downloader (yt-dlp) weekly by itself and has Beat Key › Run Doctor.

## What the page needs (J's ask; how is yours)
- A product page for Beat Key in the site's style, marked FREE.
- Download gated behind an FLR account, the same way the stable Artemis installer is (`/account/download/artemis` pattern): sign in / create account → download.
- Requirements line: macOS 12+, Apple Silicon or Intel, ~390 MB.
- A short "first launch" note: macOS asks "Beat Key is an app downloaded from the Internet. Open?" → Open. Optional: age-restricted videos ask the user to log in to YouTube inside Beat Key once.

## Two things the beat_dl session is still settling before public release (do not block page work on them, but don't publish the download until beat_dl says go)
1. Open-source licences of the bundled parts (Essentia is AGPL-3.0; the ffmpeg build may be GPL). Public distribution likely needs a "source and licences" link on the page. beat_dl will hand over the exact text/link.
2. Wording: describe it as a tool for downloading audio you have the right to use and for analysing key/BPM. beat_dl will send final copy.

## Contact back
Write replies to `~/dev/beat_dl/handoff/FROM-FLR-SITE-*.md` on the MBP.
