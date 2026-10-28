#
# libyaml — 供 lyaml（Lua 的 YAML 绑定）使用的 C 库
#
# 背景：PassWall 26.x 拉入了 lyaml 依赖，而 lyaml 依赖 libyaml。
# openwrt-21.02 分支的 immortalwrt/packages 与 openwrt/packages 都没有
# libyaml（只有无关的 libyaml-cpp），因此在这里以源码包形式补上。
#
# Copyright (C) 2026
#
# This is free software, licensed under the GNU General Public License v2.

include $(TOPDIR)/rules.mk

PKG_NAME:=libyaml
PKG_VERSION:=0.2.5
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/yaml/libyaml/archive/refs/tags
PKG_HASH:=fa240dbf262be053f3898006d502d514936c818e422afdcf33921c63bed9bf2e
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)

PKG_MAINTAINER:=local
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_CPE_ID:=cpe:/a:yaml:libyaml

PKG_FIXUP:=autoreconf
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/libyaml
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=Fast YAML 1.1 parser and emitter library
  URL:=https://github.com/yaml/libyaml
endef

define Package/libyaml/description
  LibYAML is a YAML 1.1 parser and emitter written in C.
  Required by lyaml, which PassWall uses for its configuration.
endef

define Build/Configure
	$(call Build/Configure/Default, \
		--disable-static \
		--enable-shared \
	)
endef

define Package/libyaml/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libyaml-0.so.* $(1)/usr/lib/
endef

define Package/libyaml/dev
  $(call Package/libyaml/Default)
  SECTION:=devel
  CATEGORY:=Development
  TITLE+= (development)
  DEPENDS:=libyaml
endef

define Package/libyaml/dev/description
  Headers and static library for libyaml.
endef

define Package/libyaml/dev/install
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_INSTALL_DIR)/usr/include/yaml.h $(1)/usr/include/
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libyaml.so* $(1)/usr/lib/
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/include/yaml.h $(1)/usr/include/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libyaml.so* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,libyaml))
$(eval $(call BuildPackage,libyaml/dev))
