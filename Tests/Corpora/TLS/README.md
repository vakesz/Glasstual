# Loopback TLS identities

`LoopbackTestIdentity.p12` is a self-signed RSA-2048 test identity for
`127.0.0.1` and `localhost`. `AsyncCertificateValidationLoopbackTests` and
`LegacyCipherSuiteFallbackTests` use it, and the E2E loopback peer loads it
from `../TLS/LoopbackTestIdentity.p12` relative to `E2E_FIXTURE`.

The public test passphrase is `glasstual`. All loaders use
`kSecImportToMemoryOnly`, so no fixture is written to a keychain or trust
store.

Regenerate it with:

```sh
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 36500 \
    -nodes -subj "/CN=Glasstual Loopback Test" \
    -addext "subjectAltName=IP:127.0.0.1,DNS:localhost"
openssl pkcs12 -export -legacy -out LoopbackTestIdentity.p12 \
    -inkey key.pem -in cert.pem -passout pass:glasstual \
    -name "Glasstual Loopback Test"
```

`-legacy` selects PKCS#12 encryption supported by `SecPKCS12Import`.

## Client certificate chain

`ClientChainTestIdentity.p12` contains a generated RSA-2048 client identity
with the TLS client-authentication extended key usage, its intermediate CA
and its self-signed root CA. These are public test credentials, generated for
this repository; the passphrase is `glasstual`. `TLSClientIdentityTests` uses
it for mutual TLS over loopback, trusting only the fixture root.

Regenerate in an empty temporary directory:

```sh
openssl req -x509 -newkey rsa:2048 -nodes -days 36500 \
    -keyout root.key -out root.pem -subj '/CN=Glasstual mTLS Test Root'
openssl req -new -newkey rsa:2048 -nodes -keyout intermediate.key \
    -out intermediate.csr -subj '/CN=Glasstual mTLS Test Intermediate'
cat > intermediate.ext <<'EOF'
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF
openssl x509 -req -in intermediate.csr -CA root.pem -CAkey root.key \
    -set_serial 2 -days 36500 -extfile intermediate.ext -out intermediate.pem
openssl req -new -newkey rsa:2048 -nodes -keyout client.key \
    -out client.csr -subj '/CN=Glasstual mTLS Test Client'
cat > client.ext <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF
openssl x509 -req -in client.csr -CA intermediate.pem -CAkey intermediate.key \
    -set_serial 3 -days 36500 -extfile client.ext -out client.pem
cat intermediate.pem root.pem > chain.pem
openssl pkcs12 -export -legacy -out ClientChainTestIdentity.p12 \
    -inkey client.key -in client.pem -certfile chain.pem \
    -passout pass:glasstual -name 'Glasstual mTLS Test Client'
```

Only the `.p12` file belongs in the corpus; it does not contain either CA's
private key.
