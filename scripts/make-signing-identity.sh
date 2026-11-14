#!/usr/bin/env bash
# Creates a self-signed code-signing identity. A stable signature keeps the Accessibility
# permission across rebuilds and updates, which an ad-hoc signature can't.
#
#   ./scripts/make-signing-identity.sh
#       One-time local setup: "ShortcutPhone Local" in your login keychain, for scripts/bundle.sh.
#       macOS asks for your login password to trust the certificate for code signing.
#
#   ./scripts/make-signing-identity.sh --export <dir>
#       Release identity: writes "ShortcutPhone Release" as <dir>/release-identity.p12 plus its
#       password, without touching your keychain. Put both into the GitHub repo secrets
#       (see docs/releasing.md), then delete <dir>. Make it once and keep it: a new identity
#       makes every user grant Accessibility again.
set -euo pipefail

OPENSSL=/usr/bin/openssl # system LibreSSL: its PKCS#12 output imports cleanly into Keychain
export_dir=""
if [ "${1:-}" = "--export" ]; then
  export_dir="${2:?usage: $0 --export <dir>}"
  NAME="ShortcutPhone Release"
else
  NAME="ShortcutPhone Local"
  if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
    echo "Identity \"$NAME\" already exists and is valid."
    exit 0
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$tmp/cert.cnf" -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null

pass="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -name "$NAME" -out "$tmp/id.p12" -passout "pass:$pass"

if [ -n "$export_dir" ]; then
  mkdir -p "$export_dir"
  cp "$tmp/id.p12" "$export_dir/release-identity.p12"
  printf '%s' "$pass" > "$export_dir/release-identity.password"
  chmod 600 "$export_dir/release-identity.p12" "$export_dir/release-identity.password"
  echo "Wrote $export_dir/release-identity.p12 and release-identity.password."
  echo "Add them as GitHub secrets (see docs/releasing.md), keep a private backup, then delete $export_dir."
  exit 0
fi

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$tmp/id.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem"

security find-identity -v -p codesigning | grep "\"$NAME\"" \
  && echo "Created identity \"$NAME\"."
