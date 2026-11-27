# AnonymoKe Google Play setup

Use this guide to finish the account settings and signing steps that require your access. The backend provides public legal pages and a browser deletion flow. The Android project requires your release keystore before it will produce a release build.

## Public links for Play Console

After the backend deployment succeeds, use these exact links:

| Play Console field | Link |
| --- | --- |
| Privacy policy | https://api.anonymoke.co.ke/privacy-policy/ |
| Account deletion web link | https://api.anonymoke.co.ke/delete-account/ |
| Terms, where requested | https://api.anonymoke.co.ke/terms/ |

Open the links in a private browser window without signing in. They must load through HTTPS. The privacy policy and terms use the text already bundled with the app. The deletion page works without the app installed.

In Play Console, set the privacy policy under the app content/privacy policy section. In the Data safety form, declare that users can create accounts and provide the deletion web link. Keep the in-app path enabled: Profile → Delete account and purge data. Console labels can change; search for Privacy policy or Data safety if the navigation differs.

The worker normally picks up requests within a minute and sends a separate, single-use confirmation link to the account email. The link expires after 10 minutes. Opening an email or previewing its link cannot delete an account: the browser requires an explicit confirmation POST. After confirmation, the account is disabled, sessions are revoked, and the worker retries storage cleanup until the purge succeeds. Minimal completion audit and financial records are retained separately as described by the policy. This is permanent deletion, unlike Pause profile.

## Railway and Resend

The deployment adds its database migration automatically through the existing migration command. Keep the API and Celery services on the same backend revision. The worker must consume the `default` queue, and one Celery Beat scheduler must run. The existing worker command already includes both. Do not add another Beat scheduler when scaling workers.

The optional setting `PUBLIC_BASE_URL` defaults to `https://api.anonymoke.co.ke`. For another environment, set it to that environment's public HTTPS origin, with no path. This controls links in deletion emails. It must never point to localhost in production.

The existing `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, database, Redis, encryption key, and R2 credentials are reused. No additional paid messaging API is required. If you have explicitly set `EMAIL_PRIVACY_URL` or `EMAIL_TERMS_URL`, update them to the public links above; otherwise their new defaults already use those links.

Domain verification in Resend enables sending. It does not automatically create an inbox. Set up monitored inbound mailboxes or forwarding for the contacts in your supplied policy and terms: `privacy@anonymoke.co.ke`, `support@anonymoke.co.ke`, and `legal@anonymoke.co.ke`. Set `RESEND_REPLY_TO_EMAIL` only to an address you can receive and monitor.

For a real-world deletion check, create an account you control solely for testing. Request deletion in a private browser, check spam if necessary, open the email, and explicitly confirm. Verify that the account cannot sign in and that the purge finishes. Do not use your main account for this test.

If cleanup is delayed, inspect the worker logs for `web_erasure_attempt_deferred`. Check R2 access and worker availability. Confirmed jobs remain in the database and are retried every minute when due, with backoff after failures. Email challenges and completed web job rows are cleaned up after one day; the minimal data-subject request audit remains. Never paste a confirmation token, signed media URL, or a Resend response into public logs.

## Review your supplied legal text

The implementation preserves the policy and terms you previously supplied. Before submitting to Play, confirm that the developer name and contact details match your Console listing. Review the claims about ODPC registration, international transfers and agreements, financial retention, banned-account identifiers, encryption guarantees, screenshot restrictions, identity verification, and payment options against your actual operations. Publishing a policy does not establish those organizational arrangements.

The supplied text mentions optional providers/features and app-store payments. Your current checkout uses M-Pesa for digital premium features and boosts. Google Play normally requires Play Billing for digital purchases unless an applicable exception or authorized program applies. Resolve the purchase approach for the Play-distributed app before submitting it for review. The existing checkout was not changed by this work.

Complete Data safety declarations from the actual app behavior, including profile and matching data, location, photos, audio, chats, identity verification where enabled, purchase information, safety reports, and Firebase notification identifiers. Keep the form, bundled policy, and public policy consistent. If policy wording changes, update both repositories and the legal version used by the consent screens.

## Create or reuse your upload keystore

If this app already has a Play upload key, use that key. Do not generate a replacement for an app already configured in Play Console. Otherwise, run these commands directly in Windows CMD:

```bat
mkdir "%USERPROFILE%\AnonymoKe-keys"
keytool -genkeypair -v -keystore "%USERPROFILE%\AnonymoKe-keys\anonymoke-upload.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Enter the passwords interactively and keep them in your password manager. Do not paste passwords into chat or commit them to Git. Keep a secure backup of the keystore separately from your computer. For a PKCS12 keystore, use the same key password and store password.

Copy `android/key.properties.example` to `android/key.properties`. Edit the new file:

```properties
storeFile=C:/Users/PC/AnonymoKe-keys/anonymoke-upload.jks
storePassword=YOUR_ACTUAL_STORE_PASSWORD
keyAlias=upload
keyPassword=YOUR_ACTUAL_KEY_PASSWORD
```

