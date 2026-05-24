#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

json_files=()
while IFS= read -r file; do
  [[ -n "$file" ]] && json_files+=("$file")
done < <(git ls-files '*.json')

if (( ${#json_files[@]} == 0 )); then
  echo "No JSON files found."
  exit 0
fi

if command -v python3 >/dev/null 2>&1; then
  for file in "${json_files[@]}"; do
    python3 -m json.tool "$file" >/dev/null
  done
elif command -v plutil >/dev/null 2>&1; then
  for file in "${json_files[@]}"; do
    plutil -lint "$file" >/dev/null
  done
else
  echo "error: need plutil or python3 to lint JSON files" >&2
  exit 1
fi

echo "JSON lint gate passed for ${#json_files[@]} files."
