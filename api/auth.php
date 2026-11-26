<?php
// ============================================================
// የዐጸደ ትጉሃን የተጠቃሚዎች ማረጋገጫ ኤፒአይ (Hardened Authentication API)
// ============================================================

require_once __DIR__ . '/config.php';

$action = $_GET['action'] ?? 'login';
$method = $_SERVER['REQUEST_METHOD'];

// 1. መግቢያ (Secure Login with Rate Limiting)
if ($action === 'login' && $method === 'POST') {
    $input = getJsonInput();
    $loginIdentifier = trim($input['username'] ?? $input['department_id'] ?? '');
    $password = (string)($input['password'] ?? '');

    if (empty($loginIdentifier) || empty($password)) {
        jsonError('እባክዎ የተጠቃሚ ስም እና የይለፍ ቃል ያስገቡ።', 400);
    }

    $ip = $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1';
    $rateLimitKey = "login_" . hash('sha256', $ip . '_' . strtolower($loginIdentifier));

    // Rate Limiting ፍተሻ (ከ 5 ሙከራ በላይ ከሆነ ለ 15 ደቂቃ ይቆልፋል)
    checkRateLimit($pdo, $rateLimitKey, 5, 15);

    // ተጠቃሚውን ከዳታቤዝ ብቻ መፈለግ (Auto-creation ሙሉ በሙሉ ተወግዷል!)
    // 2026-11-26: አንድ ክፍል ብዙ ሰዎች ሊኖሩት ይችላል (ለምሳሌ ቁጥጥር 4 ሰዎች)።
    // ስም አይጠየቅም — ክፍል + የይለፍ ቃል ብቻ ነው። የይለፍ ቃሉ የየትኛው ሰው እንደሆነ
    // ይለያል፦ በክፍሉ ውስጥ ያሉትን ሁሉንም ንቁ ተጠቃሚዎች እንፈትሻለን፣ የይለፍ ቃሉ
    // የሚዛመደው ሰው እንደገባ ይቆጠራል። (በአንድ ክፍል ውስጥ የሁለት ሰዎች የይለፍ
    // ቃል አንድ መሆን የለበትም — አሁን ሁሉም የተለየ ነው።)
    $stmt = $pdo->prepare("
        SELECT u.id, u.username, u.full_name, u.role_title, u.role, u.password_hash, u.status, u.phone, u.email,
               u.must_change_password, u.token_version,
               d.id AS department_id, d.name AS department_name, d.short_name AS department_short_name, d.is_super_admin, d.can_view_all
        FROM users u
        JOIN departments d ON u.department_id = d.id
        WHERE (u.username = ? OR u.department_id = ?)
          AND u.status = 'active'
    ");
    $stmt->execute([$loginIdentifier, $loginIdentifier]);
    $candidates = $stmt->fetchAll();

    // የይለፍ ቃል በ Bcrypt ብቻ ማረጋገጥ (ምንም ደካማ ነባሪ የለም!)
    $user = null;
    foreach ($candidates as $candidate) {
        if (password_verify($password, $candidate['password_hash'])) {
            $user = $candidate;
            break;
        }
    }

    if (!$user) {
        recordFailedLoginAttempt($pdo, $rateLimitKey);
        jsonError('የተሳሳተ የተጠቃሚ ስም ወይም የይለፍ ቃል!', 401);
    }

    // ስኬታማ መግቢያ — Rate Limit ሪከርድ ማጽዳት
    clearRateLimit($pdo, $rateLimitKey);

    $now = date('Y-m-d H:i:s');
    $pdo->prepare("UPDATE users SET last_login = ? WHERE id = ?")->execute([$now, $user['id']]);

    // HMAC Token በሰርቨር ላይ ብቻ በተመሰረቱ ትክክለኛ መረጃዎች ማመንጨት
    $tokenPayload = [
        'user_id' => (int)$user['id'],
        'department_id' => $user['department_id'],
        'username' => $user['username'],
        'is_super_admin' => (bool)$user['is_super_admin'],
        // 2026-11-26: control department sees all (view-only).
        'can_view_all' => (bool)($user['can_view_all'] ?? false),
        'role_title' => $user['role_title'],
        'role' => $user['role'] ?? 'member',
        // 2026-11-26: token version — bumped on every password change;
        // verifyToken() rejects tokens with a stale version.
        'token_version' => (int)($user['token_version'] ?? 0)
    ];
    $token = createToken($tokenPayload, 86400 * 7); // ለ 7 ቀናት የሚሰራ

    logAudit($pdo, 'user_login', 'users', (string)$user['id'], (int)$user['id'], $user['department_id'], [
        'username' => $user['username'],
        'ip' => $ip
    ]);

    jsonResponse([
        'token' => $token,
        'user' => [
            'id' => (int)$user['id'],
            'username' => $user['username'],
            'full_name' => $user['full_name'],
            'role_title' => $user['role_title'],
            'department_id' => $user['department_id'],
            'department_name' => $user['department_name'],
            'department_short_name' => $user['department_short_name'],
            'is_super_admin' => (bool)$user['is_super_admin'],
            // 2026-11-26: control department sees all (view-only).
            'can_view_all' => (bool)($user['can_view_all'] ?? false),
            'role' => $user['role'] ?? 'member',
            'is_dept_admin' => (($user['role'] ?? '') === 'dept_admin'),
            // Audit fix 2026-11-25: seed passwords must be changed on
            // first login — the app shows the change screen when true.
            'must_change_password' => (bool)($user['must_change_password'] ?? 0)
        ]
    ]);
}

// 2. መውጫ (Secure Logout — Revoke Token)
if ($action === 'logout' && $method === 'POST') {
    $auth = requireAuth();
    $headers = getallheaders();
    $authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    if (preg_match('/Bearer\s+(.*)$/i', $authHeader, $matches)) {
        revokeToken($pdo, trim($matches[1]), $auth['user_id']);
    }
    logAudit($pdo, 'user_logout', 'users', (string)$auth['user_id'], $auth['user_id'], $auth['department_id']);
    jsonResponse(['message' => 'በተሳካ ሁኔታ ከስርዓቱ ወጥተዋል']);
}

// 3. የአሁኑን ተጠቃሚ መረጃ ማረጋገጫ (Profile)
if ($action === 'me' && $method === 'GET') {
    $auth = requireAuth();

    $stmt = $pdo->prepare("
        SELECT u.id, u.username, u.full_name, u.role_title, u.phone, u.email, u.last_login, u.must_change_password,
               d.id AS department_id, d.name AS department_name, d.short_name AS department_short_name, d.is_super_admin, d.can_view_all
        FROM users u
        JOIN departments d ON u.department_id = d.id
        WHERE u.id = ? AND u.status = 'active'
        LIMIT 1
    ");
    $stmt->execute([$auth['user_id']]);
    $user = $stmt->fetch();

    if (!$user) {
        jsonError('ተጠቃሚው አልተገኘም ወይም ታግዷል!', 404);
    }

    jsonResponse(['user' => $user]);
}

// 4. የይለፍ ቃል መቀየሪያ (Change Password)
if ($action === 'change_password' && $method === 'POST') {
    $auth = requireAuth();
    $input = getJsonInput();
    $oldPass = (string)($input['old_password'] ?? '');
    $newPass = (string)($input['new_password'] ?? '');

    if (strlen($newPass) < 8 || !preg_match('/[0-9]/', $newPass)) {
        jsonError('አዲሱ የይለፍ ቃል ቢያንስ 8 ፊደላት እና ቢያንስ አንድ ቁጥር መያዝ አለበት።', 400);
    }

    $stmt = $pdo->prepare("SELECT password_hash FROM users WHERE id = ?");
    $stmt->execute([$auth['user_id']]);
    $currentHash = $stmt->fetchColumn();

    if (!$currentHash || !password_verify($oldPass, $currentHash)) {
        jsonError('የድሮው የይለፍ ቃል የተሳሳተ ነው!', 400);
    }

    $newHash = password_hash($newPass, PASSWORD_BCRYPT, ['cost' => 12]);
    // Audit fix 2026-11-25: a successful change clears the first-login flag.
    // 2026-11-26: bump token_version so every token issued before this
    // password change stops working immediately.
    $pdo->prepare("UPDATE users SET password_hash = ?, must_change_password = 0, token_version = token_version + 1 WHERE id = ?")->execute([$newHash, $auth['user_id']]);

    logAudit($pdo, 'password_change', 'users', (string)$auth['user_id'], $auth['user_id'], $auth['department_id']);

    jsonResponse(['message' => 'የይለፍ ቃልዎ በተሳካ ሁኔታ ተቀይሯል!']);
}

// 5. Telegram ማገናኘት — አንድ ጊዜ የሚሰራ 6 አሃዝ ኮድ መስጠት (Link code)
// 2026-11-26 (bot upgrade): the app asks for a code, the user sends
// /start <code> to the bot, the bot verifies it (bot.php link_verify).
// The code itself is returned to the LOGGED-IN user only — it is
// their own code, for their own account.
if ($action === 'link_code' && $method === 'POST') {
    $auth = requireAuth();
    $userId = (int)$auth['user_id'];

    // ሰዓት ውስጥ 5 ኮዶች ብቻ — ስፓም እንዳይሆን።
    $countStmt = $pdo->prepare("SELECT COUNT(*) FROM telegram_link_codes WHERE user_id = ? AND created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)");
    $countStmt->execute([$userId]);
    if ((int)$countStmt->fetchColumn() >= 5) {
        jsonError('በጣም ብዙ ኮድ ጠይቀዋል — እባክዎ ከአንድ ሰዓት በኋላ ደግመው ይሞክሩ', 429);
    }

    $code = (string)random_int(100000, 999999);
    $hash = hash('sha256', $code);
    $expires = date('Y-m-d H:i:s', time() + 900); // 15 minutes
    $pdo->prepare("UPDATE telegram_link_codes SET used_at = NOW() WHERE user_id = ? AND used_at IS NULL")->execute([$userId]);
    $pdo->prepare("INSERT INTO telegram_link_codes (user_id, code_hash, expires_at) VALUES (?, ?, ?)")->execute([$userId, $hash, $expires]);

    logAudit($pdo, 'telegram_link_code', 'users', (string)$userId, $userId, $auth['department_id'], []);
    jsonResponse(['code' => $code, 'expires_in_seconds' => 900]);
}

// 6. Telegram የተገናኘበት ሁኔታ (Link status)
if ($action === 'telegram_status' && $method === 'GET') {
    $auth = requireAuth();
    $stmt = $pdo->prepare("SELECT telegram_chat_id FROM users WHERE id = ? LIMIT 1");
    $stmt->execute([(int)$auth['user_id']]);
    $chatId = $stmt->fetchColumn();
    jsonResponse([
        'linked' => !empty($chatId),
        'telegram_chat_id' => $chatId ?: null,
    ]);
}

// 7. Telegram ማገናኘት ማቋረጥ (Unlink)
if ($action === 'unlink_telegram' && $method === 'POST') {
    $auth = requireAuth();
    $pdo->prepare("UPDATE users SET telegram_chat_id = NULL WHERE id = ?")->execute([(int)$auth['user_id']]);
    logAudit($pdo, 'telegram_unlink', 'users', (string)$auth['user_id'], (int)$auth['user_id'], $auth['department_id'], []);
    jsonResponse(['linked' => false, 'message' => 'Telegram ማገናኘት ተቋርጧል']);
}

// 8. የይለፍ ቃል ዳግም ማስጀመር በኮድ — ከመግቢያ ገጹ "የይለፍ ቃል ረሳህ?"
// (Password reset with a Telegram code — no login needed)
// Flow: the user sends /reset to the bot, the bot sends a 6-digit
// code to their LINKED Telegram chat, the user types the code + a
// new password here. Rate-limited exactly like login (5 tries /
// 15 min, keyed by IP + username). The code is compared by hash
// server-side and never logged.
if ($action === 'reset_with_code' && $method === 'POST') {
    $input = getJsonInput();
    $identifier = trim($input['username'] ?? $input['department_id'] ?? '');
    $code = trim((string)($input['code'] ?? ''));
    $newPass = (string)($input['new_password'] ?? '');

    if ($identifier === '' || $code === '' || $newPass === '') {
        jsonError('የተጠቃሚ ስም፣ ኮድ እና አዲስ የይለፍ ቃል ያስፈልጋሉ', 400);
    }
    if (strlen($newPass) < 8 || !preg_match('/[0-9]/', $newPass)) {
        jsonError('አዲሱ የይለፍ ቃል ቢያንስ 8 ፊደላት እና ቢያንስ አንድ ቁጥር መያዝ አለበት።', 400);
    }

    $ip = $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1';
    $rateLimitKey = "reset_" . hash('sha256', $ip . '_' . strtolower($identifier));
    checkRateLimit($pdo, $rateLimitKey, 5, 15);

    $stmt = $pdo->prepare("
        SELECT u.id, u.username, u.department_id
        FROM users u
        WHERE (u.username = ? OR u.department_id = ?)
          AND u.status = 'active'
    ");
    $stmt->execute([$identifier, $identifier]);
    $candidates = $stmt->fetchAll();

    $userId = null;
    $codeId = null;
    $codeHash = hash('sha256', $code);
    foreach ($candidates as $candidate) {
        $cStmt = $pdo->prepare("
            SELECT id FROM password_reset_codes
            WHERE user_id = ? AND code_hash = ? AND used_at IS NULL AND expires_at > NOW()
            ORDER BY created_at DESC LIMIT 1
        ");
        $cStmt->execute([(int)$candidate['id'], $codeHash]);
        $found = $cStmt->fetch();
        if ($found) {
            $userId = (int)$candidate['id'];
            $codeId = (int)$found['id'];
            break;
        }
    }

    if ($userId === null) {
        recordFailedLoginAttempt($pdo, $rateLimitKey);
        jsonError('ኮዱ የተሳሳተ ነው ወይም ጊዜው አልፏል — በቴሌግራም /reset ብለው አዲስ ኮድ ይጠይቁ', 400);
    }

    $newHash = password_hash($newPass, PASSWORD_BCRYPT, ['cost' => 12]);
    $pdo->beginTransaction();
    try {
        // Password change bumps token_version — every token issued
        // before this reset stops working immediately.
        $pdo->prepare("UPDATE users SET password_hash = ?, must_change_password = 0, token_version = token_version + 1 WHERE id = ?")->execute([$newHash, $userId]);
        $pdo->prepare("UPDATE password_reset_codes SET used_at = NOW() WHERE id = ?")->execute([$codeId]);
        $pdo->commit();
    } catch (Exception $e) {
        $pdo->rollBack();
        error_log('reset_with_code error: ' . $e->getMessage());
        jsonError('የይለፍ ቃል መቀየር አልተቻለም — እባክዎ እንደገና ይሞክሩ', 500);
    }

    clearRateLimit($pdo, $rateLimitKey);
    logAudit($pdo, 'telegram_password_reset', 'users', (string)$userId, $userId, null, []);
    jsonResponse(['message' => 'የይለፍ ቃልዎ በተሳካ ሁኔታ ተቀይሯል! በአዲሱ ይግቡ።']);
}

jsonError('ያልታወቀ ጥያቄ ወይም ዘዴ', 404);
