pid_file = "./pidfile"

vault {
  address = "https://vault:8200"
  tls_skip_verify = true
}

auto_auth {
  method {
    type = "approle"

    config = {
      role_id_file_path = "/vault-agent/s3-proxy-token-wrapper-role.id"
      secret_id_file_path = "/vault-agent/s3-proxy-token-wrapper-secret.id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink {
    type = "file"
    wrap_ttl = "5m"
    config = {
      path = "/vault-agent/token-wrapped"
    }
  }
}

api_proxy {
  use_auto_auth_token = true
}

listener "tcp" {
    address = "0.0.0.0:8200"
    tls_disable = true
}
