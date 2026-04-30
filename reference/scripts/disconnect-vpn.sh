#!/bin/bash

echo "=== 中斷 VPN 連接 ==="

if ! ip addr show ppp0 >/dev/null 2>&1; then
    echo "✗ VPN 未連接"
    exit 0
fi

# 顯示當前 VPN 狀態
echo "當前 VPN IP: $(ip addr show ppp0 | grep "inet " | awk '{print $2}')"

# 檢查並終止 YubiKey 自動模式（nohup）
if [ -f /tmp/vpn.pid ]; then
    VPN_PID=$(cat /tmp/vpn.pid)
    echo "檢測到 YubiKey 自動模式 (PID: $VPN_PID)"
    
    # 嘗試正常終止
    if kill -0 $VPN_PID 2>/dev/null; then
        echo "正在終止 VPN 進程..."
        sudo kill $VPN_PID
        sleep 2
    fi
    
    rm -f /tmp/vpn.pid
fi

# 檢查並終止手動模式（screen）
if screen -list 2>/dev/null | grep -q "vpn"; then
    echo "檢測到 screen 會話"
    echo "正在終止 screen 會話..."
    screen -X -S vpn quit 2>/dev/null
fi

# 終止所有 openfortivpn 進程（路由會自動清除）
echo "正在終止 openfortivpn..."
sudo pkill openfortivpn

# 等待介面關閉
sleep 2

if ip addr show ppp0 >/dev/null 2>&1; then
    echo "✗ VPN 仍在運行，嘗試強制終止..."
    sudo pkill -9 openfortivpn
    sleep 1
    
    if ip addr show ppp0 >/dev/null 2>&1; then
        echo "✗ VPN 無法終止，可能需要手動處理"
        exit 1
    fi
fi

# 清理日誌文件和 PID 文件
rm -f /tmp/vpn-connect.log /tmp/vpn.pid

echo "✓ VPN 已中斷"