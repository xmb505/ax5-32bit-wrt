# Binary port of the proprietary QSDK WiFi stack, extracted from a running
# NWRT (QSDK 12.2, ipq60xx_32) install. vermagic matches our kernel
# (5.4.213 SMP preempt mod_unload ARMv7 p2v8), so the modules load as-is.

include $(TOPDIR)/rules.mk

PKG_NAME:=nwrt-wifi
PKG_VERSION:=7682368
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/nwrt-wifi
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Proprietary QSDK WiFi stack (qca_ol/umac, hostapd, firmware)
  DEPENDS:=@TARGET_ipq60xx_ipq60xx_32 \
	+kmod-cfg80211-linux +kmod-qca-nss-drv +libopenssl +libubus +libuci
endef

define Package/nwrt-wifi/description
  qca-wifi (qca_ol/umac/qdf), qca-hostapd, wpa_supplicant, cnss2,
  IPQ6018 firmware and the QCSDK init/config glue, extracted from a
  working NWRT build for Redmi AX5.
endef

define Build/Compile
endef

define Package/nwrt-wifi/extra_provides
	echo cfg80211.ko
endef

define Package/nwrt-wifi/install
	tar -xzf ./files/rootfs.tgz -C $(1)
endef

$(eval $(call BuildPackage,nwrt-wifi))
