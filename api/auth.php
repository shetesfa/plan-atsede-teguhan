<?php
// ============================================================
// የአጸደ ትጉሃን የተጠቃሚዎች ማረጋገጫ ኤፒአይ (Hardened Authentication API)
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
               u.must_change_password,
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
        'role' => $user['role'] ?? 'member'
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
    $pdo->prepare("UPDATE users SET password_hash = ?, must_change_password = 0 WHERE id = ?")->execute([$newHash, $auth['user_id']]);

    logAudit($pdo, 'password_change', 'users', (string)$auth['user_id'], $auth['user_id'], $auth['department_id']);

    jsonResponse(['message' => 'የይለፍ ቃልዎ በተሳካ ሁኔታ ተቀይሯል!']);
}

jsonError('ያልታወቀ ጥያቄ ወይም ዘዴ', 404);
