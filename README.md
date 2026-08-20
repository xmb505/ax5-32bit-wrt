# AX5-32Bit (NWRT Kernel + Rootfs) 手工拼装完美固件与文档分发仓库

> **🌟 全网首创 · 手工拼装 · 绝不 OOM · 100% 自由**
>
> ⚠️ **重要声明**: 本仓库 **不是** 一个可通过 `make` 编译源码的 OpenWrt 仓库！
> 这是一个 **已经拼装好的、高稳定、满血 WiFi + NSS 加速 的 AX5 32-bit 固件及完整开发手册分发仓库**。
> 你在别的地方 clone 下来，可以立马通过 `build.sh` 或 TFTP 刷入一模一样的完美 UBI 固件，而不需要在 11GB 的 QSDK 源码泥潭里编译几十个小时！

```
 █████╗ ██╗  ██╗██╗   ██╗    ██████╗ ██████╗ ████████╗
██╔══██╗╚██╗██╔╝██║   ██║    ██╔══██╗██╔══██╗╚══██╔══╝
███████║ ╚███╔╝ ██║   ██║    ███████║██████╔╝   ██║
██╔══██║ ██╔██╗ ██║   ██║    ██╔══██║██╔══██╗   ██║
██║  ██║██╔╝ ██╗╚██████╔╝    ██║  ██║██║  ██║   ██║
╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝     ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
```

---

## 1. 为什么有这个仓库? (Honest Truth)

小米红米 AX5 (RA67, IPQ6018) 出厂 128MB RAM, 128MB NAND 限制极大。
- **OpenWrt / ImmortalWrt 主线**: 根本不支持 IPQ60xx,且 Linux 6.x + 开源驱动在 128MB 上直接 **OOM (内存泄漏崩溃)**。
- **LibWrt (64-bit)**: 只有 64 位，占用内存极高,开源 Wi-Fi 驱动在 128MB RAM 上连跑都不稳定。
- **QSDK (32-bit)**: 极难编译，没有任何好用的 WiFi 脚本集成，WiFi 默认不可配。

我们花了几十个小时，通过 **NWRT 原厂 5.4 内核 (绕过 Secure Boot)** + **手工高精度剥离 4KB 损坏头部** + **高精度裁剪 NWRT rootfs** + **补齐所有依赖库**，手工拼装出了这个**世界上唯一在 AX5 上满血加速、稳定跑 WiFi 的 32-bit UBI 固件**。

本仓库就是用来**分发这个成果的，没有任何无用代码，38MB 即开即用**！

---

## 2. 仓库目录结构

```
.
├── doc/                        # 📄 2000+ 行极致开发与调试手册
│   ├── CURRENT_WORK.md         # 进度交接
│   ├── INCIDENT_2026-08-20.md  # 调试事故复盘 (必读,教训清单)
│   ├── NWRT_WIFI_BOOT_FLOW.md  # NWRT WiFi 启动流程深度剖析
│   ├── NWRT_FACTORY_REFERENCE.md # NWRT 原厂 vs 我们 rootfs 核心对比
│   └── WIFI_IMPLEMENTATION.md  # 🛠️ 开发者速查手册 (文件、命令、调试技巧)
│
├── release/                    # 📦 真正有用的烧写包与脚本 (38MB)
│   ├── ax5-32bit-v13.9-release.ubi     # 🌟 20MB 最终 UBI 刷写固件 (包含内核与文件系统)
│   ├── ax5-32bit-v13.9-rootfs.squashfs # 🛠️ 14.5MB 拼装好的满血 rootfs (squashfs-xz)
│   ├── ax5-32bit-v13.9-kernel-fit.itb  # 3.9MB standalone 内核 FIT image (供备用)
│   ├── .config                         # 281KB 编译配置参考
│   ├── ubinize.cfg                     # UBI 卷配置文件
│   ├── customize.sh                    # 🎨 一键"塞自定义文件 + 重打包 UBI"脚本
│   ├── customize/                      # 📂 你的自定义文件按目标路径放这里
│   ├── CUSTOMIZE.md                    # 📖 自定义 rootfs 完整指南
│   ├── pack-ubi.sh                     # ⚙️ 一键重新拼装为 .ubi 镜像的脚本
│   ├── build.sh                        # 🚀 路由器 SSH 一键烧写脚本 (sys1 -> sys2 互刷)
│   ├── flash-via-tftp.sh               # 🚑 串口 TFTP 应急救援脚本 (变砖用)
│   └── CHECKSUM.txt                    # 校验和与手工拼装流程说明
│
└── README.md                   # 本文件
```

---

## 3. 实测状态 (2026-08-21 验证通过)

| 组件 | 状态 | 说明 |
|---|---|---|
| **Kernel** | NWRT 5.4.213 (32-bit ARM) ✅ | 高精度剥离 4KB 垃圾头，绕过小米 U-Boot 校验 |
| **WiFi 5G** | `Nwrt_5G`, chan 149, 802.11axa ✅ | Master 模式，WPA2-PSK 正常，**不设 WPA2-PSK 连不上** |
| **WiFi 2.4G** | `Nwrt_2.4G`, chan 13, 802.11axg ✅ | Master 模式，WPA2-PSK 正常 |
| **密码** | `12345678` ✅ | 默认配置已置于 squashfs 只读层 |
| **DHCP** | `dnsmasq` (`udp 0.0.0.0:67`) ✅ | 补齐 `libnettle.so.8.4` 和 `libhogweed.so.6.4` 实文件后完美运行 |
| **br-lan** | ath0 + ath1 + eth0/1/2 ✅ | 桥接完美, 手机/笔记本可连 |
| **NSS 加速** | NSS Core 0 满血启动 ✅ | NSS0-retail 固件完备, 加密与转发满血硬件加速 |

