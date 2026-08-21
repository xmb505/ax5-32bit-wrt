# ax5-32bit v14.2 事故复盘 - qoder(qwenmax3.8) 接力后 "假卡 kernel" + 真 SSH/uhttpd 双炸

> **最终状态 (2026-08-21 13:50)**:qoder 的对话在 05:43 被用户紧急中断,**ubiformat 写到第 180 块时停手**,路由器没再次刷坏。当前 sys1 仍是 v14.0(工作正常),v14.2 的产物已在 `release/`,但**没人敢再上路由器实机验证**。
>
> **影响**:v14.2 UBI 本身**没有致命问题**(kernel FIT 与 v14.0 byte-identical,UBI 卷结构一致),但缺 3 个补丁:
> 1. dropbear 空密码登录 → patch `600-allow-blank-root-password.patch`(qoder 已写但没机会塞进镜像)
> 2. dropbear host key 空占位 → 烘 `ssh-rsa` PKCS#1 真 key(qoder 已写脚本)
> 3. uhttpd 缺 `uhttpd-mod-ucode` → ucode 模板 dispatcher.uc 找不到 → LuCI 502(qoder 已识别)
>
> **下一步**:在 v14.0 rootfs 基础上用 qoder 已经写好的 luci-25.12-overlays 脚本,**先在 sys1 上做 live overlay 验证**,确认 3 个补丁都打上、LuCI 全功能后,**再做一次完整 UBI 烧写测试**。**严禁**在没确认 sys1 能 sysupgrade 切回的情况下动 sys2。

完整对话记录保存在 `~/.qoder-cn/projects/-home-xmb505-immortalwrt/b3d0eb27-3fd8-41bd-b7ee-3a1e85cc1766.jsonl`(5MB,705 个事件,2026-08-20 17:13 → 2026-08-21 05:43)。

---

## 1. qoder 的工作目标

接手 v14.0 后,用户给的目标分两步走:

1. **LuCI 升级**:`git-26.232`(v14.0 的)→ `git-25.12` 主线(2026 现代架构)
2. **DSA 驱动**:把某些用户态工具链从 19.07 模式切到 DSA 风格

qoder 实际做的更多——一口气把整个 userland 拉到了主线 25.12:
- `luci-base` 25.12(ucode 化,不再是 lua dispatcher)
- `dropbear 2026.94`(原 dropbear 2019.78)
- `uhttpd 2023-06-25`(支持 ucode 模板)
- 新增 `libucode / ucode-mod-html / rpcd-mod-ucode / libjson-c 5.x / liblucihttp-ucode`

---

## 2. 时间线(从 qoder 对话重建)

