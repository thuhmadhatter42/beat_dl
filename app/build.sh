#!/bin/bash
# Builds "Beat Key.app" and its signed, notarized, stapled DMG.
# Public name Beat Key; the executable (Orion), bundle ID and code stay Orion.
#   app/build.sh                  -> app/build/Beat Key.app, app/build/Beat-Key-<VERSION>.dmg (notarized)
#   app/build.sh --no-notarize    same, stops after signing the DMG
# Signing is inside-out and never --deep: runtime.sh signs every Mach-O of the tool runtime
# (yt-dlp with its own entitlements), then the app itself is signed. --deep is for verify only.
# Nothing is written into the bundle after it is signed.
set -euo pipefail
APP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$APP/.." && pwd)"
B="$APP/build"
VER="$(tr -d '[:space:]' < "$ROOT/VERSION")"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: J Shriver (9WTFGV63S2)}"
PROFILE="${NOTARY_PROFILE:-artemis-notary}"
NOTARIZE=1
[ "${1:-}" = --no-notarize ] && NOTARIZE=0
APP_NAME="Beat Key"                     # = Brand.name (FaceplateTests checks it)
OUTAPP="$B/$APP_NAME.app"
DMG="$B/Beat-Key-$VER.dmg"
# Spotlight finds the app by name for "beat" and "key"; this Finder comment + keywords carry
# "bpm" and "download". They are xattrs on the bundle folder: not sealed by the signature, and
# Finder / ditto keep them through the DMG and the drag to Applications.
FINDER_COMMENT="YouTube downloader, BPM and key finder: download a beat as MP3, get its BPM, tempo and key."
KEYWORDS="bpm download youtube mp3 key tempo beat music"
# Finder layout, shared with app/dmg/make_background.swift
WIN_W=600; WIN_H=380; ICON=112; APP_X=160; LINK_X=440; ICON_Y=190

security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\"" \
  || { echo "no '$IDENTITY' signing identity in the keychain"; exit 1; }
for f in "$APP/icon/Orion.icns" "$APP/dmg/background.png" "$APP/dmg/background@2x.png"; do
  [ -f "$f" ] || { echo "missing $f (run app/icon/make_icon.swift / app/dmg/make_background.swift)"; exit 1; }
done
echo "== $APP_NAME $VER"

echo "== swift build (universal)"
(cd "$APP" && swift build -c release --arch arm64 --arch x86_64)
PROD="$(cd "$APP" && swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
[ -x "$PROD/Orion" ] || { echo "no binary at $PROD/Orion"; exit 1; }
ARCHS="$(lipo -archs "$PROD/Orion")"
case "$ARCHS" in *arm64*x86_64*|*x86_64*arm64*) ;; *) echo "binary is not universal: $ARCHS"; exit 1 ;; esac

echo "== runtime"
[ -d "$B/runtime/arm64" ] && [ -d "$B/runtime/x86_64" ] && [ -d "$B/runtime/scripts" ] || "$APP/runtime.sh" build
"$APP/runtime.sh" sign

echo "== assemble $OUTAPP"
rm -rf "$OUTAPP"
mkdir -p "$OUTAPP/Contents/MacOS" "$OUTAPP/Contents/Resources"
cp "$PROD/Orion" "$OUTAPP/Contents/MacOS/Orion"
cp "$APP/Info.plist" "$OUTAPP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VER" "$OUTAPP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VER" "$OUTAPP/Contents/Info.plist"
plutil -replace NSHumanReadableCopyright -string "© $(date +%Y) J Shriver" "$OUTAPP/Contents/Info.plist"
plutil -lint "$OUTAPP/Contents/Info.plist" >/dev/null
printf 'APPL????' > "$OUTAPP/Contents/PkgInfo"
cp "$APP/icon/Orion.icns" "$OUTAPP/Contents/Resources/Orion.icns"
[ -d "$PROD/Orion_Orion.bundle" ] || { echo "no Orion_Orion.bundle in $PROD"; exit 1; }
ditto "$PROD/Orion_Orion.bundle" "$OUTAPP/Contents/Resources/Orion_Orion.bundle"
ditto "$B/runtime" "$OUTAPP/Contents/Resources/runtime"
find "$OUTAPP" -name .DS_Store -delete
xattr -cr "$OUTAPP"

