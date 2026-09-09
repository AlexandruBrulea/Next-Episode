# TMDB retention and administrative shutdown

## Normal use

TMDB metadata carries its retrieval timestamp. Successful network retrieval replaces metadata; simply reading or copying cached data does not renew its timestamp. Expiry is six calendar months in UTC, clamped to the destination month's last day. Existing cache entries use their stored retrieval date. Undated legacy catalog copies are treated conservatively as expired.

Public library and cache reads enforce retention. Startup/resume and the existing 30-minute synchronization also enforce it. While the app runs, a timer checks at the next known expiry (at least hourly when that expiry is further away). Expired cache rows are deleted; library/catalog records retain only internal identity and the selection's source identifier with an unavailable-details label. A later successful fetch restores descriptions and episode information against the same internal episode slots, preserving watched marks.

The sweep covers library metadata, catalog metadata, episode/film/popular cache, and JSON embedded in migration staging/fingerprints/backups. Snapshots containing expired/revoked TMDB content become `retention_expired` and cannot be activated or rolled back; prepare a new migration. Active TVmaze records are not purged. `watched`, library membership/added dates, user history, preferences and logical identity mappings are preserved.

Scheduled TMDB alerts never target a time beyond the metadata's expiry. Purges refresh notification scheduling and clear Flutter's in-memory image cache. The app has no dedicated persistent poster-download cache. SQLite secure deletion is enabled for metadata cleanup; this is not a guarantee about OS snapshots, backups or forensic storage recovery.

## Administrative disable

The normal local build setting is:

```dotenv
TMDB_CONTENT_ENABLED=true
```

Setting it to `false` and rebuilding with `--dart-define-from-file=.env` blocks TMDB and purges its metadata on startup. A build configured false cannot be re-enabled by a remote manifest. Changing an env file does not change already installed apps.

For existing installations configured with `CONTENT_CONFIG_URL`, publish a valid global HTTPS manifest with a strictly newer policy `generation`:

```json
{
  "provider": "tmdb",
  "deploymentId": "tmdb-disabled-2026-09",
  "generation": 2,
  "phase": "committed",
  "tmdbContentEnabled": false
}
```

Use a generation greater than every previous policy revision; 2 is only an example. The flag is applied independently of whether catalog migration succeeds. Prepared manifests do not disable anything. Omission leaves the last policy unchanged. The accepted flag/revision is persisted: failed requests and older manifests cannot undo it. Explicit re-enabling needs a newer revision with `true` and a build whose local switch permits it. Re-enable only when authorized to use TMDB again.

An ordinary timeout, 401/403 or service failure does **not** itself issue a purge command. Network requests and persistence are guarded against disabled TMDB, including responses arriving after disable. Offline fallbacks recheck eligibility before returning content.

No configuration service was deployed by this change. Devices must reconnect/run to receive remote policy; a stopped process cannot execute deletion. Operating-system backups are outside the app's deletion control. Minimal cross-provider ID mappings are retained for the user's progress and re-linking; confirm their treatment with TMDB if a termination notice requires removal of all identifiers as well as descriptive content. This mechanism is not a declaration that those external constraints have been resolved.

## Validation

`test/tmdb_retention_test.dart` exercises month boundaries, expiry, removed-title caches, failed refreshes, progress rehydration, monotonic administrative disable and migration snapshot invalidation. Run it alongside persistence and administrative migration tests before release. Device notification delivery and backup behavior require platform testing.
