#!/bin/bash
# 02-enable-ip-forward.sh — 永久啟用 IPv4 forwarding
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "請以 root / sudo 執行" >&2
    exit 1
fi

CONF=/etc/sysctl.d/99-vpn-gateway.conf
cat > "$CONF" <<'EOF'
# Managed by vpn-gateway-openfortivpn
net.ipv4.ip_forward = 1
# 不接受 ICMP redirects（gateway 上一般關掉）
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
# 反向路徑過濾：用 loose mode 以容納非對稱路由情境
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
EOF

sysctl --system >/dev/null

echo "✓ ip_forward 已啟用：$(sysctl -n net.ipv4.ip_forward)"