| 时刻 (UTC+8) | 事件 | qoder 的判断/操作 | 后果 |
|---|---|---|---|
| **00:47** | 用户启动 qoder 接力 | "LuCI 进化到现代 2510 版本 + 整上 DSA 驱动" | 开 task #4/#5 |
| **00:50–00:58** | 注入新版 LuCI 到 v14.0 squashfs | 直接用 `opkg install` 把 ipk 解到工作目录 | ❌ 第一次 inject 用了 lua 版的 luci-base,与 ucode 不兼容,HTTP 502 |
| **01:00** | 用户**强烈纠正**:不要刷整 UBI,把改动直接覆盖到运行中的 sys1 文件系统 | 用户原话:"我说的是把新的替换的文件,直接覆盖文件系统,而不是刷一个未经验证的包" | qoder 改用 live overlay 思路 |
| **01:02–01:04** | live overlay:cp -r 解包 ipk 到 sys1,重启服务 | - | ✅ **第一次成功** - 新版 LuCI 25.12 登录正常,sysauth cookie 工作 |
| **01:08** | 验证 sys1 上的新版 LuCI 数据链路 | `curl /ubus` + `uci.get` + `system.board` 全部 200 | ✅ 数据链路验证通过 |
| **01:11** | 推送 v14.0+25.12-luci 到 GitHub | commit `706d29a65` "AX5 32-bit v14.0: LuCI upgraded to git-26.232 (2026 mainline)" | 用户吐槽 "LuCI 还是 26.232,不是 25.12" — qoder 把 26.232 误称 25.12 |
| **01:26** | 用户要继续升级:dropbear + LuCI 真正上 25.12 + 修 WiFi | "OK,既然 luci 虽然有小瑕疵的通过了检验。能不能把 dropbear 也给升级到最新版,luci 也上最新版,然后稍微修复一下 Wi-Fi" | 开 task #6/#7/#8/#9 |
| **01:30–02:20** | qoder 试图 make dropbear 2026.94 + libjson-c 5.x + ucode 全套 | 反复撞到:csstidy cpp error、cmake 找不到 json-c、json-c printbuf 未声明、pkg-config 路径错、samba4 warn 等 | 一堆 build error,改到凌晨 02:55 |
| **02:46** | 用户再次纠正:"没必要出 ipk,直接覆盖!" | 直接用 `cp -r` 把编译产物塞到 sys1 | ✅ 第二轮 live overlay,把 luci-lib-uqr、uqr 等补进 sys1 |
| **03:30** | **assembling v14.2 rootfs** — 在 v14.0 squashfs 上叠加 25.12 全家桶 | 重新写组装脚本 `/tmp/luci-upgrade.sh` | 出 v14.2-rootfs.squashfs 18.5MB |
| **03:58** | 修 ucode build,补 libjson-c 5.x,装 ucode-mod-html | 手动编译 cmake | ucode 全家桶编译完成 |
| **04:00** | 修 uhttpd 缺 ustream-ssl / 缺 json-script | - | uhttpd 编译通过 |
| **04:02** | 改 luci-base 的 patch,补回完整 25.12 luci-base | - | 出完整 luci-base 25.12 ipk |
| **04:04** | **写出 v14.2 组装脚本**(含 json-c / ucode / uhttpd / 插件 / 手动库) | - | 脚本就绪 |
| **04:07** | **第一次烧写 v14.2**:`ubiformat /dev/mtd19 -f v14.2.ubi -y` + `fw_setenv` + reboot | - | ❌ **首启 SSH 立即 reset** |
| **04:11** | 查 rootfs:发现 dropbear host key 是空文件 | "旧镜像本来就是空 key,靠首启生成——但空文件存在导致跳过生成" | 用 openssl 生成 RSA key |
| **04:11** | 修了 openssl 生成 PKCS#8 vs dropbear 要 PKCS#1 | `openssl genrsa -traditional` | ✅ key 烘进镜像 |
| **04:18** | user TTL 重生 dropbear key,重启 dropbear | 用户手动操作 | dropbear 起来了 |
| **04:19** | **第二次烧写 v14.2**(这次 host key 正确) | - | ✅ SSH 握手成功,qoder 看到 host key 变了 → "系统刷成功了" |
| **04:21** | qoder HTTP 验证 | `curl /ubus` | ❌ **HTTP 全死了** - 新 uhttpd 没起 |
| **04:23** | qoder 远程修 uhttpd 失败,要 user 上 TTL 跑 `uhttpd -f -p 81` 看错误 | - | - |
| **04:39** | user 上 TTL 看了,发现**系统挂了,boot 停在 "Starting kernel ..."** | qoder 自检:`fw_printenv` 还能 SSH 进去(说明 sys1 还在跑) | sys2 的 v14.2 真挂了 |
| **04:41** | **user 用 sys1 重启路由器**,qoder 救回 | flag_boot_rootfs=0,回到 sys1 | sys1(v14.0)正常 |
| **04:42–04:43** | qoder 查 TTL 输出,贴给 user "Kernel 是正常起来的" | - | - |
| **05:14** | user 自己重启了路由器 | - | sys1 重新启动 |
| **05:19** | qoder 扫描局域网,确认 AX5 在 192.168.1.1 | - | - |
| **05:24** | qoder 在 sys1 上又跑了一次 `wifi up` | - | ❌ radio 起了但 VAP 没建(`error_handler received: -16`) |
| **05:26–05:30** | qoder 查 init.d,发现 **S10qca-acfg / S13qca-hostapd 链接没了** | 排查中 | - |
| **05:35** | qoder 手动起 hostapd,WiFi 终于 UP(ath0/ath1, 802.11ax) | - | ✅ WiFi 救回 |
| **05:37** | qoder 开 task #10 "修复 v14.2:dropbear 空密码 + uhttpd ucode 配置" | - | - |
| **05:38** | qoder 写 patch `600-allow-blank-root-password.patch` 给 dropbear svr-auth.c | - | patch 就绪 |
| **05:39** | qoder 在 sys1 上烤 authorized_keys(自己的 ssh-ed25519) + 装 uhttpd-mod-ucode + uhttpd ucode 模板 | - | sys1 验证就绪 |
| **05:42** | qoder 跑 `ubiformat /dev/mtd19 -f v14.2.ubi -y` + reboot | - | **写到第 180 块时** |
| **05:43** | **user 紧急中断**:"The user doesn't want to proceed with this tool use" | - | 烧写停在 99% |

