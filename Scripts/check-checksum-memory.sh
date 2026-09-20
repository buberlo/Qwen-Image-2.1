#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/checks
swiftc -O App/Core/ModelManifest.swift Tests/Memory/ChecksumMemory.swift -o build/checks/checksum-memory
/usr/bin/time -l build/checks/checksum-memory 2> build/checks/checksum-memory.metrics
python3 - <<'PY'
import re
from pathlib import Path
metrics = Path('build/checks/checksum-memory.metrics').read_text()
peak = int(re.search(r'(\d+)\s+maximum resident set size', metrics).group(1))
assert peak < 128 * 1024 * 1024, f'Checksum memory grew beyond bound: {peak} bytes'
print(f'PASS: peak RSS {peak / 1024 / 1024:.1f} MiB (limit 128 MiB)')
PY
