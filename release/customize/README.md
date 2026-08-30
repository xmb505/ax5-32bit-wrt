# OpenWrt 固件文件组织

`files/` 目录直接镜像路由器文件系统根目录，ImageBuilder 直接 `cp -r files/* target/` 即可。

## 结构

**main（共用资源）：**
```
files/
├── README.md
└── etc/morden_web/
    ├── favicon.png         # 共用浏览器标签图标
    └── background.jpg      # 共用登录页背景
```

**机型 branch（merge main 后，叠加机型专属文件）：**
```
files/
├── etc/
│   ├── morden_web/
│   │   ├── favicon.png     # 来自 main
│   │   ├── background.jpg  # 来自 main
│   │   └── config.json     # 本机型品牌配置
│   ├── init.d/haku_wrt     # procd 服务脚本
│   ├── uci-defaults/       # 首启脚本（仅 ax5，遗留；新机型不要再用）
│   ├── config/             # UCI 配置覆盖（newifid2/ax6/ax3600/ax3000t）
│   │                       #   newifid2 的 network 含救命口 backend 接口
│   │                       #   （br-lan 第二 IP 10.114.51.4/24，程序永不触碰）
│   ├── passwd              # ax6/ax3600/ax3000t
│   └── shadow
└── usr/bin/haku_wrt        # make package 自动填入，不进 git
```

## 机型配置原则

1. **优先 files 覆盖，尽量不用首启脚本（uci-defaults）。**
   files 覆盖是声明式的、可静态审查、刷进去就生效；首启脚本是一次性命令式逻辑，
   跑完即删、出错难查、容易和固件默认行为打架。
2. **覆盖文件必须从真机拉取，不要手写。**
   流程：真机调好 → `ssh root@<device> cat /etc/config/<name>` 落盘到 files → 逐行核对再入库。
   真机跑通的配置才是事实，手写配置是猜测。
3. **拉取后逐行核对两样东西**：
   - 每设备独有的值（如 ULA 前缀、设备专属 MAC）——不应入库的剥掉，让首启自动重新生成
   - 个体调整值（如测试机临时改的信道）——确认它是出厂默认还是个体状态
4. 实在需要运行时逻辑（每设备随机值等）才用首启脚本，且只放做不了的那几行。

## 分支

```
main        # 项目骨架 + 共用资源
├── newifid2    # Newifi D2 (mipsle, mt7621) — 固件更新
├── ax5         # Redmi AX5 (aarch64, IPQ6000) — 软件更新
├── ax6         # Redmi AX6 (aarch64, IPQ8071A) — 软件更新
├── ax3600      # Xiaomi AX3600 (aarch64, IPQ8074A) — 软件更新
└── ax3000t     # Xiaomi AX3000T (aarch64, MT7981B) — 固件更新
```

## 本地开发布局（git worktree）

```
morden_wrt_control_panel/       # main（日常开发 Go/Vue）
└── models/
    ├── newifid2/
    ├── ax5/
    ├── ax6/
    ├── ax3600/
    └── ax3000t/
```

## 工作流

1. **改通用代码**：在 main 开发，commit + push
2. **同步到机型**：在对应 worktree 里 `git merge main`
3. **编译打包**：在对应 worktree 里 `make package-aarch64`（或对应架构）
4. **改机型配置**：直接在对应 worktree 里改 `files/etc/` 下的文件

## 新增机型

1. `git checkout -b <model> main`
2. 建 `files/etc/{init.d,morden_web}` 目录
3. 写 `config.json`（model_name / firmware_name / title）
4. 从真机拉取 `/etc/config/*` 等文件做覆盖（见「机型配置原则」），避免写首启脚本
5. `make package-<arch>` 验证

## 注意事项

- `files/usr/bin/` 由 `make package` 生成，**不要提交二进制**
- `config.json` 里的路径必须是路由器绝对路径（`/etc/morden_web/...`）
- `uci-defaults` 脚本只在首启跑一次——遗留方式，新配置一律走 files 覆盖（见「机型配置原则」）
- **每次 `build` / `cross-*` / `package-*` / `deploy` 都会自动 bump 版本号**（改 `files/etc/morden_web/config.json`），**测试部署也涨是有意为之**：版本号跟随构建次数，每个上设备的二进制都有唯一版本可追溯，不要回退丢弃。bump 后的 config.json 记得随代码一并提交
