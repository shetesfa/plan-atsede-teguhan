<?php
// ============================================================
// የአጸደ ትጉሃን ደህንነቱ የተጠበቀ የፋይል ማውረጃ ኤንድፖይንት (Authenticated File Handler)
// ============================================================

require_once __DIR__ . '/config.php';

// 1. የማረጋገጫ ቶከን መፈተሽ (ከ Header ወይም ከ Query Parameter)
$auth = null;
$token = null;

$headers = getallheaders();
$authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? '';
if (empty($authHeader) && isset($_SERVER['HTTP_AUTHORIZATION'])) {
    $authHeader = $_SERVER['HTTP_AUTHORIZATION'];
}

if (preg_match('/Bearer\s+(.*)$/i', $authHeader, $matches)) {
    $token = trim($matches[1]);
} elseif (!empty($_GET['token'])) {
    $token = trim($_GET['token']);
}

if ($token) {
    $auth = verifyToken($token, $pdo);
}

if (!$auth) {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'message' => 'ያልተፈቀደ መዳረሻ! እባክዎ ትክክለኛ የፍቃድ ቶከን ያቅርቡ (Unauthorized).'], JSON_UNESCAPED_UNICODE);
    exit;
}

$id = trim($_GET['id'] ?? '');
$action = $_GET['action'] ?? 'download'; // download or preview

if (empty($id)) {
    jsonError('የፋይል ወይም የአባሪ መለያ (id) ያስፈልጋል', 400);
}

$filePath = null;
$fileName = null;
$fileType = null;
$fileDept = null;

// 1. በሪፖርት አባሪዎች ውስጥ መፈለግ
$stmt = $pdo->prepare("
    SELECT a.file_name, a.file_path, a.file_type, r.department_id
    FROM report_attachments a
    JOIN reports r ON a.report_id = r.id
    WHERE a.id = ? LIMIT 1
");
$stmt->execute([$id]);
$att = $stmt->fetch();

if ($att) {
    $filePath = $att['file_path'];
    $fileName = $att['file_name'];
    $fileType = $att['file_type'];
    $fileDept = $att['department_id'];
} else {
    // 2. በይፋዊ ሰነዶች ውስጥ መፈለግ
    $dStmt = $pdo->prepare("SELECT id, title, department_id, pdf_file_path FROM documents WHERE id = ? LIMIT 1");
    $dStmt->execute([$id]);
    $doc = $dStmt->fetch();
    if ($doc && !empty($doc['pdf_file_path'])) {
        $filePath = $doc['pdf_file_path'];
        $fileName = $doc['title'] . '.pdf';
        $fileType = 'application/pdf';
        $fileDept = $doc['department_id'];
    }
}

if (!$filePath) {
    jsonError('ፋይሉ አልተገኘም ወይም ተሰርዟል', 404);
}

// 3. የክፍል ባለቤትነት ፈቃድ ማረጋገጥ (RBAC Protection)
if (!$auth['is_super_admin'] && $fileDept !== $auth['department_id']) {
    jsonError('የተከለከለ ክንውን! የሌላ ክፍልን የግል ፋይል የማውረድ ፈቃድ የለዎትም (Forbidden).', 403);
}

// 4. Path Traversal ጥበቃ
$baseUploadDir = realpath(__DIR__ . '/uploads');
$targetFullPath = realpath(__DIR__ . '/../' . ltrim($filePath, '/\\'));
if (!$targetFullPath || !str_starts_with($targetFullPath, $baseUploadDir) || !file_exists($targetFullPath)) {
    // የቀጥታ የ uploads ፋይል ከሆነ መፈተሽ
    $directPath = realpath(__DIR__ . '/uploads/' . basename($filePath));
    if ($directPath && str_starts_with($directPath, $baseUploadDir) && file_exists($directPath)) {
        $targetFullPath = $directPath;
    } else {
        jsonError('የተጠየቀው ፋይል በዲስክ ላይ አልተገኘም', 404);
    }
}

// 5. ደህንነቱ የተጠበቀ የፋይል ማውረጃ ራስጌዎች
$disposition = ($action === 'preview' && (str_starts_with($fileType, 'image/') || $fileType === 'application/pdf')) ? 'inline' : 'attachment';
$cleanFileName = preg_replace('/[^a-zA-Z0-9_\-\.\x{1200}-\x{137F}]/u', '_', $fileName ?: basename($targetFullPath));

header("Content-Type: " . ($fileType ?: 'application/octet-stream'));
header("Content-Disposition: $disposition; filename=\"$cleanFileName\"");
header("Content-Length: " . filesize($targetFullPath));
header("X-Content-Type-Options: nosniff");
header("Cache-Control: private, no-transform, no-store, must-revalidate");
header("Pragma: no-cache");

logAudit($pdo, 'download_file', 'attachments', $id, $auth['user_id'], $fileDept);

readfile($targetFullPath);
exit;
