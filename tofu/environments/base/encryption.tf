# OpenTofu native state encryption
# Passphrase provided via TF_VAR_state_encryption_passphrase env var.
# Store the passphrase securely (e.g. in Vault at secret/tofu/encryption).

terraform {
  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_encryption_passphrase
    }

    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }

    state {
      method = method.aes_gcm.state
    }

    plan {
      method = method.aes_gcm.state
    }
  }
}
