# KV secrets — NOT managed by OpenTofu.
#
# The following Vault KV secrets are seeded by support VM services, bootstrap
# scripts, and the seed-broker-secrets.sh script. OpenTofu does not need to
# own them — they exist before tofu runs and are consumed via data sources
# or ExternalSecrets operators in the clusters.
#
# Removed resources (previously tracked with lifecycle { ignore_changes }):
#   keycloak/admin, keycloak/test-users, keycloak/teleport-client,
#   keycloak/gitlab-client, keycloak/db-credentials, open-webui/db-credentials,
#   oauth2-proxy, harbor/<cluster>-pull,
#   grafana/admin, minio/loki-<cluster>,
#   gitlab/ssh-host-keys, gitlab/apps-token
#
# Now managed by OpenTofu (base environment):
#   harbor/admin, harbor/apps-push, harbor/apps-pull,
#   cloudflare, grafana/admin, keycloak/db-credentials,
#   open-webui/db-credentials, oauth2-proxy, minio/loki-<cluster>
#
# Now managed by OpenTofu (per-cluster environment):
#   harbor/<cluster>-pull
#
# Now managed by OpenTofu (convenience namespace):
#   keycloak/admin, keycloak/test-users, keycloak/teleport-client,
#   keycloak/gitlab-client, gitlab/admin, ziti/admin, teleport/admin,
#   minio/admin, harbor/admin
#
# If migrating from an existing deployment, run:
#   just tofu-migrate-secrets
# to remove these from the tofu state without destroying the actual secrets.
