<?php
// ============================================================
// የአጸደ ትጉሃን የውስጥ ውይይት ኤፒአይ (Internal Persistent Chat API)
// ቋሚ የ MySQL ማከማቻ፣ የክፍሎች ውይይት፣ አባሪ ፋይሎች እና የንባብ ማረጋገጫ
// ============================================================

require_once __DIR__ . '/config.php';

$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';

// 1. የውይይት ክፍሎችን ወይም መልእክቶችን ማምጣት (GET Messages / Rooms)
if ($method === 'GET') {
    // ክፍሎችን ማምጣት
    if ($action === 'rooms') {
        $stmt = $pdo->query("SELECT * FROM chat_rooms ORDER BY created_at ASC");
        jsonResponse($stmt->fetchAll());
    }

    $channel = $_GET['channel'] ?? $_GET['room_id'] ?? 'ይፋዊ መመሪያዎች';
    $since = $_GET['since'] ?? null; // ለፈጣን አዳዲስ መልእክቶች ብቻ (Incremental polling)
    $limit = isset($_GET['limit']) ? (int)$_GET['limit'] : 100;

    $sql = "
        SELECT m.*, d.name AS department_name, d.short_name AS department_short_name
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

// 2. አዲስ መልእክት መላክ (POST Message)
if ($method === 'POST') {
    $auth = authenticateRequest();
    $input = getJsonInput();

    // የተነበበ ምልክት ማድረግ (Mark messages as read)
    if ($action === 'mark_read') {
        $channel = $input['channel'] ?? '';
        if (!empty($channel)) {
            $stmt = $pdo->prepare("UPDATE chat_messages SET is_read = 1 WHERE channel = ? OR room_id = ?");
            $stmt->execute([$channel, $channel]);
            jsonResponse(['message' => 'መልእክቶቹ እንደተነበቡ ተደርገዋል']);
        }
        jsonError('ቻናል ያስፈልጋል', 400);
    }

    $msgId = $input['id'] ?? ('msg_' . time() . '_' . rand(100, 999));
    $channel = $input['channel'] ?? ($input['room_id'] ?? 'ይፋዊ መመሪያዎች');
    $deptId = $input['department_id'] ?? ($auth['department_id'] ?? 'admin');
    $senderName = $input['sender_name'] ?? ($auth['username'] ?? 'አባል');
    $senderRole = $input['sender_role'] ?? 'የክፍል ተወካይ';
    $message = trim($input['message'] ?? '');
    $isNotice = !empty($input['is_official_notice']) ? 1 : 0;
    $replyToId = $input['reply_to_id'] ?? null;
    $attachmentPath = $input['attachment_path'] ?? null;
    $syncId = $input['sync_id'] ?? ('sync_' . uniqid());

    // አባሪ ፋይል በ Base64 ከመጣ
    if (!empty($input['attachment_base64']) && !empty($input['attachment_name'])) {
        $uploadDir = __DIR__ . '/uploads/';
        if (!is_dir($uploadDir)) mkdir($uploadDir, 0755, true);
        $base64 = $input['attachment_base64'];
        if (str_contains($base64, ',')) $base64 = explode(',', $base64)[1];
        $fileData = base64_decode($base64);
        if ($fileData !== false) {
            $safeFile = 'chat_' . time() . '_' . rand(1000, 9999) . '_' . preg_replace('/[^a-zA-Z0-9_\.-]/', '_', $input['attachment_name']);
            file_put_contents($uploadDir . $safeFile, $fileData);
            $attachmentPath = 'api/uploads/' . $safeFile;
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
            'message' => $message,
            'created_at' => date('Y-m-d H:i:s'),
            'attachment_path' => $attachmentPath
        ]
    ]);
}

jsonError('ያልተፈቀደ ዘዴ', 405);
