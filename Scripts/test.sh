#!/bin/bash
# XCTest không có trong Command Line Tools; swift-testing thì có, nhưng nằm
# ngoài đường dẫn framework mặc định của SwiftPM.
set -euo pipefail
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
cd "$(dirname "$0")/.."
exec swift test --build-system native \
  -Xswiftc -F -Xswiftc "$FW" \
  -Xlinker -F -Xlinker "$FW" "$@"
