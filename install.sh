#!/bin/bash
# Fetch the released, checksum-verified RPM installer and binaries.
set -euo pipefail
TAG=latest
MIRROR_PREFIX=${PHP71_GITHUB_PROXY:-}
RESTART=1
FRESH=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mirror-prefix) MIRROR_PREFIX=${2:?Missing mirror prefix}; shift 2 ;;
        --tag) TAG=${2:?Missing release tag}; shift 2 ;;
        --no-restart) RESTART=0; shift ;;
        --fresh) FRESH=1; shift ;;
        --help)
            cat <<'HELP'
Usage: sudo bash install.sh [--tag TAG|latest] [--mirror-prefix https://ghfast.top/] [--no-restart] [--fresh]

Defaults to the latest published, non-prerelease GitHub Release on each run.
Use --tag v7.1.33-cve20261025-r2 to select a specific release.

Official source:
curl -fL --retry 3 -o install.sh https://raw.githubusercontent.com/sunnyfancore/php7.1-patch/main/install.sh && sudo bash install.sh

Mirror acceleration (bootstrap, installer, RPM bundle and checksums):
curl -fL --retry 3 -o install.sh https://ghfast.top/https://raw.githubusercontent.com/sunnyfancore/php7.1-patch/main/install.sh && sudo bash install.sh --mirror-prefix https://ghfast.top/

The proxy prefix is replaceable. --no-restart skips installer restarts;
older RPM scriptlets may still restart FPM during upgrade.
HELP
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done
[[ $EUID -eq 0 ]] || { echo 'Run with sudo bash install.sh' >&2; exit 1; }
[[ "$TAG" == latest || "$TAG" =~ ^v7\.1\.33-cve[0-9]+-r[0-9]+$ ]] || { echo 'Invalid release tag' >&2; exit 1; }
if [[ -n "$MIRROR_PREFIX" ]]; then
    [[ "$MIRROR_PREFIX" =~ ^https://[^[:space:]\?\#]+/?$ ]] || { echo 'Mirror prefix must be an HTTPS URL' >&2; exit 1; }
    MIRROR_PREFIX=${MIRROR_PREFIX%/}/
fi
TMP=$(mktemp -d /tmp/php71w-download.XXXXXXXX)
trap 'rm -rf -- "$TMP"' EXIT
download() {
    curl --fail --location --retry 3 --connect-timeout 20 --proto '=https' --tlsv1.2 \
        "${MIRROR_PREFIX}https://github.com/sunnyfancore/php7.1-patch/$1" -o "$2"
}
if [[ "$TAG" == latest ]]; then
    # Resolve once, then pin every asset so a new release cannot mix builds.
    download releases/latest/download/BUILDINFO.json "$TMP/latest-BUILDINFO.json"
    TAG=$(python - "$TMP/latest-BUILDINFO.json" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as handle:
        sys.stdout.write(json.load(handle)['release_tag'])
except (IOError, ValueError, KeyError, TypeError):
    sys.exit('Invalid latest release metadata in BUILDINFO.json')
PY
)
fi
[[ "$TAG" =~ ^v7\.1\.33-cve[0-9]+-r[0-9]+$ ]] || { echo 'Invalid resolved release tag' >&2; exit 1; }
printf 'Selected release: %s\n' "$TAG"
for name in SHA256SUMS install-php71.sh php71w-centos7.9-x86_64-rpms.tar.gz; do
    download "releases/download/$TAG/$name" "$TMP/$name"
done
for name in install-php71.sh php71w-centos7.9-x86_64-rpms.tar.gz; do
    hash=$(awk -v name="$name" '$2 == name {print $1}' "$TMP/SHA256SUMS")
    [[ "$hash" =~ ^[a-f0-9]{64}$ ]] || { echo "Missing checksum: $name" >&2; exit 1; }
    printf '%s  %s\n' "$hash" "$TMP/$name" | sha256sum -c -
done
ARGS=(--tag "$TAG" --package "$TMP/php71w-centos7.9-x86_64-rpms.tar.gz" --checksums "$TMP/SHA256SUMS")
[[ $RESTART -eq 0 ]] || ARGS+=(--restart-services)
[[ $FRESH -eq 0 ]] || ARGS+=(--fresh)
bash "$TMP/install-php71.sh" "${ARGS[@]}"
