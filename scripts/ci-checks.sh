#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Checking generated artifacts"
./scripts/check-generated-artifacts.sh

echo "==> Linting JSON files"
./scripts/lint-json.sh

echo "==> Checking whitespace"
git diff --check

echo "==> Building"
swift build

echo "==> Testing"
swift test
