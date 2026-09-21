# Physical-device acceptance

Target: standard iPhone 16, iOS 27. Use a signed Release build for measured runs. Keep the phone cool and foregrounded; record whether charging and whether a debugger is attached. A simulator run does not count.

## Deployment record — 2026-09-21

Signed Release app installed successfully over Wi-Fi on the paired iPhone 16 running iOS 27. `devicectl` confirmed launch; a subsequent process listing showed QwenOffline running (PID 14271). The user subsequently reported model download completion. Physical-device inference acceptance has not passed.

The workspace is managed by a file provider, which reapplied FinderInfo metadata to the built app and prevented Xcode code signing. Deployment used a temporary copy outside the synced workspace (`ditto --norsrc --noextattr`), signed with the Xcode-selected development identity and generated entitlements. `codesign --verify --deep --strict` passed before installation. For future signed builds, use DerivedData outside the synced workspace.

## Build 3 download recovery

The original personal installation was updated in place to build 3 and relaunched. Its approximately 3.91 GiB diffusion `.partial` file was still present after the update. The display name is now Pocket Canvas; this does not change its existing container.

- Resume model installation without removing the app or the saved model files.
- Confirm the first component passes checksum verification, is renamed from `.partial`, and the encoder download begins.
- Confirm all four files install and verify, with no iOS termination during either initial verification or verification after relaunch.
- Observe physical memory during verification; compare stages rather than treating the download byte counter as RAM usage. Retain relevant Jetsam records privately.
- The 5 GiB desktop regression guards against checksum buffer accumulation. Record phone measurements separately; it is not a substitute for a completed phone installation.

## Build 4 inference retry

Two build 3 generation attempts crashed during prompt encoding after a failed Metal allocation. Build 4 adds allocation-failure handling and lowers the managed-buffer budget to 1.5 GiB. It was installed and launched in place, retaining the model files.

- Let startup verification finish, then try one text generation. Record whether it completes, reports an error, or terminates.
- If an error is shown, verify cleanup and retry without restarting the app. Collect diagnostics and the native console before attributing all failures to the same cause.
- If generation completes, inspect prompt-following and proceed to a reference-photo edit and the full suite below.
- A successful launch or completed download does not establish inference feasibility.

## Build and installation

- Build with full Xcode / iOS 27 SDK; fix any device-specific build errors before testing.
- Pair the iOS 27 phone wirelessly: same Wi-Fi network, Xcode → Open Developer Tool → Device Hub → + → Pair Nearby Device → iPhone; follow Developer Mode and Trust prompts. Select the user's existing developer team and verify installation on the paired phone.
- Start the model download. Pause mid-file, kill/relaunch, and resume. Previously saved bytes must be reused.
- Repeat with a network disconnect and restore connectivity. A retry must preserve partial progress.
- Verify the app declines installation when storage cannot cover remaining bytes plus installation overhead.
- Replace a test copy of one installed file with same-size corrupted bytes using Xcode's app container tools. Relaunch: checksum verification must fail, generation remain disabled, and redownload restore readiness. Never alter the source model files.

## Six output runs plus cancellation/restart

1. In Create, select a photo with a clearly recognizable subject. Confirm orientation and letterboxing.
2. Start Device test. It generates three red-teapot images (seeds 42–44), then three watercolor edits of the selected photo (seeds 45–47).
3. It starts another generation, requests cancellation after step two, then generates a blue cup (seed 49) to test restart. Seven successful images plus one cancelled run are expected.
4. Inspect all images. Teapot images must follow the prompt; each edit must visibly change to watercolor while retaining the subject/composition; the restart image must follow its prompt. Completion alone is not quality acceptance.
5. Export diagnostics. Each run reports device, OS, runtime/model pin, elapsed time, sampled footprint peak, minimum available memory, thermal states, and output ID. Sampling can miss brief peaks; inspect Instruments/Xcode memory tools as well.
6. Check the device logs for jetsam/termination events. A recovered `interrupted` record reports only that the app exited; it does not prove why.
7. Repeat after disabling Wi-Fi and cellular. No model verification or inference operation may require connectivity once installed.

Pass only after three consecutive generations and three consecutive edits complete without termination, cancellation stops work, restart succeeds, visual checks pass, and offline behavior is verified. The UI intentionally does not assert a quality pass automatically.

## App behavior

- Empty prompt cannot generate. A second job cannot start while one is running.
- Cancel during loading, prompt encoding, sampling and decoding; confirm no new generation starts before cleanup. Loading may finish before cancellation takes effect.
- Background the app during a run; expiration requests cancellation. Relaunch after an OS termination must retain completed history and mark the incomplete run as interrupted.
- Memory warnings / critically low memory / critical thermal state must request cancellation. Serious thermal state blocks starting a new user job. Record performance under repeated workloads.
- Open each output, reuse it as a reference, save to Photos, deny Photos permission and retry, and share its PNG.
- Relaunch: history and metadata persist. Delete one entry: both metadata and PNG disappear. Remove models: history persists and generation is disabled.

If failures prevent the acceptance gate, retain the harness and exported diagnostics; document the failing stage and memory measurements. Do not replace Qwen, add a remote backend, or declare the device supported.