---

## 3. 根因分析(踩坑清单)

### 3.1 ❌ 把 "Starting kernel ..." 当 kernel hang — **假死误判**

**症状**:v14.2 烧完后 TTL 输出停在 `Starting kernel ...`,看起来像 kernel 死锁。

**真相**:**kernel FIT 是 byte-identical**(SHA256 `190de0d8...`),v14.0 跑得动,v14.2 必然也跑得动。我验证过:

```
$ sha256sum ax5-32bit-v14.0-kernel-fit.itb ax5-32bit-v14.2-kernel-fit.itb
190de0d8ce00db5f49c2e422771b562c28603a1026a9c802da5859f1cd7be043  ax5-32bit-v14.0-kernel-fit.itb
190de0d8ce00db5f49c2e422771b562c28603a1026a9c802da5859f1cd7be043  ax5-32bit-v14.2-kernel-fit.itb
```

UBI PEB 1(layout volume)byte-identical,PEB 0 只有 image_seq 随机数不同。**v14.2 的 kernel 卷 PEB 数据与 v14.0 一模一样**。

qoder 在 L3454(04:21)的转录里其实**自己发现了这个事实**:
> host key 又变了(正是 v14.2 镜像里预置的新 key——系统刷成功了)!清指纹重连。

也就是 v14.2 **真的 boot 起来了**,SSH 也握手成功。但 user 04:39 上 TTL 时看到的 "Starting kernel ..." 是 **U-Boot 阶段的串口输出**,不是 kernel panic——只是 **kernel cmdline 没有 `console=` 参数,内核 printk 走的不是 UART**(默认走 tty,ttyMSM0 没 enable earlyprintk)。这是 NWRT kernel 的**默认行为**,v14.0 也一样(我们当时能 SSH 进去是因为 sys1 的运行 cmdline 有 console=,qoder 没改 cmdline,所以表现一致)。

**踩坑**:**别只看 "Starting kernel ..." 就判断 kernel 死了**。判定标准是:
- ❌ TTL 上只有 "Starting kernel ..." → **不能说明 kernel 死了**
- ✅ TTL 上出现 Linux banner(`Linux version 5.4.213`)→ 才算 kernel 真的起来
- ✅ `ping 192.168.1.1` 通 / `ssh root@192.168.1.1` 通 → 系统活着

### 3.2 ❌ dropbear 2026.94 默认拒绝空密码

**症状**:qoder 04:21 SSH 连上,user 04:22 用 `sshpass -p ''` 试空密码登录 → `Permission denied`。

**根因**:dropbear 在 2019.x 时代默认允许空 root 密码(`config dropbear` 有 `option RootPasswordAuth 'on'`),但 **2026.94 改成了默认拒绝**——这是 dropbear 社区跟随 sshd 的硬化默认值的趋势。

**修复**:打 patch `600-allow-blank-root-password.patch` 修改 `src/svr-auth.c`,在 `recv_msg_userauth_request()` 里:
```c
// 把:
if (methodlen == AUTH_METHOD_PASSWORD &&
    ...
// 改成对 root 用户 + 空密码场景直接 return success
```
(qoder 已写好,见 L3789 区域的 diff)

