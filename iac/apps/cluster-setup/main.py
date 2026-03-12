"""Cluster Setup Service

Self-service web UI for viewing OIDC token info and downloading kubeconfig.
Sits behind OAuth2-Proxy which handles all authentication.

Endpoints:
  GET  /             - Serve web UI
  GET  /health       - Health check
  GET  /api/token-info  - Decode JWT from OAuth2-Proxy headers
  GET  /api/kubeconfig  - Generate OIDC kubeconfig YAML download
"""

import base64
import json
import os
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "info").upper())
logger = logging.getLogger("cluster-setup")

CLUSTER_NAME = os.environ["CLUSTER_NAME"]
CLUSTER_DOMAIN = os.environ["CLUSTER_DOMAIN"]
KEYCLOAK_URL = os.environ["KEYCLOAK_URL"]
API_SERVER = os.environ["API_SERVER"]

STATIC_DIR = Path(__file__).parent / "static"

_index_html = (STATIC_DIR / "index.html").read_bytes()


def decode_jwt_payload(token):
    """Decode JWT payload without verification (OAuth2-Proxy already validated it)."""
    parts = token.split(".")
    if len(parts) != 3:
        return None
    payload = parts[1]
    # Add padding
    padding = 4 - len(payload) % 4
    if padding != 4:
        payload += "=" * padding
    try:
        decoded = base64.urlsafe_b64decode(payload)
        return json.loads(decoded)
    except Exception:
        return None


def generate_kubeconfig():
    """Generate OIDC kubeconfig YAML from environment variables."""
    return f"""apiVersion: v1
kind: Config
clusters:
- cluster:
    server: {API_SERVER}
    insecure-skip-tls-verify: true
  name: {CLUSTER_NAME}-oidc
contexts:
- context:
    cluster: {CLUSTER_NAME}-oidc
    user: oidc-user
  name: {CLUSTER_NAME}-oidc
current-context: {CLUSTER_NAME}-oidc
users:
- name: oidc-user
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: kubectl
      args:
        - oidc-login
        - get-token
        - --oidc-issuer-url={KEYCLOAK_URL}/realms/broker
        - --oidc-client-id=kubernetes
        - --oidc-extra-scope=groups
        - --oidc-extra-scope=email
"""


class SetupHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/health":
            self.send_json(200, {"status": "ok"})
        elif path == "/api/token-info":
            self.handle_token_info()
        elif path == "/api/kubeconfig":
            self.handle_kubeconfig()
        elif path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(_index_html)
        else:
            self.send_json(404, {"error": "not found"})

    def handle_token_info(self):
        access_token = self.headers.get("X-Auth-Request-Access-Token", "")
        user = self.headers.get("X-Auth-Request-User", "")
        email = self.headers.get("X-Auth-Request-Email", "")
        groups = self.headers.get("X-Auth-Request-Groups", "")

        if not access_token:
            self.send_json(401, {"error": "No access token found in headers"})
            return

        claims = decode_jwt_payload(access_token)
        if claims is None:
            self.send_json(400, {"error": "Failed to decode JWT"})
            return

        self.send_json(200, {
            "user": user,
            "email": email,
            "groups": groups.split(",") if groups else [],
            "claims": claims,
            "raw_token": access_token,
        })

    def handle_kubeconfig(self):
        kubeconfig = generate_kubeconfig()
        filename = f"kubeconfig-{CLUSTER_NAME}-oidc.yaml"
        self.send_response(200)
        self.send_header("Content-Type", "application/x-yaml")
        self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
        self.end_headers()
        self.wfile.write(kubeconfig.encode())

    def send_json(self, status, data):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, format, *args):
        logger.debug(format % args)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    server = HTTPServer(("0.0.0.0", port), SetupHandler)
    logger.info(f"Cluster Setup Service starting on port {port}")
    server.serve_forever()
