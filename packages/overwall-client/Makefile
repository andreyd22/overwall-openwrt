include $(TOPDIR)/rules.mk

PKG_NAME:=overwall-client
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Overwall

include $(INCLUDE_DIR)/package.mk

define Package/overwall-client
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=Overwall VPN router client
  URL:=https://overwall.online
  PKGARCH:=all
  DEPENDS:=+ucode +ucode-mod-fs +ucode-mod-uci +ucode-mod-ubus +curl +ca-bundle +resolveip +flock +coreutils-timeout +ip-full +nftables-json +kmod-nft-tproxy +kmod-wireguard +wireguard-tools +xray-core +uhttpd +qrencode
endef

define Package/overwall-client/description
  Manage Overwall and independent VLESS subscriptions and WireGuard profiles.
endef

define Build/Compile
endef

define Package/overwall-client/install
	$(INSTALL_DIR) $(1)/usr/share/ucode/overwall
	$(INSTALL_DATA) ./files/usr/share/overwall/*.uc $(1)/usr/share/ucode/overwall/
	$(INSTALL_DIR) $(1)/usr/bin $(1)/etc/init.d $(1)/usr/lib/overwall $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/usr/bin/overwall $(1)/usr/bin/
	$(INSTALL_BIN) ./files/etc/init.d/* $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/etc/uci-defaults/* $(1)/etc/uci-defaults/
	$(INSTALL_BIN) ./files/usr/lib/overwall/* $(1)/usr/lib/overwall/
endef

define Package/overwall-client/conffiles
/etc/overwall/
endef

define Package/overwall-client/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] && exit 0
umask 077
mkdir -p /etc/overwall /var/run/overwall
chmod 700 /etc/overwall /var/run/overwall
if [ -f /etc/uci-defaults/90-overwall ]; then
 sh /etc/uci-defaults/90-overwall
 rm /etc/uci-defaults/90-overwall
fi
/etc/init.d/overwall enable
/etc/init.d/overwall start
exit 0
endef

define Package/overwall-client/prerm
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] && exit 0
/usr/bin/overwall disconnect >/dev/null 2>&1 || exit 1
/etc/init.d/overwall stop
/etc/init.d/overwall disable
uci -q delete firewall.ow_boot_guard
uci commit firewall
exit 0
endef

$(eval $(call BuildPackage,overwall-client))
