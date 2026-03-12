output "push_robot_name" {
  description = "Full push robot account name"
  value       = harbor_robot_account.push.full_name
}

output "push_robot_secret" {
  description = "Push robot account secret (only available at creation time)"
  value       = harbor_robot_account.push.secret
  sensitive   = true
}

output "pull_robot_name" {
  description = "Full pull robot account name"
  value       = harbor_robot_account.pull.full_name
}

output "pull_robot_secret" {
  description = "Pull robot account secret (only available at creation time)"
  value       = harbor_robot_account.pull.secret
  sensitive   = true
}
