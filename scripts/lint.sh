#!/usr/bin/env bash
# Runs swift-format and SwiftLint the way CI does.
# Usage: scripts/lint.sh [--fix] [swift-format|swiftlint]
#   --fix         format the code and apply SwiftLint's automatic fixes first
#   swift-format  run only swift-format (the toolchain's `swift format`, configured in .swift-format)
#   swiftlint     run only SwiftLint (the pinned release from scripts/install-swiftlint.sh, .swiftlint.yml)
set -euo pipefail
cd "$(dirname "$0")/.."

FIX=0
TOOLS=()
for arg in "$@"; do
    case "$arg" in
        --fix) FIX=1 ;;
        swift-format | swiftlint) TOOLS+=("$arg") ;;
        *)
            echo "usage: scripts/lint.sh [--fix] [swift-format|swiftlint]" >&2
            exit 2
            ;;
    esac
done
[[ ${#TOOLS[@]} -gt 0 ]] || TOOLS=(swift-format swiftlint)

PATHS=(Package.swift Sources Tests)
status=0
for tool in "${TOOLS[@]}"; do
    case "$tool" in
        swift-format)
            echo "== swift-format $(swift format --version)"
            if [[ $FIX -eq 1 ]]; then
                swift format format --in-place --recursive --parallel "${PATHS[@]}"
            fi
            swift format lint --strict --recursive --parallel "${PATHS[@]}" || status=1
            ;;
        swiftlint)
            swiftlint="$(scripts/install-swiftlint.sh)"
            echo "== SwiftLint $("$swiftlint" version)"
            if [[ $FIX -eq 1 ]]; then
                "$swiftlint" lint --fix --quiet
            fi
            "$swiftlint" lint --strict --quiet || status=1
            ;;
    esac
done
exit $status
