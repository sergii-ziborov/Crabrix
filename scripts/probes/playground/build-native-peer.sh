#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
mkdir -p build/playground-crossclient
xcrun swiftc -O -parse-as-library \
  scripts/probes/playground/native-probe.swift \
  CrabrixShared/PlaygroundLink.swift \
  Crabrix/Projects/ProjectFilePolicy.swift \
  Crabrix/Playground/PlaygroundDocument.swift \
  Crabrix/Playground/PlaygroundCodec.swift \
  Crabrix/Playground/PlaygroundRuntimeCryptography.swift \
  Crabrix/Playground/PlaygroundRuntimePolicy.swift \
  Crabrix/Playground/PlaygroundRuntimeProtocol.swift \
  Crabrix/Playground/PlaygroundEncryption.swift \
  Crabrix/Playground/PlaygroundLiveSession.swift \
  Crabrix/Playground/PlaygroundRelayConfiguration.swift \
  -o build/playground-crossclient/native-peer
