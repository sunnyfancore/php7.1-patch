#!/bin/bash
set -euo pipefail
php -n /src/ci/verify-patch.php
php /src/ci/verify-patch.php
php -v
php -i | grep 'CVE Patch'
rpm -qf /usr/bin/php
! ldd /usr/bin/php | grep 'not found'
MARKER=$(mktemp /tmp/php71-shutdown.XXXXXXXX)
rm -f "$MARKER"
set +e
timeout 15 php -n -d memory_limit=8M -r '
register_shutdown_function(function() use ($argv) { file_put_contents($argv[1], "ran"); });
$a=[]; while (true) {$a[]=str_repeat("x", 1024);}
' "$MARKER" >/tmp/oom.stdout 2>/tmp/oom.stderr
STATUS=$?
set -e
[[ $STATUS -eq 1 ]]
grep -q 'Allowed memory size' /tmp/oom.stderr
[[ ! -e "$MARKER" ]]
php-fpm -t
echo 'PASS: CLI, build identity, dynamic linking, OOM, FPM configuration'
