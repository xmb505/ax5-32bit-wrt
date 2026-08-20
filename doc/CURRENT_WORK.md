# ax5-32bit 编译进度交接 - v13.9 (✅ 已发布, 含 HAKU WRT 面板)

> **当前最终状态 (2026-08-21)**: v13.9 已发布到本仓库 `release/` 目录并推送至
> GitHub `xmb505/ax5-32bit-wrt` 分支 `AX5-NwrtKernel`。
> rootfs 已集成 haku_wrt 控制面板。WiFi / NSS / DHCP / LuCI 全部实测通过。
>
> **注意**: 下文 v13-release-v8 的本地路径与 SHA 是历史中间版本记录，
> 最终出货产物一律以 `release/` 目录及 `release/CHECKSUM.txt` 为准。
>
> 用户的策略：**用 NWRT 已经验证能完美启动的 5.4.213 内核 + 我们极限精简且补全固件的 rootfs**，组合成 factory.ubi。
> 成功解决了所有物理总线死锁、分区挂载死锁、NSS/WiFi 崩溃死锁等底层问题！

## 用户目标 (最终)

为 Redmi AX5 (IPQ6018) 出一个能完美启动、WiFi 和 NSS 均满血、且**空出整整 14MB 物理 NAND 空间**给 `haku_wrt` 仪表盘的 32-bit ARMv7 固件。

---

## 终极出货版：v13-release-v8 ✅

**固件路径**：`/home/xmb505/immortalwrt/ax5-32bit/bin/openwrt-ipq60xx-ipq60xx_32-redmi_ax5-squashfs-factory-v13-release-v8.ubi`
**文件大小**：19.1 MB (`20054016` 字节)，比原厂 32MB 固件**省出整整 13MB**！
**SHA256**：`a851b70ed7e33144b96ac59fe921d4d58e9719c12a83c13131fc1a36a88dcc26`

### 🛠️ 相比于旧版的 8 个关键技术修复：

1. **解决 XZ 挂载崩溃 (`zlib unsupported`)**
   - **问题**：原版 NWRT 内核关闭了 `CONFIG_SQUASHFS_ZLIB` 支持，只保留了 `CONFIG_SQUASHFS_XZ`。
   - **修复**：我们的 rootfs squashfs 重新使用 **`mksquashfs -comp xz -b 128K`** 强行压制为标准的 `xz` 格式，不仅体积从 16.4M 缩减到 13.5M，更完美解决了内核挂载 Panic。

2. **解决 UBI 卷名卡死 (`vol_name=rootfs`)**
   - **问题**：内核 `921-ubifs-ubi-rootfs-block-device-creation.patch` 补丁在早期引导时，只会寻找名为 `"rootfs"` 的卷并建立 `/dev/ubiblock0_1` 块设备。
   - **修复**：在 `ubinize.cfg` 中强行将系统分区的 UBI 卷名修正为最标准的 **`rootfs`**。

3. **解决 NSS 驱动 Probe 失败 (Missing Firmwares)**
   - **问题**：NSS 驱动因缺少 `/lib/firmware/qca-nss0.bin` 固件导致 Probe 报 -12 错误而挂掉。
   - **修复**：从原厂提取了完好的 860KB 实机 `qca-nss0.bin` 固件二进制，补全到我们的文件系统中，网络 NSS 满血硬件加速！

4. **解决 WiFi 协同处理器 (WCSS) 启动 Oops 崩溃 (q6_fw 段缺失)**
   - **问题**：由于精简时漏掉了 Q6 协同处理器的关键固件切片 `q6_fw.b04`, `q6_fw.b05`, `q6_fw.b07`, `q6_fw.b08`，导致 remoteproc 引导 WLAN WCSS 时直接发生段加载失败，并触发了内核崩溃。
   - **修复**：高精度提取了上述 4 个 Q6 固件分段塞回 `/lib/firmware/IPQ6018/`。并且完美复位了整个 **/lib/wifi/** 下 of QSDK 无线自配置和驱动加载脚本！WiFi 完美正常上线！

5. **解决 LuCI 登录报错 `No valid theme found`**
   - **运行环境**：之前精简系统时，误将 `/usr/lib/lua/luci/view/` 下的 HTML 模板全部抹除，导致 LuCI 前端找不到任何可用页面。
   - **修复**：完整恢复了原厂 view 目录（仅 180KB），并在 `/etc/config/luci` 中将 Bootstrap 主题重新注册为默认。LuCI 前端成功秒进！

6. **解决 `/etc/fw_env.config` 缺失问题**
   - **问题**：命令行运行 `fw_printenv` 会报错 `No such file or directory`。
   - **修复**：成功为 Redmi AX5 补全了精简后的 `/etc/fw_env.config`。
     配置文件内容：`/dev/mtd6 0x0 0x10000 0x20000`。现在可以在系统内直接读取和写入 APPSBLENV 环境变量了！

7. **解决 `Failed to send message to driver Error:-22` (wlanconfig/cfg80211tool 不兼容)**
   - **问题**：我们自编译的 `wlanconfig`、`cfg80211tool` 和 `acfg_tool` 等用户态二进制与 NWRT 原厂闭源驱动不兼容，导致接口创建时抛出 -22 错误。
   - **修复**：从 NWRT 中精准剥离了原厂的 5 个无线管理二进制工具（`wlanconfig`、`wifitool`、`radartool`、`athstats`、`apstats`）并完整覆盖进了 `/usr/sbin/`，彻底打通用户态控制链！

8. **解决首 Boot 无线检测重叠冲突 (静态预置配置)**
   - **问题**：OpenWrt 的 `mac80211` 与 QSDK 的无线检测脚本打架，生成了 OpenWrt + Nwrt 4 个重叠无线网卡导致启动失败。
   - **修复**：直接在只读系统分区中静态预置了完美无冲突的单 VAP **`/etc/config/wireless`** 配置文件，开机无需检测检测，彻底绝离冲突，直接一键拉起 WiFi！

---

## 🚀 最终刷机与引导指令

由于安全机制，路由器可能回滚到了 64 位的 LibWrt。你可以直接在 **64位 LibWrt 路由器 SSH 终端** 中运行：

```bash
# 1. 登录路由器，直接拉取最新的终极 v13-v8 刷机固件 (开发机 IP 为 192.168.1.254，输入开发机系统密码)
scp -O xmb505@192.168.1.254:/home/xmb505/immortalwrt/ax5-32bit/bin/openwrt-ipq60xx-ipq60xx_32-redmi_ax5-squashfs-factory-v13-release-v8.ubi /tmp/

# 2. 刷写最新 v8 出货包到 mtd19
ubiformat /dev/mtd19 -f /tmp/openwrt-ipq60xx-ipq60xx_32-redmi_ax5-squashfs-factory-v13-release-v8.ubi

# 3. 干净设置引导分区并重启！
fw_setenv flag_boot_rootfs 1
fw_setenv flag_try_sys1_failed 1
fw_setenv flag_try_sys2_failed 0
reboot
```