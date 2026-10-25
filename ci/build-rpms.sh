#!/bin/bash
set -euo pipefail
cd /src
: "${SOURCE_COMMIT:?SOURCE_COMMIT is required}"
[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]]
bash ci/setup-centos7.sh
TOP=/tmp/php71-rpmbuild
mkdir -p "$TOP"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
cp packaging/webtatic/* "$TOP/SOURCES/"
cp packaging/webtatic/php71.spec "$TOP/SPECS/php71.spec"
yum-builddep -y --define 'dist .el7' "$TOP/SPECS/php71.spec"
# Package this repository's already-patched source, not a fresh remote PHP tree.
mkdir /tmp/php71-source
tar --exclude=.git --exclude=dist --exclude=packaging --exclude=.github --exclude=ci \
    -cf - . | tar -xf - -C /tmp/php71-source
sed -i "s/source-checkout/$SOURCE_COMMIT/" /tmp/php71-source/main/php_cve_patch.h
mv /tmp/php71-source /tmp/php-7.1.33
tar -cjf "$TOP/SOURCES/php-7.1.33.tar.bz2" -C /tmp php-7.1.33
rpmbuild -ba --define "_topdir $TOP" --define 'dist .el7' \
    --define 'runselftest 0' --define "_smp_mflags -j${JOBS:-2}" \
    "$TOP/SPECS/php71.spec"
mkdir -p dist/rpms
find "$TOP/RPMS/x86_64" -name '*.rpm' ! -name '*debuginfo*' -exec cp {} dist/rpms/ \;
cp "$TOP/SRPMS/"*.src.rpm dist/
rpm -qp --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n' dist/rpms/*.rpm | sort > dist/PACKAGES.tsv
rpm -qp --configfiles dist/rpms/php71w-common-*.rpm > dist/CONFIGFILES.txt
grep -q '^/etc/php.ini$' dist/CONFIGFILES.txt
cp ci/verify-patch.php dist/verify-patch.php
cp packaging/keys/RPM-GPG-KEY-EPEL-7 dist/
cp packaging/install-rpms.sh dist/install-php71.sh
sed -i "s/@RELEASE_TAG@/${RELEASE_TAG}/g" dist/install-php71.sh
cp packaging/RELEASE-NOTES.md dist/RELEASE-NOTES.md
python - <<'PY'
import json,os,subprocess
d={'version':'7.1.33-cve20261025-r1','patch_id':'CVE-2026-109618+CVE-2026-109619;r1',
   'source_commit':os.environ['SOURCE_COMMIT'],'release_tag':os.environ['RELEASE_TAG'],
   'target':'CentOS 7.9 x86_64','glibc':subprocess.check_output(['getconf','GNU_LIBC_VERSION']).decode().strip(),
   'webtatic_packaging_commit':'36d3aeb770d2133a7600ec229f599adaff3c2f3b',
   'run_url':os.environ.get('RUN_URL'),
   'rpm_list':subprocess.check_output(['rpm','-qa']).decode().splitlines()}
with open('dist/BUILDINFO.json','w') as f: json.dump(d,f,indent=2,sort_keys=True)
PY
tar -czf dist/php71w-centos7.9-x86_64-rpms.tar.gz -C dist rpms PACKAGES.tsv BUILDINFO.json CONFIGFILES.txt verify-patch.php RPM-GPG-KEY-EPEL-7
(cd dist && sha256sum *.gz *.rpm *.json *.tsv *.txt *.php *.sh *.md > SHA256SUMS)
