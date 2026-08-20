# NWRT 原厂固件 WiFi 工作流程参考 (2026-08-20 实测)

> **目的**:对比 NWRT 出厂固件 vs 我们 v13 rootfs,搞清楚 NWRT 出厂 WiFi 是怎么 work 的,
> 把我们的 v14 rootfs 缺什么搞清楚。
>
> **方法**:把 NWRT QSDK 12.2 原厂固件 (`Nwrt-QSDK12.2-2024-04-13-ipq60xx-ipq60xx_32-redmi_ax5-squashfs-nand-factory.bin`)
> 通过 `ubiformat /dev/mtd19` 刷到 sys2,然后 `fw_setenv` 切换到 sys2 active,重启。
> 登录后查看所有关键 WiFi 配置文件。
>
> **更新 (15:00)**:在 sys1 (我们的 v13) 上把 wifi 跑起来了!关键修复:
> 1. 补 `/etc/config/qcacfg80211` 含 `enable='1'`
> 2. `cfg80211_config=1` 通过 insmod module param 传给 qca_ol
> 3. 完整 rmmod wifi modules → insmod 重新加载

---

## 1. NWRT 出厂的 WiFi 工作配置 (sys2,factory fresh)

### 1.1 `iwconfig` 实测输出

```
wifi0     no wireless extensions.
wifi1     no wireless extensions.
ath1      IEEE 802.11axg  ESSID:"Nwrt_2.4G"
          Mode:Master  Frequency:2.472 GHz  Access Point: 00:03:7F:12:6E:67
          Bit Rate:573.5 Mb/s   Tx-Power:20 dBm
          Encryption key:5FF4-3432-FD67-C182-29DA-85A0-6724-CB08   Security mode:restricted
ath0      IEEE 802.11axa  ESSID:"Nwrt_5G"
          Mode:Master  Frequency:5.745 GHz  Access Point: 00:03:7F:12:82:8B
          Bit Rate:1.201 Gb/s   Tx-Power:28 dBm
          Encryption key:8F16-491B-81DC-4B69-A048-9099-271B-EFAB   Security mode:restricted
```

| 项 | NWRT 出厂值 |
|---|---|
| 5G ath0 | Master, **5.745 GHz (chan 149)**, WPA2 设上 |
| 2.4G ath1 | Master, **2.472 GHz (chan 13)**, WPA2 设上 |
| Security mode | **restricted** (= WPA2-PSK 加密) |

### 1.2 `/etc/config/wireless` 关键内容

```uci
config wifi-device  wifi0
        option type     qcawificfg80211   # ⚠️ 必须用 qcawificfg80211,不是 qcawifi
        option wband    5g
        option hwmode   11axa
        option htmode   HT80
        option channel  149
        option country CN
        option disabled 0

config wifi-iface
        option device   wifi0
        option mode     ap
        option ifname   ath0                # ⚠️ 必须用 ath0/ath1,不是 wifi0/wifi1
        option ssid     Nwrt_5G
        option encryption psk2+ccmp        # ⚠️ 必须用 psk2+ccmp,不是 sae mixed
        option key '12345678'
        option disabled 0
```

### 1.3 `/var/run/hostapd-ath0.conf` 关键内容

```
driver=nl80211                  # ⚠️ hostapd 用 nl80211,不是 atheros
interface=ath0
channel=149
ieee80211ac=1
ieee80211n=1
ieee80211ax=1
he_oper_chwidth=1
he_oper_centr_freq_seg0_idx=155
ht_capab=[LDPC][SMPS-DYNAMIC]...
vht_capab=[MAX-MPDU-11454]...
hw_mode=a
wmm_enabled=1
wpa=2                           # ⚠️ WPA2 设上
wpa_passphrase=12345678
wpa_pairwise=CCMP 
wpa_key_mgmt=WPA-PSK
ssid=Nwrt_5G
bridge=br-lan
ieee80211w=0
ctrl_interface=/var/run/hostapd-wifi0
```

**关键**:hostapd 走 **`driver=nl80211`** 路径,不是 atheros!ACFG 驱动在 WPA 模式下内部 wrapper 成 nl80211 兼容接口!

---

## 2. 我之前的错误总结

