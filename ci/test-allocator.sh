#!/bin/bash
set -euo pipefail
# Build/test only. No probe extension is included in any published RPM.
yum -y --setopt=localpkg_gpgcheck=0 localinstall /src/dist/rpms/php71w-common-*.rpm /src/dist/rpms/php71w-cli-*.rpm /src/dist/rpms/php71w-devel-*.rpm
gcc -shared -fPIC $(php-config --includes) /src/ci/allocator-probe.c -o /tmp/allocator-probe.so
rm -f /tmp/allocator-shutdown
set +e
timeout 15 php -n -d extension=/tmp/allocator-probe.so -r '
register_shutdown_function(function() { file_put_contents("/tmp/allocator-shutdown", "ran"); });
audit_huge_allocation();' >/tmp/allocator.stdout 2>/tmp/allocator.stderr
status=$?
set -e
[[ $status -eq 1 ]]
grep -q 'Possible integer overflow in huge memory allocation' /tmp/allocator.stderr
[[ ! -e /tmp/allocator-shutdown ]]
echo 'PASS: SIZE_MAX huge allocation exits safely without shutdown callbacks'
set +e
USE_ZEND_ALLOC=0 timeout 15 php -n -d extension=/tmp/allocator-probe.so -r '
register_shutdown_function(function() { file_put_contents("/tmp/allocator-shutdown", "ran"); });
audit_huge_allocation();' >/tmp/system-allocator.stdout 2>/tmp/system-allocator.stderr
status=$?
set -e
[[ $status -eq 1 ]]
grep -q 'Out of memory' /tmp/system-allocator.stderr
[[ ! -e /tmp/allocator-shutdown ]]
echo 'PASS: system allocator OOM exits safely without shutdown callbacks'
# Regeneration must reproduce the checked-in VM, including every specialized
# concat handler. Use a scratch copy so the checkout remains unchanged.
mkdir -p /tmp/vm-regeneration
cp /src/Zend/zend_vm_{gen.php,def.h,execute.skl} /tmp/vm-regeneration/
php -n /tmp/vm-regeneration/zend_vm_gen.php
diff -u -B /src/Zend/zend_vm_execute.h /tmp/vm-regeneration/zend_vm_execute.h
echo 'PASS: generated VM matches zend_vm_def.h (ignoring original release blank lines)'
# Reuse the upstream regressions for the string/array paths touched here.
mkdir -p /tmp/php71-upstream-tests
cp /src/run-tests.php /tmp/php71-upstream-tests/run-tests.php
cp /src/Zend/tests/concat_*.phpt /src/Zend/tests/parse_str_with_unpack.phpt /src/Zend/tests/this_in_parse_str.phpt /tmp/php71-upstream-tests/
cp /src/ext/standard/tests/strings/{parse_str*,str_repeat*,str_split*}.phpt /tmp/php71-upstream-tests/
NO_INTERACTION=1 REPORT_EXIT_STATUS=1 TEST_PHP_EXECUTABLE=/usr/bin/php \
    php -n /tmp/php71-upstream-tests/run-tests.php -n -q --show-diff /tmp/php71-upstream-tests
