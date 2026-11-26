import os
import sys
import json
import time
import threading
from datetime import datetime as _dt, timezone as _tz, timedelta as _td
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

def bot_api(action, payload=None):
    """Call the PHP bot API (api/bot.php) server-to-server.

    The PHP side accepts ONLY the shared BOT_PROXY_SECRET (header
    X-Bot-Proxy-Secret). Returns the decoded `data` dict on success,
    or None on any failure (unreachable / non-200 / error status).
    The bot NEVER forwards the secret or any token to Telegram users.
    """
    if not PHP_API_BASE or " " in PHP_API_BASE or not BOT_PROXY_SECRET:
        return None
    body = dict(payload or {})
    body["action"] = action
    try:
        res = requests.post(
            f"{PHP_API_BASE.rstrip('/')}/bot.php",
            headers={"X-Bot-Proxy-Secret": BOT_PROXY_SECRET,
                     "Content-Type": "application/json"},
            json=body,
            timeout=15,
        )
        if res.status_code != 200:
            return None
        data = res.json()
        if data.get("status") != "success":
            return None
        return data.get("data")
    except Exception as e:
        print(f"bot_api({action}) error: {e}")
        return None


def bot_user_by_chat(chat_id):
    """Who owns this Telegram chat, if the account is linked."""
    if chat_id is None:
        return None
    data = bot_api("user_by_chat", {"chat_id": str(chat_id)})
    if not data or not data.get("linked"):
        return None
    return data.get("user")


def get_plans_from_database(dept=None):
    """LIVE plans from the PHP bot API (server-to-server, proxy auth).

    2026-11-26 (bot upgrade): the old code called plans.php with NO
    auth, so it always got 401 and silently fell back to the stale
    static file (137 plans from before the Excel import). Now the bot
    asks api/bot.php, which returns live data. The static file is
    ONLY a last resort when the API itself is unreachable.
    """
    global _php_api_base_warned
    if PHP_API_BASE:
        if " " in PHP_API_BASE:
            if not _php_api_base_warned:
                print("WARNING: PHP_API_BASE contains a space and is invalid; "
                      "ignoring it and using the static plans file. "
                      "Set PHP_API_BASE to a valid URL with no spaces.")
                _php_api_base_warned = True
        else:
            payload = {}
            if dept:
                payload["department_id"] = dept
            data = bot_api("plans_list", payload)
            if data and isinstance(data.get("plans"), list):
                return data["plans"]
            print("Notice: PHP bot API unavailable, using local JSON fallback.")
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
    # 2026-11-26 (M2): the full plan list was public — anyone could read
    # all 137 plans without any credential. Same proxy auth as the other
    # endpoints (BOT_PROXY_SECRET header or Bearer BOT_TOKEN).
    auth_error = require_proxy_auth()
    if auth_error is not None:
        return auth_error
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
    report_id = body.get("report_id") or ""
    if not message:
        return jsonify({"error": "መልእክት አልተሰጠም"}), 400

    # 2026-11-26 (bot upgrade): a report notice carries Approve /
    # Reject buttons for the office. The buttons are inline-keyboard
    # callbacks (review:approve:<id> / review:reject:<id>); the
    # polling loop answers them via api/bot.php report_review, after
    # checking the clicker is a linked super-admin.
    payload = {
        "chat_id": target_chat,
        "text": message,
        "parse_mode": "HTML",
    }
    if report_id:
        payload["reply_markup"] = {
            "inline_keyboard": [[
                {"text": "✅ ጸድቋል", "callback_data": f"review:approve:{report_id}"},
                {"text": "❌ አልተቀበልም", "callback_data": f"review:reject:{report_id}"},
            ]]
        }

    try:
        res = requests.post(f"{BASE_URL}/sendMessage", json=payload, timeout=12)
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
# answers /start, /link, /menu, /plans, /myplans, /recent, /depts,
# /reset, /info plus the inline-keyboard callbacks (menu, lists,
# progress, report review). If the Flutter app ALSO polled getUpdates, the two would steal updates
# from each other and messages would randomly disappear for one side. So:
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
# ማሳሰቢያ መርሐግብር (Reminder Scheduler — audit fix 2026-11-25)
# POST /api/scheduler/run — one pass: ask the PHP API which
# plans are due soon / overdue without a report, send the
# Telegram reminders + office escalations, mark them sent.
# Called once an hour by a GitHub Actions workflow (the free
# Render service sleeps, so no in-process scheduler can be
# trusted to wake up on its own). Same proxy-secret auth as
# the other proxy endpoints. The PHP side dedups: one reminder
# and one escalation per plan per day.
# ==============================================================
import html as _html


def _send_telegram_message_to(chat_id, text):
    """Send one Telegram message to a given chat. True on success."""
    if not BOT_TOKEN or not chat_id:
        return False
    try:
        res = requests.post(f"{BASE_URL}/sendMessage", json={
            "chat_id": chat_id,
            "text": text,
            "parse_mode": "HTML"
        }, timeout=15)
        data = res.json()
        return res.status_code == 200 and data.get("ok") is True
    except Exception as e:
        print(f"Scheduler send error: {e}")
        return False


def _send_telegram_message(text):
    """Send one Telegram message to the office chat (CHAT_ID)."""
    return _send_telegram_message_to(CHAT_ID, text)


