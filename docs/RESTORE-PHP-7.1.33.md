# 恢复到未打补丁的 PHP 7.1.33

本文适用于本项目的 **CentOS 7.9 x86_64 + Webtatic php71w RPM** 安装，手动将本项目 r1/r2 包降级到 Webtatic 原版 `7.1.33-1.w7`。没有新增自动回滚参数，也不会在业务服务器上自动执行本文操作。

PHP 官方为 Linux 发布的是源码归档；`php71w-*.rpm` 由 Webtatic 打包，不能称为 PHP 官方 RPM。已有 Webtatic 安装应使用下面的 RPM 降级步骤，保留 RPM 管理和原有路径。直接编译官方源码并执行 `make install` 会形成另一套安装，不能完成对现有 RPM 的降级。

恢复原版后，本项目的 CVE-2026-109618 / CVE-2026-109619 缓解及相关行为调整随之撤销。请在维护窗口执行，PHP-FPM / Apache 和常驻 PHP 进程需要重新启动。

## 备份与版本选择

升级时产生的 `/var/backups/php71w-cve-*` 只保存配置、RPM 版本清单及部分运行状态，**不包含旧 RPM**。仅复制配置不能恢复 PHP 程序版本；现有 `install.sh --tag ...` 也不提供降级功能。

先查看已有备份，选择对应那次升级的目录，避免直接把时间最新的目录当作原版备份：

```bash
sudo ls -dt /var/backups/php71w-cve-*
# 将下面路径替换为实际选中的目录。
PHP_BACKUP=/var/backups/php71w-cve-实际日期时间-进程号
sudo grep -E '^(php71w-|mod_php71w-)' "$PHP_BACKUP/packages-before.txt"
```

以下步骤固定恢复到 Webtatic `7.1.33-1.w7.x86_64`。如果要恢复版本清单里的其它版本，需要取得对应版本的完整同名 RPM，不能混用不同 PHP 版本的 common、SAPI 和扩展包。

## 1. 保存当前配置并记录需要降级的包

以下各步在**同一个 root Bash 会话**中执行；后面的步骤会使用前面定义的变量。发生错误时停止，不要跳过失败的步骤继续降级。

```bash
sudo -i
set -euo pipefail
RESTORE_DIR=$(mktemp -d /var/tmp/php71w-original.XXXXXXXX)
mkdir "$RESTORE_DIR/rpms"
chmod 700 "$RESTORE_DIR"
rpm -qa | sort > "$RESTORE_DIR/packages-before.txt"
rpm -qa --qf '%{NAME} %{VERSION} %{RELEASE} %{ARCH}\n' \
  > "$RESTORE_DIR/installed-before.txt"

# 只选择本项目的 PHP 7.1.33 包；保留未被本项目替换的第三方 PECL 包。
awk '$2 == "7.1.33" && $3 ~ /^1[.]w7[.]cve[0-9]+[.]r[0-9]+[.]el7$/ &&
     $4 == "x86_64" && ($1 ~ /^php71w-/ || $1 == "mod_php71w") { print $1 }' \
  "$RESTORE_DIR/installed-before.txt" | sort -u > "$RESTORE_DIR/package-names.txt"
test -s "$RESTORE_DIR/package-names.txt" || {
  echo '没有找到本项目的 PHP 7.1.33 x86_64 RPM，停止。' >&2
  exit 1
}
mapfile -t PHP_PACKAGES < "$RESTORE_DIR/package-names.txt"
cat "$RESTORE_DIR/package-names.txt"

: > "$RESTORE_DIR/config-paths.txt"
for path in etc/php.ini etc/php.d etc/php-fpm.conf etc/php-fpm.d \
  etc/php-zts.d etc/httpd/conf.d/php.conf etc/httpd/conf.modules.d/10-php.conf \
  etc/sysconfig/php-fpm usr/local/share/php71w-cve; do
  if [[ -e "/$path" || -L "/$path" ]]; then
    printf '%s\n' "$path" >> "$RESTORE_DIR/config-paths.txt"
  fi
done
tar -czpf "$RESTORE_DIR/config-before.tar.gz" -C / \
  -T "$RESTORE_DIR/config-paths.txt"

FPM_ACTIVE=0
HTTPD_ACTIVE=0
if rpm -q php71w-fpm >/dev/null 2>&1 && systemctl is-active --quiet php-fpm; then
  /usr/sbin/php-fpm -t
  FPM_ACTIVE=1
fi
if rpm -q mod_php71w >/dev/null 2>&1 && systemctl is-active --quiet httpd; then
  httpd -t
  HTTPD_ACTIVE=1
fi
printf 'php-fpm=%s\nhttpd=%s\n' "$FPM_ACTIVE" "$HTTPD_ACTIVE" \
  > "$RESTORE_DIR/services-before.txt"
printf '本次操作记录和配置备份：%s\n' "$RESTORE_DIR"
```

