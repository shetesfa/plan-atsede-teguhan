-- ============================================================
-- የአጸደ ትጉሃን ሰንበት ትምህርት ቤት የውሂብ ጎታ (MySQL Database Schema)
-- ለ XAMPP phpMyAdmin በቀላሉ Import የሚደረግ
-- ============================================================

CREATE DATABASE IF NOT EXISTS `atsede_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `atsede_db`;

-- 1. የክፍሎች ሰንጠረዥ (Departments)
CREATE TABLE IF NOT EXISTS `departments` (
  `id` VARCHAR(50) NOT NULL PRIMARY KEY,
  `name` VARCHAR(150) NOT NULL,
  `short_name` VARCHAR(50) NOT NULL,
  `is_super_admin` TINYINT(1) DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `departments` (`id`, `name`, `short_name`, `is_super_admin`) VALUES
('admin', 'ጽ/ቤት', 'ጽ/ቤት', 1),
('mezmur', 'መዝሙርና ስነጥበብ ክፍል', 'መዝሙር', 0),
('education', 'ትምህርት እና ስልጠና ክፍል', 'ትምህርት', 0),
('program', 'መርሃግብር እና ጉባኤያት ክፍል', 'መርሃግብር', 0),
('pr', 'መረጃና የውስጥ ግንኙነት ክፍል', 'መረጃ', 0),
('members', 'አባላት አስተዳደር ክፍል', 'አባላት', 0),
('audit', 'ቁጥጥር ክፍል', 'ቁጥጥር', 0),
('development', 'ልማትና በጎ አድራጎት ክፍል', 'ልማት', 0),
('finance', 'በጀት እና ንብረት አስተዳደር ክፍል', 'በጀት', 0),
('hr', 'ሰው ሀብት አስተዳደር ክፍል', 'ሰው ሀብት', 0)
ON DUPLICATE KEY UPDATE `name`=VALUES(`name`);

-- 2. የተጠቃሚዎች ሰንጠረዥ (Users)
CREATE TABLE IF NOT EXISTS `users` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `department_id` VARCHAR(50) NOT NULL,
  `full_name` VARCHAR(150) NOT NULL,
  `role_title` VARCHAR(100) NOT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `phone` VARCHAR(30) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`department_id`) REFERENCES `departments`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. የዓመታዊ እቅድ ክንውን ሰንጠረዥ (Plans)
CREATE TABLE IF NOT EXISTS `plans` (
  `id` VARCHAR(100) NOT NULL PRIMARY KEY,
  `department_id` VARCHAR(50) NOT NULL,
  `sub_department` VARCHAR(150) NULL,
  `main_task` TEXT NOT NULL,
  `detail_task` TEXT NOT NULL,
  `measurement` VARCHAR(100) NULL,
  `quantity` VARCHAR(100) NULL,
  `execution_time` VARCHAR(200) NULL,
  `budget` VARCHAR(100) NULL,
  `remarks` TEXT NULL,
  `months_json` JSON NULL,
  `progress_percent` INT DEFAULT 0,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`department_id`) REFERENCES `departments`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. ያልታቀዱ ግን የተከናወኑ ተግባራት (Unplanned Activities)
CREATE TABLE IF NOT EXISTS `unplanned_activities` (
  `id` VARCHAR(100) NOT NULL PRIMARY KEY,
  `department_id` VARCHAR(50) NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `description` TEXT NOT NULL,
  `reason` TEXT NULL,
  `date` VARCHAR(50) NOT NULL,
  `budget_spent` VARCHAR(100) NULL,
  `status` VARCHAR(50) DEFAULT 'submitted',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`department_id`) REFERENCES `departments`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. የተዘጋጁ ይፋዊ ሰነዶች ማህደር (Documents Archive)
CREATE TABLE IF NOT EXISTS `documents` (
  `id` VARCHAR(100) NOT NULL PRIMARY KEY,
  `department_id` VARCHAR(50) NOT NULL,
  `doc_type` ENUM('letter', 'proposal', 'note', 'table') NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `recipient` VARCHAR(255) NULL,
  `date` VARCHAR(50) NOT NULL,
  `content_json` JSON NOT NULL,
  `pdf_file_path` VARCHAR(255) NULL,
  `sent_to_telegram` TINYINT(1) DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`department_id`) REFERENCES `departments`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6. የውይይት መልእክቶች (Chat Messages)
CREATE TABLE IF NOT EXISTS `chat_messages` (
  `id` VARCHAR(100) NOT NULL PRIMARY KEY,
  `channel` VARCHAR(100) NOT NULL,
  `department_id` VARCHAR(50) NOT NULL,
  `sender_name` VARCHAR(150) NOT NULL,
  `sender_role` VARCHAR(100) NOT NULL,
  `message` TEXT NOT NULL,
  `is_official_notice` TINYINT(1) DEFAULT 0,
  `attachment_path` VARCHAR(255) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`department_id`) REFERENCES `departments`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 7. የስርዓቱ እና የቴሌግራም ቅንብሮች (Settings)
CREATE TABLE IF NOT EXISTS `system_settings` (
  `setting_key` VARCHAR(100) NOT NULL PRIMARY KEY,
  `setting_value` TEXT NOT NULL,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `system_settings` (`setting_key`, `setting_value`) VALUES
('telegram_bot_token', '8754142388:AAGKJUQ9PoeCgrlFNRQQlXEPy4uldnAP_c8'),
('telegram_chat_id', '')
ON DUPLICATE KEY UPDATE `setting_value`=VALUES(`setting_value`);
