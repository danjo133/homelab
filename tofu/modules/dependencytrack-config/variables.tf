# Dependency-Track configuration module variables

variable "oidc_groups" {
  description = "Keycloak groups to map to DT teams with their DT permissions"
  type = map(object({
    permissions = list(string)
  }))
  default = {
    "platform-admins" = {
      permissions = [
        "ACCESS_MANAGEMENT",
        "BOM_UPLOAD",
        "POLICY_MANAGEMENT",
        "POLICY_VIOLATION_ANALYSIS",
        "PROJECT_CREATION_UPLOAD",
        "SYSTEM_CONFIGURATION",
        "VIEW_PORTFOLIO",
        "VIEW_VULNERABILITY",
        "VULNERABILITY_ANALYSIS",
        "VULNERABILITY_MANAGEMENT",
      ]
    }
    "k8s-admins" = {
      permissions = [
        "BOM_UPLOAD",
        "PROJECT_CREATION_UPLOAD",
        "VIEW_PORTFOLIO",
        "VIEW_VULNERABILITY",
        "VULNERABILITY_ANALYSIS",
      ]
    }
    "app-users" = {
      permissions = [
        "VIEW_PORTFOLIO",
        "VIEW_VULNERABILITY",
      ]
    }
  }
}

variable "osv_ecosystems" {
  description = "Semicolon-separated list of OSV ecosystems to mirror (PURL-based vuln matching)"
  type        = string
  default     = "Go;Alpine;Debian;npm;PyPI;Maven;crates.io;NuGet;Packagist;RubyGems"
}

variable "projects" {
  description = "DT projects to pre-create for SBOM tracking"
  type = map(object({
    description = optional(string, "")
    classifier  = optional(string, "APPLICATION")
  }))
  default = {
    "portal"           = { description = "Portal service discovery dashboard" }
    "jit-elevation"    = { description = "JIT privilege elevation service" }
    "cluster-setup"    = { description = "Self-service kubeconfig tool" }
    "architecture"     = { description = "LikeC4 architecture visualization" }
    "openclaw"         = { description = "Case management system" }
    "support-vm-nixos" = { description = "NixOS support VM system packages", classifier = "OPERATING_SYSTEM" }
  }
}
