# Saber fork on iPad

This fork (`ladisk/saber`) adds the features listed in the README. It runs on the iPad without a paid Apple Developer account:

1. GitHub Actions builds an **unsigned** `.ipa` (plus Linux builds) and
   publishes them as a GitHub release.
2. **SideStore** on the iPad signs it with a free Apple ID and installs it.
3. **LocalDevVPN** lets SideStore reach the iPad's own install service. It is
   a loopback VPN: no traffic leaves the iPad.

Free signatures last **7 days**, so SideStore must refresh the apps weekly.

## Weekly: keep the apps alive

1. Turn on LocalDevVPN (status bar shows **VPN**).
2. Open SideStore → *My Apps* → **Refresh All**.

If the apps expire, they do not open until refreshed. Notes are not lost.

## Shipping a new build

For a change in this fork, or after merging upstream updates (below):

1. Commit and push to `origin` (`ladisk/saber`).
2. Start the build:

   ```sh
   gh workflow run fork-release.yml -R ladisk/saber
   ```

   It takes about 10–15 minutes. Watch it with
   `gh run list -R ladisk/saber --workflow fork-release.yml`.
   It creates a release named `v<version>-fork.<n>` (e.g. `v1.36.1-fork.2`;
   `<n>` restarts at 1 after an upstream version change) with the iPad
   `.ipa` and Linux `.AppImage` / `.tar.gz` files (x86_64 and arm64).
3. On the iPad, with LocalDevVPN on: open the release in Safari, download the
   `.ipa`, then SideStore → *My Apps* → **+** → pick the file.
   It replaces the installed Saber and keeps notes and settings.

The workflow is manual-only on purpose. Pushing a tag would also start the
upstream release workflows, which fail on this fork (they need the upstream
author's signing secrets).

## Pulling upstream Saber updates

```sh
git fetch upstream
git log --oneline main..upstream/main   # what is new
git merge upstream/main                 # fix conflicts if any
./submodules/flutter/bin/flutter test   # see baseline below
```

Conflicts are most likely in `lib/pages/editor/editor.dart` and
`lib/data/tools/select.dart`, where the resize feature lives. Then ship a new
build as above.

## Building and testing on Linux

Flutter is the repo's pinned submodule, not a system install:

```sh
git submodule update --init --depth 1 submodules/flutter
./submodules/flutter/bin/flutter pub get
JAVA_HOME=$(mise where java@temurin-21) \
  ./submodules/flutter/bin/flutter build linux --debug
build/linux/x64/debug/bundle/saber
```

- If Flutter reports version `0.0.0-unknown`, fetch its tag:
  `git -C submodules/flutter fetch --depth 1 origin 'refs/tags/<version>:refs/tags/<version>'`.
- Rust (via mise) and a JDK are needed by native dependencies.
- If a Linux build fails during configuration, delete `build/linux` before
  retrying. A stale CMake cache makes it try to install into `/usr/local`.
- 16 tests fail on unmodified upstream as well (screenshot goldens, Nextcloud
  network tests, version check). Only new failures matter.
- The debug app uses your real Nextcloud account and syncs immediately.

## Troubleshooting on the iPad

| Symptom | Fix |
|---|---|
| SideStore: "No Wi-Fi or VPN connection" | LocalDevVPN connected and Wi-Fi on; turn off other VPNs and DNS/ad blockers; restart both apps; retry. |
| An app shows **revoked** | LocalDevVPN on, SideStore → **Refresh All**. |
| SideStore does not open at all | Reinstall it from Linux with iloader (below). |
| Installing fails: "signing certificate … was revoked" | SideStore's own certificate is revoked. See *SideStore must own the certificate* below. |

### Reinstalling SideStore from Linux (rarely needed)

Each iloader install revokes the current certificate, so use it only when
SideStore itself is broken.

1. Packages: `sudo pacman -S --needed usbmuxd fuse2`.
2. Connect the iPad by USB, unlock it, and trust the computer if asked.
   `idevicepair validate` should report success.
3. Run `~/Applications/iloader.AppImage`
   ([releases](https://github.com/nab138/iloader/releases)), sign in with the
   Apple ID, select the iPad, click **SideStore (Stable)**. If it reports
   "Maximum certificates reached", click **Continue**.
4. Give SideStore its own certificate, as below.

### SideStore must own the certificate

A free Apple ID holds very few signing certificates, and making a new one
revokes an old one. iloader signs SideStore with *iloader's* certificate,
but SideStore cannot use that one to sign other apps. If SideStore is left
with an old, revoked certificate of its own, refreshing installed apps may
still seem to work, but installing anything fails with "signing certificate
… was revoked".

Fix, on the iPad, all in one go without leaving SideStore:

1. LocalDevVPN on. SideStore → Settings → **Sign Out**, then sign in again.
2. When it asks which certificate to revoke (e.g. "iloader"), tap
   **Revoke**. SideStore creates its own certificate.
3. Right away: *My Apps* → refresh **SideStore** itself, then
   **Refresh All**. A running app is not stopped by a revoked certificate,
   but SideStore will not reopen until it is re-signed.

Do not delete Saber to fix signing problems: deleting removes notes that
are not yet synced to Nextcloud.

First-time iPad setup also needs Developer Mode
(*Settings → Privacy & Security*) and trusting the Apple ID under
*Settings → General → VPN & Device Management*.
