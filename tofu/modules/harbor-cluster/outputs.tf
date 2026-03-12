output "project_id" {
  description = "Harbor project ID"
  value       = harbor_project.cluster.id
}

output "project_name" {
  description = "Harbor project name"
  value       = harbor_project.cluster.name
}

output "robot_name" {
  description = "Full robot account name"
  value       = harbor_robot_account.pull.full_name
}

output "robot_secret" {
  description = "Robot account secret (only available at creation time)"
  value       = harbor_robot_account.pull.secret
  sensitive   = true
}
