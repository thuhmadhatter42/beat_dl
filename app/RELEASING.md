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
  with the exported file (override: `SPARKLE_ED_FILE=<path>`). Never commit or print it (backed up:
  on Sofia since 2026-10-29, signing keys in Passwords since 2026-11-09). Losing it means the next update must change the key and the Developer ID
  certificate cannot change in the same release (sparkle-project.org/documentation, "Rotating
  signing keys").
- Public key: `SUPublicEDKey` in `app/Info.plist`. `generate_keys --account beat-key -p` prints it.
- Notary profile `artemis-notary` in the login Keychain (`xcrun notarytool store-credentials`).

## Every release

1. Bump `VERSION` (last number +1). The version is both `CFBundleVersion` and
   `CFBundleShortVersionString`, and Sparkle compares it, so it must only go up.
2. Build: `app/build.sh` (on a Mac someone is using, add
   `DMG_LAYOUT_FROM=<an earlier Beat Key DMG>` so no Finder window opens). It ends with
   `app/build/Beat-Key-<ver>.pkg` (the download for people), `app/build/Beat-Key-<ver>.dmg` (for
   Sparkle updates only), both signed (the pkg with `Developer ID Installer: J Shriver (9WTFGV63S2)`,
   override `PKG_SIGN_IDENTITY`), notarized and stapled, and `app/build/appcast.xml` (one
   item for that DMG, EdDSA-signed, enclosure
   `https://github.com/thuhmadhatter42/beat_dl/releases/download/Beat-Key-<ver>/Beat-Key-<ver>.dmg`).
3. Commit everything (the script needs HEAD on `main` with tracked files clean), then publish with
   `bash tools/publish.sh`, which reads `VERSION`. Since 0.1.62 it does all of this in three phases
   and logs to `app/build/publish-<ver>.log`:
   - checks, nothing changed anywhere: DMG and pkg stapled, pkg signed (`pkgutil --check-signature`), `appcast.xml` names `<ver>`, the tag
     `Beat-Key-<ver>` and the GitHub release do not exist yet, Sofia reachable and not already
     holding `Beat-Key-<ver>.dmg` or `Beat-Key-<ver>.pkg`;
   - publish: tag, push `main` and the tag, DMG and pkg to Sofia
     `~/fourletterrecords/beat-key-releases/` (never overwrites), `beat-key-latest.json` =
     `{"version": "<ver>"}`, the friends page, and last the GitHub release with the pkg, the DMG and
     `appcast.xml` (the step every installed Beat Key sees). No restart of anything;
   - final check: `https://fourletterrecords.com/account/download/beat-key` answers 303 and
     `beat-key-latest.json` on Sofia names `<ver>`. Only then it prints `PUBLISHED <ver>`; any
     failure prints which public steps already happened.
   Auto mode may block public pushes; then J runs it: `! bash ~/dev/beat_dl/tools/publish.sh`.
4. After it: `curl -sIL https://github.com/thuhmadhatter42/beat_dl/releases/latest/download/appcast.xml`
   ends in `200` and the file names `<ver>`.

## The pkg installer

`app/pkg/distribution.xml` + `app/pkg/postinstall`, assembled by build.sh (`pkgbuild` with a component
plist that sets `BundleIsRelocatable = false`, so it always installs `/Applications/Beat Key.app`;
`productbuild` signs it). The installer's `installation-check` (Installer JS
`system.applications.fromIdentifier('com.jshriver.orion')`, plus a scan of `system.applications.all()`
for an `Orion.app` / `Beat Key.app` bundle path) shows "Beat Key is open. Quit Beat Key, then click
Continue." while Beat Key runs. `postinstall` opens Beat Key as the logged-in console user. Both log
to `/var/log/install.log` (lines `JS: Beat Key check:` and `Beat Key postinstall:`).
Sparkle keeps using the DMG (it quits Beat Key itself before installing); the pkg is only the download.
Every launch, Beat Key also asks Sparkle for one background check (no timer).

## Testing an update without publishing

Build the newer version with `APPCAST_DOWNLOAD_PREFIX=http://127.0.0.1:<port>/`, serve its DMG and
appcast with `python3 -m http.server <port> --bind 127.0.0.1`, point the installed older Beat Key at
it with `defaults write com.jshriver.orion SUFeedURL http://127.0.0.1:<port>/appcast.xml`, and
use Check for Updates…. Afterwards: `defaults delete com.jshriver.orion SUFeedURL`, stop the server.
