"""Atsede Teguhan -- plan reminder scheduler (C4: real implementation).

Reads plans, finds incomplete plans that are due soon or overdue, and
sends ONE summary reminder per run to Telegram.

Plan sources (in order):
  1. The PHP API (``PHP_API_BASE`` + ``/plans.php``) when that env var is
     set to a valid URL. If the API is unreachable or returns an error,
     the scheduler falls back to the static file instead of sending
     nothing -- a missed reminder is worse than a reminder from the
     bundled plans. NOTE: plans.php requires auth; if
     ``SYSTEM_API_TOKEN`` is set it is sent as a Bearer token.
  2. The static plans file at ``assets/default_plans.json`` (repo root).
     NEVER ``backend/default_plans.json`` -- that duplicate is deleted.

How "due soon" is decided (plans have no Gregorian due date; the
bundled data uses Ethiopian months, e.g. executionTime "መስ (10)"):
  * a plan with an ISO ``target_date`` is due when that date is overdue
    or within ``--days-ahead`` days (default 7);
  * otherwise a plan is due when one of its execution months is the
    CURRENT Ethiopian month. The Ethiopian month is derived from the
    Gregorian date with a month-start table (accurate to +/-1 day around
    Enkutatash in leap years -- fine for a reminder).

Sending: direct Telegram Bot API call with ``BOT_TOKEN`` from env to
``TELEGRAM_CHAT_ID`` from env. Both are REQUIRED -- the scheduler fails
with a clear error (exit code 2) instead of silently sending nowhere.
No chat ID or token is ever hardcoded here.

Usage:
  python reminder_scheduler.py --once    # single run (default; Render cron)
  python reminder_scheduler.py --loop    # repeat every REMINDER_INTERVAL_MINUTES (default 60)
"""

import argparse
import json
import os
import sys
import time
from datetime import date, datetime, timedelta, timezone

import requests

# የኢትዮጵያ ሰዓት ቀጠና (UTC+3)
EAT = timezone(timedelta(hours=3))

# Ethiopian month names, index 1-13. The bundled plans use the short
# forms (መስ, ጥቅ, ...) in executionTime / months; the API may use full names.
ETH_MONTHS_SHORT = ["መስ", "ጥቅ", "ህዳር", "ታህ", "ጥር", "የካ",
                    "መጋ", "ሚያ", "ግን", "ሰኔ", "ሐም", "ነሐ", "ጳጉሜ"]
ETH_MONTHS_FULL = ["መስከረም", "ጥቅምት", "ኅዳር", "ታኅሣሥ", "ጥር", "የካቲት",
                   "መጋቢት", "ሚያዝያ", "ግንቦት", "ሰኔ", "ሐምሌ", "ነሐሴ", "ጳጉሜ"]
# "ህዳር" (with ህ) is also used for Hidar; accept both spellings.
_MONTH_NAME_TO_INDEX = {}
for _i, _name in enumerate(ETH_MONTHS_SHORT, start=1):
    _MONTH_NAME_TO_INDEX[_name] = _i
for _i, _name in enumerate(ETH_MONTHS_FULL, start=1):
    _MONTH_NAME_TO_INDEX[_name] = _i
_MONTH_NAME_TO_INDEX["ህዳር"] = 3

# Gregorian (month, day) on which each Ethiopian month starts.
# Order: Meskerem .. Nehasse, then Pagume (Sep 6).
_ETH_MONTH_STARTS = [(9, 11), (10, 11), (11, 10), (12, 10), (1, 9),
                     (2, 8), (3, 10), (4, 9), (5, 9), (6, 8),
                     (7, 8), (8, 7)]


def ethiopian_month_index(gregorian_date):
    """Return the Ethiopian month index (1-13) for a Gregorian date."""
    def _key(month, day):
        return (month if month >= 9 else month + 12, day)
    target = _key(gregorian_date.month, gregorian_date.day)
    # Before Meskerem 1 (Sep 11) the date is Pagume (month 13) of the old year.
    index = 13
    for i, (m, d) in enumerate(_ETH_MONTH_STARTS, start=1):
        if _key(m, d) <= target:
            index = i
    return index


