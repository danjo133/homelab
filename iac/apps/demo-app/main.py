"""Demo App

Example application exercising all generic-app chart features:
PostgreSQL CRUD, persistent storage, health probes, and portal registration.

Endpoints:
  GET  /           - HTML page showing app info + notes list
  GET  /health     - Liveness probe (always 200)
  GET  /ready      - Readiness probe (checks DB if DATABASE_URL set)
  GET  /api/notes  - List notes as JSON
  POST /api/notes  - Create a note (form: title, content)
"""

import json
import logging
import os
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import parse_qs

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "info").upper())
logger = logging.getLogger("demo-app")

DATABASE_URL = os.environ.get("DATABASE_URL", "")
DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))

_db_conn = None


def _get_db():
    """Get or create a database connection. Returns None if no DATABASE_URL."""
    global _db_conn
    if not DATABASE_URL:
        return None
    if _db_conn is not None:
        try:
            _db_conn.cursor().execute("SELECT 1")
            return _db_conn
        except Exception:
            _db_conn = None
    try:
        import psycopg2
        _db_conn = psycopg2.connect(DATABASE_URL)
        _db_conn.autocommit = True
        return _db_conn
    except ImportError:
        # Fallback: use psycopg (v3) if psycopg2 not available
        pass
    try:
        import psycopg
        _db_conn = psycopg.connect(DATABASE_URL, autocommit=True)
        return _db_conn
    except ImportError:
        logger.warning("No PostgreSQL driver available (need psycopg2 or psycopg)")
        return None


def _init_db():
    """Create the notes table if it doesn't exist."""
    conn = _get_db()
    if conn is None:
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS notes (
                id SERIAL PRIMARY KEY,
                title TEXT NOT NULL,
                content TEXT NOT NULL DEFAULT '',
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)
        logger.info("Database initialized")
    except Exception as e:
        logger.error("Failed to initialize database: %s", e)


def _list_notes():
    """Return all notes from the database."""
    conn = _get_db()
    if conn is None:
        return []
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, title, content, created_at FROM notes ORDER BY id DESC LIMIT 100")
        rows = cur.fetchall()
        return [
            {"id": r[0], "title": r[1], "content": r[2], "created_at": str(r[3])}
            for r in rows
        ]
    except Exception as e:
        logger.error("Failed to list notes: %s", e)
        return []


def _create_note(title, content):
    """Insert a note into the database."""
    conn = _get_db()
    if conn is None:
        return None
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO notes (title, content) VALUES (%s, %s) RETURNING id",
            (title, content),
        )
        row = cur.fetchone()
        return row[0] if row else None
    except Exception as e:
        logger.error("Failed to create note: %s", e)
        return None


def _storage_info():
    """Return info about the persistent storage directory."""
    if not DATA_DIR.exists():
        return {"available": False, "path": str(DATA_DIR)}
    try:
        files = list(DATA_DIR.iterdir())
        return {
            "available": True,
            "path": str(DATA_DIR),
            "file_count": len(files),
            "files": [f.name for f in files[:20]],
        }
    except Exception as e:
        return {"available": False, "path": str(DATA_DIR), "error": str(e)}


