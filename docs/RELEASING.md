# Releasing Interval

Interval uses the official Sparkle Swift package pinned to 2.9.6. The release script deliberately refuses to run without all production credentials; an ad-hoc-signed local build is runnable but cannot be notarized or distributed as a trusted public update.

1. Install a `Developer ID Application` certificate and create an `xcrun notarytool store-credentials` keychain profile.
2. Generate and securely retain Sparkle's EdDSA private key. Publish only its public key in `SPARKLE_PUBLIC_KEY`.
3. Set an HTTPS appcast location (`UPDATE_FEED_URL`), `CODE_SIGN_IDENTITY`, `NOTARY_PROFILE`, `SPARKLE_PUBLIC_KEY`, semantic `VERSION`, and positive integer `BUILD_NUMBER`. If archives are hosted somewhere other than the appcast's directory, also set HTTPS `ARCHIVE_URL_PREFIX`.
4. Run `scripts/release.sh`. It builds and signs nested Sparkle code inside-out, notarizes, staples, packages, signs the archive with Sparkle `sign_update`, and runs `generate_appcast`.
5. Inspect and upload the ZIP and generated appcast together. Confirm the appcast URL and archive URL are HTTPS before publishing.

Do not publish an ad-hoc build, invent credentials, skip notarization, or expose the Sparkle private key. See Sparkle's official [documentation](https://sparkle-project.org/documentation/) and [2.9.6 release](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.6).