echo "== sign app"
codesign --force --options runtime --timestamp --entitlements "$APP/entitlements.plist" \
  --sign "$IDENTITY" "$OUTAPP"
codesign --verify --deep --strict --verbose=2 "$OUTAPP"
# the yt-dlp entitlements survived (the app sign must not have re-signed nested code)
for a in arm64 x86_64; do
  ents="$(codesign -d --entitlements - "$OUTAPP/Contents/Resources/runtime/$a/bin/yt-dlp" 2>/dev/null)"
  for k in disable-library-validation allow-unsigned-executable-memory; do
    grep -q "$k" <<<"$ents" || { echo "yt-dlp ($a) lost its $k entitlement"; exit 1; }
  done
done

echo "== spotlight metadata"
bplist_hex() {  # $1 = an XML plist body (<string>/<array>); prints it as binary-plist hex
  local f; f="$(mktemp)"
  printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0">%s</plist>' "$1" > "$f"
  plutil -convert binary1 "$f"; xxd -p "$f" | tr -d '\n'; rm -f "$f"
}
kw=""; for w in $KEYWORDS; do kw="$kw<string>$w</string>"; done
xattr -wx com.apple.metadata:kMDItemFinderComment "$(bplist_hex "<string>$FINDER_COMMENT</string>")" "$OUTAPP"
xattr -wx com.apple.metadata:kMDItemKeywords "$(bplist_hex "<array>$kw</array>")" "$OUTAPP"
codesign --verify --deep --strict "$OUTAPP" || { echo "metadata xattrs broke the signature"; exit 1; }

echo "== dmg"
STAGE="$B/dmg-stage"; RW="$B/Beat-Key-rw.dmg"
rm -rf "$STAGE" "$RW" "$DMG"
mkdir -p "$STAGE/.background"
ditto "$OUTAPP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
tiffutil -cathidpicheck "$APP/dmg/background.png" "$APP/dmg/background@2x.png" \
  -out "$STAGE/.background/background.tiff" >/dev/null
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
MNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)"
[ -d "$MNT" ] || { echo "could not mount $RW"; exit 1; }
VOL="$(basename "$MNT")"
detach() { hdiutil detach "$MNT" -quiet 2>/dev/null || hdiutil detach "$MNT" -force -quiet 2>/dev/null || true; }
trap detach EXIT
# Finder lays the window out and writes .DS_Store. Bounds are the whole window; macOS adds the
# title bar (32 pt on current macOS, measured) on top of the content area, so the height gets
# TITLE extra.
TITLE=32
osascript <<EOF
tell application "Finder"
  tell disk "$VOL"
    open
    set w to container window
    set current view of w to icon view
    set toolbar visible of w to false
    set statusbar visible of w to false
    set pathbar visible of w to false
    set sidebar width of w to 0
    set bounds of w to {200, 120, 200 + $WIN_W, 120 + $WIN_H + $TITLE}
    set o to icon view options of w
    set arrangement of o to not arranged
    set icon size of o to $ICON
    set text size of o to 12
    set background picture of o to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of w to {$APP_X, $ICON_Y}
    set position of item "Applications" of w to {$LINK_X, $ICON_Y}
    update without registering applications
    delay 2
    close
    open
    delay 1
    close
  end tell
end tell
EOF
[ -f "$MNT/.DS_Store" ] || { echo "Finder wrote no .DS_Store: layout not saved"; exit 1; }
chmod -Rf go-w "$MNT" 2>/dev/null || true
sync
detach; trap - EXIT
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"; rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
echo "dmg: $DMG ($(du -h "$DMG" | cut -f1))"

[ "$NOTARIZE" = 1 ] || { echo "== skipped notarization (--no-notarize)"; exit 0; }

echo "== notarize (profile $PROFILE)"
OUTJ="$B/notary-$VER.json"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format json | tee "$OUTJ"
ID="$(/usr/bin/plutil -extract id raw -o - "$OUTJ" 2>/dev/null || true)"
STATUS="$(/usr/bin/plutil -extract status raw -o - "$OUTJ" 2>/dev/null || true)"
echo "submission $ID: $STATUS"
if [ "$STATUS" != Accepted ]; then
  [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" || true
  echo "notarization not Accepted: $STATUS"; exit 1
fi
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -vv -t open --context context:primary-signature "$DMG"
echo "done: $DMG"
