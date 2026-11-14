<?php
// Trivial health endpoint for the PHP API -- no auth, no secrets, no DB.
// Used to verify the API is up after deploy (42web or Render Docker):
//   GET https://<host>/api/health.php  ->  {"status":"ok","service":"plan-atsede-php-api"}
header('Content-Type: application/json; charset=UTF-8');
echo json_encode(['status' => 'ok', 'service' => 'plan-atsede-php-api'], JSON_UNESCAPED_UNICODE);
