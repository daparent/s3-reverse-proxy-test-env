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

## Configure Vault
First shut everything down that has been configured, we'll focus just on vault to avoid all the logs that show up for all the services.  To do this run the following commands:
- `docker compose down -v`
- `docker compose up -d vault`

Since vault has first launched it will need to have the unseal key(s) setup, and this is done by going to `https://localhost:8200`.  Follow the prompts, I setup a single unseal key since this is just for dev purposes.

Once into vault configure the login methods, I setup OIDC with keycloak and I configure a couple key-value stores.  Vault will be used to hold the s3 keys in a secure manner.  For my tests I will use it to provide the credentials to aws-s3-reverse-proxy.

Configure vault as follows:

## All Done
Now that evertyhing is complete you can start everything up from here on out with:
`docker compose up -d`

# How to Debug Go Applications Running in a Container

[Debug Go In a Container](https://github.com/olivere/go-container-debugging/tree/master)

# References
- https://github.com/cht42/minio-keycloak
- https://min.io/docs/minio/container/operations/external-iam/configure-keycloak-identity-management.html
