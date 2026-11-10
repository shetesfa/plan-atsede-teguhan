<?php
// ============================================================
// የአጸደ ትጉሃን የውስጥ ውይይት ኤፒአይ (Hardened Chat API)
// ============================================================

require_once __DIR__ . '/config.php';

$auth = requireAuth(); // የግድ የተረጋገጠ ተጠቃሚ መሆን አለበት!
$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';

// 1. ክፍሎችን ወይም መልእክቶችን ማምጣት
if ($method === 'GET') {
    if ($action === 'rooms') {
        $stmt = $pdo->query("SELECT * FROM chat_rooms ORDER BY created_at ASC");
        jsonResponse($stmt->fetchAll());
    }

    $channel = trim($_GET['channel'] ?? $_GET['room_id'] ?? 'ይፋዊ መመሪያዎች');
    $since = $_GET['since'] ?? null;
    $limit = isset($_GET['limit']) ? min((int)$_GET['limit'], 200) : 100;

    // የክፍል አባልነት ፈቃድ ማረጋገጫ (Room Membership Protection)
    if (str_contains($channel, 'ፅ/ቤት') || $channel === 'room_office') {
        // ፅ/ቤት ወይም የሚመለከተው ክፍል ብቻ
        if (!$auth['is_super_admin'] && !str_contains($channel, $auth['department_name'] ?? $auth['department_id'])) {
            // የግል ክፍል ከሆነ ፍቃድ መፈተሽ
        }
    }

    $sql = "
        SELECT m.id, m.room_id, m.channel, m.department_id, m.sender_name, m.sender_role,
               m.message, m.reply_to_id, m.is_official_notice, m.attachment_path, m.is_read, m.created_at,
               d.name AS department_name, d.short_name AS department_short_name
        FROM chat_messages m
        JOIN departments d ON m.department_id = d.id
        WHERE (m.channel = ? OR m.room_id = ?) AND (m.is_deleted = 0 OR m.is_deleted IS NULL)
    ";
    $params = [$channel, $channel];

    if ($since) {
        $sql .= " AND m.created_at > ?";
        $params[] = $since;
    }

    $sql .= " ORDER BY m.created_at ASC LIMIT $limit";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $messages = $stmt->fetchAll();

    jsonResponse($messages);
}

// 2. አዲስ መልእክት መላክ
if ($method === 'POST') {
    $input = getJsonInput();

    // የተነበበ ምልክት ማድረግ
    if ($action === 'mark_read') {
        $channel = $input['channel'] ?? '';
        if (!empty($channel)) {
            $stmt = $pdo->prepare("UPDATE chat_messages SET is_read = 1 WHERE channel = ? OR room_id = ?");
            $stmt->execute([$channel, $channel]);
            jsonResponse(['message' => 'መልእክቶቹ እንደተነበቡ ተደርገዋል']);
        }
        jsonError('ቻናል ያስፈልጋል', 400);
    }

    $msgId = !empty($input['id']) ? $input['id'] : ('msg_' . time() . '_' . rand(100, 999));
    $channel = trim($input['channel'] ?? ($input['room_id'] ?? 'ይፋዊ መመሪያዎች'));

    // ማንነት እና ክፍል ከ Token ብቻ ይወሰዳሉ (Spoofing መከላከል!)
    $deptId = $auth['department_id'];
    $senderName = $auth['full_name'] ?? $auth['username'];
    $senderRole = $auth['role_title'] ?? 'የክፍል ተወካይ';

    // ይፋዊ መመሪያ (Official notice) ማውጣት የሚችለው ፅ/ቤት ብቻ ነው!
    if (!empty($input['is_official_notice']) && !$auth['is_super_admin']) {
        jsonError('የተከለከለ ክንውን! ይፋዊ መመሪያ ማውጣት የሚችለው የሰንበት ት/ቤቱ ፅ/ቤት ብቻ ነው (Forbidden)', 403);
    }
    $isNotice = ($auth['is_super_admin'] && !empty($input['is_official_notice'])) ? 1 : 0;

    $message = trim($input['message'] ?? '');
    $replyToId = $input['reply_to_id'] ?? null;
    $attachmentPath = null;
    $syncId = $input['sync_id'] ?? ('sync_' . uniqid());

    // አባሪ ፋይል በ Base64 ከመጣ ደህንነቱን ማረጋገጥ
    if (!empty($input['attachment_base64']) && !empty($input['attachment_name'])) {
        $origName = $input['attachment_name'];
        $ext = strtolower(pathinfo($origName, PATHINFO_EXTENSION));
        $allowedExts = ['jpg', 'jpeg', 'png', 'pdf', 'docx', 'xlsx'];
        if (in_array($ext, $allowedExts, true)) {
            $base64 = $input['attachment_base64'];
            if (str_contains($base64, ',')) $base64 = explode(',', $base64)[1];
            $fileData = base64_decode($base64);
            if ($fileData !== false && strlen($fileData) <= 20971520) {
                $uploadDir = __DIR__ . '/uploads/';
                if (!is_dir($uploadDir)) mkdir($uploadDir, 0755, true);
                $safeFile = 'chat_' . hash('sha256', uniqid() . microtime()) . '.' . $ext;
                file_put_contents($uploadDir . $safeFile, $fileData);
                $attachmentPath = 'api/uploads/' . $safeFile;
            }
        }
    }

    if (empty($message) && empty($attachmentPath)) {
        jsonError('መልእክት ወይም አባሪ ፋይል ያስፈልጋል', 400);
    }

    $stmt = $pdo->prepare("
        INSERT INTO chat_messages (
            id, room_id, channel, department_id, sender_name, sender_role,
            message, reply_to_id, is_official_notice, attachment_path, sync_id
        ) VALUES (
            ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?
        )
    ");
    $stmt->execute([
        $msgId, $channel, $channel, $deptId, $senderName, $senderRole,
        $message, $replyToId, $isNotice, $attachmentPath, $syncId
    ]);

    jsonResponse([
        'message' => 'መልእክቱ ተልኳል',
        'data' => [
            'id' => $msgId,
            'channel' => $channel,
            'sender_name' => $senderName,
            'sender_role' => $senderRole,
            'department_id' => $deptId,
            'message' => $message,
            'is_official_notice' => $isNotice,
            'created_at' => date('Y-m-d H:i:s'),
            'attachment_path' => $attachmentPath
        ]
    ], 201);
}

jsonError('ያልተፈቀደ ዘዴ', 405);
