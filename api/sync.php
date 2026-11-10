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

    $allowedEntities = ['plan', 'report', 'chat'];
    $allowedActions = ['insert', 'update', 'delete'];

    $pdo->beginTransaction();
    try {
        foreach ($changes as $item) {
            $entityType = trim($item['entity_type'] ?? '');
            $action = trim($item['action'] ?? 'update');
            $syncId = $item['sync_id'] ?? null;
            $payload = $item['payload'] ?? ($item['data'] ?? []);
            $clientVersion = (int)($item['version'] ?? 1);

            if (empty($syncId)) {
                $results['errors'][] = "ማመሳከሪያ መለያ (sync_id) የሌለው ለውጥ ተዘሏል";
                continue;
            }

            // entity_type እና action በግልጽ በ allowlist መፈተሽ
            if (!in_array($entityType, $allowedEntities, true)) {
                $results['errors'][] = "ያልተፈቀደ የዳታ አይነት ($entityType) ተዘሏል";
                continue;
            }
            if (!in_array($action, $allowedActions, true)) {
                $results['errors'][] = "ያልተፈቀደ ክንውን ($action) ተዘሏል";
                continue;
            }

            // የክፍል ፈቃድ ማረጋገጫ (Cross-department check)
            $itemDept = $item['department_id'] ?? ($payload['department_id'] ?? null);
            if (!empty($itemDept) && !$auth['is_super_admin'] && $itemDept !== $auth['department_id']) {
                $pdo->rollBack();
                jsonError("የተከለከለ ክንውን! በሌላ ክፍል ($itemDept) ስም መረጃ ማመሳከር አይፈቀድም (Forbidden)", 403);
            }

            // 1. የድግግሞሽ እና የ Idempotency ቁልፍ ጥበቃ (User Scoped Idempotency & Conflict Check)
            $payloadJson = json_encode($payload, JSON_UNESCAPED_UNICODE);
            $currentPayloadHash = hash('sha256', $payloadJson);

            $dupStmt = $pdo->prepare("SELECT id, user_id, payload_hash, status FROM sync_queue WHERE id = ?");
            $dupStmt->execute([$syncId]);
            $existingQueue = $dupStmt->fetch();

            if ($existingQueue) {
                // ሀ. የሌላ ተጠቃሚን sync_id መጠቀም መከልከል (Idempotency Key Hijack Prevention)
                if (!empty($existingQueue['user_id']) && (int)$existingQueue['user_id'] !== (int)$auth['user_id']) {
                    $pdo->rollBack();
                    jsonError("የተከለከለ ክንውን! ይህ ማመሳከሪያ መለያ ($syncId) በሌላ ተጠቃሚ የተመዘገበ ነው (Forbidden).", 403);
                }

                // ለ. ተመሳሳይ sync_id ከተለየ ይዘት ጋር ሲላክ ግጭት መጣል (Repeated ID with different payload)
                if (!empty($existingQueue['payload_hash']) && $existingQueue['payload_hash'] !== $currentPayloadHash) {
                    $pdo->rollBack();
                    jsonError("የስሪት ግጭት (Idempotency Conflict)! ይህ sync_id ቀደም ሲል ከተለየ ይዘት ጋር ጥቅም ላይ ውሏል (Conflict).", 409);
                }

                // ሐ. ተመሳሳይ ጥያቄ ተደግሞ ሲመጣ እና አስቀድሞ ከተሰራ መዝለል
                if ($existingQueue['status'] === 'processed') {
                    $results['skipped_duplicates']++;
                    continue;
                }
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
                        $pdo->rollBack();
                        jsonError("የተከለከለ ክንውን! ለእቅድ $planId የክፍል ፈቃድ የለዎትም (Forbidden).", 403);
                    }

                    // Optimistic Concurrency ፍተሻ (የሰርቨሩ ስሪት የበለጠ አዲስ ከሆነ ግጭት መመዝገብ)
                    $serverVersion = (int)$serverPlan['version'];
                    if ($serverVersion > $clientVersion) {
                        $results['conflicts']++;
                        $qStmt = $pdo->prepare("
                            INSERT INTO sync_queue (id, device_id, user_id, entity_type, action, payload, payload_hash, status, conflict_resolution, processed_at)
                            VALUES (?, ?, ?, 'plan', ?, ?, ?, 'conflict', 'የአገልጋዩ መረጃ የበለጠ አዲስ በመሆኑ አልተተካም', NOW())
                            ON DUPLICATE KEY UPDATE status = 'conflict', processed_at = NOW(), payload_hash = VALUES(payload_hash)
                        ");
                        $qStmt->execute([$syncId, $deviceId, $auth['user_id'], $action, $payloadJson, $currentPayloadHash]);
                        continue;
                    }

                    if ($action === 'delete') {
                        if ($auth['is_super_admin']) {
                            $pdo->prepare("UPDATE plans SET is_deleted = 1, version = version + 1 WHERE id = ?")->execute([$planId]);
                        } else {
                            $pdo->rollBack();
                            jsonError("እቅድ የመሰረዝ ፈቃድ የለዎትም (Office Only).", 403);
                        }
                    } else {
                        $progress = max(0, min(100, (int)($payload['progress_percent'] ?? 0)));
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
                        max(0, min(100, (int)($payload['progress_percent'] ?? 0))), $payload['status'] ?? 'in_progress',
                        $payload['priority'] ?? 'medium', $syncId
                    ]);
                }
            }

            // 3. በሪፖርት ላይ የተደረገ ለውጥ (Report Sync - Hardened IDOR & Immutability)
            elseif ($entityType === 'report') {
                $reportId = $payload['id'] ?? null;
                if (!$reportId) continue;

                // ነባር ሪፖርት መኖሩን አስቀድሞ መፈተሽ
                $rCheck = $pdo->prepare("SELECT department_id, status, plan_id FROM reports WHERE id = ?");
                $rCheck->execute([$reportId]);
                $existingReport = $rCheck->fetch();

                if ($existingReport) {
                    // 1. የሌላ ክፍልን ሪፖርት እንዳይተካ ማረጋገጥ (Cross-Department IDOR Prevention)
                    if (!$auth['is_super_admin'] && $existingReport['department_id'] !== $auth['department_id']) {
                        $pdo->rollBack();
                        jsonError("የተከለከለ ክንውን! ለሪፖርት $reportId የክፍል ፈቃድ የለዎትም (Forbidden).", 403);
                    }

                    // 2. በፅ/ቤት የጸደቀ ሪፖርት ላይ ተራ ክፍል ማሻሻያ ማድረግ አይችልም!
                    if ($existingReport['status'] === 'approved' && !$auth['is_super_admin']) {
                        $pdo->rollBack();
                        jsonError("የተከለከለ ክንውን! በፅ/ቤት የጸደቀ ሪፖርት ($reportId) ላይ ማሻሻያ ማድረግ አይቻልም (Forbidden).", 403);
                    }
                }

                // የተገናኘው plan_id የዚያው ክፍል መሆኑን ማረጋገጥ
                $targetPlanId = $payload['plan_id'] ?? ($existingReport['plan_id'] ?? null);
                if ($targetPlanId) {
                    $pCheck = $pdo->prepare("SELECT department_id FROM plans WHERE id = ?");
                    $pCheck->execute([$targetPlanId]);
                    $linkedPlan = $pCheck->fetch();
                    if ($linkedPlan && !$auth['is_super_admin'] && $linkedPlan['department_id'] !== $auth['department_id']) {
                        $pdo->rollBack();
                        jsonError("የተከለከለ ክንውን! ሪፖርቱ የተያያዘበት እቅድ ($targetPlanId) የሌላ ክፍል ነው (Forbidden).", 403);
                    }
                }

                // የሪፖርት ክፍል ከ Token ብቻ ይወሰዳል
                $deptId = $auth['is_super_admin'] ? ($payload['department_id'] ?? $auth['department_id']) : $auth['department_id'];
                $submittedBy = $auth['full_name'] ?? $auth['username'];

                if ($existingReport) {
                    $rStmt = $pdo->prepare("
                        UPDATE reports SET
                            title = ?, activities_completed = ?, progress_percent = ?, challenges = ?,
                            budget_spent = ?, status = COALESCE(?, status), sync_id = ?, version = version + 1
                        WHERE id = ?
                    ");
                    $rStmt->execute([
                        $payload['title'] ?? 'ክንውን ሪፖርት',
                        $payload['activities_completed'] ?? ($payload['summary'] ?? ''),
                        max(0, min(100, (int)($payload['progress_percent'] ?? 0))),
                        $payload['challenges'] ?? null,
                        (float)($payload['budget_spent'] ?? 0),
                        $payload['status'] ?? null,
                        $syncId,
                        $reportId
                    ]);
                } else {
                    $rStmt = $pdo->prepare("
                        INSERT INTO reports (
                            id, plan_id, department_id, submitted_by, title, activities_completed,
                            progress_percent, challenges, budget_spent, status, sync_id
                        ) VALUES (
                            ?, ?, ?, ?, ?, ?,
                            ?, ?, ?, ?, ?
                        )
                    ");
                    $rStmt->execute([
                        $reportId,
                        $targetPlanId,
                        $deptId,
                        $submittedBy,
                        $payload['title'] ?? 'ክንውን ሪፖርት',
                        $payload['activities_completed'] ?? ($payload['summary'] ?? ''),
                        max(0, min(100, (int)($payload['progress_percent'] ?? 0))),
                        $payload['challenges'] ?? null,
                        (float)($payload['budget_spent'] ?? 0),
                        'submitted',
                        $syncId
                    ]);
                }
            }

            // 4. በቻት መልእክት ላይ የተደረገ ለውጥ (Chat Sync - Room Membership & IDOR)
            elseif ($entityType === 'chat') {
                $msgId = $payload['id'] ?? null;
                if (!$msgId) continue;

                $channel = trim($payload['channel'] ?? ($payload['room_id'] ?? 'ይፋዊ መመሪያዎች'));

                // 1. የሩም አባልነት ፈቃድ በግድ መረጋገጥ አለበት
                requireChatRoomMembership($auth, $channel);

                // 2. ነባር መልእክት ከሆነ የሌላ ክፍልን እንዳይቀይር ማረጋገጥ
                $mCheck = $pdo->prepare("SELECT department_id, sender_name FROM chat_messages WHERE id = ?");
                $mCheck->execute([$msgId]);
                $existingMsg = $mCheck->fetch();

                if ($existingMsg) {
                    if (!$auth['is_super_admin'] && $existingMsg['department_id'] !== $auth['department_id']) {
                        $pdo->rollBack();
                        jsonError("የተከለከለ ክንውን! የሌላ ክፍልን የውይይት መልእክት ($msgId) መቀየር አይፈቀድም (Forbidden).", 403);
                    }
                    $cStmt = $pdo->prepare("UPDATE chat_messages SET message = ?, sync_id = ? WHERE id = ?");
                    $cStmt->execute([$payload['message'] ?? '', $syncId, $msgId]);
                } else {
                    $cStmt = $pdo->prepare("
                        INSERT INTO chat_messages (
                            id, room_id, channel, department_id, sender_name, sender_role, message, sync_id
                        ) VALUES (
                            ?, ?, ?, ?, ?, ?, ?, ?
                        )
                    ");
                    $cStmt->execute([
                        $msgId,
                        $channel,
                        $channel,
                        $auth['department_id'],
                        $auth['full_name'] ?? $auth['username'],
                        $auth['role_title'] ?? 'የክፍል ተወካይ',
                        $payload['message'] ?? '',
                        $syncId
                    ]);
                }
            }

            // የወረፋ ሁኔታን ማዘመን (User, Device እና Payload Hash ጭምር መመዝገብ)
            $qStmt = $pdo->prepare("
                INSERT INTO sync_queue (id, device_id, user_id, entity_type, action, payload, payload_hash, status, processed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, 'processed', NOW())
                ON DUPLICATE KEY UPDATE status = 'processed', processed_at = NOW(), payload_hash = VALUES(payload_hash)
            ");
            $qStmt->execute([$syncId, $deviceId, $auth['user_id'], $entityType, $action, $payloadJson, $currentPayloadHash]);
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
