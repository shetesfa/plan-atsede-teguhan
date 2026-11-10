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
} else {
    // ከሞባይል መተግበሪያ ወይም ቀጥታ ከአገልጋይ የሚመጣ ጥያቄ (Empty origin)
    header("Access-Control-Allow-Origin: " . ($allowedOrigins[0] ?? 'http://127.0.0.1'));
}

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
$dbHost = getenv('DB_HOST') ?: '127.0.0.1';
$dbName = getenv('DB_NAME') ?: 'atsede_db';
$dbUser = getenv('DB_USER');
$dbPass = getenv('DB_PASS');
$dbCharset = getenv('DB_CHARSET') ?: 'utf8mb4';

if ($dbUser === false || $dbUser === null) {
    jsonError('የዳታቤዝ ምስክርነት (DB_USER) አልተዋቀረም። እባክዎ .env ፋይልዎን ያረጋግጡ።', 500);
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

    // የተሰረዘ (Revoked / Logged out) መሆኑን መፈተሽ
    if ($pdo !== null) {
        $tokenHash = hash('sha256', $token);
        try {
            $stmt = $pdo->prepare("SELECT id FROM revoked_tokens WHERE token_hash = ? AND expires_at > ? LIMIT 1");
            $stmt->execute([$tokenHash, time()]);
            if ($stmt->fetch()) {
                return null; // ተጠቃሚው ከዚህ ቶከን ወጥቷል (Revoked)
            }
        } catch (\Exception $e) {}
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
    } catch (\Exception $e) {}
}

function recordFailedLoginAttempt(PDO $pdo, string $key): void {
    try {
        $stmt = $pdo->prepare("
            INSERT INTO login_attempts (attempt_key, attempts, last_attempt)
            VALUES (?, 1, NOW())
            ON DUPLICATE KEY UPDATE attempts = attempts + 1, last_attempt = NOW()
        ");
        $stmt->execute([$key]);
    } catch (\Exception $e) {}
}

function clearRateLimit(PDO $pdo, string $key): void {
    try {
        $pdo->prepare("DELETE FROM login_attempts WHERE attempt_key = ?")->execute([$key]);
    } catch (\Exception $e) {}
}

// 11. የስራ ታሪክ መመዝገቢያ ረዳት (Audit Logger)
function logAudit(PDO $pdo, string $action, string $entityType, ?string $entityId, ?int $userId, ?string $deptId, $details = null): void {
    try {
        $ip = $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1';
        $detailsJson = $details ? json_encode($details, JSON_UNESCAPED_UNICODE) : null;
        $stmt = $pdo->prepare("INSERT INTO audit_logs (user_id, department_id, action, entity_type, entity_id, details, ip_address) VALUES (?, ?, ?, ?, ?, ?, ?)");
        $stmt->execute([$userId, $deptId, $action, $entityType, $entityId, $detailsJson, $ip]);
    } catch (\Exception $e) {}
}
