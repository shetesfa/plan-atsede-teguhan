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
 * has no usable month + day (e.g. "ዓመቱን ሙሉ", "መስ (ሁሌ)...").
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

    // Month name + day, in either order. Day AFTER the month first
    // (so a leading year like "2019 ... ጥር 10" is not mistaken
    // for the day), then before it.
    $monthKey = null;
    $month = null;
    foreach (ethiopianMonthsMap() as $key => $num) {
        if (mb_strpos($text, $key) !== false) {
            $monthKey = $key;
            $month = $num;
            break;
        }
    }
    if ($month === null || $monthKey === null) return null;

    $monthIndex = mb_strpos($text, $monthKey);
    $afterMonth = mb_substr($text, $monthIndex + mb_strlen($monthKey));
    $beforeMonth = mb_substr($text, 0, $monthIndex);
    // Ignore 4-digit years when hunting for the day.
    $dayText = preg_replace('/20\d{2}/u', ' ', $afterMonth);
    $day = null;
    if (preg_match('/(\d{1,2})/u', $dayText, $dm)) {
        $day = (int)$dm[1];
    } else {
        $dayTextBefore = preg_replace('/20\d{2}/u', ' ', $beforeMonth);
        if (preg_match('/(\d{1,2})/u', $dayTextBefore, $dm)) {
            $day = (int)$dm[1];
        }
    }
    if ($day === null || $day < 1 || $day > 30) return null;

    $ethYear = currentEthiopianYear();
    if (preg_match('/(20\d{2})/u', $text, $ym)) {
        $ethYear = (int)$ym[1];
    }
    $d = ethiopianToGregorian($ethYear, $month, $day);
    return $d ? $d->format('Y-m-d') : null;
}
