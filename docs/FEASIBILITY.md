# Current findings — 2026-09-21

## Implemented and checked

- Empty initial workspace; created a native SwiftUI iPhone project and a real C/C++ runtime bridge.
- Runtime pinned to `c678dfe704a2230342376b46add9c8ca736a653d`, with its pinned ggml submodule.
- Metal-enabled runtime and bridge compiled on arm64 macOS using Command Line Tools; native CTest smoke passed.
- Foundation/CryptoKit core compiled. Nine executable core checks passed, covering manifest validation, same-size corruption, offline installation verification, model removal, corrupt installed files, persisted history, resumed ranges, invalid HTTP responses, and cancellation.
- Swift app sources passed iOS 27 typechecking, and the complete unsigned arm64 iOS app built and linked successfully with Xcode 27.0 (27A266a). Bundle manifest/license membership and permission description checked.
- Both the CMake-linked and combined-archive native smoke executables passed on macOS. All four pinned model URLs returned valid HTTP 206 range responses for a small probe.
- The selected weight files total **11,059,819,128 bytes**. This is download/storage size, not measured inference memory.

## Runtime approach

The 7B diffusion model is only part of the pipeline. The runtime also requires Qwen3-VL-8B text encoding; editing uses its vision projection; decoding requires the Qwen-Image-2.1-specific VAE. All four components are pinned.

The native wrapper explicitly chooses disk-backed parameter storage, mmap, segmented execution, and disables prefetch. This avoids assuming that moving GPU weights to CPU RAM solves unified-memory pressure. A 3 GiB managed-buffer budget leaves headroom in principle but cannot cap process footprint; actual graph/workspace residency, iOS memory allowance, and speed remain unknown. VAE tiles start at 256 pixels.

Cancellation is cooperative. Upstream offers generation cancellation but no cancellable model-loading API. The wrapper retains native resources until work finishes, reapplies cancellation at progress boundaries, and releases the context before returning to Swift.

## Device deployment and remaining validation

- A signed Release build was installed and launched successfully on a physical iPhone 16 running iOS 27 over Wi-Fi. Signing configuration remains in the ignored local `Signing.xcconfig`.
- The latest update adds live download speed, received bytes, and a waiting indicator. It passed the nine core checks and signed Release build, and was installed and launched on the phone.
- No real-model output, quality assessment, performance timing, or iPhone memory feasibility result is claimed.
- Real-device download interruption, insufficient-storage, thermal/background behavior, Photos export, and airplane-mode acceptance still require the procedure in DEVICE_VALIDATION.md.

The implementation is an experimental prototype and harness, **not a completed feasibility proof**. If actual-device tests fail, preserve measurements and report the limits instead of substituting a model or service.
