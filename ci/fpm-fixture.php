<?php
header('Content-Type: application/json');
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