这里保存的是当前配置和版本记录，不是当前 r2 二进制的完整备份。如需在降级后重新安装 r2，请同时保留 [r2 发布包及 SHA256SUMS](https://github.com/sunnyfancore/php7.1-patch/releases/tag/v7.1.33-cve20261025-r2)。

## 2. 下载原版同名 RPM 并验证签名

Webtatic 的 [EL7 镜像列表](https://mirror.webtatic.com/yum/el7/x86_64/mirrorlist) 指向 `https://repo.webtatic.com/yum/el7/x86_64/`，包文件位于其 `RPMS/` 子目录。2026-10-25 已核实原版 `7.1.33-1.w7` 的 CLI/common/FPM/Apache 和配套扩展包仍在该目录中。

```bash
ORIGINAL_BASE=https://repo.webtatic.com/yum/el7/x86_64/RPMS
for name in "${PHP_PACKAGES[@]}"; do
  file="$RESTORE_DIR/rpms/$name-7.1.33-1.w7.x86_64.rpm"
  curl -fL --retry 3 --proto '=https' --tlsv1.2 \
    -o "$file" "$ORIGINAL_BASE/$name-7.1.33-1.w7.x86_64.rpm"
  actual=$(rpm -qp --qf '%{NAME} %{VERSION} %{RELEASE} %{ARCH}' "$file")
  [[ "$actual" == "$name 7.1.33 1.w7 x86_64" ]] || {
    echo "RPM 身份不符：$file" >&2
    exit 1
  }
done

curl -fL --retry 3 --proto '=https' --tlsv1.2 \
  -o "$RESTORE_DIR/RPM-GPG-KEY-webtatic-el7" \
  https://mirror.webtatic.com/yum/RPM-GPG-KEY-webtatic-el7
printf 'f2bab3a2b2ea38c0d6a60231ea13ae80999d4007a58e44c5f650eb6e6a4834c4  %s\n' \
  "$RESTORE_DIR/RPM-GPG-KEY-webtatic-el7" | sha256sum -c -
rpm --import "$RESTORE_DIR/RPM-GPG-KEY-webtatic-el7"
ORIGINAL_RPMS=("$RESTORE_DIR"/rpms/*.rpm)
rpm -K "${ORIGINAL_RPMS[@]}"
```

公钥校验和、包身份和 RPM 签名都必须通过。签名检查应显示 `OK`；若出现 `NOKEY`、`NOT OK`、下载 404 或身份不符，应先解决问题，不要使用 `--nogpgcheck`、`--nodeps` 或其它强制跳过检查的参数。

## 3. 在同一事务中降级全部目标包

先执行 RPM 事务测试，再实际降级。只使用上一步下载的本地 RPM，临时禁用网络仓库，避免 CentOS 7 的失效仓库影响操作；不会修改已有 `.repo` 文件。实际事务执行时请核对列出的包和操作，确认没有意外删除其它业务依赖。

```bash
yum --disablerepo='*' --setopt=localpkg_gpgcheck=1 \
  --setopt=tsflags=test downgrade "${ORIGINAL_RPMS[@]}"
yum --disablerepo='*' --setopt=localpkg_gpgcheck=1 \
  downgrade "${ORIGINAL_RPMS[@]}"

for name in "${PHP_PACKAGES[@]}"; do
  actual=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$name.x86_64")
  [[ "$actual" == '7.1.33-1.w7.x86_64' ]] || {
    echo "降级后版本不符：$name $actual" >&2
    exit 1
  }
done
rpm -q "${PHP_PACKAGES[@]}"
```

不要仅降级 `php71w-cli` 或 `php71w-common`。依赖关系可能要求 common、FPM/Apache 和扩展包具有相同的版本与发布号。若事务测试提示缺少系统依赖或其它 PHP 扩展冲突，应先取得缺少的原版 RPM 或处理冲突，不能跳过依赖检查。

## 4. 检查配置、重启服务并验证

原版 RPM 的 `%config(noreplace)` 通常保留已经修改的配置。先检查 `.rpmnew`、`.rpmsave` 和扩展加载情况；只有确实需要恢复升级前配置时，才从选定备份中复制对应文件。不要默认覆盖所有配置，避免丢失升级后新增的业务设置。例如，在 root 会话中恢复指定备份的 `php.ini`：

```bash
# 可选：先替换成实际备份目录，并确认其中 php.ini 正是要恢复的配置。
PHP_BACKUP=/var/backups/php71w-cve-实际日期时间-进程号
test -f "$PHP_BACKUP/config/etc/php.ini"
cp -a -- "$PHP_BACKUP/config/etc/php.ini" /etc/php.ini
```

无论是否复制配置，都要检查配置并重新启动降级前处于运行状态的服务：

```bash
if rpm -q php71w-fpm >/dev/null 2>&1; then
  /usr/sbin/php-fpm -t
  /usr/sbin/php-fpm -v
fi
if rpm -q mod_php71w >/dev/null 2>&1; then
  httpd -t
fi
if [[ $FPM_ACTIVE -eq 1 ]]; then
  systemctl restart php-fpm
  systemctl is-active --quiet php-fpm
fi
if [[ $HTTPD_ACTIVE -eq 1 ]]; then
  systemctl restart httpd
  systemctl is-active --quiet httpd
fi
if rpm -q php71w-cli >/dev/null 2>&1; then
  /usr/bin/php -v
  /usr/bin/php -m
  /usr/bin/php -r 'if (PHP_VERSION !== "7.1.33" || defined("PHP_CVE_PATCH_ID")) { fwrite(STDERR, "Unexpected PHP build\n"); exit(1); } echo "PASS original PHP 7.1.33\n";'
fi
```

CLI/FPM 版本应为 `7.1.33`，RPM 发布号为 `1.w7`，不再带 `cve20261025-r2`。重启其它常驻队列进程，并在实际网站请求中核对 `PHP_VERSION` 为 `7.1.33`、`defined('PHP_CVE_PATCH_ID')` 为 `false`，然后验收上传、数据库连接和业务所需扩展。仅检查命令行版本不能确认网站进程已切换。

`/usr/local/share/php71w-cve/BUILDINFO.json` 和 `verify-patch.php` 是之前补丁安装留下的文件；降级后它们不能代表当前进程的版本，也不应继续使用补丁验证器作为原版验收方法。如需保留记录，可把该目录归档到本次操作目录：

```bash
if [[ -d /usr/local/share/php71w-cve ]]; then
  mv -- /usr/local/share/php71w-cve "$RESTORE_DIR/patched-build-metadata"
fi
```

若实际事务或重启失败，不会自动恢复先前二进制。请保留本次终端输出、`$RESTORE_DIR` 和 r2 发布包，先核对当前已安装版本再处理，不要重复执行强制覆盖命令。

## PHP 官方 7.1.33 源码包

若需要的是未修改的上游源码，可以从 [PHP 官方归档](https://museum.php.net/php7/php-7.1.33.tar.xz) 下载。SHA256 来自 [PHP 官方 7.1.33 发布元数据](https://www.php.net/releases/index.php?json&version=7.1.33)：

```bash
curl -fL --retry 3 -o php-7.1.33.tar.xz \
  https://museum.php.net/php7/php-7.1.33.tar.xz
echo 'bd7c0a9bd5433289ee01fd440af3715309faf583f75832b64fe169c100d52968  php-7.1.33.tar.xz' \
  | sha256sum -c -
```

这是源码归档，不包含可直接降级现有 Webtatic 安装的 RPM。本文的 Webtatic 降级流程不会使用源码编译覆盖系统文件。
