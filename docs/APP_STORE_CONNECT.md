# Pocket Canvas beta distribution

Scope: free, non-commercial research/evaluation beta. The model's research license does not authorize general commercial use merely because an app is free. No successful real-model iPhone inference has been confirmed. Complete DEVICE_VALIDATION.md before a consumer release.

- Display name: Pocket Canvas
- Bundle identifier: com.buberlo.pocketcanvas
- App Store Connect app: https://appstoreconnect.apple.com/apps/6814293165
- SKU: pocket-canvas-ios
- Primary language: English (US)
- Version/build: 0.1.0 (2)
- Repository: https://github.com/buberlo/Qwen-Image-2.1
- Privacy policy source: docs/PRIVACY.md

The original personal-device build uses a different bundle identifier. Installing the beta creates a separate app container and does not inherit that build's model downloads or history. Do not remove the original app while evaluating the beta.

## Beta description

Pocket Canvas is a research and evaluation beta exploring whether Qwen-Image-2.1 can generate and edit images entirely on an iPhone. It includes a native Metal runtime, one reference-photo workflow, local history, and resumable model installation. Approximately 11.06 GB of model files must be downloaded before testing. Keep the app open during download and inference.

Inference feasibility, memory use, output quality, and duration remain unverified on the target iPhone 16. The app may fail to complete generation. This is a feasibility test, not a production image generator. No remote inference or substitute model is used.

## What to test

Verify download speed/progress, pause/resume, checksum validation, model setup, then 512-square generation and one-photo editing. Run the Device test suite. Record failures, temperature, duration, and diagnostics. Verify airplane-mode generation after installation. Do not submit private photos or prompts in public feedback.

## Packaging

An opaque 1024-square original icon is included. PrivacyInfo.xcprivacy declares file metadata for app-container files, uptime for elapsed-time measurement, and disk-space checks before model installation. It declares no tracking or developer data collection. The source policy separately describes third-party model downloads and user-directed exports; confirm App Store Connect disclosures against Apple's current definitions before publishing.

Use DerivedData and archives outside synced Documents folders. Signing details remain in ignored Signing.xcconfig. Pass PRODUCT_BUNDLE_IDENTIFIER=com.buberlo.pocketcanvas when archiving for App Store Connect so the personal-device configuration remains intact.
