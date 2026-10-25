#!/bin/bash
# Run the installer from a published Release. No PHP compilation on the host.
set -euo pipefail
TAG='@RELEASE_TAG@'
ASSET=php71w-centos7.9-x86_64-rpms.tar.gz
LOCAL_PACKAGE=
CHECKSUMS=
FRESH=0
RESTART=0
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
trap 'rm -rf -- "$TMP"' EXIT
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

declare -A AVAILABLE
for file in "$TMP"/rpms/*.rpm; do
    name=$(rpm -qp --qf '%{NAME}' "$file")
    AVAILABLE["$name"]=$file
done
SELECTED=()
while IFS= read -r name; do
    [[ -n "${AVAILABLE[$name]:-}" ]] && SELECTED+=("${AVAILABLE[$name]}")
done < <(rpm -qa --qf '%{NAME}\n' | sort -u)
if [[ ${#SELECTED[@]} -eq 0 ]]; then
    [[ $FRESH -eq 1 ]] || { echo 'No supported Webtatic php71w packages installed. Use --fresh only for a new installation.' >&2; exit 1; }
    SELECTED=("${AVAILABLE[php71w-common]}" "${AVAILABLE[php71w-cli]}" "${AVAILABLE[php71w-fpm]}")
fi
# Every selected installed package is upgraded together, so exact-version
# php71w-common dependencies remain consistent. Third-party PECL packages stay.
BACKUP="/var/backups/php71w-cve-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$BACKUP/config"
rpm -qa | sort > "$BACKUP/packages-before.txt"
for file in /etc/php.ini /etc/php.d /etc/php-fpm.conf /etc/php-fpm.d /etc/php-zts.d; do
    [[ ! -e "$file" ]] || cp -a -- "$file" "$BACKUP/config/"
done
if command -v php >/dev/null; then php -m > "$BACKUP/modules-before.txt" 2>&1 || true; fi
rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' "${SELECTED[@]}"
echo "Configuration backup: $BACKUP"

# Use archived dependency repositories for this transaction only. Existing
# repository configuration is left intact. Release RPMs are checksum-verified
# above; they are currently unsigned. Distribution dependencies keep GPG checks.
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
"${YUM[@]}" localinstall "${SELECTED[@]}"
mkdir -p /usr/local/share/php71w-cve
cp "$TMP/verify-patch.php" "$TMP/BUILDINFO.json" /usr/local/share/php71w-cve/
/usr/bin/php -n /usr/local/share/php71w-cve/verify-patch.php
if [[ $RESTART -eq 1 ]] && [[ -d /run/systemd/system ]]; then
    if systemctl is-active --quiet php-fpm; then /usr/sbin/php-fpm -t; systemctl restart php-fpm; fi
    if rpm -q mod_php71w >/dev/null 2>&1 && systemctl is-active --quiet httpd; then httpd -t; systemctl restart httpd; fi
fi
echo 'Installed RPM versions:'
rpm -qf /usr/bin/php
echo 'CLI verification: php -n /usr/local/share/php71w-cve/verify-patch.php'
echo 'Restart long-running PHP workers. Verify the patch constants through the web/FPM process too.'
