#!/bin/bash
# Publish the Beat Key release named in VERSION (J runs this; auto mode blocks public pushes).
# Needs app/build/Beat-Key-<V>.dmg (notarized, from app/build.sh) and app/build/appcast.xml.
# Steps: stapler check, push main + tag, GitHub release (DMG + appcast), DMG + beat-key-latest.json
# to the FLR site on Sofia, friends page. Restarts, shuts down or logs out nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
V=$(cat VERSION); D=app/build/Beat-Key-$V.dmg
echo "== publishing $V"
xcrun stapler validate "$D" >/dev/null
git tag -f "Beat-Key-$V" && git push origin main && git push origin "Beat-Key-$V"
gh release create "Beat-Key-$V" -R thuhmadhatter42/beat_dl --title "Beat Key $V" "$D" app/build/appcast.xml
~/.claude/scripts/ssh-rc js-mac-pro "test ! -e ~/fourletterrecords/beat-key-releases/Beat-Key-$V.dmg"
scp "$D" js-mac-pro:fourletterrecords/beat-key-releases/
~/.claude/scripts/ssh-rc js-mac-pro "printf '{\"version\": \"$V\"}\n' > ~/fourletterrecords/beat-key-latest.json && cat ~/fourletterrecords/beat-key-latest.json"
scp friends-page/index.html js-mac-pro:beatkey/
curl -sI https://fourletterrecords.com/account/download/beat-key | head -1
echo "PUBLISHED $V"