@app.route("/api/scheduler/run", methods=["POST", "OPTIONS"])
def scheduler_run():
    if request.method == "OPTIONS":
        return "", 200
    auth_error = require_proxy_auth()
    if auth_error is not None:
        return auth_error
    if not BOT_TOKEN:
        return jsonify({"ok": False, "description": "Bot token not configured on server"}), 500
    if not PHP_API_BASE or " " in PHP_API_BASE:
        return jsonify({"ok": False, "description": "PHP_API_BASE not configured on server"}), 500
    if not CHAT_ID:
        return jsonify({"ok": False, "description": "CHAT_ID not configured on server"}), 500

    try:
        due_res = requests.get(
            f"{PHP_API_BASE.rstrip('/')}/scheduler.php?action=due",
            headers={"X-Bot-Proxy-Secret": BOT_PROXY_SECRET},
            timeout=25,
        )
        due_data = due_res.json()
    except Exception as e:
        return jsonify({"ok": False, "description": f"PHP scheduler unreachable: {e}"}), 502
    if due_res.status_code != 200 or due_data.get("status") != "success":
        return jsonify({"ok": False, "description": "PHP scheduler error", "detail": str(due_data)[:200]}), 502

    payload = due_data.get("data", {}) or {}
    due_soon = payload.get("due_soon", []) or []
    overdue = payload.get("overdue", []) or []
    user_reminders = payload.get("user_reminders", []) or []

    sent_items = []
    failed = []
    for plan in due_soon:
        dept = _html.escape(str(plan.get("department_name") or plan.get("department_id") or ""))
        task = _html.escape(str(plan.get("main_task") or plan.get("detail_task") or "እቅድ"))
        when = _html.escape(str(plan.get("execution_time") or ""))
        text = (f"⏰ <b>ማሳሰቢያ</b>\nየ<b>{dept}</b> እቅድ “{task}” ቀኑ <b>{when}</b> ነው። "
                f"ሪፖርት ገና አልገባም — እባክዎ ሪፖርት ያስገቡ።")
        if _send_telegram_message(text):
            sent_items.append({"plan_id": plan["id"], "kind": "reminder"})
        else:
            failed.append({"plan_id": plan["id"], "kind": "reminder"})
    for plan in overdue:
        dept = _html.escape(str(plan.get("department_name") or plan.get("department_id") or ""))
        task = _html.escape(str(plan.get("main_task") or plan.get("detail_task") or "እቅድ"))
        when = _html.escape(str(plan.get("execution_time") or ""))
        text = (f"🚨 <b>ለፅ/ቤት ማሳሰቢያ — ሪፖርት ዘግይቷል</b>\nየ<b>{dept}</b> እቅድ “{task}” "
                f"ቀኑ አልፏል (<b>{when}</b>) እና ሪፖርት አልተላከም። እባክዎ ክፍሉን ያነጋግሩ።")
        if _send_telegram_message(text):
            sent_items.append({"plan_id": plan["id"], "kind": "escalation"})
        else:
            failed.append({"plan_id": plan["id"], "kind": "escalation"})

    # 2026-11-26 (bot upgrade): per-user reminders — each linked user
    # gets ONLY their own department's plans in their own chat.
    # One reminder per user per plan per day (the PHP side dedups in
    # user_reminder_log, and mark_sent below records user_id).
    user_sent = 0
    for entry in user_reminders:
        chat_id = entry.get("chat_id")
        user_id = entry.get("user_id")
        if not chat_id or not user_id:
            continue
        lines = []
        for plan in entry.get("overdue", []) or []:
            task = _html.escape(str(plan.get("main_task") or plan.get("detail_task") or "እቅድ"))
            when = _html.escape(str(plan.get("execution_time") or ""))
            lines.append(f"🚨 <b>ዘግይቷል፦</b> “{task}” (<b>{when}</b>)")
        for plan in entry.get("due_soon", []) or []:
            task = _html.escape(str(plan.get("main_task") or plan.get("detail_task") or "እቅድ"))
            when = _html.escape(str(plan.get("execution_time") or ""))
            lines.append(f"⏰ <b>ቀኑ ደርሷል፦</b> “{task}” (<b>{when}</b>)")
        if not lines:
            continue
        name = _html.escape(str(entry.get("full_name") or ""))
        dept = _html.escape(str(entry.get("department_name") or ""))
        text = (f"ሰላም <b>{name}</b> 🕊️\n"
                f"የ<b>{dept}</b> እቅዶችህ ማሳሰቢያ፦\n\n" + "\n".join(lines[:10]) +
                "\n\n<i>ሪፖርት በአፕ ውስጥ አስገባ።</i>")
        if _send_telegram_message_to(chat_id, text):
            user_sent += 1
            for plan in entry.get("overdue", []) or []:
                sent_items.append({"plan_id": plan["id"], "kind": "escalation", "user_id": user_id})
            for plan in entry.get("due_soon", []) or []:
                sent_items.append({"plan_id": plan["id"], "kind": "reminder", "user_id": user_id})
        else:
            for plan in entry.get("overdue", []) or []:
                failed.append({"plan_id": plan["id"], "kind": "escalation", "user_id": user_id})
            for plan in entry.get("due_soon", []) or []:
                failed.append({"plan_id": plan["id"], "kind": "reminder", "user_id": user_id})

    if sent_items:
        try:
            requests.post(
                f"{PHP_API_BASE.rstrip('/')}/scheduler.php?action=mark_sent",
                headers={"X-Bot-Proxy-Secret": BOT_PROXY_SECRET, "Content-Type": "application/json"},
                json={"items": sent_items},
                timeout=15,
            )
        except Exception as e:
            print(f"Scheduler mark_sent error: {e}")

    return jsonify({
        "ok": True,
        "today": payload.get("today"),
        "due_soon": len(due_soon),
        "overdue": len(overdue),
        "user_reminders": len(user_reminders),
        "user_messages_sent": user_sent,
        "sent": len(sent_items),
        "failed": failed,
    }), 200

# ==============================================================
# የቴሌግራም ቦት አዳማጭ ሉፕ (Telegram Polling Loop)
# ==============================================================
def send_telegram_reply(chat_id, text, reply_to_message_id=None, reply_markup=None):
    """Send a message; reply_markup is an inline keyboard dict (optional)."""
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
        if reply_markup:
            payload["reply_markup"] = reply_markup
        requests.post(f"{BASE_URL}/sendMessage", json=payload, timeout=10)
    except Exception as e:
        print(f"Reply error: {e}")

# 2026-11-26 (bot upgrade): in-memory reset flow state.
# chat_id -> {"stage": "username", "ts": epoch seconds}.
# A restart loses it — the user just sends /reset again.
_reset_pending = {}


def answer_callback_query(callback_query_id, text=""):
    if not BOT_TOKEN:
        return
    try:
        payload = {
            "callback_query_id": callback_query_id,
            "show_alert": False,
        }
        if text:
            payload["text"] = text
        requests.post(f"{BASE_URL}/answerCallbackQuery", json=payload, timeout=10)
    except Exception as e:
        print(f"answerCallbackQuery error: {e}")


def edit_message_text(chat_id, message_id, text, reply_markup=None):
    """Edit a message's text (and keyboard). Telegram ignores an edit
    whose text is identical to the current one — callers must change
    something (page, progress, view) before editing."""
    if not BOT_TOKEN:
        return
    try:
        payload = {
            "chat_id": chat_id,
            "message_id": message_id,
            "text": text,
            "parse_mode": "HTML",
        }
        if reply_markup is not None:
            payload["reply_markup"] = reply_markup
        requests.post(f"{BASE_URL}/editMessageText", json=payload, timeout=10)
    except Exception as e:
        print(f"editMessageText error: {e}")


def _short(text, limit=80):
    text = (text or "").strip().replace("\n", " ")
    return text if len(text) <= limit else text[: limit - 1] + "…"


