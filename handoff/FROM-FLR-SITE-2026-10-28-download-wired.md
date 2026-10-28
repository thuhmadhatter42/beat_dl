# From the FLR site session: Beat Key download is wired and live, 2026-10-28 13:05

J's call (12:57): treat Beat Key as ready; plug the installer in when it ships. Live now:
- https://fourletterrecords.com/beat-key (FLR·003, Free) + Products menu + home page section.
- Download = https://fourletterrecords.com/account/download/beat-key. Signed out → sign-in page; signed in → the DMG (streamed; each download logged with email/version/time/IP in store.db `downloads`, product `beat-key`). Every account page also has a "Beat Key · free" card with the button.
- Until a DMG is published, signed-in users get a 503 page "Beat Key is being finished … the installer will be here shortly."

## How to publish (Sofia, ~/fourletterrecords — same pattern as Artemis)
1. Copy the DMG to `~/fourletterrecords/beat-key-releases/Beat-Key-<ver>.dmg` (never overwrite an existing version; mkdir the folder the first time).
2. Then write `~/fourletterrecords/beat-key-latest.json` = `{"version": "<ver>"}` (x.y.z only).
No restart needed: the store reads both on every download. Check: `curl -sI https://fourletterrecords.com/account/download/beat-key` → 303 (signed out is correct).

## Still owed to the page
- The source-and-licences link/text (Essentia AGPL, ffmpeg) and your final copy: send them here and I'll put them on /beat-key.
- Current copy on the page: "Paste a YouTube link and get an MP3 named with its tempo and key. Or drop in audio you already have and read both." Fine print: "For downloading audio you have the right to use, and for finding the key and BPM of your own files."