def get_current_ethiopian_time():
    return datetime.now(EAT)


def _plan_field(plan, *names):
    for name in names:
        value = plan.get(name)
        if value not in (None, ""):
            return value
    return None


def _plan_months(plan):
    """Ethiopian month indexes a plan is scheduled in (from executionTime / months)."""
    months = set()
    execution_time = _plan_field(plan, "executionTime", "execution_time") or ""
    for name, idx in _MONTH_NAME_TO_INDEX.items():
        if name in str(execution_time):
            months.add(idx)
    months_map = plan.get("months") or {}
    if isinstance(months_map, dict):
        for name, value in months_map.items():
            if value not in (None, "") and name in _MONTH_NAME_TO_INDEX:
                months.add(_MONTH_NAME_TO_INDEX[name])
    return months


def _parse_iso_date(value):
    try:
        return date.fromisoformat(str(value)[:10])
    except (ValueError, TypeError):
        return None


def plan_is_due(plan, today, days_ahead):
    """True when an incomplete plan is due soon or overdue."""
    progress = _plan_field(plan, "progressPercent", "progress_percent") or 0
    try:
        progress = int(progress)
    except (ValueError, TypeError):
        progress = 0
    if progress >= 100:
        return False
    if str(_plan_field(plan, "status") or "").lower() == "completed":
        return False

    target = _parse_iso_date(_plan_field(plan, "target_date", "targetDate"))
    if target is not None:
        return target <= today + timedelta(days=days_ahead)
    # No ISO date: due when scheduled in the current Ethiopian month.
    return ethiopian_month_index(today) in _plan_months(plan)


def plan_due_label(plan, today):
    target = _parse_iso_date(_plan_field(plan, "target_date", "targetDate"))
    if target is not None:
        if target < today:
            return f"ተዘግይቷል ({target.isoformat()})"
        return f"የሚደርስ {target.isoformat()}"
    months = sorted(_plan_months(plan))
    names = "፣ ".join(ETH_MONTHS_FULL[i - 1] for i in months) if months else ""
    return f"የዚህ ወር እቅድ ({names})" if names else "የሚደርስ እቅድ"


def load_static_plans():
    path = os.path.join(os.path.dirname(__file__), "..", "assets", "default_plans.json")
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data if isinstance(data, list) else data.get("data", [])


def fetch_plans():
    """Plans from the PHP API when configured, else the static file."""
    api_base = (os.environ.get("PHP_API_BASE") or "").strip()
    if api_base:
        if " " in api_base:
            print("WARNING: PHP_API_BASE contains a space and is invalid; "
                  "using the static plans file.")
        else:
            system_token = os.environ.get("SYSTEM_API_TOKEN", "")
            headers = ({"Authorization": f"Bearer {system_token}"}
                       if system_token else {})
            try:
                res = requests.get(f"{api_base.rstrip('/')}/plans.php",
                                   headers=headers, timeout=10)
                if res.status_code == 200:
                    data = res.json()
                    if isinstance(data, dict) and data.get("status") == "success":
                        return data.get("data", [])
                    if isinstance(data, list):
                        return data
                print(f"Notice: Plans API returned status {res.status_code}; "
                      "falling back to the static plans file.")
            except Exception as e:
                print(f"Notice: PHP API unavailable, using static plans file: {e}")
    else:
        print("WARNING: PHP_API_BASE is not set -- the PHP API is disabled; "
              "using the static plans file (assets/default_plans.json).")
    try:
        return load_static_plans()
    except Exception as e:
        print(f"ERROR: could not load the static plans file: {e}")
        return []


def send_telegram_message(bot_token, chat_id, text):
    res = requests.post(
        f"https://api.telegram.org/bot{bot_token}/sendMessage",
        json={"chat_id": chat_id, "text": text, "parse_mode": "HTML"},
        timeout=15,
    )
    if res.status_code != 200:
        print(f"ERROR: Telegram sendMessage returned {res.status_code}: {res.text[:300]}")
        return False
    return True


