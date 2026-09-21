# Large-library startup

The home screen uses local cached data before starting automatic network sync.
Automatic sync skips active shows updated within six hours and ended/canceled
shows updated within seven days. A missing or expired cache is always eligible.
Explicit `sync()` / repository `refresh()` calls still support a forced refresh.
These intervals are eligibility checks while the app runs, not iOS background jobs.

Only Library is built on first launch. Other tabs are created on their first visit
and retained afterward so navigation state is preserved. Episode cache loading
uses a single query; production file databases decode and validate the JSON in a
Dart isolate. Retention scans also decode the main metadata tables in isolates.

Retention skips repeated scans only while SQLite change counters, content access,
and expiry permit it. Writes, external database changes, expiry, clock rollback,
and policy changes require a new scan. A scan inside an enclosing transaction
cannot authorize skipping the next scan because that transaction may roll back.
No retention duration or watched history is changed.

A no-op sync leaves the existing library snapshot intact. Successful updates
reload only the affected episode bundles and invalidate their detail providers.
Watch-progress calculations are reused within each snapshot/day. Alerts are
refilled on the first sync of the session/day and after a library update.

## Marking watched progress

Single episodes, seasons and the To watch confirmation save progress in one
atomic SQL batch with history. Existing watched timestamps are preserved and
duplicate/no-op actions do not create duplicate history. After saving, only
watched marks are read back; the loaded catalog and unaffected show progress
calculations are reused. Confirmation also reuses the loaded show's episodes.
The interface receives saved progress before notification scheduling finishes.
An older metadata reload cannot overwrite a newer published watched snapshot.

Badge scheduling builds release/expiry prefix counts once per refresh, instead
of traversing all episodes for every scheduled notification. Badge counts and
retention cutoffs keep the same behavior.

The Windows in-memory regression fixture (210 shows / 16,800 episodes, marking
80 episodes) measured 3,729 ms before and 22–26 ms after these changes, with
catalog/library reads during marking reduced from one each to zero. These are
test-harness measurements, excluding real iPhone rendering, disk and notification
delivery; they are not an iPhone latency guarantee. Network synchronization can
still continue after launch, and an in-flight catalog database transaction may
briefly share the database with progress writes.

## Navigation and image work

To Watch builds widgets on demand, with one viewport of prepared rows ahead
and behind. It keeps five episodes per show initially and expands by three with
Show more. Episode filtering still uses the complete in-memory snapshot, so a
watch mark removes the episode immediately even when it is off screen.

Saved show/season screens read their complete bundle synchronously from the
library. Missing or expired bundles use the existing repository loader; normal
background refresh no longer replaces saved details with a loading spinner.
Every screen still observes the shared watched map, including hidden tabs.

TMDB poster thumbnails use w185 or w342 only when that bucket covers the physical
display pixels, accounting for screen density and the 2:3 cover crop. Larger
posters retain their existing w500 source. Layout and non-poster art are unchanged.
The sizes follow TMDB's image URL scheme and documented poster buckets:
https://developer.themoviedb.org/docs/image-basics
https://www.themoviedb.org/talk/5ca37ad692514140e049a0ed

Notification rescheduling and database transaction ordering are unchanged by
these navigation improvements.

## Verification

`test/startup_performance_test.dart` exercises 210 shows / 16,800 episodes,
zero catalog requests and no snapshot replacement for a fresh library, six-hour
and seven-day eligibility, missing-cache recovery, forced refresh, watch dates,
file-backed worker decoding, and expiry/rollback/disable behavior.
`test/progress_performance_test.dart` covers the large-library marking path,
idempotent history, atomic rollback, unreleased-episode validation, concurrent
metadata reload and marking during pending network sync. Badge tests compare
prefix counts with ordinary release counting and exercise expiry boundaries.
`test/navigation_performance_test.dart` checks lazy rows with 210 shows, Show more,
scrolling, synchronous saved details without a repository loader, live watched
updates, missing/expired bundle fallback, and density-aware poster sizes.

Before shipping, profile a physical iPhone with a realistic 210-show library:
measure launch-to-library, frame timings during scrolling/sync, memory, and HTTP
request count. Repeat with fresh data, stale data, offline mode, and quick resume.
Desktop tests do not establish an iPhone speedup or a launch-time guarantee.

Incremental fetching of individual seasons is a separate follow-up: an eligible
show currently still receives a full refresh. Also, the initial library snapshot
still loads its episode bundles; persisted summary-only startup is not included.
