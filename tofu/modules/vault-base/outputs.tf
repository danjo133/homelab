output "pki_path" {
  description = "Path of the root PKI mount"
  value       = vault_mount.pki.path
}

output "namespace_paths" {
  description = "Map of namespace name to path"
  value       = { for k, v in vault_namespace.cluster : k => v.path }
}

output "cluster_kv_mount_paths" {
  description = "Map of namespace name to KV v2 mount path"
  value       = { for k, v in vault_mount.cluster_kv : k => v.path }
}

output "convenience_kv_mount_path" {
  description = "KV v2 mount path in the convenience namespace"
  value       = vault_mount.convenience_kv.path
}
