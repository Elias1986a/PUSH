# PUSHTYPE

**Dictation and autocomplete for the Mac, all on-device.** Hold a key and
speak, or start typing and PUSHTYPE finishes your sentence (Type). Sold at
[pushtype.app](https://pushtype.app): $35 once for 3 Macs.

The repo, bundle id (`com.push.voicetotext`), executable, `PUSH.app` and
Application Support folder are still called PUSH; users see PUSHTYPE.

- **How the code is laid out, and the rules for working on it:** [CLAUDE.md](CLAUDE.md)
- **What changed and why, release by release:** [NOTES.md](NOTES.md) and `release-notes/`
- **Models and why they were chosen:** [docs/MODELS.md](docs/MODELS.md)
- **Website:** `website/` (Netlify, plain HTML; see `netlify.toml`)
- **Legal pages:** `legal/*.md`, rendered by `python3 website/build_legal.py`

## Build

```bash
swift build      # build
swift test       # unit tests
swift run        # run (not the shipped app: own prefs domain, no Info.plist)
```

Use Xcode's toolchain: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
(the Command Line Tools' Foundation breaks FluidAudio). `.build` is a symlink to
`~/Library/Developer/SwiftPackages/PUSH-build`, because iCloud evicts files in
~/Documents and hangs builds.

## Release

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `PUSH/Info.plist`,
   and write `release-notes/<version>.md`.
2. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./build_distribution.sh`
   builds, signs, notarizes, staples, makes the DMG and ZIP, and prepends the new
   item to `appcast.xml` (the feed keeps every past release). `SIGN_ONLY=1` stops
   at a signed test app in `~/Library/Developer/SwiftPackages/PUSH-dist/` (quit a
   running copy from there first).
3. Run the two commands it prints: `gh release create v<version> …` (the tag must
   match the appcast URL), then commit and push `appcast.xml`.
4. Upload the new DMG to Polar.

Needed on the release Mac, set up once:
- **Developer ID certificate** for team B8R5B24PMP in the login Keychain.
- **Notarization credentials:** `xcrun notarytool store-credentials "notarytool-profile"`
  with an app-specific password.
- **Provisioning profile** for iCloud at
  `~/Library/Developer/PUSH-signing/PUSH_Developer_ID_iCloud.provisionprofile`.
  An app with the iCloud entitlement and no profile refuses to launch.
- **Sparkle's EdDSA private key** in the login Keychain (service
  `https://sparkle-project.org`). Without it no update can be signed that
  installed copies will accept, so keep a backup
  (`generate_keys -x sparkle_private_key.txt`, stored offline).

## Licence

Proprietary: [LICENSE](LICENSE) and the [EULA](legal/EULA.md). Versions up to
8.2.2 were MIT-licensed and remain so. Open-source components and models are
credited in [Third-party notices](legal/THIRD_PARTY_NOTICES.md).
