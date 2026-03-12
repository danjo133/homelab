output "pki_path" {
  description = "Path of the root PKI mount"
  value       = vault_mount.pki.path
}

output "namespace_paths" {
  description = "Map of namespace name to path"
  value       = { for k, v in vault_namespace.cluster : k => v.path }
}
