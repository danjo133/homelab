output "group_id" {
  description = "GitLab infra group ID"
  value       = gitlab_group.infra.id
}

output "project_id" {
  description = "GitLab kss project ID"
  value       = gitlab_project.kss.id
}

output "project_ssh_url" {
  description = "Git SSH URL for the project"
  value       = gitlab_project.kss.ssh_url_to_repo
}

output "project_http_url" {
  description = "Git HTTP URL for the project"
  value       = gitlab_project.kss.http_url_to_repo
}

output "argocd_user_id" {
  description = "GitLab user ID for ArgoCD"
  value       = gitlab_user.argocd.id
}

output "argocd_ssh_public_key" {
  description = "ArgoCD SSH public key (for verification)"
  value       = tls_private_key.argocd.public_key_openssh
}
