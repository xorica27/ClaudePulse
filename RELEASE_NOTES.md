# ClaudePulse 0.2.2

Checksummed releases, and a Launch at Login toggle that works immediately.

## Added

- **SHA-256 checksums.** `package-dmg.sh` and `package-zip.sh` now write a `.sha256` file next to each artifact, so a downloaded DMG or zip can be verified against the published hash.

## Changed

- **Launch at Login applies immediately.** Enabling it now bootstraps the LaunchAgent right away instead of waiting for the next login.
- **Release builds no longer depend on the locale.** A multibyte character directly after a shell variable made `build-release.sh` fail on systems whose default locale is not a classic UTF-8 locale (including `C.UTF-8`); the build now works regardless of locale.

# ClaudePulse 0.2.1

ClaudePulse now runs on Intel Macs.

## Added

- **Intel Mac support.** Nothing in the app was ever Apple Silicon specific — it is plain Swift and AppKit, and the cookie decryption path uses CommonCrypto against the same `Claude Safe Storage` Keychain item on either architecture. Only the release build pinned `arm64`, which left Intel Macs with no download that would open at all. Release builds are now universal `arm64` + `x86_64` and run natively on both, with no Rosetta needed on either.

## Changed

- **Release artifacts are renamed** from `ClaudePulse-macos-arm64.{dmg,zip}` to `ClaudePulse-macos-universal.{dmg,zip}`. Anything pointing at the old filenames — a bookmark, a download script — needs updating. The 0.2.0 assets keep their original names.
- `scripts/build-release.sh` builds both architectures and fails if a requested slice is missing from the result, so a build that quietly falls back to one architecture cannot ship. `CLAUDEPULSE_ARCHS=arm64` overrides it for a faster single-slice local build.
- The packaging scripts derive their artifact name from the binary they are handed rather than hardcoding it, so a filename can never promise a slice the app does not carry.

## Requirements

- macOS 13 or newer
- Apple Silicon or Intel Mac

## Privacy

Unchanged. ClaudePulse makes authenticated read requests to Claude's own endpoints using Claude Desktop's local cookies. It does not send telemetry, contact third-party services, or display cookie values.

This build is ad-hoc signed, so macOS may ask for confirmation the first time you open it. If that happens, right-click `ClaudePulse.app`, choose **Open**, then confirm.
