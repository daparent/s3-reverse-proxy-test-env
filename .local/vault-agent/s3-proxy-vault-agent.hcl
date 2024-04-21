pid_file = "./pidfile"

vault {
  address = "https://vault:8200"
  tls_skip_verify = true
}

auto_auth {
  method {
    type = "approle"

    config = {
      role_id_file_path = "/vault-agent/s3-reverse-proxy-role.id"
      secret_id_file_path = "/vault-agent/s3-reverse-proxy-wrapped-secret.id"
      secret_id_response_wrapping_path = "auth/approle/role/s3-reverse-proxy/secret.id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink {
    type = "file"
    config = {
      path = "/vault-agent/token"
    }
  }

  sink {
    type = "file"
    wrap_ttl = 5m
    config = {
      path = "/vault-agent/token-wrapped"
    }
  }
}

// template {
//   source = "/vault-agent/s3keys.ctmpl"
//   destination = "/vault-agent/s3keys.json"
// }

api_proxy {
  use_auto_auth_token = true
}

// cache {
//   use_auto_auth_token = true
// }

listener "tcp" {
    address = "0.0.0.0:8200"
    tls_disable = true
}


