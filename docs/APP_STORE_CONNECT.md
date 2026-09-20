# Pocket Canvas App Store submission

Target: a free, non-commercial research/evaluation app submitted directly to App Review. No TestFlight tester distribution is planned. The model's research license does not authorize general commercial use merely because an app is free. No successful real-model iPhone inference has been confirmed. Complete DEVICE_VALIDATION.md before a consumer release.

- Display name: Pocket Canvas
- Bundle identifier: com.buberlo.pocketcanvas
- App Store Connect app: https://appstoreconnect.apple.com/apps/6814293165
- SKU: pocket-canvas-ios
- Primary language: English (US)
- Current source/personal-device build: 0.1.0 (3)
- Uploaded build selected in the App Store draft: 0.1.0 (2), superseded by the checksum fix; replace before review
- Repository: https://github.com/buberlo/Qwen-Image-2.1
- Privacy policy source: docs/PRIVACY.md

The original personal-device build uses a different bundle identifier. Installing the App Store build creates a separate app container and does not inherit that build's model downloads or history. Do not remove the original app while completing device validation.

## Product scope (not final store copy)

Pocket Canvas is a research and evaluation app exploring whether Qwen-Image-2.1 can generate and edit images entirely on an iPhone. It includes a native Metal runtime, one reference-photo workflow, local history, and resumable model installation. Approximately 11.06 GB of model files must be downloaded before testing. Keep the app open during download and inference.

Inference feasibility, memory use, output quality, and duration remain unverified on the target iPhone 16. The app may fail to complete generation. This is a feasibility test, not a production image generator. No remote inference or substitute model is used.

## What to test

Verify download speed/progress, pause/resume, checksum validation, model setup, then 512-square generation and one-photo editing. Run the Device test suite. Record failures, temperature, duration, and diagnostics. Verify airplane-mode generation after installation. Do not submit private photos or prompts in public feedback.

## Packaging

An opaque 1024-square original icon is included. PrivacyInfo.xcprivacy declares file metadata for app-container files, uptime for elapsed-time measurement, and disk-space checks before model installation. It declares no tracking or developer data collection. The source policy separately describes third-party model downloads and user-directed exports; confirm App Store Connect disclosures against Apple's current definitions before publishing.

Use DerivedData and archives outside synced Documents folders. Signing details remain in ignored Signing.xcconfig. Pass PRODUCT_BUNDLE_IDENTIFIER=com.buberlo.pocketcanvas when archiving for App Store Connect so the personal-device configuration remains intact.

## Upload record — 2026-09-21

App Store Connect app 6814293165 was created. Xcode archive and upload succeeded for 0.1.0 (2); Apple reported the uploaded package was processing. Beta description, repository URL, and privacy policy URL were saved in TestFlight. This is not an App Store release or a completed physical-device feasibility test.

## Direct submission draft and remaining work

The release route was changed to direct App Store submission. Version 0.1.0 has build 2 selected; export-compliance questions were completed based on the app using Apple-provided networking/cryptography. Support and repository URLs, copyright, no-login requirement, and factual review notes were saved. The app remains in preparation for submission. No TestFlight invitations were sent and no App Review submission was made.

Build 3 fixes a confirmed checksum-memory problem and is installed on the original personal-device bundle ID. It has **not** been uploaded to App Store Connect. Do not submit the currently selected build 2.

Before submission:

1. Confirm complete model installation, generation, and photo editing on the physical phone, including the acceptance suite and offline operation.
2. Archive and upload build 3 or a later corrected build with `./Scripts/archive-beta.sh` (the script's historical name does not require TestFlight). Select that build in the App Store version and complete any new build questions.
3. Supply genuine app screenshots, final accurate description/keywords, App Review contact email and phone, age rating, category, store privacy disclosures, and free pricing/availability.
4. Reconcile the review notes with actual test results. Preserve the research/evaluation license scope; a zero price does not grant commercial-use rights.
5. Submit to App Review. Public availability requires Apple's approval; an upload alone is not a release.
