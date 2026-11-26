# Tab UX refinements

The existing brand palette and card designs are retained. Matches and Safety
keep their title/controls pinned above the scroll view; Profile keeps its
avatar, alias and edit control pinned. Blocked people/reports uses the same
header behavior. Demo mode follows the same tab structure.

Profile pausing works from the entire row and the switch. The client immediately
shows the intended state, prevents duplicate writes, rolls back a failed save,
and ignores profile reads that began before the visibility change. The API's
`is_discoverable` field remains authoritative. Existing matches and Safety stay
available while the profile is hidden from Discover.

Initial content loading uses reusable shimmer shapes on Discover, Matches,
Safety, Profile, Boost, chat and blocked/report pages. Loaded content stays in
place during background refreshes. Shimmer honors reduced-motion settings,
stops offstage and disposes its ticker when replaced by real content.

Every route has an opaque background. Android uses a transition that begins
after the back gesture commits, so cancelling a swipe keeps the page in place.
Other platforms retain the SDK's native transitions. Framework tests exercise
gesture start, progress, cancellation and a single committed pop. Final device
behavior should be checked on an Android phone after rebuilding the APK.

Trusted contacts use the existing in-app invitation flow:

1. Save their name and optionally a phone number.
2. Generate a single-use invite code and share it yourself.
3. They sign in to AnonymoKE and enter the code in Safety within 24 hours.
4. After linking, create a date plan. The contact can receive and acknowledge
   in-app date-plan and panic alerts.

A phone number alone does not send an invitation or enable SMS/WhatsApp alerts.
Push delivery requires a registered device and notification permission; the
in-app inbox remains the stored record. The form now explains the next linking
step and the delivery channel.

Discovery previews now use a 48px intermediate image with a 3.5px blur, scaled
to the existing 512px derivative. The onboarding preview uses the same blur
parameters. Approved originals still stay private and the reveal authorization
flow is unchanged. Existing approved derivatives can be regenerated on the
backend; no original image is downloaded into Discover for a client-side blur.
