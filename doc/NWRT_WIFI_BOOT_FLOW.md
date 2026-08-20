# NWRT WiFi 启动完整流程解析 - 2026-08-20 调试记录

> **结论**:NWRT 32-bit (IPQ6018, kernel 5.4.213, armv7l) 的 WiFi 启动走完整流程后,
> 5G/2.4G VAP 都能 UP、SSID 广播、加入 br-lan,但 WPA 加密因为 hostapd 二进制不兼容
> qca 闭源扩展而无法注入。
>
> **当前可达成的状态**: ✅ SSID 可搜不可连(无加密)。要 WPA 工作,需补装
> NWRT 的 `qca-hostapd` 包(包含 atheros driver 的 hostapd 二进制)。

---

## 1. 路由器 boot 时 WiFi 状态

| 阶段 | 触发 | 结果 |
|---|---|---|
| 引导脚本 S00wifi_fw_mount | wifi_fw_mount init | 把 IPQ6018 wifi firmware 挂到 /lib/firmware |
| 引导脚本 S11qcawifi-config-cmd | boot_dependency + boot_wifi | insmod NSS/cfg80211 + 跑 `/sbin/wifi config` 生成 `/etc/config/wireless` 默认段 |
| 引导脚本 S13qca-hostapd | procd | 启动 **空的** global hostapd(`-g /var/run/hostapd/global`),没有任何 BSS |
| 引导脚本 S13qca-wpa-supplicant | procd | 启动空 global wpa_supplicant |
| 引导脚本 S20network | ubus trigger | `wireless` config 变更时调用 `/sbin/wifi reload_legacy`,**但 boot 时默认 disabled,所以不触发** |
| `wifi0/wifi1` radio UP | driver 加载完 | radio interface UP,但**没有 ath0/ath1 VAP** |

**关键事实**:**boot 后 WiFi 默认是关闭状态**,需要用户首次配置/触发 `/sbin/wifi up`。

---

## 2. driver 模式识别

NWRT (QSDK 12.2) 内核驱动是 **Atheros Configuration (ACFG) 私有协议**,不是标准 Linux `nl80211`:

| 检测方法 | 结果 | 含义 |
|---|---|---|
| `ls /sys/class/ieee80211/` | 空 | 没有标准 cfg80211 phy |
| `ls /sys/class/net/wifi0/phy80211` | 不存在 | 没有 cfg80211 netdev symlink |
| `wlanconfig ath0 create ... -cfg80211` | `Invalid tag '-cfg80211' for current mode` | 驱动不接受标准 CFG80211 VAP 创建 |
| `hostapd -dd ... driver=nl80211` | `Driver does not support authentication/association` | 走不了 nl80211 |
| `acfg_tool -p` | 916 行 API | ACFG 私有 API 完整 |
| `modprobe lsmod` | `cfg80211` 仅被 `wifi_3_0` `qca_ol` `umac` `qdf` 引用,但 wifi_3_0 只在 monitor 模式下 | 走 ACFG 路径 |

**结论**:必须走 ACFG 路径(用 `wlanconfig create` **不**带 `-cfg80211`)。

---

## 3. 让 WiFi 起来的完整步骤 (实测)

### 3.1 修改 wireless config 使用 ACFG type

NWRT 出厂 default `wireless` config 用 `type qcawificfg80211`,但驱动是 ACFG,
走 qcawificfg80211 路径会失败(脚本内部依赖 sysfs `phy80211/name`,该路径不存在)。

改为 `type qcawifi`:

```uci
config wifi-device 'wifi0'
    option type 'qcawifi'              # ⚠️ 必须 qcawifi,不能用 qcawificfg80211
    option channel '149'
    option hwmode '11axa'
    option wband '5g'
    option htmode 'HT80'
    option country 'CN'
    option disabled '0'
    option force_hostapd_attach '1'    # ⚠️ 关键:让 hostapd_setup_vif 调用 ADD
    option macaddr '00:03:7f:12:1a:fb' # ⚠️ 用 ART 中的真实 WiFi MAC

config wifi-iface
    option device 'wifi0'
    option network 'lan'
    option mode 'ap'
    option ifname 'ath0'               # ⚠️ 必须是 ath0/ath1,不是 wifi0/wifi1
    option ssid 'Nwrt_5G'
    option encryption 'psk2+ccmp'
    option key '12345678'
    option disabled '0'
```

