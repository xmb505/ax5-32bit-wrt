# AX5 (IPQ6018, NWRT 32-bit) WiFi 实现详解

> **目标读者**:之后想改 WiFi 配置 / 加 SSID / 改密码 / 改频道 / 加 hostapd 扩展 / 重启 wifi 的开发者
>
> **环境**: NWRT QSDK 12.2, kernel 5.4.213, armv7l, ACFG + nl80211 混合 driver
>
> **SSID/密码**: Nwrt_5G / Nwrt_2.4G, password `12345678`, 5G chan 149, 2.4G chan 13

---

## 1. WiFi 系统架构图

```
┌─────────────────────────────────────────────────────────────┐
│                         用户态 (userspace)                       │
├─────────────────────────────────────────────────────────────┤
│  /sbin/wifi                  ← OpenWrt 标准 wifi 控制脚本      │
│  ├─ wireless config (uci)                                     │
│  ├─ wifi up/down/reload/status                                │
│  │                                                              │
│  └─ 调 DRIVERS="qcawifi"  → qcawifi.sh + qcawificfg80211.sh   │
│      │                                                          │
│      ├─ load_qcawificfg80211 (master mode insmod)              │
│      ├─ enable_qcawificfg80211 wifi0                           │
│      │   ├─ load wifi modules (mem_manager → qca_ol + cfg80211_config=1) │
│      │   ├─ start_recovery_daemon (acfg_tool -e -s)            │
│      │   ├─ iwconfig wifi0 channel 149                          │
│      │   ├─ hostapd_setup_vif ath0 nl80211 (写 conf)          │
│      │   │   └─ driver create ath0 VAP                          │
│      │   │       (-cfg80211 flag accepted)                     │
│      │   └─ wpa_cli raw ADD bss_config=ath0:conf (hostapd)    │
│      │                                                          │
│      └─ post_qcawificfg80211 wifi0                             │
│                                                                │
│  /usr/sbin/hostapd -g /var/run/hostapd/global -B   (空 global) │
│  /usr/sbin/wpa_supplicant -g /var/run/wpa_supplicantglobal -B│
│                                                                │
│  /usr/sbin/acfg_tool (916 API)                                │
│  /usr/sbin/wlanconfig (ath0/1 创建)                          │
│  /usr/sbin/iwconfig (legacy channel 设置)                    │
│  /usr/sbin/wifitool /usr/sbin/cfg80211tool.1                  │
├─────────────────────────────────────────────────────────────┤
│                       内核态 (kernel)                          │
├─────────────────────────────────────────────────────────────┤
│  /sys/class/ieee80211/phy0/, phy1/    (cfg80211 master phs)  │
│  /sys/class/net/wifi0/, wifi1/        (radio netdevs)        │
│  /sys/class/net/ath0/, ath1/          (AP VAP netdevs)         │
│                                                                │
│  内核模块 (按依赖):                                            │
│  mem_manager → qdf → umac → qca_ol (cfg80211_config=1)       │
│                       ↓                                          │
│              wifi_3_0 (master mode 注册 cfg80211)              │
│              monitor (monitor-only 模式)                       │
│              ath_pktlog                                         │
│                                                                │
│  cnss-daemon (QMI service 与 WCSS 通信)                      │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 关键文件路径速查

### 2.1 用户态配置

| 文件 | 作用 | 修改方式 |
|---|---|---|
| `/etc/config/wireless` | WiFi 主配置 (uci) | `uci set wireless.wifi0.X=Y; uci commit wireless` |
| `/etc/config/network` | 网络接口 (lan, wan) | 同上 |
| `/etc/config/dhcp` | DHCP 配置 | `uci set dhcp.lan.X=Y; uci commit dhcp` |
| `/etc/config/firewall` | 防火墙 (input/forward/output) | uci |
| `/etc/config/qcacfg80211` | **关键** - qcawificfg80211 路径开关 | 必须存在 `option enable '1'` |
| `/etc/config/wireless` 中 `type` | wifi0/wifi1 type | **必须 `qcawificfg80211`** |
| `/etc/fw_env.config` | U-Boot env 设备路径 | `echo "/dev/mtd6 0x0 0x10000 0x20000" > /etc/fw_env.config` |
| `/etc/dropbear/authorized_keys` | SSH 公钥 | 添加 `ssh-ed25519 ...` |

### 2.2 /ini 配置 (driver FW ini)

| 文件 | 作用 |
|---|---|
| `/ini/global.ini` | 全局 driver 配置 (`cfg80211_config=0/1`) |
| `/ini/QCA6018.ini` | AX5 board 文件 |
| `/ini/internal/global_i.ini` | **关键** - `fast_boot_vap_mode=1` 触发 boot 自动 wifi up |
| `/ini/internal/QCA6018_i.ini` | QCA6018 datapath config |

`load_qcawifi()` 每次 wifi up 时都会 `cp /cfg/default/ini/global.ini /ini/global.ini` 重置 ini。修改要在 `/cfg/default/ini/global.ini` 里。

### 2.3 WiFi 脚本

| 文件 | 作用 |
|---|---|
| `/lib/wifi/qcawificfg80211.sh` | **主要 wifi up 路径 (CFG80211)** (246KB) |
| `/lib/wifi/qcawifi.sh` | fallback ACFG 路径 (148KB) |
| `/lib/wifi/hostapd.sh` | `hostapd_setup_vif` 函数 (85KB) |
| `/lib/wifi/wpa_supplicant.sh` | `wpa_supplicant_setup_vif` |
| `/lib/wifi/launch_vap.sh` | fast boot VAP 自动创建 |
| `/lib/wifi/.first_time_boot` | **空文件** - fast boot trigger 标志 |

### 2.4 init.d

| 文件 | START | 作用 |
|---|---|---|
| `/etc/init.d/load_cnss2` | 00 | insmod cnss2 driver (WLAN 协处理器) |
| `/etc/init.d/wifi_fw_mount` | 00 | 挂载 IPQ6018 wifi firmware |
| `/etc/init.d/wifi_fw_done` | 96 | 完成 wifi firmware mount,检查 soc_model |
| `/etc/init.d/qca-acfg` | 10 | 启动 `acfg_tool -e -s` 监听事件 |
| `/etc/init.d/qcawifi-config-cmd` | 11 | boot_dependency + `/sbin/wifi config` 生成 wireless config |
| `/etc/init.d/qca-hostapd` | 13 | global hostapd (`-g /var/run/hostapd/global`) |
| `/etc/init.d/qca-wpa-supplicant` | 13 | global wpa_supplicant |
| `/etc/init.d/network` | 20 | ubus 触发 `/sbin/wifi reload` |

### 2.5 运行时关键路径

| 路径 | 作用 |
|---|---|
| `/var/run/wifilock` | wifi up 互斥锁 (脚本顺序) |
| `/var/run/hostapd/global` | hostapd global control socket |
| `/var/run/hostapd-wifi0.conf` | ath0 BSS 配置 (driver=atheros) |
| `/var/run/hostapd-ath0.conf` | ath0 BSS 配置 (driver=atheros) |
| `/var/run/wpa_supplicantglobal` | wpa_supplicant global |
| `/tmp/wifi_load_done` | boot wifi 阶段完成标志 |
| `/tmp/.wifi-config-done` | qcawifi-config-cmd 完成标志 |

---

## 3. WiFi 完整启动流程 (从 reboot 到 WPA2 ready)

```
[boot]
  ├─ /etc/preinit
  ├─ /etc/init.d/rcS → /etc/rc.d/S* 顺序执行
  │
  ├─ S00load_cnss2      → insmod ipq_cnss2 (WLAN 协处理器平台驱动)
  │                         + start cnssdaemon (QMI service)
  │
  ├─ S00wifi_fw_mount   → mkdir + mount tmpfs /lib/firmware/IPQ6018
  │                         + cp /lib/firmware/IPQ6018/*.bin from ROM
  │                         + cp caldata.bin from mtd9 (ART partition)
  │
  ├─ S10qca-acfg        → /usr/sbin/acfg_tool -e -s (后台监听)
  │
  ├─ S11qcawifi-config-cmd
  │   ├─ boot_dependency: insmod qca-ssdk, qca-nss-dp, qca-nss-drv, cfg80211
  │   ├─ boot_wifi: /sbin/wifi config 1 → 生成 /etc/config/wireless
  │   └─ [注意]此时**不加载** wifi_3_0 master mode!
  │
  ├─ S13qca-hostapd     → procd → /usr/sbin/hostapd -g ... -B (空 global)
  ├─ S13qca-wpa-supplicant → 类似
  │
  ├─ S19dnsmasq         → DHCP server (udp 0.0.0.0:67)
  │
  ├─ S96wifi_fw_done    → check soc_model IPQ6018, mount_wifi_fw "IPQ6018"
  │                         此步检查 /tmp/wifi_load_done flag
  │
  └─ 触发 /etc/rc.d/S95done (custom script)
      │
      └─ /usr/bin/launch_vap wifi0 wifi1
          ├─ . /lib/wifi/qcawificfg80211.sh
          ├─ get_vap_mode (1 = fast boot enabled)
          ├─ post_load_qcawificfg80211 wifi0
          │   └─ enable_qcawificfg80211 wifi0 "" "event_reload_legacy"
          │       ├─ load_qcawificfg80211 (真正加载 wifi modules)
          │       │   ├─ cp /cfg/default/ini/global.ini /ini/global.ini
          │       │   ├─ update_ini_file cfg80211_config "1"
          │       │   ├─ insmod mem_manager
          │       │   ├─ insmod qdf
          │       │   ├─ insmod umac
          │       │   ├─ do_cold_boot_calibration_qcawifi
          │       │   ├─ insmod qca_ol cfg80211_config=1   ← 关键!
          │       │   ├─ insmod wifi_3_0 (master mode)
          │       │   └─ insmod monitor, ath_pktlog
          │       │
          │       ├─ iwconfig wifi0 channel 149
          │       ├─ iwconfig ath0 channel 149
          │       │
          │       ├─ hostapd_setup_vif wifi0 ath0 atheros no_nconfig
          │       │   ├─ 写 /var/run/hostapd-ath0.conf:
          │       │   │     driver=atheros
          │       │   │     interface=ath0
          │       │   │     channel=149, hw_mode=a
          │       │   │     wpa=2, wpa_passphrase=12345678
          │       │   │     wpa_pairwise=CCMP, ssid=Nwrt_5G
          │       │   │     ctrl_interface=/var/run/hostapd-wifi0
          │       │   └─ wpa_cli -g .../hostapd/global raw ADD bss_config=ath0:conf
          │       │
          │       └─ echo "VAP ath0 created!" → driver log
          │
          ├─ post_detect_qcawificfg80211 wifi0
          ├─ touch /tmp/event_radio_done_for_wifi0
          └─ wifi1 同样处理
```

**关键**:
- 如果 `fast_boot_vap_mode=1` + `/lib/wifi/.first_time_boot` 存在 → boot 阶段自动跑 wifi up
- 否则 user 需要手动跑 `/sbin/wifi up`

---

## 4. 常用操作指南

### 4.1 修改 SSID / 密码 / 频道

```bash
# 1. uci 修改 wireless config
uci set wireless.@wifi-iface[0].ssid='NewSSID_5G'
uci set wireless.@wifi-iface[0].key='new_password_1234'
uci set wireless.@wifi-iface[1].ssid='NewSSID_2.4G'
uci set wireless.@wifi-iface[1].key='new_password_1234'

uci set wireless.@wifi-device[0].channel='149'
uci set wireless.@wifi-device[1].channel='13'

# 2. 提交
uci commit wireless

# 3. reload wifi (不重启进程)
rm -f /var/run/wifilock
/sbin/wifi reload
```

### 4.2 修改加密方式

```bash
# WPA2-PSK + CCMP (推荐)
uci set wireless.@wifi-iface[0].encryption='psk2+ccmp'

# WPA3-SAE + CCMP
uci set wireless.@wifi-iface[0].encryption='sae+ccmp'
uci set wireless.@wifi-iface[0].key='wpa3_password'

# 开放网络 (无密码,危险!)
uci set wireless.@wifi-iface[0].encryption='none'

uci commit wireless
rm -f /var/run/wifilock
/sbin/wifi reload
```

### 4.3 添加新的 WiFi VAP (multi-BSS)

```bash
# 加第二个 SSID (guest network) 在 5G 上
uci add wireless wifi-iface
uci set wireless.@wifi-iface[-1].device='wifi0'
uci set wireless.@wifi-iface[-1].network='lan'
uci set wireless.@wifi-iface[-1].mode='ap'
uci set wireless.@wifi-iface[-1].ifname='ath2'
uci set wireless.@wifi-iface[-1].ssid='Guest_5G'
uci set wireless.@wifi-iface[-1].encryption='psk2+ccmp'
uci set wireless.@wifi-iface[-1].key='guest_password'
uci set wireless.@wifi-iface[-1].disabled='0'

uci commit wireless
rm -f /var/run/wifilock
/sbin/wifi reload
```

### 4.4 启用 / 禁用 radio

```bash
# 禁用 5G (临时)
uci set wireless.@wifi-device[0].disabled='1'
uci commit wireless
rm -f /var/run/wifilock
/sbin/wifi down

# 重新启用
uci set wireless.@wifi-device[0].disabled='0'
uci commit wireless
rm -f /var/run/wifilock
/sbin/wifi up
```

### 4.5 重启整个 WiFi 栈

```bash
# 完全重启 wifi driver + hostapd (谨慎,会断开所有 wifi 客户端)
killall hostapd wpa_supplicant 2>/dev/null
rm -f /var/run/wifilock
wlanconfig ath0 destroy 2>/dev/null
wlanconfig ath1 destroy 2>/dev/null
sleep 3

# reload modules
rmmod monitor ath_pktlog wifi_3_0 qca_ol umac qdf mem_manager 2>/dev/null
sleep 2
insmod mem_manager
insmod qdf
insmod umac
insmod qca_ol cfg80211_config=1
insmod wifi_3_0
insmod monitor
insmod ath_pktlog

# Start services
/etc/init.d/qca-acfg restart
/etc/init.d/qca-hostapd restart
sleep 2

# Wifi up
/sbin/wifi up
```

### 4.6 查看 WiFi 状态

```bash
# 查看所有 VAP 状态
iwconfig
ip link show ath0
ip link show ath1

# 查看 driver 状态
cat /sys/module/wifi_3_0/parameters/is_wifi_3_0_installed
lsmod | grep -E "wifi_3|qca_ol|umac"

# 查看 driver 的 sysfs (cfg80211 mode)
ls /sys/class/ieee80211/

# 查看连接的客户端
iw dev ath0 station dump
iw dev ath1 station dump
wlanconfig ath0 list_sta

# 查看 DHCP 分配的客户端
cat /tmp/dhcp.leases

# 查看 hostapd 状态
hostapd_cli -p /var/run/hostapd status

# 实时日志
logread -f | grep -i wifi

# WiFi 频谱扫描
iwlist ath1 scan
```

### 4.7 修改 ini 配置 (driver FW 参数)

```bash
# 修改 fast_boot_vap_mode 禁用 boot 自动 wifi up
sed -i "s/fast_boot_vap_mode=1/fast_boot_vap_mode=0/" /ini/internal/global_i.ini

# 修改 cfg80211 mode
sed -i "s/cfg80211_config=1/cfg80211_config=0/" /ini/global.ini

# 注意:load_qcawifi() 会从 /cfg/default/ini/global.ini 重置 /ini/global.ini
# 永久修改要写到 /cfg/default/ini/global.ini
sed -i "s/cfg80211_config=1/cfg80211_config=0/" /cfg/default/ini/global.ini
```

### 4.8 修改频道 / 国家码

```bash
# 改国家码 (影响 DFS + 频段)
uci set wireless.@wifi-device[0].country='US'
uci set wireless.@wifi-device[1].country='US'
uci commit wireless
rm -f /var/run/wifilock
/sbin/wifi reload

# 5G DFS 频道列表 (需要 country='CN' 或 'US' 才生效)
# 5G: 36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 149 153 157 161 165 169 173 177
# 2.4G: 1-13 (1-11 US, 1-13 EU/CN)

# 启用 DFS 自动选频道
uci set wireless.@wifi-device[0].channel='auto'
uci set wireless.@wifi-device[1].channel='auto'
uci commit wireless
```

### 4.9 排查 WiFi 故障

```bash
# 1. 检查 driver 模块加载
lsmod | grep -E "wifi_3|qca_ol|umac|monitor"

# 2. 检查 ieee80211 sysfs (master mode 必须有 phy0/phy1)
ls /sys/class/ieee80211/

# 3. 检查 wifi0/1 radio up
ip link show wifi0 wifi1

# 4. 检查 VAP
ip link show ath0 ath1

# 5. 检查 hostapd BSS
ls /var/run/hostapd/

# 6. 检查 driver log
dmesg | grep -i wlan | tail -30

# 7. 检查 init.d 服务
ls /etc/rc.d/S* | grep -iE "wifi|hostap"

# 8. 手动跑 wifi up 看 log
rm -f /var/run/wifilock
( /sbin/wifi up 2>&1 ) > /tmp/wifi_up_debug.log &
sleep 10
cat /tmp/wifi_up_debug.log
```

---

## 5. 关键错误及修复

### 5.1 `Invalid tag '-cfg80211' for current mode`

**原因**: driver 没在 cfg80211 mode (只 monitor mode)
**修复**:
```bash
sed -i "s/cfg80211_config=1/cfg80211_config=1/" /ini/global.ini  # 确认是1
rmmod wifi_3_0 qca_ol umac qdf mem_manager 2>/dev/null
sleep 2
insmod mem_manager
insmod qdf
insmod umac
insmod qca_ol cfg80211_config=1    # 关键参数!
insmod wifi_3_0
```

### 5.2 `cat: can't open '/sys/class/net/wifi0/device/ieee80211/phy0/name'`

**原因**: driver 没注册 cfg80211 phy (master mode 失败)
**修复**: 同 5.1

### 5.3 `Failed to send message to driver Error:-22`

**原因**: driver 当前不支持 nl80211 模式,需要 qcawificfg80211 path
**修复**: 确认 `/etc/config/qcacfg80211` 存在且 `option enable '1'`

### 5.4 dhcp 不响应 (Dnsmasq library not found)

**原因**: `/usr/lib/libnettle.so.8` + `libhogweed.so.6` 是空符号链接,缺 .so.8.4 + .so.6.4
**修复**:
```bash
# 把实际库文件 scp 上去
scp .../libnettle.so.8.4 root@192.168.1.1:/usr/lib/
scp .../libhogweed.so.6.4 root@192.168.1.1:/usr/lib/
chmod 0755 /usr/lib/libnettle.so.8.4 /usr/lib/libhogweed.so.6.4
/etc/init.d/dnsmasq start
```

### 5.5 WPA 加密没设上 (Encryption key:off)

**原因**: hostapd_setup_vif 没跑全 (没找到 `hostapd_setup_vif` 函数)
**修复**: 确认 `/lib/wifi/hostapd.sh` (85KB) 完整,不是空壳

### 5.6 `Invalid tag '-cfg80211' for current mode` (再次)

**原因**: 即使 ini 是 cfg80211_config=1,driver 没重新 probe
**修复**: 必须 rmmod wifi_3_0 + qca_ol → insmod 时传 `cfg80211_config=1`

---

## 6. 修改 WiFi 后要重启的最小步骤

```bash
# 改 uci
uci set wireless.wifi0.channel='149'
uci commit wireless

# 触发 wifi reload (不会重启 driver,只重新建 VAP)
rm -f /var/run/wifilock
/sbin/wifi reload

# 如果 driver 状态出问题,完整重启
/etc/init.d/network restart
```

---

## 7. 监控 / 调试 WiFi 健康状态

```bash
# 加进 /etc/rc.local boot 后自动跑
cat >> /etc/rc.local <<'EOF'
# WiFi health check + auto-recovery
wifi_check=$(iw dev ath0 station dump 2>&1 | wc -l)
if [ "$wifi_check" = "0" ]; then
    echo "WiFi ath0 has no clients, attempting restart..."
    rm -f /var/run/wifilock
    /sbin/wifi up
fi
EOF
```

---

## 8. 从备份分区恢复 (回滚)

```bash
# 切回 NWRT 原厂 sys2 (如果 sys1 坏了)
fw_setenv flag_boot_rootfs 1
fw_setenv flag_try_sys1_failed 1
fw_setenv flag_try_sys2_failed 0
reboot

# 切回我们的 sys1
fw_setenv flag_boot_rootfs 0
fw_setenv flag_try_sys1_failed 0
fw_setenv flag_try_sys2_failed 1
reboot
```

---

## 9. 开发者备忘

### 9.1 boot 阶段 wifi 行为差异

| 状态 | 表现 |
|---|---|
| `fast_boot_vap_mode=1` + `.first_time_boot` 存在 | boot 自动跑 wifi up (NWRT 默认) |
| `fast_boot_vap_mode=0` 或 `.first_time_boot` 缺失 | boot 时 wifi 关闭,user 需手动 `/sbin/wifi up` |

### 9.2 driver cfg80211 mode 触发条件

- `/etc/config/qcacfg80211.config.enable = '1'` (用户态配置)
- `/ini/global.ini` 中 `cfg80211_config=1` (FW ini)
- `insmod qca_ol cfg80211_config=1` (module param)

三者必须全部满足。

### 9.3 NWRT 原始 firmware 装载

- `/etc/init.d/wifi_fw_mount` 把 firmware 从 ROM 复制到 tmpfs `/lib/firmware/IPQ6018/`
- 必须先有这个 mount (wifi_fw_done 检测)
- boot 时 wifi 模块读 ini 时 firmware 必须存在

### 9.4 关键判断 (从 sysfs)

```bash
# master mode 工作正常:
ls /sys/class/ieee80211/   → phy0, phy1
ls /sys/class/net/wifi0/device/ieee80211/   → phy0

# monitor mode (wifi 没 up):
ls /sys/class/ieee80211/   → empty

# 判断 driver mode:
cat /sys/module/qca_ol/parameters/is_wifi_3_0_installed  # 1 = installed
lsmod | grep wifi_3_0  # 看被谁引用 (monitor vs qca_ol)
```

### 9.5 重大 bug 经验

1. **`ip link set ath0 up` 在 ACFG 模式** → driver panic,reboot 恢复
2. **`kill -9` wifi 持锁进程** → driver 死锁,kernel panic
3. **`acfg_set_freq ath0 5745` 在 radio enable 后手动调用** → driver SSR (System SubSystem Reset),wifi0/1 DOWN,需 reboot
4. **`/sbin/wifi reload` 多次** → VAP 半残 (ath0 No such device)

**最佳实践**:
- 用 `/sbin/wifi up/down` 而不是手动 `wlanconfig create`
- 用 `uci set wireless...` 改配置而不是手动改 .conf
- 用 `kill -9 hostapd` 之后必须重启整个 WiFi 栈 (lock 会卡)
- 用 `acfg_tool acfg_enable_radio` + `wlanconfig create` + `iwconfig channel` + `acfg_set_ssid` 顺序手动建 VAP (不用 wifi up) 是最安全的紧急修复路径