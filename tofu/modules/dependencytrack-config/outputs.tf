output "automation_api_key" {
  description = "API key for the Automation team (SBOM upload)"
  value       = dependencytrack_team_apikey.automation.key
  sensitive   = true
}

output "automation_team_id" {
  description = "UUID of the Automation team"
  value       = dependencytrack_team.automation.id
}

output "project_ids" {
  description = "Map of project names to UUIDs"
  value       = { for k, v in dependencytrack_project.apps : k => v.id }
}
