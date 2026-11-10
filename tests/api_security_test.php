<?php
/**
 * ዓጸደ ትጉሃን - Automated Security & API Access Control Test Suite
 * 
 * ይህ የሙከራ ስክሪፕት በአጸደ ትጉሃን ኤፒአይ ላይ የተተገበሩትን ሁሉንም
 * የደህንነት፣ የማረጋገጫ (Auth)፣ የፈቃድ (RBAC) እና የከመስመር ውጭ ማመሳሰል (Sync)
 * ጥበቃዎች በዝርዝር ፈትሾ ሪፖርት ያቀርባል።
 */

class ApiSecurityTester {
    private string $baseUrl;
    private array $results = [];
    private ?string $adminToken = null;
    private ?string $educationToken = null;
    private ?string $mezmurToken = null;
    private $createdPlanId = 0;
    private $createdReportId = 0;

    public function __construct(string $baseUrl = 'http://127.0.0.1:8000') {
        $this->baseUrl = rtrim($baseUrl, '/');
    }

    private function request(string $method, string $path, ?array $body = null, ?string $token = null, array $extraHeaders = []): array {
        $ch = curl_init($this->baseUrl . $path);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);

        $headers = ['Accept: application/json'];
        if ($token) {
            $headers[] = "Authorization: Bearer $token";
        }
        foreach ($extraHeaders as $k => $v) {
            $headers[] = "$k: $v";
        }

