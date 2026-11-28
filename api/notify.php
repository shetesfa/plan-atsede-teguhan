<?php
// ============================================================
// የዐጸደ ትጉሃን Telegram relay (Server-side Telegram relay)
// 2026-11-28: the app must NEVER need a bot token. The app calls
// this endpoint with the user's own login token, and THIS server
// forwards the message to the bot proxy with the server-side
// BOT_PROXY_SECRET. The target chat is server-side only — the
// client can never choose where the message goes.
// ============================================================

require_once __DIR__ . '/config.php';

// Bot service base URL — override with BOT_SERVICE_URL in Render;
// the default is the live bot service.
function notifyBotBase(): string {
    $base = trim((string)(getenv('BOT_SERVICE_URL') ?: ''));
    if ($base === '') {
        $base = 'https://plan-atsede-teguhan-new.onrender.com';
    }
    return rtrim($base, '/');
}

function notifyProxySecret(): string {
    return (string)(getenv('BOT_PROXY_SECRET') ?: '');
}

// The office chat, server-side only:
//   1) TELEGRAM_CHAT_ID (or CHAT_ID) env on this service;
//   2) for the overdue alert only, the sender's own linked chat
//      (the sender IS the office, so their chat is an office chat);
//   3) null — the bot proxy itself defaults to its own office
//      CHAT_ID when chat_id is omitted, so the caller omits it.
// A report notice NEVER falls back to the sender's chat: it must
// reach the office, not come back to the sender.
function notifyOfficeChatId(array $auth, PDO $pdo, bool $allowSenderFallback): ?string {
    $env = trim((string)(getenv('TELEGRAM_CHAT_ID') ?: getenv('CHAT_ID') ?: ''));
    if ($env !== '') {
        return $env;
    }
    if ($allowSenderFallback) {
        $stmt = $pdo->prepare("SELECT telegram_chat_id FROM users WHERE id = ? LIMIT 1");
        $stmt->execute([(int)$auth['user_id']]);
        $chatId = $stmt->fetchColumn();
        if ($chatId !== false && $chatId !== null && trim((string)$chatId) !== '') {
            return trim((string)$chatId);
        }
    }
    return null;
}

// POST JSON to the bot proxy. Returns ['transport_error' => bool,
// 'status' => int, 'body' => array|null]. No curl extension is
// installed in the Docker image, so this uses a stream context.
function notifyPostJson(string $url, array $payload, string $secret): array {
    $context = stream_context_create([
        'http' => [
            'method' => 'POST',
            'header' => "Content-Type: application/json\r\nX-Bot-Proxy-Secret: {$secret}\r\n",
            'content' => json_encode($payload, JSON_UNESCAPED_UNICODE),
            'timeout' => 15,
            'ignore_errors' => true,
        ],
        'ssl' => [
            'verify_peer' => true,
            'verify_peer_name' => true,
        ],
    ]);
    $raw = @file_get_contents($url, false, $context);
    if ($raw === false) {
        return ['transport_error' => true];
    }
    $status = 0;
    if (isset($http_response_header) && is_array($http_response_header)) {
        foreach ($http_response_header as $h) {
            if (preg_match('#^HTTP/\S+\s+(\d+)#', $h, $m)) {
                $status = (int)$m[1];
            }
        }
    }
    $decoded = json_decode($raw, true);
    return [
        'transport_error' => false,
        'status' => $status,
        'body' => is_array($decoded) ? $decoded : null,
    ];
}

