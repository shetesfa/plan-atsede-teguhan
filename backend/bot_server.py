import os
import sys
import json
import time
import threading
import requests
from flask import Flask, jsonify, request

# ኮንሶል የ UTF-8 ፊደላትንና ኢሞጂዎችን በትክክል እንዲያሳይ
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

# ==============================================================
# የ .env ውቅር ማንበቢያ (Safe Environment Loader)
# ==============================================================
def load_env_file():
    possible_paths = [
        os.path.join(os.path.dirname(__file__), ".env"),
        os.path.join(os.path.dirname(__file__), "..", "api", ".env"),
        os.path.join(os.path.dirname(__file__), "..", ".env"),
    ]
    for p in possible_paths:
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if not line or line.startswith("#"):
                            continue
                        if "=" in line:
                            k, v = line.split("=", 1)
                            k, v = k.strip(), v.strip().strip("\"'")
                            if k not in os.environ:
                                os.environ[k] = v
            except Exception as e:
                print(f"Error loading env from {p}: {e}")

load_env_file()

# ==============================================================
# የቴሌግራም ቦት ውቅር (Bot Configuration)
# ==============================================================
BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN") or os.environ.get("BOT_TOKEN", "")
CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID") or os.environ.get("CHAT_ID", "")

# M6: PHP_API_BASE has NO usable default. The old default contained a space
# and was an invalid URL, so the bot silently fell back to the static file
# forever. Unset/empty means "PHP API disabled" -> static plans file only.
PHP_API_BASE = (os.environ.get("PHP_API_BASE") or "").strip()
_php_api_base_warned = False

# H2: shared secret that authorises the Flutter app to use the bot proxy
# endpoints below. NEVER put its value in code, git, or a reply; set it only
# as the BOT_PROXY_SECRET env var in Render (same value in the app config).
# CONTRACT: the app sends this secret (header X-Bot-Proxy-Secret, or JSON /
# form field "proxy_secret"). It must NEVER send a bot token, and this
# server NEVER accepts a client-supplied token -- every Telegram call uses
# the server-side BOT_TOKEN env var only.
BOT_PROXY_SECRET = os.environ.get("BOT_PROXY_SECRET", "")

# H8: True while the bot polling loop in this file is consuming getUpdates.
BOT_LOOP_RUNNING = False

BASE_URL = f"https://api.telegram.org/bot{BOT_TOKEN}" if BOT_TOKEN else ""

app = Flask(__name__)

# የተፈቀዱ CORS አመጣጦች (Restricted Origins Only — Never use '*')
ALLOWED_ORIGINS = [
    o.strip() for o in os.environ.get(
        "ALLOWED_ORIGINS", 
        "http://localhost:3000,http://127.0.0.1:8000,http://localhost:8080,http://127.0.0.1"
    ).split(",") if o.strip()
]

@app.after_request
def add_cors_headers(response):
    origin = request.headers.get("Origin", "")
    if origin and origin in ALLOWED_ORIGINS:
        response.headers['Access-Control-Allow-Origin'] = origin
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type,Authorization,X-Bot-Proxy-Secret'
        response.headers['Access-Control-Allow-Methods'] = 'GET,POST,OPTIONS'
    return response

