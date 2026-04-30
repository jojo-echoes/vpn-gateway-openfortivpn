#!/bin/bash
# 99-verify.sh — 一鍵自我檢測
set -u

ok()   { echo -e "  \033[32m✓\033[0m $*"; }
bad()  { echo -e "  \033[31m✗\033[0m $*"; }
warn() { echo -e "  \033[33m⚠\033[0m $*"; }

echo "=== 1. 套件 ==="
for p in openfortivpn pppd iptables-save; do
    command -v "$p" >/dev/null && ok "$p: $(command -v $p)" || bad "缺少 $p"
done

echo
echo "=== 2. sysctl ==="
v=$(sysctl -n net.ipv4.ip_forward)
[[ "$v" == "1" ]] && ok "net.ipv4.ip_forward = 1" || bad "net.ipv4.ip_forward = $v"

echo
echo "=== 3. 設定檔 ==="
if [ -f /etc/openfortivpn/config ]; then
    ok "/etc/openfortivpn/config 存在"
    for k in 'set-routes\s*=\s*0' 'set-dns\s*=\s*0'; do
        grep -Eq "^$k" /etc/openfortivpn/config \
            && ok "  含 $k" \
            || warn "  未發現 $k （請確認是否關閉 route/DNS 綁架）"
    done
else
    bad "/etc/openfortivpn/config 不存在"
fi

echo
echo "=== 4. ppp ip-up hook ==="
HOOK=/etc/ppp/ip-up.d/00-vpn-gateway-routes
[ -x "$HOOK" ] && ok "$HOOK 存在且可執行" || bad "$HOOK 不存在或不可執行"

echo
echo "=== 5. systemd 服務 ==="
systemctl is-enabled openfortivpn.service 2>/dev/null \
    | grep -q enabled && ok "openfortivpn.service: enabled" \
    || warn "openfortivpn.service 尚未 enable"
systemctl is-active openfortivpn.service 2>/dev/null \
    | grep -q active && ok "openfortivpn.service: active" \
    || warn "openfortivpn.service 尚未 active"

echo
echo "=== 6. ppp0 介面 ==="
if ip -4 addr show ppp0 &>/dev/null; then
    ok "ppp0 UP"
    ip -4 addr show ppp0 | grep inet | sed 's/^/    /'
else
    warn "ppp0 尚未建立"
fi

echo
echo "=== 7. 公司網段路由 ==="
for net in 163.17.38.0/24 163.17.40.0/24 140.128.53.0/24; do
    ip route show "$net" | grep -q "dev ppp0" \
        && ok "$net -> ppp0" \
        || warn "$net 未指向 ppp0"
done

echo
echo "=== 8. 預設路由（不應走 ppp0） ==="
def=$(ip route show default | head -1)
echo "    $def"
echo "$def" | grep -q "dev ppp0" \
    && bad "預設路由跑到 ppp0 —— 表示 underlay 被綁架了！" \
    || ok "預設路由仍走 underlay（正確）"

echo
echo "=== 9. iptables ==="
iptables -t nat -C POSTROUTING -o ppp0 -j MASQUERADE 2>/dev/null \
    && ok "NAT POSTROUTING -o ppp0 MASQUERADE 已存在" \
    || bad "缺少 NAT MASQUERADE 規則"