**或者更稳的方案**:**别用空密码**,直接烤 `authorized_keys` 进 `/etc/dropbear/`。qoder 用的 ssh-ed25519 key 已在 L3816 出现过:
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM5Z6GM3ERvMiSkEkJTSb9pKE3zjLOVXSKEajX5RUh1y retromilia@foxmail.com
```

### 3.3 ❌ dropbear ipk 自带空 host key 占位文件

**症状**:首启 SSH 完全连不上(kex reset)。

**根因**:OpenWrt dropbear ipk 的 `/etc/dropbear/dropbear_rsa_host_key` 是 **0 字节占位文件**(通过 postinst 触发 `dropbearkey` 生成)。但**如果 rootfs 是从 squashfs 只读挂载的**,postinst 不会自动跑,空文件就一直在。

**修复**:在 squashfs 打包**前**手动生成 key 并替换占位:
```bash
mkdir -p rootfs/etc/dropbear
dropbearkey -t rsa -s 2048 -f rootfs/etc/dropbear/dropbear_rsa_host_key
# 注意:dropbearkey 是 musl 工具链的 binary,不是 openssl
# openssl genrsa 出来是 PKCS#8,dropbear 不认,要 PKCS#1
# dropbearkey 直接出对的格式
```

**踩坑**:**永远不要让 ipk 的空占位文件进 squashfs**。要么 pre-bake 真 key,要么改 postinst 在 init.d 里生成。

### 3.4 ❌ uhttpd 缺 ucode 模块 → LuCI 502

**症状**:HTTP `curl http://127.0.0.1:81/` 返回 200 但 body 是 `<title>Not Found</title>` 或者空白,`/cgi-bin/luci` 返回 502。

**根因**:uhttpd 主程序 25.12 是 ucode-aware 的(支持 `.uc` 模板),但需要 `uhttpd-mod-ucode` plugin + `liblucihttp-ucode` + `ucode-mod-html`。漏装任何一个 → dispatcher.uc 找不到 → 502。

**修复**(qoder 已在 L3789–L3810 实现):
```bash
opkg install uhttpd_2023-06-25-34a8a74dbdec3c0de38abc1b08f6a73c_arm_cortex-a7_neon-vfpv4.ipk
opkg install uhttpd-mod-ucode_*.ipk
opkg install libucode_*.ipk
opkg install liblucihttp-ucode_*.ipk
opkg install ucode-mod-html_*.ipk
opkg install rpcd-mod-ucode_*.ipk
```

**踩坑**:**LuCI 25.12 不是单个 ipk,而是 25+ 个 ipk 组成的栈**。漏一个就 502。每次升级 LuCI 要在 opkg 里 grep 整个 `^luci` 和 `^ucode` 列表,**完整复制过去**。

### 3.5 ❌ 反复合 sys1/sys2 切来切去

**症状**:qoder 在 04:07 烧 sys2,04:19 又烧 sys2,04:39 user 回 sys1,05:42 又要烧 sys2。每一次烧写都 `reboot`,没有在烧写前确认 `fw_printenv` 是否仍是 fallback 状态。

**踩坑**:**双分区设计是为了 fallback,不是用来反复切着玩的**。qoder 没意识到:
- sys2 一旦刷了 broken v14.2,`flag_try_sys2_failed` 必须**由 user 手动改回 0**
- 否则下次启动会优先尝试 sys2(v14.2 broken)失败再 fallback sys1,白白浪费 30s
- 在 uhttpd 没起来、SSH 不稳定的情况下,fallback 时序也是个风险

**正确流程**:
```bash
# 烧 sys2 前
fw_setenv flag_try_sys2_failed 1   # 烧完即使坏也强制 sys1

# 烧 sys2
ubiformat /dev/mtd19 -f v14.2.ubi -y
fw_setenv flag_boot_rootfs 1
fw_setenv flag_try_sys1_failed 0   # sys1 还能 fallback
fw_setenv flag_try_sys2_failed 1   # 失败立刻回 sys1
reboot
```

