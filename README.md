# PHP 7.1 CVE 回移植与 CentOS 7.9 RPM

为 **CentOS 7.9 x86_64 + Webtatic php71w** 提供 CVE-2026-109618 / CVE-2026-109619 缓解更新，保留 `/usr/bin/php`、`/etc/php.ini`、`/etc/php.d/`、`/usr/lib64/php/modules` 和 RPM 包管理方式。

源码历史：第一提交是完整官方 7.1.33；第二提交只提取 17 文件 CVE 补丁；后续提交加入版本标识和 Actions/RPM 打包。没有使用宝塔安装脚本或 `/www` 目录。

## 二进制下载与安装

引导脚本每次运行时自动获取 GitHub Releases 的最新正式版（不包含草稿和预发布），再固定该标签下载并校验全部安装文件。以后发布 r3、r4，无需修改脚本中的默认版本。也可用 `sudo bash install.sh --tag v7.1.33-cve20261025-r2` 指定版本；`--tag latest` 恢复自动选择。

官方源一键命令：

```bash
curl -fL --retry 3 -o install.sh https://raw.githubusercontent.com/sunnyfancore/php7.1-patch/main/install.sh && sudo bash install.sh
```

镜像加速一键命令（示例使用第三方 ghfast.top，可换成可用的 GitHub 代理前缀）：

```bash
curl -fL --retry 3 -o install.sh https://ghfast.top/https://raw.githubusercontent.com/sunnyfancore/php7.1-patch/main/install.sh && sudo bash install.sh --mirror-prefix https://ghfast.top/
```

加速作用于引导脚本、Release 安装器、RPM 合集及校验文件。两种方式均校验 SHA256，安装后默认重启已运行的 FPM/httpd。`--no-restart` 只跳过安装器主动重启；原版/r1 FPM RPM 的旧卸载脚本仍可能触发重启，升级请安排维护窗口。r2 的新 RPM 已取消这项自动重启。`bash install.sh --help` 也列出两种命令。CentOS/EPEL 系统依赖仍由其归档仓库下载。

下载 [Releases](https://github.com/sunnyfancore/php7.1-patch/releases) 的 `php71w-centos7.9-x86_64-rpms.tar.gz`，或者直接安装：

```bash
TAG=v7.1.33-cve20261025-r2
BASE="https://github.com/sunnyfancore/php7.1-patch/releases/download/$TAG"
curl -fL --retry 3 -o install-php71.sh "$BASE/install-php71.sh"
curl -fL --retry 3 -o SHA256SUMS "$BASE/SHA256SUMS"
awk '$2 == "install-php71.sh" {print}' SHA256SUMS | sha256sum -c -
sudo bash install-php71.sh --restart-services
```

安装器备份配置和包清单到 `/var/backups/php71w-cve-*`，再由 YUM 同步更新本机已经安装且本次提供的同名 RPM。不会安装所有扩展，第三方 PECL 包继续保留；依赖不满足会中止，没有使用 `--nodeps`。配置遵循 `%config(noreplace)`，已有修改不会被覆盖。支持只有 FPM 而没有 CLI 的 php71w 安装；会检查 FPM 二进制标识和配置。按升级前记录的活动状态重启服务，重启或校验失败返回非零。CLI/FPM 扩展清单会在升级前后比较。新安装显式加 `--fresh`，只安装 CLI/common/FPM。

本项目 RPM 尚未签名，使用 HTTPS 和 SHA256 校验；发行版依赖仍检查官方 GPG 签名。依赖仅对本次事务启用临时 CentOS/EPEL 归档仓库，不改已有 `.repo`。若要回退，事先保留原版本 RPM；配置备份不能代替旧二进制。

恢复到未打补丁的 PHP 7.1.33，见 [原版恢复说明](docs/RESTORE-PHP-7.1.33.md)：包含 Webtatic 原版同名 RPM 下载、签名校验、统一降级、配置与服务验收，以及 PHP 官方源码归档地址。当前未提供自动回滚功能。

已下载二进制包可这样安装，缺少的系统依赖仍需网络：

```bash
sudo bash install-php71.sh --restart-services \
  --package ./php71w-centos7.9-x86_64-rpms.tar.gz --checksums ./SHA256SUMS
```

## 升级后识别补丁

```bash
rpm -qf /usr/bin/php
# php71w-cli-7.1.33-1.w7.cve20261025.r2.el7.x86_64
php -v
# PHP 7.1.33-cve20261025-r2 ...
php -n /usr/local/share/php71w-cve/verify-patch.php
php -r 'echo PHP_CVE_PATCH_ID, PHP_EOL, PHP_CVE_PATCH_BUILD, PHP_EOL;'
# CVE-2026-109618+CVE-2026-109619;r2
# <40 位源码提交号>
php -i | grep 'CVE Patch'
# 纯 FPM 环境：
php-fpm -i | grep -E 'CVE Patch|PHP Version'
```

版本后缀与常量编译在二进制中，`BUILDINFO.json` 记录构建来源；Actions 验证实际缓解行为。标识证明当前进程使用该构建，不能证明所有扩展或其它安全问题均已修复。

CLI 与网站/FPM 可能不是同一进程。`--restart-services` 会检查并重启正在运行的 php-fpm，及使用 mod_php71w 的 httpd。常驻队列需另行重启。可在网站临时诊断页核对下列信息，完成后删除诊断页：

```php
<?php
header('Content-Type: text/plain');
echo PHP_VERSION, "\n";
echo defined('PHP_CVE_PATCH_ID') ? PHP_CVE_PATCH_ID : 'UNPATCHED', "\n";
echo defined('PHP_CVE_PATCH_BUILD') ? PHP_CVE_PATCH_BUILD : 'unknown', "\n";
```

## Actions 构建及发布

Actions → **CentOS 7.9 Webtatic-compatible RPMs** → Run workflow。默认发布标签 `v7.1.33-cve20261025-r2`；关闭 `publish` 可只生成构建产物。所有测试成功后才创建 Release 和标签，不覆盖已有发布。

固定 CentOS 7.9 amd64 容器内构建 Webtatic 子包，产出二进制 RPM 合集、源码 RPM、SHA256、包清单、构建信息。新容器验证安装和配置保留；CLI 验证标识/嵌套变量/字符串/OOM；FPM 验证同一 worker 连续请求、multipart 上限、文件上传、上传进度关闭和 OOM 后 worker 重建。

r2 进一步补齐超大分配对齐溢出检查和三个处理器栈的请求间复位，清理重复的 VM 检查。Actions 增加 SIZE_MAX 分配探针、VM 重新生成一致性、真实 r1→r2 纯 FPM/Apache 升级、重复请求和异常清理测试。详见 [源码核对记录](docs/AUDIT-2026-10-25.md)。

打包来源见 [packaging/PROVENANCE.md](packaging/PROVENANCE.md)。

## 行为与范围

- 分配器 OOM 立即退出进程，不执行 shutdown 回调；FPM 重新生成 worker。
- session 上传进度在源码层面关闭，普通文件上传可继续使用。
- 新增 `max_multipart_body_parts`，默认 `-1` 表示 `max_input_vars + max_file_uploads`。
- PHP API/Zend ABI 编号保持原值，第三方扩展与实际业务仍需验收。

PHP 7.1 与 CentOS 7 均已停止维护。本项目只提供指定两个 CVE 的第三方缓解回移植，不是官方 PHP 7.1.34，也不覆盖其它已知漏洞。
