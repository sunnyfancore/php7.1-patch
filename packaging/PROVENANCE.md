# RPM 打包来源

上游：https://github.com/webtatic-rpms/php71w

固定提交：`36d3aeb770d2133a7600ec229f599adaff3c2f3b`。`webtatic/` 保留其配置、兼容补丁和 spec；spec 本地调整为 RPM 发布号、维护者来源及带补丁后缀的版本检查。继续提供原有 PHP API/Zend ABI、NTS/ZTS、Apache/FPM/CLI 和扩展子包布局。

PHP 源码取自本仓库。前两次提交分别保存官方 7.1.33 发布包和仅涉及两个 CVE 的 17 文件回移植。版本标识不宣称这是官方 PHP 7.1.34。

CentOS linux/amd64 基础镜像固定为 `sha256:dead07b4d8ed7e29e98de0f4504d87e8880d4347859d839686a31da35a3b532f`。依赖使用 CentOS 7.9/EPEL 7 归档，并检查发行版 GPG 签名；构建 RPM 清单记录在 `BUILDINFO.json`。本项目尚未设置自己的 RPM 签名密钥。

EPEL 7 公钥来自 distribution-gpg-keys 项目，SHA256 为 `028b9accc59bab1d21f2f3f544df5469910581e728a64fd8c411a725a82300c2`。
