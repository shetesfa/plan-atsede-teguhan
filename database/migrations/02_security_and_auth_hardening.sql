-- ============================================================
-- የአጸደ ትጉሃን የደህንነት ማጠናከሪያ ስክሪፕት (Migration 02: Security & Hardening)
-- ============================================================

USE `atsede_db`;

-- 1. የመግቢያ ሙከራዎችን መከታተያ (Rate Limiting Table)
CREATE TABLE IF NOT EXISTS `login_attempts` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `attempt_key` VARCHAR(150) NOT NULL UNIQUE,
  `attempts` INT DEFAULT 1,
  `last_attempt` DATETIME NOT NULL,
  `locked_until` DATETIME NULL,
  INDEX (`attempt_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. የተሰረዙ ቶከኖች መዝገብ (Revoked Tokens Table for Secure Logout)
CREATE TABLE IF NOT EXISTS `revoked_tokens` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `token_hash` VARCHAR(64) NOT NULL UNIQUE,
  `user_id` INT NULL,
  `revoked_at` DATETIME NOT NULL,
  `expires_at` INT NOT NULL,
  INDEX (`token_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. የተጠቃሚዎችን የይለፍ ቃል ወደ አስተማማኝ ጠንካራ hash ማዘመን
-- (ነባሪ የሙከራ ክፍሎች ካሉ ጠንካራ የ bcrypt hash እንሰጣቸዋለን)
-- የይለፍ ቃል: Atsede@2019Secured!
-- Bcrypt cost 12: $2y$12$7Jd8kG9q1FvY8wL4hN2sI.5ZgYw1P0xR6mU9vQ3tB7nE5aC8dF1kO
