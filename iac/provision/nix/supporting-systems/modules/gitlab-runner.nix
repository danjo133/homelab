# GitLab Runner — Docker executor for CI/CD builds
# Registers as an instance-wide runner via the GitLab API
# Runs builds in unprivileged Docker containers

{ config, pkgs, lib, ... }:

let
  runnerDir = "/var/lib/gitlab-runner";
  configFile = "/etc/gitlab-runner/config.toml";

  runnerSetupScript = pkgs.writeShellScript "gitlab-runner-setup" ''
    set -eu

    export PATH="${lib.makeBinPath [
      pkgs.curl pkgs.jq pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.openssl
    ]}"

    GITLAB_URL="http://127.0.0.1:8929"
    GITLAB_API="$GITLAB_URL/api/v4"
    RUNNER_DIR="${runnerDir}"
    CONFIG_FILE="${configFile}"
    SETUP_MARKER="$RUNNER_DIR/.setup-complete"
    TOKEN_FILE="$RUNNER_DIR/runner-token"

    if [ -f "$SETUP_MARKER" ]; then
      echo "GitLab Runner already registered"
      exit 0
    fi

    echo "==> GitLab Runner Setup"

    # Wait for GitLab API
    echo "Waiting for GitLab API..."
    for i in $(seq 1 120); do
      if curl -sf -H "X-Forwarded-Proto: https" -H "Host: gitlab.support.example.com" "$GITLAB_URL/users/sign_in" >/dev/null 2>&1; then
        echo "GitLab API is ready"
        break
      fi
      if [ "$i" -eq 120 ]; then
        echo "ERROR: GitLab not ready after 20 minutes"
        exit 1
      fi
      sleep 10
    done

    # Get admin OAuth token
    ADMIN_PASSWORD=$(cat /etc/gitlab/admin_password)
    OAUTH_RESPONSE=$(curl -sf -H "X-Forwarded-Proto: https" -X POST "$GITLAB_URL/oauth/token" \
      -d "grant_type=password&username=root&password=$ADMIN_PASSWORD")
    ACCESS_TOKEN=$(echo "$OAUTH_RESPONSE" | jq -r '.access_token')

    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
      echo "ERROR: Failed to get OAuth token"
      exit 1
    fi

    # Create instance-wide runner via API
    echo "==> Registering runner..."
    RUNNER_RESPONSE=$(curl -sf -X POST "$GITLAB_API/user/runners" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "X-Forwarded-Proto: https" \
      -H "Content-Type: application/json" \
      -d '{
        "runner_type": "instance_type",
        "description": "support-vm-docker",
        "tag_list": ["docker", "kaniko"],
        "run_untagged": true,
        "locked": false
      }')

    RUNNER_TOKEN=$(echo "$RUNNER_RESPONSE" | jq -r '.token')
    if [ -z "$RUNNER_TOKEN" ] || [ "$RUNNER_TOKEN" = "null" ]; then
      echo "ERROR: Failed to create runner: $RUNNER_RESPONSE"
      exit 1
    fi

    echo "$RUNNER_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    echo "  Runner registered (token stored)"

    # Generate config.toml
    echo "==> Generating config.toml..."
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << TOMLEOF
concurrent = 4
check_interval = 5

[[runners]]
  name = "support-vm-docker"
  url = "$GITLAB_URL"
  token = "$RUNNER_TOKEN"
  executor = "docker"
  [runners.docker]
    image = "harbor.support.example.com/docker.io/library/alpine:latest"
    privileged = false
    disable_entrypoint_overwrite = false
    oom_kill_disable = false
    disable_cache = false
    volumes = ["/cache"]
    shm_size = 0
    pull_policy = ["if-not-present"]
    network_mode = "host"
TOMLEOF

    chmod 600 "$CONFIG_FILE"
    touch "$SETUP_MARKER"
    echo "==> GitLab Runner setup complete"
  '';
in
{
  # Runner setup service — registers runner with GitLab
  systemd.services.gitlab-runner-setup = {
    description = "GitLab Runner Registration";
    requires = [ "gitlab-setup.service" "docker.service" ];
    after = [ "gitlab-setup.service" "docker.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = runnerSetupScript;
      TimeoutStartSec = "30min";
    };

    unitConfig = {
      StartLimitIntervalSec = 0;
    };
  };

  # Runner service — runs the gitlab-runner process
  systemd.services.gitlab-runner = {
    description = "GitLab Runner";
    requires = [ "gitlab-runner-setup.service" "docker.service" ];
    after = [ "gitlab-runner-setup.service" "docker.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.gitlab-runner}/bin/gitlab-runner run --config ${configFile}";
      Restart = "always";
      RestartSec = "10s";
    };
  };

  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d ${runnerDir} 0750 root root -"
    "d /etc/gitlab-runner 0750 root root -"
  ];

  # Install gitlab-runner
  environment.systemPackages = [ pkgs.gitlab-runner ];
}
