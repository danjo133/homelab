# Dependency-Track configuration via SolarFactories/dependencytrack provider
#
# Manages teams, API keys, OIDC group mappings, and projects.
# Requires Dependency-Track to be running and accessible.

# ============================================================================
# Automation team — used by CronJobs and GitLab CI to upload SBOMs
# ============================================================================

resource "dependencytrack_team" "automation" {
  name = "Automation"
}

resource "dependencytrack_team_permissions" "automation" {
  team = dependencytrack_team.automation.id
  permissions = [
    "BOM_UPLOAD",
    "PORTFOLIO_MANAGEMENT",
    "PROJECT_CREATION_UPLOAD",
    "VIEW_PORTFOLIO",
  ]
}

resource "dependencytrack_team_apikey" "automation" {
  team    = dependencytrack_team.automation.id
  comment = "Managed by OpenTofu — used by SBOM upload CronJob and GitLab CI"
}

# ============================================================================
# OIDC teams and group mappings — map Keycloak groups to DT permissions
# ============================================================================

resource "dependencytrack_team" "oidc" {
  for_each = var.oidc_groups
  name     = each.key
}

resource "dependencytrack_team_permissions" "oidc" {
  for_each    = var.oidc_groups
  team        = dependencytrack_team.oidc[each.key].id
  permissions = each.value.permissions
}

resource "dependencytrack_oidc_group" "groups" {
  for_each = var.oidc_groups
  name     = each.key
}

resource "dependencytrack_oidc_group_mapping" "mappings" {
  for_each = var.oidc_groups
  group    = dependencytrack_oidc_group.groups[each.key].id
  team     = dependencytrack_team.oidc[each.key].id
}

# ============================================================================
# Projects — pre-create for each tracked application
# ============================================================================

resource "dependencytrack_project" "apps" {
  for_each    = var.projects
  name        = each.key
  description = each.value.description
  classifier  = each.value.classifier
  active      = true
}

# ============================================================================
# Vulnerability sources — enable OSV for PURL-based matching
# ============================================================================

# NVD only matches CPEs; Trivy SBOMs use PURLs. OSV matches PURLs and
# aggregates data from GitHub Advisories, Go vuln DB, PyPI, Alpine, etc.
resource "dependencytrack_config_property" "osv_ecosystems" {
  group = "vuln-source"
  name  = "google.osv.enabled"
  type  = "STRING"
  value = var.osv_ecosystems
}

resource "dependencytrack_config_property" "osv_alias_sync" {
  group = "vuln-source"
  name  = "google.osv.alias.sync.enabled"
  type  = "BOOLEAN"
  value = "true"
}

# OIDC configuration is set via ALPINE_OIDC_* env vars in the Helm values.
# DT 4.14 does not expose these as config properties via the API.
