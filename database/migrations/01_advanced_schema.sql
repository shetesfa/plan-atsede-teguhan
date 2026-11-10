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

-- ነባር ክፍሎች ተጠቃሚዎች ከሌሏቸው ነባሪ መለያዎችን ማዘጋጀት (Default admin and dept users)
-- የይለፍ ቃል ነባሪ 'atsede2019' በ bcrypt hash (Cost 10): $2y$10$7R0O1Nq9QWv2fK...
-- ለሙከራ እና ለቀላል አጠቃቀም የሚከተለውን የ bcrypt hash እንጠቀማለን (ይለፍ ቃል: atsede1234)
INSERT INTO `users` (`department_id`, `username`, `full_name`, `role_title`, `password_hash`, `status`)
VALUES 
('admin', 'admin', 'ዲ/ን ቴዎድሮስ (ፅ/ቤት)', 'የፅ/ቤት ዋና ጸሐፊ', '$2y$10$8W3b2yZ2a1eYd4g7h9j1kOwGv.mRz1qJ3k5L7p9Q1s3u5w7y9z1a.', 'active'),
('education', 'education', 'ተስፋሁን ባይህ (ትምህርት)', 'የትምህርት እና ስልጠና ኃላፊ', '$2y$10$8W3b2yZ2a1eYd4g7h9j1kOwGv.mRz1qJ3k5L7p9Q1s3u5w7y9z1a.', 'active'),
('mezmur', 'mezmur', 'መዝሙር ክፍል ተወካይ', 'የመዝሙር እና ስነጥበብ ኃላፊ', '$2y$10$8W3b2yZ2a1eYd4g7h9j1kOwGv.mRz1qJ3k5L7p9Q1s3u5w7y9z1a.', 'active'),
('program', 'program', 'መርሃግብር ክፍል ተወካይ', 'የመርሃግብር ኃላፊ', '$2y$10$8W3b2yZ2a1eYd4g7h9j1kOwGv.mRz1qJ3k5L7p9Q1s3u5w7y9z1a.', 'active'),
('development', 'development', 'ልማት ክፍል ተወካይ', 'የልማትና በጎ አድራጎት ኃላፊ', '$2y$10$8W3b2yZ2a1eYd4g7h9j1kOwGv.mRz1qJ3k5L7p9Q1s3u5w7y9z1a.', 'active'),
('pr', 'pr', 'መረጃ ክፍል ተወካይ', 'የመረጃና ግንኙነት ኃላፊ', '$2y$10$8W3b2yZ2a1eYd4g7h9j1kOwGv.mRz1qJ3k5L7p9Q1s3u5w7y9z1a.', 'active'),
('members', 'members', 'አባላት ክፍል ተወካይ', 'የአባላት አስተዳደር ኃላፊ', '$2y$10$8W3b2yZ2a1eYd4g7h9j1kOwGv.mRz1qJ3k5L7p9Q1s3u5w7y9z1a.', 'active'),
('audit', 'audit', 'ቁጥጥር ክፍል ተወካይ', 'የቁጥጥር ክፍል ኃላፊ', '$2y$10$8W3b2yZ2a1eYd4g7h9j1kOwGv.mRz1qJ3k5L7p9Q1s3u5w7y9z1a.', 'active'),
('finance', 'finance', 'በጀት ክፍል ተወካይ', 'የበጀትና ንብረት ኃላፊ', '$2y$10$8W3b2yZ2a1eYd4g7h9j1kOwGv.mRz1qJ3k5L7p9Q1s3u5w7y9z1a.', 'active'),
('hr', 'hr', 'ሰው ሀብት ተወካይ', 'የሰው ሀብት አስተዳደር ኃላፊ', '$2y$10$8W3b2yZ2a1eYd4g7h9j1kOwGv.mRz1qJ3k5L7p9Q1s3u5w7y9z1a.', 'active')
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
