#!/usr/bin/env bash
# PostToolUse hook: format the just-edited Swift file with SwiftFormat.
# Safe by design: no-ops if swiftformat is missing, only touches .swift files,
# and always exits 0 so it can never block an edit.
command -v swiftformat >/dev/null 2>&1 || exit 0

input=$(cat)
file=$(printf '%s' "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)

case "$file" in
  *.swift) ;;
  *) exit 0 ;;
esac

[ -f "$file" ] || exit 0
swiftformat "$file" >/dev/null 2>&1
exit 0
