-- ============================================================
-- የአጸደ ትጉሃን የተጠቃሚ-ተኮር የንባብ ማረጋገጫ (Migration 03: Per-User Read Receipts)
-- ነባር ሰንጠረዦችን እና መረጃዎችን ሳይነካ የሚተገበር
-- ============================================================

USE `atsede_db`;

-- 1. የቻት መልእክቶች የተጠቃሚ-ተኮር ንባብ ማረጋገጫ
CREATE TABLE IF NOT EXISTS `chat_message_reads` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `message_id` VARCHAR(100) NOT NULL,
  `user_id` INT NOT NULL,
  `read_at` DATETIME NOT NULL,
  UNIQUE KEY `uk_user_msg` (`user_id`, `message_id`),
  INDEX `idx_msg` (`message_id`),
  INDEX `idx_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. የማሳወቂያዎች የተጠቃሚ-ተኮር ንባብ ማረጋገጫ
CREATE TABLE IF NOT EXISTS `notification_reads` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `notification_id` VARCHAR(100) NOT NULL,
  `user_id` INT NOT NULL,
  `read_at` DATETIME NOT NULL,
  UNIQUE KEY `uk_user_notif` (`user_id`, `notification_id`),
  INDEX `idx_notif` (`notification_id`),
  INDEX `idx_user_notif` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
