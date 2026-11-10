<?php
// ============================================================
// የአጸደ ትጉሃን ከመስመር ውጭ ማመሳከሪያ ኤፒአይ (Hardened Sync API)
// የፈቃድ ቁጥጥር፣ ድግግሞሽን መከላከል፣ እና የስሪት ግጭት አፈታት
// ============================================================

require_once __DIR__ . '/config.php';

$auth = requireAuth(); // ማመሳከር የሚችለው የተረጋገጠ ተጠቃሚ ብቻ ነው!
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'POST') {
    $input = getJsonInput();

    $deviceId = htmlspecialchars($input['device_id'] ?? 'device_unknown', ENT_QUOTES, 'UTF-8');
    $changes = $input['changes'] ?? [];

    $results = [
        'processed' => 0,
        'skipped_duplicates' => 0,
        'conflicts' => 0,
        'errors' => []
    ];

    $pdo->beginTransaction();
    try {
        foreach ($changes as $item) {
            $entityType = $item['entity_type'] ?? '';
            $action = $item['action'] ?? 'update';
            $syncId = $item['sync_id'] ?? null;
            $payload = $item['payload'] ?? ($item['data'] ?? []);
            $clientVersion = (int)($item['version'] ?? 1);

            if (empty($syncId)) {
                $results['errors'][] = "ማመሳከሪያ መለያ (sync_id) የሌለው ለውጥ ተዘሏል";
                continue;
            }

            // የክፍል ፈቃድ ማረጋገጫ (Cross-department check)
            $itemDept = $item['department_id'] ?? ($payload['department_id'] ?? null);
            if (!empty($itemDept) && !$auth['is_super_admin'] && $itemDept !== $auth['department_id']) {
                $pdo->rollBack();
                jsonError("የተከለከለ ክንውን! በሌላ ክፍል ($itemDept) ስም መረጃ ማመሳከር አይፈቀድም (Forbidden)", 403);
            }

            // 1. የድግግሞሽ ፍተሻ (Idempotency Key Check)
            $dupStmt = $pdo->prepare("SELECT id, status FROM sync_queue WHERE id = ?");
            $dupStmt->execute([$syncId]);
            $existingQueue = $dupStmt->fetch();

            if ($existingQueue && $existingQueue['status'] === 'processed') {
                $results['skipped_duplicates']++;
                continue;
            }

            // 2. በእቅድ ላይ የተደረገ ለውጥ (Plan Sync)
            if ($entityType === 'plan') {
                $planId = $payload['id'] ?? ('plan_' . time() . '_' . rand(100, 999));

                $checkStmt = $pdo->prepare("SELECT department_id, version, updated_at FROM plans WHERE id = ?");
                $checkStmt->execute([$planId]);
                $serverPlan = $checkStmt->fetch();

                if ($serverPlan) {
                    // የሌላ ክፍልን እቅድ እንዳያሻሽል ማረጋገጥ
                    if (!$auth['is_super_admin'] && $serverPlan['department_id'] !== $auth['department_id']) {
                        $results['errors'][] = "ለእቅድ $planId የክፍል ፈቃድ የለዎትም";
                        continue;
                    }

                    // Optimistic Concurrency ፍተሻ (የሰርቨሩ ስሪት የበለጠ አዲስ ከሆነ ግጭት መመዝገብ)
                    $serverVersion = (int)$serverPlan['version'];
                    if ($serverVersion > $clientVersion) {
                        $results['conflicts']++;
                        $qStmt = $pdo->prepare("
                            INSERT INTO sync_queue (id, device_id, entity_type, action, payload, status, conflict_resolution, processed_at)
                            VALUES (?, ?, 'plan', ?, ?, 'conflict', 'የአገልጋዩ መረጃ የበለጠ አዲስ በመሆኑ አልተተካም', NOW())
                            ON DUPLICATE KEY UPDATE status = 'conflict', processed_at = NOW()
                        ");
                        $qStmt->execute([$syncId, $deviceId, $action, json_encode($payload, JSON_UNESCAPED_UNICODE)]);
                        continue;
                    }

                    if ($action === 'delete') {
                        if ($auth['is_super_admin']) {
                            $pdo->prepare("UPDATE plans SET is_deleted = 1, version = version + 1 WHERE id = ?")->execute([$planId]);
                        }
                    } else {
                        $progress = (int)($payload['progress_percent'] ?? 0);
                        $status = $payload['status'] ?? ($progress >= 100 ? 'completed' : 'in_progress');
                        $pdo->prepare("
                            UPDATE plans SET
                                progress_percent = ?, status = ?, version = version + 1, sync_id = ?
                            WHERE id = ?
                        ")->execute([$progress, $status, $syncId, $planId]);
                    }
                } else {
                    // አዲስ እቅድ መጨመር (Insert new plan)
                    $deptId = $auth['department_id'];
                    $mainTask = $payload['main_task'] ?? ($payload['title'] ?? 'ከመስመር ውጭ የተመዘገበ እቅድ');
                    $pStmt = $pdo->prepare("
                        INSERT INTO plans (
                            id, department_id, main_task, detail_task, progress_percent, status, priority, sync_id
                        ) VALUES (
                            ?, ?, ?, ?, ?, ?, ?, ?
                        )
                    ");
                    $pStmt->execute([
                        $planId, $deptId, $mainTask, $payload['description'] ?? '',
                        (int)($payload['progress_percent'] ?? 0), $payload['status'] ?? 'in_progress',
                        $payload['priority'] ?? 'medium', $syncId
                    ]);
                }
            }

            // 3. በሪፖርት ላይ የተደረገ ለውጥ (Report Sync)
            elseif ($entityType === 'report') {
                $reportId = $payload['id'] ?? null;
                if (!$reportId) continue;

                // የሪፖርት ክፍል ከ Token ብቻ ይወሰዳል
                $deptId = $auth['is_super_admin'] ? ($payload['department_id'] ?? $auth['department_id']) : $auth['department_id'];
                $submittedBy = $auth['full_name'] ?? $auth['username'];

                $rStmt = $pdo->prepare("
                    INSERT INTO reports (
                        id, plan_id, department_id, submitted_by, title, activities_completed,
                        progress_percent, challenges, budget_spent, status, sync_id
                    ) VALUES (
                        ?, ?, ?, ?, ?, ?,
                        ?, ?, ?, ?, ?
                    ) ON DUPLICATE KEY UPDATE
                        activities_completed = VALUES(activities_completed),
                        progress_percent = VALUES(progress_percent),
                        challenges = VALUES(challenges),
                        status = VALUES(status),
                        version = version + 1
                ");
                $rStmt->execute([
                    $reportId,
                    $payload['plan_id'] ?? null,
                    $deptId,
                    $submittedBy,
                    $payload['title'] ?? 'ክንውን ሪፖርት',
                    $payload['activities_completed'] ?? '',
                    (int)($payload['progress_percent'] ?? 0),
                    $payload['challenges'] ?? null,
                    (float)($payload['budget_spent'] ?? 0),
                    'submitted',
                    $syncId
                ]);
            }

            // 4. በቻት መልእክት ላይ የተደረገ ለውጥ (Chat Sync)
            elseif ($entityType === 'chat') {
                $msgId = $payload['id'] ?? null;
                if (!$msgId) continue;

                $cStmt = $pdo->prepare("
                    INSERT INTO chat_messages (
                        id, room_id, channel, department_id, sender_name, sender_role, message, sync_id
                    ) VALUES (
                        ?, ?, ?, ?, ?, ?, ?, ?
                    ) ON DUPLICATE KEY UPDATE message = VALUES(message)
                ");
                $cStmt->execute([
                    $msgId,
                    $payload['channel'] ?? 'ይፋዊ መመሪያዎች',
                    $payload['channel'] ?? 'ይፋዊ መመሪያዎች',
                    $auth['department_id'],
                    $auth['full_name'] ?? $auth['username'],
                    $auth['role_title'] ?? 'የክፍል ተወካይ',
                    $payload['message'] ?? '',
                    $syncId
                ]);
            }

            // የወረፋ ሁኔታን ማዘመን
            $qStmt = $pdo->prepare("
                INSERT INTO sync_queue (id, device_id, entity_type, action, payload, status, processed_at)
                VALUES (?, ?, ?, ?, ?, 'processed', NOW())
                ON DUPLICATE KEY UPDATE status = 'processed', processed_at = NOW()
            ");
            $qStmt->execute([$syncId, $deviceId, $entityType, $action, json_encode($payload, JSON_UNESCAPED_UNICODE)]);
            $results['processed']++;
        }

        $pdo->commit();

        jsonResponse([
            'message' => 'የማመሳከር ሂደት ተጠናቋል',
            'summary' => $results,
            'server_time' => date('Y-m-d H:i:s')
        ]);
    } catch (\Exception $e) {
        $pdo->rollBack();
        jsonError('ማመሳከር አልተቻለም፡ ' . $e->getMessage(), 500);
    }
}

jsonError('ያልተፈቀደ ዘዴ', 405);