---

## 4. ⚡ 3 分钟极速刷机 (SSH 方式)

> 假设你手里的 AX5 路由器已经在任何可 SSH 登录的固件上 (如 sys1), 并且你可以与开发机 (192.168.1.254) 互通。

```bash
# 1. 克隆这个极简的分发仓库
git clone -b AX5-NwrtKernel https://github.com/xmb505/ax5-32bit-wrt.git
cd ax5-32bit-wrt/release

# 2. 把烧写包推送到路由器 /tmp/ 目录下
scp -O -o HostKeyAlgorithms=+ssh-rsa ax5-32bit-v13.9-release.ubi root@192.168.1.1:/tmp/

# 3. 登录路由器, 运行 build.sh (或手动运行以下三行命令)
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.1.1
# [在路由器上运行]
ubiformat /dev/mtd19 -f /tmp/ax5-32bit-v13.9-release.ubi
fw_setenv flag_boot_rootfs 1
fw_setenv flag_try_sys1_failed 1
fw_setenv flag_try_sys2_failed 0
reboot
```

🎉 **完工。** 手机直接搜索 `Nwrt_5G` / `Nwrt_2.4G`, 密码 `12345678` 连入，立刻拿 IP，满血运行！

---

## 5. 🚑 变砖救援 (串口 TFTP 方式)

如果你的路由器完全无法启动，不要慌。接上串口 (波特率 115200 8N1), 进入 U-Boot 终端，把 `release/` 下的文件通过 TFTP 烧入：

```bash
# 在 U-Boot 终端输入以下命令 (开发机 TFTP 设为 192.168.31.100):
setenv serverip 192.168.31.100
setenv ipaddr 192.168.31.1
tftpboot 0x44000000 ax5-32bit-v13.9-release.ubi
nand erase 0x1180000 0x2400000
nand write 0x44000000 0x1180000 ${filesize}
reset
```

---

## 6. 🤝 与其他 AX5 仓库的客观对比

| 仓库 | 64-bit | 32-bit | NWRT Kernel | WiFi | Secure Boot | LUCI | 128M 可用性 |
|---|---|---|---|---|---|---|---|
| `immortalwrt/ipq807x` | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ **没有 ipq60xx 支持** |
| `libwrt/libwrt-stock` | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ **64位 + 开源 WiFi 直接 OOM 崩溃** |
| `everything411/qsdk` | ❌ | ✅ | ✅ | ⚠️ 实验 | ⚠️ 实验 | ❌ | ❌ **WiFi 用户态脚本缺失, 无法使用** |
| **本仓库 (AX5-NwrtKernel)** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | 🌟 **完美运行, 稳定不崩溃** |

### 为什么只有 32-bit 闭源 qca-wifi 驱动能拯救 AX5?
- **64-bit 架构**: 64 位指针和指令在 128MB RAM 的 AX5 上是奢侈品, 运行不了几个包就爆内存。
- **开源 Wi-Fi 驱动 (ath11k)**: 内存占用极大, 启动就需要近 40MB 的共享内存池, 会直接触发 **OOM**。
- **本仓库解决方案**: 采用高通官方 QSDK 12.2 的 **32-bit AArch32 兼容执行态**, 配合极低内存开销的 **qca-wifi 闭源驱动**, 使得整机运行内存仅占用 45MB，空出近 60MB RAM 给你的其他自定义应用！

---

## 7. 🛠️ 塞自己的文件进 rootfs / 重新打包

不需要编译任何东西。开发机装好 `squashfs-tools` + `mtd-utils` 后：

```bash
cd release/

# 1. 按目标路径放文件 (customize/usr/bin/myapp -> 路由器 /usr/bin/myapp)
mkdir -p customize/usr/bin
cp myapp customize/usr/bin/ && chmod +x customize/usr/bin/myapp

# 2. 一键重打包 (自动 unsquashfs -> 注入 -> mksquashfs xz -> ubinize)
./customize.sh

# 3. 刷 ax5-32bit-v13.9-release-custom.ubi (方法同第 4 节)
```

整个流程只要 **30 秒**。原理、坑点（必须 xz 压缩、卷名必须叫 `rootfs`、别动内核卷等）详见 **[`release/CUSTOMIZE.md`](release/CUSTOMIZE.md)**。

如果你想做深度魔改（裁剪包、换 LuCI、改 WiFi 脚本），再看 **[`doc/NWRT_FACTORY_REFERENCE.md`](doc/NWRT_FACTORY_REFERENCE.md)** §6 的修补清单。

---

## 8. 🙏 致谢

- [nicklaskey/qca-wifi-host](https://github.com/nicklaskey/qca-wifi-host) 提供 QSDK 12.2 基础
- [everything411/qsdk](https://github.com/everything411/qsdk) 提供的 32 位底层补丁
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 团队提供的基础 base
- 小米/高通原厂固件工程师

---

## 📜 License

本仓库基于 NWRT (LGPL/GPL) 和 OpenWrt (GPL-2.0)。
仓库作者: xmb505 (retromilia@foxmail.com)

**🚀 Happy hacking. 你已经拥有了红米 AX5 历史上最轻量、最强悍的 32 位满血系统。**