def get_plans_from_database(dept=None):
    """እቅዶችን በቀጥታ ከ MySQL / PHP API በማምጣት አንድ የእውነት ምንጭ (Single Source of Truth) መኖሩን ያረጋግጣል"""
    global _php_api_base_warned
    plans = []
    if PHP_API_BASE:
        # Never build a request URL from a base that contains a space or is
        # otherwise unusable -- fall through to the static file instead.
        if " " in PHP_API_BASE:
            if not _php_api_base_warned:
                print("WARNING: PHP_API_BASE contains a space and is invalid; "
                      "ignoring it and using the static plans file. "
                      "Set PHP_API_BASE to a valid URL with no spaces.")
                _php_api_base_warned = True
        else:
            try:
                url = f"{PHP_API_BASE.rstrip('/')}/plans.php"
                params = {}
                if dept:
                    params["dept"] = dept
                res = requests.get(url, params=params, timeout=5)
                if res.status_code == 200:
                    data = res.json()
                    if data.get("status") == "success":
                        plans = data.get("data", [])
            except Exception as e:
                print(f"Notice: PHP API unavailable, using local JSON fallback: {e}")
            if plans:
                return plans
    else:
        if not _php_api_base_warned:
            print("WARNING: PHP_API_BASE is not set -- the PHP API is disabled; "
                  "plans are served from the static assets/default_plans.json file. "
                  "Set PHP_API_BASE to the PHP API base URL to use live data.")
            _php_api_base_warned = True

    # አገልጋዩ በማይገኝበት ጊዜ የሚረዳ አማራጭ (Fallback)
    local_path = os.path.join(os.path.dirname(__file__), "..", "assets", "default_plans.json")
    if os.path.exists(local_path):
        try:
            with open(local_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                if dept:
                    return [p for p in data if p.get("department") == dept or p.get("departmentId") == dept]
                return data
        except Exception:
            pass
    return []

@app.route("/", methods=["GET"])
def home():
    # M11: the root endpoint is a public health check. It must NOT expose
    # anything derived from a secret -- no token prefix, no chat ID.
    return jsonify({
        "status": "online",
        "service": "Atsede Teguhan Telegram Bot & API Server",
        "plans_count": len(get_plans_from_database()),
        "bot_active": bool(BOT_TOKEN),
    })

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "time": time.time()})

@app.route("/api/plans", methods=["GET"])
def api_get_plans():
    dept = request.args.get("dept")
    plans = get_plans_from_database(dept)
    return jsonify({"status": "success", "count": len(plans), "data": plans})

# ==============================================================
# Telegram Proxy API (ደህንነቱ የተጠበቀ ድልድይ)
# H2: every proxy endpoint below requires one of the two credentials
# documented on require_proxy_auth(): the shared BOT_PROXY_SECRET
# (header X-Bot-Proxy-Secret, or "proxy_secret" field) OR an
# `Authorization: Bearer` header equal to the server-side BOT_TOKEN.
# The Flutter app sends one of those -- it NEVER sends a bot token in a
# body, form field, or query string, and this server NEVER accepts a
# client-supplied token: all Telegram calls use the server-side
# BOT_TOKEN env var only. Without a valid credential the proxy would be
# an open relay anyone could use to send spam as the church bot, so an
# unknown credential means 401, not open access.
# ==============================================================
import hmac


def _proxy_secret_provided():
    """Return the proxy secret the caller supplied, from header, JSON body, or form."""
    secret = request.headers.get("X-Bot-Proxy-Secret", "")
    if secret:
        return secret
    body = request.get_json(silent=True) or {}
    if isinstance(body, dict) and body.get("proxy_secret"):
        return body.get("proxy_secret")
    if request.form.get("proxy_secret"):
        return request.form.get("proxy_secret")
    return ""


def _bearer_token_provided():
    """Return the token from an `Authorization: Bearer <token>` header, if any."""
    auth = request.headers.get("Authorization", "")
    if auth.lower().startswith("bearer "):
        return auth[7:].strip()
    return ""


def require_proxy_auth():
    """401 unless the caller presents one of the two accepted credentials.

    Accepted credentials (either one is enough):
      (1) header `X-Bot-Proxy-Secret` equal to the BOT_PROXY_SECRET env var
          (primary -- the Flutter app's proxy secret, and server-to-server
          use such as the reminder scheduler). The same secret may also be
          sent as the "proxy_secret" field of a JSON body / multipart form.
      (2) header `Authorization: Bearer <token>` where the token equals the
          server-side BOT_TOKEN env var EXACTLY (the Telegram-service
          contract: the app sends the church's own bot token as a Bearer
          header, never in a query string or body).

    This still closes the open relay: an arbitrary client-supplied token
    is rejected -- only the church's own server token or the proxy secret
    works. A token value is NEVER accepted from the request body, form
    fields, or query string, and the server always makes the Telegram
    call with its own BOT_TOKEN env var. If the proxy secret is not
    configured server-side, credential (1) simply never matches; the
    endpoints still work via credential (2).
    """
    provided_secret = _proxy_secret_provided()
    if BOT_PROXY_SECRET and provided_secret and hmac.compare_digest(provided_secret, BOT_PROXY_SECRET):
        return None
    provided_bearer = _bearer_token_provided()
    if BOT_TOKEN and provided_bearer and hmac.compare_digest(provided_bearer, BOT_TOKEN):
        return None
    return jsonify({"ok": False, "error": "unauthorised: missing or wrong proxy credential"}), 401