        if ($body !== null) {
            $jsonData = json_encode($body);
            curl_setopt($ch, CURLOPT_POSTFIELDS, $jsonData);
            $headers[] = 'Content-Type: application/json';
        }

        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        $raw = curl_exec($ch);
        $statusCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        $json = json_decode($raw, true);
        return [
            'status' => $statusCode,
            'body' => $json,
            'raw' => $raw
        ];
    }

    private function record(string $testName, bool $passed, string $expected, string $actual, string $details = ''): void {
        $this->results[] = [
            'name' => $testName,
            'passed' => $passed,
            'expected' => $expected,
            'actual' => $actual,
            'details' => $details
        ];
        $mark = $passed ? "\033[32m[PASS]\033[0m" : "\033[31m[FAIL]\033[0m";
        echo sprintf("%-8s %-50s (Expected: %s, Got: %s)\n", $mark, $testName, $expected, $actual);
        if (!$passed && $details) {
            echo "         Details: $details\n";
        }
    }

    public function runAll(): void {
        echo "\n=================================================================\n";
        echo "   ዓጸደ ትጉሃን - የደህንነት እና የፍቃድ አውቶሜትድ ፍተሻ (Security Test Suite)\n";
        echo "=================================================================\n\n";

        $this->testUnauthenticatedAccess();
        $this->testInvalidToken();
        $this->testInvalidLogin();
        $this->testRateLimiting();
        $this->testValidLogin();
        $this->testCrossDepartmentAccess();
        $this->testReportApprovalPermission();
        $this->testChatOfficialNoticePermission();
        $this->testMaliciousFileUpload();
        $this->testSyncSecurityAndIdempotency();
        $this->testLogoutAndTokenRevocation();

        $this->printSummary();
    }

    private function testUnauthenticatedAccess(): void {
        echo "--- 1. ያልተፈቀደ መዳረሻ ፍተሻ (Unauthenticated Endpoints) ---\n";
        $endpoints = [
            '/api/plans.php',
            '/api/reports.php',
            '/api/chat.php',
            '/api/sync.php',
            '/api/notifications.php',
            '/api/documents.php'
        ];

        foreach ($endpoints as $ep) {
            $res = $this->request('GET', $ep);
            $this->record(
                "ያለ Token $ep መጠየቅ",
                $res['status'] === 401,
                "401 Unauthorized",
                (string)$res['status'],
                $res['raw']
            );
        }
    }

    private function testInvalidToken(): void {
        echo "\n--- 2. የተሳሳተ ወይም የተበላሸ ቶከን ፍተሻ (Invalid/Forged Token) ---\n";
        $res = $this->request('GET', '/api/plans.php', null, 'forged.signature.token');
        $this->record(
            "በተበላሸ ቶከን /api/plans.php መጠየቅ",
            $res['status'] === 401,
            "401 Unauthorized",
            (string)$res['status'],
            $res['raw']
        );
    }

    private function testInvalidLogin(): void {
        echo "\n--- 3. የተሳሳተ የይለፍ ቃል ፍተሻ (Invalid Credentials) ---\n";
        $res = $this->request('POST', '/api/auth.php', [
            'username' => 'education',
            'password' => 'WrongPassword123!'
        ]);
        $this->record(
            "በስህተት የይለፍ ቃል መግባት",
            $res['status'] === 401,
            "401 Unauthorized",
            (string)$res['status'],
            $res['raw']
        );
    }

    private function testRateLimiting(): void {
        echo "\n--- 4. የብሩት ፎርስ መከላከያ ፍተሻ (Rate Limiting) ---\n";
        $hitRateLimit = false;
        $attemptStatus = 0;
        
        // 5 ተከታታይ የተሳሳተ ሙከራ በማድረግ 6ኛው ወይም 7ኛው 429 መመለሱን ማረጋገጥ
        for ($i = 1; $i <= 6; $i++) {
            $res = $this->request('POST', '/api/auth.php', [
                'username' => 'fake_attacker_user',
                'password' => 'badpass_' . $i
            ], null, ['X-Forwarded-For' => '192.168.1.199']);
            
            if ($res['status'] === 429) {
                $hitRateLimit = true;
                $attemptStatus = 429;
                break;
            }
            $attemptStatus = $res['status'];
        }

        $this->record(
            "ከተደጋጋሚ የስህተት ሙከራ በኋላ 429 Too Many Requests ማግኘት",
            $hitRateLimit,
            "429 Too Many Requests",
            (string)$attemptStatus,
            "Attempt result: $attemptStatus"
        );
    }

    private function testValidLogin(): void {
        echo "\n--- 5. ትክክለኛ መግቢያ እና የቶከን አሰጣጥ ፍተሻ (Valid Logins) ---\n";
        
        // 1. ትምህርት ክፍል
        $res1 = $this->request('POST', '/api/auth.php', [
            'username' => 'education',
            'password' => 'Atsede@2019Secure!'
        ]);
        $hasToken1 = !empty($res1['body']['data']['token'] ?? null);
        if ($hasToken1) {
            $this->educationToken = $res1['body']['data']['token'];
        }
        $this->record("የትምህርት ክፍል መግባት (education)", $res1['status'] === 200 && $hasToken1, "200 OK + Token", (string)$res1['status']);

        // 2. መዝሙር ክፍል
        $res2 = $this->request('POST', '/api/auth.php', [
            'username' => 'mezmur',
            'password' => 'Atsede@2019Secure!'
        ]);
        $hasToken2 = !empty($res2['body']['data']['token'] ?? null);
        if ($hasToken2) {
            $this->mezmurToken = $res2['body']['data']['token'];
        }
        $this->record("የመዝሙር ክፍል መግባት (mezmur)", $res2['status'] === 200 && $hasToken2, "200 OK + Token", (string)$res2['status']);

        // 3. ፅ/ቤት (Admin)
        $res3 = $this->request('POST', '/api/auth.php', [
            'username' => 'admin',
            'password' => 'Atsede@2019Secure!'
        ]);
        $hasToken3 = !empty($res3['body']['data']['token'] ?? null);
        if ($hasToken3) {
            $this->adminToken = $res3['body']['data']['token'];
        }
        $this->record("የፅ/ቤት አስተዳዳሪ መግባት (admin)", $res3['status'] === 200 && $hasToken3, "200 OK + Token", (string)$res3['status']);
    }

    private function testCrossDepartmentAccess(): void {
        echo "\n--- 6. የክፍሎች ድንበር ጥሰት መከላከል ፍተሻ (Cross-Department RBAC) ---\n";
        
        // 1. የትምህርት ክፍል የራሱን እቅድ ይፈጥራል (201 Created)
        $res1 = $this->request('POST', '/api/plans.php', [
            'title' => 'የ2019 ዓ.ም የትምህርት ጥራት ማሻሻያ ስልጠና',
            'description' => 'ለመምህራን የተዘጋጀ ሳምንታዊ ስልጠና',
            'department_id' => 'education',
            'priority' => 'high',
            'status' => 'pending',
            'start_date' => '2026-11-15',
            'end_date' => '2026-12-30'
        ], $this->educationToken);
        
        $this->createdPlanId = $res1['body']['data']['id'] ?? 0;
        $this->record(
            "የትምህርት ክፍል የራሱን እቅድ መፍጠር",
            $res1['status'] === 201 && $this->createdPlanId > 0,
            "201 Created",
            (string)$res1['status']
        );

        // 2. የትምህርት ክፍል በመዝሙር ክፍል ስም እቅድ ሊፈጥር ሲሞክር (403 Forbidden)
        $res2 = $this->request('POST', '/api/plans.php', [
            'title' => 'ህገወጥ የመዝሙር ጥናት እቅድ',
            'description' => 'ከትምህርት ክፍል የተላከ የሌላ ክፍል እቅድ',
            'department_id' => 'mezmur',
            'priority' => 'medium'
        ], $this->educationToken);

        $this->record(
            "የትምህርት ክፍል በሌላ ክፍል (mezmur) ስም እቅድ ሲፈጥር መከልከሉ",
            $res2['status'] === 403,
            "403 Forbidden",
            (string)$res2['status'],
            $res2['raw']
        );

        // 3. የመዝሙር ክፍል የትምህርት ክፍልን እቅድ ለማሻሻል ሲሞክር (403 Forbidden)
        if ($this->createdPlanId > 0) {
            $res3 = $this->request('PUT', '/api/plans.php', [
                'id' => $this->createdPlanId,
                'title' => 'የተጠለፈ የትምህርት እቅድ በመዝሙር'
            ], $this->mezmurToken);

            $this->record(
                "የመዝሙር ክፍል የትምህርት ክፍልን እቅድ ለማሻሻል ሲሞክር መከልከሉ",
                $res3['status'] === 403,
                "403 Forbidden",
                (string)$res3['status'],
                $res3['raw']
            );
        }

        // 4. የትምህርት ክፍል ተራ ተጠቃሚ እቅድ ለመሰረዝ ሲሞክር (403 Forbidden - Delete is office-only)
        if ($this->createdPlanId > 0) {
            $res4 = $this->request('DELETE', "/api/plans.php?id={$this->createdPlanId}", null, $this->educationToken);
            $this->record(
                "ተራ የክፍል ተጠቃሚ እቅድ ለመሰረዝ ሲሞክር መከልከሉ (Office Only)",
                $res4['status'] === 403,
                "403 Forbidden",
                (string)$res4['status'],
                $res4['raw']
            );
        }
    }

    private function testReportApprovalPermission(): void {
        echo "\n--- 7. የሪፖርት ማፅደቅ ፈቃድ ፍተሻ (Report Review Authorization) ---\n";
        
        // 1. የትምህርት ክፍል ሪፖርት ያቀርባል (201 Created)
        $res1 = $this->request('POST', '/api/reports.php', [
            'title' => 'የጥቅምት ወር የትምህርት ክፍል አፈፃፀም ሪፖርት',
            'summary' => 'ስልጠናዎች በተሳካ ሁኔታ ተጠናቀዋል',
            'plan_id' => $this->createdPlanId > 0 ? $this->createdPlanId : null,
            'report_period' => 'monthly'
        ], $this->educationToken);

        $this->createdReportId = $res1['body']['data']['id'] ?? 0;
        $this->record(
            "የትምህርት ክፍል ሪፖርት ማቅረብ",
            $res1['status'] === 201 && $this->createdReportId > 0,
            "201 Created",
            (string)$res1['status']
        );

        if ($this->createdReportId > 0) {
            // 2. የትምህርት ክፍል የራሱን ወይም የሌላውን ሪፖርት ለማጽደቅ ሲሞክር (403 Forbidden)
            $res2 = $this->request('POST', '/api/reports.php?action=review', [
                'id' => $this->createdReportId,
                'status' => 'approved',
                'review_comments' => 'ራሴን አጽድቄያለሁ'
            ], $this->educationToken);

            $this->record(
                "ተራ የክፍል ተጠቃሚ ሪፖርት ለማጽደቅ ሲሞክር መከልከሉ (403)",
                $res2['status'] === 403,
                "403 Forbidden",
                (string)$res2['status'],
                $res2['raw']
            );

            // 3. የፅ/ቤት ተጠቃሚ (Admin) ሪፖርቱን ሲያጸድቅ (200 OK)
            $res3 = $this->request('POST', '/api/reports.php?action=review', [
                'id' => $this->createdReportId,
                'status' => 'approved',
                'review_comments' => 'በፅ/ቤት የተረጋገጠ እና የጸደቀ'
            ], $this->adminToken);

            $this->record(
                "የፅ/ቤት አስተዳዳሪ ሪፖርትን ማጽደቁ (200 OK)",
                $res3['status'] === 200,
                "200 OK",
                (string)$res3['status'],
                $res3['raw']
            );
        }
    }

    private function testChatOfficialNoticePermission(): void {
        echo "\n--- 8. የቻት ይፋዊ መመሪያ ፈቃድ ፍተሻ (Official Notice Authorization) ---\n";

        // 1. የትምህርት ክፍል ይፋዊ መመሪያ (is_official_notice=1) ሊልክ ሲሞክር (403 Forbidden)
        $res1 = $this->request('POST', '/api/chat.php', [
            'room' => 'general',
            'message' => 'ይህ ህገወጥ ይፋዊ መመሪያ ነው',
            'is_official_notice' => 1
        ], $this->educationToken);

        $this->record(
            "ተራ የክፍል ተጠቃሚ ይፋዊ መመሪያ (Official Notice) ሲልክ መከልከሉ",
            $res1['status'] === 403,
            "403 Forbidden",
            (string)$res1['status'],
            $res1['raw']
        );

        // 2. የፅ/ቤት ተጠቃሚ ይፋዊ መመሪያ ሲልክ (201 Created)
        $res2 = $this->request('POST', '/api/chat.php', [
            'room' => 'general',
            'message' => 'በሰንበት ት/ቤቱ ፅ/ቤት የተላለፈ ይፋዊ መመሪያ',
            'is_official_notice' => 1
        ], $this->adminToken);

        $this->record(
            "የፅ/ቤት አስተዳዳሪ ይፋዊ መመሪያ ማስተላለፉ (201 Created)",
            $res2['status'] === 201,
            "201 Created",
            (string)$res2['status'],
            $res2['raw']
        );
    }

    private function testMaliciousFileUpload(): void {
        echo "\n--- 9. አደገኛ የፋይል ሰቀላ መከላከል ፍተሻ (Malicious Upload Blocked) ---\n";

        // አደገኛ .php ፋይል ሰቀላ ሙከራ
        $cfile = new CURLFile(__FILE__, 'text/php', 'exploit_shell.php');
        
        $ch = curl_init($this->baseUrl . '/api/reports.php?action=upload');
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, ['file' => $cfile]);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            "Authorization: Bearer " . $this->educationToken
        ]);
        $raw = curl_exec($ch);
        $statusCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        $this->record(
            "የ .php አደገኛ ፋይል ሰቀላ መከልከሉ (400 Bad Request)",
            $statusCode === 400,
            "400 Bad Request",
            (string)$statusCode,
            $raw
        );
    }

    private function testSyncSecurityAndIdempotency(): void {
        echo "\n--- 10. የከመስመር ውጭ ማመሳሰል እና የተባዛ መከላከል ፍተሻ (Sync Security & Idempotency) ---\n";

        // 1. ያለ ቶከን ማመሳሰል (401 Unauthorized)
        $res1 = $this->request('POST', '/api/sync.php', ['changes' => []]);
        $this->record("ያለ ቶከን /api/sync.php መጠየቅ", $res1['status'] === 401, "401 Unauthorized", (string)$res1['status']);

        // 2. የሌላ ክፍልን ዳታ በ sync ለማስገባት መሞከር (403 Forbidden)
        $res2 = $this->request('POST', '/api/sync.php', [
            'client_timestamp' => date('c'),
            'changes' => [
                [
                    'sync_id' => 'sync_fake_cross_dept_' . uniqid(),
                    'entity_type' => 'plan',
                    'action' => 'insert',
                    'department_id' => 'mezmur', // የትምህርት ክፍል ሆኖ መዝሙርን ለመንካት መሞከር
                    'data' => ['title' => 'ህገወጥ ማመሳሰል']
                ]
            ]
        ], $this->educationToken);

        $this->record(
            "በ sync ውስጥ የሌላ ክፍል ዳታ ሲላክ መከልከሉ",
            $res2['status'] === 403,
            "403 Forbidden",
            (string)$res2['status'],
            $res2['raw']
        );

        // 3. ትክክለኛ ማመሳሰል እና የተባዛ sync_id መከላከል (Idempotency)
        $syncId = 'sync_edu_valid_' . uniqid();
        $payload = [
            'client_timestamp' => date('c'),
            'changes' => [
                [
                    'sync_id' => $syncId,
                    'entity_type' => 'plan',
                    'action' => 'insert',
                    'department_id' => 'education',
                    'data' => [
                        'title' => 'ከመስመር ውጭ የተመዘገበ እቅድ',
                        'priority' => 'low'
                    ]
                ]
            ]
        ];

        // የመጀመሪያው ጥያቄ
        $res3 = $this->request('POST', '/api/sync.php', $payload, $this->educationToken);
        $firstPassed = ($res3['status'] === 200 && ($res3['body']['data']['summary']['processed'] ?? 0) === 1);

        // ተመሳሳዩን የ sync_id የያዘ ሁለተኛ ጥያቄ (ድግግሞሽ መከላከል)
        $res4 = $this->request('POST', '/api/sync.php', $payload, $this->educationToken);
        $secondPassed = ($res4['status'] === 200 && ($res4['body']['data']['summary']['skipped_duplicates'] ?? 0) === 1);

        $this->record(
            "የማመሳሰል Idempotency እና የተባዛ መከላከል (Duplicate Skipped)",
            $firstPassed && $secondPassed,
            "200 OK (1 inserted, then 1 skipped)",
            "First: {$res3['status']} (processed=" . ($res3['body']['data']['summary']['processed'] ?? 0) . "), Second: {$res4['status']} (skipped=" . ($res4['body']['data']['summary']['skipped_duplicates'] ?? 0) . ")"
        );
    }

    private function testLogoutAndTokenRevocation(): void {
        echo "\n--- 11. ቶከን ማሰናከያ ፍተሻ (Logout & Token Revocation) ---\n";

        // 1. መውጣት (Logout)
        $res1 = $this->request('POST', '/api/auth.php?action=logout', null, $this->mezmurToken);
        $this->record("የመዝሙር ክፍል ሎግአውት ማድረግ", $res1['status'] === 200, "200 OK", (string)$res1['status']);

        // 2. ከተሰናከለ ቶከን በኋላ እንደገና መጠየቅ (401 Unauthorized)
        $res2 = $this->request('GET', '/api/plans.php', null, $this->mezmurToken);
        $this->record(
            "ከተሰናከለ ቶከን (Revoked Token) በኋላ መጠየቅ ሲከለከል (401)",
            $res2['status'] === 401,
            "401 Unauthorized",
            (string)$res2['status'],
            $res2['raw']
        );
    }

    private function printSummary(): void {
        $total = count($this->results);
        $passed = count(array_filter($this->results, fn($r) => $r['passed']));
        $failed = $total - $passed;

        echo "\n=================================================================\n";
        echo "   የሙከራው ማጠቃለያ ውጤት (Test Execution Summary)\n";
        echo "=================================================================\n";
        echo "  አጠቃላይ የተካሄዱ ሙከራዎች: $total\n";
        echo "  ያለፉ (PASSED): \033[32m$passed\033[0m\n";
        echo "  የወደቁ (FAILED): " . ($failed > 0 ? "\033[31m$failed\033[0m" : "\033[32m0\033[0m") . "\n";
        echo "=================================================================\n\n";

        if ($failed > 0) {
            echo "የወደቁ ሙከራዎች ዝርዝር:\n";
            foreach ($this->results as $r) {
                if (!$r['passed']) {
                    echo " - {$r['name']} (Expected: {$r['expected']}, Got: {$r['actual']})\n";
                }
            }
            exit(1);
        } else {
            echo "\033[32mእንኳን ደስ አለዎት! ሁሉም የደህንነት እና የፍቃድ ሙከራዎች 100% አልፈዋል።\033[0m\n";
            exit(0);
        }
    }
}

// ማስኬጃ
$tester = new ApiSecurityTester('http://127.0.0.1:8000');
$tester->runAll();
