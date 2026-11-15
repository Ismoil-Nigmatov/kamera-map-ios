#!/bin/bash
set -euo pipefail

repo="Ismoil-Nigmatov/kamera-map-ios"
private_key="${IPA_PRIVATE_KEY:-$HOME/.config/kamera-map-ios/ipa-private.pem}"
out="${1:-.}"
gh_bin="$(command -v gh || echo "$HOME/.local/bin/gh")"

run_id="${RUN_ID:-$("$gh_bin" api "repos/$repo/actions/artifacts?name=KameraMap-ipa&per_page=1" --jq '.artifacts[0].workflow_run.id')}"
if [ -z "$run_id" ] || [ "$run_id" = "null" ]; then
  echo "No KameraMap-ipa artifact found" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
"$gh_bin" run download "$run_id" -R "$repo" -n KameraMap-ipa -D "$work"

(umask 077 && openssl pkeyutl -decrypt -inkey "$private_key" \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
  -in "$work/ipa.key.enc" -out "$work/ipa.key")
openssl enc -d -aes-256-cbc -md sha256 -pbkdf2 -iter 200000 \
  -in "$work/KameraMap.ipa.enc" -out "$out/KameraMap.ipa" -pass "file:$work/ipa.key"

(cd "$out" && sha256sum -c "$work/KameraMap.ipa.sha256")
echo "Run $run_id -> $out/KameraMap.ipa"
