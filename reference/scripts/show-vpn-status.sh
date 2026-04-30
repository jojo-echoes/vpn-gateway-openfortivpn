#!/bin/bash

echo "=========================================="
echo "VPN 狀態檢查"
echo "=========================================="

# 動態偵測當前網路環境
CURRENT_IP=$(ip route get 8.8.8.8 2>/dev/null | head -1 | awk '{print $7}')

# 更精確的 LAN 網段偵測
if ip addr show ppp0 >/dev/null 2>&1; then
    # VPN 已連接，需要排除 ppp0 路由，只取 LAN 路由
    LAN_NETWORK=$(ip route | grep -v ppp0 | grep "proto kernel scope link src $CURRENT_IP" | awk '{print $1}')
else
    # VPN 未連接
    LAN_NETWORK=$(ip route | grep "proto kernel scope link src $CURRENT_IP" | awk '{print $1}')
fi

if [ -n "$LAN_NETWORK" ]; then
    LAN_PREFIX=$(echo $LAN_NETWORK | cut -d'/' -f1 | cut -d'.' -f1-3)
    WINDOWS_IP="${LAN_PREFIX}.148"
else
    WINDOWS_IP="192.168.88.148"
fi

echo "當前環境："
echo "  本機 IP: $CURRENT_IP"
echo "  LAN 網段: $LAN_NETWORK"
echo "  推測 Windows IP: $WINDOWS_IP"
echo ""

if ip addr show ppp0 >/dev/null 2>&1; then
    echo "✓ VPN 已連接"
    echo ""
    echo "VPN 介面資訊："
    ip addr show ppp0 | grep "inet "
    echo ""
    echo "VPN 相關路由："
    ip route show | grep ppp0
    echo ""
    echo "預設閘道："
    ip route | grep default
    echo ""
    
    # 檢查 VPN 連接模式和進程狀態
    echo "VPN 連接模式："
    
    # 檢查 YubiKey 自動模式（nohup + PID 文件）
    if [ -f /tmp/vpn.pid ]; then
        VPN_PID=$(cat /tmp/vpn.pid)
        if kill -0 $VPN_PID 2>/dev/null; then
            echo "  ✓ YubiKey 自動模式 (PID: $VPN_PID)"
            echo "    日誌檔案: /tmp/vpn-connect.log"
        else
            echo "  ⚠ YubiKey 自動模式 (PID 文件存在但進程已退出)"
        fi
    # 檢查手動模式（screen）
    elif screen -list 2>/dev/null | grep -q "vpn"; then
        VPN_PID=$(pgrep -x openfortivpn 2>/dev/null)
        echo "  ✓ 手動模式 (screen 會話)"
        if [ -n "$VPN_PID" ]; then
            echo "    進程 PID: $VPN_PID"
        fi
        echo "    重新連接: screen -r vpn"
    # 都不是，但有 openfortivpn 進程
    elif pgrep -x openfortivpn &>/dev/null; then
        VPN_PID=$(pgrep -x openfortivpn)
        echo "  ⚠ 未知模式 (進程 PID: $VPN_PID)"
        echo "    可能不是由 connect-vpn.sh 啟動"
    else
        echo "  ✗ VPN 進程未運行"
    fi
    
    echo ""
    echo "測試連接："
    if ping -c 1 -W 2 163.17.38.238 &>/dev/null; then
        echo "  ✓ Cisco 設備 (163.17.38.238) 可達"
    else
        echo "  ⚠ Cisco 設備 ping 失敗"
    fi
    
    if ping -c 1 -W 2 $WINDOWS_IP &>/dev/null; then
        echo "  ✓ Windows ($WINDOWS_IP) 可達"
    else
        echo "  ⚠ Windows ($WINDOWS_IP) 連接失敗"
    fi
    
    echo ""
    echo "對外 IP (Split Tunneling 檢查)："
    EXTERNAL_IP=$(curl -s --max-time 2 ifconfig.me)
    if [ -n "$EXTERNAL_IP" ]; then
        echo "  $EXTERNAL_IP"
    else
        echo "  檢查超時"
    fi
    echo ""
    
else
    echo "✗ VPN 未連接"
    echo ""
    echo "使用以下命令連接："
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    echo "  $SCRIPT_DIR/connect-vpn.sh"
fi

echo "=========================================="