我之前一直用 **`type qcawifi`** (这是 qcawifi.sh 的 fallback) 而不是 **`type qcawificfg80211`**,因为 v9 提取时**漏掉了 `qcawificfg80211.sh` 246KB 完整脚本**。结果是 wifi up 跑空路径,driver 状态机半残。

修正:**wireless config 必须用 `type qcawificfg80211`**(配合 `/lib/wifi/qcawificfg80211.sh` 246KB 完整脚本)。

---

## 3. NWRT 出厂 rootfs 必需文件清单 (v14 修补)

下面这些文件**必须**在 rootfs 里,否则 WiFi 不 work:

### 3.1 核心 wifi 脚本

| 源 (NWRT factory) | 目标 | 大小 | 用途 |
|---|---|---|---|
| `/lib/wifi/qcawificfg80211.sh` | 同 | 246KB | **CFG80211 路径 wifi up** (主路径) |
| `/lib/wifi/qcawifi.sh` | 同 | 148KB | ACFG 路径 fallback |
| `/lib/wifi/hostapd.sh` | 同 | 85KB | hostapd_setup_vif 等 |
| `/lib/wifi/wpa_supplicant.sh` | 同 | 18KB | wpa_supplicant_setup_vif |
| `/lib/wifi/qca-wifi-modules` | 同 | <1KB | 模块加载列表 |
| `/lib/wifi/.first_time_boot` | 同 | 0 bytes | fast boot 触发标志(空文件) |
| `/lib/wifi/qcawifi_countrycode.txt` | 同 | <2KB | 频道配置 |
| `/lib/wifi/wifi-utils.sh` | 同 | <2KB | 通用工具函数 |
| `/lib/wifi/iface_mgr.sh` | 同 | 12KB | iface manager |
| `/lib/wifi/launch_vap.sh` | 同 | <2KB | Fast boot VAP 启动 |
| `/lib/wifi/wps-*` (3 个) | 同 | ~20KB | WPS 流程 |
| `/lib/wifi/qcacommands_*.xml` (3 个) | 同 | ~80KB | QCA 命令定义 |
| `/lib/wifi/dpp-*` | 同 | ~10KB | DPP 流程 |
| `/lib/wifi/qwrap.sh` | 同 | 8KB | 无线回程 |
| `/lib/wifi/debug/*` | 同 | <2KB | 调试脚本 |
| `/lib/wifi/tools_config` | 同 | <1KB | 工具配置 |

### 3.2 wifi 用户态工具

| 源 | 目标 | 大小 | 用途 |
|---|---|---|---|
| `/usr/sbin/wifi_hw_mode` | 同 | 9KB | 硬件模式管理 |
| `/usr/sbin/wifi_try` | 同 | 6KB | wifi 配置尝试 |
| `/usr/sbin/wifistats` | 同 | 8KB | wifi 统计 |
| `/usr/sbin/wlanfw-upgrade.sh` | 同 | 6KB | firmware 升级 |
| `/usr/sbin/wifitool` | 同 | 123KB | 无线 ioctl 工具 |
| `/usr/sbin/wlanconfig` | 同 | 82KB | VAP 管理 |
| `/usr/sbin/acfg_tool` | 同 | 96KB | **ACFG API 主入口** |
| `/usr/sbin/cfg80211tool` | 同 | 2.6KB | CFG80211 命令工具 |
| `/usr/sbin/cfg80211tool.1` | 同 | 72KB | **cfg80211tool 主 binary** |
| `/usr/sbin/cfg80211tool_mesh` | symlink | - | mesh |
| `/usr/sbin/hostapd` | 同 | 2.4MB | **hostapd 主 binary** (走 nl80211) |
| `/usr/sbin/hostapd_cli` | 同 | 86KB | hostapd 控制 |
| `/usr/sbin/hostapd-macsec` | 同 | 2.2MB | hostapd macsec 版本 |
| `/usr/sbin/wpa_supplicant` | 同 | 3.2MB | **wpa_supplicant 主 binary** |
| `/usr/sbin/wpa_supplicant-macsec` | 同 | 3.0MB | wpa_supplicant macsec |
| `/usr/sbin/wpa_cli` | 同 | 140KB | wpa_supplicant 控制 |
| `/usr/sbin/hostapd_cli` | symlink | - | - |
| `/usr/sbin/hapd` | shell wrapper | <1KB | QCA 控制 wrapper |

