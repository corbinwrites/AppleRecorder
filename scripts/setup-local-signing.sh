#!/usr/bin/env bash
set -euo pipefail
NAME="AppleRecorder Local Dev"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then echo "'$NAME' already exists"; exit 0; fi
TMP="$(mktemp -d)"; cd "$TMP"
cat > c.cnf <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout k.pem -out c.pem -days 3650 -config c.cnf
openssl pkcs12 -export -inkey k.pem -in c.pem -out d.p12 -name "$NAME" -passout pass:ar \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
security import d.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P ar -T /usr/bin/codesign
rm -rf "$TMP"
echo "Created '$NAME'. If codesign asks for keychain access, choose Always Allow."
