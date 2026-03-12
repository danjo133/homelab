# GitHub → GitLab mirror sync
# Systemd timer that discovers repos in a GitHub org and mirrors them to GitLab
# Runs every 10 minutes, creates GitLab projects with CI config from kss repo

{ config, pkgs, lib, ... }:

let
  deployConfig = import ../generated-config.nix;
  vaultAddr = "http://127.0.0.1:8200";
  keysFile = "/var/lib/openbao/init-keys.json";
  configDir = "/etc/github-mirror";
  stateDir = "/var/lib/github-mirror";

  mirrorScript = pkgs.writeShellScript "github-mirror-sync" ''
    set -eu

    export PATH="${lib.makeBinPath [
      pkgs.curl pkgs.jq pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.openssl pkgs.git pkgs.openssh
    ]}"
    export HOME=/tmp

    GITLAB_URL="http://127.0.0.1:8929"
    GITLAB_API="$GITLAB_URL/api/v4"
    CONFIG_DIR="${configDir}"
    STATE_DIR="${stateDir}"
    VAULT_ADDR="${vaultAddr}"
    KEYS_FILE="${keysFile}"
    TOKEN_FILE="$CONFIG_DIR/gitlab-token"
    ORG_FILE="$CONFIG_DIR/github-org"
    GITHUB_TOKEN_FILE="/run/secrets/github_token"
    # Read GitHub org name
    if [ -f "$ORG_FILE" ]; then
      GITHUB_ORG=$(cat "$ORG_FILE")
    else
      GITHUB_ORG="${deployConfig.githubOrg}"
    fi

    echo "==> GitHub Mirror Sync (org: $GITHUB_ORG)"

    # Build GitHub auth header if token exists
    GITHUB_AUTH=""
    if [ -f "$GITHUB_TOKEN_FILE" ]; then
      GITHUB_AUTH="-H \"Authorization: token $(cat "$GITHUB_TOKEN_FILE")\""
    fi

    # --- Ensure GitLab admin PAT ---
    if [ -f "$TOKEN_FILE" ]; then
      GITLAB_TOKEN=$(cat "$TOKEN_FILE")
    else
      echo "==> Creating GitLab admin PAT..."

      # Wait for GitLab API
      for i in $(seq 1 60); do
        if curl -sf -H "X-Forwarded-Proto: https" -H "Host: gitlab.${deployConfig.domain}" "$GITLAB_URL/users/sign_in" >/dev/null 2>&1; then
          break
        fi
        if [ "$i" -eq 60 ]; then
          echo "ERROR: GitLab not ready after 10 minutes"
          exit 1
        fi
        sleep 10
      done

      ADMIN_PASSWORD=$(cat /etc/gitlab/admin_password)

      # Get OAuth token for API access
      OAUTH_RESPONSE=$(curl -sf -H "X-Forwarded-Proto: https" -X POST "$GITLAB_URL/oauth/token" \
        -d "grant_type=password&username=root&password=$ADMIN_PASSWORD")
      ACCESS_TOKEN=$(echo "$OAUTH_RESPONSE" | jq -r '.access_token')

      if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
        echo "ERROR: Failed to get OAuth token"
        exit 1
      fi

      # Create a personal access token with api scope (expires in 1 year)
      EXPIRY=$(date -d "+365 days" +%Y-%m-%d)
      PAT_RESPONSE=$(curl -sf -X POST "$GITLAB_API/users/1/personal_access_tokens" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "X-Forwarded-Proto: https" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg exp "$EXPIRY" '{name: "github-mirror", scopes: ["api"], expires_at: $exp}')")
      GITLAB_TOKEN=$(echo "$PAT_RESPONSE" | jq -r '.token')

      if [ -z "$GITLAB_TOKEN" ] || [ "$GITLAB_TOKEN" = "null" ]; then
        echo "ERROR: Failed to create PAT"
        exit 1
      fi

      echo "$GITLAB_TOKEN" > "$TOKEN_FILE"
      chmod 600 "$TOKEN_FILE"
      echo "  PAT created and stored"
    fi

    GL_AUTH="-H \"PRIVATE-TOKEN: $GITLAB_TOKEN\""

    # --- Ensure 'apps' group exists ---
    echo "==> Ensuring GitLab 'apps' group..."
    APPS_GROUP_ID=$(curl -sf "$GITLAB_API/groups?search=apps" \
      -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H "X-Forwarded-Proto: https" | jq -r '.[] | select(.path == "apps") | .id')

    if [ -z "$APPS_GROUP_ID" ] || [ "$APPS_GROUP_ID" = "null" ]; then
      echo "  Creating 'apps' group..."
      APPS_GROUP_ID=$(curl -sf -X POST "$GITLAB_API/groups" \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H "X-Forwarded-Proto: https" \
        -H "Content-Type: application/json" \
        -d '{"name": "apps", "path": "apps", "visibility": "internal"}' | jq -r '.id')
      echo "  Created group id=$APPS_GROUP_ID"
    else
      echo "  Group 'apps' exists (id=$APPS_GROUP_ID)"
    fi

    # --- Grant argocd user Reporter access to apps group ---
    echo "==> Granting argocd user access to apps group..."
    ARGOCD_USER_ID=$(curl -sf "$GITLAB_API/users?username=argocd" \
      -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H "X-Forwarded-Proto: https" | jq -r '.[0].id')

    if [ -n "$ARGOCD_USER_ID" ] && [ "$ARGOCD_USER_ID" != "null" ]; then
      # Check existing membership
      EXISTING=$(curl -sf "$GITLAB_API/groups/$APPS_GROUP_ID/members/$ARGOCD_USER_ID" \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H "X-Forwarded-Proto: https" 2>/dev/null | jq -r '.id // empty')
      if [ -z "$EXISTING" ]; then
        curl -sf -X POST "$GITLAB_API/groups/$APPS_GROUP_ID/members" \
          -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H "X-Forwarded-Proto: https" \
          -H "Content-Type: application/json" \
          -d "{\"user_id\": $ARGOCD_USER_ID, \"access_level\": 20}" || true
        echo "  Granted Reporter access"
      else
        echo "  argocd already a member"
      fi
    else
      echo "  WARNING: argocd user not found in GitLab (will retry next run)"
    fi

    # --- Set group CI/CD variables (Harbor push credentials) ---
    echo "==> Setting group CI/CD variables..."
    if [ -f "$KEYS_FILE" ]; then
      ROOT_TOKEN=$(jq -r '.root_token' "$KEYS_FILE")

      # Read push robot credentials from Vault (kss namespace — same creds for all)
      PUSH_CREDS=$(curl -sf \
        -H "X-Vault-Token: $ROOT_TOKEN" \
        -H "X-Vault-Namespace: kss" \
        "$VAULT_ADDR/v1/secret/data/harbor/apps-push" 2>/dev/null | jq -r '.data.data // empty')

      if [ -n "$PUSH_CREDS" ] && [ "$PUSH_CREDS" != "null" ]; then
        PUSH_USER=$(echo "$PUSH_CREDS" | jq -r '.username')
        PUSH_PASS=$(echo "$PUSH_CREDS" | jq -r '.password')

        for VAR_KEY in HARBOR_PUSH_USER HARBOR_PUSH_PASSWORD; do
          if [ "$VAR_KEY" = "HARBOR_PUSH_USER" ]; then
            VAR_VAL="$PUSH_USER"
            MASKED="false"
          else
            VAR_VAL="$PUSH_PASS"
            MASKED="true"
          fi

          # Delete existing variable (ignore errors)
          curl -sf -X DELETE "$GITLAB_API/groups/$APPS_GROUP_ID/variables/$VAR_KEY" \
            -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H "X-Forwarded-Proto: https" 2>/dev/null || true

          curl -sf -X POST "$GITLAB_API/groups/$APPS_GROUP_ID/variables" \
            -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H "X-Forwarded-Proto: https" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg key "$VAR_KEY" --arg val "$VAR_VAL" --argjson masked "$MASKED" \
              '{key: $key, value: $val, masked: $masked, protected: false, raw: true}')" >/dev/null
          echo "  Set $VAR_KEY"
        done
      else
        echo "  WARNING: Harbor apps-push credentials not in Vault yet"
      fi
    fi

    # --- Store GitLab PAT in Vault for ArgoCD SCM Provider ---
    if [ -f "$KEYS_FILE" ]; then
      ROOT_TOKEN=$(jq -r '.root_token' "$KEYS_FILE")
      for VAULT_NS in kss kcs; do
        if curl -sf -X POST \
          -H "X-Vault-Token: $ROOT_TOKEN" \
          -H "X-Vault-Namespace: $VAULT_NS" \
          -H "Content-Type: application/json" \
          -d "$(jq -n --arg token "$GITLAB_TOKEN" '{data: {token: $token}}')" \
          "$VAULT_ADDR/v1/secret/data/gitlab/apps-token" >/dev/null; then
          echo "  Stored gitlab/apps-token in $VAULT_NS"
        else
          echo "  WARNING: Could not store gitlab/apps-token in $VAULT_NS (namespace may not exist yet)"
        fi
      done
    fi

    # --- Store GitLab SSH host keys in Vault ---
    echo "==> Scanning GitLab SSH host keys..."
    SSH_HOST_KEYS=$(ssh-keyscan -p 2222 -t ed25519,ecdsa-sha2-nistp256,rsa 127.0.0.1 2>/dev/null \
      | sed 's/^\[127\.0\.0\.1\]:2222/[gitlab.${deployConfig.domain}]:2222/')

    if [ -n "$SSH_HOST_KEYS" ] && [ -f "$KEYS_FILE" ]; then
      ROOT_TOKEN=$(jq -r '.root_token' "$KEYS_FILE")
      for VAULT_NS in kss kcs; do
        if curl -sf -X POST \
          -H "X-Vault-Token: $ROOT_TOKEN" \
          -H "X-Vault-Namespace: $VAULT_NS" \
          -H "Content-Type: application/json" \
          -d "$(jq -n --arg keys "$SSH_HOST_KEYS" '{data: {known_hosts: $keys}}')" \
          "$VAULT_ADDR/v1/secret/data/gitlab/ssh-host-keys" >/dev/null; then
          echo "  Stored gitlab/ssh-host-keys in $VAULT_NS"
        else
          echo "  WARNING: Could not store gitlab/ssh-host-keys in $VAULT_NS (namespace may not exist yet)"
        fi
      done
    fi

    # --- Discover GitHub repos and mirror ---
    echo "==> Discovering GitHub repos in '$GITHUB_ORG'..."

    # Build GitHub clone URL prefix with auth
    if [ -f "$GITHUB_TOKEN_FILE" ]; then
      GH_TOKEN=$(cat "$GITHUB_TOKEN_FILE")
      GH_CLONE_PREFIX="https://oauth2:$GH_TOKEN@github.com"
    else
      GH_TOKEN=""
      GH_CLONE_PREFIX="https://github.com"
    fi

    # Fetch all repos from GitHub org (paginated)
    PAGE=1
    ALL_REPOS=""
    while true; do
      if [ -n "$GH_TOKEN" ]; then
        RESPONSE=$(curl -sf "https://api.github.com/orgs/$GITHUB_ORG/repos?per_page=100&page=$PAGE" \
          -H "Authorization: token $GH_TOKEN")
      else
        RESPONSE=$(curl -sf "https://api.github.com/orgs/$GITHUB_ORG/repos?per_page=100&page=$PAGE")
      fi

      COUNT=$(echo "$RESPONSE" | jq 'length')
      if [ "$COUNT" -eq 0 ]; then
        break
      fi

      ALL_REPOS="$ALL_REPOS$(echo "$RESPONSE" | jq -r '.[] | .name')
