-- ============================================================
-- የአጸደ ትጉሃን የዳታቤዝ ማሻሻያ ስክሪፕት (Migration 01: Advanced Schema)
-- ነባር መረጃዎችን ሳይደመስስ ሙሉ የሪፖርት፣ የቻት፣ የማሳወቂያ እና የተመሳክሮ አቅምን ይጨምራል
-- ============================================================

-- የውሂብ ጎታ ምርጫ የሚከናወነው በአገልጋዩ ውቅር (PDO DSN) አማካኝነት ነው (No hardcoded USE db)

-- 1. የተጠቃሚዎች ሰንጠረዥ ማሻሻያ (Users Schema Enhancement)
ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `username` VARCHAR(80) NULL UNIQUE AFTER `department_id`,
  ADD COLUMN IF NOT EXISTS `email` VARCHAR(150) NULL AFTER `phone`,
  ADD COLUMN IF NOT EXISTS `status` ENUM('active', 'inactive', 'suspended') DEFAULT 'active' AFTER `phone`,
  ADD COLUMN IF NOT EXISTS `last_login` DATETIME NULL AFTER `created_at`;

-- ነባር ክፍሎች ተጠቃሚዎች ከሌሏቸው የመጀመሪያ መለያዎችን ማዘጋጀት (Initial admin and dept users)
-- እያንዳንዱ ተጠቃሚ የራሱ የተለየ ጠንካራ የይለፍ ቃል አለው፤ hashዎቹ እዚህ በታች
-- በ bcrypt (cost 12) የተፈጠሩ እውነተኛ hashes ናቸው እና በ PHP password_verify()
-- ይረጋገጣሉ (PHP $2b$ bcrypt hash ያቀበላል)። የይለፍ ቃል እሴቶች በዚህ ፋይል ውስጥ
-- የሉም፤ የመጀመሪያ የይለፍ ቃሎች ለተስፋ ብቻ በተ riêng የግል ፋይል ተሰጥተዋል።
-- እያንዳንዱ ተጠቃሚ በመጀመሪያ መግቢያ ላይ የይለፍ ቃሉን መቀየር አለበት።
-- (Audit 2026-11-14, C2/H7: ቀደም ሲል 10ቱም ተጠቃሚዎች አንድ የተፈጠረ hash ነበራቸው፤ ተስተካክሏል።)
INSERT INTO `users` (`department_id`, `username`, `full_name`, `role_title`, `password_hash`, `status`)
VALUES 
('admin', 'admin', 'ዲ/ን ቴዎድሮስ (ፅ/ቤት)', 'የፅ/ቤት ዋና ጸሐፊ', '$2b$12$TfyAbDTxR9b0e/NrGafUn.Km7y758L6qrzaoI9ScB4Y/cRDFFzmRi', 'active'),
('education', 'education', 'ተስፋሁን ባይህ (ትምህርት)', 'የትምህርት እና ስልጠና ኃላፊ', '$2b$12$FqzJgTrx1LWCrTiGnQEX0e1X7.pSKcMhNZAPsdq4sRpmqPyHH4RHG', 'active'),
('mezmur', 'mezmur', 'መዝሙር ክፍል ተወካይ', 'የመዝሙር እና ስነጥበብ ኃላፊ', '$2b$12$AnjPEjehA.4ZSkFczExfRODxfYQ7dn.F1TYQN6BnoGgXbw7pYDTcm', 'active'),
('program', 'program', 'መርሃግብር ክፍል ተወካይ', 'የመርሃግብር ኃላፊ', '$2b$12$Xz6jV27LdLdP/65GbthT9.551mS3yKvYokHFRLSbz/J1fs7jnh/lm', 'active'),
('development', 'development', 'ልማት ክፍል ተወካይ', 'የልማትና በጎ አድራጎት ኃላፊ', '$2b$12$1FQXpXm0xqg.rkJQGaT5E.c6gWKwtOUosMlpHyaAsVcCzah11cEG2', 'active'),
('pr', 'pr', 'መረጃ ክፍል ተወካይ', 'የመረጃና ግንኙነት ኃላፊ', '$2b$12$kMsAEASzxcufskb7UtemOO1TN8m3b0OnWgWq1zyqXgVqErfvrgFNm', 'active'),
('members', 'members', 'አባላት ክፍል ተወካይ', 'የአባላት አስተዳደር ኃላፊ', '$2b$12$UNiAylHjYr6UPONlWD55sOXIsay3P/.Mjk061mB7Fj6aigocadg/.', 'active'),
('audit', 'audit', 'ቁጥጥር ክፍል ተወካይ', 'የቁጥጥር ክፍል ኃላፊ', '$2b$12$msoaShoeFub5K6WlZ4JebekQZM/ba1Q8WMfLuHkG0O3.5p8EdyOEq', 'active'),
('finance', 'finance', 'በጀት ክፍል ተወካይ', 'የበጀትና ንብረት ኃላፊ', '$2b$12$brqvw1SUMZX8vqhsesCFzOKPfcD9DEvSTWxA27nSUn/eH46egVyb6', 'active'),
('hr', 'hr', 'ሰው ሀብት ተወካይ', 'የሰው ሀብት አስተዳደር ኃላፊ', '$2b$12$ALjZMkTXkVl.vVhJlyw8Lua6jOc6obf4i.rkH5GUkLb6ZkXlyk8SO', 'active')
ON DUPLICATE KEY UPDATE `full_name`=VALUES(`full_name`);

