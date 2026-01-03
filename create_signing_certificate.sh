#!/bin/bash
# Create a self-signed certificate for stable code signing

CERT_NAME="PUSH Developer Certificate"

echo "Creating self-signed certificate for PUSH..."

# Check if certificate already exists
if security find-certificate -c "$CERT_NAME" &>/dev/null; then
    echo "✅ Certificate '$CERT_NAME' already exists"
    exit 0
fi

# Create certificate
cat > /tmp/push-cert.conf <<EOF
[ req ]
default_bits = 2048
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[ req_distinguished_name ]
CN = $CERT_NAME
O = PUSH
C = US

[ v3_req ]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:false
EOF

# Generate certificate
openssl req -x509 -newkey rsa:2048 -keyout /tmp/push-key.pem -out /tmp/push-cert.pem -days 3650 -nodes -config /tmp/push-cert.conf

# Create p12 file with empty password
openssl pkcs12 -export -out /tmp/push-cert.p12 -inkey /tmp/push-key.pem -in /tmp/push-cert.pem -passout pass:

# Import to keychain with empty password
security import /tmp/push-cert.p12 -k ~/Library/Keychains/login.keychain-db -P "" -T /usr/bin/codesign -T /usr/bin/security

# Trust the certificate for code signing
security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db /tmp/push-cert.pem

# Clean up
rm /tmp/push-cert.conf /tmp/push-key.pem /tmp/push-cert.pem /tmp/push-cert.p12

echo "✅ Certificate created and installed"
echo ""
echo "Run './build_xcode_project.sh' to rebuild with stable signing"
