#!/usr/bin/env bash
# Creates a self-signed code-signing certificate in the login keychain.
#
# macOS stores Accessibility grants against the app's designated requirement.
# Ad-hoc signatures (`codesign --sign -`) pin that requirement to the binary's
# cdhash, so every rebuild looks like a different app: System Settings still
# shows the toggle on, but AXIsProcessTrusted() is false. A stable certificate
# pins the requirement to the cert instead, so one grant survives rebuilds.
set -euo pipefail

CERT_NAME="${DEV_CERT_NAME:-Magic Mouse Zone Dev}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "$CERT_NAME"; then
    echo "Code-signing identity already present: $CERT_NAME"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = ${CERT_NAME}
O = Magic Mouse Zone

[v3_req]
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -new -x509 -days 3650 -nodes \
    -newkey rsa:2048 -sha256 \
    -config "$TMP/openssl.cnf" \
    -keyout "$TMP/key.pem" \
    -out "$TMP/cert.pem"

P12_PW="$(openssl rand -hex 16)"
if ! openssl pkcs12 -export -legacy \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$CERT_NAME" -out "$TMP/cert.p12" -passout pass:"$P12_PW" 2>/dev/null; then
    openssl pkcs12 -export \
        -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
        -name "$CERT_NAME" -out "$TMP/cert.p12" -passout pass:"$P12_PW"
fi

security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$P12_PW" -A -T /usr/bin/codesign

if [ -n "${KEYCHAIN_PASSWORD:-}" ]; then
    security set-key-partition-list -S apple-tool:,apple:,codesign: \
        -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 || true
fi

if ! security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "$CERT_NAME"; then
    echo "warning: imported $CERT_NAME but codesign cannot see it yet" >&2
    exit 1
fi

echo "Created self-signed code-signing identity: $CERT_NAME"
