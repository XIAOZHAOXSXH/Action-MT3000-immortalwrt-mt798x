#
# lyaml — libyaml 的 Lua 绑定
#
# 背景：PassWall 26.x 的 LUCI_DEPENDS 里包含 +lyaml。上游 immortalwrt/packages
# 提供的 lyaml 使用 `luarocks make` 构建，并依赖 `luarocks/host`；在 openwrt-21.02
# 的工具链组合下这条链路很脆（host luarocks 与目标 lua 的 rockspec 解析经常失败）。
#
# 这里改用 lyaml 自带的 `build-aux/luke` 构建脚本直接编译：
#   * luke 是一个纯 Lua 的构建器，用 host lua 执行，不需要 luarocks；
#   * 需要目标 libyaml 的头文件与库（由 package/libyaml 提供）。
# 这样 21.02 上也有了可用的 lyaml，PassWall 依赖得以闭合。
#
# Copyright (C) 2026
#
# This is free software, licensed under the GNU General Public License v2.

include $(TOPDIR)/rules.mk

PKG_NAME:=lyaml
PKG_VERSION:=6.2.7
PKG_RELEASE:=2

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/gvvaughan/lyaml/archive/refs/tags
PKG_SOURCE_VERSION:=v$(PKG_VERSION)
PKG_HASH:=9bb489cefae48b150d66f6bab4141d8d5831fcb7465bfc52a9845fa01efc63b0
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)

PKG_MAINTAINER:=local
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=lua/host

include $(INCLUDE_DIR)/package.mk

define Package/lyaml
  SUBMENU:=Lua
  SECTION:=lang
  CATEGORY:=Languages
  TITLE:=Lua lib-yaml bindings
  URL:=https://github.com/gvvaughan/lyaml
  DEPENDS:=+lua +libyaml
endef

define Package/lyaml/description
  Lua bindings for libyaml. Used by luci-app-passwall.
endef

TARGET_CFLAGS += -I$(STAGING_DIR)/usr/include

# luke 用 host lua 跑；这里显式给它目标平台的头文件与库路径。
define Build/Compile
	cd $(PKG_BUILD_DIR) && \
	LUA=$(STAGING_DIR_HOSTPKG)/bin/lua \
	CFLAGS="$(TARGET_CFLAGS) $(TARGET_CPPFLAGS) $(FPIC)" \
	LDFLAGS="$(TARGET_LDFLAGS)" \
	CC="$(TARGET_CC)" \
	LD="$(TARGET_CC)" \
	YAML_DIR=$(STAGING_DIR)/usr \
	YAML_INCDIR=$(STAGING_DIR)/usr/include \
	YAML_LIBDIR=$(STAGING_DIR)/usr/lib \
	$(STAGING_DIR_HOSTPKG)/bin/lua build-aux/luke \
		build \
		PREFIX=/usr \
		package=lyaml \
		version=$(PKG_VERSION) \
		LIB_EXTENSION=so \
		OBJ_EXTENSION=o \
		LUA_DIR=$(STAGING_DIR)/usr/share/lua/5.1 \
		LUA_INCDIR=$(STAGING_DIR)/usr/include
endef

define Package/lyaml/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/lyaml
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/lib/yaml.so $(1)/usr/lib/lua/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/lib/lyaml/*.lua $(1)/usr/lib/lua/lyaml/
endef

$(eval $(call BuildPackage,lyaml))
