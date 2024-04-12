# Self-Signed Certificates For Vault

To create self-signed certificates:

```
openssl req -x509 -sha512 -days 365 -nodes -newkey rsa:4096 -subj "/CN=localhost/C=CA/ST=Ontario/L=Ottawa" -keyout rootCA.key -out rootCA.crt
openssl genrsa -out vault.key 4096

# use csr.conf or generate a new one by doing the following:
cat > csr.conf <<EOF
[ req ]
default_bits = 4096
prompt = no
default_md = sha512
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C = CA
ST = Ontario
L = Chatham
O = CTown
OU = CTown Dev
CN = localhost

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = localhost
DNS.2 = vault
IP.1 = 127.0.0.1

EOF

openssl req -new -key vault.key -out vault.csr -config csr.conf

cat > cert.conf <<EOF

authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = vault

EOF

openssl x509 -req -in vault.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out vault.crt -days 365 -sha512 -extfile cert.conf

```

Once that is all done copy the following files into the vault/config/tls folder:
```
mkdir -p vault/config/tls
cp rootCA.crt vault/config/tls/ca.crt
cp vault.crt vault.key vault/config/tls/
```
