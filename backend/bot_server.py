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
# answers /start, /link, /plans, /myplans, /recent, /depts, /reset,
# /info plus the report-review inline-keyboard callbacks. If the
# Flutter app ALSO polled getUpdates, the two would steal updates
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

# 2026-11-26 (bot upgrade): in-memory reset flow state.
# chat_id -> {"stage": "username", "ts": epoch seconds}.
# A restart loses it — the user just sends /reset again.
_reset_pending = {}


def answer_callback_query(callback_query_id, text):
    if not BOT_TOKEN:
        return
    try:
        requests.post(f"{BASE_URL}/answerCallbackQuery", json={
            "callback_query_id": callback_query_id,
            "text": text,
            "show_alert": False,
        }, timeout=10)
    except Exception as e:
        print(f"answerCallbackQuery error: {e}")


def edit_message_text(chat_id, message_id, text):
    if not BOT_TOKEN:
        return
    try:
        requests.post(f"{BASE_URL}/editMessageText", json={
            "chat_id": chat_id,
            "message_id": message_id,
            "text": text,
            "parse_mode": "HTML",
        }, timeout=10)
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


def handle_update(update):
    # Inline-keyboard callbacks (report Approve / Reject) come first —
    # they carry no "message" of their own.
    if update.get("callback_query"):
        try:
            handle_review_callback(update["callback_query"])
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
        link_hint = ""
        if linked_user:
            link_hint = (
                f"\n✅ ይህ account ከ<b>{linked_user.get('department_name', '')}</b> "
                f"({linked_user.get('full_name', '')}) ጋር ተገናኝቷል።\n"
            )
        else:
            link_hint = (
                "\n🔗 Telegramህን ለማገናኘት፦ በአፕ ውስጥ Telegram አገናኝ የሚለውን "
                "ተጫን፣ ኮድ አግኝተህ እዚህ <b>/start &lt;ኮድ&gt;</b> ብለህ ላክ።\n"
            )
        welcome = (
            f"ሰላም <b>{user_name}</b> እንኳን ወደ <b>ዐጸደ ትጉሃን ሰንበት ትምህርት ቤት</b> የእቅድና ሪፖርት ቦት በደህና መጡ! 🕊️\n"
            f"{link_hint}\n"
            "<b>የሚገኙ ትእዛዞች፦</b>\n"
            "📋 /plans - የክፍሎች አጠቃላይ እቅድ ማጠቃለያ\n"
            "📌 /myplans - የኔ ክፍል እቅዶች (የተገናኘ account ብቻ)\n"
            "⏰ /recent - በቅርብ 7 ቀናት ውስጥ የሚደርሱ እቅዶች\n"
            "🏢 /depts - የሁሉም ክፍሎች ስም ዝርዝር\n"
            "🔑 /reset - የይለፍ ቃል ዳግም ማስጀመር\n"
            "📢 /info - ስለ ቦቱ እና መተግበሪያው መረጃ\n"
        )
        send_telegram_reply(chat_id, welcome, msg_id)

    elif text.startswith("/reset"):
        # Linked account? Use their own username straight away.
        if linked_user:
            _do_reset_request(chat_id, linked_user.get("username", ""), msg_id)
            return
        _reset_pending[str(chat_id)] = {"stage": "username", "ts": time.time()}
        send_telegram_reply(
            chat_id,
            "🔑 <b>የይለፍ ቃል ዳግም ማስጀመር</b>\n\n"
            "የተጠቃሚ ስምህን ላክ (ለምሳሌ፦ <b>mezmur</b>)።\n"
            "ኮድ ወደተገናኘው Telegram accountህ ይላካል።\n"
            "ለማቋረጥ /cancel ላክ።",
            msg_id,
        )

    elif text.startswith("/cancel"):
        _reset_pending.pop(str(chat_id), None)
        send_telegram_reply(chat_id, "ተቋርጧል — ምንም አልተቀየረም።", msg_id)

    elif text.startswith("/myplans"):
        if not linked_user:
            send_telegram_reply(
                chat_id,
                "📌 <b>/myplans</b> የራስህን ክፍል እቅዶች ለማየት Telegramህን ማገናኘት አለብህ።\n\n"
                "በአፕ ውስጥ Telegram አገናኝ የሚለውን ተጫን፣ ኮድ አግኝተህ እዚህ <b>/start &lt;ኮድ&gt;</b> ብለህ ላክ።\n\n"
                "የሁሉም ክፍል ማጠቃለያ ለማየት /plans ብል።",
                msg_id,
            )
            return
        data = bot_api("plans_for", {"chat_id": str(chat_id)})
        if not data:
            send_telegram_reply(chat_id, "⚠️ እቅዶችን ማምጣት አልተቻለም — እባክዎ ትንሽ ቆይተህ እንደገና ሞክር።", msg_id)
            return
        plans = data.get("plans", []) or []
        # "Today" in Addis Ababa time — the Render container runs on
        # UTC, and the PHP side also uses Africa/Addis_Ababa.
        today = _dt.now(_tz(_td(hours=3))).strftime("%Y-%m-%d")
        overdue = [p for p in plans
                   if (p.get("due_date") or "") < today
                   and (p.get("progress_percent") or 0) < 100
                   and p.get("latest_report_status") not in ("submitted", "under_review", "approved")]
        upcoming = [p for p in plans
                    if (p.get("due_date") or "") >= today
                    and (p.get("progress_percent") or 0) < 100
                    and p.get("latest_report_status") not in ("submitted", "under_review", "approved")]
        upcoming.sort(key=lambda p: (p.get("due_date") or "", p.get("id") or ""))
        lines = [f"📌 <b>የ{linked_user.get('department_name', '')} እቅዶች (ጠቅላላ፦ {data.get('total', len(plans))})፦</b>\n"]
        if overdue:
            lines.append(f"🚨 <b>የዘገዩ ({len(overdue)})፦</b>")
            for p in overdue[:8]:
                lines.append(f"• “{_short(p.get('main_task'))}” — {p.get('due_date_ethiopian') or p.get('due_date') or ''}")
            lines.append("")
        if upcoming:
            lines.append(f"⏰ <b>በቅርብ የሚደርሱ ({len(upcoming)})፦</b>")
            for p in upcoming[:8]:
                lines.append(f"• “{_short(p.get('main_task'))}” — {p.get('due_date_ethiopian') or p.get('due_date') or ''}")
        if not overdue and not upcoming:
            lines.append("🎉 ምንም የዘገየ ወይም በቅርብ የሚደርስ እቅድ የለም!")
        lines.append("\n<i>ዝርዝር እቅዶችን እና ሪፖርቶችን በሞባይል መተግበሪያው ውስጥ መከታተል ይችላሉ!</i>")
        send_telegram_reply(chat_id, "\n".join(lines), msg_id)

    elif text.startswith("/recent"):
        data = bot_api("recent_for", {"chat_id": str(chat_id)})
        if not data:
            send_telegram_reply(chat_id, "⚠️ እቅዶችን ማምጣት አልተቻለም — እባክዎ ትንሽ ቆይተህ እንደገና ሞክር።", msg_id)
            return
        plans = data.get("plans", []) or []
        scope = ""
        if data.get("user"):
            scope = f" — {data['user'].get('department_name', '')}"
        if not plans:
            send_telegram_reply(
                chat_id,
                f"⏰ <b>የቅርብ 7 ቀናት እቅዶች{scope}፦</b>\n\nበቅርብ 7 ቀናት ውስጥ የሚደርስ ወይም የዘገየ እቅድ የለም። 🎉",
                msg_id,
            )
            return
        lines = [f"⏰ <b>የቅርብ 7 ቀናት እቅዶች{scope} ({len(plans)})፦</b>\n"]
        for p in plans[:15]:
            dept = f"[{p.get('department_name', '')}] " if not data.get("user") else ""
            lines.append(f"• {dept}“{_short(p.get('main_task'))}” — {p.get('due_date_ethiopian') or p.get('due_date') or ''}")
        send_telegram_reply(chat_id, "\n".join(lines), msg_id)

    elif text.startswith("/depts"):
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
        send_telegram_reply(chat_id, depts_text, msg_id)

    elif text.startswith("/plans") or text.startswith("/plan"):
        data = bot_api("plans_summary", {})
        if not data:
            # LIVE አገልጋዩ ካልተገኘ ወደ ቀድሞው የፋይል ምንጭ መመለስ።
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
            return
        lines = [f"📊 <b>የ2019 ዓ.ም የእቅዶች ማጠቃለያ (ጠቅላላ፦ {data.get('total', 0)})፦</b>\n"]
        for dept, cnt in (data.get("by_department") or {}).items():
            lines.append(f"• <b>{dept}</b>፦ {cnt} እቅዶች")
        if data.get("overdue_count"):
            lines.append(f"\n🚨 <b>የዘገዩ፦ {data['overdue_count']}</b>")
        lines.append("\n<i>የራስህን ክፍል ብቻ ለማየት Telegramህን አገናኝተህ /myplans ብል።</i>")
        send_telegram_reply(chat_id, "\n".join(lines), msg_id)

    elif text.startswith("/info"):
        info_text = (
            "ℹ️ <b>ዐጸደ ትጉሃን የዕቅድና ሪፖርት አስተዳደር ስርዓት</b>\n\n"
            "ይህ ቦት ከመተግበሪያው ጋር በቀጥታ የተገናኘ ሲሆን፣ ክፍሎች ሪፖርት ሲያስገቡና እቅድ ሲያስተላልፉ በቅጽበት ማሳወቂያዎችን ያደርሳል።\n\n"
            "🟢 ሁኔታ፦ መስመር ላይ (Online 24/7)"
        )
        send_telegram_reply(chat_id, info_text, msg_id)

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
            "ትእዛዙን አልተረዳሁም። የሚገኙ ትእዛዞች፦ /plans, /myplans, /recent, /depts, /reset, /info — ወይም /help።",
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
