# Loading performance changes

Tab navigation now retains each tab's route, loaded content, deck position and
scroll state. Profile and Safety polling stops while their tab is hidden or
the app is in the background; Matches continues to refresh its unread badge.
Returning to a tab refreshes its data while preserving the existing content.
Changing account clears account-scoped providers and the image cache. Profile
mutations invalidate the retained Discover feed, including pause and consent
changes.

Discover requests profile and consent data concurrently, then checks consent
before accessing location. Matches and likes load concurrently. Profile
publishes its main data before optional premium and media-status requests finish.

Swipe saving starts alongside the card animation. Only an acknowledged swipe
advances the logical deck; failed saves bring the same card back, and retrying
retains the request's idempotency key. Rapid repeated taps cannot send duplicate
swipes. No match is announced until confirmed by the server.

The image cache reuses valid signed URLs for up to three minutes, accounts for
their actual expiry, and holds at most 64 resources. It lives in memory, is
scoped to the signed-in account and evicts its decoded images on account change.
Changed object paths and non-signature query parameters select distinct images.
Discover preloads at most the next two blurred images. Decoding uses explicit
width limits instead of full-resolution originals.

Profile uses a new optional `avatar_thumbnail_url` from the owner-only profile
endpoint. The 256px JPEG is stored privately, generated only from an approved
original, and uses expiring signed access. Older app versions can continue using
`avatar_url`. Discover never receives the private thumbnail or original.
Thumbnails are tracked and included in media/account erasure; deterministic
candidate keys cover partial upload/refresh failures.

New voice clips use 64 kbps mono AAC with fast-start container metadata, retaining
the 15-second limit, disguise choice and metadata stripping. Existing clips are
not repeatedly transcoded. Playback remains on demand, rechecks authorization,
and displays buffering feedback. Switching tabs stops voice playback.

Location sync checks device permission even when its recent-update cache is
valid. A last-known fix can avoid GPS acquisition only when it is no older than
60 seconds, has acceptable accuracy and coordinates, and is not marked as mock.
Otherwise fresh GPS is requested. Concurrent callers share one update. Account
changes/invalidation prevent a pending old GPS result from being submitted.
The backend still validates, snaps and checks all submitted locations.

Deploy the additive `profiles.0005_media_thumbnail` migration with the API and
media worker. Run `python manage.py rebuild_avatar_previews --dry-run --limit 100`
and then the same command without `--dry-run` to backfill private thumbnails for
approved photos. This preserves originals, approval and profile visibility.

Redis configuration and hosting region are unchanged. Measured database work
was already fast; these changes target mobile waits and media work. Measure
release/profile builds on actual Kenyan devices before deciding on a region move.
No APK is generated as part of this change.