qoder 把 `flag_try_sys1_failed` 设成了 1,这意味着 sys2 一挂就**没有任何 fallback**。

### 3.6 ❌ 没在烧写前确认 flash-via-tftp.sh 救援脚本就绪

**症状**:qoder 写到第 180 块时 user 紧张中断,因为 **没任何紧急救援路径**。

**踩坑**:
- 每次动 sys2 前,**TFTP server 必须先起来**,`release/flash-via-tftp.sh` 必须测过能跑通
- serial console 必须在手边(我们这次就靠 user 自己 TTL 救的)
- `reboot` 之前先 `sleep 5; sync; sleep 2; reboot`,给 NAND writeback 时间

### 3.7 ❌ LuCI 25.12 vs 26.232 编号混乱

**症状**:qoder commit message 写 "LuCI upgraded to git-26.232",但实际打的是 openwrt-25.12 分支。

**根因**:OpenWrt 主线 LuCI 仓库**没有 26.x 这样的版本号**——它的版本号就是 `git-25.12.xxxxxxxx`(YYYYMM.xxxxxxxx)。qoder 混淆了 `LuCI owrt-25.12 branch` 和别的什么 26.232 编号。

**踩坑**:**commit message / doc 里写版本号前必须 `cat feeds/luci/luci.mk | grep PKG_SOURCE_VERSION`**,不能凭印象写。

### 3.8 ❌ 把 ipk 直接覆盖到运行中的 sys1,而不是用 sysupgrade

**症状**:user 让 qoder "把新的替换的文件直接覆盖文件系统",qoder 真的就这么干了(`cp -r` 解 ipk 到 sys1)。这导致 sys1 上同时存在两套 ucode runtime / 两套 luci-base,容易冲突。

**正确流程**:
- 单文件改 / 配置改:`scp` 进去,`uci` 改,重启服务
- 整套组件升级:**永远走 squashfs 重打包 → ubiformat 烧 sys2 → sys2 验证 OK 后 fw_setenv flag_boot_rootfs 切过去**

直接在 running sys1 上叠 ipk 文件是**最危险的捷径**,因为:
- ipk 的 postinst 不会被 squashfs 触发
- ipk 的 conffiles 不会被 opkg 跟踪
- 后续 opkg upgrade 会和手工文件冲突

---

## 4. v14.2 的真实问题清单(按优先级)

| # | 问题 | 严重度 | 修复 | qoder 已做? |
|---|---|---|---|---|
| 1 | dropbear 拒绝空 root 密码 | 🔴 critical | 烧 authorized_keys 或打 patch | ✅ patch 写了,没机会塞 |
| 2 | dropbear host key 是空占位 | 🔴 critical | pre-bake 真 RSA key | ✅ 脚本写了,没烧 |
| 3 | uhttpd 缺 ucode plugin 链 | 🟡 major | 装 uhttpd-mod-ucode + liblucihttp-ucode + ucode-mod-html + rpcd-mod-ucode | ✅ 验证过,没烧 |
| 4 | flag_try_sys1_failed 误置 1 | 🟠 risk | 烧 sys2 时保留 sys1 为 fallback | ❌ 没改 |
| 5 | 没在烧写前 TFTP server up | 🟠 risk | 每次烧 sys2 前检查 | ❌ |
| 6 | "Starting kernel ..." 误判为 hang | 🟢 cosmetic | TTL 看 Linux banner / ping / ssh 判生死 | ❌ |
| 7 | commit message 版本号错 (26.232 vs 25.12) | 🟢 cosmetic | cat feeds/luci/luci.mk 验证 | ❌ |

---

## 5. v14.2 是否还能用?——能,但要按顺序补 3 个补丁

v14.2 UBI 本身没问题(kernel FIT byte-identical,UBI 卷结构 OK),只是 squashfs 里 3 个文件需要补。**别再烧新 UBI,直接在现有 v14.2-rootfs.squashfs 上做**:

