# Harbor apps project + robot accounts
#
# Creates a shared "apps" project for custom application images (portal,
# jit-elevation, cluster-setup, architecture, etc.) and push/pull robot
# accounts for CI and cluster consumption.

resource "harbor_project" "apps" {
  name                   = "apps"
  public                 = false
  vulnerability_scanning = false
  force_destroy          = false
  storage_quota          = -1
}

resource "harbor_robot_account" "push" {
  name        = "push"
  description = "CI push account for apps images"
  level       = "project"
  duration    = -1

  permissions {
    kind      = "project"
    namespace = harbor_project.apps.name

    access {
      resource = "repository"
      action   = "push"
    }
    access {
      resource = "repository"
      action   = "pull"
    }
    access {
      resource = "repository"
      action   = "list"
    }
    access {
      resource = "tag"
      action   = "create"
    }
    access {
      resource = "tag"
      action   = "list"
    }
  }

  lifecycle { ignore_changes = [secret] }
}

resource "harbor_robot_account" "pull" {
  name        = "pull"
  description = "Pull account for apps images"
  level       = "project"
  duration    = -1

  permissions {
    kind      = "project"
    namespace = harbor_project.apps.name

    access {
      resource = "repository"
      action   = "pull"
    }
    access {
      resource = "repository"
      action   = "list"
    }
    access {
      resource = "tag"
      action   = "list"
    }
  }

  lifecycle { ignore_changes = [secret] }
}
