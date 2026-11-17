#!/usr/bin/env bash
# agentdesk 安装：Fedora 零 sudo —— 依赖 RPM 解包到 ~/.local/agentdesk/root，不写 /usr
# 前置：能访问 dnf 仓库；Xvfb 没在跑（先 `agentdesk stop`，否则覆盖二进制会报 Text file busy）
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # 仓库 etc/ 目录
A="$HOME/.local/agentdesk"; mkdir -p "$A"/{rpm,root,var/log,var/pid,var/shots,etc/openbox,bin}

# 1) 取包（含依赖）—— rootless dnf download，不装系统包
cd "$A/rpm"
dnf download --resolve --destdir=. \
  xorg-x11-server-Xvfb xdotool x11vnc openbox novnc xclip

# 2) 解包到私有前缀（/usr/* → $A/root/*，/etc/xdg/openbox → $A/etc/openbox）
for f in *.rpm; do
  d=$(mktemp -d); rpm2cpio "$f" | (cd "$d" && cpio -idm --quiet)
  [ -d "$d/usr" ] && cp -a "$d/usr/." "$A/root/"
  [ -d "$d/etc/xdg/openbox" ] && cp -a "$d/etc/xdg/openbox/." "$A/etc/openbox/"
  rm -rf "$d"
done

# 3) noVNC 的 WebSocket 桥（python 包，装到用户目录）
pip install --user -q websockify

# 4) 放 CLI / 配置 / 桌面主题，建软链
install -m 755 "$HERE/../bin/agentdesk" "$A/bin/agentdesk"
[ -f "$A/etc/agentdesk.conf" ] || install -m 644 "$HERE/agentdesk.conf" "$A/etc/agentdesk.conf"
[ -f "$A/etc/openbox/rc.xml" ] || install -m 644 "$HERE/openbox/rc.xml" "$A/etc/openbox/rc.xml"
mkdir -p "$HOME/.local/bin" && ln -sfn "$A/bin/agentdesk" "$HOME/.local/bin/agentdesk"

echo "OK → $A/bin/agentdesk"
echo "下一步：agentdesk start && agentdesk service enable"
