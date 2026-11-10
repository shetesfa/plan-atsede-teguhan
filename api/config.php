<?php
// ============================================================
// የአጸደ ትጉሃን አገልጋይ ማእከላዊ ውቅር (Core Configuration & Database)
// ============================================================

// 1. የሰዓት አቆጣጠር ወደ ኢትዮጵያ (Africa/Addis_Ababa) ማስተካከል
date_default_timezone_set('Africa/Addis_Ababa');

// 2. CORS እና የደህንነት ሄደሮች
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, X-Device-ID");
header("Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS");
header("Content-Type: application/json; charset=UTF-8");
header("X-Content-Type-Options: nosniff");
header("X-Frame-Options: SAMEORIGIN");
header("X-XSS-Protection: 1; mode=block");

// የ OPTIONS ጥያቄዎችን በፈጣኑ ማስተናገድ
if (isset($_SERVER['REQUEST_METHOD']) && $_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// 3. የ .env ፋይል ማንበቢያ ረዳት
function loadEnv($filePath) {
    if (!file_exists($filePath)) return;
    $lines = file($filePath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        $line = trim($line);
        if (empty($line) || str_starts_with($line, '#')) continue;
        if (str_contains($line, '=')) {
            list($key, $val) = explode('=', $line, 2);
            $key = trim($key);
            $val = trim($val);
            // ጥቅሶችን ማስወገድ
            $val = trim($val, "\"'");
            if (!getenv($key)) {
                putenv("$key=$val");
                $_ENV[$key] = $val;
            }
        }
    }
}

// .env ፋይልን መጫን
loadEnv(__DIR__ . '/.env');
loadEnv(__DIR__ . '/../.env');

// 4. የዳታቤዝ ምስክርነቶች
$dbHost = getenv('DB_HOST') ?: 'localhost';
$dbName = getenv('DB_NAME') ?: 'atsede_db';
$dbUser = getenv('DB_USER') ?: 'root';
$dbPass = getenv('DB_PASS') !== false ? getenv('DB_PASS') : '';
$dbCharset = getenv('DB_CHARSET') ?: 'utf8mb4';

$dsn = "mysql:host=$dbHost;dbname=$dbName;charset=$dbCharset";
$options = [
    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES   => false,
];

try {
    $pdo = new PDO($dsn, $dbUser, $dbPass, $options);
} catch (\PDOException $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'ዳታቤዝ መገናኘት አልተቻለም። እባክዎ የአገልጋዩን ዝግጁነት ያረጋግጡ።'
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

// 5. ወጥ የሆኑ የ JSON ምላሽ ረዳቶች (Response Helpers)
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

// 6. JSON ግብዓት ማንበቢያ ረዳት
function getJsonInput(): array {
    $raw = file_get_contents('php://input');
    if (empty($raw)) return [];
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

// 7. ቀላል እና ደህንነቱ የተጠበቀ Token ፈጣሪ እና ፈታሽ (HMAC Signed Token)
function createToken(array $payload, int $expirySeconds = 86400 * 30): string {
    $secret = getenv('JWT_SECRET') ?: 'atsede_fallback_secret_key_2019';
    $payload['exp'] = time() + $expirySeconds;
    $base64Payload = base64_encode(json_encode($payload));
    $signature = hash_hmac('sha256', $base64Payload, $secret);
    return $base64Payload . '.' . $signature;
}

function verifyToken(?string $token): ?array {
    if (empty($token)) return null;
    $secret = getenv('JWT_SECRET') ?: 'atsede_fallback_secret_key_2019';
    $parts = explode('.', $token);
    if (count($parts) !== 2) return null;
    
    list($base64Payload, $signature) = $parts;
    $expectedSignature = hash_hmac('sha256', $base64Payload, $secret);
    if (!hash_equals($expectedSignature, $signature)) {
        return null; // የተጭበረበረ ወይም የተለወጠ ቶከን
    }
    
    $payload = json_decode(base64_decode($base64Payload), true);
    if (!is_array($payload) || !isset($payload['exp']) || $payload['exp'] < time()) {
        return null; // ጊዜው ያለፈበት ቶከን
    }
    return $payload;
}

// 8. የጥያቄን ፈቃድ ማረጋገጫ (Auth Middleware)
function authenticateRequest(): ?array {
    $headers = getallheaders();
    $authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    if (empty($authHeader) && isset($_SERVER['HTTP_AUTHORIZATION'])) {
        $authHeader = $_SERVER['HTTP_AUTHORIZATION'];
    }
    
    if (preg_match('/Bearer\s+(.*)$/i', $authHeader, $matches)) {
        $token = trim($matches[1]);
        return verifyToken($token);
    }
    return null;
}

// 9. የስራ ታሪክ መመዝገቢያ ረዳት (Audit Logger)
function logAudit(PDO $pdo, string $action, string $entityType, ?string $entityId, ?int $userId, ?string $deptId, $details = null): void {
    try {
        $ip = $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1';
        $detailsJson = $details ? json_encode($details, JSON_UNESCAPED_UNICODE) : null;
        $stmt = $pdo->prepare("INSERT INTO audit_logs (user_id, department_id, action, entity_type, entity_id, details, ip_address) VALUES (?, ?, ?, ?, ?, ?, ?)");
        $stmt->execute([$userId, $deptId, $action, $entityType, $entityId, $detailsJson, $ip]);
    } catch (\Exception $e) {
        // የኦዲት መዝገብ ዋናውን ስራ እንዳያቋርጥ ስህተቱን በጸጥታ ማለፍ
    }
}
