# AnonymoKE mobile

Privacy-first anonymous discovery for Kenya

## Backend connection

The app is connected to the Django API in `C:\Users\PC\Desktop\AnonimoBackend`.

The default API base URL is `https://api.anonymoke.co.ke/api/v1`. It can be
overridden with `API_BASE_URL` at build/run time.

For an Android emulator using the local Django server:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

For a physical device connecting to a local server, use the computer's LAN
address instead.

Connected flows:

- Email magic-link request and verification.
- Secure JWT storage, refresh-token rotation, logout, and session restoration.
- Native Google sign-in on Android/iOS and Apple sign-in on iOS, using Django sessions.
- Email-link handoff, resend cooldown and automatic verification with app_links.
- Onboarding consent records, profile updates, and matching preferences.
- Discovery cards and swipe submission.

Public OAuth client IDs are bundled with the app. Server secrets belong in Railway.

## Authentication configuration

Google's Web/server client ID is included as the default `GOOGLE_WEB_CLIENT_ID`
and as a type-3 OAuth entry in Android's `google-services.json`. Override it with
a Flutter build definition when using another Google Cloud environment. iOS also
requires its own `GOOGLE_IOS_CLIENT_ID` and registered callback scheme.

Set this matching audience on Railway:

```env
GOOGLE_OIDC_CLIENT_ID=441811643862-eekavq3aeaa7nbigi5omagv354a482h0.apps.googleusercontent.com
```

Register the Android signing fingerprints in the same Google Cloud project.
The current native ID-token flow does not use an OAuth client secret or a web
redirect endpoint.
Native Apple sign-in requires the iOS App ID capability/provisioning profile and
the matching Django `APPLE_BUNDLE_ID`. Resend requires a verified sender and
`RESEND_API_KEY` on the backend. Unconfigured delivery produces a readable error.

Production sign-in emails use
`https://api.anonymoke.co.ke/auth/magic-link#token=...`. The fragment keeps tokens
out of HTTP access logs. Android verified App Links are registered for the API
host, and the backend publishes the certificate association. Install a new APK
for this native association to take effect. Existing APKs use the public HTTPS
page's **Open AnonymoKE** action and their existing custom callback.

The parser's `AUTH_LINK_HOST` defaults to `api.anonymoke.co.ke`. Additional hosts
require matching native/domain association; the Dart definition alone does not
register them. iOS retains its custom callback until Apple Universal Link
provisioning is completed. See the backend's `docs/authentication-screen.md` for
the complete handoff configuration and physical-device checks.
No token-paste UI or password field is used. Preview without an account remains
available only in Demo builds.

## Onboarding policy documents

The supplied Terms of Use and Privacy Policy are bundled under `assets/legal/`
and can be read offline from sign-in, onboarding Step 5, and Profile's Privacy
and consents area in both live and Demo builds. The reader has selectable text,
section navigation, the supplied effective dates, and the existing dark theme.
Viewing a document leaves consent unchecked.

The bundled revision is `2026-11-16`; onboarding, Profile and Discover use the
same configured revision for new consent records. Existing acceptance history
keeps its original version. No legal URL definitions are needed for the bundled
reader. `TERMS_URL` and `PRIVACY_POLICY_URL` may still override the defaults with
published HTTPS documents; set `CONSENT_VERSION` to their displayed revision.
A version override that conflicts with a bundled document blocks live completion.
Every privacy choice starts unchecked, and voice remains optional. Demo completion
validates the same local steps and makes no consent/profile API calls.

Bundled assets do not publish public web pages or configure the email footer's
HTTPS policy URLs.

## Live Discover verification

The Demo build uses sample cards. To test the live feed against
`https://api.anonymoke.co.ke/api/v1`, disable Demo mode:

```cmd
flutter pub get
flutter build apk --release --dart-define=DEMO_MODE=false
```

Deploy the backend changes and apply its migrations first. Discover requests
foreground location after consent, saves age/distance preferences, retains failed
swipes for retry, displays mutual matches, and refills the feed after each batch.
The undo button restores the latest pass for Premium accounts. Boosts must be
purchased before a separate 30-minute activation; the server enforces consumption
and expiry. Profile details and voice playback request fresh eligibility-checked
media URLs. Original photos are never requested by Discover.

Focused client regressions: `flutter test test/discover_live_test.dart`.

## Live Matches

Matches uses server previews, reveal states, unread counts, signed pagination and
Premium-gated nearby likes. The inbox refreshes every 20 seconds; visible chat
refreshes every five seconds and pauses in the background. Failed sends preserve
the draft and retry identifier. Request, accept, decline and withdraw reveal,
report, block and unmatch are connected to the API. Original photos are fetched
only from the protected revealed-profile endpoint.

Apply backend migration `chat.0002_reliable_messages` and run the Celery worker
with its `moderation` queue plus Celery beat. Messages await moderation before
recipient delivery. FCM taps open the specific conversation after sign-in.
Device push delivery needs the Firebase Admin credentials configured on Railway;
foreground refresh works without them.

Focused client regressions: `flutter test test/matches_live_test.dart`.

## Firebase App Distribution

Build a test APK using the default production API URL:

```cmd
flutter pub get
flutter build apk --release --dart-define=DEMO_MODE=false
```

Upload the generated APK after adding the Android app to Firebase:

```powershell
firebase appdistribution:distribute .\build\app\outputs\flutter-apk\app-release.apk `
  --app YOUR_FIREBASE_ANDROID_APP_ID `
  --groups internal-testers `
  --release-notes "Initial backend-connected test build"
```

The Firebase Android app must use package name `co.anonymoke.anonymoke`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
# AnonymoKe2004-mobile
# AnonymoKe2004 mobile new
