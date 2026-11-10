# የለውጦች ማህደር (CHANGELOG)
## ዓጸደ ትጉሃን የሰንበት ት/ቤት የዕቅድ፣ ሪፖርት እና ግንኙነት ስርዓት
### Atsede Teguhan Sunday School Planning & Report System

ሁሉም ለውጦች እና ማሻሻያዎች በዝርዝር እና በጊዜ ቅደም ተከተል ተመዝግበዋል።

---

## [ስሪት 2.0.0] - 2026-11-10

### 🛡️ ደህንነት እና መሰረት (Security & Foundation)
- **የተጋለጡ ቶከኖች ማግለል (Exposed Secrets Removal):** በ `bot_server.py`፣ `telegram_service.dart` እና `atsede_db.sql` ውስጥ በግልጽ ተቀምጠው የነበሩ የቴሌግራም ቦት ቶከኖች ተወግደው በ `.env` ፋይል እና በአገልጋይ ውቅር እንዲተዳደሩ ተደርጓል።
- **ጠንካራ የይለፍ ቃል ማረጋገጫ (Bcrypt Password Hashing):** በሞባይል ኮድ ውስጥ በግልጽ ተጽፎ የነበረው ነጠላ የይለፍ ቃል ፍተሻ ተወግዶ በ PHP `password_hash()` እና `password_verify()` በደህንነት እንዲፈተሽ ተደርጓል።
- **የጥያቄዎች ማረጋገጫ (HMAC Token Authentication):** እያንዳንዱ የኤፒአይ ጥያቄ በ Bearer Token እና HMAC-SHA256 እንዲረጋገጥ ተደርጓል።
- **የጊዜ ቀጠና (Timezone):** አገልጋዩ እና የጊዜ ሰሌዳው ሙሉ በሙሉ በኢትዮጵያ ሰዓት አቆጣጠር (`Africa/Addis_Ababa`) እንዲሰሩ ተዋቅረዋል።

### 📋 የእቅድ እና የሪፖርት የስራ ፍሰት (Plans & Reports Workflow)
- **የተሟላ የዕቅድ CRUD:** እቅዶችን በቀጥታ በዳታቤዝ መፍጠር፣ ማረም፣ በክፍል እና በወር ማጣራት፣ መፈለግ እና በፈቃድ መሰረዝ (Soft Delete) ተተግብሯል።
- **የክንውን ሪፖርት አቀራረብ (Reporting):** ክፍላት ለእያንዳንዱ እቅድ የተከናወኑ ስራዎችን፣ ያጋጠሙ ተግዳሮቶችን፣ የመቶኛ ደረጃን እና ማስረጃ ፎቶዎችን አያይዘው ለፅ/ቤት የሚያቀርቡበት የስራ ፍሰት ተገንብቷል።
- **የፅ/ቤት መገምገሚያ ማዕከል (Office Review):** ፅ/ቤት የቀረቡ ሪፖርቶችን መርምሮ ማጽደቅ (Approve)፣ ማሻሻያ መጠየቅ (Request Revision)፣ ወይም ውድቅ ማድረግ (Reject) የሚያስችለው አዲስ `OfficeReportsScreen` ተጨምሯል።
- **የግምገማ ታሪክ (Audit Trail):** እያንዳንዱ ሪፖርት የቀረበበት፣ የተገመገመበት እና የተስተካከለበት ታሪክ በ `report_reviews` ሰንጠረዥ ይመዘገባል።

### 💬 የውስጥ ውይይት እና ቴሌግራም (Chat & Telegram Communication)
- **ቋሚ የ MySQL ማከማቻ:** በሜሞሪ ብቻ ይሰራ የነበረው ቻት አሁን መልእክቶችን፣ አባሪዎችን እና ክፍሎችን በ MySQL `chat_messages` ሰንጠረዥ ቋሚ አድርጎ ያስቀምጣል።
- **የቴሌግራም ቦት ውህደት:** የቴሌግራም ቦት ከዋናው MySQL ዳታቤዝ ጋር እንዲገናኝ እና አንድ ነጠላ የእውነት ምንጭ (Single Source of Truth) እንዲከተል ተደርጓል።

### 📊 የ Word እና Excel ሰነዶች የስራ ቦታ (Document Workspace)
- **እውነተኛ የ Excel (.xlsx) ድጋፍ:** ሰንጠረዦችን ማረም፣ የቀመር ስሌት መስራት፣ እንደ `.xlsx` ፋይል ማመንጨት እና ማውረድ (Export XLSX) ተተግብሯል።
- **የኤክሴል ፋይል ማስገቢያ (Import XLSX):** ነባር የ `.xlsx` ፋይሎችን ከመሳሪያ ላይ መርጦ ወደ ሰንጠረዡ መጫን ተችሏል።
- **የውጫዊ Office ዝግጁነት:** የተዘጋጁ DOCX እና XLSX ሰነዶችን በ Microsoft Office ወይም በሌሎች የቢሮ አፕሊኬሽኖች በቀላሉ መክፈት እንዲቻል ተደርጓል።

### 🔔 ማሳወቂያዎች እና አስታዋሾች (Notifications & Reminders)
- **የውስጠ-መተግበሪያ ማሳወቂያዎች (In-App Notifications):** አዲስ እቅድ ሲመደብ፣ ሪፖርት ሲቀርብ፣ ሲጸድቅ ወይም ማሻሻያ ሲጠየቅ ተጠቃሚዎች በአፑ ውስጥ ማሳወቂያ የሚያገኙበት `NotificationService` ተተግብሯል።
- **የሰርቨር አስታዋሽ (Reminder Scheduler):** በኢትዮጵያ ሰዓት አቆጣጠር ያልተጠናቀቁ እና የቀነ-ገደብ እቅዶችን የሚከታተል የጀርባ ስክሪፕት `reminder_scheduler.py` ተዘጋጅቷል።

### 🔄 ከመስመር ውጭ አሰራር (Offline-First & Synchronization)
- **ከመስመር ውጭ ድጋፍ:** ኢንተርኔት በሌለበት ጊዜ መተግበሪያው ከአካባቢው ካሽና ፋይሎች ያለምንም መቆራረጥ መስራቱን ይቀጥላል።
- **የለውጦች ማመሳከሪያ (Sync Engine):** ኢንተርኔት ሲመለስ ከመስመር ውጭ የተሰሩ ለውጦች በ `sync_id` ድግግሞሽ ሳይፈጠር (Idempotent) ወደ አገልጋዩ ይተላለፋሉ።
