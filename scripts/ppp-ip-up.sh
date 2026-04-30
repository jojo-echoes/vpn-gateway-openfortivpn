#!/bin/bash
# /etc/ppp/ip-up.d/00-vpn-gateway-routes
#
# 由 pppd 在 ppp0 介面 UP 之後自動呼叫。引數：
#   $1 = interface (e.g. ppp0)
#   $2 = tty
#   $3 = speed
#   $4 = local IP
#   $5 = remote IP
#   $6 = ipparam
#
# 因為 openfortivpn 設定了 set-routes=0，所有要走 VPN 的網段都必須在這裡手動加。
# 修改 ROUTES 陣列即可新增/刪除公司網段。

set -e

IFACE="$1"
[ "$IFACE" = "ppp0" ] || exit 0

LOG=/var/log/vpn-gateway-routes.log
log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

ROUTES=(
    "163.17.38.0/24"
    "163.17.40.0/24"
    "140.128.53.0/24"
)

log "ppp0 UP — adding ${#ROUTES[@]} corporate routes"
for net in "${ROUTES[@]}"; do
    ip route replace "$net" dev "$IFACE" \
        && log "  + $net dev $IFACE" \
        || log "  ! failed to add $net"
done

exit 0
