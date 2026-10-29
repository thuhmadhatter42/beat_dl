# beatkey.jshriver.com — friends download

Live on Sofia: `~/beatkey/` (port 8171), tunnel `beatkey` (id a362a727-085e-4b43-bea8-6c90ef205d05, `~/.cloudflared/config-beatkey.yml`), launchd `com.jshriver.beatkey-server` / `-tunnel`.
Email in (no confirmation) → logged to `~/beatkey/downloads.jsonl` → 303 to the GitHub DMG of the version in `~/fourletterrecords/beat-key-latest.json`.
Update: `scp friends-page/index.html js-mac-pro:beatkey/` (read per request); restart the server only after editing serve.py.
Tear down: unload both plists, then `cloudflared tunnel delete beatkey` (removes DNS too).