INDEX_HTML = """\
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Demo App</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 800px; margin: 2rem auto; padding: 0 1rem; color: #333; }
    h1 { color: #2563eb; }
    .card { background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 1rem; margin: 1rem 0; }
    .card h3 { margin-top: 0; }
    form { display: flex; flex-direction: column; gap: 0.5rem; }
    input, textarea { padding: 0.5rem; border: 1px solid #cbd5e1; border-radius: 4px; font-size: 1rem; }
    button { padding: 0.5rem 1rem; background: #2563eb; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 1rem; }
    button:hover { background: #1d4ed8; }
    .note { border-left: 3px solid #2563eb; padding-left: 0.75rem; margin: 0.5rem 0; }
    .note .meta { font-size: 0.8rem; color: #64748b; }
    .status { display: inline-block; padding: 0.2rem 0.5rem; border-radius: 4px; font-size: 0.85rem; }
    .status.ok { background: #dcfce7; color: #166534; }
    .status.off { background: #fef3c7; color: #92400e; }
    pre { background: #1e293b; color: #e2e8f0; padding: 1rem; border-radius: 8px; overflow-x: auto; }
  </style>
</head>
<body>
  <h1>Demo App</h1>
  <p>Example app exercising all <code>generic-app</code> chart features.</p>

  <div class="card">
    <h3>Status</h3>
    <div id="status">Loading...</div>
  </div>

  <div class="card" id="notes-section">
    <h3>Notes (PostgreSQL CRUD)</h3>
    <form id="note-form">
      <input type="text" name="title" placeholder="Title" required>
      <textarea name="content" placeholder="Content" rows="2"></textarea>
      <button type="submit">Add Note</button>
    </form>
    <div id="notes-list"></div>
  </div>

  <script>
    async function loadStatus() {
      try {
        const [notesRes, readyRes] = await Promise.all([
          fetch('/api/notes'),
          fetch('/ready')
        ]);
        const notes = await notesRes.json();
        const ready = await readyRes.json();

        document.getElementById('status').innerHTML =
          '<b>Database:</b> <span class="status ' + (ready.database ? 'ok' : 'off') + '">' +
          (ready.database ? 'Connected' : 'Not configured') + '</span> &nbsp; ' +
          '<b>Storage:</b> <span class="status ' + (ready.storage?.available ? 'ok' : 'off') + '">' +
          (ready.storage?.available ? ready.storage.file_count + ' files' : 'Not mounted') + '</span>';

        if (!ready.database) {
          document.getElementById('notes-section').style.display = 'none';
        }

        renderNotes(notes);
      } catch (e) {
        document.getElementById('status').textContent = 'Error: ' + e.message;
      }
    }

    function renderNotes(notes) {
      const list = document.getElementById('notes-list');
      if (!notes.length) {
        list.innerHTML = '<p style="color:#64748b">No notes yet.</p>';
        return;
      }
      list.innerHTML = notes.map(n =>
        '<div class="note"><b>' + escapeHtml(n.title) + '</b>' +
        (n.content ? '<br>' + escapeHtml(n.content) : '') +
        '<div class="meta">#' + n.id + ' &mdash; ' + n.created_at + '</div></div>'
      ).join('');
    }

    function escapeHtml(s) {
      const d = document.createElement('div');
      d.textContent = s;
      return d.innerHTML;
    }

    document.getElementById('note-form').addEventListener('submit', async (e) => {
      e.preventDefault();
      const form = e.target;
      const body = new URLSearchParams(new FormData(form));
      const res = await fetch('/api/notes', { method: 'POST', body });
      if (res.ok) {
        form.reset();
        const notes = await (await fetch('/api/notes')).json();
        renderNotes(notes);
      }
    });

    loadStatus();
  </script>
</body>
</html>
"""


class DemoHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/health":
            self.send_json(200, {"status": "ok"})
        elif path == "/ready":
            self.handle_ready()
        elif path == "/api/notes":
            self.send_json(200, _list_notes())
        elif path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(INDEX_HTML.encode())
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        path = self.path.split("?")[0]
        if path == "/api/notes":
            self.handle_create_note()
        else:
            self.send_json(404, {"error": "not found"})

    def handle_ready(self):
        db_ok = False
        if DATABASE_URL:
            conn = _get_db()
            if conn:
                try:
                    conn.cursor().execute("SELECT 1")
                    db_ok = True
                except Exception:
                    pass
        result = {
            "status": "ok",
            "database": db_ok,
            "storage": _storage_info(),
        }
        self.send_json(200, result)

    def handle_create_note(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length).decode()
        params = parse_qs(body)
        title = params.get("title", [""])[0].strip()
        content = params.get("content", [""])[0].strip()
        if not title:
            self.send_json(400, {"error": "title is required"})
            return
        note_id = _create_note(title, content)
        if note_id is None:
            self.send_json(500, {"error": "failed to create note"})
            return
        self.send_json(201, {"id": note_id, "title": title, "content": content})

    def send_json(self, status, data):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, fmt, *args):
        logger.debug(fmt % args)


if __name__ == "__main__":
    _init_db()

    # Write a marker file to /data to demonstrate storage
    if DATA_DIR.exists():
        try:
            marker = DATA_DIR / "started.txt"
            marker.write_text(f"Demo app started at {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\n")
            logger.info("Wrote marker file to %s", marker)
        except Exception as e:
            logger.warning("Could not write to %s: %s", DATA_DIR, e)

    port = int(os.environ.get("PORT", "8080"))
    server = HTTPServer(("0.0.0.0", port), DemoHandler)
    logger.info("Demo App starting on port %d (db=%s, storage=%s)", port, bool(DATABASE_URL), DATA_DIR.exists())
    server.serve_forever()
