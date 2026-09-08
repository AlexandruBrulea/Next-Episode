# Next Episode icon

Source: `app-icon.png`, generated with the built-in image generation tool.
The artwork represents play/next episode and watch progress with a folded cyan/violet ribbon and orbital arcs on midnight navy. No lettering or baked-in rounded corners.

Generated outputs are committed directly to the platform resource folders:
- iOS: `ios/Runner/Assets.xcassets/AppIcon.appiconset`, including opaque 1024px App Store artwork.
- Android: five `mipmap-* / ic_launcher.png` density variants.
- Windows: `windows/runner/resources/app_icon.ico`, seven sizes.
- Google Play listing: `assets/branding/google-play-icon.png` (512px).

To change the icon later, replace `app-icon.png` and run `./tool/update-icons.ps1` from PowerShell on Windows. Commit the source and the platform outputs. Codemagic does not need an icon-generation dependency; a new native build picks up these resources automatically. No Flutter asset declaration is needed for launcher icons.

Generation prompt:
Create a single polished production mobile app icon for Next Episode, a TV series and movie watch tracker. Square 1024x1024 full bleed opaque dark midnight navy background, no rounded outside corners (OS masks it). A bold instantly recognizable central sculptural symbol: a right-facing play triangle formed from one folded luminous ribbon, with a short forward edge suggesting next episode and a restrained partial orbital arc suggesting watch progress. Electric cyan transitioning to violet, sophisticated softly beveled satin glass, crisp silhouette, restrained glow, exceptional readability at 48px. Symbol comfortably inside central 65% of canvas, balanced generous negative space. Premium futuristic entertainment brand, minimal, original. No text, no letters, no numbers, no filmstrip holes, no tiny details, no mockup, no phone, no extra icons, no watermark. Deliver only actual square icon artwork.
