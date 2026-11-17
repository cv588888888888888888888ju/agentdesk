# agentdesk

A **rootless, headless X11 desktop for AI agents** on Fedora — Xvfb + openbox + x11vnc + noVNC, all unpacked into `~/.local/agentdesk` (no `/usr`, no sudo, never touches your real `:0` desktop).

给 AI agent 用的独立无头桌面：截图、点按、打字都在自己的 `:99` 上，不打扰你正在用的屏幕。

## 特性

- **零 sudo**：依赖 RPM 全部 `rpm2cpio` 解包到私有前缀 `~/.local/agentdesk/root`
- **不碰真桌面**：独立 display，不抢焦点、不截你的屏（默认软件渲染；`AD_GPU=zink` 可让 GL 走 iGPU/Vulkan，见「GPU 模式」）
- **动作齐全**：全屏截图、鼠标移动/点击/拖拽/滚轮、ASCII 打字、中文走剪贴板（`xclip` + Ctrl+V）、按键组合
- **程序记账**：`app` 拉起的程序记进 `var/apps.tsv`，`kill-app` 只杀这些，不误伤你自己的进程
- **浏览器旁观**：noVNC 页面 `http://127.0.0.1:6080/vnc.html`（默认只绑 127.0.0.1）
- **空闲冻结**：1 小时无操作自动 `SIGSTOP` 整块桌面——保留现场、CPU 归零；任何动作命令先自动解冻，有 VNC 旁观连接时不冻
- **systemd --user 自启**：`agentdesk.service` + `agentdesk-idle.timer`，无窗口

## 安装（Fedora）

```bash
git clone https://github.com/cv588888888888888888888ju/agentdesk.git
cd agentdesk
bash etc/install.sh        # dnf download + 解包 + pip install websockify
agentdesk start            # 起 :99
agentdesk service enable   # 可选：登录自启 + 空闲冻结 timer
```

需要：Fedora（`dnf`）、python3/pip、ImageMagick（`import`/`magick`）。

## 用法

```bash
agentdesk status            # xvfb / wm / vnc / web 四行状态 + 旁观地址 + 空闲/冻结
agentdesk shot [out.png] [--scale 50]
agentdesk windows           # 窗口 id / 尺寸 / 标题（* = 焦点）
agentdesk app <命令...>      # 在 :99 上起 GUI 程序
agentdesk apps | kill-app <pid|all>
agentdesk click X Y [--button 1] [--count 2]
agentdesk move X Y | drag X1 Y1 X2 Y2 | scroll down 5 [--at X Y]
agentdesk type 'ASCII'      # 只支持 ASCII
agentdesk paste '你好，世界' # 中文/非 ASCII：剪贴板 + Ctrl+V
agentdesk key 'ctrl+l' | key Return | key 'alt+Tab'
agentdesk clip get|set 'x'
agentdesk freeze | thaw | idle-check
agentdesk gpu               # 显示当前 GL 后端实测（zink / llvmpipe）
agentdesk run <命令...>      # 带桌面环境变量执行
agentdesk service enable|disable|status
```

## 空闲冻结怎么工作

- `agentdesk-idle.timer` 每 5 分钟跑一次 `agentdesk idle-check`（`AD_IDLE_CHECK_SEC`）。
- 最近一次动作距今超过 `AD_IDLE_FREEZE_SEC`（默认 3600 秒）⇒ 把 Xvfb / openbox / x11vnc / websockify / `app` 起的程序整组 `SIGSTOP`。
- 任何动作命令（`shot/click/type/paste/key/app/run/...`）在分发前自动 `thaw`；`stop` 也先解冻。
- 有一条 ESTABLISHED 到 `AD_VNC_PORT` 的连接（有人在 noVNC 旁观）⇒ 视为在用，空闲计时重置。
- 冻结保留内存与现场（解冻是瞬时的）；要释放内存请 `agentdesk stop`。

配置在 `etc/agentdesk.conf`（首次安装后为 `~/.local/agentdesk/etc/agentdesk.conf`）：

```bash
AD_DISPLAY=":99"          # display 号
AD_GEOMETRY="1920x1080x24"
AD_VNC_PORT="5900"
AD_WEB_PORT="6080"
AD_BIND="127.0.0.1"       # 旁观通道绑定地址（改成 0.0.0.0 请自担风险）
AD_IDLE_FREEZE_SEC="3600" # 空闲多久冻结
AD_IDLE_CHECK_SEC="300"   # timer 检查间隔
AD_GPU="off"              # off|zink|auto：GL 是否走 Vulkan(iGPU)
AD_GPU_ICD=""             # 指定 Vulkan ICD（空=默认设备）
AD_VK_ICD_DIR="/usr/share/vulkan/icd.d"  # auto 模式的探测目录
```

## GPU 模式（可选）

默认 llvmpipe 软件渲染。设 `AD_GPU=zink` 后，本工具拉起的子进程改为 GL → Vulkan → zink（本机实测走 Intel iGPU）：

```bash
AD_GPU=zink agentdesk gpu               # 期望 Device: zink Vulkan … / Accelerated: yes
AD_GPU=zink agentdesk run glxinfo -B
```

- 只换 GL 后端，**截图（import）、输入（xdotool）、VNC 链路都不变**。
- `AD_GPU=auto`：系统有 `/usr/share/vulkan/icd.d/*.json` 才启用，否则退回软件渲染。
- `AD_GPU_ICD=/usr/share/vulkan/icd.d/nouveau_icd.x86_64.json`：可选指定别的 Vulkan 设备；本机 nouveau（RTX 5070）实测 GLX 建上下文失败（`X_GLXCreateNewContext`），默认 Intel iGPU 可用。
- 浏览器要吃到 GPU 还得给 Chromium 系传 ANGLE 参数：
  `agentdesk app chromium --no-sandbox --ozone-platform=x11 --use-gl=angle --use-angle=gl <url>`
  实测网页 `UNMASKED_RENDERER_WEBGL` = `ANGLE (Mesa, zink Vulkan 1.4(Intel …), OpenGL 4.6)`。

## 已知坑（都是踩过的）

- **`pkill` 会杀掉自己**：命令行里含匹配串时 `pkill -f 'Xvfb :99'` 会命中自己这条 shell。用 `agentdesk stop` / `kill-app all`；非用不可写 `'Xvf[b] :99'`。
- **Wayland 环境变量**：残留 `WAYLAND_DISPLAY`/`XDG_SESSION_TYPE=wayland` 会让 x11vnc 秒退、GTK 应用往 wayland 跑。CLI 已 `unset` 并强制 `GDK_BACKEND=x11`。
- **GPU 默认不开**：默认 llvmpipe 软件渲染；`AD_GPU=zink` 才走 iGPU（见「GPU 模式」）。老写法 `MESA_LOADER_DRIVER_OVERRIDE=zink` 在本机会失败（`DRI3 not available`），别用。
- **没有窗口标题栏**：openbox 主题在私有前缀下画不出来，正常，反而利于取坐标。
- **根窗口是纯黑**：本机无 `xsetroot`/`feh`，不铺壁纸。
- **解包覆盖运行中的二进制**会报 `Text file busy`：先 `agentdesk stop`。

## 目录

```
bin/agentdesk         # 全部逻辑（bash）
etc/agentdesk.conf    # 默认配置
etc/install.sh        # 依赖解包安装
etc/openbox/rc.xml    # openbox 配置
var/                  # 运行态：pid / 日志 / 截图 / apps.tsv（不入库）
root/                 # 解包出来的二进制（不入库）
```

## License

MIT — 见 `LICENSE`。
