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
GOLANG_REPO="${GOLANG_REPO:-https://github.com/kenzok8/golang.git}"
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

# 注意：不要写成 `[ ... ] && var=true`。脚本开头是 set -e，
# 条件为假时整条语句返回非 0，会被当成命令失败直接退出。
# 之前就是这样，WITH_PASSWALL=false 时后面的 install 全被跳过，
# 而飞书日志里只留一行空行，很隐蔽。
need_third_party=false
if [ "$WITH_OPENCLASH" = "true" ] || [ "$WITH_PASSWALL" = "true" ]; then
    need_third_party=true
fi

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

    # ---- 只 clone 不建索引 ----
    #
    # feeds update -a 会顺带扫描每个源建索引，而 small 源里有几个 Makefile
    # 在 21.02 上根本解析不了（dae / daed 要 bpf-headers，dns2socks-rust 要
    # rust/host），扫描它们会报 "ERROR: please fix feeds/small/xxx/Makefile"。
    # 更麻烦的是这会让整个 small 索引不完整，后面 feeds install 找不到包名，
    # 又因为 stderr 被吞掉，日志里只看到一片空行。
    #
    # 所以拆成两步：先 update 只拉源码（-i 之外的更新），
    # 裁掉不需要的目录，最后统一用 update -i 建一次干净的索引。
    log "拉取 feeds 源码并裁剪 small 源"
    # 先只把源码 clone 下来（此时不生成索引，扫描错误不会中断流程）
    ./scripts/feeds update -a || true

    keep_dirs=""
    if [ "$WITH_PASSWALL" = "true" ]; then
        keep_dirs="${PASSWALL_FEED_DIRS[*]}"
    fi

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

    # ---- 关键修复 1：替换 golang ----
    #
    # 21.02 自带的 golang 是 1.19.13，而现在的代理内核全都要求更高的 Go：
    #   geoview 0.2.8        go 1.25.0
    #   sing-box 1.15        go 1.25.5
    #   xray-core 26.10      go 1.27
    #   (官方 xray-core 1.8.3 也要 go 1.20)
    # Go 1.19 连 "go 1.25.0" 这种三段式版本号都不认，直接报
    #   invalid go version '1.25.0': must match format 1.23
    # 所以按 kenzok8/small README 的做法，换成 kenzok8/golang 打包的 Go。
    # 这个仓库的分支号就是 Go 版本号。xray-core 26.10 要求 go 1.27，
    # 所以取 1.27 分支（Go 1.27.3），同时满足其余包的下限要求。
    log "替换 golang 为 kenzok8/golang 的 ${GOLANG_BRANCH:-1.27} 分支"
    rm -rf feeds/packages/lang/golang
    git clone --depth=1 -b "${GOLANG_BRANCH:-1.27}" "$GOLANG_REPO" feeds/packages/lang/golang

    # ---- 关键修复 2：移除官方 feed 中与 small 冲突或已失效的包 ----
    #
    # 与 small 重名的包必须删掉官方版本，否则 feeds install 会优先选中官方的。
    # 官方这几个在 21.02 上都不可用：
    #   - xray-core 1.8.3 太旧，xray 26.x 才是 small 里的版本
    #   - v2ray-geodata 钉的 2023-12-02 geosite 已被 v2fly 删除，下载 404
    # 清理列表取自 kenzok8/small 的 README，按 21.02 实际情况裁剪过。
    log "移除官方 feed 中冲突的包"
    for p in net/alist net/adguardhome net/mosdns \
             net/xray-core net/v2ray-core net/v2ray-geodata \
             net/smartdns utils/v2dat; do
        if [ -d "feeds/packages/$p" ]; then
            rm -rf "feeds/packages/$p"
            echo "  移除 feeds/packages/$p"
        fi
    done
    if [ -d feeds/luci/applications/luci-app-mosdns ]; then
        rm -rf feeds/luci/applications/luci-app-mosdns
        echo "  移除 feeds/luci/applications/luci-app-mosdns"
    fi

    # ---- 关键修复 3：重建 feeds 索引 ----
    #
    # scripts/feeds 的 get_feed() 读的是 feeds/<name>.index 缓存文件，
    # 不是实时扫目录。删了目录、裁剪了 small 源之后必须重建索引，
    # 否则 install 仍会按旧索引命中已删除的路径。
    log "重建 feeds 索引"
    # 必须连 feeds/<name>.tmp 一起删。
    #
    # feeds/<name>.index 只是个软链，指向 feeds/<name>.tmp/.packageinfo。
    # 只删软链、留 .tmp 的话，update -i 里的 scan.mk 会认为缓存仍是最新的
    # （它按 .packageinfo-xxx 的依赖时间戳判断），直接跳过扫描，
    # 结果生成一个几乎空的索引。表现就是后面 feeds install 时满屏
    # "WARNING: has a dependency on 'xxx', which does not exist"，
    # 连 bash、lua-cjson 这种基础包都装不上。
    for d in feeds/*.index feeds/*.targetindex feeds/*.tmp; do
        if [ -e "$d" ]; then
            rm -rf "$d"
        fi
    done
    ./scripts/feeds update -i
    # 建完检查一下各源索引的大小，索引异常为空时早发现
    for idx in feeds/*.index; do
        if [ -f "$idx" ]; then
            echo "  $(basename "$idx"): $(wc -l < "$idx") 行"
        fi
    done

    log "安装选中的包"
    install_list=""
    if [ "$WITH_PASSWALL" = "true" ]; then
        install_list="$install_list luci-app-passwall chinadns-ng dns2socks ipt2socks microsocks tcping sing-box xray-core geoview v2ray-geodata v2ray-geoip v2ray-geosite"
    fi
    # OpenClash 用 ruby 处理配置，ruby / ruby-yaml 来自官方 packages feed，
    # 必须在索引重建之后再 install，否则 feeds 找不到它们。
    if [ "$WITH_OPENCLASH" = "true" ]; then
        install_list="$install_list ruby ruby-yaml"
    fi
    # 注意不要用 2>/dev/null 吞掉错误：feeds install 失败时只在 stderr 说明原因，
    # 吞掉之后日志里只剩空行，完全看不出问题在哪。
    for p in $install_list; do
        echo "  install $p"
        ./scripts/feeds install "$p" || echo "  !! 跳过 $p（源里没有该包名）"
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
