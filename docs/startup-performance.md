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

## Verification

`test/startup_performance_test.dart` exercises 210 shows / 16,800 episodes,
zero catalog requests and no snapshot replacement for a fresh library, six-hour
and seven-day eligibility, missing-cache recovery, forced refresh, watch dates,
file-backed worker decoding, and expiry/rollback/disable behavior.

Before shipping, profile a physical iPhone with a realistic 210-show library:
measure launch-to-library, frame timings during scrolling/sync, memory, and HTTP
request count. Repeat with fresh data, stale data, offline mode, and quick resume.
Desktop tests do not establish an iPhone speedup or a launch-time guarantee.

Incremental fetching of individual seasons is a separate follow-up: an eligible
show currently still receives a full refresh. Also, the initial library snapshot
still loads its episode bundles; persisted summary-only startup is not included.
