<?php
// ============================================================
// የአጸደ ትጉሃን አገልጋይ ማእከላዊ ውቅር እና የደህንነት መጠበቂያ (Core Configuration & Hardened Security)
// ============================================================

// 1. የሰዓት አቆጣጠር ወደ ኢትዮጵያ (Africa/Addis_Ababa) ማስተካከል
date_default_timezone_set('Africa/Addis_Ababa');

// 2. የ .env ፋይል ማንበቢያ ረዳት
function loadEnvFile(string $filePath): void {
    if (!file_exists($filePath)) return;
    $lines = file($filePath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        $line = trim($line);
        if (empty($line) || str_starts_with($line, '#')) continue;
        if (str_contains($line, '=')) {
            list($key, $val) = explode('=', $line, 2);
            $key = trim($key);
            $val = trim($val, " \t\n\r\0\x0B\"'");
            if (getenv($key) === false) {
                putenv("$key=$val");
                $_ENV[$key] = $val;
            }
        }
    }
}

loadEnvFile(__DIR__ . '/.env');
loadEnvFile(__DIR__ . '/../.env');

// 3. ወጥ የሆኑ የ JSON ምላሽ ረዳቶች
function jsonResponse($data, int $statusCode = 200): void {
    http_response_code($statusCode);
    echo json_encode([
        'status' => 'success',
        'timestamp' => date('Y-m-d H:i:s'),
        'data' => $data
    ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    exit;
}

function jsonError(string $message, int $statusCode = 400, $errors = null): void {
    http_response_code($statusCode);
    $response = [
        'status' => 'error',
        'timestamp' => date('Y-m-d H:i:s'),
        'message' => $message
    ];
    if ($errors !== null) {
        $response['errors'] = $errors;
    }
    echo json_encode($response, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    exit;
}

// 4. የተፈቀደ የ CORS ጥበቃ (Restricted Trusted Origins Only — Never use '*')
$allowedOriginsStr = getenv('ALLOWED_ORIGINS') ?: 'http://localhost:3000,http://127.0.0.1:8000,http://localhost:8080,http://127.0.0.1';
$allowedOrigins = array_filter(array_map('trim', explode(',', $allowedOriginsStr)));

$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if (!empty($origin)) {
    if (in_array($origin, $allowedOrigins, true)) {
        header("Access-Control-Allow-Origin: $origin");
    } else {
        // ያልተፈቀደ የውጭ አመጣጥ ከተገኘ ጥያቄውን ማገድ
        http_response_code(403);
        echo json_encode(['status' => 'error', 'message' => 'የተከለከለ የ CORS መዳረሻ (Untrusted Origin)'], JSON_UNESCAPED_UNICODE);
        exit;
    }
}
// ማሳሰቢያ፦ $origin ከሌለ (ከሞባይል መተግበሪያ ወይም ቀጥታ ከአገልጋይ የመጣ ከሆነ) ምንም የ Access-Control-Allow-Origin ራስጌ አይላክም (No arbitrary echo)

header("Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, X-Device-ID");
header("Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS");
header("Access-Control-Allow-Credentials: true");
header("Content-Type: application/json; charset=UTF-8");
header("X-Content-Type-Options: nosniff");
header("X-Frame-Options: DENY");
header("X-XSS-Protection: 1; mode=block");
header("Referrer-Policy: strict-origin-when-cross-origin");

if (isset($_SERVER['REQUEST_METHOD']) && $_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// 5. ጥብቅ የ JWT Secret ፍተሻ (Refuse to start if missing or weak)
$jwtSecret = getenv('JWT_SECRET');
if (empty($jwtSecret) || strlen($jwtSecret) < 32) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'የአገልጋዩ የደህንነት ምስጢር (JWT_SECRET) አልተዋቀረም ወይም ደካማ ነው። እባክዎ በ .env ውስጥ ቢያንስ 32 ፊደላት/ቁጥሮች ያለው ቁልፍ ያዋቅሩ።'
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

// 6. የዳታቤዝ ምስክርነቶች ከ .env ብቻ (No hardcoded credentials)
$appEnv = getenv('APP_ENV') ?: 'production';
$dbHost = getenv('DB_HOST') ?: '127.0.0.1';
$dbName = getenv('DB_NAME') ?: 'atsede_db';
$dbUser = getenv('DB_USER');
$dbPass = getenv('DB_PASS');
$dbCharset = getenv('DB_CHARSET') ?: 'utf8mb4';

if ($dbUser === false || $dbUser === null || trim($dbUser) === '') {
    jsonError('የዳታቤዝ ተጠቃሚ ስም (DB_USER) አልተዋቀረም። እባክዎ .env ፋይልዎን ያረጋግጡ።', 500);
}

// DB_PASS ካልተዋቀረ አገልጋዩ ስራውን ማቆም አለበት (Never silently substitute an empty password)
if ($dbPass === false || $dbPass === null) {
    jsonError('የዳታቤዝ ምስክርነት (DB_PASS) አልተዋቀረም! አገልጋዩ በደህንነት ምክንያት ስራውን አቁሟል።', 500);
}

// በምርት (Production) አካባቢ ባዶ የይለፍ ቃል በጥብቅ የተከለከለ ነው
if ($appEnv === 'production' && trim($dbPass) === '') {
    jsonError('በምርት አካባቢ (production) ላይ ባዶ የዳታቤዝ የይለፍ ቃል መጠቀም በጥብቅ የተከለከለ ነው (Empty DB_PASS is forbidden).', 500);
}

$dsn = "mysql:host=$dbHost;dbname=$dbName;charset=$dbCharset";
$options = [
    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES   => false,
];

try {
    $pdo = new PDO($dsn, $dbUser, $dbPass !== false ? $dbPass : '', $options);
} catch (\PDOException $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'ዳታቤዝ መገናኘት አልተቻለም። እባክዎ የአገልጋዩን ዝግጁነት ያረጋግጡ።'
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

// 7. JSON ግብዓት ማንበቢያ
function getJsonInput(): array {
    $raw = file_get_contents('php://input');
    if (empty($raw)) return [];
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

// 8. አስተማማኝ HMAC Signed Token (No fallback)
function createToken(array $payload, int $expirySeconds = 86400 * 7): string {
    global $jwtSecret;
    $payload['exp'] = time() + $expirySeconds;
    $payload['iat'] = time();
    $base64Payload = base64_encode(json_encode($payload, JSON_UNESCAPED_SLASHES));
    $signature = hash_hmac('sha256', $base64Payload, $jwtSecret);
    return $base64Payload . '.' . $signature;
}

function verifyToken(?string $token, ?PDO $pdo = null): ?array {
    global $jwtSecret;
    if (empty($token)) return null;
    $parts = explode('.', $token);
    if (count($parts) !== 2) return null;

    list($base64Payload, $signature) = $parts;
    $expectedSignature = hash_hmac('sha256', $base64Payload, $jwtSecret);
    if (!hash_equals($expectedSignature, $signature)) {
        return null;
    }

    $payload = json_decode(base64_decode($base64Payload), true);
    if (!is_array($payload) || !isset($payload['exp']) || $payload['exp'] < time()) {
        return null; // ጊዜው ያለፈበት ቶከን
    }

    // የተሰረዘ (Revoked / Logged out) መሆኑን መፈተሽ (Fail-Closed)
    if ($pdo !== null) {
        $tokenHash = hash('sha256', $token);
        try {
            $stmt = $pdo->prepare("SELECT id FROM revoked_tokens WHERE token_hash = ? AND expires_at > ? LIMIT 1");
            $stmt->execute([$tokenHash, time()]);
            if ($stmt->fetch()) {
                return null; // ተጠቃሚው ከዚህ ቶከን ወጥቷል (Revoked)
            }
        } catch (\Exception $e) {
            // የዳታቤዝ ችግር ካለ ለደህንነት ሲባል ቶከኑን ውድቅ ማድረግ (Fail-Closed)
            return null;
        }

        // ተጠቃሚው አሁንም በዳታቤዝ ውስጥ ንቁ (active) መሆኑን ማረጋገጥ
        $userId = $payload['user_id'] ?? null;
        if ($userId) {
            try {
                $uStmt = $pdo->prepare("
                    SELECT u.id, u.username, u.department_id, u.full_name, u.role_title, u.status,
                           d.is_super_admin, d.name AS department_name
                    FROM users u
                    LEFT JOIN departments d ON u.department_id = d.id
                    WHERE u.id = ? LIMIT 1
                ");
                $uStmt->execute([$userId]);
                $liveUser = $uStmt->fetch();

                if (!$liveUser || ($liveUser['status'] ?? '') !== 'active') {
                    // ተጠቃሚው ታግዷል፣ ተሰርዟል ወይም ንቁ አይደለም
                    return null;
                }

                // የቅርብ ጊዜውን ፈቃድና ክፍል ከአገልጋዩ ዳታቤዝ ማዘመን (በአሮጌ ቶከን ብቻ አለመተማመን)
                $payload['username'] = $liveUser['username'];
                $payload['department_id'] = $liveUser['department_id'];
                $payload['department_name'] = $liveUser['department_name'];
                $payload['full_name'] = $liveUser['full_name'];
                $payload['role_title'] = $liveUser['role_title'];
                $payload['is_super_admin'] = (bool)($liveUser['is_super_admin'] ?? false);
            } catch (\Exception $e) {
                return null; // Fail-Closed
            }
        }
    }

    return $payload;
}

function revokeToken(PDO $pdo, string $token, ?int $userId = null): void {
    $tokenHash = hash('sha256', $token);
    $parts = explode('.', $token);
    $exp = time() + (86400 * 7);
    if (count($parts) === 2) {
        $payload = json_decode(base64_decode($parts[0]), true);
        if (isset($payload['exp'])) {
            $exp = (int)$payload['exp'];
        }
    }
    try {
        $stmt = $pdo->prepare("INSERT INTO revoked_tokens (token_hash, user_id, revoked_at, expires_at) VALUES (?, ?, NOW(), ?)");
        $stmt->execute([$tokenHash, $userId, $exp]);
    } catch (\Exception $e) {}
}

// 9. የጥያቄን ፈቃድ ማረጋገጫ (Auth Middleware)
function authenticateRequest(): ?array {
    global $pdo;
    $headers = getallheaders();
    $authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    if (empty($authHeader) && isset($_SERVER['HTTP_AUTHORIZATION'])) {
        $authHeader = $_SERVER['HTTP_AUTHORIZATION'];
    }

    if (preg_match('/Bearer\s+(.*)$/i', $authHeader, $matches)) {
        $token = trim($matches[1]);
        return verifyToken($token, $pdo);
    }
    return null;
}

function requireAuth(): array {
    $auth = authenticateRequest();
    if (!$auth) {
        jsonError('ያልተፈቀደ መዳረሻ! እባክዎ ትክክለኛ የፍቃድ ቶከን ይዘው ይግቡ (Unauthorized).', 401);
    }
    return $auth;
}

function requireSuperAdmin(array $auth): void {
    if (empty($auth['is_super_admin'])) {
        jsonError('ይህንን ተግባር ለማከናወን የፅ/ቤት (Super Admin) ፈቃድ ያስፈልጋል (Forbidden).', 403);
    }
}

function requireDepartmentOrAdmin(array $auth, string $targetDeptId): void {
    if (empty($auth['is_super_admin']) && $auth['department_id'] !== $targetDeptId) {
        jsonError('የሌላ ክፍልን መረጃ የማየት ወይም የማሻሻል ፈቃድ የለዎትም (Forbidden).', 403);
    }
}

function requireResourceOwnership(array $auth, string $resourceDeptId, string $resourceType = 'resource'): void {
    if (empty($auth['is_super_admin']) && $auth['department_id'] !== $resourceDeptId) {
        jsonError("የተከለከለ ክንውን! ይህ $resourceType የሚመለከተው ሌላ ክፍልን ነው (Forbidden).", 403);
    }
}

// 9. አስተማማኝ የደንበኛ IP አድራሻ ፈላጊ (Reverse Proxy Aware)
function getClientIp(): string {
    $remoteIp = $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1';
    $trustedProxiesStr = getenv('TRUSTED_PROXIES') ?: '';
    if (!empty($trustedProxiesStr)) {
        $trustedProxies = array_filter(array_map('trim', explode(',', $trustedProxiesStr)));
        if (in_array($remoteIp, $trustedProxies, true)) {
            $forwarded = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? '';
            if (!empty($forwarded)) {
                $ips = array_map('trim', explode(',', $forwarded));
                $client = $ips[0] ?? '';
                if (filter_var($client, FILTER_VALIDATE_IP)) {
                    return $client;
                }
            }
        }
    }
    return $remoteIp;
}

function requireChatRoomMembership(array $auth, string $roomOrChannel): void {
    global $pdo;
    $room = trim($roomOrChannel);

    // 1. በዳታቤዝ ውስጥ ሩሙን መፈለግ (Database-backed Membership Model)
    if ($pdo !== null) {
        try {
            $rStmt = $pdo->prepare("SELECT id, name, type, target_department_id, is_office_only, is_public FROM chat_rooms WHERE id = ? OR name = ? LIMIT 1");
            $rStmt->execute([$room, $room]);
            $dbRoom = $rStmt->fetch();
            if ($dbRoom) {
                if (!empty($dbRoom['is_public'])) {
                    return; // ይፋዊ ሩም
                }
                if (!empty($dbRoom['is_office_only'])) {
                    if (empty($auth['is_super_admin'])) {
                        jsonError('የተከለከለ ክንውን! የፅ/ቤት የውስጥ ውይይትን ማግኘት የሚችሉት የፅ/ቤት አባላት ብቻ ናቸው (Forbidden).', 403);
                    }
                    return;
                }
                if (!empty($dbRoom['target_department_id'])) {
                    if (empty($auth['is_super_admin']) && $auth['department_id'] !== $dbRoom['target_department_id']) {
                        jsonError("የተከለከለ ክንውን! የዚህ ክፍል (" . $dbRoom['target_department_id'] . ") አባል ባለመሆንዎ ውይይቱን ማግኘት አይችሉም (Forbidden).", 403);
                    }
                    return;
                }
            }
        } catch (\Exception $e) {
            error_log("requireChatRoomMembership DB lookup error: " . $e->getMessage());
        }
    }

    // 2. ነባሪ ህጎች (Fallback rules)
    $publicChannels = ['ይፋዊ መመሪያዎች', 'general', 'ጠቅላላ ውይይት', 'public', 'all', 'room_official', 'room_leaders', 'room_docs'];
    if (in_array($room, $publicChannels, true)) {
        return;
    }

    // የፅ/ቤት የግል ቻናል ለፅ/ቤት ብቻ
    if ($room === 'office' || $room === 'ፅ/ቤት' || $room === 'room_office') {
        if (empty($auth['is_super_admin'])) {
            jsonError('የተከለከለ ክንውን! የፅ/ቤት የውስጥ ውይይትን ማግኘት የሚችሉት የፅ/ቤት አባላት ብቻ ናቸው (Forbidden).', 403);
        }
        return;
    }

    // የክፍል ውስጣዊ ቻናሎች (ለምሳሌ dept_education, dept_mezmur)
    if (str_starts_with($room, 'dept_')) {
        $targetDept = substr($room, 5);
        if (empty($auth['is_super_admin']) && $auth['department_id'] !== $targetDept) {
            jsonError("የተከለከለ ክንውን! የዚህ ክፍል ($targetDept) አባል ባለመሆንዎ ውይይቱን ማግኘት አይችሉም (Forbidden).", 403);
        }
        return;
    }

    // ነባሪ ጥበቃ - ስሙ የክፍሉን ስም ካልያዘ እና ፅ/ቤት ካልሆነ መከልከል
    if (empty($auth['is_super_admin']) && !str_contains($room, $auth['department_id'])) {
        jsonError('የተከለከለ ክንውን! ወደዚህ የውይይት ክፍል የመግባት ፈቃድ የለዎትም (Forbidden).', 403);
    }
}

// 10. የመግቢያ Rate Limiting (Brute-Force Protection)
function checkRateLimit(PDO $pdo, string $key, int $maxAttempts = 5, int $decayMinutes = 15): void {
    try {
        $stmt = $pdo->prepare("SELECT attempts, locked_until FROM login_attempts WHERE attempt_key = ?");
        $stmt->execute([$key]);
        $record = $stmt->fetch();

        if ($record) {
            if ($record['locked_until'] && strtotime($record['locked_until']) > time()) {
                $rem = ceil((strtotime($record['locked_until']) - time()) / 60);
                jsonError("ተደጋጋሚ የተሳሳተ ሙከራ ተደርጓል! እባክዎ ከ $rem ደቂቃ በኋላ ደግመው ይሞክሩ (Too Many Requests).", 429);
            }
            if ($record['attempts'] >= $maxAttempts) {
                $lockedUntil = date('Y-m-d H:i:s', time() + ($decayMinutes * 60));
                $pdo->prepare("UPDATE login_attempts SET locked_until = ? WHERE attempt_key = ?")->execute([$lockedUntil, $key]);
                jsonError("የመግቢያ ሙከራ ገደብ አልፏል! ስርዓቱ ለ $decayMinutes ደቂቃ ተቆልፏል።", 429);
            }
        }
    } catch (\Exception $e) {
        error_log("Rate limit DB check error: " . $e->getMessage());
    }
}

function recordFailedLoginAttempt(PDO $pdo, string $key): void {
    try {
        $stmt = $pdo->prepare("
            INSERT INTO login_attempts (attempt_key, attempts, last_attempt)
            VALUES (?, 1, NOW())
            ON DUPLICATE KEY UPDATE attempts = attempts + 1, last_attempt = NOW()
        ");
        $stmt->execute([$key]);
    } catch (\Exception $e) {
        error_log("Record failed login DB error: " . $e->getMessage());
    }
}

function clearRateLimit(PDO $pdo, string $key): void {
    try {
        $pdo->prepare("DELETE FROM login_attempts WHERE attempt_key = ?")->execute([$key]);
    } catch (\Exception $e) {
        error_log("Clear rate limit DB error: " . $e->getMessage());
    }
}

// 11. የስራ ታሪክ መመዝገቢያ ረዳት (Audit Logger)
function logAudit(PDO $pdo, string $action, string $entityType, ?string $entityId, ?int $userId, ?string $deptId, $details = null): void {
    try {
        $ip = getClientIp();
        $detailsJson = $details ? json_encode($details, JSON_UNESCAPED_UNICODE) : null;
        $stmt = $pdo->prepare("INSERT INTO audit_logs (user_id, department_id, action, entity_type, entity_id, details, ip_address) VALUES (?, ?, ?, ?, ?, ?, ?)");
        $stmt->execute([$userId, $deptId, $action, $entityType, $entityId, $detailsJson, $ip]);
    } catch (\Exception $e) {
        error_log("Audit log DB error: " . $e->getMessage());
    }
}
