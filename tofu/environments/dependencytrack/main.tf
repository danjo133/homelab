# Dependency-Track environment
#
# Manages DT configuration (teams, API keys, OIDC mappings, projects) and
# writes the automation API key to Vault for CronJobs and CI to consume.
#
# Separated from the base environment so that `just tofu base` does not
# require Dependency-Track to be running.

module "dependencytrack_config" {
  source = "../../modules/dependencytrack-config"
}

# Write the DT automation API key to Vault for CronJobs and CI to consume
resource "vault_kv_secret_v2" "dependency_track_api_key" {
  namespace = var.cluster_name
  mount     = "secret"
  name      = "dependency-track/api-key"

  data_json = jsonencode({
    "api-key" = module.dependencytrack_config.automation_api_key
  })
}
