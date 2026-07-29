# Homebrew Cask for Termora (briefs/2 "Dağıtım").
#
# This file is the source of truth that gets copied into the tap repository
# (ahmetbarut/homebrew-termora). `scripts/update-cask.sh` rewrites `version` and
# `sha256` from a real, notarized DMG — never edit those two lines by hand, because a
# sha256 that does not match the published DMG makes `brew install` fail for everyone
# with a checksum error and no way to tell which side is wrong.
cask "termora" do
  version "1.0"
  sha256 "cc0afe92d394299f35ceb6ec0e6d128f99b17b7fa85afa7e9b661a3f44a12dc0"

  url "https://github.com/ahmetbarut/termora/releases/download/v#{version}/Termora-#{version}.dmg",
      verified: "github.com/ahmetbarut/termora/"
  name "Termora"
  desc "Terminal for macOS with workspaces, SSH and AI assistance"
  homepage "https://github.com/ahmetbarut/termora"

  # Sparkle keeps the app up to date once it is installed; Homebrew only needs to know
  # that so `brew upgrade` does not fight it (see docs/updates.md).
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Termora.app"

  zap trash: [
    "~/Library/Application Support/Termora",
    "~/Library/Caches/com.ahmetbarut.Termora",
    "~/Library/Preferences/com.ahmetbarut.Termora.plist",
    "~/Library/Saved Application State/com.ahmetbarut.Termora.savedState",
  ]
end
