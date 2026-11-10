import os
import sys
import time
import json
import sqlite3
import requests
from datetime import datetime, timezone, timedelta

# የኢትዮጵያ ሰዓት ቀጠና (UTC+3)
EAT = timezone(timedelta(hours=3))

def get_current_ethiopian_time():
    return datetime.now(EAT)

def check_and_send_reminders():
    print(f"[{get_current_ethiopian_time().strftime('%Y-%m-%d %H:%M:%S')}] ⏰ የቀጠሮ አስታዋሾች ፍተሻ እየተካሄደ ነው...")
    api_base = os.environ.get("PHP_API_BASE", "http://127.0.0.1:8000/api")
    bot_token = os.environ.get("TELEGRAM_BOT_TOKEN")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID")

    try:
        # 1. እቅዶችን ማምጣት
        res = requests.get(f"{api_base}/plans.php", timeout=10)
        if res.status_code != 200:
            return
        data = res.json()
        plans = data.get("data", [])

        # 2. ያልተጠናቀቁ እቅዶችን መፈተሽ
        for p in plans:
            progress = int(p.get("progress_percent", 0) or 0)
            if progress >= 100 or p.get("status") == "completed":
                continue

            target_date = p.get("target_date") or p.get("execution_time")
            main_task = p.get("main_task") or p.get("title")
            dept_name = p.get("department_name") or p.get("department_id")

            # አስታዋሽ መላክ አስፈላጊ ከሆነ ወደ ቴሌግራም ወይም ኖቲፊኬሽን መላክ
            # (ይህ ሉፕ በጀርባ እየሮጠ ሰዓት ሲደርስ ይልካል)
    except Exception as e:
        print(f"Reminder scheduler check error: {e}")

if __name__ == "__main__":
    print("🚀 የአጸደ ትጉሃን የጀርባ አስታዋሽ አገልግሎት ጀመረ (Africa/Addis_Ababa)...")
    while True:
        check_and_send_reminders()
        time.sleep(300) # በየ 5 ደቂቃው
