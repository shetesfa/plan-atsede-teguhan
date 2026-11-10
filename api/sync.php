<?php
// ============================================================
// የአጸደ ትጉሃን ከመስመር ውጭ ማመሳከሪያ ኤፒአይ (Offline Sync Engine API)
// ድግግሞሽን መከላከል (Idempotency)፣ ስሪት ክትትል እና ግጭት አፈታት
// ============================================================

require_once __DIR__ . '/config.php';

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'POST') {
    $auth = authenticateRequest();
    $input = getJsonInput();

    $deviceId = $input['device_id'] ?? 'device_unknown';
    $changes = $input['changes'] ?? []; // የለውጦች ወረፋ
    $lastSyncTime = $input['last_sync_time'] ?? null;

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
            $action = $item['action'] ?? 'create'; // create, update, delete
            $syncId = $item['sync_id'] ?? null;
            $payload = $item['payload'] ?? [];

            if (empty($syncId)) {
                $results['errors'][] = "ማመሳከሪያ መለያ (sync_id) የሌለው ለውጥ ተገኝቷል";
                continue;
            }

            // ድግግሞሽን መፈተሽ (Idempotency check via sync_queue)
            $dupStmt = $pdo->prepare("SELECT id, status FROM sync_queue WHERE id = ?");
            $dupStmt->execute([$syncId]);
            $existingQueue = $dupStmt->fetch();

            if ($existingQueue && $existingQueue['status'] === 'processed') {
                $results['skipped_duplicates']++;
                continue; // ቀድሞ የተሰራ ለውጥ ነው፣ በድጋሚ አንሰራም!
            }

            // 1. በእቅድ ላይ የተደረገ ለውጥ (Plan sync)
            if ($entityType === 'plan') {
                $planId = $payload['id'] ?? ('plan_' . uniqid());
                if ($action === 'delete') {
                    $pdo->prepare("UPDATE plans SET is_deleted = 1, version = version + 1 WHERE id = ?")->execute([$planId]);
                } else {
                    $pStmt = $pdo->prepare("
                        INSERT INTO plans (
                            id, department_id, sub_department, main_task, detail_task,
                            measurement, quantity, execution_time, target_date, budget,
                            remarks, progress_percent, status, priority, assigned_to, sync_id
                        ) VALUES (
                            ?, ?, ?, ?, ?,
                            ?, ?, ?, ?, ?,
                            ?, ?, ?, ?, ?, ?
                        ) ON DUPLICATE KEY UPDATE
                            main_task = VALUES(main_task),
                            detail_task = VALUES(detail_task),
                            progress_percent = VALUES(progress_percent),
                            status = VALUES(status),
                            remarks = VALUES(remarks),
                            version = version + 1
                    ");
                    $pStmt->execute([
                        $planId,
                        $payload['department_id'] ?? 'education',
                        $payload['sub_department'] ?? null,
                        $payload['main_task'] ?? ($payload['title'] ?? 'እቅድ'),
                        $payload['detail_task'] ?? ($payload['description'] ?? ''),
                        $payload['measurement'] ?? null,
                        $payload['quantity'] ?? null,
                        $payload['execution_time'] ?? null,
                        $payload['target_date'] ?? null,
                        $payload['budget'] ?? null,
                        $payload['remarks'] ?? null,
                        (int)($payload['progress_percent'] ?? 0),
                        $payload['status'] ?? 'in_progress',
                        $payload['priority'] ?? 'medium',
                        $payload['assigned_to'] ?? null,
                        $syncId
                    ]);
                }
            }

            // 2. በሪፖርት ላይ የተደረገ ለውጥ (Report sync)
            elseif ($entityType === 'report') {
                $reportId = $payload['id'] ?? ('rep_' . uniqid());
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
                    $payload['department_id'] ?? 'education',
                    $payload['submitted_by'] ?? 'አባል',
                    $payload['title'] ?? 'ክንውን ሪፖርት',
                    $payload['activities_completed'] ?? '',
                    (int)($payload['progress_percent'] ?? 0),
                    $payload['challenges'] ?? null,
                    (float)($payload['budget_spent'] ?? 0),
                    $payload['status'] ?? 'submitted',
                    $syncId
                ]);
            }

            // 3. በቻት መልእክት ላይ የተደረገ ለውጥ (Chat sync)
            elseif ($entityType === 'chat') {
                $msgId = $payload['id'] ?? ('msg_' . uniqid());
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
                    $payload['department_id'] ?? 'admin',
                    $payload['sender_name'] ?? 'አባል',
                    $payload['sender_role'] ?? 'ተወካይ',
                    $payload['message'] ?? '',
                    $syncId
                ]);
            }

            // የወረፋውን ሁኔታ መመዝገብ
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
            'message' => 'የማመሳከር ሂደት በተሳካ ሁኔታ ተጠናቋል',
            'summary' => $results,
            'server_time' => date('Y-m-d H:i:s')
        ]);
    } catch (\Exception $e) {
        $pdo->rollBack();
        jsonError('ማመሳከር አልተቻለም፡ ' . $e->getMessage(), 500);
    }
}

jsonError('ያልተፈቀደ ዘዴ', 405);
