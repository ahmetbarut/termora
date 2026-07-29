#!/bin/zsh
# Termora release pipeline: build → sign → DMG → notarize → staple → verify.
#
# One-time setup (you run this once, it stores credentials in the login keychain):
#
#   xcrun notarytool store-credentials "termora-notary" \
#     --apple-id "<your Apple ID>" \
#     --team-id "WPLDF8U4M5" \
#     --password "<app-specific password from appleid.apple.com>"
#
# Then:  ./scripts/release.sh            # full release
#        ./scripts/release.sh --no-notarize   # local build + DMG only
#
# Nothing here uploads anything until the notarize step, and that step only runs
# when the credentials above exist.

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"

SCHEME="Termora"
CONFIG="Release"
TEAM_ID="WPLDF8U4M5"
SIGN_ID="Developer ID Application: Ahmet Barut ($TEAM_ID)"
NOTARY_PROFILE="termora-notary"
BUILD_DIR="$PROJECT_ROOT/build/release"
EXPORT_DIR="$BUILD_DIR/export"
NOTARIZE=1

for arg in "$@"; do
  case "$arg" in
    --no-notarize) NOTARIZE=0 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

step() { print -P "\n%F{blue}▸ $1%f"; }
fail() { print -P "%F{red}✗ $1%f" >&2; exit 1; }

# --- preflight ------------------------------------------------------------
step "Preflight"

security find-identity -v -p codesigning | grep -q "$SIGN_ID" \
  || fail "Signing identity not found: $SIGN_ID"
print "  signing identity ✓"

if [[ $NOTARIZE -eq 1 ]]; then
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    fail "Notary profile '$NOTARY_PROFILE' not found.
  Store it once with:
    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\
      --apple-id \"<your Apple ID>\" --team-id \"$TEAM_ID\" \\
      --password \"<app-specific password>\"
  Or run with --no-notarize to skip."
  fi
  print "  notary credentials ✓"
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :MARKETING_VERSION" /dev/stdin 2>/dev/null <<< "" || true)
VERSION=$(grep -m1 'MARKETING_VERSION = ' Termora.xcodeproj/project.pbxproj | sed 's/.*= //; s/;//')
BUILD_NUM=$(grep -m1 'CURRENT_PROJECT_VERSION = ' Termora.xcodeproj/project.pbxproj | sed 's/.*= //; s/;//')
print "  version $VERSION ($BUILD_NUM)"

# The tests are the gate: a release that ships a red suite is not a release.
step "Tests"
xcodebuild test -project Termora.xcodeproj -scheme "$SCHEME" \
  -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR/dd-test" \
  -only-testing:TermoraTests > "$BUILD_DIR-test.log" 2>&1 \
  || fail "Tests failed — see $BUILD_DIR-test.log"
print "  $(grep -oE "Test case '[A-Za-z]+/[a-zA-Z0-9_]+\(\)' passed" "$BUILD_DIR-test.log" | sort -u | wc -l | tr -d ' ') tests passed ✓"

# --- archive & export -----------------------------------------------------
step "Archive"
rm -rf "$BUILD_DIR/Termora.xcarchive" "$EXPORT_DIR"
xcodebuild archive -project Termora.xcodeproj -scheme "$SCHEME" \
  -configuration "$CONFIG" -archivePath "$BUILD_DIR/Termora.xcarchive" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY="$SIGN_ID" CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -quiet || fail "Archive failed"

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST

step "Export"
xcodebuild -exportArchive -archivePath "$BUILD_DIR/Termora.xcarchive" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR" -quiet || fail "Export failed"

APP="$EXPORT_DIR/Termora.app"
[[ -d "$APP" ]] || fail "Exported app not found at $APP"

# Hardened runtime is required for notarization; the project sets it, verify anyway.
codesign -dv --verbose=4 "$APP" 2>&1 | grep -q "flags=.*runtime" \
  || fail "Hardened runtime missing — notarization would be rejected"
print "  hardened runtime ✓"

# --- DMG ------------------------------------------------------------------
step "DMG"
DMG="$BUILD_DIR/Termora-$VERSION.dmg"
STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Termora" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet \
  || fail "DMG creation failed"
codesign --force --sign "$SIGN_ID" --timestamp "$DMG" || fail "DMG signing failed"
print "  $DMG ✓"

# --- notarize -------------------------------------------------------------
if [[ $NOTARIZE -eq 0 ]]; then
  print -P "\n%F{yellow}Skipped notarization (--no-notarize).%f"
  print "Gatekeeper will refuse this DMG on another Mac until it is notarized."
  exit 0
fi

step "Notarize (uploads the DMG to Apple)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
  || fail "Notarization failed — inspect with: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"

step "Staple"
xcrun stapler staple "$DMG" || fail "Stapling failed"

step "Verify"
spctl -a -vvv -t install "$APP" 2>&1 | grep -q "accepted" \
  || fail "Gatekeeper rejected the app"
xcrun stapler validate "$DMG" || fail "Stapler validation failed"

print -P "\n%F{green}✓ Release ready: $DMG%f"
print "Verified: signed with Developer ID, notarized, stapled, accepted by Gatekeeper."

# --- Homebrew cask --------------------------------------------------------
# The checksum is computed from the DMG that was just notarized, so the cask can never
# claim a checksum for a build that does not exist.
step "Homebrew cask"
"$PROJECT_ROOT/scripts/update-cask.sh" "$DMG" || fail "Cask update failed"

# --- appcast reminder -----------------------------------------------------
# The DMG is ready to hand out, but existing installs learn about it only through the
# Sparkle appcast — and that step needs the EdDSA private key, which lives in your login
# Keychain and deliberately never enters this script (see docs/updates.md).
if /usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$APP/Contents/Info.plist" >/dev/null 2>&1; then
  print -P "\n%F{yellow}Next: sign this release into the appcast.%f"
  print "  ./bin/generate_appcast <releases-dir>/   # from the Sparkle release archive"
  print "Until the appcast is updated, installed copies will not see this version."
else
  print -P "\n%F{yellow}This build carries no SUFeedURL — installed copies cannot update themselves.%f"
  print "See docs/updates.md to set SUFeedURL and SUPublicEDKey."
fi
