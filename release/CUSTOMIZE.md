# 自定义 rootfs 指南 (customize 工作流)

> 目标：任何人 clone 本仓库后，都能在不编译 QSDK 源码的情况下
> 1. 重新打包出可刷的 AX5 UBI 固件；
> 2. 把自己的文件/脚本/二进制塞进 rootfs。

## 依赖 (仅开发机需要)

```bash
# Debian / Ubuntu
sudo apt install squashfs-tools mtd-utils xz-utils
```

## 三步走

```bash
cd release/

# 1. 把自定义文件按目标路径放进 customize/
mkdir -p customize/usr/bin
cp /path/to/myapp customize/usr/bin/
chmod +x customize/usr/bin/myapp

# 2. 一键重打包 (解包 -> 注入 -> mksquashfs xz -> ubinize)
./customize.sh

# 3. 刷机 (路由器 SSH 里执行)
scp ax5-32bit-v13.9-release-custom.ubi root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'ubiformat /dev/mtd19 -f /tmp/ax5-32bit-v13.9-release-custom.ubi && \
    fw_setenv flag_boot_rootfs 1 && fw_setenv flag_try_sys1_failed 1 && \
    fw_setenv flag_try_sys2_failed 0 && reboot'
```

## customize.sh 做了什么

1. 首次运行把 `ax5-32bit-v13.9-rootfs.squashfs` 备份为 `.orig`，之后永远以 `.orig` 为基底（可反复重跑，不会叠加污染）。
2. `unsquashfs` 解包基底 → 把 `customize/` 整个目录 `cp -a` 覆盖进去（保留权限）。
3. `mksquashfs -comp xz -b 128K` 重打包 —— **必须 xz**：NWRT 内核砍掉了 squashfs-zlib 支持，用 gzip/zstd 打包会挂载 panic。
4. 调 `pack-ubi.sh` → `ubinize`（-m 2048 -p 128KiB -s 2048，对应 AX5 NAND 参数）产出 `ax5-32bit-v13.9-release-custom.ubi`。

UBI 卷结构（`ubinize.cfg`）：

| 卷 | 名称 | 类型 | 内容 |
|---|---|---|---|
| vol0 | `kernel` | static | NWRT 5.4.213 FIT 内核（勿动，动了 Secure Boot 过不了） |
| vol1 | `rootfs` | dynamic + autoresize | 你改的 squashfs |

## 常见坑

- **kernel 卷名必须叫 `kernel`、rootfs 卷名必须叫 `rootfs`**：内核补丁只认这两个名字建 ubiblock 设备。
- **不要动 kernel-fit.itb**：这是从小米原厂 UBI 里按 124KB LEB 高精度剥离出来的签名内核，任何修改都会导致 Secure Boot 拒绝启动。
- **同名文件直接覆盖**：往 `customize/etc/` 放文件前先想清楚是不是要覆盖。
- **rootfs 只剩约 7MB 余量**（24MB 卷 - 已用约 17MB），大文件请三思。
- 变砖了用 `flash-via-tftp.sh` 里的串口 U-Boot 命令救回。

完整拼装原理见 `CHECKSUM.txt` 后半部分和 `doc/NWRT_FACTORY_REFERENCE.md`。
