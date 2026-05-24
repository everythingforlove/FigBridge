#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

violations=()

while IFS= read -r path; do
  case "$path" in
    .build/*|dist/*|DerivedData/*|Packages/*|.swiftpm/*)
      violations+=("$path")
      ;;
    harmony/*|entry/*|oh_modules/*)
      violations+=("$path")
      ;;
    *.dmg|*.app|*.app/*|*.xcarchive|*.xcarchive/*)
      violations+=("$path")
      ;;
    tmp/*)
      if [[ "$path" != "tmp/app-icon-source.png" ]]; then
        violations+=("$path")
      fi
      ;;
    */agent-output.txt|*/figbridge-harmony-report.md|*/design-ir/design.json)
      if [[ "$path" != Tests/* ]]; then
        violations+=("$path")
      fi
      ;;
  esac
done < <(git ls-files)

if (( ${#violations[@]} > 0 )); then
  echo "error: generated or local-only artifacts are tracked:" >&2
  printf '  %s\n' "${violations[@]}" >&2
  echo "" >&2
  echo "Move intentional fixtures under Tests/FigBridgeTests/Fixtures or remove generated artifacts from git." >&2
  exit 1
fi

echo "Generated artifact gate passed."