def handle_review_callback(callback):
    """Office Approve / Reject button on a report notice."""
    data = (callback.get("data") or "")
    parts = data.split(":")
    if len(parts) != 3 or parts[0] != "review" or parts[1] not in ("approve", "reject"):
        return
    report_id = parts[2]
    cb_id = callback.get("id")
    from_chat = (callback.get("from") or {}).get("id")
    msg = callback.get("message") or {}
    chat_id = (msg.get("chat") or {}).get("id")
    message_id = msg.get("message_id")
    original_text = msg.get("text") or ""

    user = bot_user_by_chat(from_chat)
    if not user or not user.get("is_super_admin"):
        answer_callback_query(cb_id, "ይህንን ማድረግ የሚችለው የፅ/ቤት አባል ብቻ ነው።")
        return

    result = bot_api("report_review", {
        "report_id": report_id,
        "action": parts[1],
        "chat_id": str(from_chat),
    })
    if not result:
        answer_callback_query(cb_id, "ግምገማው አልተመዘገበም — እባክዎ እንደገና ይሞክሩ።")
        return

    verdict = "✅ ጸድቋል" if result.get("status") == "approved" else "❌ አልተቀበልም"
    answer_callback_query(cb_id, f"ሪፖርቱ {verdict}")
    edit_message_text(
        chat_id, message_id,
        original_text + f"\n\n<b>{verdict}</b> — {user.get('full_name', '')}",
    )


# ==============================================================
# Modern bot UI (2026-11-26) — inline menus, paginated plan
# cards, per-plan progress buttons. Telegram cannot show the
# app's maroon / gold colours, so the app's look is mirrored
# with clean header blocks, status chips, progress bars and
# Ethiopian dates. Every button does something: navigation is
# encoded in the callback data (no server-side button state),
# and every data-changing callback re-checks the clicker
# server-side (linked user + own department) before acting.
# Callback data is namespaced and short (Telegram limit: 64
# bytes): menu | myplans:<page> | recent:<page> | plans |
# depts | dept:<id>:<page> | plan:<id>:<src> |
# prog:<id>:<pct>:<src> | report:<id> | link | reset | info |
# noop | review:approve|reject:<id>.
# ==============================================================
PAGE_SIZE = 5
_DIV = "━━━━━━━━━━━━━━━"
_REPORT_STATUS_AM = {
    "draft": "ረቂቅ",
    "submitted": "ሪፖርት ተልኳል",
    "under_review": "በግምገማ ላይ",
    "approved": "ጸድቋል",
    "rejected": "አልተቀበልም",
}


def _today_str():
    """Today in Addis Ababa time (the Render container runs on UTC)."""
    return _dt.now(_tz(_td(hours=3))).strftime("%Y-%m-%d")


def _week_str():
    return (_dt.now(_tz(_td(hours=3))) + _td(days=7)).strftime("%Y-%m-%d")


def progress_bar(pct):
    """10-block progress bar, e.g. ▓▓▓▓▓▓░░░░ 60%."""
    pct = max(0, min(100, int(pct or 0)))
    filled = int(round(pct / 10))
    return "▓" * filled + "░" * (10 - filled) + f" {pct}%"


def plan_status_chip(plan):
    """Status chip for one plan (API due date + latest report)."""
    if (plan.get("progress_percent") or 0) >= 100:
        return "✅ ተጠናቋል"
    if plan.get("latest_report_status") in ("submitted", "under_review", "approved"):
        return "📝 ሪፖርት ተልኳል"
    today = _today_str()
    due = plan.get("due_date") or ""
    if due and due < today:
        return "🔴 ዘግይቷል"
    if due and due <= _week_str():
        return "⏰ ቀኑ ደርሷል"
    return "📋 እየተሰራ ነው"


def plan_card(plan, number=None):
    """One plan as a formatted card block."""
    title = _html.escape(_short(plan.get("main_task"), 90))
    dept = _html.escape(plan.get("department_name") or "")
    due = plan.get("due_date_ethiopian") or plan.get("due_date") or "—"
    head = f"<b>{number}. {title}</b>\n" if number else f"<b>{title}</b>\n"
    return (
        head
        + f"🏢 {dept}  •  📅 {due}\n"
        + f"{plan_status_chip(plan)}  •  {progress_bar(plan.get('progress_percent') or 0)}"
    )


def sort_plans_for_list(plans):
    """Overdue first, then by due date — the order every list uses."""
    today = _today_str()

    def key(p):
        due = p.get("due_date") or "9999-12-31"
        overdue = 0 if (due < today and (p.get("progress_percent") or 0) < 100) else 1
        return (overdue, due, str(p.get("id") or ""))

    return sorted(plans, key=key)


def kb_menu():
    """Main menu inline keyboard."""
    return {"inline_keyboard": [
        [{"text": "📌 የእኔ እቅዶች", "callback_data": "myplans:0"}],
        [{"text": "📊 ማጠቃለያ", "callback_data": "plans"},
         {"text": "⏰ የቅርብ ቀናት", "callback_data": "recent:0"}],
        [{"text": "🏢 ክፍሎች", "callback_data": "depts"},
         {"text": "🔗 አገናኝ", "callback_data": "link"}],
        [{"text": "🔑 የይለፍ ቃል ዳግም ማስጀመር", "callback_data": "reset"}],
        [{"text": "ℹ️ መረጃ", "callback_data": "info"}],
    ]}


def kb_home_row():
    return [[{"text": "🏠 ዋና ማውጫ", "callback_data": "menu"}]]


def kb_page_nav(prefix, page, total_pages):
    """◀️ ▶️ navigation + page indicator + back-to-menu."""
    row = []
    if page > 0:
        row.append({"text": "◀️ ቀዳሚ", "callback_data": f"{prefix}:{page - 1}"})
    row.append({"text": f"ገጽ {page + 1}/{max(total_pages, 1)}", "callback_data": "noop"})
    if page < total_pages - 1:
        row.append({"text": "ቀጣይ ▶️", "callback_data": f"{prefix}:{page + 1}"})
    return {"inline_keyboard": [row] + kb_home_row()}


