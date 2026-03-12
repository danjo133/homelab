"""Cluster Portal

Landing page that discovers services via Kubernetes Ingress and HTTPRoute
annotations and displays them as a categorized, searchable dashboard.

Services opt in by adding ANNOTATION_PREFIX annotations (e.g. portal.example.com/*)
to their Ingress or HTTPRoute resources.

Endpoints:
  GET  /           - Serve web UI
  GET  /health     - Health check
  GET  /api/apps   - JSON list of discovered services
"""

import json
import logging
import os
import ssl
import time
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "info").upper())
logger = logging.getLogger("portal")

CLUSTER_NAME = os.environ.get("CLUSTER_NAME", "unknown")
CLUSTER_DOMAIN = os.environ.get("CLUSTER_DOMAIN", "")

STATIC_DIR = Path(__file__).parent / "static"
_index_html = (STATIC_DIR / "index.html").read_bytes()

SA_TOKEN_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/token"
SA_CA_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
K8S_API = "https://kubernetes.default.svc"
ANNOTATION_PREFIX = os.environ.get("ANNOTATION_PREFIX", "portal.example.com/")

CACHE_TTL = 30
_cache = {"data": None, "timestamp": 0}


def _k8s_get(path):
    """Make an authenticated GET request to the in-cluster K8s API."""
    try:
        token = Path(SA_TOKEN_PATH).read_text().strip()
    except FileNotFoundError:
        logger.warning("Service account token not found at %s", SA_TOKEN_PATH)
        return None

    ctx = ssl.create_default_context()
    try:
        ctx.load_verify_locations(SA_CA_PATH)
    except FileNotFoundError:
        logger.warning("CA bundle not found at %s, using default", SA_CA_PATH)

    url = f"{K8S_API}{path}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})

    try:
        with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            logger.debug("Resource not found: %s (CRDs may not be installed)", path)
        else:
            logger.warning("K8s API error %d for %s: %s", e.code, path, e.reason)
        return None
    except Exception as e:
        logger.warning("K8s API request failed for %s: %s", path, e)
        return None


def _extract_apps_from_ingresses(items):
    """Extract portal-annotated apps from Ingress resources."""
    apps = []
    for item in items:
        annotations = item.get("metadata", {}).get("annotations") or {}
        if not any(k.startswith(ANNOTATION_PREFIX) for k in annotations):
            continue
        if annotations.get(f"{ANNOTATION_PREFIX}hidden") == "true":
            continue

        name = annotations.get(f"{ANNOTATION_PREFIX}name", item["metadata"]["name"])
        description = annotations.get(f"{ANNOTATION_PREFIX}description", "")
        icon = annotations.get(f"{ANNOTATION_PREFIX}icon", "")
        category = annotations.get(f"{ANNOTATION_PREFIX}category", "Other")
        order = int(annotations.get(f"{ANNOTATION_PREFIX}order", "100"))

        # Extract URL from ingress spec
        spec = item.get("spec", {})
        host = ""
        tls_hosts = spec.get("tls", [])
        if tls_hosts and tls_hosts[0].get("hosts"):
            host = tls_hosts[0]["hosts"][0]
        elif spec.get("rules") and spec["rules"][0].get("host"):
            host = spec["rules"][0]["host"]

        if not host:
            continue

        url = f"https://{host}"
        namespace = item["metadata"].get("namespace", "")

        apps.append({
            "name": name,
            "description": description,
            "icon": icon,
            "category": category,
            "order": order,
            "url": url,
            "namespace": namespace,
        })
    return apps


def _extract_apps_from_httproutes(items):
    """Extract portal-annotated apps from HTTPRoute resources."""
    apps = []
    for item in items:
        annotations = item.get("metadata", {}).get("annotations") or {}
        if not any(k.startswith(ANNOTATION_PREFIX) for k in annotations):
            continue
        if annotations.get(f"{ANNOTATION_PREFIX}hidden") == "true":
            continue

        name = annotations.get(f"{ANNOTATION_PREFIX}name", item["metadata"]["name"])
        description = annotations.get(f"{ANNOTATION_PREFIX}description", "")
        icon = annotations.get(f"{ANNOTATION_PREFIX}icon", "")
        category = annotations.get(f"{ANNOTATION_PREFIX}category", "Other")
        order = int(annotations.get(f"{ANNOTATION_PREFIX}order", "100"))

        hostnames = item.get("spec", {}).get("hostnames", [])
        if not hostnames:
            continue

        url = f"https://{hostnames[0]}"
        namespace = item["metadata"].get("namespace", "")

        apps.append({
            "name": name,
            "description": description,
            "icon": icon,
            "category": category,
            "order": order,
            "url": url,
            "namespace": namespace,
        })
    return apps


def _discover_apps():
    """Discover all portal-annotated services from the K8s API."""
    apps = []

    # Fetch Ingresses
    data = _k8s_get("/apis/networking.k8s.io/v1/ingresses")
    if data and "items" in data:
        apps.extend(_extract_apps_from_ingresses(data["items"]))

    # Fetch HTTPRoutes (may 404 if Gateway API CRDs not installed)
    data = _k8s_get("/apis/gateway.networking.k8s.io/v1/httproutes")
    if data and "items" in data:
        apps.extend(_extract_apps_from_httproutes(data["items"]))

    # Group by category
    categories = {}
    for app in apps:
        cat = app["category"]
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(app)

    # Sort apps within each category by order then name
    for cat in categories:
        categories[cat].sort(key=lambda a: (a["order"], a["name"]))

    # Sort categories alphabetically, but "Other" last
    sorted_cats = sorted(categories.keys(), key=lambda c: (c == "Other", c))

    return {
        "cluster": CLUSTER_NAME,
        "domain": CLUSTER_DOMAIN,
        "categories": [
            {"name": cat, "apps": categories[cat]}
            for cat in sorted_cats
        ],
        "total": len(apps),
        "cached_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }


def get_apps():
    """Return cached app list, refreshing if TTL expired."""
    now = time.time()
    if _cache["data"] is not None and (now - _cache["timestamp"]) < CACHE_TTL:
        return _cache["data"]
    result = _discover_apps()
    _cache["data"] = result
    _cache["timestamp"] = now
    logger.info("Refreshed app cache: %d services discovered", result["total"])
    return result


class PortalHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/health":
            self.send_json(200, {"status": "ok"})
        elif path == "/api/apps":
            self.send_json(200, get_apps())
        elif path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(_index_html)
        else:
            self.send_json(404, {"error": "not found"})

    def send_json(self, status, data):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, fmt, *args):
        logger.debug(fmt % args)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    server = HTTPServer(("0.0.0.0", port), PortalHandler)
    logger.info("Portal starting on port %d (cluster: %s)", port, CLUSTER_NAME)
    server.serve_forever()