-- 2. የእቅዶች ሰንጠረዥ ማሻሻያ (Plans Schema Enhancement)
ALTER TABLE `plans`
  ADD COLUMN IF NOT EXISTS `title` VARCHAR(255) NULL AFTER `department_id`,
  ADD COLUMN IF NOT EXISTS `status` ENUM('draft', 'pending', 'approved', 'in_progress', 'completed', 'overdue', 'cancelled') DEFAULT 'in_progress' AFTER `progress_percent`,
  ADD COLUMN IF NOT EXISTS `priority` ENUM('low', 'medium', 'high', 'urgent') DEFAULT 'medium' AFTER `status`,
  ADD COLUMN IF NOT EXISTS `assigned_to` VARCHAR(150) NULL AFTER `priority`,
  ADD COLUMN IF NOT EXISTS `target_date` VARCHAR(100) NULL AFTER `execution_time`,
  ADD COLUMN IF NOT EXISTS `start_date` DATE NULL AFTER `target_date`,
  ADD COLUMN IF NOT EXISTS `end_date` DATE NULL AFTER `start_date`,
  ADD COLUMN IF NOT EXISTS `created_by` VARCHAR(100) NULL AFTER `assigned_to`,
  ADD COLUMN IF NOT EXISTS `sync_id` VARCHAR(100) NULL AFTER `updated_at`,
  ADD COLUMN IF NOT EXISTS `version` INT DEFAULT 1 AFTER `sync_id`,
  ADD COLUMN IF NOT EXISTS `is_deleted` TINYINT(1) DEFAULT 0 AFTER `version`,
  ADD COLUMN IF NOT EXISTS `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP AFTER `is_deleted`;

-- 3. የክንውን ሪፖርት ማቅረቢያ ሰንጠረዥ (Reports Table)
CREATE TABLE IF NOT EXISTS `reports` (
  `id` VARCHAR(100) NOT NULL PRIMARY KEY,
  `plan_id` VARCHAR(100) NULL,
  `department_id` VARCHAR(50) NOT NULL,
  `submitted_by` VARCHAR(150) NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `activities_completed` TEXT NOT NULL,
  `progress_percent` INT DEFAULT 0,
  `challenges` TEXT NULL,
  `solutions_proposed` TEXT NULL,
  `budget_spent` DECIMAL(12, 2) DEFAULT 0.00,
  `status` ENUM('draft', 'submitted', 'under_review', 'approved', 'revision_requested', 'rejected') DEFAULT 'submitted',
  `office_feedback` TEXT NULL,
  `reviewed_by` VARCHAR(150) NULL,
  `reviewed_at` DATETIME NULL,
  `sync_id` VARCHAR(100) NULL,
  `version` INT DEFAULT 1,
  `is_deleted` TINYINT(1) DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`department_id`) REFERENCES `departments`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`plan_id`) REFERENCES `plans`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. የሪፖርት ግምገማዎች እና ማሻሻያ ታሪክ (Report Reviews & Audit Trail)
CREATE TABLE IF NOT EXISTS `report_reviews` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `report_id` VARCHAR(100) NOT NULL,
  `reviewer_name` VARCHAR(150) NOT NULL,
  `reviewer_role` VARCHAR(100) NOT NULL,
  `action` ENUM('submitted', 'reviewed', 'approved', 'revision_requested', 'rejected') NOT NULL,
  `comment` TEXT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`report_id`) REFERENCES `reports`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. የሪፖርት አባሪ ሰነዶችና ፎቶዎች (Report Attachments)
CREATE TABLE IF NOT EXISTS `report_attachments` (
  `id` VARCHAR(100) NOT NULL PRIMARY KEY,
  `report_id` VARCHAR(100) NOT NULL,
  `file_name` VARCHAR(255) NOT NULL,
  `file_path` VARCHAR(500) NOT NULL,
  `file_type` VARCHAR(100) NOT NULL,
  `file_size` INT DEFAULT 0,
  `uploaded_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`report_id`) REFERENCES `reports`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6. ማሳወቂያዎች (Notifications)
