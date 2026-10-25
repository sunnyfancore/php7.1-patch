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
printf '{"release_tag":"v7.1.33-cve20261025-r2"}\n' > "$BOOTSTRAP_FIXTURES/BUILDINFO.json"
printf 'fixture binary archive\n' > "$BOOTSTRAP_FIXTURES/php71w-centos7.9-x86_64-rpms.tar.gz"
cat > "$BOOTSTRAP_FIXTURES/install-php71.sh" <<'INSTALLER'
#!/bin/bash
set -euo pipefail
found_package=0
found_checksums=0
found_restart=0
found_fresh=0
found_tag=
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag) found_tag=$2; shift 2 ;;
        --package) test -s "$2"; found_package=1; shift 2 ;;
        --checksums) test -s "$2"; found_checksums=1; shift 2 ;;
        --restart-services) found_restart=1; shift ;;
        --fresh) found_fresh=1; shift ;;
        *) exit 1 ;;
    esac
done
[[ $found_package -eq 1 && $found_checksums -eq 1 ]]
[[ $found_restart -eq ${EXPECT_RESTART:-1} ]]
[[ $found_fresh -eq ${EXPECT_FRESH:-0} ]]
[[ "$found_tag" == "${EXPECT_TAG:-v7.1.33-cve20261025-r2}" ]]
touch "$BOOTSTRAP_CALLED"
INSTALLER
(cd "$BOOTSTRAP_FIXTURES" && sha256sum --text install-php71.sh *.tar.gz > SHA256SUMS)
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
case "$url" in
    */releases/latest/download/BUILDINFO.json)
        cp "$BOOTSTRAP_FIXTURES/BUILDINFO.json" "$out"
        if [[ ${BOOTSTRAP_ADVANCE_LATEST:-0} -eq 1 ]]; then
            printf '{"release_tag":"v7.1.33-cve20261025-r3"}\n' > "$BOOTSTRAP_FIXTURES/BUILDINFO.json"
        fi
        ;;
    */releases/download/"${EXPECT_TAG:-v7.1.33-cve20261025-r2}"/*)
        cp "$BOOTSTRAP_FIXTURES/${url##*/}" "$out"
        ;;
    *) echo "Unexpected download URL: $url" >&2; exit 1 ;;
esac
CURL
chmod +x "$TEST_TMP/bin/curl"
export PATH="$TEST_TMP/bin:$PATH"
bash "$ROOT/install.sh"
test -e "$BOOTSTRAP_CALLED"
[[ $(grep -c '^https://github.com/' "$BOOTSTRAP_URL_LOG") -eq 4 ]]
rm "$BOOTSTRAP_CALLED"
: > "$BOOTSTRAP_URL_LOG"
EXPECT_RESTART=0 EXPECT_FRESH=1 bash "$ROOT/install.sh" --mirror-prefix https://mirror.example/ --no-restart --fresh
test -e "$BOOTSTRAP_CALLED"
[[ $(grep -c '^https://mirror.example/https://github.com/' "$BOOTSTRAP_URL_LOG") -eq 4 ]]
rm "$BOOTSTRAP_CALLED"
: > "$BOOTSTRAP_URL_LOG"
EXPECT_TAG=v7.1.33-cve20261025-r1 bash "$ROOT/install.sh" --tag v7.1.33-cve20261025-r1
test -e "$BOOTSTRAP_CALLED"
[[ $(wc -l < "$BOOTSTRAP_URL_LOG") -eq 3 ]]
! grep -q '/releases/latest/' "$BOOTSTRAP_URL_LOG"
rm "$BOOTSTRAP_CALLED"
: > "$BOOTSTRAP_URL_LOG"
# A new release appearing mid-download must not change the selected assets.
BOOTSTRAP_ADVANCE_LATEST=1 bash "$ROOT/install.sh" --tag latest
test -e "$BOOTSTRAP_CALLED"
[[ $(grep -c '/releases/download/v7.1.33-cve20261025-r2/' "$BOOTSTRAP_URL_LOG") -eq 3 ]]
rm "$BOOTSTRAP_CALLED"
: > "$BOOTSTRAP_URL_LOG"
EXPECT_TAG=v7.1.33-cve20261025-r3 bash "$ROOT/install.sh"
test -e "$BOOTSTRAP_CALLED"
[[ $(grep -c '/releases/download/v7.1.33-cve20261025-r3/' "$BOOTSTRAP_URL_LOG") -eq 3 ]]
rm "$BOOTSTRAP_CALLED"
: > "$BOOTSTRAP_URL_LOG"
if bash "$ROOT/install.sh" --tag invalid; then
    echo 'Invalid explicit tag unexpectedly accepted' >&2; exit 1
fi
test ! -s "$BOOTSTRAP_URL_LOG"
test ! -e "$BOOTSTRAP_CALLED"
for metadata in '{"release_tag":"../../invalid"}' '{"release_tag":""}' '{}' 'not json'; do
    printf '%s\n' "$metadata" > "$BOOTSTRAP_FIXTURES/BUILDINFO.json"
    : > "$BOOTSTRAP_URL_LOG"
    if bash "$ROOT/install.sh"; then
        echo 'Invalid latest metadata unexpectedly accepted' >&2; exit 1
    fi
    [[ $(wc -l < "$BOOTSTRAP_URL_LOG") -eq 1 ]]
    test ! -e "$BOOTSTRAP_CALLED"
done
printf '{"release_tag":"v7.1.33-cve20261025-r2"}\n' > "$BOOTSTRAP_FIXTURES/BUILDINFO.json"
cp "$BOOTSTRAP_FIXTURES/install-php71.sh" "$TEST_TMP/installer-good"
printf '# corrupted installer\n' > "$BOOTSTRAP_FIXTURES/install-php71.sh"
if bash "$ROOT/install.sh"; then
    echo 'Installer checksum corruption unexpectedly accepted' >&2; exit 1
fi
test ! -e "$BOOTSTRAP_CALLED"
cp "$TEST_TMP/installer-good" "$BOOTSTRAP_FIXTURES/install-php71.sh"
printf 'corrupted archive\n' > "$BOOTSTRAP_FIXTURES/php71w-centos7.9-x86_64-rpms.tar.gz"
if bash "$ROOT/install.sh"; then
    echo 'Checksum corruption unexpectedly accepted' >&2; exit 1
fi
test ! -e "$BOOTSTRAP_CALLED"
echo 'PASS bootstrap: latest discovery, pinned releases, proxy, flags, metadata and checksum rejection'
