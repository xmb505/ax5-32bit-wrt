# customize/ — 你的自定义文件放这里

把想塞进 AX5 rootfs 的文件按**目标路径结构**放进来，然后运行上一级的 `customize.sh`。

示例：

```
customize/
├── usr/bin/myapp              # 会被放到路由器的 /usr/bin/myapp
├── etc/myapp.conf             # -> /etc/myapp.conf
└── etc/rc.local               # ⚠️ 同名文件会直接覆盖原文件！
```

## 注意事项

1. **同名覆盖**：与 rootfs 里已有文件同路径的文件会**直接覆盖**原文件。
   改 WiFi 密码/SSID 不建议改文件，刷好后用 `uci` 命令改更安全（见 doc/WIFI_IMPLEMENTATION.md）。
2. **可执行权限**：脚本会 `cp -a` 保留权限，所以放进来前记得 `chmod +x` 你的二进制/脚本。
3. **架构**：AX5 是 **32-bit ARMv7 (arm_cortex-a7, musl libc)**，别塞 x86 或 64 位二进制。
4. **空间**：rootfs 分区约 24MB，当前已用约 17MB，剩余空间有限，别塞大文件。
5. 本目录下的 `README.md` 不会被打包进镜像。
