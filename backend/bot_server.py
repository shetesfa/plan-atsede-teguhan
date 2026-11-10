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
PHP_API_BASE = os.environ.get("PHP_API_BASE", "http://127.0.0.1/plan%20atsedeteguhan/api")

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
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type,Authorization'
        response.headers['Access-Control-Allow-Methods'] = 'GET,POST,OPTIONS'
    return response

def get_plans_from_database(dept=None):
    """እቅዶችን በቀጥታ ከ MySQL / PHP API በማምጣት አንድ የእውነት ምንጭ (Single Source of Truth) መኖሩን ያረጋግጣል"""
    try:
        url = f"{PHP_API_BASE}/plans.php"
        params = {}
        if dept:
            params["dept"] = dept
        res = requests.get(url, params=params, timeout=5)
        if res.status_code == 200:
            data = res.json()
            if data.get("status") == "success":
                return data.get("data", [])
    except Exception as e:
        print(f"Notice: PHP API unavailable, using local JSON fallback: {e}")

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
    has_token = bool(BOT_TOKEN)
    token_preview = (BOT_TOKEN[:10] + "...") if has_token else "NOT_CONFIGURED"
    return jsonify({
        "status": "online",
        "service": "Atsede Teguhan Telegram Bot & Background Scheduler",
        "bot_configured": has_token,
        "bot_token_prefix": token_preview,
        "chat_id_configured": bool(CHAT_ID),
        "timezone": "Africa/Addis_Ababa"
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
# ==============================================================
@app.route("/api/send_notice", methods=["POST", "OPTIONS"])
def send_notice():
    if request.method == "OPTIONS":
        return "", 200
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
    body = request.get_json(silent=True) or {}
    target_chat = body.get("chat_id") or CHAT_ID
    text = body.get("text", "")
    parse_mode = body.get("parse_mode", "HTML")
    custom_token = body.get("bot_token")
    token_to_use = custom_token or BOT_TOKEN
    if not token_to_use:
        return jsonify({"ok": False, "description": "No bot token provided"}), 400

    url = f"https://api.telegram.org/bot{token_to_use}/sendMessage"
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
    try:
        chat_id = request.form.get("chat_id") or CHAT_ID
        caption = request.form.get("caption", "")
        custom_token = request.form.get("bot_token")
        token_to_use = custom_token or BOT_TOKEN
        if not token_to_use:
            return jsonify({"ok": False, "description": "No bot token provided"}), 400

        url = f"https://api.telegram.org/bot{token_to_use}/sendDocument"
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
    try:
        chat_id = request.form.get("chat_id") or CHAT_ID
        caption = request.form.get("caption", "")
        custom_token = request.form.get("bot_token")
        token_to_use = custom_token or BOT_TOKEN
        if not token_to_use:
            return jsonify({"ok": False, "description": "No bot token provided"}), 400

        url = f"https://api.telegram.org/bot{token_to_use}/sendPhoto"
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
    if not BOT_TOKEN:
        print("⚠️ የቴሌግራም ቦት ቶከን አልተዋቀረም፤ ፖሊንግ አይሰራም።")
        return

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
