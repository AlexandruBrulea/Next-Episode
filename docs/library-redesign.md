# Library, calendar and iOS presentation

- Library uses three columns with lazily built poster cards, SHOW/MOVIE labels,
  watch progress, title, release year and the available status.
- The watch-time card covers the whole saved library, independent of search and
  filters. A watched mark counts a full episode or movie once. The denominator
  includes all cached known episodes, including specials and announced episodes.
  Episode runtime takes precedence over the show's runtime fallback. Estimated
  durations are labelled; missing durations or unavailable titles are excluded
  and disclosed. Removing a title removes it from this library total while its
  watch history remains saved. This is not measured playback time.
- Calendar cards group by title identity, season and exact air date. Different
  dates remain separate, and gaps render as `E01, E03` rather than an invented
  continuous range. A batch opens an episode chooser; a single episode opens
  its details directly. Existing all-watched ticks apply to the entire batch.
- LaunchScreen and the initial native Flutter view use opaque navy `#040C28`.
  The existing centered logo is retained.
- Enabling Episode alerts requests iOS alert, sound and badge authorization.
  The settings screen links to the native notification settings on iOS 16.0+
  and app settings on earlier supported versions. iOS owns these switches;
  the app cannot override a user's choice. A badge of 1 means a new reminder,
  and clears when the app becomes active, including the scene lifecycle.

## Release checks

Widget/domain tests cover three columns at narrow widths and enlarged text,
watch-time math, grouped release ranges and navigation, and mocked iOS permission
requests. Both storyboard files parse as XML. Native Swift compilation and real
iPhone notification controls require the normal Xcode/Codemagic/TestFlight build;
they cannot be verified by Windows widget tests.

In TestFlight, check a cold launch, app switcher, enabling notifications, changing
banners/sounds/badges in Settings, receiving a reminder, and clearing its badge.

## App Store search images

The supplied screenshot shows **Open**, so the app is already installed. A compact
search result is not evidence that product-page screenshots are missing. Apple
controls the search presentation and says that up to three screenshots/previews
may appear, depending on platform and image orientation:
https://developer.apple.com/app-store/search/

Check the full product page and a device without the app installed. If screenshots
are absent on the product page too, verify the published version, language and
iPhone screenshot sets in App Store Connect:
https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots

No App Store Connect metadata, screenshots, or release were changed here.
