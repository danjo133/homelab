{{- $ctx := (ds "ctx") -}}
{{- $portalPrefix := $ctx.config.portalPrefix -}}
# Dependency-Track — {{ $ctx.computed.name }} cluster overrides

apiServer:
  extraEnv:
    - name: ALPINE_DATABASE_MODE
      value: "external"
    - name: ALPINE_DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: dependency-track-db-credentials
          key: database-url
    - name: ALPINE_DATABASE_DRIVER
      value: "org.postgresql.Driver"
    - name: ALPINE_DATABASE_USERNAME
      valueFrom:
        secretKeyRef:
          name: dependency-track-db-credentials
          key: username
    - name: ALPINE_DATABASE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: dependency-track-db-credentials
          key: password
    - name: ALPINE_OIDC_ENABLED
      value: "true"
    - name: ALPINE_OIDC_CLIENT_ID
      value: "dependency-track"
    - name: ALPINE_OIDC_ISSUER
      value: "https://auth.{{ $ctx.computed.domain }}/realms/broker"
    - name: ALPINE_OIDC_USERNAME_CLAIM
      value: "preferred_username"
    - name: ALPINE_OIDC_TEAMS_CLAIM
      value: "groups"
    - name: ALPINE_OIDC_USER_PROVISIONING
      value: "true"
    - name: ALPINE_OIDC_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: dependency-track-oidc
          key: client-secret
    - name: ALPINE_OIDC_TEAM_SYNCHRONIZATION
      value: "true"

frontend:
  apiBaseUrl: "https://dtrack.{{ $ctx.computed.domain }}"
  extraEnv:
    - name: OIDC_ISSUER
      value: "https://auth.{{ $ctx.computed.domain }}/realms/broker"
    - name: OIDC_CLIENT_ID
      value: "dependency-track"
    - name: OIDC_FLOW
      value: "code"
    - name: OIDC_LOGIN_BUTTON_TEXT
      value: "Log in with SSO"

ingress:
{{- if $ctx.computed.isIstioMesh }}
  enabled: false  # Uses Gateway API HTTPRoute
{{- else }}
  enabled: true
  ingressClassName: nginx
  annotations:
    {{ $portalPrefix }}/name: "Dependency-Track"
    {{ $portalPrefix }}/description: "SBOM management & vulnerability tracking"
    {{ $portalPrefix }}/icon: "\U0001F6E1"
    {{ $portalPrefix }}/category: "Security"
    {{ $portalPrefix }}/order: "50"
  hostname: dtrack.{{ $ctx.computed.domain }}
{{- end }}
