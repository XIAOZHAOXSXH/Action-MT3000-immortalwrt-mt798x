#!/usr/bin/env bash
#
# set-default-lan.sh —— 把固件出厂的 LAN 地址改成 192.168.8.1/24
#
# OpenWrt 的出厂 LAN 地址并不是写死在某个配置文件里的，而是在首次启动时由
# package/base-files/files/bin/config_generate 生成 /etc/config/network。
# 所以必须在源码树里改这个脚本，改 .config 里的 CONFIG_TARGET_PREINIT_* 是不够的
# ——那两项只管 U-Boot 预初始化阶段的临时地址（failsafe 救援模式）。
#
# 这里两个地方都会处理：
#   1. config_generate 里 lucidef 给出的默认 ip 与掩码；
#   2. 若源码树里存在打包进镜像的 /etc/config/network，一并改写。
#
# 掩码可能是 255.255.255.0，也可能是 24 这种前缀长度，两种都能识别。

set -euo pipefail

OPENWRT_DIR="${1:-openwrt}"
LAN_IP="${LAN_IP:-192.168.8.1}"
LAN_MASK="${LAN_MASK:-255.255.255.0}"
LAN_PREFIX="${LAN_PREFIX:-24}"

CONFIG_GENERATE="$OPENWRT_DIR/package/base-files/files/bin/config_generate"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$CONFIG_GENERATE" ] || die "找不到 $CONFIG_GENERATE，源码树结构可能变了"

echo "==> 目标出厂 LAN 地址: ${LAN_IP}/${LAN_PREFIX} (${LAN_MASK})"

# --- 1. 改 config_generate 里的默认 ipaddr / netmask ------------------------
#
# 原始代码大致是：
#   case "$1" in
#       lan) ipad=${ipaddr:-"192.168.1.1"} ;;
#       *)   ipad=${ipaddr:-"192.168.$((addr_offset++)).1"} ;;
#   esac
#   netm=${netmask:-"255.255.255.0"}
#
# 有的版本写成 CIDR 形式，比如 ipad="192.168.1.1" 配 netm="24"，
# 也有的直接给 ipaddr="192.168.1.1/24"。统一用正则兜住。

before=$(grep -nE '192\.168\.[0-9]+\.1|netmask|prefix' "$CONFIG_GENERATE" || true)

# 1a. 默认 ip 地址：只有 lan 这一行是固定值，其余是 addr_offset 动态生成，不能动
sed -i -E "s#(lan\)[[:space:]]*ipad=\\\$\{ipaddr:-[\"']?)192\.168\.[0-9]+\.[0-9]+([\"']?\})#\1${LAN_IP}\2#g" "$CONFIG_GENERATE"

# 1b. 默认掩码：点分形式
sed -i -E "s#(netm=\\\$\{netmask:-[\"']?)255\.255\.255\.0([\"']?\})#\1${LAN_MASK}\2#g" "$CONFIG_GENERATE"

# 1c. 默认掩码：CIDR 前缀形式（如 netm=${netmask:-"24"}）
sed -i -E "s#(netm=\\\$\{netmask:-[\"']?)[0-9]{1,2}([\"']?\})#\1${LAN_PREFIX}\2#g" "$CONFIG_GENERATE"

after=$(grep -nE '192\.168\.[0-9]+\.1|netmask|prefix' "$CONFIG_GENERATE" || true)

echo "--- config_generate 改动前 ---"
echo "$before"
echo "--- config_generate 改动后 ---"
echo "$after"

# 自检：lan 那行必须已经指向新地址，且掩码位不能丢
if ! grep -qE "lan\)[[:space:]]*ipad=.*${LAN_IP//./\\.}" "$CONFIG_GENERATE"; then
    die "config_generate 里 lan 的默认 ip 没改成 ${LAN_IP}"
fi
if ! grep -qE "netm=\\\$\{netmask:-" "$CONFIG_GENERATE"; then
    die "config_generate 里的 netm 赋值不见了，掩码可能被误删"
fi

# --- 2. 若存在随镜像发布的 network 配置，也一并改写 ------------------------
NETWORK_FILES=$(find "$OPENWRT_DIR" -path '*/files/etc/config/network' -type f 2>/dev/null || true)
for f in $NETWORK_FILES; do
    echo "==> 改写 $f"
    sed -i -E "s#(option[[:space:]]+ipaddr[[:space:]]+['\"]?)192\.168\.[0-9]+\.[0-9]+(['\"]?)#\1${LAN_IP}\2#g" "$f"
    # 掩码：点分形式
    sed -i -E "s#(option[[:space:]]+netmask[[:space:]]+['\"]?)255\.255\.255\.0(['\"]?)#\1${LAN_MASK}\2#g" "$f"
    # 掩码：CIDR 形式
    sed -i -E "s#(option[[:space:]]+netmask[[:space:]]+['\"]?)[0-9]{1,2}(['\"]?)#\1${LAN_PREFIX}\2#g" "$f"
done

# --- 3. DHCP 下发网段 -------------------------------------------------------
# dnsmasq 的 dhcp_option 里也有网段，跟着 LAN 一起改
DHCP_FILES=$(find "$OPENWRT_DIR" -path '*/files/etc/config/dhcp' -type f 2>/dev/null || true)
for f in $DHCP_FILES; do
    echo "==> 改写 $f"
    sed -i -E "s#192\.168\.1\.#192.168.8.#g" "$f"
done

echo "==> 出厂 LAN 地址已设为 ${LAN_IP}/${LAN_PREFIX}"
