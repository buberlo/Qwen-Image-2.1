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
