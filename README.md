# ዓጸደ ተጉሃን የሰንበት ት/ቤት የዕቅድ እና ሪፖርት መተግበሪያ
### Atsede Teguhan Sunday School Planning & Report System

ይህ ፕሮጀክት የዓጸደ ተጉሃን ሰንበት ት/ቤት የ2019 ዓ.ም ዓመታዊ ዕቅዶችን፣ የክፍላት ተግባራትን፣ ሪፖርቶችን፣ ይፋዊ ደብዳቤዎችን እና ፕሮፖዛሎችን በዘመናዊ መልኩ ለማስተዳደር የተዘጋጀ የተሟላ የሞባይልና የዳመና (Cloud) ሥርዓት ነው።

---

## 📁 የተካተቱ የውሂብ ሰነዶች እና ዳታዎች (Data & Assets)

* **የዕቅድ ሰነዶች (Official Plans):**
  * `2019 ዓ.ም እቅድ (2).xlsx` - ዋናው የ2019 ዓ.ም የክፍላት ዕቅድ ሰነድ
  * `እቅድ መዝሙር ክፍል 2019 አዲስ.pdf` - የተጠናቀረ የመዝሙር ክፍል ዕቅድ
  * `assets/plan_2019.xlsx` & `assets/default_plans.json` - በመተግበሪያው ውስጥ በቀጥታ የተቀናጁ የዕቅድ ዝርዝሮች
* **የተተነተኑ ዳታዎች (Extracted & Structured Data):**
  * `full_extracted_data.json` - ከሰነዶች የወጡ የተሟሉ የክፍላት ተግባራት በዝርዝር
  * `dept_counts.json` - በእያንዳንዱ ክፍል የተያዙ የዕቅዶች ብዛት
  * `dept_dates_summary.json` - የእቅዶች የጊዜ ሰሌዳና የቀናት ማጠቃለያ
* **የዳታቤዝ እና የኤፒአይ ፋይሎች (Database & API):**
  * `database/atsede_db.sql` - የተሟላ የ MySQL ዳታቤዝ አወቃቀር
  * `api/db.php` & `api/plans.php` - የዌብ ኤፒአይ ግንኙነት ፋይሎች
* **የቴሌግራም ቦት እና የደመና አገልጋይ (Telegram Bot & Cloud Server):**
  * `backend/bot_server.py` - የቴሌግራም ማሳወቂያ እና ሪፖርት መቀበያ ቦት (@atsedetestsystembot)
  * `backend/render.yaml` & `backend/Procfile` - በ Render ደመና ላይ ለማስተናገድ የተዘጋጁ የማዋቀሪያ ፋይሎች

---

## 🚀 ዋና ዋና ገጽታዎች (Features)

1. **ዘመናዊ ዳሽቦርድ (Executive Dashboard):**
   * የክፍላትን አፈፃፀም፣ አጠቃላይ የዕቅድ ብዛት እና መሪ ሰሌዳ (Leaderboard) ያሳያል።
2. **የዕቅድ ካላንደር እና ዝርዝር (Calendar & Task Tracking):**
   * ተግባራትን በቀን፣ በክፍል እና በሁኔታ (የተጠናቀቀ፣ በሂደት ላይ ያለ፣ ያልተጀመረ) የመከታተል አቅም።
3. **ደብዳቤና ፕሮፖዛል ማመንጫ (Official Letter & Proposal Generator):**
   * በኢትዮጵያ ዘመን አቆጣጠር ይፋዊ ደብዳቤዎችን እና ፕሮፖዛሎችን በፒዲኤፍ የማመንጨት እና የማጋራት ችሎታ።
4. **የቴሌግራም ቦት ውህደት (Telegram Bot Integration):**
   * አዳዲስ ተግባራት ሲከናወኑ እና ሪፖርቶች ሲቀርቡ ለተጠቃሚዎች እና ለአመራሩ ወዲያውኑ ማሳወቂያ ይልካል።

---

## 🛠️ አጠቃቀም እና ማስኬጃ (Running the Project)

### የፍላተር መተግበሪያ (Flutter App):
```bash
flutter pub get
flutter run
```

### የባክኤንድ ሰርቨር (Backend / Bot):
```bash
cd backend
pip install -r requirements.txt
python bot_server.py
```
