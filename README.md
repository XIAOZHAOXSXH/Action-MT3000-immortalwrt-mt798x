# GL-MT3000 自编译 ImmortalWrt

给 GL.iNet GL-MT3000（MT7981）用的 ImmortalWrt 自动编译仓库。源码取 [hanwckf/immortalwrt-mt798x](https://github.com/hanwckf/immortalwrt-mt798x) 的 `openwrt-21.02` 分支——这个分支由 hanwckf 针对 MT798x 系列维护，MTK 无线驱动是闭源的 mt76 配套版本，比官方树里的开源驱动稳定得多。

`glmt3000.config` 是编译配置，改完推上去就会自动重新编译。

## 固件特性

- **默认管理地址 `192.168.8.1`**，掩码 `/24`
- LuCI 中文界面，Argon 主题
- dnsmasq-full（带 ipset / nftset / DNSSEC）
- 可选编入 OpenClash 或 PassWall，见下文
- 产物自动挂到 Release

## 编译开关

在 Actions 页面点 **Run workflow** 时有三个勾选项：

| 开关 | 说明 |
| --- | --- |
| `编译 OpenClash` | 勾上才编 OpenClash。会一并编入 `ruby`、`ruby-yaml` |
| `编译 PassWall` | 勾上才编 PassWall。会一并编入 sing-box、xray-core、hysteria、geoview 等 |
| `上传到 Release` | 默认开。关掉只留 Actions Artifacts（保留 30 天） |

两个插件开关都不勾时，产出的就是干净的官方包集合，体积最小。可以两个都勾，但注意两个都是透明代理类工具，同时开容易抢 dnsmasq 和流量转发规则，实际用只留一个。

除手动触发外，改动这几个路径也会自动触发编译：

```
glmt3000.config
feeds.conf
scripts/**
.github/workflows/build-mt3000.yml
```

## 目录结构

```
.
├── glmt3000.config                  # 编译配置（OpenWrt 的 .config）
├── feeds.conf                       # 上游 feeds + kenzok8/small 插件源
├── package/
│   ├── libyaml/                     # 补包：21.02 没有 libyaml
│   └── lyaml/                       # 补包：PassWall 依赖的 Lua YAML 绑定
├── scripts/
│   ├── prepare-packages.sh          # 按开关准备插件
│   └── set-default-lan.sh           # 改出厂 LAN 地址
└── .github/workflows/build-mt3000.yml
```

## 关于 `192.168.8.1`

大部分教程会让你改 `.config` 里的 `CONFIG_TARGET_PREINIT_IP`，但那只管 U-Boot 预初始化阶段的临时地址，也就是 failsafe 救援模式用的那个。真正决定首次启动后 `/etc/config/network` 内容的是源码里的 `package/base-files/files/bin/config_generate`，它在第一次 boot 时生成网络配置。

所以 `scripts/set-default-lan.sh` 直接改那个脚本：

```
lan) ipad=${ipaddr:-"192.168.1.1"} ;;   →   lan) ipad=${ipaddr:-"192.168.8.1"} ;;
netm=${netmask:-"255.255.255.0"}        →   保持不变
```

掩码的写法在不同版本里可能是 `255.255.255.0` 也可能是 `24`，脚本两种正则都覆盖了，并且改完会自检 `netm=` 那一行还在——掩码被静默删掉的话网段会退化成 /32，机器直接连不上。

`.config` 里的 `CONFIG_TARGET_PREINIT_IP` / `_BROADCAST` 也同步改成了 `192.168.8.1` / `192.168.8.255`，这样救援模式地址和正式地址一致。

想换别的网段就不用改代码，覆盖环境变量即可：

```bash
LAN_IP=10.0.0.1 LAN_MASK=255.255.255.0 LAN_PREFIX=24 ./scripts/set-default-lan.sh openwrt
```

## 关于两个补包

PassWall 26.x 的 `LUCI_DEPENDS` 里有 `+lyaml`，lyaml 又依赖 `libyaml`。但 `openwrt-21.02` 的 immortalwrt/packages 和 openwrt/packages 都没有 libyaml 这个包（只有不相干的 `libyaml-cpp`），上游的 lyaml 还依赖 `luarocks/host` 构建，在 21.02 的工具链下很容易挂。

所以这里自己补了两个包：

- `package/libyaml` —— libyaml 0.2.5 源码包，标准 autotools 构建
- `package/lyaml` —— lyaml 6.2.7，绕开 luarocks，直接用上游自带的 `build-aux/luke` 配合 host lua 编译

如果哪天上游 feed 补上了这两个包，删掉 `package/libyaml`、`package/lyaml` 即可，PassWall 会自动用 feed 里的版本。

## OpenClash 为什么没进 feeds.conf

OpenClash 仓库根目录除了 `luci-app-openclash`，还有 `img/` 这类纯图片目录。用 `src-git` 挂进 feeds 的话，`scripts/feeds` 会把每个一级目录都当包去解析，碰上没有 Makefile 的目录直接报错退出。

`scripts/prepare-packages.sh` 改成单独 clone，然后只把 `luci-app-openclash` 一个目录软链到 `package/` 下。

PassWall 那边用的 `kenzok8/small` 就没有这个问题，目录名和包名一一对应，可以直接进 `feeds.conf`。原版 `xiaorouji/openwrt-passwall` 仓库已经访问不了，kenzok8 是持续同步的镜像。

## 刷机

第一次从 GL.iNet 原厂固件切过来：

1. 断电，按住 reset 不放上电，进 U-Boot 的 recovery 页面（地址通常是 `192.168.1.1`）
2. 刷 `*factory.bin`

原厂 U-Boot 会校验厂商信息，直接 sysupgrade 原厂固件是刷不进的，必须走 recovery。

已经跑 ImmortalWrt 的：

- 保留配置升级：系统 → 备份/升级，选 `*sysupgrade.bin`
- 干净升级：解掉「保留配置」勾选

刷完等 2 分钟左右，浏览器打开 <http://192.168.8.1>，默认无密码，第一次进要设一个。

## 编译时间

首次编译大约 1.5～2 小时。仓库里配了 ccache 和 `dl` 目录缓存，后面只改配置的话通常能压到 30 分钟出头。

## 免责声明

自己用的固件，不保证兼容性和稳定性。刷机有变砖风险，MT3000 有 U-Boot recovery，只要不动 BL2 和 FIP 分区基本都能救回来。出事别找我。
