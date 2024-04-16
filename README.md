# General Config

Some of these settings would be bad for a production server, shortcuts are used here when they are unimportant for dev purposes since the server contains fake data and is only intended to be used for development.  **DO NOT USE ANY OF THIS SETUP FOR PRODUCTION WITHOUT GIVING PROPER SCRUTINY**.

Add a .env file in the same folder as the docker-compose.yaml file.  The file should contain at least the following configuration:

```
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD="<generated_password>"
MINIO_SERVER_URL=http://localhost:9000
MINIO_BROWSER_REDIRECT_URL=http://localhost:9001
DB_PASSWORD="<generated_password>"
KEYCLOAK_ADMIN_LOGIN=admin
KEYCLOAK_ADMIN_PASSWORD="<generated_password>"
WRITE_DATALAKE_CREDENTIALS="actual_key_id,actual_secret"
AWS_REGION="ca-east-ont"
```

Create all the external volumes that will attach to the containers (this is a one-time setup):

```
docker volume create data1-1
docker volume create data1-2
docker volume create data2-1
docker volume create data2-2
docker volume create data3-1
docker volume create data3-2
docker volume create data4-1
docker volume create data4-2
docker volume create postgres_data
```

## Configure the Keycloak Realm
Launch keycloak, which means starting postgres as well: 
- `docker compose up -d postgres`
- `docker compose up -d keycloak`
Go to the admin console found at http://localhost:8080 and login with the credentials found in the KEYCLOAK_ADMIN_LOGIN and KEYCLOAK_ADMIN_PASSWORD found in you .env file.  Remember this is config for dev purposes only.

Once in configure keycloak as follows (assuming OIDC is used for minio):
- Go to `Realm Settings`
    - Unmanaged Attributes: `Enabled`
    - Click `Save`
- Go to `Clients`
    - Click on create
        - Client ID: `minio`
        - Name: `minio`
        - Description: `minio keycloak client`
        - Always display in UI: `On`
        - Click `Next`
        - Client authentication: `On`
        - Authorization: `On`
        - Authentication Flow:
            - Standard flow: `Checked`
            - Direct access grants: `Checked`
            - Implicit flow: `Checked`
            - Service accounts roles: `Checked`
            - Oauth 2.0 Device Authorization Grant: `Checked`
            - OIDC CIBA Grant: `Checked`
        - Click `Next`
        - Valid redirect URIS: `*`
        - Click `Save`
    - Click on Credentials, the `Client Secret` can be copied and pasted into the .env file for the `MINIO_IDENTITY_OPENID_CLIENT_SECRET` variable
- Go to `Users`
     - Click on the `admin` user
     - Click on the `Attributes` tab
     - Click on `Add attributes`
        - Key: `policy`
        - Value: `readwrite`
    - Click `Save`
- Go to `Clients`
    - Click on `minio`
    - Click on the `Client scopes` tab
    - Click `minio-dedicated`
    - Click on `Add mapper` drop down and choose `By configuration`
        - Choose `Audience`
            - Name: `minio-audience`
            - Included Client Audience: `security-admin-console`
        - Click `Save`
    - Click on `Client Details` in the bread crumbs at the top
    - Click on the `Service accounts roles` tab
    - Click `Assign role`
        - Check the checkbox beside `admin` and click `Assign`
    - Click on the `Roles` tab
    - Click `Create role`
        - Role name: `admin`
        - Description: `${role_admin}`
        - Click `Save`

You now have keycloak setup for OIDC with minio if you so choose to use it that way.  For my purposes right now it is not necessary but I figured it doesn't hurt to keep that config around.

## Configure Minio
Launch the rest of the containers, we'll configure minio next: `docker compose up -d minio1 minio2 minio3 minio4 nginx`.  Go to the minio console and login with the admin credentials found in MINIO_ROOT_USER and MINIO_ROOT_PASSWORD found in your .env file.  You could setup minio to work directly with keycloak but for the purpose of what I'm working on this is not a requirement - s3 storage is actually separate from the auth and auth tool...

Now configure minio as follows:
- Login to minio at `http://localhost:9000`
- If it's your first time logging in it shows the Buckets view, if not then click on `Buckets`
- Click `Create Bucket +`
    - Bucket Name: `ts-datalake`
    - Click `Create Bucket`
- Click `Create Bucket +`
    - Bucket Name: `ts-datalake-users`
    - Click `Create Bucket`
