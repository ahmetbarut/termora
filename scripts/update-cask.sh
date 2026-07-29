#!/bin/zsh
# Point Casks/termora.rb at a real DMG: rewrite `version` and `sha256`.
#
#   ./scripts/update-cask.sh build/release/Termora-1.0.dmg
#
# The checksum is computed from the file you pass, never typed. A sha256 that does not
# match the published DMG breaks `brew install` for everyone with an error that names
# neither side, so this is the one number that must not be hand-edited.
#
# After this runs, copy Casks/termora.rb into the tap repository
# (ahmetbarut/homebrew-termora) and push — that repo is what `brew` reads.

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
CASK="$PROJECT_ROOT/Casks/termora.rb"

fail() { print -P "%F{red}✗ $1%f" >&2; exit 1 }

DMG="${1:-}"
[[ -n "$DMG" ]] || fail "usage: update-cask.sh <path-to-dmg>"
[[ -f "$DMG" ]] || fail "no such file: $DMG"
[[ -f "$CASK" ]] || fail "cask missing: $CASK"

# The version comes from the DMG's own name, not from an argument: the file that ships
# and the version the cask claims can then never disagree.
VERSION="${${DMG:t:r}#Termora-}"
[[ "$VERSION" != "${DMG:t:r}" ]] || fail "DMG name must look like Termora-<version>.dmg, got ${DMG:t}"

PROJECT_VERSION=$(grep -m1 'MARKETING_VERSION = ' "$PROJECT_ROOT/Termora.xcodeproj/project.pbxproj" | sed 's/.*= //; s/;//')
[[ "$VERSION" == "$PROJECT_VERSION" ]] \
  || fail "DMG says $VERSION but the project says $PROJECT_VERSION — releasing a cask for a version that was never built"

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)

/usr/bin/sed -i '' \
  -e "s/^  version \".*\"$/  version \"$VERSION\"/" \
  -e "s/^  sha256 \".*\"$/  sha256 \"$SHA\"/" \
  "$CASK"

# Verify the rewrite landed: a silent no-op here would ship the old checksum.
grep -q "version \"$VERSION\"" "$CASK" || fail "version was not written"
grep -q "sha256 \"$SHA\"" "$CASK" || fail "sha256 was not written"

print -P "%F{green}✓ Casks/termora.rb → $VERSION%f"
print "  sha256 $SHA"
print "\nNext: copy this file into ahmetbarut/homebrew-termora and push."
print "Then verify on a clean Mac:  brew install --cask ahmetbarut/termora/termora"
