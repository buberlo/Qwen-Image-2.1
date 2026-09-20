#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/checks
swiftc -swift-version 5 -parse-as-library App/Core/*.swift Tests/QwenCoreTests/CoreTests.swift -o build/checks/core-checks
build/checks/core-checks
swiftc -frontend -parse App/*.swift
python3 Scripts/check-project.py
