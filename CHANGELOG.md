# Changelog

## 0.1.0 (4) — 2026-09-21

- Handle failed Metal buffer allocations before dereferencing the result; release shared host memory on failure. Bootstrap reproducibly applies the local patch to pinned ggml.
- Lower the managed-buffer budget from 3 GiB to 1.5 GiB; keep the exact model and quantization unchanged.
- Diagnose two build 3 prompt-encoding crashes with sampled footprints around 2.6 GB. The user reports completed model download.
- Nine core checks and the signed iOS Release build passed. Installed and launched over the personal app with model files retained. Successful generation and editing still require physical-device validation.

## 0.1.0 (3) — 2026-09-21

### Fixed

- Release Foundation checksum read buffers after each 4 MiB chunk. Previously they accumulated during verification of multi-gigabyte files. Phone Jetsam logs reported `per-process-limit` terminations around the end of the first model download.
- Preserve the existing model paths and resume data when updating the personal-device app.

### Validation

- Nine core checks and signed iOS Release build passed.
- A valid 5 GiB sparse-file checksum passed with 11.4 MiB peak RSS on the development Mac; a standalone regression enforces a 128 MiB RSS limit.
- Installed and launched on the iPhone; the approximately 3.91 GiB partial download remained present.
- Full phone installation, generation, editing, and offline acceptance remain unconfirmed. Build 3 is not yet uploaded to App Store Connect.

## 0.1.0 (2) — 2026-09-21

- Added Pocket Canvas branding, an original app icon, required-reason privacy manifest, and published privacy policy.
- Archived and uploaded to App Store Connect; subsequently selected for the direct App Store submission draft.
- Contains the checksum memory bug corrected in build 3; replace it before review.

## Initial personal-device prototype

- Added SwiftUI create/edit flows, local history, Photos/share export, and a pinned Metal runtime bridge for Qwen-Image-2.1.
- Added resumable, checksummed model downloads; later added live transfer speed, received bytes, and waiting indicators.
- Installed and launched on iPhone 16 / iOS 27. No successful real-model inference was claimed.
