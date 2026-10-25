#!/bin/bash
set -euo pipefail
mode=${1:?fpm or apache}
bash /src/ci/setup-centos7.sh --runtime
if [[ "$mode" == fpm ]]; then package=php71w-fpm; else package=mod_php71w; fi
yum -y --setopt=localpkg_gpgcheck=0 localinstall /src/baseline/rpms/php71w-common-*.rpm /src/baseline/rpms/"$package"-*.rpm
! rpm -q php71w-cli
test ! -e /usr/bin/php
echo '; preserve SAPI-only upgrade configuration' >> /etc/php.ini
sha256sum /etc/php.ini > /tmp/php-ini-before
bash /src/dist/install-php71.sh --restart-services --package /src/dist/php71w-centos7.9-x86_64-rpms.tar.gz --checksums /src/dist/SHA256SUMS
sha256sum -c /tmp/php-ini-before
! rpm -q php71w-cli
test ! -e /usr/bin/php
echo "PASS: r1 to r2 $mode-only upgrade, no CLI dependency and configuration retained"
if [[ "$mode" == fpm ]]; then
    echo 'extension=ci_nonexistent_extension.so' > /etc/php.d/zz-ci-invalid.ini
    if bash /src/dist/install-php71.sh --package /src/dist/php71w-centos7.9-x86_64-rpms.tar.gz --checksums /src/dist/SHA256SUMS; then
        echo 'Broken extension incorrectly accepted' >&2; exit 1
    fi
    rm /etc/php.d/zz-ci-invalid.ini
    echo 'PASS: extension startup diagnostics are rejected'
    # Test service bookkeeping against a deterministic systemctl double; the
    # actual FPM process and requests below use the real binary.
    mkdir -p /tmp/service-bin /run/systemd/system
    cat > /tmp/service-bin/systemctl <<'MOCK'
#!/bin/bash
set -euo pipefail
echo "$*" >> /tmp/service-calls
if [[ $1 == restart && ${FAIL_RESTART:-0} == 1 ]]; then exit 1; fi
exit 0
MOCK
    chmod +x /tmp/service-bin/systemctl
    PATH="/tmp/service-bin:$PATH" bash /src/dist/install-php71.sh --restart-services --package /src/dist/php71w-centos7.9-x86_64-rpms.tar.gz --checksums /src/dist/SHA256SUMS
    grep -q '^restart php-fpm$' /tmp/service-calls
    if FAIL_RESTART=1 PATH="/tmp/service-bin:$PATH" bash /src/dist/install-php71.sh --restart-services --package /src/dist/php71w-centos7.9-x86_64-rpms.tar.gz --checksums /src/dist/SHA256SUMS; then
        echo 'Restart failure incorrectly reported as success' >&2; exit 1
    fi
    rmdir /run/systemd/system
    echo 'PASS: pre-transaction active service is restarted; restart failure returns nonzero'
    exec /usr/sbin/php-fpm -F -y /src/ci/fpm-test.conf
fi
sed -i 's/^Listen 80$/Listen 9072/' /etc/httpd/conf/httpd.conf
cat > /etc/httpd/conf.d/cve-test.conf <<'HTTPD'
ServerName localhost
StartServers 1
ServerLimit 1
MinSpareServers 1
MaxSpareServers 1
MaxRequestWorkers 1
MaxConnectionsPerChild 0
php_admin_value max_multipart_body_parts 2
php_admin_flag session.upload_progress.enabled on
php_admin_flag session.upload_progress.cleanup off
php_admin_value session.save_path /tmp
<Files startup-fixture.php>
    php_admin_value memory_limit 8M
    php_admin_value post_max_size 32M
</Files>
<Files ini-fixture.php>
    php_value date.timezone CI/Invalid
</Files>
HTTPD
cp /src/ci/fpm-fixture.php /var/www/html/fpm-fixture.php
cp /src/ci/fpm-fixture.php /var/www/html/startup-fixture.php
cp /src/ci/fpm-fixture.php /var/www/html/ini-fixture.php
httpd -t
exec /usr/sbin/httpd -DFOREGROUND
