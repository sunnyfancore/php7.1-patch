#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]]
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d /tmp/php71-bootstrap-test.XXXXXXXX)
trap 'rm -rf -- "$TEST_TMP"' EXIT
export BOOTSTRAP_FIXTURES="$TEST_TMP/assets"
export BOOTSTRAP_URL_LOG="$TEST_TMP/urls"
export BOOTSTRAP_CALLED="$TEST_TMP/called"
mkdir -p "$BOOTSTRAP_FIXTURES" "$TEST_TMP/bin"
printf 'fixture binary archive\n' > "$BOOTSTRAP_FIXTURES/php71w-centos7.9-x86_64-rpms.tar.gz"
cat > "$BOOTSTRAP_FIXTURES/install-php71.sh" <<'INSTALLER'
#!/bin/bash
set -euo pipefail
found_package=0
found_checksums=0
found_restart=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --package) test -s "$2"; found_package=1; shift 2 ;;
        --checksums) test -s "$2"; found_checksums=1; shift 2 ;;
        --restart-services) found_restart=1; shift ;;
        *) exit 1 ;;
    esac
done
[[ $found_package -eq 1 && $found_checksums -eq 1 ]]
[[ $found_restart -eq ${EXPECT_RESTART:-1} ]]
touch "$BOOTSTRAP_CALLED"
INSTALLER
(cd "$BOOTSTRAP_FIXTURES" && sha256sum install-php71.sh *.tar.gz > SHA256SUMS)
cat > "$TEST_TMP/bin/curl" <<'CURL'
#!/bin/bash
set -euo pipefail
url=
out=
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out=$2; shift 2 ;;
        https://*) url=$1; shift ;;
        *) shift ;;
    esac
done
[[ -n "$url" && -n "$out" ]]
printf '%s\n' "$url" >> "$BOOTSTRAP_URL_LOG"
cp "$BOOTSTRAP_FIXTURES/${url##*/}" "$out"
CURL
chmod +x "$TEST_TMP/bin/curl"
export PATH="$TEST_TMP/bin:$PATH"
bash "$ROOT/install.sh"
test -e "$BOOTSTRAP_CALLED"
[[ $(grep -c '^https://github.com/' "$BOOTSTRAP_URL_LOG") -eq 3 ]]
rm "$BOOTSTRAP_CALLED"
: > "$BOOTSTRAP_URL_LOG"
EXPECT_RESTART=0 bash "$ROOT/install.sh" --mirror-prefix https://mirror.example/ --no-restart
test -e "$BOOTSTRAP_CALLED"
[[ $(grep -c '^https://mirror.example/https://github.com/' "$BOOTSTRAP_URL_LOG") -eq 3 ]]
rm "$BOOTSTRAP_CALLED"
printf 'corrupted archive\n' > "$BOOTSTRAP_FIXTURES/php71w-centos7.9-x86_64-rpms.tar.gz"
if bash "$ROOT/install.sh"; then
    echo 'Checksum corruption unexpectedly accepted' >&2; exit 1
fi
test ! -e "$BOOTSTRAP_CALLED"
echo 'PASS bootstrap: direct downloads, all-asset proxy, restart flag and checksum rejection'
