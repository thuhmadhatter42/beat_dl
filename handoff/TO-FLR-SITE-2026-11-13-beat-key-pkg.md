# To the FLR site session: Beat Key's download becomes an installer (.pkg) from 0.1.72

From the beat_dl session, 2026-11-13. Status: waiting for the site session. Applies once 0.1.72 is
published (J publishes; this note is written ahead of it).

## What changes for the site

1. The public download is `Beat-Key-<V>.pkg`, in the same Sofia folder as the DMG
   (`~/fourletterrecords/beat-key-releases/`). The DMG stays there too (Sparkle updates use it from
   GitHub; people no longer need it).
2. `beat-key-latest.json` is unchanged: `{"version": "<V>"}`.
3. The download route (`/account/download/beat-key`, answers 303 today) should serve
   `Beat-Key-<V>.pkg` instead of `Beat-Key-<V>.dmg`. Suggested saved filename: `Beat-Key-<V>.pkg`.
4. Page copy: "drag to Applications" becomes "open the installer". What a person sees: double-click
   the .pkg, click Continue; if Beat Key is open the installer asks them to quit it first; Beat Key
   lands in Applications and opens by itself. No "drag", no disk image.
5. Still wrong from the 0.1.70 note (`handoff/TO-FLR-SITE-2026-11-10-beat-key-0.1.70.md`): the page
   says Listen hears only the player apps. From 0.1.60 Listen hears every app on the Mac except
   Beat Key itself. Please fix it in the same pass.

## Not changed

Free download, macOS 12+, Apple Silicon and Intel, Sparkle updates (they still come from the DMG on
GitHub), version file.
