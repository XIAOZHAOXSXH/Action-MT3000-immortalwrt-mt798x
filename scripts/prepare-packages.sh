#!/usr/bin/env bash
#
# prepare-packages.sh —— 按 workflow 开关把 OpenClash / PassWall 编进固件
#
# 用法:
#   ./scripts/prepare-packages.sh <openwrt源码目录> <是否OpenClash> <是否PassWall>
#
# ── 为什么不能 `feeds install -a` ────────────────────────────────────────
# kenzok8/small 是一个「大杂烩」源，里面同时躺着适配 21.02 / 22.03 / 23.05 的包。
# 全量 install 之后 `include/scan.mk` 会把 feeds/small 下每个 Makefile 都扫进
# tmp/.config-package.in，其中：
#   * clashoo / nikki / momo / luci-app-homeproxy 依赖 firewall4、kmod-nft-*，
#     这些在 21.02（firewall3）里根本不存在；
#   * luci-app-passwall2 的 Iptables_Transparent_Proxy 会 select PACKAGE_iptables。
# 于是符号图里出现：
#     PACKAGE_coreutils  <-selected-  PACKAGE_luci-app-passwall
#     PACKAGE_luci-app-passwall       ->depends-> PACKAGE_iptables
#     PACKAGE_iptables   <-selected-  PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy
# 形成递归依赖环，Kconfig 解析时直接 Segmentation fault（make 报 Error 139）。
#
# 所以这里按白名单精确 install，让 feeds/small 里那些不相关的包不进入扫描。

set -euo pipefail

OPENWRT_DIR="${1:?缺少 openwrt 源码目录}"
WITH_OPENCLASH="${2:-false}"
WITH_PASSWALL="${3:-false}"

OPENCLASH_REPO="${OPENCLASH_REPO:-https://github.com/vernesong/OpenClash.git}"
OPENCLASH_BRANCH="${OPENCLASH_BRANCH:-master}"

cd "$OPENWRT_DIR"

log() { echo -e "\n>>> $*"; }

# ---------------------------------------------------------------------------
# 包清单
# ---------------------------------------------------------------------------
# PassWall 本体 + 它 LUCI_DEPENDS 里 21.02 feed 缺失、必须由 kenzok8/small 提供的部分。
# 其余依赖（coreutils / curl / ip-full / dnsmasq-full / luci-compat …）官方 feed 里都有，
# 由 make defconfig 自动补全，不需要列在这里。
PASSWALL_PKGS=(
    luci-app-passwall
    lyaml
    chinadns-ng
    dns2socks
    ipt2socks
    microsocks
    tcping
    sing-box
    xray-core
    geoview
    v2ray-geodata
    v2ray-geoip
    v2ray-geosite
)

# feeds 里实际存在的「源目录名」。
# v2ray-geoip / v2ray-geosite 是 v2ray-geodata 这一个 Makefile 里 BuildPackage 出来的
# 子包，目录名只有 v2ray-geodata，所以裁剪白名单要按目录名而不是包名来算。
PASSWALL_FEED_DIRS=(
    luci-app-passwall
    chinadns-ng
    dns2socks
    ipt2socks
    microsocks
    tcping
    sing-box
    xray-core
    geoview
    v2ray-geodata
)

need_third_party=false
[ "$WITH_OPENCLASH" = "true" ] && need_third_party=true
[ "$WITH_PASSWALL" = "true" ]  && need_third_party=true

# ---------------------------------------------------------------------------
# 1. 预置要追加进 .config 的开关
# ---------------------------------------------------------------------------
DOT_EXTRA="$OPENWRT_DIR/.extra-deps"
: > "$DOT_EXTRA"

if [ "$WITH_OPENCLASH" = "true" ]; then
    for p in luci-app-openclash ruby ruby-yaml; do
        echo "CONFIG_PACKAGE_$p=y" >> "$DOT_EXTRA"
    done
fi

if [ "$WITH_PASSWALL" = "true" ]; then
    for p in "${PASSWALL_PKGS[@]}"; do
        echo "CONFIG_PACKAGE_$p=y" >> "$DOT_EXTRA"
    done
    # 透明代理分支不在这里写死：两个分支都是
    # `default y if PACKAGE_firewall4` / `if ! PACKAGE_firewall4`，
    # 21.02 没有 firewall4，会自动落到 iptables 分支。
    # 手动指定反而容易与 passwall2 的同名符号打架。
