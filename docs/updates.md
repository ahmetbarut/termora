# Signed automatic updates (Sparkle)

Termora ships Sparkle 2, but **an ordinary build does not update itself.** The updater
only starts when the app bundle carries both of these Info.plist keys:

| Key | What it is |
|---|---|
| `SUFeedURL` | the HTTPS address of your `appcast.xml` |
| `SUPublicEDKey` | the EdDSA **public** key that signs your releases |

Either one missing → `AppUpdater` is never constructed, Settings ▸ Updates says so
plainly, and the app behaves exactly as it did before Sparkle was added. Both are
required together on purpose: a feed without a public key would mean downloading and
installing a package whose signature cannot be verified, which is the one thing
briefs/2 forbids ("İmzası doğrulanamayan paket kurulmuyor").

## One-time setup

1. **Generate the key pair.** Sparkle's `generate_keys` stores the *private* key in your
   login Keychain and prints the public one. The private key never leaves your Mac and
   must never enter this repository.

   ```sh
   # From the Sparkle release archive (https://github.com/sparkle-project/Sparkle/releases)
   ./bin/generate_keys
   ```

   Back it up somewhere safe. Losing it means you can never sign an update that existing
   installs will accept — every user has to reinstall by hand.

2. **Put the public key and the feed address in the build.** Add these two build settings
   to the Termora target (the project generates its Info.plist, so `INFOPLIST_KEY_*` is
   how custom keys get in):

   ```
   INFOPLIST_KEY_SUFeedURL = https://<your-host>/appcast.xml
   INFOPLIST_KEY_SUPublicEDKey = <the public key generate_keys printed>
   ```

3. **Host the appcast.** After `scripts/release.sh` produces a notarized DMG, run
   Sparkle's `generate_appcast` over the directory holding your releases. It signs each
   package with the private key from step 1 and writes `appcast.xml`:

   ```sh
   ./bin/generate_appcast /path/to/releases/
   ```

   Upload the directory (DMG + `appcast.xml`) to the host named in `SUFeedURL`. Serve it
   over HTTPS — Sparkle refuses plain HTTP feeds.

## What the update check sends

The check asks the feed for the latest version number. Nothing else. Sparkle's optional
machine profile (CPU, model, language, macOS version) is switched off in
`UpdaterConfiguration.sendsSystemProfile`, which is a **constant, not a setting** — a
switch the user can see is a switch that can one day come on by accident. `UpdateController`
re-applies it every time settings change, so no other code path can turn it back on.

briefs/2 "Gizlilik": *Güncelleme kontrolü telemetri toplamıyor.*

## Release notes and "Remind Me Later"

The update window (version number, release notes, download size, Install / Skip This
Version / Remind Me Later) is Sparkle's standard user driver. Release notes come from the
`<description>` of each appcast item, so write them there — `generate_appcast` will pick
up a matching `.html` file next to the DMG.
