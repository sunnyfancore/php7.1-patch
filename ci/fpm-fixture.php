<?php
header('Content-Type: application/json');
if (isset($_GET['handlers'])) {
    ini_set('display_errors', '0');
    class AuditHandler {
        function __invoke() { return false; }
        function __destruct() { trigger_error('CI fatal handler cleanup', E_USER_ERROR); }
    }
    for ($i = 0; $i < 3; $i++) {
        set_error_handler(new AuditHandler());
        set_exception_handler(new AuditHandler());
    }
}
if (isset($_GET['oom'])) {
    ini_set('memory_limit', '8M');
    $items = []; while (true) { $items[] = str_repeat('x', 1024); }
}
session_start();
echo json_encode([
    'pid'=>getmypid(), 'version'=>PHP_VERSION,
    'patch'=>defined('PHP_CVE_PATCH_ID') ? PHP_CVE_PATCH_ID : null,
    'build'=>defined('PHP_CVE_PATCH_BUILD') ? PHP_CVE_PATCH_BUILD : null,
    'keys'=>array_keys($_POST), 'post'=>$_POST,
    'progress'=>isset($_SESSION['upload_progress_probe']),
    'file'=>isset($_FILES['upload']) && $_FILES['upload']['error'] === 0,
    'auth'=>isset($_SERVER['PHP_AUTH_USER']) ? $_SERVER['PHP_AUTH_USER'] : null
]);
