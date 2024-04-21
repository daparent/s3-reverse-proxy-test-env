# "Safely" Retrieve A Token To Access S3 Tokens In Hashicorp Vault

What am I trying to do:

1. Have a role-id and secret-id (unwrapped) called s3-reverse-proxy-token-wrapper that vault-agent can use to create a token that allows for a write process to occur to get a secret-id from the s3-reverse-proxy approle.  The token should have a short ttl, like 15m or something like that, allow the vault-agent to take care of renewing.  Renewals should not be limited on this approle
2. Set that role-id and secret-id, unwrapped, in the vault-agent and have it pull a token and wrap it on the file system, the vault-agent
3. Give the reverse proxy a token that is able to only unwrap the wrapped token produced by step 2
4. Give the reverse proxy the role-id for the s3-reverse-proxy approle
5. Have a token that can only unwrap the s3-reverse-proxy approle secret-id in a file that the reverse proxy can read, this token will have to be renewed every 10-15 minutes
Create the token
6. Have the reverse proxy open the file
    - validate the wrapped token, make sure it hasn't expired, and has at least 1 use left
    - unwrap the secret-id and store it in a variable
7. Using the role-id and the now retrieved secret-id generate a token that can be used to access the s3 bucket secrets
8. Get the s3 bucket secret

## Policies
read-and-wrap-s3-reverse-proxy-secret-id:
```
# Allow a token to wrap arbitrary values in a response-wrapping token
path "sys/wrapping/wrap" {
    capabilities = ["update"]
}

path "auth/approle/role/s3-reverse-proxy/secret-id" {
  	capabilities = ["read", "update"]
}
```
validate-and-unwrap:
```
# Allow a token to unwrap a response-wrapping token. This is a convenience to
# avoid client token swapping since this is also part of the response wrapping
# policy.
path "sys/wrapping/unwrap" {
    capabilities = ["update"]
}
path "sys/wrapping/lookup" {
 		capabilities = ["read"]
}
# Allow tokens to renew themselves
path "auth/token/renew-self" {
    capabilities = ["update"]
}
```

## Approle setup
- Create approle for a token unwrapper
```
$ vault write -f auth/approle/role/s3-reverse-proxy-token-wrapper \
token_policies=read-and-wrap-s3-reverse-proxy-secret-id \
token_no_default_policy=true \
token_max_ttl=15m \
secret_id_ttl=15m \
secret_id_num_uses=1
```
- Create an approle for retrieving s3-proxy credentials
```
$ vault write auth/approle/role/s3-reverse-proxy \
secret_id_ttl=10m \
token_num_uses=0 \
token_policies=default,s3-datalake-creds \
secret_id_num_uses=2 \
token_ttl=5m \
token_max_ttl=15m
```

## Create tokens
- The s3 token unwrapper tokens that will go into the vault-agent, the vault-agent should take care of renewing the generated token from them. This token will be unwrapped but will only have the ability to wrap the secret-id of the s3-reverse-proxy approle.  The vault-agent will write out the wrapped version to disk for the s3-reverse-proxy to read in.
```
$ export TOKEN_WRAPPER_ROLE_ID=$(vault read auth/approle/role/s3-reverse-proxy-token-wrapper/role-id | jq -r '.data.role_id')
$ export TOKEN_WRAPPER_SECRET_ID=$(vault write -f auth/approle/role/s3-reverse-proxy-token-wrapper/secret-id | jq -r '.data.secret_id')
```

- The token for validating and unwrapping the s3-reverse-proxy secret-id.  This will be given to the s3-reverse-proxy app and will have to be renewed regularly.  Having a ttl of 72 hours and renewing every hour (with an error / alert on failure) should cover off long weekends where things go wrong.  All this token can do is unwrap a wrapped token, nothing else.
```
$ export VALIDATE_AND_UNWRAP_TOKEN=$(vault token create -format=json -orphan -no-default-policy -policy=validate-and-unwrap | jq -r '.auth.client_token')
```

## Testing
- For testing out at the cli, fake out pulling the token wrapper token and create a wrapped s3-reverse-proxy secret-id
```
$ TOKEN_WRAPPER_TOKEN=$(vault write -format=json auth/approle/login role_id=${TOKEN_WRAPPER_ROLE_ID} secret_id=${TOKEN_WRAPPER_SECRET_ID} | jq -r '.auth.client_token')
# This next step is to fake out what the vault-agent would automatically do with the token wrapping
$ WRAPPED_S3_PROXY_SECRET_ID=$(VAULT_TOKEN="${TOKEN_WRAPPER_TOKEN}" vault write -format=json -f -wrap-ttl=15m auth/approle/role/s3-reverse-proxy/secret-id | jq -r '.wrap_info.token')
```

- Once again for testing, fake out what the s3-reverse-proxy will do, take the unwrap token
```
$ S3_REVERSE_PROXY_SECRET_ID=$(VAULT_TOKEN="${VALIDATE_AND_UNWRAP_TOKEN}" vault unwrap -format=json ${WRAPPED_S3_PROXY_SECRET_ID} | jq -r '.data.secret_id')
$ S3_REVERSE_PROXY_ROLE_ID=$(vault read -format=json auth/approle/role/s3-reverse-proxy/role-id | jq -r '.data.role_id')
$ S3_REVERSE_PROXY_TOKEN=$(vault write -format=json auth/approle/login role_id=${S3_REVERSE_PROXY_ROLE_ID} secret_id=${S3_REVERSE_PROXY_SECRET_ID} | jq -r '.auth.client_token')
```

- Now test to make sure that you can actually retrieve a secret with the resulting token
```
# You should now have a token that can read the s3 secrets
$ VAULT_TOKEN="${S3_REVERSE_PROXY_TOKEN}" vault kv get kv/s3/datalake_write
```
