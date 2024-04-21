Steps:

- Create a policy called `pull-wrapped-tokens` and set it to:
```
path "auth/approle/role/+/secret*" {
  capabilities = [ "create", "read", "update" ]
  min_wrapping_ttl = "100s"
  max_wrapping_ttl = "300s"
}
```
- Generate approle for retrieving token that will allow fetching of approle for the application
    - Make sure bind_secret_id is set to false (so the secret_id can be wrapped for the vault-agent)
```
$ vault write auth/approle/role/s3-reverse-proxy \
> secret_id_ttl=10m \
> token_num_uses=0 \
> token_policies=default,s3-datalake-creds \
> secret_id_num_uses=2 \
> token_ttl=5m \
> token_max_ttl=15m
$ vault read auth/approle/role/s3-reverse-proxy/role-id
```
    - Put the role_id into the s3-reverse-proxy-role-id file in the /vault-agent directory for the container
    - Get the wrapped token onto the machine running the proxy
```
$ vault write -f -wrap-ttl=10m auth/approle/role/token-grabber/secret-id
```
    - Put the wrapped secret_id into the s3-reverse-proxy-wrapped-secret-id
- Launch the vault-agent and let it retrieve the token that the app can use to retrieve secrets
    - You could also write a template file that pulls the secrets out and puts them somewhere the app can reach as well...
- Your app should mount the same directory the token was output to as read-write, it will delete the token when it reads it in



What am I trying to do:

1. Have a role-id and secret-id (unwrapped) called s3-reverse-proxy-token-wrapper that vault-agent can use to create a token that allows for a write process to occur to get a secret-id from the s3-reverse-proxy approle.  The token should have a short ttl, like 15m or something like that, allow the vault-agent to take care of renewing.  Renewals should not be limited on this approle
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

Create approle for this unwrapper
```
$ vault write -f auth/approle/role/s3-reverse-proxy-token-wrapper \ token_policies=read-and-wrap-s3-reverse-proxy-secret-id \
token_no_default_policy=true \
token_max_ttl=15m \
secret_id_ttl=15m secret_id_num_uses=1
```

2. Set that role-id and secret-id, unwrapped, in the vault-agent and have it pull a token and wrap it on the file system, the vault-agent
```
$ vault read auth/approle/role/s3-reverse-proxy-token-wrapper/role-id
abb18943-962e-d94c-6642-f4c77b56fdbf
$ vault write -f auth/approle/role/s3-reverse-proxy-token-wrapper/secret-id
bfe0b372-c32a-b865-80d1-be4b04de1ff8
```

3. Give the reverse proxy a token that is able to only unwrap the wrapped token produced by step 2
4. Give the reverse proxy the role-id for the s3-reverse-proxy approle
5. Have a token that can only unwrap the s3-reverse-proxy approle secret-id in a file that the reverse proxy can read, this token will have to be renewed every 10-15 minutes
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
Create the token
```
$ vault token create -orphan -no-default-policy -policy=validate-and-unwrap
```

6. Have the reverse proxy open the file
    - validate the wrapped token, make sure it hasn't expired, and has at least 1 use left
    - unwrap the secret-id and store it in a variable
```
$ vault write auth/approle/login \
role_id=abb18943-962e-d94c-6642-f4c77b56fdbf \
secret_id=bfe0b372-c32a-b865-80d1-be4b04de1ff8
# This next step is to fake out what the vault-agent would automatically do with the token wrapping
$ VAULT_TOKEN="token_from_above" vault write -f -wrap-ttl=15m auth/approle/role/s3-reverse-proxy/secret-id
```

7. Using the role-id and the now retrieved secret-id generate a token that can be used to access the s3 bucket secrets
```
$ VAULT_TOKEN="token_from_previous_cmd" vault unwrap <wrapped_token>
$ vault write auth/approle/login \
role_id= \
secret_id=
```

8. Get the s3 bucket secret
```
# You should now have a token that can read the s3 secrets
$ vault kv get kv/s3/datalake_write
```







# Allow tokens to look up their own properties
path "auth/token/lookup-self" {
    capabilities = ["read"]
}

# Allow tokens to renew themselves
path "auth/token/renew-self" {
    capabilities = ["update"]
}

# Allow tokens to revoke themselves
path "auth/token/revoke-self" {
    capabilities = ["update"]
}

# Allow a token to look up its own capabilities on a path
path "sys/capabilities-self" {
    capabilities = ["update"]
}

# Allow a token to look up its own entity by id or name
path "identity/entity/id/{{identity.entity.id}}" {
  capabilities = ["read"]
}
path "identity/entity/name/{{identity.entity.name}}" {
  capabilities = ["read"]
}


# Allow a token to look up its resultant ACL from all policies. This is useful
# for UIs. It is an internal path because the format may change at any time
# based on how the internal ACL features and capabilities change.
path "sys/internal/ui/resultant-acl" {
    capabilities = ["read"]
}

# Allow a token to renew a lease via lease_id in the request body; old path for
# old clients, new path for newer
path "sys/renew" {
    capabilities = ["update"]
}
path "sys/leases/renew" {
    capabilities = ["update"]
}

# Allow looking up lease properties. This requires knowing the lease ID ahead
# of time and does not divulge any sensitive information.
path "sys/leases/lookup" {
    capabilities = ["update"]
}

# Allow a token to manage its own cubbyhole
path "cubbyhole/*" {
    capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow a token to wrap arbitrary values in a response-wrapping token
path "sys/wrapping/wrap" {
    capabilities = ["update"]
}

# Allow a token to look up the creation time and TTL of a given
# response-wrapping token
path "sys/wrapping/lookup" {
    capabilities = ["update"]
}

# Allow a token to unwrap a response-wrapping token. This is a convenience to
# avoid client token swapping since this is also part of the response wrapping
# policy.
path "sys/wrapping/unwrap" {
    capabilities = ["update"]
}

# Allow general purpose tools
path "sys/tools/hash" {
    capabilities = ["update"]
}
path "sys/tools/hash/*" {
    capabilities = ["update"]
}

# Allow checking the status of a Control Group request if the user has the
# accessor
path "sys/control-group/request" {
    capabilities = ["update"]
}

# Allow a token to make requests to the Authorization Endpoint for OIDC providers.
path "identity/oidc/provider/+/authorize" {
    capabilities = ["read", "update"]
}
