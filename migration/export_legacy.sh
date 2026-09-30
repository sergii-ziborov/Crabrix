#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_sha="$(git rev-parse HEAD)"
output="${1:-migration/baseline-inventory.json}"
version="${2:-1.0.0}"
binary="$(mktemp -t crabrix-legacy-export.XXXXXX)"
trap 'rm -f "$binary"' EXIT
swiftc -O -o "$binary" \
  migration/LegacyExportStubs.swift migration/export_legacy.swift \
  Crabrix/Learn/RustCourseCatalog.swift \
  Crabrix/Learn/RustLearningPath.swift \
  Crabrix/Learn/RustLessonContent.swift \
  Crabrix/Learn/RustLessonDepth.swift \
  Crabrix/Learn/RustBasicsExpansion.swift \
  Crabrix/Learn/RustAdvancedExpansion.swift \
  Crabrix/Learn/AlgorithmCourseCatalog.swift \
  Crabrix/Learn/AlgorithmCourseData.swift \
  Crabrix/Learn/AlgorithmVerificationData.swift \
  Crabrix/Compiler/RustSamples.swift \
  Crabrix/Compiler/RustShowcaseCatalog.swift \
  Crabrix/Compiler/RustShowcaseExpansionCatalog.swift \
  Crabrix/Compiler/RustVisualShowcaseCatalog.swift \
  Crabrix/Compiler/RustCanvasOutput.swift
"$binary" "$source_sha" "$version" "$output"