- Click `Users`
    - Click `Create User +`
        - User Name: `datalake_read`
        - Click the checkbox beside `readonly`
        - Click `Save`
    - Click `Create User +`
        - User Name: `datalake_write`
        - Click the checkbox beside `readonly` and `readwrite`
        - Click `Save`
    - Click `Create User +`
        - User Name: `datalake_users_write`
        - Click the checkbox beside `readonly` and `readwrite`
        - Click `Save`
    - Click on `datalake_write`
        - Click on the `Service Accounts` tab
            - Click `Create Access Key +`
                - Turn Restrict beyond user policy to `ON`
                - Add in the following block:
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "arn:aws:s3:::ts-datalake",
                "arn:aws:s3:::ts-datalake/*"
            ]
        }
    ]
}
```
                - Name `ts-datalake-write`
                - Description `Write access to the ts-datalake`
                - Click `Create`
                - Capture the `Access Key` and `Secret Key` to use later on (I put it in my .env file as `DATALAKE_WRITE_ACCESS_KEY` and `DATALAKE_WRITE_SECRET_KEY`
                - Click the `X` in the top right
- Click `Users`
    - Click on `datalake_read`
        - Click on the `Service Accounts` tab
            - Click `Create Access Key +`
                - Turn Restrict beyond user policy to `ON`
                - Add in the following block:
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation",
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::ts-datalake",
                "arn:aws:s3:::ts-datalake/*"
            ]
        }
    ]
}
```
                - Name `ts-datalake`
                - Description `Read access to the ts-datalake`
                - Click `Create`
                - Capture the `Access Key` and `Secret Key` to use later on (I put it in my .env file as `DATALAKE_READ_ACCESS_KEY` and `DATALAKE_READ_SECRET_KEY`
                - Click the `X` in the top right


## Configure Vault

Vault needs TLS configured and it's as easy as creating some self-signed certificates.  To do so follow these steps and for reference you can always visit [devopscube.com](https://devopscube.com/create-self-signed-certificates-openssl).

These instructions will work in Linux or in WSL for windows, really anywhere that openssl is available to run.  There likely is a
windows binary but setting up wsl is pretty straightforward (and beyond the scope of this document but a quick google search will
turn up decent instructions).  I'll assume a bash shell is available at this point:

```
$ cd .local
$ mkdir tls-config && cd tls-config
$ openssl req -x509 -sha512 -days 365 -nodes -newkey rsa:4096 -subj "/CN=localhost/C=CA/L=Chatham" -keyout rootCA.key -out rootCA.crt
$ openssl genrsa -out vault.key 4096
$ cat > csr.conf <<EOF
[ req ]
default_bits = 4096
prompt = no
default_md = sha512
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C = Country Code (US / CA / etc)
ST = State or Province
L = City
O = Organization
OU = Organization Unit
CN = localhost

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = localhost
IP.1 = 127.0.0.1

EOF
$ openssl req -new -key vault.key -out vault.csr -config csr.conf
$ cat > cert.conf <<EOF

authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost

EOF
$ openssl x509 -req -in vault.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out vault.crt -days 365 -sha512 -extfile cert.conf
$ cp rootCA.crt ../vault/config/tls/ca.crt
$ cp vault.key vault.crt ../vault/config/tls/
$ cd ../vault/config
$ cat > config.json <<EOF
{
  "listener": {
    "tcp": {
      "address": "0.0.0.0:8200",
      "tls_cert_file": "/vault/config/tls/vault.crt",
      "tls_key_file": "/vault/config/tls/vault.key",
      "tls_client_ca_file": "/vault/config/tls/ca.crt",
      "max_request_size": "-1",
      "max_request_duration": "10m"
    }
  },
  "backend": {
    "file": {
      "path": "/vault/data"
     }
  },
  "default_lease_ttl": "168h",
  "max_lease_ttl": "720h",
  "max_ttl": "12h",
  "api_addr": "https://0.0.0.0:8200",
  "disable_mlock": true,
  "ui": true
}

EOF

```

First shut everything down that has been configured, we'll focus just on vault to avoid all the logs that show up for all the services.  To do this run the following commands:
- `docker compose down -v`
- `docker compose up -d vault`

Since vault has first launched it will need to have the unseal key(s) setup, and this is done by going to `https://localhost:8200`.  Follow the prompts:
- Key shares: `1`
- Key threshold: `1`
- Click `Initialize`
- Copy `Initial root token` somewhere safe, this is a dev instance so don't worry about it getting into the wrong hands, just store it somewhere you can find it again
- Copy `Key 1` somewhere safe, this is a dev instance so don't worry about it getting into the wrong hands, just store it somewhere you can find it again
- Click `Continue to Unseal`
- Copy and paste (or type) the `Key 1` value (that you saved somewhere safe) into the `Unseal Key Portion` text field
- Click `Unseal`
- To login as `root` copy the `Initial root token` value and paste it into the `Token` prompt.

Now you're in to vault as root, the rest of the config will be done from the cli using the vault cli program.  Configure vault as follows:

## All Done
Now that evertyhing is complete you can start everything up from here on out with:
`docker compose up -d`

# How to Debug Go Applications Running in a Container

[Debug Go In a Container](https://github.com/olivere/go-container-debugging/tree/master)

# References
- https://github.com/cht42/minio-keycloak
- https://min.io/docs/minio/container/operations/external-iam/configure-keycloak-identity-management.html