@app.route("/api/send_notice", methods=["POST", "OPTIONS"])
def send_notice():
    if request.method == "OPTIONS":
        return "", 200
    auth_error = require_proxy_auth()
    if auth_error is not None:
        return auth_error
    if not BOT_TOKEN:
        return jsonify({"error": "የቴሌግራም ቦት ቶከን አልተዋቀረም", "ok": False}), 500

    body = request.get_json(silent=True) or {}
    message = body.get("message", "")
    target_chat = body.get("chat_id") or CHAT_ID
    if not message:
        return jsonify({"error": "መልእክት አልተሰጠም"}), 400

    try:
        res = requests.post(f"{BASE_URL}/sendMessage", json={
            "chat_id": target_chat,
            "text": message,
            "parse_mode": "HTML"
        }, timeout=12)
        return jsonify(res.json()), res.status_code
    except Exception as e:
        return jsonify({"error": str(e), "ok": False}), 500

@app.route("/api/telegram/sendMessage", methods=["POST", "OPTIONS"])
def proxy_send_message():
    if request.method == "OPTIONS":
        return "", 200
    auth_error = require_proxy_auth()
    if auth_error is not None:
        return auth_error
    if not BOT_TOKEN:
        return jsonify({"ok": False, "description": "Bot token not configured on server"}), 500
    body = request.get_json(silent=True) or {}
    target_chat = body.get("chat_id") or CHAT_ID
    text = body.get("text", "")
    parse_mode = body.get("parse_mode", "HTML")

    url = f"{BASE_URL}/sendMessage"
    try:
        res = requests.post(url, json={
            "chat_id": target_chat,
            "text": text,
            "parse_mode": parse_mode
        }, timeout=15)
        return jsonify(res.json()), res.status_code
    except Exception as e:
        return jsonify({"ok": False, "description": str(e)}), 500

@app.route("/api/telegram/sendDocument", methods=["POST", "OPTIONS"])
def proxy_send_document():
    if request.method == "OPTIONS":
        return "", 200
    auth_error = require_proxy_auth()
    if auth_error is not None:
        return auth_error
    if not BOT_TOKEN:
        return jsonify({"ok": False, "description": "Bot token not configured on server"}), 500
    try:
        chat_id = request.form.get("chat_id") or CHAT_ID
        caption = request.form.get("caption", "")

        url = f"{BASE_URL}/sendDocument"
        files = {key: (f.filename, f.stream, f.mimetype) for key, f in request.files.items()}
        data = {"chat_id": chat_id}
        if caption:
            data["caption"] = caption
            data["parse_mode"] = "HTML"

        res = requests.post(url, data=data, files=files, timeout=30)
        return jsonify(res.json()), res.status_code
    except Exception as e:
        return jsonify({"ok": False, "description": str(e)}), 500

@app.route("/api/telegram/sendPhoto", methods=["POST", "OPTIONS"])
def proxy_send_photo():
    if request.method == "OPTIONS":
        return "", 200
    auth_error = require_proxy_auth()
    if auth_error is not None:
        return auth_error
    if not BOT_TOKEN:
        return jsonify({"ok": False, "description": "Bot token not configured on server"}), 500
    try:
        chat_id = request.form.get("chat_id") or CHAT_ID
        caption = request.form.get("caption", "")

        url = f"{BASE_URL}/sendPhoto"
        files = {key: (f.filename, f.stream, f.mimetype) for key, f in request.files.items()}
        data = {"chat_id": chat_id}
        if caption:
            data["caption"] = caption
            data["parse_mode"] = "HTML"

        res = requests.post(url, data=data, files=files, timeout=30)
        return jsonify(res.json()), res.status_code
    except Exception as e:
        return jsonify({"ok": False, "description": str(e)}), 500