Use forward slashes in the Windows file path. Replace the example values with your actual values; keep `key.properties` local. Keystores and this configuration file are already ignored by Git. Release builds now fail with a clear setup error if signing is missing, instead of using the debug key. Debug builds still use the normal debug configuration.

If existing testers installed a debug-signed APK, Android cannot update it in place with an APK signed by a different key. They may need to uninstall that old APK once and sign in again after installing the new one. Uninstalling does not delete their server account.

If a build reports that Android Studio's `jbr/lib/jvm.cfg` is missing, its bundled Java installation is incomplete. This machine also has a JDK at `C:/Users/PC/AppData/Local/Programs/Eclipse Adoptium/jdk-17.0.19.10-hotspot`. If Flutter selects the incomplete installation, point it to the working JDK:

```bat
flutter config --jdk-dir="C:/Users/PC/AppData/Local/Programs/Eclipse Adoptium/jdk-17.0.19.10-hotspot"
flutter doctor -v
```

## Enable Play App Signing and register certificates

When creating the first Play release, enroll in Play App Signing. You sign the AAB with your upload key. Google signs the APK delivered to testers using the app signing key. These are normally different certificates.

1. In Play Console, open App integrity/App signing and locate the **app signing certificate**.
2. Copy its SHA-1 and SHA-256 fingerprints.
3. In Firebase project `anonymoke-e038b`, open Project settings → your Android app `co.anonymoke.anonymoke` and add those fingerprints. Keep existing fingerprints used for local/Firebase testing.
4. Download the updated `google-services.json` to `android/app/google-services.json` if Firebase configuration changed.
5. If Google sign-in fails in the Play-installed build, check that the matching Android OAuth client exists for this package and Play certificate in the same Google Cloud project. Keep the existing Web OAuth client ID as the server client ID; never put a Web client secret in the app.
6. For HTTPS magic links, add the Play app signing certificate's SHA-256 fingerprint to the backend `ANDROID_APP_LINK_SHA256_FINGERPRINTS` setting. Preserve other trusted release fingerprints using the setting's comma-separated format. Check `https://api.anonymoke.co.ke/.well-known/assetlinks.json` afterward.

For an APK built locally, its certificate is your local release keystore certificate. Register that certificate too if you distribute those APKs through Firebase App Distribution. You can display its fingerprints with:

```bat
keytool -list -v -keystore "%USERPROFILE%\AnonymoKe-keys\anonymoke-upload.jks" -alias upload
```

## Build an obfuscated Play bundle

Choose a build number greater than the highest one already uploaded to Play. The example below uses 17; change it if needed. Use a new symbol directory for each released version and build number.

```bat
cd /d C:\Users\PC\Desktop\AnonymoKE-mobile
set ANONYMOKE_BUILD_NUMBER=17
flutter pub get
flutter build appbundle --release --build-number=%ANONYMOKE_BUILD_NUMBER% --obfuscate --split-debug-info=artifacts/symbols/1.0.0-%ANONYMOKE_BUILD_NUMBER%
```

The AAB is `build\app\outputs\bundle\release\app-release.aab`. Upload it to your chosen internal or closed testing track and add your testers. These commands omit `DEMO_MODE`, so this is the backend-connected build.

For direct APK testing, use:

```bat
flutter build apk --release --build-number=%ANONYMOKE_BUILD_NUMBER% --obfuscate --split-debug-info=artifacts/symbols/1.0.0-%ANONYMOKE_BUILD_NUMBER%
```

The APK is `build\app\outputs\flutter-apk\app-release.apk`. Archive the matching `artifacts\symbols\1.0.0-<build-number>` directory securely with the release. It is ignored by Git. Those Dart symbols are needed to interpret obfuscated Dart crash stacks. Retain Android/R8 mapping files too if generated; they serve a different purpose. Obfuscation makes code harder to read; it does not turn embedded API credentials into secrets.

When debugging a Dart stack trace from a release, use the symbol file matching its architecture and build, for example:

```bat
flutter symbolize -i crash.txt -d artifacts/symbols/1.0.0-17/app.android-arm64.symbols
```

## Check the installed Play build

Sign in through Google and email. Open a magic link from the mail app. Confirm that notifications are allowed and the device token reaches the backend. Use a second test account you control to exercise a Like, a Match, and a message notification. Verify that tapping the notification opens the intended destination.

On Profile, leave the tab open across background refreshes and confirm the photo remains steady. Replace/remove a photo and switch accounts to verify that the previous image is cleared. Certificate pinning has not been added; the app continues to use normal HTTPS certificate validation.

## Official references

- [Google Play user data policy](https://support.google.com/googleplay/android-developer/answer/10144311)
- [Google Play account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111)
- [Google Play payments policy](https://support.google.com/googleplay/android-developer/answer/9858738)
- [Android app signing](https://developer.android.com/studio/publish/app-signing)
- [Flutter Android release configuration](https://docs.flutter.dev/deployment/android)
- [Flutter obfuscation and symbol files](https://docs.flutter.dev/deployment/obfuscate)
