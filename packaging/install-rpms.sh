#!/bin/bash
# Run the installer from a published Release. No PHP compilation on the host.
set -euo pipefail
TAG='@RELEASE_TAG@'
ASSET=php71w-centos7.9-x86_64-rpms.tar.gz
LOCAL_PACKAGE=
CHECKSUMS=
FRESH=0
RESTART=0
BACKUP=
TRANSACTION_STARTED=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag) TAG=${2:?Missing tag}; shift 2 ;;
        --package) LOCAL_PACKAGE=${2:?Missing package}; shift 2 ;;
        --checksums) CHECKSUMS=${2:?Missing checksums}; shift 2 ;;
        --fresh) FRESH=1; shift ;;
        --restart-services) RESTART=1; shift ;;
        --help) echo 'Usage: bash install-php71.sh [--restart-services] [--tag TAG] [--package FILE --checksums FILE] [--fresh]'; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done
[[ $EUID -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }
[[ $(uname -m) == x86_64 ]] || { echo 'Only x86_64 is supported' >&2; exit 1; }
grep -q 'CentOS.*7\.9' /etc/centos-release || { echo 'Requires CentOS 7.9' >&2; exit 1; }
[[ "$TAG" =~ ^v7\.1\.33-cve[0-9]+-r[0-9]+$ ]] || { echo 'Invalid or unsubstituted release tag' >&2; exit 1; }
TMP=$(mktemp -d /tmp/php71w-install.XXXXXXXX)
cleanup() {
    status=$?
    if [[ $status -ne 0 && $TRANSACTION_STARTED -eq 1 ]]; then
        echo "FAILED after the RPM transaction started. Packages may already be upgraded; no automatic binary rollback. Backup: $BACKUP" >&2
    fi
    rm -rf -- "$TMP"
    exit "$status"
}
trap cleanup EXIT
if [[ -n "$LOCAL_PACKAGE" ]]; then
    cp -- "$LOCAL_PACKAGE" "$TMP/$ASSET"
    cp -- "${CHECKSUMS:?--checksums is required with --package}" "$TMP/SHA256SUMS"
else
    URL="https://github.com/sunnyfancore/php7.1-patch/releases/download/$TAG"
    curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$URL/$ASSET" -o "$TMP/$ASSET"
    curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$URL/SHA256SUMS" -o "$TMP/SHA256SUMS"
fi
EXPECTED=$(awk -v name="$ASSET" '$2 == name {print $1}' "$TMP/SHA256SUMS")
[[ "$EXPECTED" =~ ^[a-f0-9]{64}$ ]] || { echo 'Missing bundle checksum' >&2; exit 1; }
printf '%s  %s\n' "$EXPECTED" "$TMP/$ASSET" | sha256sum -c -
tar -xzf "$TMP/$ASSET" -C "$TMP"
read -r EXPECTED_VERSION EXPECTED_PATCH EXPECTED_BUILD < <(python - "$TMP/BUILDINFO.json" "$TAG" <<'PY'
import json, sys
with open(sys.argv[1]) as handle: data = json.load(handle)
if data['release_tag'] != sys.argv[2]: raise SystemExit('Bundle release tag mismatch')
print(data['version'], data['patch_id'], data['source_commit'])
PY
)
[[ "$EXPECTED_BUILD" =~ ^[a-f0-9]{40}$ ]] || { echo 'Invalid build metadata' >&2; exit 1; }

declare -A AVAILABLE
for file in "$TMP"/rpms/*.rpm; do
    read -r name arch < <(rpm -qp --qf '%{NAME} %{ARCH}\n' "$file")
    [[ "$arch" == x86_64 && -z "${AVAILABLE[$name]:-}" ]] || { echo "Unsupported/duplicate RPM: $file" >&2; exit 1; }
    AVAILABLE["$name"]=$file
done
SELECTED=()
NAMES=()
while read -r name arch; do
    if [[ -n "${AVAILABLE[$name]:-}" ]]; then
        [[ "$arch" == x86_64 ]] || { echo "Unsupported installed architecture: $name.$arch; no multilib upgrade performed" >&2; exit 1; }
        SELECTED+=("${AVAILABLE[$name]}")
        NAMES+=("$name")
    fi
done < <(rpm -qa --qf '%{NAME} %{ARCH}\n' | sort -u)
if [[ ${#SELECTED[@]} -eq 0 ]]; then
    [[ $FRESH -eq 1 ]] || { echo 'No supported Webtatic php71w packages installed. Use --fresh only for a new installation.' >&2; exit 1; }
    NAMES=(php71w-common php71w-cli php71w-fpm)
    SELECTED=("${AVAILABLE[php71w-common]}" "${AVAILABLE[php71w-cli]}" "${AVAILABLE[php71w-fpm]}")
fi
# Keep the installed SAPI/extension selection. No permanent CLI dependency.
BACKUP="/var/backups/php71w-cve-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$BACKUP/config"
rpm -qa | sort > "$BACKUP/packages-before.txt"
# Includes Apache and extension config paths, preserving their directory tree.
for file in /etc/php.ini /etc/php.d /etc/php-fpm.conf /etc/php-fpm.d /etc/php-zts.d /etc/httpd/conf.d/php.conf /etc/httpd/conf.modules.d/10-php.conf /etc/sysconfig/php-fpm; do
    [[ ! -e "$file" ]] || cp -a --parents -- "$file" "$BACKUP/config/"
done
FPM_ACTIVE=0
HTTPD_ACTIVE=0
if [[ -d /run/systemd/system ]]; then
    if rpm -q php71w-fpm >/dev/null 2>&1 && systemctl is-active --quiet php-fpm; then FPM_ACTIVE=1; fi
    if rpm -q mod_php71w >/dev/null 2>&1 && systemctl is-active --quiet httpd; then HTTPD_ACTIVE=1; fi
fi
printf 'php-fpm=%s\nhttpd=%s\n' "$FPM_ACTIVE" "$HTTPD_ACTIVE" > "$BACKUP/services-before.txt"
if [[ $FPM_ACTIVE -eq 1 ]]; then /usr/sbin/php-fpm -t; fi
if [[ $HTTPD_ACTIVE -eq 1 ]]; then httpd -t; fi

MODULE_BIN=
if rpm -q php71w-cli >/dev/null 2>&1; then MODULE_BIN=/usr/bin/php
elif rpm -q php71w-fpm >/dev/null 2>&1; then MODULE_BIN=/usr/sbin/php-fpm
fi
capture_modules() {
    local target=$1
    "$MODULE_BIN" -d display_errors=stderr -d log_errors=0 -m > "$target" 2> "$target.stderr"
    if [[ -s "$target.stderr" ]]; then cat "$target.stderr" >&2; echo 'PHP startup diagnostics must be resolved before reporting success' >&2; return 1; fi
    LC_ALL=C sort -u -o "$target" "$target"
}
if [[ -n "$MODULE_BIN" ]]; then capture_modules "$BACKUP/modules-before.txt"; fi
rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' "${SELECTED[@]}"
echo "Configuration backup: $BACKUP"

# Temporary dependency repositories; release RPMs are checksum-verified above.
mkdir "$TMP/repos"
for entry in 'base os' 'updates updates' 'extras extras'; do
    read -r repo subdir <<< "$entry"
    cat >> "$TMP/repos/dependencies.repo" <<REPO
[php71-$repo]
name=CentOS 7.9 $repo archive
baseurl=https://vault.centos.org/7.9.2009/$subdir/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
REPO
done
cat >> "$TMP/repos/dependencies.repo" <<REPO
[php71-epel]
name=EPEL 7 archive
baseurl=https://archives.fedoraproject.org/pub/archive/epel/7/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file://$TMP/RPM-GPG-KEY-EPEL-7
REPO
YUM=(yum -y --setopt="reposdir=$TMP/repos" --setopt=localpkg_gpgcheck=0)
"${YUM[@]}" --setopt=tsflags=test localinstall "${SELECTED[@]}"
TRANSACTION_STARTED=1
"${YUM[@]}" localinstall "${SELECTED[@]}"
# YUM may return success for a no-op with a newer/different installed build.
for file in "${SELECTED[@]}"; do
    name=$(rpm -qp --qf '%{NAME}' "$file")
    expected=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$file")
    actual=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$name.x86_64")
    [[ "$actual" == "$expected" ]] || { echo "RPM version mismatch: expected $expected, got $actual" >&2; exit 1; }
done
mkdir -p /usr/local/share/php71w-cve
cp "$TMP/verify-patch.php" "$TMP/BUILDINFO.json" /usr/local/share/php71w-cve/
if rpm -q php71w-cli >/dev/null 2>&1; then
    PHP71_EXPECTED_BUILD="$EXPECTED_BUILD" /usr/bin/php -n /usr/local/share/php71w-cve/verify-patch.php
fi
if rpm -q php71w-fpm >/dev/null 2>&1; then
    /usr/sbin/php-fpm -n -i > "$TMP/fpm-info"
    for value in "$EXPECTED_VERSION" "$EXPECTED_PATCH" "$EXPECTED_BUILD"; do
        grep -Fq -- "$value" "$TMP/fpm-info" || { echo "FPM build identity mismatch: $value" >&2; exit 1; }
    done
    /usr/sbin/php-fpm -t
    echo "PASS FPM binary identity: $EXPECTED_VERSION ($EXPECTED_BUILD)"
fi
if rpm -q mod_php71w >/dev/null 2>&1; then
    httpd -t
    echo 'Apache module configuration checked; verify patch constants in the website process as documented.'
fi
if [[ -n "$MODULE_BIN" ]]; then
    capture_modules "$BACKUP/modules-after.txt"
    LC_ALL=C comm -23 "$BACKUP/modules-before.txt" "$BACKUP/modules-after.txt" > "$BACKUP/modules-missing.txt"
    [[ ! -s "$BACKUP/modules-missing.txt" ]] || { cat "$BACKUP/modules-missing.txt" >&2; echo 'Previously loaded PHP modules are missing' >&2; exit 1; }
fi
if [[ $RESTART -eq 1 ]]; then
    # Use the pre-transaction state, even if an old RPM scriptlet stopped FPM.
    if [[ $FPM_ACTIVE -eq 1 ]]; then systemctl restart php-fpm; systemctl is-active --quiet php-fpm; fi
    if [[ $HTTPD_ACTIVE -eq 1 ]]; then systemctl restart httpd; systemctl is-active --quiet httpd; fi
else
    echo 'Installer restart skipped. Older RPM upgrade scriptlets may still restart FPM; arrange a maintenance window.'
fi
echo 'Installed RPM versions:'
rpm -q "${NAMES[@]}"
echo "PASS installed package set. Metadata: /usr/local/share/php71w-cve/BUILDINFO.json"
echo 'Restart other long-running PHP workers and verify constants through the website/FPM process.'
