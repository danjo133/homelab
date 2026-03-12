"""JIT Role Elevation Service

Handles temporary privilege escalation via Keycloak Token Exchange (RFC 8693).

Endpoints:
  POST /api/elevate  - Request elevation with current access token + reason
  GET  /api/config   - Public OIDC config for the web UI
  GET  /api/audit    - View recent elevation events
  GET  /health       - Health check
  GET  /             - Web UI (SPA with PKCE OIDC flow)
"""

import json
import os
import time
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.request import urlopen, Request
from urllib.parse import urlencode
from urllib.error import URLError
from pathlib import Path

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "info").upper())
logger = logging.getLogger("jit")

KEYCLOAK_URL = os.environ["KEYCLOAK_URL"]
REALM = os.environ["KEYCLOAK_REALM"]
CLIENT_ID = os.environ["CLIENT_ID"]
CLIENT_SECRET = os.environ["CLIENT_SECRET"]
ELIGIBLE_GROUPS = os.environ.get("ELIGIBLE_GROUPS", "platform-admins,k8s-admins").split(",")
MAX_DURATION = int(os.environ.get("MAX_DURATION", "300"))
COOLDOWN = int(os.environ.get("COOLDOWN", "900"))

TOKEN_ENDPOINT = f"{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/token"
USERINFO_ENDPOINT = f"{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/userinfo"

STATIC_DIR = Path(__file__).parent / "static"

# In-memory audit log and cooldown tracker
audit_log = []
last_elevation = {}  # user -> timestamp


def get_userinfo(access_token):
    """Validate token and get user info from Keycloak."""
    req = Request(USERINFO_ENDPOINT, headers={
        "Authorization": f"Bearer {access_token}"
    })
    with urlopen(req) as resp:
        return json.loads(resp.read())


def token_exchange(subject_token, requested_token_type="urn:ietf:params:oauth:token-type:access_token"):
    """Perform RFC 8693 Token Exchange to get elevated token."""
    data = urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "subject_token": subject_token,
        "subject_token_type": "urn:ietf:params:oauth:token-type:access_token",
        "requested_token_type": requested_token_type,
        "audience": CLIENT_ID,
    }).encode()

    req = Request(TOKEN_ENDPOINT, data=data, headers={
        "Content-Type": "application/x-www-form-urlencoded"
    })
    with urlopen(req) as resp:
        return json.loads(resp.read())


# Cache the index.html in memory at startup
_index_html = (STATIC_DIR / "index.html").read_bytes()


class JITHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/health":
            self.send_json(200, {"status": "ok"})
        elif path == "/api/config":
            self.send_json(200, {
                "keycloak_url": KEYCLOAK_URL,
                "realm": REALM,
                "client_id": "kubernetes",
                "eligible_groups": ELIGIBLE_GROUPS,
                "max_duration": MAX_DURATION,
            })
        elif path == "/api/audit":
            self.send_json(200, {"events": audit_log[-100:]})
        elif path in ("/", "/callback"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(_index_html)
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/api/elevate":
            self.send_json(404, {"error": "not found"})
            return

        content_length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(content_length)) if content_length > 0 else {}

        auth_header = self.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            self.send_json(401, {"error": "Missing Bearer token"})
            return

        access_token = auth_header[7:]
        reason = body.get("reason", "")
        duration = min(int(body.get("duration", MAX_DURATION)), MAX_DURATION)

        if not reason:
            self.send_json(400, {"error": "Reason is required"})
            return

        try:
            userinfo = get_userinfo(access_token)
        except URLError as e:
            logger.error(f"Failed to validate token: {e}")
            self.send_json(401, {"error": "Invalid or expired token"})
            return

        username = userinfo.get("preferred_username", "unknown")
        groups = userinfo.get("groups", [])

        eligible = any(g in ELIGIBLE_GROUPS for g in groups)
        if not eligible:
            logger.warning(f"User {username} not in eligible groups: {groups}")
            self.send_json(403, {"error": "Not authorized for elevation",
                                 "groups": groups,
                                 "eligible_groups": ELIGIBLE_GROUPS})
            return

        now = time.time()
        last = last_elevation.get(username, 0)
        if now - last < COOLDOWN:
            remaining = int(COOLDOWN - (now - last))
            self.send_json(429, {"error": f"Cooldown active, try again in {remaining}s",
                                 "retry_after": remaining})
            return

        try:
            result = token_exchange(access_token)
        except URLError as e:
            logger.error(f"Token exchange failed for {username}: {e}")
            self.send_json(502, {"error": "Token exchange failed"})
            return

        last_elevation[username] = now
        event = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "user": username,
            "reason": reason,
            "duration": duration,
            "groups": groups,
        }
        audit_log.append(event)
        logger.info(f"ELEVATION: {json.dumps(event)}")

        self.send_json(200, {
            "access_token": result.get("access_token"),
            "token_type": result.get("token_type", "Bearer"),
            "expires_in": result.get("expires_in", duration),
            "user": username,
            "elevated": True,
        })

    def send_json(self, status, data):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.end_headers()

    def log_message(self, format, *args):
        logger.debug(format % args)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    server = HTTPServer(("0.0.0.0", port), JITHandler)
    logger.info(f"JIT Elevation Service starting on port {port}")
    server.serve_forever()