### 3.3 init.d 服务

| 源 | 目标 | START | 用途 |
|---|---|---|---|
| `/etc/init.d/qca-acfg` | 同 | 10 | acfg event 监听 |
| `/etc/init.d/qcawifi-config-cmd` | 同 | 11 | wifi config 生成 |
| `/etc/init.d/qca-hostapd` | 同 | 13 | hostapd global |
| `/etc/init.d/qca-wpa-supplicant` | 同 | 13 | wpa_supplicant global |
| `/etc/init.d/wifi_fw_done` | 同 | - | wifi firmware mount |
| `/etc/init.d/wifi_fw_mount` | 同 | - | wifi firmware ready |
| `/etc/init.d/hostapd_cli` | 同 | - | hostapd_cli daemon |

### 3.4 ini 配置 (Fast Boot 关键)

| 源 | 目标 | 大小 | 用途 |
|---|---|---|---|
| `/ini/global.ini` | 同 | 5.6KB | 全局 ini |
| `/ini/QCA6018.ini` | 同 | 74B | 板卡 ini (binary,只读权限) |
| `/ini/internal/global_i.ini` | 同 | 3KB | **关键**:`fast_boot_vap_mode=1` |
| `/ini/internal/QCA6018_i.ini` | 同 | 3.5KB | QCA6018 datapath config |
| `/ini/internal/QCA8074_i.ini` | 同 | 3.4KB | 其他 chip 的 ini |
| `/ini/internal/QCA9574_i.ini` | 同 | 3KB | 其他 chip 的 ini |
| `/ini/internal/QCN6122_i.ini` | 同 | 3KB | 其他 chip 的 ini |
| `/ini/internal/QCN9000_i.ini` | 同 | 3.5KB | 其他 chip 的 ini |
| `/ini/internal/QCN9160_i.ini` | 同 | 3KB | 其他 chip 的 ini |
| `/ini/internal/QCN9224_i.ini` | 同 | 6KB | 其他 chip 的 ini |
| `/ini/internal/AR900B_i.ini` | 同 | <1KB | 其他 chip 的 ini |
| `/ini/internal/QCA5018_i.ini` | 同 | 3.6KB | 其他 chip 的 ini |
| `/ini/internal/QCA5332_i.ini` | 同 | 4KB | 其他 chip 的 ini |
| `/ini/internal/QCA6290_i.ini` | 同 | 1.8KB | 其他 chip 的 ini |
| `/ini/internal/QCA8074V2_i.ini` | 同 | 4.4KB | 其他 chip 的 ini |

**关键设置**:`/ini/internal/global_i.ini` 里 **`fast_boot_vap_mode=1`**!这一行让 boot 后 wifi 自动跑 fast boot VAP 创建!

### 3.5 缺失的库 (实文件,不是软链接)

| 源 | 目标 | 大小 |
|---|---|---|
| `/usr/lib/libnettle.so.8.4` | 同 | 282KB |
| `/usr/lib/libhogweed.so.6.4` | 同 | 241KB |

### 3.6 /etc 关键配置

| 源 | 目标 |
|---|---|
| `/etc/config/wireless` | NWRT 出厂完整版 |
| `/etc/dropbear/authorized_keys` | 我的开发机 ed25519 公钥 |
| `/etc/fw_env.config` | `/dev/mtd6 0x0 0x10000 0x20000` |

---

## 4. NWRT 出厂 boot 流程 (实测)

按时间顺序:

1. **S00wifi_fw_mount** — 把 IPQ6018 wifi firmware 挂到 `/lib/firmware`
2. **S00load_cnss2** — cnss2 driver (WLAN 协处理器平台驱动)
3. **S10qca-acfg** — 启动 `acfg_tool -e -s` 监听 ACFG 事件
4. **S11qcawifi-config-cmd** — `insmod` wifi modules + 跑 `/sbin/wifi config` 生成默认 wireless config
5. **S13qca-hostapd** — 启动空 global hostapd (`-g /var/run/hostapd/global`)
6. **S13qca-wpa-supplicant** — 启动空 global wpa_supplicant
7. **S19firewall** — 防火墙
8. **S19dnsmasq** — DHCP server (`udp 0.0.0.0:67`)
9. **S20network** — ubus 网络管理 (会触发 `/sbin/wifi reload_legacy` 触发 wifi up)

