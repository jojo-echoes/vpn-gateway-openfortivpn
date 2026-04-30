#!/bin/bash
# 03-setup-iptables.sh — 設定 NAT MASQUERADE on ppp0 + FORWARD 規則並持久化
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "請以 root / sudo 執行" >&2
    exit 1
fi

# 偵測對外（LAN 側）介面：以 default route 對應的介面為準
LAN_IF="$(ip route show default | awk '/default/ {print $5; exit}')"
LAN_IF="${LAN_IF:-eth0}"
echo "LAN 側介面：$LAN_IF"
echo "VPN 側介面：ppp0（由 openfortivpn 啟動時建立）"

# --- NAT：所有走 ppp0 出去的封包都用 ppp0 的 IP 做 MASQUERADE ---
iptables -t nat -C POSTROUTING -o ppp0 -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -o ppp0 -j MASQUERADE

# --- FORWARD：允許 LAN -> VPN，及回程 ---
iptables -C FORWARD -i "$LAN_IF" -o ppp0 -j ACCEPT 2>/dev/null \
    || iptables -A FORWARD -i "$LAN_IF" -o ppp0 -j ACCEPT

iptables -C FORWARD -i ppp0 -o "$LAN_IF" \
        -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
    || iptables -A FORWARD -i ppp0 -o "$LAN_IF" \
        -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# --- 持久化 ---
mkdir -p /etc/iptables
iptables-save  > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true

echo "✓ iptables 規則已套用並寫入 /etc/iptables/rules.v4"
iptables -t nat -nvL POSTROUTING
iptables -nvL FORWARD
