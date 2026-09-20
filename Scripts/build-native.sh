#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
sdk="${1:-iphoneos}"
case "$sdk" in iphoneos|iphonesimulator|macosx) ;; *) echo 'Unsupported SDK' >&2; exit 1;; esac
./Scripts/bootstrap.sh
sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
args=(-DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_SYSROOT="$sdk_path" -DCMAKE_OSX_ARCHITECTURES=arm64)
if [ "$sdk" != macosx ]; then
  args+=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=27.0)
fi
cmake -S . -B "build/$sdk" "${args[@]}"
cmake --build "build/$sdk" --config Release -j 4
python3 - "$sdk" <<'PY'
import pathlib,subprocess,sys
root=pathlib.Path('build')/sys.argv[1]
archives=[str(p) for p in root.rglob('*.a') if p.name != 'libQwenNative.a']
if not archives: raise SystemExit('No static libraries built')
subprocess.run(['xcrun','libtool','-static','-o',str(root/'libQwenNative.a'),*archives],check=True)
PY
