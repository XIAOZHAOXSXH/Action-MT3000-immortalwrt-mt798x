#!/usr/bin/env bash
#
# prepare-packages.sh —— 按 workflow 开关把 OpenClash / PassWall 编进固件
#
# 用法:
#   ./scripts/prepare-packages.sh <openwrt源码目录> <是否OpenClash> <是否PassWall>
#   例如: ./scripts/prepare-packages.sh openwrt true false
#
# 设计要点：
#   * 两个开关都为 false 时，完全不碰第三方源，产出的就是干净的官方固件。
#   * 选中的包名与它们的依赖写进 .extra-deps，由 workflow 拼到 .config 后面，
#     再统一 make defconfig，避免「先 defconfig 再 append 导致依赖被裁掉」的老问题。
#   * OpenClash 不通过 feeds 引入：其仓库根目录含 img/ 等非包目录，
#     scripts/feeds 会把它当成包去解析而报错。这里单独 clone，只链接单个目录。

set -euo pipefail

OPENWRT_DIR="${1:?缺少 openwrt 源码目录}"
WITH_OPENCLASH="${2:-false}"
WITH_PASSWALL="${3:-false}"

OPENCLASH_REPO="${OPENCLASH_REPO:-https://github.com/vernesong/OpenClash.git}"
OPENCLASH_BRANCH="${OPENCLASH_BRANCH:-master}"

cd "$OPENWRT_DIR"

log() { echo -e "\n>>> $*"; }

EXTRA_DEPS_FILE="$OPENWRT_DIR/.extra-deps"
: > "$EXTRA_DEPS_FILE"

# 写一个 PACKAGE 开关
add_pkg() { echo "CONFIG_PACKAGE_$1=y" >> "$EXTRA_DEPS_FILE"; }

need_feeds_update=false
[ "$WITH_OPENCLASH" = "true" ] && need_feeds_update=true
[ "$WITH_PASSWALL" = "true" ]  && need_feeds_update=true

# ---------------------------------------------------------------------------
# 0. 应用仓库自带的 feeds.conf（含 kenzok8/small）
# ---------------------------------------------------------------------------
if [ "$need_feeds_update" = "true" ]; then
    log "应用自定义 feeds.conf"
    cp -f "$GITHUB_WORKSPACE/feeds.conf" "$OPENWRT_DIR/feeds.conf"
fi

# ---------------------------------------------------------------------------
# 1. OpenClash
# ---------------------------------------------------------------------------
if [ "$WITH_OPENCLASH" = "true" ]; then
    log "启用 OpenClash"
    rm -rf /tmp/openclash-src
    git clone --depth=1 -b "$OPENCLASH_BRANCH" "$OPENCLASH_REPO" /tmp/openclash-src

    [ -d /tmp/openclash-src/luci-app-openclash ] || {
        echo "ERROR: OpenClash 仓库中没有 luci-app-openclash 目录" >&2
        exit 1
    }
    ln -sfn /tmp/openclash-src/luci-app-openclash package/luci-app-openclash

    # OpenClash 运行时要用 ruby 处理配置文件；两者都来自 official packages feed。
    # dnsmasq-full / kmod-tun 在基础配置里已经是 y，这里不再重复声明。
    add_pkg luci-app-openclash
    add_pkg ruby
    add_pkg ruby-yaml
fi

# ---------------------------------------------------------------------------
# 2. PassWall
# ---------------------------------------------------------------------------
if [ "$WITH_PASSWALL" = "true" ]; then
    log "启用 PassWall"

    add_pkg luci-app-passwall

    # 逐一列出的原因：PassWall 的依赖分散在 official feed 与 kenzok8/small 两处，
    # 显式写出来能让缺包在 defconfig 阶段立刻暴露，而不是编译到一半才失败。
    for p in \
        lyaml \
        chinadns-ng \
        dns2socks \
        ipt2socks \
        microsocks \
        tcping \
        sing-box \
        xray-core \
        geoview \
        v2ray-geodata \
        v2ray-geoip \
        v2ray-geosite
    do
        add_pkg "$p"
    done

    # PassWall 的配置子项，默认值看架构，这里显式打开常用的几项
    cat >> "$EXTRA_DEPS_FILE" <<'EOF'
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_SingBox=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Geoview=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_V2ray_Geodata=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Simple_Obfs=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Client=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_V2ray_Plugin=y
EOF
fi

# ---------------------------------------------------------------------------
# 3. 汇报
# ---------------------------------------------------------------------------
if [ -n "$(cat "$EXTRA_DEPS_FILE")" ]; then
    log "本次会额外编入的包："
    sed -E 's/^CONFIG_PACKAGE_//; s/=y$//' "$EXTRA_DEPS_FILE" | grep -E '^[a-z]' | sed 's/^/    /'
else
    log "未选择插件，只编基础固件"
fi

if [ -n "${GITHUB_ENV:-}" ]; then
    {
        echo "PLUGINS_OPENCLASH=$WITH_OPENCLASH"
        echo "PLUGINS_PASSWALL=$WITH_PASSWALL"
    } >> "$GITHUB_ENV"
fi
