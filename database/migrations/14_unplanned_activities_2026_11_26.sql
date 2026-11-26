-- Migration 14 (2026-11-26): server storage for unplanned-but-executed works.
--
-- Unplanned activities lived ONLY in the phone's memory (MainNavigationScreen
-- held a plain List, nothing ever saved it): an app restart wiped every
-- unplanned work, and the office could never see other departments' works.
-- They now live in this table.
--
-- Evidence photos are stored as bytes (evidence_data) — the Render container
-- filesystem is not writable, so nothing is ever gated on a disk write
-- (same lesson as migration 10 / reports.php). evidence_path holds the
-- original file name only; a device-local path is never stored.
--
-- TiDB-safe: idempotent (IF NOT EXISTS); one statement at a time.
CREATE TABLE IF NOT EXISTS `unplanned_activities` (
  `id` VARCHAR(64) PRIMARY KEY,
  `department_id` VARCHAR(64) NOT NULL,
  `department_name` VARCHAR(255) NOT NULL,
  `title` TEXT NOT NULL,
  `description` TEXT NULL,
  `execution_date` VARCHAR(100) NULL,
  `budget_used` VARCHAR(100) NULL,
  `evidence_path` VARCHAR(500) NULL,
  `evidence_mime` VARCHAR(100) NULL,
  `evidence_data` LONGBLOB NULL,
  `status` VARCHAR(50) NOT NULL DEFAULT 'ተመዝግቧል',
  `secretariat_note` TEXT NULL,
  `submitted_by_user_id` INT NULL,
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

ALTER TABLE `unplanned_activities` ADD INDEX IF NOT EXISTS `idx_unplanned_dept_date` (`department_id`, `execution_date`);
