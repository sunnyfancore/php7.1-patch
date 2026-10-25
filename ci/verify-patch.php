<?php
// Run using the upgraded CLI; the constants can also be checked through FPM.
function fail_check($message) { fwrite(STDERR, "FAIL: ".$message."\n"); exit(1); }
if (!defined('PHP_CVE_PATCH_ID') || PHP_CVE_PATCH_ID !== 'CVE-2026-109618+CVE-2026-109619;r2') fail_check('patch ID missing');
if (!defined('PHP_CVE_PATCH_BUILD') || !preg_match('/^[a-f0-9]{40}$/D', PHP_CVE_PATCH_BUILD)) fail_check('build commit missing');
if (getenv('PHP71_EXPECTED_BUILD') && PHP_CVE_PATCH_BUILD !== getenv('PHP71_EXPECTED_BUILD')) fail_check('unexpected source commit');
if (PHP_VERSION !== '7.1.33-cve20261025-r2') fail_check('unexpected build version');
if (ini_get('max_multipart_body_parts') === false) fail_check('multipart mitigation INI missing');
parse_str('a[b][c]=1&a[b][d]=2&x[]=3', $result);
if ($result !== ['a'=>['b'=>['c'=>'1','d'=>'2']], 'x'=>['3']]) fail_check('nested variable regression');
$pairs = [];
for ($i = 0; $i < 300; $i++) $pairs[] = 'rows[k'.$i.'][value]='.$i;
parse_str(implode('&', $pairs), $result);
if (count($result['rows']) !== 300 || $result['rows']['k299']['value'] !== '299') fail_check('small hash table growth regression');
$x = str_repeat('x',16); $y = str_repeat('y',16);
if (($x.$y) !== 'xxxxxxxxxxxxxxxxyyyyyyyyyyyyyyyy') fail_check('concatenation regression');
echo 'PASS '.PHP_VERSION."\n".PHP_CVE_PATCH_ID."\nsource=".PHP_CVE_PATCH_BUILD."\n";
