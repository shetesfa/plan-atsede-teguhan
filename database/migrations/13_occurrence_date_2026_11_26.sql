-- Migration 13 (2026-11-26): one report per occurrence for recurring plans.
--
-- A plan that repeats every month/week used to show only ONE comment —
-- the card always showed the latest report. Each report now carries the
-- exact occurrence date it belongs to (occurrence_date), so the Calendar
-- can show each month's own report and a reported month stops looking
-- overdue. NULL = report submitted before this feature (legacy).
--
-- TiDB-safe: one ADD COLUMN per statement; idempotent (IF NOT EXISTS).
ALTER TABLE `reports` ADD COLUMN IF NOT EXISTS `occurrence_date` DATE NULL;

ALTER TABLE `reports` ADD INDEX IF NOT EXISTS `idx_reports_occurrence` (`occurrence_date`);