### 3.2 在路由器上手动跑启动流程

```bash
# 1. 确保 global hostapd 跑着(qca-hostapd init 启动,但可能被 kill)
hostapd -g /var/run/hostapd/global -B -P /var/run/hostapd-global.pid

# 2. 干净的 wifi up(在 lock 干净的状态下)
/sbin/wifi up
```

### 3.3 wifi up 内部流程(走 ACFG 路径)

`enable_qcawifi(wifi0)` (在 `/lib/wifi/qcawifi.sh`) 内部流程:

1. `load_qcawifi` —— 加载内核模块 `mem_manager → qdf → umac → qca_ol → wifi_3_0`
2. `start_recovery_daemon` —— 启动 `acfg_tool -e -s`(监听 ACFG 事件)
3. `iwconfig wifi0 channel 149` —— 通过 legacy iwconfig API 设 channel
4. `enable_vifs_qcawifi` 对每个 vif 调 `hostapd_setup_vif "$vif" atheros no_nconfig`
5. `hostapd_setup_vif` (在 `/lib/wifi/hostapd.sh`):
   - 写 `driver=atheros` 到 `/var/run/hostapd-ath0.conf`
   - 如果 `force_hostapd_attach=1`: `wpa_cli -g .../hostapd/global raw ADD bss_config=ath0:/var/run/hostapd-ath0.conf`

### 3.4 验证

```bash
# VAP 应该 up 且绑定 br-lan
iwconfig ath0
# ath0  IEEE 802.11axa  ESSID:"Nwrt_5G"  
#           Mode:Master  Frequency:5.745 GHz  Access Point: 28:D1:27:E4:13:D6

brctl show br-lan
# bridge name    bridge id           STP enabled    interfaces
# br-lan         7fff.28d127e413d5  no             ath0
#                                                  ath1
```

---

## 4. 关键发现 - 5G 频道

**`iwconfig ath0 channel 149` 会被 driver 接受并设到 5.745 GHz** ✅

之前我一直以为 driver 把 channel 绑死在 36,实际上是:
- 第一次 `wifi up` 走完整流程时 channel 是被设上的
- 我之前手动 `acfg_set_freq` 触发 SSR 是因为我在 radio enable **之后** 单独调用,内部状态机不一致

**核心结论**:通过 `/sbin/wifi up` (不手动调 acfg_set_freq) 就能正确设到 chan 149/11。

---

## 5. WPA 问题 - hostapd 二进制兼容性

### 5.1 问题

`/var/run/hostapd-ath0.conf` 里是 `driver=atheros`,这是 QCA 私有 driver 模式。

我们编译的 hostapd (从 staging_dir 装的 OpenWrt hostapd `v2.10-devel`) **不支持 atheros driver**:
```
$ hostapd -dd -t /var/run/hostapd-ath0.conf
Line 1: invalid/unknown driver 'atheros'
```

而 `nl80211` 路径 driver 不支持:
```
nl80211: Driver does not support authentication/association or connect commands
```

### 5.2 NWRT 出厂怎么解决的

NWRT 路由器出厂装了 `qca-hostapd` 包,里面包含 **支持 atheros driver 的 hostapd 二进制**。

我们的 v9/v13 rootfs 漏装了这个包,直接用 OpenWrt 的 hostapd (只支持 nl80211/wired)。

### 5.3 解决方案 - 补装 qca-hostapd

```bash
# 找 NWRT 原厂的 qca-hostapd ipk
scp ... mtd19:/tmp/qca-hostapd*.ipk
opkg install /tmp/qca-hostapd*.ipk --force-depends
# 重启 hostapd
/etc/init.d/qca-hostapd restart
/sbin/wifi up
```

