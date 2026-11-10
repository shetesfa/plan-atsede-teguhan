# ዓጸደ ትጉሃን የሰንበት ትምህርት ቤት የዕቅድ፣ ሪፖርት እና ግንኙነት ስርዓት
### Atsede Teguhan Sunday School Plan Management & Communication System (v2.0)

ይህ ፕሮጀክት የዓጸደ ትጉሃን ሰንበት ት/ቤት የ2019 ዓ.ም ዓመታዊ ዕቅዶችን፣ የ10ሩን ክፍላት ተግባራት፣ የክንውን ሪፖርቶችን፣ ይፋዊ ሰነዶችን (Word እና Excel)፣ የውስጥ ውይይቶችን እና የቴሌግራም ማሳወቂያዎችን በዘመናዊ፣ አስተማማኝ እና ከመስመር ውጭ (Offline-first) በሚሰራ መልኩ ለማስተዳደር የተዘጋጀ የተሟላ ስርዓት ነው።

---

## 🏛️ የስርዓቱ አርክቴክቸር (System Architecture)

```
[ የሞባይልና የኮምፒውተር መተግበሪያ (Flutter) ]
       │              ▲
       ▼ (REST API)   │ (Offline Cache & Sync Queue)
[ PHP 8.2 Backend (api/) ] ──► [ MySQL Database (atsede_db) ]
       ▲
       │
[ Python 3.14 Background Worker & Telegram Bot (backend/) ]
```

1. **የፊት ለፊት መተግበሪያ (Frontend - Flutter 3.44):**
   - አንድሮይድ (Android)፣ አይኦኤስ (iOS)፣ ዌብ (Web) እና ዊንዶውስ (Windows) ይደግፋል።
   - ከመስመር ውጭም ሆነ በመስመር ላይ እኩል አገልግሎት ይሰጣል።
   - የኢትዮጵያ ዘመን አቆጣጠርን እና ፊደላትን ሙሉ በሙሉ ይደግፋል።

2. **የኋላ አገልጋይ (Backend - PHP 8.2 & MySQL):**
   - ንጹህ እና ደህንነቱ የተጠበቀ RESTful API።
   - በ `password_hash()` (Bcrypt) የተጠበቀ የይለፍ ቃል እና HMAC-SHA256 Token ማረጋገጫ።
   - የኢትዮጵያ ሰዓት ቀጠና (`Africa/Addis_Ababa`)።
   - አንድ ነጠላ የእውነት ምንጭ (Single Source of Truth)።

3. **የቴሌግራም ቦት እና አስታዋሽ (Python Background Tasks):**
   - ማሳወቂያዎችን እና አስታዋሾችን በጀርባ ማዳመጥ እና መላክ።
   - ቶከኖችን በ `.env` ፋይል በደህንነት ማስተዳደር።

---

## 🚀 ዋና ዋና ሞጁሎች እና ገጽታዎች (Key Modules)

1. **የዕቅድ አስተዳደር (Plan Management):**
   - 137ቱን የ2019 ዓ.ም እቅዶች በክፍል፣ በወር እና በሁኔታ መከታተል።
   - አዳዲስ እቅዶችን መመዝገብ፣ ማረም፣ ኃላፊ መመደብ እና በፈቃድ መሰረዝ።
   - የክንውን ደረጃን (0% - 100%) በቅጽበት መከታተል።

2. **የሪፖርት እና የፅ/ቤት የስራ ፍሰት (Reporting & Office Workflow):**
   - ክፍላት ለእያንዳንዱ እቅድ የተሰሩ ስራዎችን፣ ያጋጠሙ ተግዳሮቶችን እና ፎቶዎችን አያይዘው ለፅ/ቤት ያቀርባሉ።
   - ፅ/ቤት የቀረቡትን ሪፖርቶች መርምሮ ማጽደቅ (Approve)፣ ማሻሻያ መጠየቅ (Request Revision)፣ ወይም ውድቅ ማድረግ (Reject) ይችላል።
   - እያንዳንዱ ሪፖርት ሙሉ የግምገማ ታሪክ (Audit trail) አለው።

3. **የ Word እና Excel የስራ ቦታ (Workspace):**
   - **Word:** ይፋዊ ደብዳቤዎችን፣ ፕሮፖዛሎችን እና ማስታወሻዎችን አዘጋጅቶ ወደ PDF ማውጣት።
   - **Excel:** ሰንጠረዦችን ማረም፣ የቀመር ስሌት (Auto-sum) መስራት፣ ወደ እውነተኛ `.xlsx` ማውጣት (Export XLSX) እና ነባር ፋይሎችን ማስገባት (Import XLSX)።
   - በውጫዊ Microsoft Office ወይም LibreOffice በቀላሉ መክፈት።