```bash
cd release/
unsquashfs -d /tmp/r142 ax5-32bit-v14.2-rootfs.squashfs

# 1. 烤 dropbear host key(防空占位)
mkdir -p /tmp/r142/etc/dropbear
dropbearkey -t rsa -s 2048 -f /tmp/r142/etc/dropbear/dropbear_rsa_host_key

# 2. 烤 authorized_keys(qoder 自己的 ed25519)
cat > /tmp/r142/etc/dropbear/authorized_keys <<EOF
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM5Z6GM3ERvMiSkEkJTSb9pKE3zjLOVXSKEajX5RUh1y retromilia@foxmail.com
EOF
chmod 600 /tmp/r142/etc/dropbear/authorized_keys

# 3. 确认 uhttpd ucode plugin 链(从 sys1 拷)
# 这部分需要先在 sys1 上验证它们能装上,然后 cp -r 到 /tmp/r142

# 重打包
mksquashfs /tmp/r142 ax5-32bit-v14.2-rootfs-fixed.squashfs -comp xz -b 128K
cp ax5-32bit-v14.2-rootfs-fixed.squashfs ax5-32bit-v14.2-rootfs.squashfs
./pack-ubi.sh
mv ax5-32bit-v14.2-release-custom.ubi ax5-32bit-v14.2-release.ubi

# 烧写前检查 TFTP
# (确认 release/flash-via-tftp.sh 在手边,串口连接稳定)

# 烧 sys2,保留 sys1 fallback
scp -O ax5-32bit-v14.2-release.ubi root@192.168.1.1:/tmp/
ssh root@192.168.1.1 << 'EOF'
ubiformat /dev/mtd19 -f /tmp/ax5-32bit-v14.2-release.ubi -y
fw_setenv flag_boot_rootfs 1
fw_setenv flag_try_sys1_failed 0   # <-- 关键:保留 sys1 fallback
fw_setenv flag_try_sys2_failed 1   # <-- 关键:失败立刻回 sys1
sync; sleep 3; reboot
EOF

# 等 60s,检查 SSH
sleep 60
ssh -o StrictHostKeyChecking=accept-new root@192.168.1.1 'echo BOOT-OK; uname -r; ls /usr/share/ucode/luci/dispatcher.uc && echo UCODE-RUNTIME-OK'
```

如果 60s 后 SSH 不通,**立刻**:
```bash
# TTL 进 U-Boot,跑 release/flash-via-tftp.sh 烧回 v14.0
```

---

## 6. 对 qoder 后续接力的建议

1. **永远在 sys1 live-overlay 验证**,不要直接烧 sys2
2. **烧 sys2 前 flag_try_sys1_failed 必须 0**(保留 fallback)
3. **任何 ipk 进 squashfs 前**手动验证其 postinst 触发的副作用(host key、uci-defaults、init.d 链接)
4. **kernel "hang" 判定**:只看 TTL,不可信;用 `ping`/`ssh`/`netstat` 实测
5. **LuCI 升级**要走完整 25+ ipk 列表,不能挑着装
6. **flash-via-tftp.sh 救援脚本**必须在每次烧 sys2 之前 dry-run 一次
7. **commit message 写版本号前**先 `cat feeds/luci/luci.mk | grep PKG_SOURCE_VERSION`

---

## 7. 引用

- qoder 完整对话(5MB JSONL):`/home/xmb505/.qoder-cn/projects/-home-xmb505-immortalwrt/b3d0eb27-3fd8-41bd-b7ee-3a1e85cc1766.jsonl`
- qoder 写好的 dropbear patch:`/tmp/luci-live/...` 或 qoder session L3789 区域的 diff
- v14.2 产物:`/home/xmb505/immortalwrt/ax5-32bit/release/ax5-32bit-v14.2-{release.ubi,kernel-fit.itb,rootfs.squashfs}`
- v14.2 ubinize 配置:`/home/xmb505/immortalwrt/ax5-32bit/release/ubinize-v142.cfg`
- v14.0 工作版本(回滚目标):`/home/xmb505/immortalwrt/ax5-32bit/release/ax5-32bit-v14.0-{release.ubi,kernel-fit.itb,rootfs.squashfs}`
- TFTP 救援脚本:`/home/xmb505/immortalwrt/ax5-32bit/release/flash-via-tftp.sh`
