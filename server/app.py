import os
import re
import time
import uuid
import sqlite3
import secrets
from functools import wraps
from pathlib import Path

from flask import Flask, Response, jsonify, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash

try:
    import httpx
    import jwt
except Exception:
    httpx = None
    jwt = None

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = Path(os.environ.get("KIDS_CONTROL_DB", BASE_DIR / "data" / "kids-control.db"))
DB_PATH.parent.mkdir(parents=True, exist_ok=True)

ADMIN_USER = os.environ.get("ADMIN_USER", "Waqaar")
ADMIN_PASSWORD_HASH = os.environ["ADMIN_PASSWORD_HASH"]
SECRET_KEY = os.environ["SECRET_KEY"]
SECURE_COOKIE = os.environ.get("SECURE_COOKIE", "0") == "1"
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "").rstrip("/")

APPLE_TEAM_ID = os.environ.get("APPLE_TEAM_ID", "")
APPLE_KEY_ID = os.environ.get("APPLE_KEY_ID", "")
APPLE_BUNDLE_ID = os.environ.get("APPLE_BUNDLE_ID", "com.kidscontrol.hub")
APNS_KEY_PATH = os.environ.get("APNS_KEY_PATH", "")
APNS_ENV = os.environ.get("APNS_ENV", "sandbox").lower()

app = Flask(__name__)
app.secret_key = SECRET_KEY
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=SECURE_COOKIE,
    PERMANENT_SESSION_LIFETIME=60 * 60 * 24 * 30,
)

DEFAULT_DEVICES = [
    ("nevaeh", "Nevaeh's iPad", "N"),
    ("inaara", "Inaara's iPad", "I"),
]

DEFAULT_DEMO_APPS = [
    ("demo-disney-plus", "Disney+", "✨"),
    ("demo-youtube-kids", "YouTube Kids", "▶️"),
    ("demo-roblox", "Roblox", "🎮"),
    ("demo-safari", "Safari", "🧭"),
    ("demo-books", "Books", "📚"),
]


def now():
    return int(time.time())


def db():
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def add_column_if_missing(conn, table, column, ddl):
    names = {row["name"] for row in conn.execute(f"PRAGMA table_info({table})")}
    if column not in names:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {ddl}")


