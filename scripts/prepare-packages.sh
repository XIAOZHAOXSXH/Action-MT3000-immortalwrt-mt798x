#!/usr/bin/env bash
#
# prepare-packages.sh —— 按 workflow 开关把 OpenClash / PassWall 编进固件
#
# 用法:
#   ./scripts/prepare-packages.sh <openwrt源码目录> <是否OpenClash> <是否PassWall>
#
# 设计原则：能不用第三方源就不用。
#
# 早先的版本引入了 kenzok8/small，想装 PassWall 26.x（最新版）。那条路踩了一串坑：
#   - small 里混着只适配 22.03/23.05 的包，全量导出会让 Kconfig 出现递归依赖而段错误
#   - PassWall 26.x 依赖 lyaml，进而依赖 libyaml
#   - sing-box / xray-core 26.x 要求 Go 1.27，而 21.02 自带 1.19
#   - 官方 feed 里的 v2ray-geodata 钉的 geosite 版本已被上游删除，下载 404
# 每一个都要单独打补丁，链路很长也很脆。
#
# 实际上 immortalwrt/luci 的 openwrt-21.02 分支自带 luci-app-passwall 4.68，
# 这是该固件项目为 21.02 钦定的版本，依赖全部来自官方 feed，不需要任何第三方源。
# 所以这里改用官方 PassWall，只从官方 feed 装包。
#
# OpenClash 仍在用上游 master（最新），它只需要 ruby / ruby-yaml / bash 等官方包。

set -euo pipefail

OPENWRT_DIR="${1:?缺少 openwrt 源码目录}"
WITH_OPENCLASH="${2:-false}"
WITH_PASSWALL="${3:-false}"

OPENCLASH_REPO="${OPENCLASH_REPO:-https://github.com/vernesong/OpenClash.git}"
OPENCLASH_BRANCH="${OPENCLASH_BRANCH:-master}"

cd "$OPENWRT_DIR"

log() { echo -e "\n>>> $*"; }

# ---------------------------------------------------------------------------
# 1. 生成要追加进 .config 的开关
# ---------------------------------------------------------------------------
DOT_EXTRA="$OPENWRT_DIR/.extra-deps"
: > "$DOT_EXTRA"

write_cfg() {
    for p in "$@"; do
        echo "CONFIG_PACKAGE_$p=y" >> "$DOT_EXTRA"
    done
}

if [ "$WITH_OPENCLASH" = "true" ]; then
    # ruby / ruby-yaml 用于 OpenClash 处理配置；bash 是它 DEPENDS 里声明的。
    # 这几个都来自官方 feed，不需要额外源。
    write_cfg luci-app-openclash ruby ruby-yaml bash
fi

if [ "$WITH_PASSWALL" = "true" ]; then
    # 官方 immortalwrt/luci 21.02 自带的 PassWall 4.68，依赖全在官方 feed。
    write_cfg luci-app-passwall
fi

# 编插件时顺带补齐的三个基础包。
# 它们在 glmt3000.config 里本来就是 =y，单独列出来是为了防止某次 defconfig
# 因为依赖解析顺序把它们丢掉——之前就因此在最后的 package/install 阶段
# 报过 cannot find dependency lua-cjson / wget-ssl / luci-proto-ipv6。
if [ "$WITH_OPENCLASH" = "true" ] || [ "$WITH_PASSWALL" = "true" ]; then
    write_cfg lua-cjson wget-ssl luci-proto-ipv6
fi

# ---------------------------------------------------------------------------
# 2. 官方 feeds
# ---------------------------------------------------------------------------
# 用上游自带的 feeds.conf.default（packages / luci / routing / telephony）。
# feeds install -a 把官方包全部展开到 package/feeds，这样 glmt3000.config 里
# 那些 =y 的包才有符号可用，不会被 defconfig 当成「不存在」丢掉。
log "更新 feeds"
./scripts/feeds update -a

log "安装 feeds（官方全量）"
./scripts/feeds install -a

# ---------------------------------------------------------------------------
# 3. OpenClash：clone 后拷一个目录进 package/
# ---------------------------------------------------------------------------
# 不能挂进 feeds.conf：它仓库根目录还有 img/ 等非包目录，scripts/feeds
# 会把每个一级目录都当包解析，碰上没有 Makefile 的直接报错退出。
# clone 后删掉 .git，避免 feeds 把这里当成一个 git 源重复登记。
if [ "$WITH_OPENCLASH" = "true" ]; then
    log "引入 OpenClash"
    rm -rf /tmp/openclash-src
    git clone --depth=1 -b "$OPENCLASH_BRANCH" "$OPENCLASH_REPO" /tmp/openclash-src

    if [ ! -d /tmp/openclash-src/luci-app-openclash ]; then
        echo "ERROR: OpenClash 仓库中没有 luci-app-openclash 目录" >&2
        exit 1
    fi
    rm -rf /tmp/openclash-src/.git
    rm -rf package/luci-app-openclash
    cp -r /tmp/openclash-src/luci-app-openclash package/luci-app-openclash
    echo "  已放入 package/luci-app-openclash"

    # OpenClash 的 Build/Prepare 用 po2lmo 把 po 编成 lmo 语言包，
    # 这个 host 工具由 luci-base 的 host 构建提供（Host/Compile 里把
    # src/po2lmo 装到 bin/po2lmo）。OpenClash 自己的 Makefile 没有声明
    # 这层 build 依赖，并行编译时可能先跑到它，报 po2lmo: not found。
    # 补一行 PKG_BUILD_DEPENDS，保证 luci-base/host 先建好。
    sed -i '/^include \$(INCLUDE_DIR)\/package\.mk$/i PKG_BUILD_DEPENDS:=luci-base/host' \
        package/luci-app-openclash/Makefile
fi

# ---------------------------------------------------------------------------
# 4. 汇报
# ---------------------------------------------------------------------------
if [ -s "$DOT_EXTRA" ]; then
    log "追加到 .config 的包开关："
    sed -nE 's/^CONFIG_PACKAGE_(.+)=y$/    \1/p' "$DOT_EXTRA"
else
    log "未选择插件，只编基础固件"
fi

if [ -n "${GITHUB_ENV:-}" ]; then
    {
        echo "PLUGINS_OPENCLASH=$WITH_OPENCLASH"
        echo "PLUGINS_PASSWALL=$WITH_PASSWALL"
    } >> "$GITHUB_ENV"
fi