4. **የውስጥ ውይይት (Persistent Chat):**
   - በ MySQL ዳታቤዝ ቋሚ ሆኖ የሚቀመጥ የክፍላትና የይፋዊ መመሪያዎች ቻት።
   - የደረሰኝ እና የንባብ ማረጋገጫ (Read Receipts)።

5. **ማሳወቂያዎች እና አስታዋሾች (Notifications & Reminders):**
   - የውስጠ-መተግበሪያ ማሳወቂያዎች ማዕከል።
   - በኢትዮጵያ ሰዓት አቆጣጠር የሚሰራ የሰርቨር አስታዋሽ።
   - የቴሌግራም ቦት ውህደት።

6. **ከመስመር ውጭ አሰራር (Offline-First):**
   - ኢንተርኔት በሌለበት ጊዜ መረጃዎችን ማየት፣ ሪፖርቶችን ረቂቅ ማድረግ፣ እቅዶችን ማረም።
   - ኢንተርኔት ሲመለስ ያለ ድግግሞሽ (Idempotent) ወደ አገልጋዩ ማመሳከር።

---

## 🛠️ የመጫኛ እና የማስኬጃ መመሪያዎች (Setup & Deployment)

### 1. የዳታቤዝ ዝግጅት (MySQL Database)
1. MySQL ሰርቨርዎን ያስጀምሩ (ለምሳሌ በ XAMPP)።
2. የዳታቤዝ ስኪማውን እና ማሻሻያውን ይጫኑ፦
   ```bash
   # ነባሩን ዳታቤዝ መጫን
   mysql -u root -p < database/atsede_db.sql

   # አዲሱን የላቀ ስኪማ መጫን (Migration 01)
   mysql -u root -p atsede_db < database/migrations/01_advanced_schema.sql
   ```

### 2. የ PHP Backend API ማስኬድ
1. ወደ `api/` ማውጫ ይሂዱ እና `.env` ፋይሉን ያረጋግጡ፦
   ```bash
   cp api/.env.example api/.env
   ```
2. በ PHP ውስጣዊ አገልጋይ ወዲያውኑ ማስኬድ ይችላሉ፦
   ```bash
   php -S 127.0.0.1:8000 -t .
   ```
   *ኤፒአዩ በ `http://127.0.0.1:8000/api/` ላይ ዝግጁ ይሆናል።*

### 3. የፍላተር መተግበሪያ (Flutter App)
```bash
# ጥገኛ ፓኬጆችን ማውረድ
flutter pub get

# መተግበሪያውን ማስኬድ (Android, Windows, or Web)
flutter run

# ለ Chrome ዌብ ማስኬድ
flutter run -d chrome

# ለአንድሮይድ APK ማመንጨት
flutter build apk --release
```

### 4. የቴሌግራም ቦት እና አስታዋሽ (Python)
```bash
cd backend
pip install -r requirements.txt
python bot_server.py
```

---

## 🔒 ነባሪ የመግቢያ መለያዎች (Default Accounts)

- **የፅ/ቤት አስተዳዳሪ (Super Admin):**
  - ክፍል / የተጠቃሚ ስም፦ `admin`
  - የይለፍ ቃል፦ `admin` (ወይም `1234` / `atsede1234`)
- **የትምህርት ክፍል (Education):**
  - ክፍል / የተጠቃሚ ስም፦ `education`
  - የይለፍ ቃል፦ `1234`
- **የመዝሙር ክፍል (Mezmur):**
  - ክፍል / የተጠቃሚ ስም፦ `mezmur`
  - የይለፍ ቃል፦ `1234`
*(ሁሉም ሌሎች ክፍሎች በክፍላቸው ስም እና በ `1234` መግባት ይችላሉ፤ በመጀመሪያው መግቢያ ላይ የይለፍ ቃሉ በራስ-ሰር ወደ ደህንነቱ የተጠበቀ Bcrypt hash ይቀየራል)*

---

## 👥 ፈቃድ እና ባለቤትነት (License)
የዓጸደ ትጉሃን ሰንበት ትምህርት ቤት © 2019 ዓ.ም - መብቱ በህግ የተጠበቀ ነው።