def init_db():
    conn = db()
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS devices (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            avatar TEXT NOT NULL,
            mode TEXT NOT NULL DEFAULT 'custom',
            block_all INTEGER NOT NULL DEFAULT 0,
            last_seen INTEGER,
            token TEXT NOT NULL,
            revision INTEGER NOT NULL DEFAULT 1,
            updated_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS apps (
            device_id TEXT NOT NULL,
            id TEXT NOT NULL,
            name TEXT NOT NULL,
            icon TEXT NOT NULL DEFAULT '📱',
            blocked INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (device_id, id),
            FOREIGN KEY(device_id) REFERENCES devices(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS audit (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            action TEXT NOT NULL,
            detail TEXT,
            created_at INTEGER NOT NULL
        );
        """
    )

    add_column_if_missing(conn, "devices", "push_token", "TEXT")
    add_column_if_missing(conn, "devices", "push_env", "TEXT DEFAULT 'sandbox'")
    add_column_if_missing(conn, "devices", "pair_code", "TEXT")
    add_column_if_missing(conn, "devices", "pair_expires", "INTEGER")
    add_column_if_missing(conn, "apps", "source", "TEXT DEFAULT 'demo'")
    add_column_if_missing(conn, "apps", "selection_b64", "TEXT")
    add_column_if_missing(conn, "apps", "created_at", "INTEGER DEFAULT 0")

    for device_id, name, avatar in DEFAULT_DEVICES:
        conn.execute(
            "INSERT OR IGNORE INTO devices (id,name,avatar,token,updated_at) VALUES (?,?,?,?,?)",
            (device_id, name, avatar, secrets.token_urlsafe(32), now()),
        )
        for app_id, app_name, icon in DEFAULT_DEMO_APPS:
            conn.execute(
                """
                INSERT OR IGNORE INTO apps
                (device_id,id,name,icon,blocked,source,created_at)
                VALUES (?,?,?,?,0,'demo',?)
                """,
                (device_id, app_id, app_name, icon, now()),
            )

    conn.commit()
    conn.close()


def login_required(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        if not session.get("authenticated"):
            if request.path.startswith("/api/"):
                return jsonify({"error": "authentication_required"}), 401
            return redirect(url_for("login"))
        return fn(*args, **kwargs)
    return wrapper


def valid_control_request():
    return request.headers.get("X-Kids-Control") == "1"


def bump_revision(conn, device_id):
    conn.execute(
        "UPDATE devices SET revision=revision+1, updated_at=? WHERE id=?",
        (now(), device_id),
    )


def write_audit(conn, device_id, action, detail=""):
    conn.execute(
        "INSERT INTO audit (device_id,action,detail,created_at) VALUES (?,?,?,?)",
        (device_id, action, detail, now()),
    )


def apns_configured():
    return bool(
        httpx and jwt and APPLE_TEAM_ID and APPLE_KEY_ID and APPLE_BUNDLE_ID
        and APNS_KEY_PATH and Path(APNS_KEY_PATH).exists()
    )


def get_device(conn, device_id):
    row = conn.execute("SELECT * FROM devices WHERE id=?", (device_id,)).fetchone()
    if not row:
        return None
    controls = conn.execute(
        """
        SELECT id,name,icon,blocked,source,selection_b64,created_at
        FROM apps WHERE device_id=?
        ORDER BY CASE source WHEN 'native' THEN 0 ELSE 1 END, name COLLATE NOCASE
        """,
        (device_id,),
    ).fetchall()
    last_seen = row["last_seen"]
    return {
        "id": row["id"],
        "name": row["name"],
        "avatar": row["avatar"],
        "mode": row["mode"],
        "block_all": bool(row["block_all"]),
        "last_seen": last_seen,
        "online": bool(last_seen and now() - last_seen < 180),
        "revision": row["revision"],
        "updated_at": row["updated_at"],
        "helper_paired": bool(last_seen or row["push_token"]),
        "push_ready": bool(row["push_token"] and apns_configured()),
        "controls": [
            {
                "id": c["id"],
                "name": c["name"],
                "icon": c["icon"],
                "blocked": bool(c["blocked"]),
                "source": c["source"] or "demo",
                "live": bool(c["selection_b64"]),
            }
            for c in controls
        ],
    }


def authenticate_agent(conn, device_id):
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return False
    row = conn.execute("SELECT token FROM devices WHERE id=?", (device_id,)).fetchone()
    return bool(row and secrets.compare_digest(auth[7:], row["token"]))


def send_apns_wake(device_id):
    if not apns_configured():
        return {"sent": False, "reason": "apns_not_configured"}

    conn = db()
    row = conn.execute(
        "SELECT push_token,push_env,revision FROM devices WHERE id=?",
        (device_id,),
    ).fetchone()
    conn.close()

    if not row or not row["push_token"]:
        return {"sent": False, "reason": "no_push_token"}

    key = Path(APNS_KEY_PATH).read_text()
    bearer = jwt.encode(
        {"iss": APPLE_TEAM_ID, "iat": int(time.time())},
        key,
        algorithm="ES256",
        headers={"kid": APPLE_KEY_ID},
    )

    environment = (row["push_env"] or APNS_ENV).lower()
    host = "api.sandbox.push.apple.com" if environment == "sandbox" else "api.push.apple.com"
    url = f"https://{host}/3/device/{row['push_token']}"
    headers = {
        "authorization": f"bearer {bearer}",
        "apns-topic": APPLE_BUNDLE_ID,
        "apns-push-type": "background",
        "apns-priority": "5",
    }
    payload = {
        "aps": {"content-available": 1},
        "reason": "state_changed",
        "revision": row["revision"],
    }

    try:
        with httpx.Client(http2=True, timeout=10) as client:
            response = client.post(url, headers=headers, json=payload)
        if response.status_code == 200:
            return {"sent": True}
        return {"sent": False, "reason": f"apns_http_{response.status_code}"}
    except Exception as exc:
        return {"sent": False, "reason": f"apns_error:{exc.__class__.__name__}"}


@app.route("/login", methods=["GET", "POST"])
def login():
    if session.get("authenticated"):
        return redirect(url_for("home"))
    error = None
    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        if secrets.compare_digest(username, ADMIN_USER) and check_password_hash(ADMIN_PASSWORD_HASH, password):
            session.clear()
            session["authenticated"] = True
            session.permanent = True
            return redirect(url_for("home"))
        error = "Incorrect username or password."
    return render_template("login.html", error=error)


@app.get("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.get("/")
@login_required
def home():
    return render_template("app.html", username=ADMIN_USER)


@app.get("/health")
def health():
    return jsonify({"ok": True, "time": now(), "apns": apns_configured()})


@app.get("/api/devices")
@login_required
def api_devices():
    conn = db()
    rows = conn.execute("SELECT id FROM devices ORDER BY name").fetchall()
    result = [get_device(conn, r["id"]) for r in rows]
    conn.close()
    return jsonify({"devices": result, "apns_configured": apns_configured()})


@app.get("/api/devices/<device_id>")
@login_required
def api_device(device_id):
    conn = db()
    device = get_device(conn, device_id)
    conn.close()
    if not device:
        return jsonify({"error": "device_not_found"}), 404
    return jsonify(device)


@app.get("/api/devices/<device_id>/audit")
@login_required
def api_audit(device_id):
    conn = db()
    rows = conn.execute(
        "SELECT action,detail,created_at FROM audit WHERE device_id=? ORDER BY id DESC LIMIT 20",
        (device_id,),
    ).fetchall()
    conn.close()
    return jsonify({"events": [dict(r) for r in rows]})


@app.post("/api/devices/<device_id>/pair-code")
@login_required
def api_pair_code(device_id):
    if not valid_control_request():
        return jsonify({"error": "invalid_request"}), 403
    conn = db()
    if not conn.execute("SELECT 1 FROM devices WHERE id=?", (device_id,)).fetchone():
        conn.close()
        return jsonify({"error": "device_not_found"}), 404
    code = f"{secrets.randbelow(1000000):06d}"
    expires = now() + 600
    conn.execute(
        "UPDATE devices SET pair_code=?,pair_expires=? WHERE id=?",
        (code, expires, device_id),
    )
    write_audit(conn, device_id, "pair_code_created")
    conn.commit()
    conn.close()
    return jsonify({"code": code, "expires_at": expires, "server_url": PUBLIC_BASE_URL})


@app.post("/api/devices/<device_id>/controls/<control_id>")
@login_required
def api_toggle_control(device_id, control_id):
    if not valid_control_request():
        return jsonify({"error": "invalid_request"}), 403
    payload = request.get_json(silent=True) or {}
    if "blocked" not in payload:
        return jsonify({"error": "blocked_required"}), 400

    conn = db()
    if not conn.execute(
        "SELECT 1 FROM apps WHERE device_id=? AND id=?",
        (device_id, control_id),
    ).fetchone():
        conn.close()
        return jsonify({"error": "control_not_found"}), 404

    blocked = 1 if bool(payload["blocked"]) else 0
    conn.execute(
        "UPDATE apps SET blocked=? WHERE device_id=? AND id=?",
        (blocked, device_id, control_id),
    )
    bump_revision(conn, device_id)
    write_audit(conn, device_id, "control_blocked" if blocked else "control_allowed", control_id)
    conn.commit()
    device = get_device(conn, device_id)
    conn.close()
    return jsonify({"device": device, "push": send_apns_wake(device_id)})


@app.post("/api/devices/<device_id>/block-all")
@login_required
def api_block_all(device_id):
    if not valid_control_request():
        return jsonify({"error": "invalid_request"}), 403
    payload = request.get_json(silent=True) or {}
    if "blocked" not in payload:
        return jsonify({"error": "blocked_required"}), 400

    blocked = bool(payload["blocked"])
    conn = db()
    if not conn.execute("SELECT 1 FROM devices WHERE id=?", (device_id,)).fetchone():
        conn.close()
        return jsonify({"error": "device_not_found"}), 404

    conn.execute(
        "UPDATE devices SET block_all=?,mode=?,updated_at=? WHERE id=?",
        (1 if blocked else 0, "lockdown" if blocked else "custom", now(), device_id),
    )
    if not blocked:
        conn.execute("UPDATE apps SET blocked=0 WHERE device_id=?", (device_id,))
    bump_revision(conn, device_id)
    write_audit(conn, device_id, "block_all" if blocked else "allow_all")
    conn.commit()
    device = get_device(conn, device_id)
    conn.close()
    return jsonify({"device": device, "push": send_apns_wake(device_id)})


@app.delete("/api/devices/<device_id>/controls/<control_id>")
@login_required
def api_delete_control(device_id, control_id):
    if not valid_control_request():
        return jsonify({"error": "invalid_request"}), 403
    conn = db()
    result = conn.execute(
        "DELETE FROM apps WHERE device_id=? AND id=?",
        (device_id, control_id),
    )
    if result.rowcount == 0:
        conn.close()
        return jsonify({"error": "control_not_found"}), 404
    bump_revision(conn, device_id)
    write_audit(conn, device_id, "control_removed", control_id)
    conn.commit()
    device = get_device(conn, device_id)
    conn.close()
    send_apns_wake(device_id)
    return jsonify(device)


@app.post("/agent/pair")
def agent_pair():
    payload = request.get_json(silent=True) or {}
    code = str(payload.get("code", "")).strip()
    if not re.fullmatch(r"\d{6}", code):
        return jsonify({"error": "invalid_pair_code"}), 400
    conn = db()
    row = conn.execute(
        "SELECT id,name,token FROM devices WHERE pair_code=? AND pair_expires>=?",
        (code, now()),
    ).fetchone()
    if not row:
        conn.close()
        return jsonify({"error": "pair_code_expired_or_invalid"}), 404
    conn.execute(
        "UPDATE devices SET pair_code=NULL,pair_expires=NULL,last_seen=? WHERE id=?",
        (now(), row["id"]),
    )
    write_audit(conn, row["id"], "helper_paired")
    conn.commit()
    conn.close()
    return jsonify({"device_id": row["id"], "device_name": row["name"], "token": row["token"]})


@app.post("/agent/<device_id>/heartbeat")
def agent_heartbeat(device_id):
    conn = db()
    if not authenticate_agent(conn, device_id):
        conn.close()
        return jsonify({"error": "unauthorized"}), 401
    conn.execute("UPDATE devices SET last_seen=? WHERE id=?", (now(), device_id))
    conn.commit()
    conn.close()
    return jsonify({"ok": True, "server_time": now()})


@app.post("/agent/<device_id>/push-token")
def agent_push_token(device_id):
    conn = db()
    if not authenticate_agent(conn, device_id):
        conn.close()
        return jsonify({"error": "unauthorized"}), 401
    payload = request.get_json(silent=True) or {}
    token = str(payload.get("token", "")).strip().lower()
    environment = str(payload.get("environment", APNS_ENV)).strip().lower()
    if not re.fullmatch(r"[0-9a-f]{32,256}", token):
        conn.close()
        return jsonify({"error": "invalid_push_token"}), 400
    if environment not in {"sandbox", "production"}:
        environment = APNS_ENV
    conn.execute(
        "UPDATE devices SET push_token=?,push_env=?,last_seen=? WHERE id=?",
        (token, environment, now(), device_id),
    )
    write_audit(conn, device_id, "push_token_registered", environment)
    conn.commit()
    conn.close()
    return jsonify({"ok": True, "apns_configured": apns_configured()})


@app.post("/agent/<device_id>/controls")
def agent_register_control(device_id):
    conn = db()
    if not authenticate_agent(conn, device_id):
        conn.close()
        return jsonify({"error": "unauthorized"}), 401
    payload = request.get_json(silent=True) or {}
    name = str(payload.get("name", "")).strip()
    selection_b64 = str(payload.get("selection_b64", "")).strip()
    icon = str(payload.get("icon", "📱")).strip() or "📱"
    if not name or len(name) > 80 or not selection_b64:
        conn.close()
        return jsonify({"error": "name_and_selection_required"}), 400
    control_id = "native-" + uuid.uuid4().hex[:16]
    conn.execute(
        """
        INSERT INTO apps
        (device_id,id,name,icon,blocked,source,selection_b64,created_at)
        VALUES (?,?,?,?,0,'native',?,?)
        """,
        (device_id, control_id, name, icon, selection_b64, now()),
    )
    bump_revision(conn, device_id)
    write_audit(conn, device_id, "native_control_registered", name)
    conn.commit()
    conn.close()
    return jsonify({"ok": True, "id": control_id, "name": name}), 201


@app.get("/agent/<device_id>/desired-state")
def agent_desired_state(device_id):
    conn = db()
    if not authenticate_agent(conn, device_id):
        conn.close()
        return jsonify({"error": "unauthorized"}), 401
    row = conn.execute("SELECT * FROM devices WHERE id=?", (device_id,)).fetchone()
    if not row:
        conn.close()
        return jsonify({"error": "device_not_found"}), 404
    controls = conn.execute(
        """
        SELECT id,name,blocked,selection_b64
        FROM apps
        WHERE device_id=? AND source='native' AND selection_b64 IS NOT NULL
        ORDER BY name COLLATE NOCASE
        """,
        (device_id,),
    ).fetchall()
    conn.execute("UPDATE devices SET last_seen=? WHERE id=?", (now(), device_id))
    conn.commit()
    conn.close()
    return jsonify(
        {
            "device_id": device_id,
            "revision": row["revision"],
            "block_all": bool(row["block_all"]),
            "controls": [
                {
                    "id": c["id"],
                    "name": c["name"],
                    "blocked": bool(c["blocked"]),
                    "selection_b64": c["selection_b64"],
                }
                for c in controls
            ],
        }
    )


@app.get("/manifest.webmanifest")
def manifest():
    return jsonify(
        {
            "name": "Kids Control",
            "short_name": "Kids Control",
            "start_url": "/",
            "scope": "/",
            "display": "standalone",
            "background_color": "#07090d",
            "theme_color": "#07090d",
            "icons": [
                {
                    "src": "/icon.svg",
                    "sizes": "any",
                    "type": "image/svg+xml",
                    "purpose": "any maskable",
                }
            ],
        }
    )


@app.get("/icon.svg")
def icon():
    svg = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#9d7cff"/><stop offset="1" stop-color="#4d6fff"/></linearGradient></defs><rect width="512" height="512" rx="120" fill="#08090d"/><path d="M256 70l145 55v111c0 96-59 171-145 210-86-39-145-114-145-210V125z" fill="url(#g)"/><path d="M197 257l39 40 83-97" fill="none" stroke="white" stroke-width="30" stroke-linecap="round" stroke-linejoin="round"/></svg>"""
    return Response(svg, mimetype="image/svg+xml")


@app.get("/sw.js")
def service_worker():
    js = "self.addEventListener('install',e=>self.skipWaiting());self.addEventListener('activate',e=>e.waitUntil(clients.claim()));"
    return Response(js, mimetype="application/javascript", headers={"Service-Worker-Allowed": "/"})


init_db()
