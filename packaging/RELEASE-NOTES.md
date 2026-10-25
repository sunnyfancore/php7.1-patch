CentOS 7.9 x86_64 / Webtatic php71w RPM 更新包，包含 CVE-2026-109618 与 CVE-2026-109619 的第三方缓解回移植。

`php71w-centos7.9-x86_64-rpms.tar.gz` 是二进制安装包；`.src.rpm` 是可重建源码包。`BUILDINFO.json` 记录源码提交、构建环境及 Actions 地址。

安装命令：

```bash
TAG=v7.1.33-cve20261025-r1
BASE="https://github.com/sunnyfancore/php7.1-patch/releases/download/$TAG"
curl -fL --retry 3 -o install-php71.sh "$BASE/install-php71.sh"
curl -fL --retry 3 -o SHA256SUMS "$BASE/SHA256SUMS"
awk '$2 == "install-php71.sh" {print}' SHA256SUMS | sha256sum -c -
sudo bash install-php71.sh --restart-services
```

安装器校验下载包，备份配置，然后通过 YUM 更新本机已安装且本次提供的同名 php71w RPM。配置沿用 `%config(noreplace)` 规则。依赖使用临时 CentOS/EPEL 归档仓库，不改本机仓库文件。自建 RPM 尚未签名，使用 HTTPS 和 SHA256 校验；发行版依赖仍检查其 GPG 签名。

验证命令：

```bash
rpm -qf /usr/bin/php
php -v
php -n /usr/local/share/php71w-cve/verify-patch.php
php -r 'echo PHP_CVE_PATCH_ID, PHP_EOL, PHP_CVE_PATCH_BUILD, PHP_EOL;'
```

应显示 `7.1.33-cve20261025-r1`、`CVE-2026-109618+CVE-2026-109619;r1` 和源码提交号。CLI 和网站/FPM 可能运行不同进程，网站也需核对常量；常驻队列进程需重启。`--restart-services` 检查并重启正在运行的 php-fpm，以及使用 mod_php71w 的 httpd。

发布前 Actions 检查 CentOS 7.9 RPM 构建、干净安装、配置保留、CLI/OOM，以及 FPM 同一 worker 连续请求、multipart 上限、上传进度关闭和 OOM 后 worker 重建。

行为变化：分配器 OOM 立即退出、不执行 shutdown 回调；session 上传进度关闭；新增 multipart 分段限制。PHP 7.1 与 CentOS 7 均已停止维护，本包只覆盖指定两个 CVE 的缓解，不代表其它漏洞全部修复。原有第三方扩展仍需按业务验证。配置备份不包含旧版本 RPM，如需回退请预先保留原 RPM。