fi

# ---------------------------------------------------------------------------
# 2. feeds
# ---------------------------------------------------------------------------
if [ "$need_third_party" = "true" ]; then
    log "应用自定义 feeds.conf"
    cp -f "$GITHUB_WORKSPACE/feeds.conf" "$OPENWRT_DIR/feeds.conf"

    log "更新 feeds"
    ./scripts/feeds update -a

    # ---- 关键修复：把 small 源里不需要的包从扫描范围里摘掉 ----
    #
    # scan.mk 会遍历 feeds/small 下所有目录，所以仅靠「install 时只装几个」
    # 是不够的 —— 那些 Makefile 依然在 feeds/small 里，依然会被扫进符号表。
    # 这里在 update 之后、install 之前，把白名单之外的目录删掉。
    log "裁剪 small 源，只保留本次需要的目录"
    keep_dirs=""
    [ "$WITH_PASSWALL" = "true" ]  && keep_dirs="$keep_dirs ${PASSWALL_FEED_DIRS[*]}"

    if [ -d feeds/small ]; then
        for d in feeds/small/*/; do
            name=$(basename "$d")
            case " $keep_dirs " in
                *" $name "*) : ;;                      # 白名单，保留
                *) rm -rf "$d" ;;                      # 其余全部移除
            esac
        done
        echo "  剩余目录：$(ls feeds/small 2>/dev/null | tr '\n' ' ')"
    fi

    log "安装选中的包"
    install_list=""
    [ "$WITH_PASSWALL" = "true" ] && install_list="luci-app-passwall chinadns-ng dns2socks ipt2socks microsocks tcping sing-box xray-core geoview v2ray-geodata v2ray-geoip v2ray-geosite"
    for p in $install_list; do
        ./scripts/feeds install "$p" 2>/dev/null || echo "  跳过 $p（源里没有该包名）"
    done
else
    log "未选择插件，使用官方 feeds"
    ./scripts/feeds update -a
    ./scripts/feeds install -a
fi

# ---------------------------------------------------------------------------
# 3. OpenClash：直接拷进 package/，不走 feeds
# ---------------------------------------------------------------------------
# OpenClash 仓库根目录含 img/ 等非包目录，用 src-git 挂进 feeds 会解析失败；
# 而 clone 出来的 .git 又会让 feeds 把整个 /tmp/openclash-src 登记成一个 git 源。
# 所以 clone 后删 .git，再把 luci-app-openclash 一个目录拷到 package/ 下，
# 它就会像本地包一样被 scan.mk 正常扫到。
if [ "$WITH_OPENCLASH" = "true" ]; then
    log "引入 OpenClash"
    rm -rf /tmp/openclash-src
    git clone --depth=1 -b "$OPENCLASH_BRANCH" "$OPENCLASH_REPO" /tmp/openclash-src

    [ -d /tmp/openclash-src/luci-app-openclash ] || {
        echo "ERROR: OpenClash 仓库中没有 luci-app-openclash 目录" >&2
        exit 1
    }
    rm -rf /tmp/openclash-src/.git
    rm -rf package/luci-app-openclash
    cp -r /tmp/openclash-src/luci-app-openclash package/luci-app-openclash
    echo "  已放入 package/luci-app-openclash"
fi

# ---------------------------------------------------------------------------
# 4. 汇报
# ---------------------------------------------------------------------------
if [ -s "$DOT_EXTRA" ]; then
    log "追加到 .config 的包开关："
    grep -E '^CONFIG_PACKAGE_' "$DOT_EXTRA" \
        | sed -E 's/^CONFIG_PACKAGE_//; s/=y$//' \
        | sed 's/^/    /'
else
    log "无额外包开关"
fi

if [ -n "${GITHUB_ENV:-}" ]; then
    {
        echo "PLUGINS_OPENCLASH=$WITH_OPENCLASH"
        echo "PLUGINS_PASSWALL=$WITH_PASSWALL"
    } >> "$GITHUB_ENV"
fi
