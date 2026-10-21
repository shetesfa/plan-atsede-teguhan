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
# የቴሌግራም ቦት ውቅር (Bot Configuration)
# ==============================================================
BOT_TOKEN = os.environ.get("BOT_TOKEN", "8754142388:AAGKJUQ9PoeCgrlFNRQQlXEPy4uldnAP_c8")
CHAT_ID = os.environ.get("CHAT_ID", "-1004395752939")
BASE_URL = f"https://api.telegram.org/bot{BOT_TOKEN}"

# Flask Web Server (ለ Render.com እና ለሌሎች ነፃ ሆስቲንጎች 24/7 ጤናማ መሆኑን ማሳወቂያ)
app = Flask(__name__)

PLANS_CACHE = []

def load_plans():
    """የእቅድ ዳታዎችን ከ default_plans.json ፋይል ይጭናል"""
    global PLANS_CACHE
    possible_paths = [
        os.path.join(os.path.dirname(__file__), "..", "assets", "default_plans.json"),
        os.path.join(os.path.dirname(__file__), "default_plans.json"),
        "assets/default_plans.json",
    ]
    for p in possible_paths:
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    PLANS_CACHE = json.load(f)
                    print(f"✅ {len(PLANS_CACHE)} እቅዶች በተሳካ ሁኔታ ተጭነዋል ከ {p}")
                    return
            except Exception as e:
                print(f"Error reading plans: {e}")
    print("⚠️ default_plans.json አልተገኘም ወይም ባዶ ነው")

@app.route("/", methods=["GET"])
def home():
    return jsonify({
        "status": "online",
        "service": "Atsede Teguhan Telegram Bot & API Server",
        "bot_active": True,
        "plans_count": len(PLANS_CACHE),
        "chat_id": CHAT_ID
    })

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "time": time.time()})

@app.route("/api/plans", methods=["GET"])
def get_plans():
    """እቅዶችን በ API ያቀርባል"""
    dept = request.args.get("dept")
    if dept:
        filtered = [p for p in PLANS_CACHE if p.get("department") == dept or p.get("departmentId") == dept]
        return jsonify({"status": "success", "count": len(filtered), "data": filtered})
    return jsonify({"status": "success", "count": len(PLANS_CACHE), "data": PLANS_CACHE})

@app.route("/api/send_notice", methods=["POST"])
def send_notice():
    """ከመተግበሪያው የሚመጣ ማሳወቂያ ወይም ሪፖርት ወደ ቴሌግራም ይልካል"""
    body = request.get_json(silent=True) or {}
    message = body.get("message", "")
    chat_id = body.get("chat_id", CHAT_ID)
    if not message:
        return jsonify({"error": "መልእክት አልተሰጠም"}), 400
    
    try:
        res = requests.post(f"{BASE_URL}/sendMessage", json={
            "chat_id": chat_id,
            "text": message,
            "parse_mode": "HTML"
        }, timeout=10)
        return jsonify(res.json())
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ==============================================================
# የቴሌግራም ቦት አዳማጭ ሉፕ (Telegram Bot Polling Loop)
# ==============================================================
def send_telegram_reply(chat_id, text, reply_to_message_id=None):
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

    # ትእዛዞች (Commands)
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
            "10. ጽ/ቤት\n\n"
            "<i>የአንድን ክፍል እቅድ ለማየት ለምሳሌ፦ /plan_ትምህርት ወይም /plan_ልማት ብለው ይጻፉ።</i>"
        )
        send_telegram_reply(chat_id, depts_text, msg_id)

    elif text.startswith("/plans") or text.startswith("/plan"):
        total = len(PLANS_CACHE)
        if total == 0:
            send_telegram_reply(chat_id, "⚠️ በአሁኑ ወቅት የተመዘገበ እቅድ አልተገኘም።", msg_id)
            return

        # ማጠቃለያ በክፍሎች
        summary = {}
        for p in PLANS_CACHE:
            dept = p.get("department", "ሌላ")
            summary[dept] = summary.get(dept, 0) + 1
        
        lines = [f"📊 <b>የ2019 ዓ.ም የእቅዶች ማጠቃለያ (ጠቅላላ፦ {total})፦</b>\n"]
        for dept, cnt in summary.items():
            lines.append(f"• <b>{dept}</b>፦ {cnt} እቅዶች")
        lines.append("\n<i>ዝርዝር እቅዶችን እና ሪፖርቶችን በሞባይል መተግበሪያው ውስጥ መከታተል ይችላሉ!</i>")
        send_telegram_reply(chat_id, "\n".join(lines), msg_id)

    elif text.startswith("/recent") or text.startswith("/today"):
        lines = ["📅 <b>የቅርብ ጊዜ እና የቀን እቅዶች ናሙና፦</b>\n"]
        dated = [p for p in PLANS_CACHE if p.get("targetDate") or p.get("month")]
        for p in dated[:6]:
            d = p.get("targetDate") or p.get("month") or "-"
            lines.append(f"▫️ <b>[{d}]</b> {p.get('title', 'እቅድ')} (<i>{p.get('department', '')}</i>)")
        send_telegram_reply(chat_id, "\n".join(lines), msg_id)

    elif text.startswith("/info"):
        info_text = (
            "ℹ️ <b>አጸደ ትጉሃን የዕቅድና ሪፖርት አስተዳደር ስርዓት</b>\n\n"
            "ይህ ቦት ከመተግበሪያው ጋር በቀጥታ የተገናኘ ሲሆን፣ ክፍሎች ሪፖርት ሲያስገቡና እቅድ ሲያስተላልፉ በቅጽበት ማሳወቂያዎችን ያደርሳል።\n\n"
            f"📍 ግሩፕ ID: <code>{CHAT_ID}</code>\n"
            "🟢 ሁኔታ፦ መስመር ላይ (Online 24/7)"
        )
        send_telegram_reply(chat_id, info_text, msg_id)

def bot_polling_loop():
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
            # print(f"Polling loop notice: {e}")
            time.sleep(3)
        time.sleep(0.5)

if __name__ == "__main__":
    load_plans()
    # የቴሌግራም ቦትን በጀርባ ትሬድ ማስጀመር
    poller_thread = threading.Thread(target=bot_polling_loop, daemon=True)
    poller_thread.start()
    
    port = int(os.environ.get("PORT", 8080))
    print(f"🌍 የ Flask ዌብ አገልጋይ በፖርት {port} ላይ እየሰራ ነው...")
    app.run(host="0.0.0.0", port=port)
