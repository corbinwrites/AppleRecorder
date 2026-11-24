#!/usr/bin/env bash
set -euo pipefail
[ -e release-cert.pem ] && { echo "Refusing to overwrite: a new cert resets every user's permissions."; exit 1; }
cat > cert.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = AppleRecorder Release
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout release-key.pem -out release-cert.pem -days 7300 -config cert.cnf
# 3DES + SHA-1 so macOS `security import` accepts it (OpenSSL 3 defaults break import)
openssl pkcs12 -export -inkey release-key.pem -in release-cert.pem -out release.p12 \
  -name "AppleRecorder Release" -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
openssl x509 -in release-cert.pem -noout -fingerprint -sha1 | sed 's/.*=//; s/://g' > release-cert.sha1
base64 -i release.p12 | pbcopy   # paste into the MAC_SIGN_P12 environment secret
echo "Commit release-cert.pem + release-cert.sha1. Never commit release-key.pem or release.p12."
