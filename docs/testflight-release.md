# TestFlight build — Codemagic workflow editor

Checklist for the next build; verify signing and App Store Connect state in Codemagic before upload.

## Existing project

- Entry point: `lib/main.dart`.
- Bundle identifier: `ro.nextepisode.nextEpisode` (register exactly this identifier, or deliberately update the project before creating the app record).
- Next candidate version: `0.1.2+11`. Increase the build number for every subsequent upload; verify that build 11 has not already been used in App Store Connect before submitting it.
- Minimum iOS version: 15.0.
- Never use `lib/retention_preview.dart` or `DEMO=true` for a distributed build.

## Build and upload

1. Register the explicit App ID in the Apple developer account and create the matching iOS app in App Store Connect.
2. Connect an App Store Connect API key to Codemagic using its integration settings. Keep the private key in the integration, not in Git.
3. In the existing Flutter workflow editor, choose iOS and Release mode. Remove `--simulator` and any `--no-codesign` argument.
4. Configure automatic iOS code signing for **App Store**, using the matching bundle identifier and Apple team.
5. Supply the application's compile-time configuration below.
6. Enable App Store Connect publishing for the signed IPA. Start with TestFlight testing; do not configure automatic public App Store release.
7. Build, check signing/build logs, then wait for App Store Connect processing. Complete any export-compliance questions based on the actual build.
8. Assign the processed build to an internal TestFlight group and install it on a real iPhone. External testing may require Beta App Review.

## Application configuration

The local `.env` is not assumed to exist on the build machine. Store the same configuration securely in Codemagic. Environment variables alone do not become Dart compile-time definitions: pass a generated configuration file using `--dart-define-from-file`, or pass the relevant `--dart-define` arguments.

Required values for this release:

- `CONTENT_PROVIDER=tmdb`
- `CONTENT_GENERATION`: use the current deployment generation; do not lower it for existing installs.
- `TMDB_CONTENT_ENABLED=true`
- `TMDB_TOKEN`: the configured TMDB credential.
- `SUPPORT_EMAIL`: the public contact from the local configuration.
- `DEMO=false`
- `CONTENT_CONFIG_URL`: only set if a production configuration endpoint has been deployed and verified.

Use `lib/main.dart`. Do not commit the configuration file containing the token, echo its contents in logs or add it to build artifacts. A token bundled in a mobile app remains extractable; CI secret storage does not make the installed token confidential.

The update-issue screen is always available. Its local history has at most 20
records; it does no network work at startup. Tapping Email report prepares a
separate text-file attachment and opens the mail composer; the user must send
the email. On iPhone, prefilled recipient plus attachment requires an Apple
Mail account. If unavailable, the share sheet preserves the attachment but
the recipient may need manual entry. Changing `SUPPORT_EMAIL` requires a new
build. Before release, test both paths on real devices and confirm receipt in
the support inbox. Review the privacy page and App Privacy answers.

## Release verification still required

- Inspect the final signed archive's privacy manifests and required-reason API declarations, including dependencies. Absence of an app-level manifest alone does not establish whether declarations are missing.
- Complete App Privacy from actual network and SDK behavior. Do not infer “Data Not Collected” solely from local library storage.
- Verify notification permission denial and approval, before/after timing and cancellation after marking an episode watched.
- Verify startup, background/resume, offline mode, persistent progress and app-update retention of the database.
- Check iPhone/iPad layout, large text, external links, support email and bundled legal documents.
- Resolve existing failing tests and analyzer warnings before final release validation.
- Complete publisher/trader information and the age-rating questionnaire; check final app name availability.

Sources: [Codemagic iOS signing in workflow editor](https://docs.codemagic.io/flutter-code-signing/ios-code-signing/), [Apple submission](https://developer.apple.com/app-store/submitting/).