qca-hostapd 的 init 脚本 `/etc/init.d/qca-hostapd`:
```
procd_set_param command /usr/sbin/hostapd -g $WPAD_VARRUN/hostapd/global -B -P $WPAD_VARRUN/hostapd-global.pid -f /tmp/hostapd.txt
```

但这个 hostapd 二进制要包含 `atheros` driver module。我们目前的 binary 没有。

### 5.4 临时方案 - 不加密开放 WiFi

如果 `qca-hostapd` 拿不到,可以让 WiFi 开放跑(没 WPA 但能用):

```bash
# 设置 wireless encryption=none
uci set wireless.@wifi-iface[0].encryption=none
uci set wireless.@wifi-iface[1].encryption=none
uci commit wireless
/sbin/wifi up
```

这能让 SSID 广播+用户连接+DHCP 拿 IP,但**所有流量明文**。生产环境绝对不能用。

---

## 6. 完整复现脚本

把下面保存为 `/etc/uci-defaults/99-wifi-bringup` 即可 boot 自动起 WiFi:

```bash
#!/bin/sh
# Wait for driver ready
sleep 5

# Destroy any leaked VAPs
wlanconfig ath0 destroy 2>/dev/null
wlanconfig ath1 destroy 2>/dev/null

# Start global hostapd
killall hostapd 2>/dev/null
sleep 1
hostapd -g /var/run/hostapd/global -B -P /var/run/hostapd-global.pid

# Trigger WiFi bringup
rm -f /var/run/wifilock
/sbin/wifi up

exit 0
```

注意:
- 必须先用 sys1 救活,然后 overlay 修改 wireless config(type=qcawifi, force_hostapd_attach=1, ifname=ath0)
- 首次 boot 后 ath0/ath1 需要 `wlanconfig create` 手动建 VAP,然后 wifi up 触发 hostapd 注册 BSS

---

## 7. sys1 / sys2 路由切换参考

| sysN | flag_try_sysN_failed | flag_boot_rootfs | 内容 |
|---|---|---|---|
| sys1 | 0 | 0 | 当前 active,NWRT 原厂 |
| sys2 | 1 | - | 之前刷的 v9,v9 rootfs |

**回滚 v9**:在 sys1 上:
```bash
fw_setenv flag_boot_rootfs 0
fw_setenv flag_try_sys1_failed 0
fw_setenv flag_try_sys2_failed 1
reboot
```
**激活 v9 (sys2)**:
```bash
fw_setenv flag_boot_rootfs 1
fw_setenv flag_try_sys1_failed 1
fw_setenv flag_try_sys2_failed 0
reboot
```

---

## 8. 当前状态 (2026-08-20 14:30)

| 项 | 状态 |
|---|---|
| 路由器 sys1 (NWRT 原厂分区) | ✅ active |
| wifi0/wifi1 radio | ✅ UP |
| ath0 (5G) | ✅ UP,ESSID:Nwrt_5G,Frequency:5.745 GHz(chan 149),AP:28:D1:27:E4:13:D6 |
| ath1 (2.4G) | ✅ UP,ESSID:Nwrt_2.4G,Frequency:2.462 GHz(chan 11),AP:28:D1:27:E4:13:D7 |
| hostapd global | ✅ 跑着(PID 22685) |
| Encryption (WPA) | ❌ 没设上(hostapd 二进制不支持 atheros driver) |
| bridge br-lan | ✅ 含 ath0/ath1/eth0/eth1/eth2 |
| 用户能搜到 SSID | ✅ |
| 用户能连 WiFi | ❌ 暂时连不上(需要 WPA) |

---

## 9. 下一步建议

