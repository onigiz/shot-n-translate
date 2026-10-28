#!/bin/bash
# Sign the app with one stable local certificate.
# Screen Recording permission follows that certificate, so a later rebuild
# keeps the grant. Ad-hoc signing would change the identity every build.
set -euo pipefail

app="${1:?app path}"
bundle_id="${2:?bundle id}"

# Screen Recording is stored against the designated requirement, not the
# Settings switch. An ad-hoc signature pins that requirement to the build
# hash, so the switch stays on while every capture asks again.
sign_app() {
  local signing_identity="$1"
  local requirement="${2:-}"
  xattr -cr "$app" || true
  if [[ -n "$requirement" ]]; then
    # A leading "=" marks literal requirement text. Without it, codesign
    # treats the string as a file path.
    codesign --force --sign "$signing_identity" --identifier "$bundle_id" --timestamp=none -r "=${requirement}" "$app"
  else
    codesign --force --sign "$signing_identity" --identifier "$bundle_id" --timestamp=none "$app"
  fi
  local req
  req="$(codesign -d -r- "$app" 2>&1 || true)"
  echo "Signing with: $signing_identity"
  echo "$req"
  if printf '%s\n' "$req" | grep -q 'cdhash'; then
    echo "Screen Recording would reset on every package because the signature is pinned to this build." >&2
    exit 1
  fi
}

# An Apple Development identity keeps Screen Recording across rebuilds.
apple_identity="$(security find-identity -p codesigning -v | sed -n 's/.*"\(Apple Development:[^"]*\)"/\1/p' | head -n 1)"
if [[ -z "$apple_identity" ]]; then
  apple_identity="$(security find-identity -p codesigning -v | sed -n 's/.*"\(Developer ID Application:[^"]*\)"/\1/p' | head -n 1)"
fi
if [[ -n "$apple_identity" ]]; then
  sign_app "$apple_identity"
  exit 0
fi

identity="Shot n Translate Development"
support="${HOME}/Library/Application Support/Shot n Translate/signing"
p12="$support/ShotNTranslateDev.p12"
cert="$support/cert.pem"
key="$support/key.pem"
password_file="$support/password"
keychain="$(security default-keychain -d user | tr -d '"' | xargs)"

identity_installed() {
  security find-identity -p codesigning | grep -F "$identity" >/dev/null
}

if ! identity_installed; then
  mkdir -p "$support"
  chmod 700 "$support"
  if [[ ! -f "$password_file" ]]; then
    openssl rand -base64 24 > "$password_file"
    chmod 600 "$password_file"
  fi
  password="$(cat "$password_file")"

  if [[ ! -f "$p12" ]]; then
    config="$(mktemp)"
    cat > "$config" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = Shot n Translate Development
[ ext ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
    openssl req -new -newkey rsa:2048 -x509 -days 3650 -nodes \
      -config "$config" \
      -extensions ext \
      -keyout "$key" \
      -out "$cert"
    rm -f "$config"
    chmod 600 "$key"
    openssl pkcs12 -export \
      -inkey "$key" \
      -in "$cert" \
      -out "$p12" \
      -passout "pass:${password}"
    chmod 600 "$p12"
  fi

  if [[ ! -f "$cert" ]]; then
    openssl pkcs12 -in "$p12" -clcerts -nokeys -out "$cert" -passin "pass:${password}"
  fi
  security import "$p12" \
    -k "$keychain" \
    -P "$password" \
    -T /usr/bin/codesign \
    -A || true
  security add-trusted-cert -r trustRoot -k "$keychain" "$cert" || true
fi

if ! identity_installed; then
  echo "The local signing certificate is not available to codesign." >&2
  echo "Open Keychain Access, find \"${identity}\", and allow codesign to use its private key." >&2
  exit 1
fi

leaf="$(security find-certificate -c "$identity" -p | openssl x509 -noout -fingerprint -sha1 | awk -F= '{print $2}' | tr -d ':')"
requirement="designated => identifier \"${bundle_id}\" and certificate leaf = H\"${leaf}\""
sign_app "$identity" "$requirement"