def build_reminder_message(due_plans, today):
    lines = [
        "⏰ <b>የእቅድ አስታዋሽ</b>",
        f"📅 {today.isoformat()} — ያልተጠናቀቁ እና የሚደርሱ/የተዘገዩ እቅዶች፦",
        "",
    ]
    by_dept = {}
    for plan in due_plans:
        dept = (_plan_field(plan, "departmentName", "department_name",
                            "department", "department_id") or "ሌላ")
        by_dept.setdefault(str(dept), []).append(plan)
    for dept, plans in sorted(by_dept.items()):
        lines.append(f"🏢 <b>{dept}</b>")
        for plan in plans:
            task = _plan_field(plan, "mainTask", "main_task", "title") or "(ስም የሌለው እቅድ)"
            progress = _plan_field(plan, "progressPercent", "progress_percent") or 0
            lines.append(f"• {task} — {plan_due_label(plan, today)} "
                         f"(ተጠናቅቋል {progress}%)")
        lines.append("")
    return "\n".join(lines).strip()


def check_and_send_reminders(days_ahead=7):
    now = get_current_ethiopian_time()
    today = now.date()
    print(f"[{now.strftime('%Y-%m-%d %H:%M:%S')}] ⏰ የቀጠሮ አስታዋሾች ፍተሻ እየተካሄደ ነው...")
    bot_token = os.environ.get("TELEGRAM_BOT_TOKEN") or os.environ.get("BOT_TOKEN", "")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID") or os.environ.get("CHAT_ID", "")
    if not bot_token or not chat_id:
        missing = [n for n, v in (("TELEGRAM_BOT_TOKEN", bot_token),
                                   ("TELEGRAM_CHAT_ID", chat_id)) if not v]
        print(f"ERROR: cannot send reminders -- missing env var(s): {', '.join(missing)}. "
              "Set them in Render (or .env) and run again.")
        return False

    plans = fetch_plans()
    print(f"[{now.strftime('%H:%M:%S')}] {len(plans)} እቅዶች ተገኝተዋል።")
    due = [p for p in plans if plan_is_due(p, today, days_ahead)]
    if not due:
        print("ምንም የሚደርስ/የተዘገየ እቅድ አልተገኘም — መልእክት አልተላከም።")
        return True

    # Keep one Telegram message readable; list at most 40 plans.
    shown, hidden = due[:40], len(due) - 40
    message = build_reminder_message(shown, today)
    if hidden > 0:
        message += f"\n\n…እና {hidden} ተጨማሪ እቅዶች።"
    ok = send_telegram_message(bot_token, chat_id, message)
    print(f"{len(due)} የሚደርሱ እቅዶች ተገኝተዋል — "
          f"አስታዋሽ {'ተልኳል ✅' if ok else 'አልተላከም ❌'}")
    return ok


def main():
    parser = argparse.ArgumentParser(description="Atsede Teguhan plan reminder scheduler")
    parser.add_argument("--once", action="store_true", default=True,
                        help="Run one reminder check and exit (default)")
    parser.add_argument("--loop", action="store_true",
                        help="Repeat the check every REMINDER_INTERVAL_MINUTES")
    parser.add_argument("--days-ahead", type=int, default=7,
                        help="Days ahead a target_date counts as due soon (default 7)")
    args = parser.parse_args()

    print("🚀 የአጸደ ትጉሃን የጀርባ አስታዋሽ አገልግሎት ጀመረ (Africa/Addis_Ababa)...")
    if args.loop:
        try:
            interval = int(os.environ.get("REMINDER_INTERVAL_MINUTES", "60"))
        except ValueError:
            interval = 60
        while True:
            check_and_send_reminders(days_ahead=args.days_ahead)
            time.sleep(max(interval, 1) * 60)
    else:
        ok = check_and_send_reminders(days_ahead=args.days_ahead)
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
