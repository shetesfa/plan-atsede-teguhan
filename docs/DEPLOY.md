# Deploy Guide — Atsede Teguhan Planning & Report App

> **Nothing is deployed by this document — it is instructions only.**
> Tesfa (or whoever holds the hosting logins) follows these steps.
> No secret VALUES are written anywhere in this file — only env var
> NAMES. Set every value in the hosting dashboard / `.env` file only,
> never in git, never in chat.

## Where things stand (2026-11-14)

| Piece | Status |
|---|---|
| Python Telegram bot on Render (`plan-atsede-teguhan.onrender.com`) | **EXISTS — Tesfa's service. Keep it, do not recreate it.** Only its env vars change (see §4). |
| PHP API (`api/*.php`) + MySQL | **NOT hosted anywhere yet. New, from scratch.** |
| App code | Only in GitHub (`shetesfa/plan-atsede-teguhan`, branch `fix/audit-2026-11-14`). |

Deploy order: **(1)** host the PHP API + MySQL, **(2)** point the bot at it,
**(3)** point the Flutter app at it.

**Preferred path is A (42web).** Path B (Render Docker) is the alternative
if 42web does not work out. Do only one of them — not both.

---

## Path A (PREFERRED) — 42web / InfinityFree: PHP API + MySQL

Tesfa already has a 42web account. Everything in this path is free.

### A1. Upload the API files

1. In the 42web control panel open **File Manager**.
2. Go into `htdocs/` (the web root of the domain, e.g. `<name>.42web.io`).
3. Create a folder `api/` inside `htdocs/`.
4. Upload **all files from the repo's `api/` folder** into `htdocs/api/`
   (`auth.php`, `chat.php`, `config.php`, `db.php`, `documents.php`,
   `files.php`, `notifications.php`, `plans.php`, `reports.php`,
   `sync.php`, `health.php`, the `uploads/` folder, and `.env.example`).
5. Do **NOT** upload any `.env` file from your computer (there is none
   in git — that is correct). The `.env` is created on the server in step A3.

### A2. Create the MySQL database

1. In the 42web control panel open **MySQL Databases** and create a new
   database. Write down the values the panel shows you:
   - MySQL hostname (looks like `sqlXXX.42web.io`)
   - Database name
   - MySQL username
   - MySQL password
2. Open **phpMyAdmin** for that database and import the SQL files **in this order**:
   1. `database/atsede_db.sql` — base schema (departments, users, plans, …)
   2. `database/migrations/01_advanced_schema.sql`
   3. `database/migrations/02_security_and_auth_hardening.sql`
   4. `database/migrations/03_per_user_read_receipts.sql`
   5. `database/migrations/04_production_hardening_and_idempotency.sql`
   
   (In phpMyAdmin: select the database → **Import** → choose file → **Go**.
   Repeat for each file. If an import reports "already exists", that step
   already ran — continue with the next file.)
3. ⚠️ **Login depends on the seed-password fix in this same branch (audit C2).**
   The old seed passwords do not work. Do not test login until that fix
   is merged; testing the API health endpoint (step A4) does not need login.

### A3. Configure the API (`api/.env` on the server)

How `api/config.php` reads config: it loads `api/.env` first (then a
repo-root `.env`), and **real environment variables win over `.env`**.
On 42web there are no per-app env vars, so the `.env` file IS the config.

1. In the file manager, inside `htdocs/api/`, make a **copy** of
   `.env.example` and name the copy `.env`.
2. Edit `htdocs/api/.env` and set exactly these keys (names only — values
   come from step A2 and from a generator):
   - `APP_ENV=production`
   - `DB_HOST=` — the MySQL hostname from the 42web panel
   - `DB_NAME=` — the database name from the panel
   - `DB_USER=` — the MySQL username from the panel
   - `DB_PASS=` — the MySQL password from the panel
     (⚠️ the key is `DB_PASS`, not `DB_PASSWORD` — `config.php` reads `DB_PASS`)
   - `DB_CHARSET=utf8mb4`
   - `JWT_SECRET=` — a long random secret, **at least 32 characters**.
     Generate one with `openssl rand -base64 32` (or any password generator).
     The API **refuses to start** without it.
   - `TELEGRAM_BOT_TOKEN=` and `TELEGRAM_CHAT_ID=` — only if the PHP API
     itself must send Telegram messages; otherwise leave them empty.
   - `ALLOWED_ORIGINS=` — only needed if the Flutter **web** build is
     hosted on another domain; the Render bot origin is already allowed
     by default.
3. The API refuses to start if `JWT_SECRET` is missing/short, or if
   `DB_USER` / `DB_PASS` are missing, or if `DB_PASS` is empty in
   production — so a `500` from any endpoint usually means `.env` is
   wrong; check those three keys first.
4. Never commit this `.env` to git and never paste its values in chat.

### A4. Verify the API is up