try {
    $auth = requireAuth();
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        jsonError('POST ብቻ ይፈቀዳል', 405);
    }

    $input = getJsonInput();
    $action = (string)($input['action'] ?? '');
    $message = trim((string)($input['message'] ?? ''));
    if ($message === '') {
        jsonError('መልእክቱ ባዶ ነው', 400);
    }
    // Telegram allows 4096 characters per message.
    if (mb_strlen($message) > 4000) {
        jsonError('መልእክቱ በጣም ረጅም ነው (ከ 4000 ፊደላት በላይ)', 400);
    }

    // Same pattern as api/bot.php: without the server-side secret
    // the relay cannot authenticate to the bot proxy.
    $secret = notifyProxySecret();
    if ($secret === '') {
        jsonError('የ Telegram relay በአገልጋዩ ላይ አልተዋቀረም', 503);
    }

    $base = notifyBotBase();
    $url = '';
    $proxyPayload = [];

    if ($action === 'overdue_alert') {
        // ያዘገዩ እቅዶች ማስጠንቀቂያ — የጽ/ቤት (Super Admin) ብቻ።
        requireSuperAdmin($auth);
        $chatId = notifyOfficeChatId($auth, $pdo, true);
        $proxyPayload = ['text' => $message, 'parse_mode' => 'HTML'];
        if ($chatId !== null) {
            $proxyPayload['chat_id'] = $chatId;
        }
        $url = $base . '/api/telegram/sendMessage';
    } elseif ($action === 'report_notice') {
        // የእቅድ ክንውን ሪፖርት ማሳወቂያ — ማንኛውም የገባ ተጠቃሚ፣
        // ግን ሪፖርቱ ሲሰጥ የራሱ ክፍል ሪፖርት መሆን አለበት።
        // 2026-11-28: ቁጥጥር ማየት ብቻ ነው — የሌላ ክፍል ሪፖርት
        // ማሳወቂያ መላክ አይችልም (የጽ/ቤት ወይም የራሱ ክፍል ብቻ)።
        $reportId = trim((string)($input['report_id'] ?? ''));
        if ($reportId !== '') {
            $stmt = $pdo->prepare("SELECT department_id FROM reports WHERE id = ? LIMIT 1");
            $stmt->execute([$reportId]);
            $repDept = $stmt->fetchColumn();
            if ($repDept === false) {
                jsonError('ሪፖርቱ አልተገኘም', 404);
            }
            if (empty($auth['is_super_admin']) && $auth['department_id'] !== $repDept) {
                jsonError('የሌላ ክፍል ሪፖርት ማሳወቂያ መላክ አይፈቀድም (Forbidden).', 403);
            }
        }
        // Target is ALWAYS the office chat — never the sender's own chat.
        $chatId = notifyOfficeChatId($auth, $pdo, false);
        $proxyPayload = ['message' => $message];
        if ($chatId !== null) {
            $proxyPayload['chat_id'] = $chatId;
        }
        if ($reportId !== '') {
            $proxyPayload['report_id'] = $reportId;
        }
        // send_notice attaches the office approve/reject buttons
        // when report_id is present.
        $url = $base . '/api/send_notice';
    } else {
        jsonError('ያልታወቀ ተግባር', 400);
    }

    $result = notifyPostJson($url, $proxyPayload, $secret);
    if (!empty($result['transport_error'])) {
        error_log('notify.php: bot proxy unreachable for action ' . $action);
        jsonError('የ Telegram አገልግሎት በአሁኑ ጊዜ አልተገኘም — እባክዎ ቆይተው እንደገና ይሞክሩ', 502);
    }

    $body = is_array($result['body']) ? $result['body'] : [];
    if (($body['ok'] ?? false) === true) {
        $telegramId = $body['result']['message_id'] ?? null;
        logAudit($pdo, 'telegram_relay', 'notifications', $action, (int)$auth['user_id'], $auth['department_id'], ['action' => $action, 'ok' => true]);
        jsonResponse(['ok' => true, 'telegram_message_id' => $telegramId]);
    }

    // Honest failure — Telegram's own error text, never DB internals.
    $error = (string)($body['description'] ?? $body['error'] ?? 'Telegram መልእክት መላክ አልተቻለም');
    logAudit($pdo, 'telegram_relay', 'notifications', $action, (int)$auth['user_id'], $auth['department_id'], ['action' => $action, 'ok' => false]);
    jsonResponse(['ok' => false, 'error' => $error]);
} catch (Throwable $e) {
    // M5: never leak internals (paths, SQL) in a 500 — log it here.
    error_log('notify.php error: ' . $e->getMessage());
    jsonError('የአገልጋይ ስህተት — እባክዎ ቆይተው እንደገና ይሞክሩ', 500);
}
