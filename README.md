# Pocket Canvas for iPhone

Experimental research/evaluation app for **Qwen-Image-2.1**, targeting the standard iPhone 16 on iOS 27. SwiftUI UI, local Metal inference, one reference-photo edit, local history, Photos export, and resumable model installation.

**Device feasibility is not established.** The native library builds and links on Apple Silicon macOS, and the signed Release app builds with Xcode 27 / iOS 27 SDK and has been installed and launched on a physical iPhone 16 over Wi-Fi. Real image generation, timing, quality, and memory survival remain unverified. There is no remote inference or substitute model.

The app is named **Pocket Canvas**. The repository and internal Xcode target retain their original names. See [App Store submission notes](docs/APP_STORE_CONNECT.md) and the [privacy policy](docs/PRIVACY.md).

## Current status — September 21, 2026

| Area | Verified status |
| --- | --- |
| Latest source and personal-device build | 0.1.0 (3), installed and launched on iPhone 16 |
| Download crash fix | Checksum buffers now released after every 4 MiB chunk; existing partial downloads preserved |
| Large-file regression | Valid 5 GiB checksum passed with 11.4 MiB peak RSS on the development Mac |
| Full model installation and inference | Still awaiting physical-device completion and validation |
| App Store Connect | Build 2 attached to a direct App Store draft; not submitted or publicly available |

**Build 2 still contains the checksum memory bug.** Build 3 must be archived, uploaded, and selected before App Review. TestFlight distribution is not part of the current release plan.

If an older build closed near the first 4–5 GB of setup, update the same installed app and choose **Model → Download / resume model**. Do not delete the app or its model files: completed download chunks can be reused. Verification reads the saved file locally and is distinct from network downloading. Completing this regression does not establish that the image model fits in iPhone memory.

See the [changelog](CHANGELOG.md) for fixes and the [device acceptance procedure](docs/DEVICE_VALIDATION.md) for outstanding tests.

## Open and run

1. Install Xcode 27 with the iOS 27 SDK and complete its first-run setup.
2. Install build tools if needed: `brew install cmake xcodegen`.
3. Copy `Signing.xcconfig.example` to `Signing.xcconfig` if it does not exist. Open `QwenOffline.xcodeproj`, add your **existing developer account** under Xcode Settings → Apple Accounts, and select its team in Signing & Capabilities. Use a unique bundle identifier for your team. Put `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER` in the ignored `Signing.xcconfig` to preserve them when regenerating the project.
4. Pair over Wi-Fi: connect the iPhone and Mac to the same network, choose Xcode → Open Developer Tool → Device Hub → + → Pair Nearby Device → iPhone, and follow the Developer Mode / PIN / Trust instructions. iOS 27 supports first-time wireless pairing. Select the paired phone as the run destination and Run. The first native build downloads the pinned runtime and compiles its Metal backend. Model weights are **not** bundled into the executable.
5. In **Model**, explicitly start the approximately **11.06 GB** download. Keep at least another 512 MB free for installation overhead. More free storage is advisable for history and normal device operation. Leave the app foregrounded; pause/resume is supported.
6. Add a photo in **Create**, then run **Device test**. Repeat with Wi-Fi and cellular disabled after model verification. Review results in History and export diagnostics.

`project.yml` is the source of truth for the Xcode project. Run `xcodegen generate` after changing project configuration. The generated project is included for convenient opening. No team identifier or credentials are committed.

## What is implemented

- 512 × 512 RGB generation and one reference image with an edit prompt; 40 Euler steps, guidance 6, runtime-selected model schedule.
- Native bridge to pinned `stable-diffusion.cpp` revision `c678dfe704a2230342376b46add9c8ca736a653d`. Metal execution with disk-backed parameters, mmap, segmented execution, prefetch disabled, tiled VAE decoding, and a 3 GiB managed-buffer budget.
- The managed budget is **not** an iOS process-memory limit. CPU offload is not used as a substitute for reducing residency in unified memory. Actual resident memory and iOS termination behavior must be measured.
- Single-job serial execution, cross-thread cancellation, unloading after each result/failure, and invalidation of stale progress callbacks.
- Manifest-pinned 4-bit diffusion and encoder files, F16 vision projection, and the matching BF16 VAE. File revisions, byte sizes, and SHA-256 digests are in `App/Resources/Models.json`.
- Downloads show live transfer speed, received bytes, and waiting time. Chunks are validated using HTTP ranges and saved to disk. Relaunch resumes from the partial file length; full-file SHA-256 verification precedes installation. All files are reverified locally when the app launches. Only explicit model installation accesses the network.
- Orientation-correct thumbnail decoding; photos are fitted onto a white 512-square canvas without stretching.
- Persistent image/prompt/seed/settings history, reuse as input, deletion, Photos save and share.
- Sampled physical footprint, available process memory, elapsed time, thermal states, durable run heartbeat, model/runtime/device metadata, and exported JSON. Interrupted runs are marked as unknown termination, not automatically attributed to an out-of-memory event.

## Checks available without Xcode

```sh
./Scripts/check.sh
./Scripts/check-checksum-memory.sh
./Scripts/build-native.sh macosx
ctest --test-dir build/macosx --output-on-failure
```

`check.sh` compiles and runs nine Foundation/CryptoKit checks, parses the app Swift sources, and verifies resource membership. The test runner deliberately does not require XCTest, which is absent from Command Line Tools. Parsing is **not** an iOS typecheck or UI test.

`check-checksum-memory.sh` verifies a 5 GiB sparse file in a separate process and enforces a peak RSS below 128 MiB. It uses local zero-filled test data, not downloaded model weights. Its memory measurements are from macOS, not the iPhone.

The native smoke test verifies linking, early cancellation, cleanup, and memory telemetry without downloading weights. macOS native verification is a build check, not a Mac inference fallback.

The unsigned device build has passed. To reproduce it:

```sh
./Scripts/device-build.sh
```

Then build/run on the actual phone with your signing team. Simulator results cannot establish iPhone memory feasibility.

## Known limits

- No successful real-model iPhone inference has been recorded. Do not treat this as a proven usable image generator yet.
- Upstream model loading has no interruptible load API. Cancellation during loading is applied when loading returns; cancellation during encoding is also reasserted at the next sampler progress boundary. Never destroy an in-flight native context.
- Background expiration requests cancellation, but iOS can suspend or terminate the app before native cleanup completes. The app does not advertise background generation.
- The 512-square starting resolution, tiled VAE behavior, Metal operator coverage, and actual quality need device validation. No automatic reduction in model or precision is hidden behind failures.
- The device suite checks six completions, cancellation at step two, and successful restart. Prompt-following and preservation of the edited subject require human inspection. Export the run report and correlate its `resultID` values with History.
- No multi-reference editing, mask painting, transparent output controls, or upscaling in this version. App Store Connect packaging is prepared for evaluation; this is not a validated consumer release.

Apple documents wireless pairing in [Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub).

See [device acceptance procedure](docs/DEVICE_VALIDATION.md) and [current findings](docs/FEASIBILITY.md). Model and runtime license texts are bundled in the app's Model → Licenses screen.