### 关键:fast boot VAP

当 `fast_boot_vap_mode=1` (在 `global_i.ini`), boot 时 wifi_fw_done 触发 `launch_vap.sh`:
- `/lib/wifi/launch_vap.sh` source `/lib/wifi/qcawificfg80211.sh`
- `get_vap_mode` 返回 1 (所有条件满足)
- 跑 `post_load_qcawificfg80211` + `post_detect_qcawificfg80211`
- **自动调用 `/sbin/wifi event_reload_legacy wifi0`** —— 触发 `enable_qcawificfg80211 wifi0`

### `enable_qcawificfg80211` 流程

1. `load_qcawifi` — insmod wifi_3_0 等
2. `start_recovery_daemon` — `acfg_tool -e -s`
3. **每个 vif 调 `hostapd_setup_vif "$vif" nl80211 no_nconfig`**(注意:**`nl80211`** 不是 atheros!)
4. hostapd_setup_vif 写 `driver=nl80211` conf + WPA 配置
5. `wpa_cli -g $WPAD_VARRUN/hostapd/global raw ADD bss_config=$ifname:...`

### WPA 怎么 work

**ACFG driver 在 WPA 模式下内部 wrapper 暴露 nl80211 兼容接口!**`wpa_supplicant` 的 nl80211 netlink cmd 调用 driver 内部转成 ACFG ioctl。所以 driver **同时支持 nl80211 和 ACFG**——只是不同 mode。

**`qcawificfg80211.sh` 路径走 nl80211** (CFG80211 标准路径),**`qcawifi.sh` 路径走 ACFG 私有**。`type qcawificfg80211` 是 NWRT 默认配置。

---

## 5. 这次实测对比总结

| 维度 | 我们的 v9/v13 | NWRT 出厂 (sys2) |
|---|---|---|
| `wireless.type` | ❌ qcawifi(我改的) | ✅ **qcawificfg80211** |
| `ifname` | ❌ ath0/ath1 | ✅ ath0/ath1 |
| `encryption` | ❌ 写 psk2 但没生效 | ✅ psk2+ccmp 真生效 |
| `/lib/wifi/qcawificfg80211.sh` | ❌ 空壳 (246KB) | ✅ 246KB 完整 |
| `/lib/wifi/.first_time_boot` | ❌ 不存在 | ✅ 0字节空文件 |
| `/ini/internal/global_i.ini` | ❌ 没刷 | ✅ 有,fast_boot_vap_mode=1 |
| `/ini/internal/QCA6018_i.ini` | ❌ 没刷 | ✅ 有 |
| `/usr/lib/libnettle.so.8.4` | ❌ 没刷 | ✅ 282KB |
| `/usr/lib/libhogweed.so.6.4` | ❌ 没刷 | ✅ 241KB |
| `/usr/sbin/wifi_hw_mode` 等 | ❌ 漏装 | ✅ 装 |
| `acfg_tool` driver mode | ACFG-only | **ACFG + nl80211 wrapper** |
| `hostapd` driver | nl80211 (无法 ACFG) | nl80211 (driver 内部 ACFG wrapper) |
| 5G channel | ✅ chan 149 | ✅ chan 149 |
| 2.4G channel | ⚠️ chan 6 (driver 自选) | ✅ chan 13 (配置指定) |
| WPA2 Encryption key | ❌ off | ✅ on |
| 5G SSID 广播 | ✅ | ✅ |
| 2.4G SSID 广播 | ✅ | ✅ |
| Phone 能关联 | ❌ 开放网络 + 无 hostapd | ✅ WPA2 + hostapd |
| Phone 能拿 IP | ⚠️ 可能 | ✅ |

---

## 6. v14 rootfs 完整修补步骤

要做出完美 v14 rootfs,需要把这些**全部**塞进 v14 squashfs:

1. 从 NWRT factory bin 7z 解开 (我之前已经解到 `/tmp/nwrt-v8-compare/`)
2. **完全替换** rootfs 文件树(不只是 wifi 部分),保留我们精简的:
   - `/usr/lib/opkg/info/` 我们的精简版本(只装必要包)
   - `/etc/config/` 我们的精简配置(只留 wifi/network/firewall/dhcp/wireless)
   - LuCI 我们的精简版本(避免加载过重)
