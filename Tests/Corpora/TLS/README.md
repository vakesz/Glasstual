# Loopback TLS identity

`LoopbackTestIdentity.p12` is a throwaway self-signed RSA-2048 identity, kept so
that `ConnectionTrustGateLoopbackTests` can stand up a TLS listener on
`127.0.0.1` and drive the real connection service against it. A self-signed
chain is exactly what the trust gate exists for: the system will not trust it,
the failure is recoverable, and the service asks the application what to do.

It is not a secret. The passphrase is `glasstual`, it is checked in on purpose,
it names no host anyone owns, and nothing outside the test bundle loads it — the
test imports it with `kSecImportToMemoryOnly`, so it never reaches a keychain.

Regenerate it with:

```sh
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 36500 \
    -nodes -subj "/CN=Glasstual Loopback Test" \
    -addext "subjectAltName=IP:127.0.0.1,DNS:localhost"
openssl pkcs12 -export -legacy -out LoopbackTestIdentity.p12 \
    -inkey key.pem -in cert.pem -passout pass:glasstual \
    -name "Glasstual Loopback Test"
```

`-legacy` matters: `SecPKCS12Import` does not read the AES/PBKDF2 encryption
OpenSSL 3 writes by default.