"
      PAGE=$((PAGE + 1))
    done

    if [ -z "$ALL_REPOS" ]; then
      echo "  No repos found in GitHub org '$GITHUB_ORG'"
      exit 0
    fi

    # Configure git for push auth
    GITLAB_PUSH_URL="http://root:$(cat /etc/gitlab/admin_password)@127.0.0.1:8929"
    MIRROR_DIR="$STATE_DIR/repos"
    mkdir -p "$MIRROR_DIR"

    echo "$ALL_REPOS" | while IFS= read -r REPO_NAME; do
      [ -z "$REPO_NAME" ] && continue
      echo "  Processing: $REPO_NAME"

      # Ensure GitLab project exists
      EXISTING_ID=$(curl -sf "$GITLAB_API/groups/$APPS_GROUP_ID/projects?search=$REPO_NAME" \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H "X-Forwarded-Proto: https" | jq -r ".[] | select(.path == \"$REPO_NAME\") | .id")

      if [ -z "$EXISTING_ID" ] || [ "$EXISTING_ID" = "null" ]; then
        echo "    Creating GitLab project..."
        curl -sf -X POST "$GITLAB_API/projects" \
          -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H "X-Forwarded-Proto: https" \
          -H "Content-Type: application/json" \
          -d "$(jq -n \
            --arg name "$REPO_NAME" \
            --arg path "$REPO_NAME" \
            --argjson nsid "$APPS_GROUP_ID" \
            --arg ci_config "ci/mirror-build.gitlab-ci.yml@infra/kss" \
            '{
              name: $name,
              path: $path,
              namespace_id: $nsid,
              ci_config_path: $ci_config,
              visibility: "internal"
            }')" >/dev/null && echo "    Created" || { echo "    WARNING: Failed to create"; continue; }
      fi

      # Git mirror: bare clone from GitHub, push to GitLab
      REPO_DIR="$MIRROR_DIR/$REPO_NAME.git"
      GH_URL="$GH_CLONE_PREFIX/$GITHUB_ORG/$REPO_NAME.git"
      GL_URL="$GITLAB_PUSH_URL/apps/$REPO_NAME.git"

      if [ -d "$REPO_DIR" ]; then
        # Ensure fetch refspec is configured (bare clones don't set one)
        git -C "$REPO_DIR" config remote.origin.fetch '+refs/heads/*:refs/heads/*' 2>/dev/null
        echo "    Fetching updates..."
        git -C "$REPO_DIR" fetch --prune origin 2>&1 | sed 's/^/    /' || { echo "    WARNING: fetch failed"; continue; }
      else
        echo "    Cloning bare repo..."
        git clone --bare "$GH_URL" "$REPO_DIR" 2>&1 | sed 's/^/    /' || { echo "    WARNING: clone failed"; continue; }
        git -C "$REPO_DIR" config remote.origin.fetch '+refs/heads/*:refs/heads/*'
      fi

      echo "    Pushing to GitLab..."
      git -C "$REPO_DIR" push --mirror "$GL_URL" 2>&1 | sed 's/^/    /' || echo "    WARNING: push failed"
    done

    echo "==> GitHub mirror sync complete"
  '';
in
{
  # Timer: run mirror sync every 10 minutes
  systemd.timers.github-mirror = {
    description = "GitHub Mirror Sync Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "10min";
      RandomizedDelaySec = "30s";
    };
  };

  systemd.services.github-mirror = {
    description = "GitHub → GitLab Mirror Sync";
    after = [ "gitlab-setup.service" "harbor-apps-project.service" ];
    wants = [ "gitlab-setup.service" "harbor-apps-project.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = mirrorScript;
      TimeoutStartSec = "10min";
    };
  };

  # Ensure config directory exists
  systemd.tmpfiles.rules = [
    "d ${configDir} 0750 root root -"
    "d ${stateDir} 0750 root root -"
  ];
}
