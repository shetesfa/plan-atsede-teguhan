<?php
// ============================================================
// የአጸደ ትጉሃን ደህንነቱ የተጠበቀ የፋይል ማውረጃ ኤንድፖይንት (Authenticated File Handler)
// ============================================================

require_once __DIR__ . '/config.php';

// 1. የማረጋገጫ ቶከን መፈተሽ (ከ Authorization Header ብቻ — Query Parameters በደህንነት ምክንያት ተከልክለዋል)
$auth = null;
$headers = getallheaders();
$authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? '';
if (empty($authHeader) && isset($_SERVER['HTTP_AUTHORIZATION'])) {
    $authHeader = $_SERVER['HTTP_AUTHORIZATION'];
}

if (preg_match('/Bearer\s+(.*)$/i', $authHeader, $matches)) {
    $token = trim($matches[1]);
    $auth = verifyToken($token, $pdo);
}

if (!$auth) {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'message' => 'ያልተፈቀደ መዳረሻ! እባክዎ በ Authorization Header ትክክለኛ የፍቃድ ቶከን ያቅርቡ (Unauthorized).'], JSON_UNESCAPED_UNICODE);
    exit;
}

$id = trim($_GET['id'] ?? '');
$action = $_GET['action'] ?? 'download'; // download or preview
$type = $_GET['type'] ?? '';

if (empty($id)) {
    jsonError('የፋይል ወይም የአባሪ መለያ (id) ያስፈልጋል', 400);
}

$filePath = null;
$fileName = null;
$fileType = null;
$fileDept = null;

$isChatAttachment = false;

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
}

// 2. በይፋዊ ሰነዶች ውስጥ መፈለግ
if (!$filePath) {
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

// 3. በቻት መልእክቶች ውስጥ መፈለግ
if (!$filePath) {
    $cStmt = $pdo->prepare("SELECT id, room_id, channel, department_id, attachment_path FROM chat_messages WHERE id = ? LIMIT 1");
    $cStmt->execute([$id]);
    $chatMsg = $cStmt->fetch();
    if ($chatMsg && !empty($chatMsg['attachment_path'])) {
        // የሩም አባልነት ፈቃድ በግድ መረጋገጥ አለበት
        requireChatRoomMembership($auth, $chatMsg['channel'] ?: $chatMsg['room_id']);
        $filePath = $chatMsg['attachment_path'];
        $fileName = basename($filePath);
        $fileDept = $chatMsg['department_id'];
        $isChatAttachment = true;
    }
}

if (!$filePath) {
    jsonError('ፋይሉ አልተገኘም ወይም ተሰርዟል', 404);
}

// 4. የክፍል ባለቤትነት ፈቃድ ማረጋገጥ (RBAC Protection)
if (!$isChatAttachment && !$auth['is_super_admin'] && $fileDept !== $auth['department_id'] && $fileDept !== 'all') {
    jsonError('የተከለከለ ክንውን! የሌላ ክፍልን የግል ፋይል የማውረድ ፈቃድ የለዎትም (Forbidden).', 403);
}

// 5. ጥብቅ Path Traversal እና Canonical Directory Boundary ጥበቃ
$realBaseDir = realpath(__DIR__ . '/uploads');
if (!$realBaseDir || !is_dir($realBaseDir)) {
    jsonError('የሰቀላ ማውጫው አልተገኘም', 500);
}
// የማውጫውን ወሰን በ DIRECTORY_SEPARATOR መዝጋት (boundary bypass መከላከል)
$canonicalBaseDir = rtrim($realBaseDir, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;

$rawTarget = __DIR__ . '/../' . ltrim($filePath, '/\\');
$targetFullPath = realpath($rawTarget);

// ፋይሉ በ canonicalBaseDir ስር መሆኑን፣ መኖሩን እና symlink አለመሆኑን ማረጋገጥ
if (!$targetFullPath || !str_starts_with($targetFullPath, $canonicalBaseDir) || !file_exists($targetFullPath) || is_link($targetFullPath)) {
    // ቀጥታ በ uploads ስር በፋይሉ ስም መፈለግ
    $directRaw = $canonicalBaseDir . basename($filePath);
    $directPath = realpath($directRaw);
    if ($directPath && str_starts_with($directPath, $canonicalBaseDir) && file_exists($directPath) && !is_link($directPath)) {
        $targetFullPath = $directPath;
    } else {
        jsonError('የተጠየቀው ፋይል በዲስክ ላይ አልተገኘም', 404);
    }
}

// የፋይሉን እውነተኛ MIME አይነት በይዘቱ መፈተሽ (MIME by content)
if (function_exists('finfo_open')) {
    $finfo = finfo_open(FILEINFO_MIME_TYPE);
    $realMime = finfo_file($finfo, $targetFullPath);
    finfo_close($finfo);
    if ($realMime) {
        $fileType = $realMime;
    }
}

// 6. ደህንነቱ የተጠበቀ የፋይል ማውረጃ ራስጌዎች
$disposition = ($action === 'preview' && (str_starts_with((string)$fileType, 'image/') || $fileType === 'application/pdf')) ? 'inline' : 'attachment';
$cleanFileName = preg_replace('/[^a-zA-Z0-9_\-\.\x{1200}-\x{137F}]/u', '_', $fileName ?: basename($targetFullPath));

header("Content-Type: " . ($fileType ?: 'application/octet-stream'));
header("Content-Disposition: $disposition; filename=\"$cleanFileName\"");
header("Content-Length: " . filesize($targetFullPath));
header("X-Content-Type-Options: nosniff");
header("Cache-Control: private, no-transform, no-store, must-revalidate");
header("Pragma: no-cache");

// ኦዲት ሎግ መያዝ (ያለ ቶከን እና ያለ ሚስጥራዊ መረጃ)
logAudit($pdo, 'download_file', 'attachments', $id, $auth['user_id'], $fileDept);

readfile($targetFullPath);
exit;
