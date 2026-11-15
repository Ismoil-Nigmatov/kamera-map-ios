#!/bin/bash
set -uo pipefail

if [ -f log-stream.pid ]; then
  kill "$(cat log-stream.pid)" 2>/dev/null || true
  sleep 1
fi

touch app.log
key=$(printf '%s' "${YANDEX_MAPKIT_KEY:-}" | tr -d '[:space:]')
if [ -n "$key" ]; then
  sed -i '' "s/$key/[mapkit-key]/g" app.log
fi
sed -E -i '' 's/([Aa][Pp][Ii]_?[Kk][Ee][Yy]=)[^&[:space:]]+/\1[hidden]/g' app.log
echo "app.log: $(wc -l < app.log) lines"
grep -iE "yandex|mapkit|tile|error|fail|invalid|forbidden|unauthori|denied|me\.ismoiljon" app.log | tail -150 || true

mkdir -p crashes
find "$HOME/Library/Logs/DiagnosticReports" -name 'KameraMap*' -newer project.yml -exec cp {} crashes/ \; 2>/dev/null || true
if ls crashes/* > /dev/null 2>&1; then
  python3 scripts/crash-summary.py crashes/*
else
  echo "No crash reports"
fi
