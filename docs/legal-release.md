# TMDB legal material — release handoff

Scope: free app, no advertisements, subscriptions or in-app purchases. TVmaze implementation and its existing credit have not been changed. This is implementation work, not a certification of worldwide legal compliance.

## Single source of text

Set `SUPPORT_EMAIL` in `.env`. The app reads it at compile time through `lib/application/app_contact.dart`; the JSON templates contain `{{SUPPORT_EMAIL}}`, never a duplicated address. Restart/rebuild with `--dart-define-from-file=.env` after changing it (hot reload is not sufficient). Supply the same define in Codemagic. Without it, email support is disabled and the app explicitly reports the missing contact.

The HTML files are generated outputs: do not edit their email addresses manually. After changing `.env`, run `./tool/export-legal.ps1` and republish those files. An alternative build configuration can be selected with `./tool/export-legal.ps1 -EnvFile path/to/config.env`. The exporter reads only SUPPORT_EMAIL into the documents and rejects a missing or invalid address.

The app reads `assets/legal/privacy.json` and `assets/legal/terms.json` offline. Run `./tool/export-legal.ps1` after changing either document; it produces matching standalone `docs/legal/privacy.html` and `terms.html`. No analytics, external fonts or scripts are included in these HTML files.

## Required before public release

- Confirm the postal contact address and any other legally required publisher details before publication. The confirmed publisher is **Alexandru Ionut Brulea**, based in **Romania**. No address was supplied or invented. Email is configured once using **SUPPORT_EMAIL** in `.env`.
- Publish the HTML at stable public HTTPS URLs, without login or geographic restrictions. No hosting or store submission has been performed. Put the privacy URL in App Store Connect and Play Console and link it from the app once the URL is known. The in-app copy remains available offline.
- Review and accept the complete current TMDB API agreement in the developer account. The official FAQ supports noncommercial use with attribution, but is not the complete contract. Recheck licensing before introducing any revenue model.
- Confirm actual provider retention/transfer safeguards and the privacy policy's legal bases with the publisher. Complete Apple App Privacy and Google Data safety accurately: local-only library storage does not mean no information leaves the device. Catalog requests, image requests and optional support email involve external services. Do not claim unverified provider retention or mark every category “not collected” without evaluating store definitions.
- Review audience/age rating and the rights to third-party content for the intended markets. Verify privacy disclosures for the exact SDK versions and final release build. A document alone cannot satisfy all operational legal duties.
- Run Flutter dependency resolution, analysis and device checks: credits/logo visible offline, both documents readable with large text, external policy links, email composer, and TMDB Where to Watch. The new SVG dependency requires `flutter pub get`; its lockfile must be resolved before release. Runtime checks were not executed in this editing session.

## Attribution asset

`assets/credits/tmdb.svg` is the official **Alt short (blue)** logo from https://www.themoviedb.org/about/logos-attribution, fetched September 9, 2026.
Source: https://www.themoviedb.org/assets/v4/logos/v2/blue_short-8e7b30f73a4020692ccca9c88bafe5dcb6f8a62a4c6bc55cd9ba82bb2cd95f6c.svg

Its CSS class fill was expressed as an equivalent SVG presentation attribute for renderer compatibility. Geometry, colors, gradient and aspect ratio are unchanged. It is bundled locally, displayed without tint at 120 logical pixels, below the app name. It is third-party branding, not an app-owned asset. JustWatch is credited next to availability data and in About. The availability list remains across regions; its caption makes that scope explicit.

## Official references checked

- TMDB attribution and noncommercial use: https://developer.themoviedb.org/docs/faq
- TMDB brand assets: https://www.themoviedb.org/about/logos-attribution
- TMDB API agreement: https://www.themoviedb.org/api-terms-of-use
- JustWatch attribution via TMDB: https://developer.themoviedb.org/reference/tv-series-watch-providers
- Apple privacy policy requirements: https://developer.apple.com/app-store/review/guidelines/#privacy
- Google Play User Data / Privacy Policy / Data safety: https://support.google.com/googleplay/android-developer/answer/10144311

The complete TMDB API agreement was subsequently retrieved directly from the official site on September 9, 2026 (page states last updated October 20, 2023). Provider privacy practices and the developer account's actual agreement still require final verification. No assertion of review approval or complete legal compliance is made.

## API compliance findings — release blockers

TMDB API terms section 1.C sets a maximum of six months for cached TMDB information. Section 1.D requires cessation of API/content use and prompt purging of cached content when the license ends. These are technical duties, not resolved by changing legal text.

The application now implements timestamp-based expiry, metadata cleanup and an explicit administrative disable flag. See [TMDB retention](tmdb-retention.md) for behavior, configuration, tests and the remaining limitations around offline devices, backups and minimal identity mappings. This addresses the application mechanism; it does not certify behavior of devices that never reconnect or third-party backups.

The app is free without advertising or paid features. Keep developer/API identity accurate; do not resell API access/content, use it for AI training or introduce direct/indirect monetization without checking the agreement. The required nonendorsement notice now follows the API agreement's wording. The user-facing terms do not transfer the publisher's API-contract obligations to end users.

## Apple / Romania release configuration

- For iOS, use Apple's **standard EULA**. Do not paste the app's service terms into the custom EULA field of App Store Connect. The Terms of Use now explicitly link the standard EULA. Android/other versions have a separate scoped personal-use license with statutory and open-source exceptions.
- Romanian law applies to the service terms with preservation of mandatory consumer protections and competent courts. Do not promise that free pricing exempts the publisher from GDPR, consumer or store obligations; assess the actual activities and applicable rules.
- Confirm EU DSA trader status in App Store Connect. Free pricing alone does not establish non-trader status; the publisher must assess its activity. Provide and verify the required details for the selected status. Postal address remains unconfirmed.
- Privacy identifies the Romanian publisher and provides ANSPDCP complaint links and GDPR rights. Confirm controller responsibilities, lawful bases and transfer protections for actual third-party processing; generic policy text cannot replace this assessment.
- Confirm app name/branding rights independently, final audience/age rating, privacy manifests/required-reason APIs in the signed build, and store privacy disclosures. No store submission or account configuration was performed.

Additional official references:
- Apple standard EULA: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
- Apple automatic standard EULA application: https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/
- Apple EU trader requirements: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
- ANSPDCP complaints: https://www.dataprotection.ro/index.jsp?lang=ro&page=procedura_plangerilor
- Romanian digital-content legislation (scope must be assessed): https://legislatie.just.ro/Public/DetaliiDocument/250054
