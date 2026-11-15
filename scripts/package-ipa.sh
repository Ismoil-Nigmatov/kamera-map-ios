#!/bin/bash
set -euo pipefail

app="$1"
public_key="Config/ipa-public.pem"
test -d "$app"
test -s "$public_key"

openssl_bin="$(brew --prefix openssl@3 2>/dev/null || true)/bin/openssl"
if [ ! -x "$openssl_bin" ]; then
  brew install openssl@3
  openssl_bin="$(brew --prefix openssl@3)/bin/openssl"
fi

du -sh "$app"
ls "$app/Frameworks" 2>/dev/null || true

rm -rf Payload KameraMap.ipa KameraMap.ipa.enc ipa.key ipa.key.enc KameraMap.ipa.sha256
mkdir Payload
cp -R "$app" Payload/
zip -qry KameraMap.ipa Payload
shasum -a 256 KameraMap.ipa | awk '{print $1 "  KameraMap.ipa"}' > KameraMap.ipa.sha256

(umask 077 && "$openssl_bin" rand -hex 32 > ipa.key)
"$openssl_bin" enc -aes-256-cbc -md sha256 -pbkdf2 -iter 200000 -salt \
  -in KameraMap.ipa -out KameraMap.ipa.enc -pass file:ipa.key
"$openssl_bin" pkeyutl -encrypt -pubin -inkey "$public_key" \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
  -in ipa.key -out ipa.key.enc

rm -rf Payload KameraMap.ipa ipa.key
ls -la KameraMap.ipa.enc ipa.key.enc
cat KameraMap.ipa.sha256
