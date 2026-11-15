#!/bin/bash
set -euo pipefail

key=$(printf '%s' "${YANDEX_MAPKIT_KEY:-}" | tr -d '[:space:]')
if [ -z "$key" ]; then
  echo "::warning::YANDEX_MAPKIT_KEY is empty, the map will show a placeholder"
  exit 0
fi

printf 'KM_YANDEX_MAPKIT_KEY = %s\n' "$key" > Config/Secrets.xcconfig
if printf '%s' "$key" | grep -Eq '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'; then
  echo "MapKit key: set, ${#key} characters"
else
  echo "::warning::YANDEX_MAPKIT_KEY is set (${#key} characters) but does not look like a MapKit key"
fi