In a browser (or `curl`) open:

```
https://<your 42web domain>/api/health.php
```

Expected: `{"status":"ok","service":"plan-atsede-php-api"}`

If that works, the PHP API is live. The login/plans endpoints
(`auth.php`, `plans.php`, …) need a login token — test them from the app,
not from the browser.

### A5. Point the Flutter app at the 42web API

The app's API address is set **at build time** (see the note in
`lib/services/api_service.dart`):

```
flutter build apk --dart-define API_BASE_URL=https://<your 42web domain>/api
```

(or set `ApiService.baseUrl = 'https://<your 42web domain>/api'` — it can
also be changed on the login screen).
The address must end with `/api`, with no trailing slash and no spaces.

---

## Path B (ALTERNATIVE) — Render Docker: PHP API only

Use this only if Path A does not work. The code for it is already in the
repo: `api/Dockerfile` + the `plan-atsede-php-api` service in
`backend/render.yaml`.

1. In the Render Dashboard, create the service from the repo blueprint
   (`backend/render.yaml`) or as a new **Web Service → Docker**, with
   Dockerfile path `./api/Dockerfile` and Docker context `.` (repo root).
2. Set these env vars in the Render Dashboard (**names only — values are
   never written in the repo**):
   `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_NAME`, `JWT_SECRET` (≥ 32 chars),
   `APP_ENV=production`.
3. ⚠️ **Render has no free MySQL.** `DB_HOST` must point at an **external**
   MySQL — e.g. the MySQL database created on 42web in step A2. The
   database host must accept connections from Render's servers.
4. Verify with `https://<render service URL>/health.php` — expected
   `{"status":"ok","service":"plan-atsede-php-api"}`.
5. Point the app at it exactly as in step A5, using the Render service URL
   + `/api`.

---

## §4. Render bot service — KEEP the existing service, update env vars

Do **not** create a new bot service. The existing service
(`atsede-telegram-bot`, `plan-atsede-teguhan.onrender.com`) stays.
In the Render Dashboard, open that service → **Environment** and make
sure these are set (add the ones that are missing):

| Env var | Value (name only — set in Dashboard) |
|---|---|
| `BOT_TOKEN` | The bot token (already set). ⚠️ The token exposed in git history (audit C1) must still be **rotated in BotFather** and the new value put here — rotating is a separate step, not part of this deploy. |
| `BOT_PROXY_SECRET` | **NEW (audit H2).** A long random secret. The Flutter app sends it as header `X-Bot-Proxy-Secret` on every bot-proxy call. Set the **same** value in the app's config. |
| `TELEGRAM_CHAT_ID` / `CHAT_ID` | The chat/group the bot writes to (already set). |
| `PHP_API_BASE` | Set **after** Path A or B is up: `https://<your API domain>/api` (no trailing slash, no spaces). Leave unset until then — the bot keeps serving the static plans file. |
| `PORT` | `10000` (already set). |

**Render free tier sleeps:** after ~15 minutes with no traffic the free
web service sleeps, and the first request after that takes ~30–60 seconds
(cold start). That is normal on the free plan — the app should tolerate a
slow first call. It does not mean the deploy failed.

After changing env vars, Render redeploys the service automatically.
Verify with `https://plan-atsede-teguhan.onrender.com/` — it must return
only `status`, `service`, `plans_count`, `bot_active` (no token prefix,
no chat ID — audit M11).

---

## §5. Reminder scheduler — daily cron (already in `render.yaml`)

The `atsede-reminder-scheduler` cron in `backend/render.yaml` runs
`python backend/reminder_scheduler.py --once` once a day at
**03:00 UTC = 06:00 EAT**. It is created automatically when the blueprint
is applied. Set its env vars in the Render Dashboard:

| Env var | Notes |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Required — the scheduler fails loudly (no silent no-op) without it. |
| `TELEGRAM_CHAT_ID` | **Required** — the chat/group the 6 AM reminder goes to. |
| `PHP_API_BASE` | Optional — set once the PHP API is hosted; unset = reminders are built from the static plans file. |

The scheduler sends **one** Telegram summary per run listing incomplete
plans due this Ethiopian month (or overdue / due within 7 days by
`target_date`). It never hardcodes a chat ID or token.

---

## Verification checklist (after deploy)

- [ ] `GET https://<API domain>/api/health.php` → `{"status":"ok",...}`
- [ ] `GET https://plan-atsede-teguhan.onrender.com/` → only `status`, `service`, `plans_count`, `bot_active`
- [ ] `POST https://plan-atsede-teguhan.onrender.com/api/send_notice` **without** a credential → `401`
- [ ] App login works (after the seed-password fix is merged)
- [ ] App shows plans from the server (not only the bundled list)
- [ ] 6 AM reminder arrives in the Telegram group the morning after the cron is created
- [ ] No `.env` file and no secret value appears in git (`git status` shows no `.env`)
