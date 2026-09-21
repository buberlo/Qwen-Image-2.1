#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
revision=c678dfe704a2230342376b46add9c8ca736a653d
runtime=vendor/stable-diffusion.cpp
if [ ! -d "$runtime/.git" ]; then
  git clone --filter=blob:none https://github.com/leejet/stable-diffusion.cpp.git "$runtime"
  git -C "$runtime" checkout "$revision"
fi
if [ "$(git -C "$runtime" rev-parse HEAD)" != "$revision" ]; then
  echo "Runtime revision mismatch; expected $revision" >&2
  exit 1
fi
git -C "$runtime" submodule update --init ggml

# Local safety patch on the pinned ggml revision; never silently overwrite edits.
patch_file="$PWD/Native/patches/ggml-metal-allocation-failure.patch"
if git -C "$runtime/ggml" apply --reverse --check "$patch_file" 2>/dev/null; then
  : # Already applied.
else
  git -C "$runtime/ggml" apply --check "$patch_file"
  git -C "$runtime/ggml" apply "$patch_file"
fi
