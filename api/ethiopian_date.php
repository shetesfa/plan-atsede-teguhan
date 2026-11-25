<?php
// ============================================================
// የኢትዮጵያ ቀን መቁጠሪያ — PHP port of the Flutter app's parser
// (lib/services/notification_service.dart :: parseEthiopianDate)
// The app's plan dates are free-text Ethiopian strings such as
// "መስከረም 5", "ጥር 10 እስከ 12" or "18/01/2019". This file gives
// the server the same best-effort reading, so due dates,
// reminders and overdue detection use one shared rule.
// Conversion is approximate: Ethiopian year N starts 11 Sep of
// Gregorian year N+7 (12 Sep when N % 4 == 0); Pagume is allowed
// up to 6 days, so a leap-day edge can be off by one.
//
// RULE (2026-11-25, Tesfa): a plan's real date is its LAST
// window, not its first. "መስ (10-30), የካ (6-28)" runs in
// Meskerem AND in Yekatit, so it is due at the END of Yekatit
// (28), not at the start of Meskerem (10). Taking the first
// date flagged such plans as "late" months too early.
// "ዓመቱን ሙሉ" (the whole year) is due at the end of the year
// (Pagume 5, 6 in a leap year). A month with no day ("ሁሌ",
// "የወሩ መጨረሻ", month name alone) is due at the end of that
// month (day 30, Pagume 5/6).
// ============================================================

date_default_timezone_set('Africa/Addis_Ababa');

/** Ethiopian month names (full + short forms) => month number. Order matters: first match wins. */
function ethiopianMonthsMap(): array {
    return [
        'መስከረም' => 1, 'መስ' => 1,
        'ጥቅምት' => 2, 'ጥቅ' => 2,
        'ኅዳር' => 3, 'ኅዳ' => 3, 'ህዳር' => 3, 'ህዳ' => 3,
        'ታኅሣሥ' => 4, 'ታኅ' => 4, 'ታህሳስ' => 4, 'ታህ' => 4,
        'ጥር' => 5,
        'የካቲት' => 6, 'የካ' => 6,
        'መጋቢት' => 7, 'መጋ' => 7,
        'ሚያዝያ' => 8, 'ሚያ' => 8,
        'ግንቦት' => 9, 'ግንቦ' => 9,
        'ሰኔ' => 10,
        'ሐምሌ' => 11, 'ሐም' => 11,
        'ነሐሴ' => 12, 'ነሐ' => 12,
        'ጳጉሜ' => 13, 'ጳጉ' => 13,
    ];
}

function currentEthiopianYear(): int {
    $now = new DateTimeImmutable('now', new DateTimeZone('Africa/Addis_Ababa'));
    $newYear = new DateTimeImmutable($now->format('Y') . '-09-11', new DateTimeZone('Africa/Addis_Ababa'));
    return $now < $newYear ? (int)$now->format('Y') - 8 : (int)$now->format('Y') - 7;
}

/** Ethiopian (year, month, day) => Gregorian DateTimeImmutable, or null. */
function ethiopianToGregorian(int $ethYear, int $month, int $day): ?DateTimeImmutable {
    if ($month < 1 || $month > 13 || $day < 1) return null;
    if ($month === 13 && $day > 6) return null;
    if ($month < 13 && $day > 30) return null;
    $startYear = $ethYear + 7;
    $startDay = ($ethYear % 4 === 0) ? 12 : 11;
    $start = new DateTimeImmutable(sprintf('%04d-09-%02d', $startYear, $startDay), new DateTimeZone('Africa/Addis_Ababa'));
    return $start->modify('+' . (($month - 1) * 30 + ($day - 1)) . ' days');
}

/**
 * Best-effort parse of a free-text Ethiopian date.
 * Returns a 'Y-m-d' Gregorian date string, or null when the text
 * has no usable month (e.g. empty text).
 *
 * The plan's real date is its LAST window: every month name in
 * the text is found, the last one wins, and within it the last
 * day number wins (ranges "10-30" -> 30, lists "4፣11፣18" -> 18).
 * A month with no day ("ሁሌ", "የወሩ መጨረሻ", name alone) is due
 * at the end of that month. "ዓመቱን ሙሉ" is due at the end of
 * the Ethiopian year.
 */
function parseEthiopianDate(?string $raw): ?string {
    if ($raw === null) return null;
    $text = trim($raw);
    if ($text === '') return null;

    // Numeric Ethiopian date: dd/mm/yyyy (e.g. 18/01/2019).
    if (preg_match('/(\d{1,2})\s*\/\s*(\d{1,2})\s*\/\s*(\d{4})/u', $text, $m)) {
        $d = ethiopianToGregorian((int)$m[3], (int)$m[2], (int)$m[1]);
        return $d ? $d->format('Y-m-d') : null;
    }

    // Year: explicit 4-digit Ethiopian year in the text, else the
    // current Ethiopian year.
    $ethYear = currentEthiopianYear();
    if (preg_match('/(20\d{2})/u', $text, $ym)) {
        $ethYear = (int)$ym[1];
    }

    // "ዓመቱን ሙሉ" (the whole year): due at the end of the year.
    if (mb_strpos($text, 'ዓመቱን ሙሉ') !== false) {
        $lastDay = ($ethYear % 4 === 0) ? 6 : 5;
        $d = ethiopianToGregorian($ethYear, 13, $lastDay);
        return $d ? $d->format('Y-m-d') : null;
    }

    // Every month-name occurrence (longest name wins at the same
    // position, so "መስ" never steals "መስከረም").
    $occurrences = []; // [charPos, nameLen, monthNum]
    foreach (ethiopianMonthsMap() as $key => $num) {
        $offset = 0;
        while (($pos = mb_strpos($text, $key, $offset)) !== false) {
            $occurrences[] = [$pos, mb_strlen($key), $num];
            $offset = $pos + 1;
        }
    }
    if (empty($occurrences)) return null;
    usort($occurrences, function ($a, $b) {
        if ($a[0] !== $b[0]) return $a[0] <=> $b[0];
        return $b[1] <=> $a[1]; // longest first at same position
    });
    $filtered = [];
    $lastPos = -1;
    $lastLen = 0;
    foreach ($occurrences as $o) {
        if ($o[0] === $lastPos && $o[1] < $lastLen) continue;
        $filtered[] = $o;
        $lastPos = $o[0];
        $lastLen = $o[1];
    }
    $last = end($filtered);
    [$lastPos, $lastLen, $month] = $last;

    // Days after the last month name: the LAST number wins.
    // 4-digit years are ignored. No number means the end of
    // that month ("ሁሌ", "የወሩ መጨረሻ", month name alone).
    $segment = mb_substr($text, $lastPos + $lastLen);
    $segment = preg_replace('/20\d{2}/u', ' ', $segment);
    $day = null;
    if (preg_match_all('/(\d{1,2})/u', $segment, $dm)) {
        $nums = array_map('intval', $dm[1]);
        $day = end($nums);
    }
    if ($day === null) {
        $day = ($month === 13) ? (($ethYear % 4 === 0) ? 6 : 5) : 30;
    }
    if ($day < 1) return null;
    if ($month === 13 && $day > 6) $day = 6;
    if ($month < 13 && $day > 30) $day = 30;

    $d = ethiopianToGregorian($ethYear, $month, $day);
    return $d ? $d->format('Y-m-d') : null;
}
