#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_sha="${CRABRIX_COURSE_SOURCE_SHA:-c38423e7503a56d6cd97e3a6c17651d5a5c33d62}"
output="${1:-migration/baseline-inventory.json}"
version="${2:-1.0.0}"
source_files=(
  Crabrix/Learn/RustCourseCatalog.swift
  Crabrix/Learn/RustLearningPath.swift
  Crabrix/Learn/RustLessonContent.swift
  Crabrix/Learn/RustLessonDepth.swift
  Crabrix/Learn/RustBasicsExpansion.swift
  Crabrix/Learn/RustAdvancedExpansion.swift
  Crabrix/Learn/AlgorithmCourseCatalog.swift
  Crabrix/Learn/AlgorithmCourseData.swift
  Crabrix/Learn/AlgorithmVerificationData.swift
  Crabrix/Learn/TermTrainDeck.swift
  Crabrix/Compiler/RustSamples.swift
  Crabrix/Compiler/RustShowcaseCatalog.swift
  Crabrix/Compiler/RustShowcaseExpansionCatalog.swift
  Crabrix/Compiler/RustVisualShowcaseCatalog.swift
  Crabrix/Compiler/RustCanvasOutput.swift
)
if ! git diff --quiet "$source_sha" -- "${source_files[@]}"; then
  echo "Curriculum sources differ from $source_sha; choose and record a new source SHA and content version." >&2
  exit 1
fi
binary="$(mktemp -t crabrix-legacy-export.XXXXXX)"
trap 'rm -f "$binary"' EXIT
swiftc -O -o "$binary" \
  migration/LegacyExportStubs.swift migration/export_legacy.swift \
  "${source_files[@]}"
"$binary" "$source_sha" "$version" "$output"