# ==============================================================
# H8 -- Telegram getUpdates proxy (diagnostics ONLY)
# ----------------------------------------------------------------
# IMPORTANT -- SINGLE CONSUMER RULE: Telegram delivers each update to
# exactly ONE getUpdates consumer. This server's bot polling loop below
# (bot_polling_loop) is THE consumer: it long-polls getUpdates and
# answers /start, /plans, /depts, /info. If the Flutter app ALSO polled
# getUpdates, the two would steal updates from each other and messages
# would randomly disappear for one side. So:
#   * while the bot loop is running, this route returns 409 and the app
#     must NOT call it -- the app reads chat through the bot / the PHP
#     chat API instead;
#   * the route only proxies to Telegram when the loop is NOT running
#     (e.g. local diagnostics with the bot loop stopped), and it still
#     requires the same BOT_PROXY_SECRET auth and still uses the
#     server-side BOT_TOKEN only.
# ==============================================================
@app.route("/api/telegram/getUpdates", methods=["GET", "OPTIONS"])
def proxy_get_updates():
    if request.method == "OPTIONS":
        return "", 200
    auth_error = require_proxy_auth()
    if auth_error is not None:
        return auth_error
    if BOT_LOOP_RUNNING:
        return jsonify({
            "ok": False,
            "error": "getUpdates is already consumed by the server bot "
                     "polling loop; only one consumer may poll Telegram. "
                     "Do not poll getUpdates from the app.",
        }), 409
    if not BOT_TOKEN:
        return jsonify({"ok": False, "description": "Bot token not configured on server"}), 500
    params = {}
    if request.args.get("offset"):
        params["offset"] = request.args.get("offset")
    if request.args.get("limit"):
        params["limit"] = request.args.get("limit")
    if request.args.get("timeout"):
        params["timeout"] = request.args.get("timeout")
    try:
        res = requests.get(f"{BASE_URL}/getUpdates", params=params, timeout=35)
        return jsonify(res.json()), res.status_code
    except Exception as e:
        return jsonify({"ok": False, "description": str(e)}), 500

# ==============================================================
# የቴሌግራም ቦት አዳማጭ ሉፕ (Telegram Polling Loop)
# ==============================================================
def send_telegram_reply(chat_id, text, reply_to_message_id=None):
    if not BOT_TOKEN:
        return
    try:
        payload = {
            "chat_id": chat_id,
            "text": text,
            "parse_mode": "HTML"
        }
        if reply_to_message_id:
            payload["reply_to_message_id"] = reply_to_message_id
        requests.post(f"{BASE_URL}/sendMessage", json=payload, timeout=10)
    except Exception as e:
        print(f"Reply error: {e}")