3. **加回**所有缺失文件:
   - 全部 wifi 脚本(qcawificfg80211.sh + hostapd.sh + wpa_supplicant.sh + ...)
   - 全部 ini 文件(/ini/global.ini + /ini/QCA6018.ini + /ini/internal/*_i.ini)
   - 全部 wifi 工具(wifi_hw_mode, wifi_try, wifistats, wlanfw-upgrade.sh, wifitool)
   - 全部 init.d 服务(qca-acfg, qcawifi-config-cmd, qca-hostapd, qca-wpa-supplicant, wifi_fw_done, wifi_fw_mount)
   - libnettle/hogweed 实文件(不是空软链)
   - `/lib/wifi/.first_time_boot` 空文件
4. **保留** NWRT 原版无线驱动 firmware (Q6 segments + IPQ6018 caldata)
5. **打包** squashfs (xz 压缩)
6. **ubiformat** 到 mtd19, fw_setenv 切换

**预期 v14 rootfs 大小**: 26-28MB (NWRT 出厂 27MB rootfs)。

---

## 7. 操作记录 (2026-08-20)

### 7.1 NWRT 出厂固件刷 sys2

```bash
# 在 sys1 (我们的 v13 修改版) 上:
scp -O Nwrt-QSDK12.2-2024-04-13-ipq60xx-ipq60xx_32-redmi_ax5-squashfs-nand-factory.bin root@192.168.1.1:/tmp

ssh root@192.168.1.1
ubiformat /dev/mtd19 -f /tmp/Nwrt-QSDK12.2-2024-04-13-ipq60xx-ipq60xx_32-redmi_ax5-squashfs-nand-factory.bin
fw_setenv flag_boot_rootfs 1
fw_setenv flag_try_sys1_failed 1
fw_setenv flag_try_sys2_failed 0
reboot
```

### 7.2 切回 sys1 (我们的 v13)

```bash
ssh root@192.168.1.1
fw_setenv flag_boot_rootfs 0
fw_setenv flag_try_sys1_failed 0
fw_setenv flag_try_sys2_failed 1
reboot
```

(注意:NWRT 默认 root 没密码,我设了 `password`)

### 7.3 sys1 上让 WiFi 真正跑起来的关键修复

关键问题:sys1 v13 rootfs 缺这些,导致 wifi up 失败:

1. **`/etc/config/qcacfg80211`** (5 行) — qcawificfg80211.sh 的 gate,缺这个走 qcawifi 路径

2. **`cfg80211_config=1` module param** — driver 必须用这个参数 insmod 才走 cfg80211 模式

3. wifi modules reload 顺序:
```bash
# 必须先 rmmod 旧模块 (busybox modprobe 不支持 -r,用 rmmod)
rmmod monitor
rmmod ath_pktlog
rmmod wifi_3_0
rmmod qca_ol
rmmod umac
rmmod qdf
rmmod mem_manager

# 再 insmod 带上 cfg80211_config=1
insmod mem_manager
insmod qdf
insmod umac
insmod qca_ol cfg80211_config=1
insmod wifi_3_0
insmod monitor
insmod ath_pktlog

# 之后 wifi up + hostapd 才能接管 BSS
hostapd -g /var/run/hostapd/global -B -P /var/run/hostapd-global.pid
/sbin/wifi up
```

### 7.4 sys1 v13 rootfs 当前 WiFi 状态 (15:00 实测)

```
ath0 IEEE 802.11ac ESSID:"Nwrt_5G"
     Mode:Master Frequency:5.745 GHz Access Point:00:03:7F:12:1A:FB
     Encryption key:6E34-C634-8A8D-2084-A22D-2D73-C21E-652B Security mode:restricted

ath1 IEEE 802.11ng ESSID:"Nwrt_2.4G"
     Mode:Master Frequency:2.472 GHz Access Point:00:03:7F:12:B6:E7
     Encryption key:6821-6C4D-6A41-13D8-8974-B6DF-436B-A28A Security mode:restricted
```

✅ WPA2 PSK 设上,5G chan 149,2.4G chan 13,br-lan 集成 ath0/ath1/eth0-2。

**v14 rootfs 必须包含所有这些修复 + 自动 reload 序列 + boot 时跑 wifi up 的脚本**。