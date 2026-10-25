#!/bin/bash
set -euo pipefail
test "$(uname -m)" = x86_64
grep -q '7.9.2009' /etc/centos-release
# Change repositories only inside the disposable CI container.
mkdir -p /etc/yum.repos.d.disabled
find /etc/yum.repos.d -maxdepth 1 -type f -name '*.repo' -exec mv -t /etc/yum.repos.d.disabled {} +
cat > /etc/yum.repos.d/cve-build.repo <<'REPOS'
[base]
name=CentOS 7.9 base archive
baseurl=https://vault.centos.org/7.9.2009/os/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
[updates]
name=CentOS 7.9 updates archive
baseurl=https://vault.centos.org/7.9.2009/updates/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
[extras]
name=CentOS 7.9 extras archive
baseurl=https://vault.centos.org/7.9.2009/extras/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
[epel-archive]
name=EPEL 7 archive
baseurl=https://archives.fedoraproject.org/pub/archive/epel/7/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///src/packaging/keys/RPM-GPG-KEY-EPEL-7
REPOS
printf '%s\n' '028b9accc59bab1d21f2f3f544df5469910581e728a64fd8c411a725a82300c2  /src/packaging/keys/RPM-GPG-KEY-EPEL-7' | sha256sum -c -
if [[ ${1:-} == --runtime ]]; then
    yum -y install ca-certificates
else
    yum -y install ca-certificates rpm-build redhat-rpm-config yum-utils autoconf automake bison re2c patch make gcc gcc-c++ cpio git
fi
