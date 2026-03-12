# Per-cluster Harbor project + robot account
#
# Proxy cache projects (docker.io, ghcr.io, quay.io) stay in harbor.nix —
# the Harbor Tofu provider doesn't support registry endpoints well.

resource "harbor_project" "cluster" {
  name   = var.cluster_name
  public = false
}

resource "harbor_robot_account" "pull" {
  name        = "pull"
  description = "Pull access for ${var.cluster_name} cluster"
  level       = "project"
  duration    = -1

  permissions {
    kind      = "project"
    namespace = harbor_project.cluster.name

    access {
      resource = "repository"
      action   = "pull"
    }
    access {
      resource = "repository"
      action   = "list"
    }
  }

  lifecycle { ignore_changes = [secret] }
}