CREATE TABLE IF NOT EXISTS `notifications` (
  `id` VARCHAR(100) NOT NULL PRIMARY KEY,
  `user_id` INT NULL,
  `department_id` VARCHAR(50) NULL,
  `title` VARCHAR(255) NOT NULL,
  `message` TEXT NOT NULL,
  `type` ENUM('plan_assigned', 'deadline_approaching', 'overdue', 'report_submitted', 'report_approved', 'revision_requested', 'chat_message', 'announcement') NOT NULL,
  `target_id` VARCHAR(100) NULL,
  `is_read` TINYINT(1) DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`department_id`) REFERENCES `departments`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 7. የቀጠሮ አስታዋሾች (Reminders)
CREATE TABLE IF NOT EXISTS `reminders` (
  `id` VARCHAR(100) NOT NULL PRIMARY KEY,
  `plan_id` VARCHAR(100) NULL,
  `department_id` VARCHAR(50) NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `message` TEXT NOT NULL,
  `remind_at` DATETIME NOT NULL,
  `is_sent` TINYINT(1) DEFAULT 0,
  `sent_at` DATETIME NULL,
  `target_channel` ENUM('in_app', 'telegram', 'both') DEFAULT 'both',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`department_id`) REFERENCES `departments`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`plan_id`) REFERENCES `plans`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 8. የውይይት ክፍሎች (Chat Rooms)
CREATE TABLE IF NOT EXISTS `chat_rooms` (
  `id` VARCHAR(100) NOT NULL PRIMARY KEY,
  `name` VARCHAR(150) NOT NULL,
  `type` ENUM('general', 'direct', 'department', 'official_notice') DEFAULT 'general',
  `created_by` VARCHAR(100) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ነባሪ የውይይት ክፍሎችን መመዝገብ
INSERT INTO `chat_rooms` (`id`, `name`, `type`) VALUES
('room_official', 'ይፋዊ መመሪያዎች እና ማሳሰቢያዎች', 'official_notice'),
('room_leaders', 'የአመራሮች አጠቃላይ ጉባኤ', 'general'),
('room_office', 'ከፅ/ቤት ጋር ቀጥታ መስመር', 'direct'),
('room_docs', 'የሰነዶች እና እቅድ ማጋሪያ', 'general')
ON DUPLICATE KEY UPDATE `name`=VALUES(`name`);

-- 9. የውይይት መልእክቶች ማሻሻያ (Chat Messages Enhancement)
ALTER TABLE `chat_messages`
  ADD COLUMN IF NOT EXISTS `room_id` VARCHAR(100) DEFAULT 'room_general' AFTER `id`,
  ADD COLUMN IF NOT EXISTS `reply_to_id` VARCHAR(100) NULL AFTER `message`,
  ADD COLUMN IF NOT EXISTS `is_read` TINYINT(1) DEFAULT 0 AFTER `is_official_notice`,
  ADD COLUMN IF NOT EXISTS `sync_id` VARCHAR(100) NULL AFTER `attachment_path`,
  ADD COLUMN IF NOT EXISTS `is_deleted` TINYINT(1) DEFAULT 0 AFTER `sync_id`;

-- 10. የስርዓት ኦዲት መዝገብ (System Audit Logs)
CREATE TABLE IF NOT EXISTS `audit_logs` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT NULL,
  `department_id` VARCHAR(50) NULL,
  `action` VARCHAR(100) NOT NULL,
  `entity_type` VARCHAR(50) NOT NULL,
  `entity_id` VARCHAR(100) NULL,
  `details` JSON NULL,
  `ip_address` VARCHAR(50) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 11. ከመስመር ውጭ የገቡ ለውጦች ማመሳከሪያ (Sync Queue)
CREATE TABLE IF NOT EXISTS `sync_queue` (
  `id` VARCHAR(100) NOT NULL PRIMARY KEY,
  `device_id` VARCHAR(150) NOT NULL,
  `entity_type` ENUM('plan', 'report', 'chat', 'unplanned', 'document') NOT NULL,
  `action` ENUM('create', 'update', 'delete') NOT NULL,
  `payload` JSON NOT NULL,
  `status` ENUM('pending', 'processed', 'conflict', 'failed') DEFAULT 'pending',
  `conflict_resolution` TEXT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `processed_at` DATETIME NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 12. የተጋለጡ ቶከኖችን ከ system_settings ማስወገድ
UPDATE `system_settings`
SET `setting_value` = ''
WHERE `setting_key` = 'telegram_bot_token';