def handle_update(update):
    msg = update.get("message") or update.get("channel_post")
    if not msg:
        return

    chat_id = msg.get("chat", {}).get("id")
    text = (msg.get("text") or "").strip()
    msg_id = msg.get("message_id")
    user_name = msg.get("from", {}).get("first_name", "ተጠቃሚ")

    if not text:
        return

    if text.startswith("/start") or text.startswith("/help"):
        welcome = (
            f"ሰላም <b>{user_name}</b> እንኳን ወደ <b>አጸደ ትጉሃን ሰንበት ትምህርት ቤት</b> የእቅድና ሪፖርት ቦት በደህና መጡ! 🕊️\n\n"
            "<b>የሚገኙ ትእዛዞች፦</b>\n"
            "📋 /plans - የክፍሎች አጠቃላይ እቅድ ማጠቃለያ\n"
            "🏢 /depts - የሁሉም ክፍሎች ስም ዝርዝር\n"
            "⏰ /recent - የቅርብ ጊዜ እና ወቅታዊ እቅዶች\n"
            "📢 /info - ስለ ቦቱ እና መተግበሪያው መረጃ\n"
        )
        send_telegram_reply(chat_id, welcome, msg_id)

    elif text.startswith("/depts"):
        depts_text = (
            "🏛️ <b>የሰንበት ትምህርት ቤቱ ክፍሎች ዝርዝር፦</b>\n\n"
            "1. ትምህርት እና ስልጠና ክፍል\n"
            "2. መርሃግብር እና ጉባኤያት ክፍል\n"
            "3. መዝሙርና ስነጥበብ ክፍል\n"
            "4. ልማትና በጎ አድራጎት ክፍል\n"
            "5. አባላት አስተዳደር ክፍል\n"
            "6. መረጃና የውስጥ ግንኙነት ክፍል\n"
            "7. በጀት እና ንብረት አስተዳደር ክፍል\n"
            "8. ሰው ሀብት አስተዳደር ክፍል\n"
            "9. ቁጥጥር ክፍል\n"
            "10. ጽ/ቤት\n"
        )
        send_telegram_reply(chat_id, depts_text, msg_id)

    elif text.startswith("/plans") or text.startswith("/plan"):
        plans = get_plans_from_database()
        total = len(plans)
        if total == 0:
            send_telegram_reply(chat_id, "⚠️ በአሁኑ ወቅት የተመዘገበ እቅድ አልተገኘም።", msg_id)
            return

        summary = {}
        for p in plans:
            dept = p.get("department_name") or p.get("department", "ሌላ")
            summary[dept] = summary.get(dept, 0) + 1

        lines = [f"📊 <b>የ2019 ዓ.ም የእቅዶች ማጠቃለያ (ጠቅላላ፦ {total})፦</b>\n"]
        for dept, cnt in summary.items():
            lines.append(f"• <b>{dept}</b>፦ {cnt} እቅዶች")
        lines.append("\n<i>ዝርዝር እቅዶችን እና ሪፖርቶችን በሞባይል መተግበሪያው ውስጥ መከታተል ይችላሉ!</i>")
        send_telegram_reply(chat_id, "\n".join(lines), msg_id)

    elif text.startswith("/info"):
        info_text = (
            "ℹ️ <b>አጸደ ትጉሃን የዕቅድና ሪፖርት አስተዳደር ስርዓት</b>\n\n"
            "ይህ ቦት ከመተግበሪያው ጋር በቀጥታ የተገናኘ ሲሆን፣ ክፍሎች ሪፖርት ሲያስገቡና እቅድ ሲያስተላልፉ በቅጽበት ማሳወቂያዎችን ያደርሳል።\n\n"
            "🟢 ሁኔታ፦ መስመር ላይ (Online 24/7)"
        )
        send_telegram_reply(chat_id, info_text, msg_id)

def bot_polling_loop():
    global BOT_LOOP_RUNNING
    if not BOT_TOKEN:
        print("⚠️ የቴሌግራም ቦት ቶከን አልተዋቀረም፤ ፖሊንግ አይሰራም።")
        return

    BOT_LOOP_RUNNING = True
    print("🚀 የቴሌግራም ቦት ማዳመጥ ጀመረ (Bot Poller Started)...")
    last_update_id = None
    while True:
        try:
            params = {"timeout": 20, "allowed_updates": ["message", "channel_post"]}
            if last_update_id:
                params["offset"] = last_update_id + 1

            res = requests.get(f"{BASE_URL}/getUpdates", params=params, timeout=30)
            if res.status_code == 200:
                data = res.json()
                if data.get("ok") and data.get("result"):
                    for update in data["result"]:
                        last_update_id = update["update_id"]
                        try:
                            handle_update(update)
                        except Exception as ex:
                            print(f"Error handling update: {ex}")
        except Exception as e:
            time.sleep(3)
        time.sleep(0.5)

if __name__ == "__main__":
    if BOT_TOKEN:
        poller_thread = threading.Thread(target=bot_polling_loop, daemon=True)
        poller_thread.start()

    port = int(os.environ.get("PORT", 8080))
    print(f"🌍 የ Flask ዌብ አገልጋይ በፖርት {port} ላይ እየሰራ ነው...")
    app.run(host="0.0.0.0", port=port)
