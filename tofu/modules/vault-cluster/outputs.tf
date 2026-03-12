output "kv_mount_path" {
  description = "Path of the KV v2 mount"
  value       = vault_mount.kv.path
}

output "pki_int_mount_path" {
  description = "Path of the intermediate PKI mount"
  value       = vault_mount.pki_int.path
}

output "policy_names" {
  description = "Names of all managed policies"
  value = {
    external_secrets  = vault_policy.external_secrets.name
    spiffe_workload   = vault_policy.spiffe_workload.name
    keycloak_operator = vault_policy.keycloak_operator.name
  }
}

output "k8s_auth_path" {
  description = "Path of the Kubernetes auth backend"
  value       = vault_auth_backend.kubernetes.path
}