1. **如果接受开放 WiFi**(没 WPA) —— 当前状态即可,设 `encryption=none` 即可
2. **如果需要 WPA** —— 从 sys1 备份 rootfs,提取 NWRT 原厂 qca-hostapd 的 atheros-enabled hostapd 二进制
3. **如果想要漂亮稳定** —— 用 qca-hostapd ipk 包,然后刷回 v13(v10/v11) rootfs 时把 qca-hostapd 二进制塞进 `/usr/sbin/hostapd`

---

## 10. DHCP 缺失问题 (14:31 发现)

WiFi VAP 起来后,**客户端连上但拿不到 IP**。根因:**`dnsmasq` 库依赖缺失**。

```
$ /usr/sbin/dnsmasq --help
Error loading shared library libnettle.so.8: No such file or directory
Error loading shared library libhogweed.so.6: No such file or directory
Error relocating /usr/sbin/dnsmasq: nettle_get_secp_384r1: symbol not found
```

### 根因
- 我们 v9 rootfs 提取时**漏了** `libnettle.so.8.4` 和 `libhogweed.so.6.4` 的**实际库文件**
- 只保留了 `.so.8` 和 `.so.6` 版本号软链接 → 悬空指向不存在的实际文件
- 这些库是 OpenWrt 的 **nettle** 包(v3.7.3)提供的,**不是 squashfs 自带的**

### 修复

```bash
# 1. 从 NWRT 原厂 rootfs 拷贝真实库文件(开发机)
scp /tmp/nwrt-rootfs-extracted/usr/lib/libnettle.so.8.4 root@192.168.1.1:/tmp/
scp /tmp/nwrt-rootfs-extracted/usr/lib/libhogweed.so.6.4 root@192.168.1.1:/tmp/

# 2. 在路由器上安装
cp /tmp/libnettle.so.8.4 /usr/lib/
cp /tmp/libhogweed.so.6.4 /usr/lib/
chmod 0755 /usr/lib/libnettle.so.8.4 /usr/lib/libhogweed.so.6.4

# 3. 启动 dnsmasq
/etc/init.d/dnsmasq start

# 4. 验证
netstat -ln | grep -E "67|53"
# 应看到:
# udp        0      0 0.0.0.0:67              0.0.0.0:*
# udp        0      0 192.168.1.1:53          0.0.0.0:*
```

### v14 rootfs 修补清单

| 源 | 目标 |
|---|---|
| `/lib/libnettle.so.8.4` | `/usr/lib/libnettle.so.8.4` |
| `/lib/libhogweed.so.6.4` | `/usr/lib/libhogweed.so.6.4` |

**根因**:`opkg info libnettle8` 显示包已装,但**实际文件不在 squashfs**(被 jffs2/overlay 剥了一层)。重新刷 rootfs 时务必复制 `.so.X.Y` 主版本实际文件,不只是软链接。

---

## 11. v14 rootfs 修补完整清单 (todo)

把以下都加进 v14 rootfs:

| 文件 | 来源 | 大小 | 原因 |
|---|---|---|---|
| `/usr/lib/libnettle.so.8.4` | NWRT 原厂 | 282KB | dnsmasq 库依赖 |
| `/usr/lib/libhogweed.so.6.4` | NWRT 原厂 | 241KB | dnsmasq 库依赖 |
| `/lib/wifi/qcawificfg80211.sh` | NWRT 原厂 | 246KB | CFG80211 完整脚本 |
| `/lib/wifi/wpa_supplicant.sh` | NWRT 原厂 | 18KB | wpa_supplicant 配置 |
| `/lib/wifi/wps-*` (3 个脚本) | NWRT 原厂 | ~20KB | WPS 配置 |
| `/usr/sbin/wifi_try` `wifi_hw_mode` `wifistats` `wlanfw-upgrade.sh` | NWRT 原厂 | ~30KB | wifi 工具链 |
| `/usr/sbin/hostapd` | NWRT 原厂 atheros-enabled | ~2.4MB | qca-hostapd 二进制 |
| `/usr/sbin/wpa_supplicant` | NWRT 原厂 atheros-enabled | ~600KB | qca-wpa-supplicant 二进制 |