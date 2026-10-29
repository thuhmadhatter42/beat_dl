# Releasing Beat Key

Beat Key updates itself with Sparkle 2 (Beat Key › Check for Updates…, the daily automatic check,
and the check at the end of Run Doctor). It reads
`https://github.com/thuhmadhatter42/beat_dl/releases/latest/download/appcast.xml`, which GitHub
redirects to the `appcast.xml` asset of the newest non-draft, non-prerelease release. So every
release must carry an `appcast.xml`, or update checks fail with a 404.

## One-time setup (already done on the MacBook Pro, 2026-10-28)

- EdDSA signing key: `generate_keys --account beat-key` (Sparkle's tool, in
  `app/.build/artifacts/sparkle/Sparkle/bin/` after `swift package resolve`). The private key is
  in the login Keychain (account `beat-key`) and exported to
  `~/.config/beat-key/sparkle_ed25519_private` (chmod 600, outside the repo). build.sh signs
  with the exported file (override: `SPARKLE_ED_FILE=<path>`). Never commit or print it; back it up
  somewhere J keeps secrets. Losing it means the next update must change the key and the Developer ID
  certificate cannot change in the same release (sparkle-project.org/documentation, "Rotating
  signing keys").
- Public key: `SUPublicEDKey` in `app/Info.plist`. `generate_keys --account beat-key -p` prints it.
- Notary profile `artemis-notary` in the login Keychain (`xcrun notarytool store-credentials`).

## Every release

1. Bump `VERSION` (last number +1). The version is both `CFBundleVersion` and
   `CFBundleShortVersionString`, and Sparkle compares it, so it must only go up.
2. Build: `app/build.sh` (on a Mac someone is using, add
   `DMG_LAYOUT_FROM=<an earlier Beat Key DMG>` so no Finder window opens). It ends with
   `app/build/Beat-Key-<ver>.dmg` (signed, notarized, stapled) and `app/build/appcast.xml` (one
   item for that DMG, EdDSA-signed, enclosure
   `https://github.com/thuhmadhatter42/beat_dl/releases/download/Beat-Key-<ver>/Beat-Key-<ver>.dmg`).
3. Commit, tag and publish the GitHub release with both files:

   ```sh
   gh release create Beat-Key-<ver> -R thuhmadhatter42/beat_dl --title "Beat Key <ver>" \
     app/build/Beat-Key-<ver>.dmg app/build/appcast.xml
   ```

   Check: `curl -sIL https://github.com/thuhmadhatter42/beat_dl/releases/latest/download/appcast.xml`
   ends in `200`, and the file names `<ver>`.
4. The site (Sofia, `~/fourletterrecords`): copy the DMG to
   `~/fourletterrecords/beat-key-releases/Beat-Key-<ver>.dmg` (never overwrite an existing
   version), then write `~/fourletterrecords/beat-key-latest.json` = `{"version": "<ver>"}`.
   No restart. Check: `curl -sI https://fourletterrecords.com/account/download/beat-key` → 303.

## Testing an update without publishing

Build the newer version with `APPCAST_DOWNLOAD_PREFIX=http://127.0.0.1:<port>/`, serve its DMG and
appcast with `python3 -m http.server <port> --bind 127.0.0.1`, point the installed older Beat Key at
it with `defaults write com.jshriver.orion SUFeedURL http://127.0.0.1:<port>/appcast.xml`, and
use Check for Updates…. Afterwards: `defaults delete com.jshriver.orion SUFeedURL`, stop the server.
