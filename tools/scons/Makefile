# Copyright (c) 2024 xmb505 / QSDK 12.2 modernization
# Licensed under the GNU General Public License v2.

include $(TOPDIR)/rules.mk

PKG_NAME:=SCons
PKG_VERSION:=4.6.0
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/source/s/scons/
PKG_HASH:=7db28958b188b800f803c287d0680cc3ac7c422ed0b1cf9895042c52567803ec

include $(INCLUDE_DIR)/host-build.mk

define Host/Compile
endef

# scons 4.x dropped setup.py in favor of pyproject.toml + hatchling.
# Install as plain Python package: copy SCons/ into site-packages, then
# wire a thin launcher that runs `python3 -m SCons.Script.Main`.
# PY_VER is computed once at parse time so we avoid shell-quoting inside recipe.
PY_VER := $(shell python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])')

define Host/Install
	cd $(HOST_BUILD_DIR) && \
		mkdir -p $(STAGING_DIR_HOST)/lib/python$(PY_VER)/site-packages && \
		cp -rp SCons $(STAGING_DIR_HOST)/lib/python$(PY_VER)/site-packages/SCons && \
		if [ -d SCons.egg-info ]; then \
			cp -rp SCons.egg-info $(STAGING_DIR_HOST)/lib/python$(PY_VER)/site-packages/ ; \
		fi && \
		install -d -m 0755 $(STAGING_DIR_HOST)/bin && \
		install -m 0755 $(TOPDIR)/tools/scons/scons.sh $(STAGING_DIR_HOST)/bin/scons
endef

$(eval $(call HostBuild))