def kb_plan_list(plans, page, prefix):
    """One button per plan on this page + navigation rows."""
    rows = []
    for i, p in enumerate(plans[page * PAGE_SIZE:(page + 1) * PAGE_SIZE]):
        num = page * PAGE_SIZE + i + 1
        rows.append([{"text": f"{num}. {_short(p.get('main_task'), 50)}",
                      "callback_data": f"plan:{p['id']}:{prefix}:{page}"}])
    total_pages = max(1, (len(plans) + PAGE_SIZE - 1) // PAGE_SIZE)
    rows.extend(kb_page_nav(prefix, page, total_pages)["inline_keyboard"])
    return {"inline_keyboard": rows}


def menu_text(user_name, linked_user):
    if linked_user:
        link_line = (
            f"✅ <b>{linked_user.get('full_name', '')}</b> — "
            f"{linked_user.get('department_name', '')} ጋር ተገናኝቷል።\n"
        )
    else:
        link_line = "🔗 Telegramህን አገናኝተህ የክፍልህን እቅዶች እይ።\n"
    return (
        "🏛 <b>ዐጸደ ትጉሃን ሰንበት ት/ቤት</b>\n"
        f"{_DIV}\n"
        f"ሰላም <b>{_html.escape(user_name)}</b> 🕊️\n"
        f"{link_line}"
        f"{_DIV}\n"
        "ከታች ካለው ማውጫ ምረጥ፦"
    )


# 2026-11-26 (link gate): a stranger sees NOTHING until the Telegram
# account is linked. Every handler/callback checks the link first and,
# when unlinked, answers with ONLY this message — how to link, nothing
# else. /start <code> (the link flow itself) stays open: that is how a
# stranger becomes linked.
LINK_FIRST_TEXT = (
    "\U0001f512 <b>መጀመሪያ Telegramህን አገናኝ</b>\n\n"
    "ይህ ቦት ለተገናኙ ሰዎች ብቻ ነው — እቅዶችህን ለማየት Telegram accountህን ማገናኘት አለብህ።\n\n"
    "በአፕ ውስጥ፦ <b>ዳሽቦርድ / ውይይት</b> → <b>Telegram</b> ቁልፍ → <b>«አገናኝ»</b> → "
    "ኮድ አግኝተህ እዚህ <b>/start &lt;ኮድ&gt;</b> ብለህ ላክ።\n\n"
    "ኮዱ ለ<b>15 ደቂቃ</b> ብቻ ይሰራል።"
)


def _link_first_kb():
    return {"inline_keyboard": [[{"text": "\U0001f517 Telegram አገናኝ", "callback_data": "link"}]]}


def _reply_link_first(chat_id, msg_id=None):
    """Unlinked chat: the ONLY reply — how to link, nothing else."""
    send_telegram_reply(chat_id, LINK_FIRST_TEXT, msg_id, _link_first_kb())


def _edit_link_first(chat_id, message_id, cb_id):
    """Unlinked chat tapping a button: replace the message with the link-first text."""
    edit_message_text(chat_id, message_id, LINK_FIRST_TEXT, _link_first_kb())
    answer_callback_query(cb_id, "Telegram ማገናኘት አለብህ።")


def _visible_departments(user, dept_list):
    """Departments this user may browse: all for office/audit, own only otherwise."""
    if not dept_list:
        return []
    if user and (user.get("is_super_admin") or user.get("can_view_all")):
        return list(dept_list)
    if not user:
        return []
    own = str(user.get("department_id"))
    return [d for d in dept_list if str(d.get("id")) == own]


def render_plan_page(plans, page, prefix, title):
    """One page of plan cards. Returns (text, keyboard)."""
    plans = sort_plans_for_list(plans)
    total_pages = max(1, (len(plans) + PAGE_SIZE - 1) // PAGE_SIZE)
    page = max(0, min(page, total_pages - 1))
    page_plans = plans[page * PAGE_SIZE:(page + 1) * PAGE_SIZE]
    lines = [title, _DIV, ""]
    if not page_plans:
        lines.append("ምንም እቅድ የለም። 🎉")
    for i, p in enumerate(page_plans):
        lines.append(plan_card(p, page * PAGE_SIZE + i + 1))
        lines.append("")
    lines.append(f"📄 ገጽ {page + 1}/{total_pages}  •  ጠቅላላ፦ {len(plans)} እቅዶች")
    return "\n".join(lines).strip(), kb_plan_list(plans, page, prefix)


def render_plan_detail(plan, user, src):
    """Full detail of one plan + action buttons. Returns (text, keyboard)."""
    title = _html.escape(plan.get("main_task") or "እቅድ")
    dept = _html.escape(plan.get("department_name") or "")
    due = plan.get("due_date_ethiopian") or plan.get("due_date") or "—"
    schedule = _html.escape(plan.get("execution_time") or "")
    detail = _html.escape(plan.get("detail_task") or "")
    pct = plan.get("progress_percent") or 0
    lines = [f"📌 <b>{title}</b>", _DIV, f"🏢 {dept}", f"📅 የሚጠበቅበት ቀን፦ {due}"]
    if schedule:
        lines.append(f"🗓 መርሐግብር፦ {schedule}")
    if detail:
        lines.append(f"\n{detail}")
    lines.append("")
    lines.append(f"{plan_status_chip(plan)}  •  {progress_bar(pct)}")
    if plan.get("is_postponed"):
        lines.append("↩️ ይህ እቅድ ተላልፏል።")
    report = plan.get("latest_report_status")
    if report:
        lines.append(f"📝 የሪፖርት ሁኔታ፦ {_REPORT_STATUS_AM.get(report, report)}")
    # Progress buttons: only a linked member of the plan's own
    # department — the office and audit are view-only in the bot.
    can_edit = bool(
        user
        and plan.get("department_id") == user.get("department_id")
        and not user.get("is_super_admin")
        and not user.get("can_view_all")
    )
    rows = []
    if can_edit:
        rows.append([
            {"text": "25%", "callback_data": f"prog:{plan['id']}:25:{src}"},
            {"text": "50%", "callback_data": f"prog:{plan['id']}:50:{src}"},
            {"text": "75%", "callback_data": f"prog:{plan['id']}:75:{src}"},
            {"text": "100% ✅", "callback_data": f"prog:{plan['id']}:100:{src}"},
        ])
    rows.append([{"text": "📝 ሪፖርት በአፕ አስገባ", "callback_data": f"report:{plan['id']}"}])
    rows.append([{"text": "🔙 ተመለስ", "callback_data": src}])
    return "\n".join(lines), {"inline_keyboard": rows}


def find_plan(chat_id, plan_id):
    """One plan this chat may see, plus the linked user (or None)."""
    user = bot_user_by_chat(chat_id)
    if not user:
        # Unlinked chats see no plan at all (the link gate blocks the
        # callbacks first; this is defense in depth).
        return None, None
    data = bot_api("plans_for", {"chat_id": str(chat_id)})
    plans = (data or {}).get("plans", []) or []
    for p in plans:
        if str(p.get("id")) == str(plan_id):
            return p, user
    return None, user


def _start_reset(chat_id):
    """Begin the password-reset flow for this chat (command or button)."""
    linked_user = bot_user_by_chat(chat_id)
    if linked_user:
        _do_reset_request(chat_id, linked_user.get("username", ""), None)
        return
    _reset_pending[str(chat_id)] = {"stage": "username", "ts": time.time()}
    send_telegram_reply(
        chat_id,
        "🔑 <b>የይለፍ ቃል ዳግም ማስጀመር</b>\n\n"
        "የተጠቃሚ ስምህን ላክ (ለምሳሌ፦ <b>mezmur</b>)።\n"
        "ኮድ ወደተገናኘው Telegram accountህ ይላካል።\n"
        "ለማቋረጥ /cancel ላክ።",
    )


def _show_myplans(chat_id, message_id, cb_id, page):
    user = bot_user_by_chat(chat_id)
    if not user:
        _edit_link_first(chat_id, message_id, cb_id)
        return
    data = bot_api("plans_for", {"chat_id": str(chat_id)})
    if not data:
        answer_callback_query(cb_id, "እቅዶችን ማምጣት አልተቻለም — እንደገና ሞክር።")
        return
    plans = data.get("plans", []) or []
    title = (
        f"📌 <b>የ{user.get('department_name', '')} እቅዶች</b>\n"
        f"ጠቅላላ፦ {data.get('total', len(plans))}  •  🚨 የዘገዩ፦ {data.get('overdue_count', 0)}"
    )
    text, kb = render_plan_page(plans, page, "myplans", title)
    edit_message_text(chat_id, message_id, text, kb)
    answer_callback_query(cb_id)


def _show_recent(chat_id, message_id, cb_id, page):
    data = bot_api("recent_for", {"chat_id": str(chat_id)})
    if not data:
        answer_callback_query(cb_id, "እቅዶችን ማምጣት አልተቻለም — እንደገና ሞክር።")
        return
    plans = data.get("plans", []) or []
    scope = ""
    if data.get("user"):
        scope = f" — {data['user'].get('department_name', '')}"
    title = f"⏰ <b>የቅርብ 7 ቀናት እቅዶች{scope}</b>"
    text, kb = render_plan_page(plans, page, "recent", title)
    edit_message_text(chat_id, message_id, text, kb)
    answer_callback_query(cb_id)


def _show_summary(chat_id, message_id, cb_id):
    user = bot_user_by_chat(chat_id)
    if not user:
        _edit_link_first(chat_id, message_id, cb_id)
        return
    data = bot_api("plans_summary", {"chat_id": str(chat_id)})
    if not data:
        answer_callback_query(cb_id, "ማጠቃለያ ማምጣት አልተቻለም — እንደገና ሞክር።")
        return
    depts = bot_api("departments", {}) or {}
    dept_list = _visible_departments(
        user, depts.get("departments") or [] if isinstance(depts, dict) else [])
    by_dept = data.get("by_department") or {}
    lines = [
        "📊 <b>የ2019 ዓ.ም የእቅዶች ማጠቃለያ</b>",
        _DIV,
        f"ጠቅላላ፦ <b>{data.get('total', 0)}</b> እቅዶች  •  🚨 የዘገዩ፦ <b>{data.get('overdue_count', 0)}</b>",
        "",
    ]
    rows = []
    for d in dept_list:
        name = d.get("name") or ""
        cnt = by_dept.get(name, 0)
        lines.append(f"• <b>{_html.escape(name)}</b>፦ {cnt} እቅዶች")
        rows.append([{"text": f"🏢 {name} ({cnt})", "callback_data": f"dept:{d.get('id')}:0"}])
    if not dept_list:
        for name, cnt in by_dept.items():
            lines.append(f"• <b>{_html.escape(name)}</b>፦ {cnt} እቅዶች")
    lines.append("")
    lines.append("ክፍል ምረጥ — እቅዶቹን ለማየት፤ ወይም Telegramህን አገናኝተህ /myplans ብል።")
    rows.append([{"text": "🏠 ዋና ማውጫ", "callback_data": "menu"}])
    edit_message_text(chat_id, message_id, "\n".join(lines), {"inline_keyboard": rows})
    answer_callback_query(cb_id)


def _dept_name(dept_id):
    """Live department name for an id (falls back to the id itself)."""
    depts = bot_api("departments", {}) or {}
    for d in (depts.get("departments") or [] if isinstance(depts, dict) else []):
        if str(d.get("id")) == str(dept_id):
            return d.get("name") or dept_id
    return dept_id


def _show_depts(chat_id, message_id, cb_id):
    user = bot_user_by_chat(chat_id)
    if not user:
        _edit_link_first(chat_id, message_id, cb_id)
        return
    depts = bot_api("departments", {}) or {}
    dept_list = _visible_departments(
        user, depts.get("departments") or [] if isinstance(depts, dict) else [])
    if not dept_list:
        # API down: regular users see only their own department.
        if user.get("is_super_admin") or user.get("can_view_all"):
            fallback = (
                "🏛️ <b>የሰንበት ትምህርት ቤቱ ክፍሎች ዝርዝር፦</b>\n\n"
                "1. ትምህርት እና ስልጠና ክፍል\n"
                "2. መርሃግብር እና ጉባኤያት ክፍል\n"
                "3. መዝሙርና ስነጥበብ ክፍል\n"
                "4. ልማትና በጎ አድራጎት ክፍል\n"
                "5. መረጃና የውስጥ ግንኙነት ክፍል\n"
                "6. ቁጥጥር ክፍል\n"
                "7. በጀት እና ንብረት አስተዳደር ክፍል\n"
                "8. ሰው ሀብት አስተዳደር ክፍል\n"
                "9. ጽ/ቤት\n"
            )
        else:
            fallback = (
                "🏛️ <b>የሰንበት ትምህርት ቤቱ ክፍሎች ዝርዝር፦</b>\n\n"
                f"• {user.get('department_name', '')}\n\n"
                "የራስህ ክፍል እቅዶች ብቻ ማየት ትችላለህ።"
            )
        edit_message_text(
            chat_id, message_id, fallback,
            {"inline_keyboard": kb_home_row()},
        )
        answer_callback_query(cb_id)
        return
    lines = ["🏛️ <b>የሰንበት ትምህርት ቤቱ ክፍሎች፦</b>", _DIV, ""]
    rows = []
    for d in dept_list:
        name = d.get("name") or ""
        lines.append(f"• {name}")
        rows.append([{"text": f"🏢 {name}", "callback_data": f"dept:{d.get('id')}:0"}])
    lines.append("")
    lines.append("ክፍል ምረጥ — እቅዶቹን ለማየት።")
    rows.extend(kb_home_row())
    edit_message_text(chat_id, message_id, "\n".join(lines), {"inline_keyboard": rows})
    answer_callback_query(cb_id)


def _show_dept_plans(chat_id, message_id, cb_id, dept_id, page):
    user = bot_user_by_chat(chat_id)
    if not user:
        _edit_link_first(chat_id, message_id, cb_id)
        return
    if not (user.get("is_super_admin") or user.get("can_view_all")) \
            and str(dept_id) != str(user.get("department_id")):
        answer_callback_query(cb_id, "የራስህ ክፍል እቅዶች ብቻ ማየት ትችላለህ።")
        dept_id = user.get("department_id")
    data = bot_api("plans_list", {"department_id": dept_id, "chat_id": str(chat_id)})
    if not data:
        answer_callback_query(cb_id, "እቅዶችን ማምጣት አልተቻለም — እንደገና ሞክር።")
        return
    plans = data.get("plans", []) or []
    dept_name = _dept_name(dept_id)
    title = (
        f"🏢 <b>{dept_name}</b>\n"
        f"ጠቅላላ፦ {data.get('total', len(plans))}  •  🚨 የዘገዩ፦ {data.get('overdue_count', 0)}"
    )
    text, kb = render_plan_page(plans, page, f"dept:{dept_id}", title)
    edit_message_text(chat_id, message_id, text, kb)
    answer_callback_query(cb_id)


def _show_plan_detail(chat_id, message_id, cb_id, plan_id, src):
    plan, user = find_plan(chat_id, plan_id)
    if not plan:
        answer_callback_query(cb_id, "እቅዱ አልተገኘም።")
        return
    text, kb = render_plan_detail(plan, user, src)
    edit_message_text(chat_id, message_id, text, kb)
    answer_callback_query(cb_id)


def _do_progress(chat_id, message_id, cb_id, plan_id, pct, src):
    """A progress button tap — verify everything server-side first,
    then update and re-render the detail card with the new bar."""
    user = bot_user_by_chat(chat_id)
    if not user:
        answer_callback_query(cb_id, "Telegram ማገናኘት አለብህ።")
        return
    if user.get("is_super_admin") or user.get("can_view_all"):
        answer_callback_query(cb_id, "ጽ/ቤት እቅድ ክንውን ከአፕ ውስጥ ብቻ ነው የሚያዘምነው።")
        return
    plan, _ = find_plan(chat_id, plan_id)
    if not plan:
        answer_callback_query(cb_id, "እቅዱ አልተገኘም።")
        return
    if plan.get("department_id") != user.get("department_id"):
        answer_callback_query(cb_id, "የሌላ ክፍል እቅድ ክንውን ማዘመን አይቻልም።")
        return
    result = bot_api("plan_progress", {
        "plan_id": plan_id, "progress": pct, "chat_id": str(chat_id),
    })
    if not result:
        answer_callback_query(cb_id, "ክንውን ማዘመን አልተቻለም — እንደገና ሞክር።")
        return
    plan, user = find_plan(chat_id, plan_id)
    if not plan:
        answer_callback_query(cb_id, "እቅዱ አልተገኘም።")
        return
    text, kb = render_plan_detail(plan, user, src)
    edit_message_text(chat_id, message_id, text, kb)
    answer_callback_query(cb_id, f"✅ ክንውን {pct}% ሆኗል")


def handle_callback_query(callback):
    """Route every inline-keyboard tap."""
    data = callback.get("data") or ""
    cb_id = callback.get("id")
    msg = callback.get("message") or {}
    chat_id = (msg.get("chat") or {}).get("id")
    message_id = msg.get("message_id")
    if not data:
        return
    # Link gate: a stranger gets ONLY the link-first message, except the
    # "link" button itself (it shows how to link) — no menu, no plans,
    # no departments, no info, no reset, no approve/reject.
    _linked = bot_user_by_chat(chat_id)
    if not _linked:
        if data == "link" or data.startswith("link:"):
            answer_callback_query(cb_id)
            send_telegram_reply(
                chat_id,
                "🔗 <b>Telegram ማገናኘት</b>\n\n"
                "በአፕ ውስጥ፦ <b>ዳሽቦርድ / ውይይት</b> → <b>Telegram</b> ቁልፍ → <b>«አገናኝ»</b> → ኮድ አግኝተህ እዚህ <b>/start &lt;ኮድ&gt;</b> ብለህ ላክ።\n\n"
                "ኮዱ ለ<b>15 ደቂቃ</b> ብቻ ይሰራል።",
            )
        else:
            _edit_link_first(chat_id, message_id, cb_id)
        return
    if data.startswith("review:"):
        try:
            handle_review_callback(callback)
        except Exception as ex:
            print(f"Error handling review callback: {ex}")
        return
    parts = data.split(":")
    kind = parts[0]
    try:
        if kind == "noop":
            answer_callback_query(cb_id, "ገጽ ለመቀየር ◀️ ቀዳሚ / ቀጣይ ▶️ ተጫን።")
        elif kind == "menu":
            user = bot_user_by_chat(chat_id)
            name = (callback.get("from") or {}).get("first_name", "ተጠቃሚ")
            edit_message_text(chat_id, message_id, menu_text(name, user), kb_menu())
            answer_callback_query(cb_id)
        elif kind == "myplans":
            _show_myplans(chat_id, message_id, cb_id, int(parts[1]) if len(parts) > 1 else 0)
        elif kind == "recent":
            _show_recent(chat_id, message_id, cb_id, int(parts[1]) if len(parts) > 1 else 0)
        elif kind == "plans":
            _show_summary(chat_id, message_id, cb_id)
        elif kind == "depts":
            _show_depts(chat_id, message_id, cb_id)
        elif kind == "dept":
            _show_dept_plans(chat_id, message_id, cb_id, parts[1], int(parts[2]) if len(parts) > 2 else 0)
        elif kind == "plan":
            src = ":".join(parts[2:]) or "menu"
            _show_plan_detail(chat_id, message_id, cb_id, parts[1], src)
        elif kind == "prog":
            src = ":".join(parts[3:]) or "menu"
            _do_progress(chat_id, message_id, cb_id, parts[1], int(parts[2]), src)
        elif kind == "report":
            answer_callback_query(cb_id, "ሪፖርት በአፕ ውስጥ ነው የሚላከው።")
            send_telegram_reply(
                chat_id,
                "📝 <b>ሪፖርት በአፕ ውስጥ ነው የሚላከው</b>\n\n"
                "በአፕ ውስጥ፦ <b>እቅዶች</b> → እቅዱን ምረጥ → <b>«ሪፖርት አስገባ»</b> የሚለውን ተጫን።\n\n"
                "በቦቱ ውስጥ ሪፖርት መላክ አይቻልም — ሪፖርት ማስረጃዎች (ፎቶ / ፋይል) ስለሚፈልግ ነው።",
            )
        elif kind == "link":
            answer_callback_query(cb_id)
            send_telegram_reply(
                chat_id,
                "🔗 <b>Telegram ማገናኘት</b>\n\n"
                "በአፕ ውስጥ፦ <b>ዳሽቦርድ / ውይይት</b> → <b>Telegram</b> ቁልፍ → <b>«አገናኝ»</b> → ኮድ አግኝተህ እዚህ <b>/start &lt;ኮድ&gt;</b> ብለህ ላክ።\n\n"
                "ኮዱ ለ<b>15 ደቂቃ</b> ብቻ ይሰራል።",
            )
        elif kind == "reset":
            answer_callback_query(cb_id)
            _start_reset(chat_id)
        elif kind == "info":
            edit_message_text(
                chat_id, message_id,
                "ℹ️ <b>ዐጸደ ትጉሃን የዕቅድና ሪፖርት አስተዳደር ስርዓት</b>\n\n"
                "ይህ ቦት ከመተግበሪያው ጋር በቀጥታ የተገናኘ ሲሆን፣ ክፍሎች ሪፖርት ሲያስገቡና እቅድ ሲያስተላልፉ በቅጽበት ማሳወቂያዎችን ያደርሳል።\n\n"
                "🟢 ሁኔታ፦ መስመር ላይ (Online 24/7)",
                {"inline_keyboard": kb_home_row()},
            )
            answer_callback_query(cb_id)
        else:
            answer_callback_query(cb_id, "ይህ ቁልፍ አልተረዳም።")
    except Exception as ex:
        print(f"Error handling callback {data}: {ex}")
        answer_callback_query(cb_id, "ስህተት ተፈጥሯል — እንደገና ሞክር።")


def handle_update(update):
    # Inline-keyboard callbacks (menu, lists, progress, review) come
    # first — they carry no "message" of their own.
    if update.get("callback_query"):
        try:
            handle_callback_query(update["callback_query"])
        except Exception as ex:
            print(f"Error handling callback: {ex}")
        return

    msg = update.get("message") or update.get("channel_post")
    if not msg:
        return

    chat_id = msg.get("chat", {}).get("id")
    text = (msg.get("text") or "").strip()
    msg_id = msg.get("message_id")
    user_name = msg.get("from", {}).get("first_name", "ተጠቃሚ")

    if not text:
        return

    linked_user = bot_user_by_chat(chat_id)

    if text.startswith("/start") or text.startswith("/link") or text.startswith("/help"):
        parts = text.split()
        code = parts[1] if len(parts) > 1 else ""
        if code:
            result = bot_api("link_verify", {"code": code, "chat_id": str(chat_id)})
            if result:
                send_telegram_reply(
                    chat_id,
                    f"✅ <b>Telegram ተገናኝቷል!</b>\n\n"
                    f"ሰላም <b>{result.get('full_name', '')}</b> — "
                    f"ይህ account ከ<b>{result.get('department_name', '')}</b> ጋር ተገናኝቷል።\n\n"
                    f"አሁን /myplans ብለህ የክፍልህን እቅዶች ማየት ትችላለህ፤ "
                    f"ማሳሰቢያዎችም ወደዚህ chat ይደርስሃል።",
                    msg_id,
                )
            else:
                send_telegram_reply(
                    chat_id,
                    "⚠️ ኮዱ የተሳሳተ ነው ወይም ጊዜው አልፏል።\n"
                    "በአፕ ውስጥ Telegram አገናኝ የሚለውን ተጫንና አዲስ ኮድ አግኝተህ እንደገና ላክ።",
                    msg_id,
                )
            return
        if linked_user:
            send_telegram_reply(chat_id, menu_text(user_name, linked_user), msg_id, kb_menu())
        else:
            _reply_link_first(chat_id, msg_id)

    elif text.startswith("/reset"):
        _start_reset(chat_id)

    elif text.startswith("/menu"):
        send_telegram_reply(chat_id, menu_text(user_name, linked_user), msg_id, kb_menu())

    elif text.startswith("/cancel"):
        _reset_pending.pop(str(chat_id), None)
        send_telegram_reply(chat_id, "ተቋርጧል — ምንም አልተቀየረም።", msg_id)

    # Link gate: from here on, only linked chats proceed. A stranger
    # gets ONLY the link-first message — no menu, no plans, no
    # departments, no info, no reset, no free-text answers.
    if not linked_user:
        _reset_pending.pop(str(chat_id), None)
        _reply_link_first(chat_id, msg_id)
        return

    elif text.startswith("/myplans"):
        data = bot_api("plans_for", {"chat_id": str(chat_id)})
        if not data:
            send_telegram_reply(chat_id, "⚠️ እቅዶችን ማምጣት አልተቻለም — እባክዎ ትንሽ ቆይተህ እንደገና ሞክር።", msg_id)
            return
        plans = data.get("plans", []) or []
        title = (
            f"📌 <b>የ{linked_user.get('department_name', '')} እቅዶች</b>\n"
            f"ጠቅላላ፦ {data.get('total', len(plans))}  •  🚨 የዘገዩ፦ {data.get('overdue_count', 0)}"
        )
        text, kb = render_plan_page(plans, 0, "myplans", title)
        send_telegram_reply(chat_id, text, msg_id, kb)

    elif text.startswith("/recent"):
        data = bot_api("recent_for", {"chat_id": str(chat_id)})
        if not data:
            send_telegram_reply(chat_id, "⚠️ እቅዶችን ማምጣት አልተቻለም — እባክዎ ትንሽ ቆይተህ እንደገና ሞክር።", msg_id)
            return
        plans = data.get("plans", []) or []
        scope = ""
        if data.get("user"):
            scope = f" — {data['user'].get('department_name', '')}"
        title = f"⏰ <b>የቅርብ 7 ቀናት እቅዶች{scope}</b>"
        text, kb = render_plan_page(plans, 0, "recent", title)
        send_telegram_reply(chat_id, text, msg_id, kb)

    elif text.startswith("/depts"):
        depts = bot_api("departments", {}) or {}
        dept_list = _visible_departments(
            linked_user, depts.get("departments") or [] if isinstance(depts, dict) else [])
        if not dept_list:
            if linked_user.get("is_super_admin") or linked_user.get("can_view_all"):
                depts_text = (
                    "🏛️ <b>የሰንበት ትምህርት ቤቱ ክፍሎች ዝርዝር፦</b>\n\n"
                    "1. ትምህርት እና ስልጠና ክፍል\n"
                    "2. መርሃግብር እና ጉባኤያት ክፍል\n"
                    "3. መዝሙርና ስነጥበብ ክፍል\n"
                    "4. ልማትና በጎ አድራጎት ክፍል\n"
                    "5. መረጃና የውስጥ ግንኙነት ክፍል\n"
                    "6. ቁጥጥር ክፍል\n"
                    "7. በጀት እና ንብረት አስተዳደር ክፍል\n"
                    "8. ሰው ሀብት አስተዳደር ክፍል\n"
                    "9. ጽ/ቤት\n"
                )
            else:
                depts_text = (
                    "🏛️ <b>የሰንበት ትምህርት ቤቱ ክፍሎች ዝርዝር፦</b>\n\n"
                    f"• {linked_user.get('department_name', '')}\n\n"
                    "የራስህ ክፍል እቅዶች ብቻ ማየት ትችላለህ።"
                )
            send_telegram_reply(chat_id, depts_text, msg_id)
            return
        lines = ["🏛️ <b>የሰንበት ትምህርት ቤቱ ክፍሎች፦</b>", _DIV, ""]
        rows = []
        for d in dept_list:
            name = d.get("name") or ""
            lines.append(f"• {name}")
            rows.append([{"text": f"🏢 {name}", "callback_data": f"dept:{d.get('id')}:0"}])
        lines.append("")
        lines.append("ክፍል ምረጥ — እቅዶቹን ለማየት።")
        rows.extend(kb_home_row())
        send_telegram_reply(chat_id, "\n".join(lines), msg_id, {"inline_keyboard": rows})

    elif text.startswith("/plans") or text.startswith("/plan"):
        data = bot_api("plans_summary", {"chat_id": str(chat_id)})
        if not data:
            # LIVE አገልጋዩ ካልተገኘ ወደ ቀድሞው የፋይል ምንጭ መመለስ።
            plans = get_plans_from_database()
            if not (linked_user.get("is_super_admin") or linked_user.get("can_view_all")):
                own_id = str(linked_user.get("department_id"))
                own_name = linked_user.get("department_name", "")
                plans = [p for p in plans
                         if str(p.get("departmentId") or "") == own_id
                         or str(p.get("department") or "") == own_id
                         or (p.get("department_name") or "") == own_name]
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
            return
        lines = [
            "📊 <b>የ2019 ዓ.ም የእቅዶች ማጠቃለያ</b>",
            _DIV,
            f"ጠቅላላ፦ <b>{data.get('total', 0)}</b> እቅዶች  •  🚨 የዘገዩ፦ <b>{data.get('overdue_count', 0)}</b>",
            "",
        ]
        rows = []
        depts = bot_api("departments", {}) or {}
        dept_list = _visible_departments(
            linked_user, depts.get("departments") or [] if isinstance(depts, dict) else [])
        by_dept = data.get("by_department") or {}
        for d in dept_list:
            name = d.get("name") or ""
            cnt = by_dept.get(name, 0)
            lines.append(f"• <b>{_html.escape(name)}</b>፦ {cnt} እቅዶች")
            rows.append([{"text": f"🏢 {name} ({cnt})", "callback_data": f"dept:{d.get('id')}:0"}])
        if not dept_list:
            for name, cnt in by_dept.items():
                lines.append(f"• <b>{_html.escape(name)}</b>፦ {cnt} እቅዶች")
        lines.append("")
        lines.append("ክፍል ምረጥ — እቅዶቹን ለማየት፤ ወይም Telegramህን አገናኝተህ /myplans ብል።")
        rows.append([{"text": "🏠 ዋና ማውጫ", "callback_data": "menu"}])
        send_telegram_reply(chat_id, "\n".join(lines), msg_id, {"inline_keyboard": rows})

    elif text.startswith("/info"):
        info_text = (
            "ℹ️ <b>ዐጸደ ትጉሃን የዕቅድና ሪፖርት አስተዳደር ስርዓት</b>\n\n"
            "ይህ ቦት ከመተግበሪያው ጋር በቀጥታ የተገናኘ ሲሆን፣ ክፍሎች ሪፖርት ሲያስገቡና እቅድ ሲያስተላልፉ በቅጽበት ማሳወቂያዎችን ያደርሳል።\n\n"
            "🟢 ሁኔታ፦ መስመር ላይ (Online 24/7)"
        )
        send_telegram_reply(chat_id, info_text, msg_id, {"inline_keyboard": kb_home_row()})

    elif not text.startswith("/"):
        # /reset የጠየቀ ሰው የተጠቃሚ ስሙን ሲልክ (multi-step reset)።
        pending = _reset_pending.get(str(chat_id))
        if pending and pending.get("stage") == "username":
            if time.time() - pending.get("ts", 0) > 600:
                _reset_pending.pop(str(chat_id), None)
                send_telegram_reply(chat_id, "⏰ ጊዜው አልፏል — /reset ብለህ እንደገና ጀምር።", msg_id)
                return
            _reset_pending.pop(str(chat_id), None)
            _do_reset_request(chat_id, text.split()[0], msg_id)
            return
        # Unknown free text — point at the commands, do not stay silent.
        send_telegram_reply(
            chat_id,
            "ትእዛዙን አልተረዳሁም። /menu ብለህ ከማውጫው ምረጥ — ወይም /plans, /myplans, /recent, /depts, /reset, /info።",
            msg_id,
        )


def _do_reset_request(chat_id, username, msg_id):
    """Ask the PHP API for a reset code and deliver it to the LINKED chat.

    The code goes ONLY to the chat the account is linked to — never to
    the chat that merely typed the username. If the account is not
    linked (or does not exist) the reply stays generic on purpose.
    """
    result = bot_api("reset_request", {"username": username})
    if not result or not result.get("ok"):
        send_telegram_reply(
            chat_id,
            "⚠️ ይህ account ከ Telegram ጋር አልተገናኘም ወይም አልተገኘም።\n"
            "መጀመሪያ በአፕ ውስጥ Telegram አገናኝ — ከዚያ /reset ብለህ ሞክር።",
            msg_id,
        )
        return
    target_chat = result.get("chat_id")
    code = result.get("code")
    name = result.get("full_name") or ""
    _send_telegram_message_to(target_chat,
        f"🔑 <b>የይለፍ ቃል ዳግም ማስጀመሪያ ኮድ</b>\n\n"
        f"ሰላም <b>{name}</b> — የአንድ ጊዜ ኮድህ፦ <b>{code}</b>\n\n"
        f"ኮዱ ለ<b>15 ደቂቃ</b> ብቻ ይሰራል።\n"
        f"በአፕ ውስጥ ከመግቢያ ገጹ «የይለፍ ቃል ረሳህ?» የሚለውን ተጫንና "
        f"ኮዱንና አዲሱን የይለፍ ቃል አስገባ።\n\n"
        f"<i>ይህንን አንተ ካልጠየክህ ኮዱን ለማንም አትስጥ።</i>")
    if str(target_chat) != str(chat_id):
        send_telegram_reply(
            chat_id,
            "📩 ኮድ ወደተገናኘው Telegram account ልኬያለሁ — እዚያ አግኝተህ በአፕ ውስጥ አስገባ።",
            msg_id,
        )

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
            params = {"timeout": 20, "allowed_updates": ["message", "channel_post", "callback_query"]}
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
