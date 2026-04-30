#!/bin/bash

# 取得腳本所在目錄的絕對路徑
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# 清理函數：確保臨時文件被刪除
cleanup() {
    rm -f /tmp/vpn-connect-wrapper.sh
}

# 註冊清理函數，在腳本退出時執行（無論正常或異常退出）
trap cleanup EXIT INT TERM

echo "=========================================="
echo "Fortigate VPN 連接腳本"
echo "=========================================="

# 檢查設定檔（改用相對路徑）
if [ ! -f "$SCRIPT_DIR/fortigate.conf" ]; then
    echo "✗ 找不到設定檔: $SCRIPT_DIR/fortigate.conf"
    echo "提示：請參考 fortigate.conf.example 建立設定檔"
    exit 1
fi

# 動態偵測當前網路環境
echo ""
echo "=== 連接前的網路狀態 ==="
CURRENT_IP=$(ip route get 8.8.8.8 2>/dev/null | head -1 | awk '{print $7}')
ORIGINAL_GW=$(ip route | grep default | awk '{print $3}' | head -1)
ORIGINAL_IF=$(ip route | grep default | awk '{print $5}' | head -1)

# 更精確的 LAN 網段偵測（使用本機 IP 對應的網段）
LAN_NETWORK=$(ip route | grep "proto kernel scope link src $CURRENT_IP" | awk '{print $1}')

echo "當前 IP: $CURRENT_IP"
echo "預設閘道: $ORIGINAL_GW (介面: $ORIGINAL_IF)"
echo "LAN 網段: $LAN_NETWORK"

# 從 LAN 網段計算可能的 Windows IP
if [ -n "$LAN_NETWORK" ]; then
    LAN_PREFIX=$(echo $LAN_NETWORK | cut -d'/' -f1 | cut -d'.' -f1-3)
    WINDOWS_IP="${LAN_PREFIX}.148"
else
    WINDOWS_IP="192.168.88.148"  # 預設值
fi

echo "推測 Windows IP: $WINDOWS_IP"

# 檢查是否已經連接 VPN
if ip addr show ppp0 >/dev/null 2>&1; then
    echo ""
    echo "⚠ VPN 已經連接"
    ip addr show ppp0 | grep "inet "
    echo ""
    echo "使用 $SCRIPT_DIR/show-vpn-status.sh 查看詳細狀態"
    exit 0
fi

# 檢查 screen 是否安裝
if ! command -v screen &>/dev/null; then
    echo "✗ 需要安裝 screen"
    echo "  執行: sudo apt install screen"
    exit 1
fi

# 檢查是否有 pass（YubiKey/GPG 方案）
if command -v pass >/dev/null 2>&1; then
    echo ""
    echo "=== 檢測 YubiKey/GPG 密碼管理器 ==="
    
    # 檢查 YubiKey 硬體是否連接
    if gpg --card-status &>/dev/null; then
        echo "✓ 已檢測到 YubiKey"
        echo "⚠️  請準備輸入 PIN（如果需要）"
        
        # 這時才真正觸發 YubiKey
        VPN_PASSWORD=$(pass show vpn/fortigate 2>&1)
        
        if [ $? -ne 0 ]; then
            echo "✗ 無法從 pass 取得密碼"
            echo "   可能原因：PIN 輸入錯誤、YubiKey 未授權、或密碼未設置"
            echo ""
            echo "將使用手動輸入模式..."
            USE_MANUAL=1
        else
            echo "✓ 已從 pass 取得密碼"
            USE_PASS=1
        fi
    else
        echo "⚠️  未檢測到 YubiKey"
        echo "   將使用手動輸入模式..."
        USE_MANUAL=1
    fi
else
    echo ""
    echo "⚠️  未安裝 pass 密碼管理器"
    echo "   將使用手動輸入模式..."
    USE_MANUAL=1
fi

# 啟動 VPN
echo ""
echo "=== 啟動 VPN 連接 ==="
echo "正在連接到 Fortigate (163.17.117.94:34401)..."

# 建立臨時腳本用於 screen 內執行
cat > /tmp/vpn-connect-wrapper.sh << 'WRAPPER_EOF'
#!/bin/bash
SCRIPT_DIR=$1

echo ""
echo "=========================================="
echo "⚠️  手動輸入密碼模式"
echo "=========================================="
echo ""
echo "接下來會出現以下提示："
echo "  1. [sudo] password for jojo: ← 輸入 Linux sudo 密碼"
echo "  2. VPN account password: ← 只需輸入 VPN 密碼即可"
echo ""
echo "說明："
echo "  • VPN 帳號已在設定檔中（jojoboyx）"
echo "  • 只需要輸入密碼，不需要輸入帳號"
echo "  • 密碼輸入時不會顯示任何字元（正常現象）"
echo ""
echo "=========================================="
echo ""

# 等待並顯示 VPN 狀態
check_vpn_status() {
    echo ""
    echo "=== 等待 VPN 介面建立 ==="
    
    # 等待 ppp0 出現
    for i in {1..60}; do
        if ip addr show ppp0 &>/dev/null 2>&1; then
            echo "✓ VPN 介面 ppp0 已建立"
            break
        fi
        sleep 1
        if [ $((i % 5)) -eq 0 ]; then
            echo -n "."
        fi
    done
    
    if ! ip addr show ppp0 &>/dev/null 2>&1; then
        echo "✗ VPN 連接失敗"
        return 1
    fi
    
    # 顯示 VPN IP
    VPN_IP=$(ip addr show ppp0 | grep "inet " | awk '{print $2}')
    echo "VPN IP: $VPN_IP"
    
    # 等待路由更新
    sleep 2
    
    # 顯示路由表（Server 推送的路由）
    echo ""
    echo "=== Server 推送的路由 ==="
    ip route show | grep "dev ppp0" | head -10
    
    # 測試連接
    echo ""
    echo "=== 測試連接 ==="
    if ping -c 2 -W 3 163.17.38.238 &>/dev/null; then
        echo "✓ Cisco 設備 (163.17.38.238) 可達"
    else
        echo "⚠ Cisco 設備 ping 失敗（可能禁止 ICMP）"
    fi
    
    echo ""
    echo "=========================================="
    echo "✓ VPN 連接完成（由 Fortigate Server 管理路由）"
    echo "=========================================="
    echo "現在可以 SSH 到 Cisco:"
    echo "  ssh admin@163.17.38.238"
    echo ""
    echo "中斷 VPN: $SCRIPT_DIR/disconnect-vpn.sh"
    echo "查看狀態: $SCRIPT_DIR/show-vpn-status.sh"
    echo ""
    echo "按 Ctrl+A 然後 D 離開（VPN 繼續運行）"
    echo "重新連接: screen -r vpn"
    echo "=========================================="
}

# 在背景執行狀態檢查
check_vpn_status &

# 啟動 VPN 連接
sudo openfortivpn -c "$SCRIPT_DIR/fortigate.conf"

# VPN 中斷後的清理
echo ""
echo "VPN 已中斷"
WRAPPER_EOF

chmod +x /tmp/vpn-connect-wrapper.sh

# 根據是否有 pass 決定使用方式
if [ "$USE_PASS" = "1" ]; then
    # 使用 pass 取得的密碼
    echo "使用 YubiKey 自動連接..."
    
    # 預先驗證 sudo（避免後台執行時要求密碼）
    echo "⚠️  需要 sudo 權限啟動 VPN"
    sudo -v
    if [ $? -ne 0 ]; then
        echo "✗ sudo 驗證失敗"
        exit 1
    fi
    
    echo "[DEBUG] 正在啟動 openfortivpn..."
    
    # 使用 nohup 在後台啟動 VPN，並將輸出導向日誌
    nohup bash -c "pass vpn/fortigate | sudo openfortivpn -c '$SCRIPT_DIR/fortigate.conf'" > /tmp/vpn-connect.log 2>&1 &
    VPN_PID=$!
    echo "$VPN_PID" > /tmp/vpn.pid  # 保存 PID 供 disconnect 使用
    echo "[DEBUG] VPN 進程 PID: $VPN_PID"
    
    # 等待 VPN 建立
    echo "等待 VPN 介面建立..."
    VPN_CONNECTED=0
    for i in {1..60}; do
        if ip addr show ppp0 &>/dev/null 2>&1; then
            echo ""
            echo "✓ VPN 介面 ppp0 已建立"
            VPN_CONNECTED=1
            break
        fi
        
        # 檢查進程是否還在運行
        if ! kill -0 $VPN_PID 2>/dev/null; then
            echo ""
            echo "✗ VPN 進程已退出"
            echo "[DEBUG] 日誌內容："
            tail -20 /tmp/vpn-connect.log
            exit 1
        fi
        
        sleep 1
        if [ $((i % 5)) -eq 0 ]; then
            echo -n "."
        fi
    done
    echo ""
    
    if [ "$VPN_CONNECTED" -eq 0 ]; then
        echo "✗ VPN 連接超時"
        echo "[DEBUG] 日誌內容："
        tail -20 /tmp/vpn-connect.log
        kill $VPN_PID 2>/dev/null
        exit 1
    fi
    
    # 設定路由
    sleep 3
    
    # 顯示狀態
    VPN_IP=$(ip addr show ppp0 | grep "inet " | awk '{print $2}')
    echo "VPN IP: $VPN_IP"
    
    # 顯示 Server 推送的路由
    echo ""
    echo "=== Server 推送的路由 ==="
    ip route show | grep "dev ppp0" | head -10
    
    echo ""
    echo "=========================================="
    echo "✓ VPN 連接完成（由 Fortigate Server 管理路由）"
    echo "=========================================="
    echo "VPN 進程 PID: $VPN_PID"
    echo "日誌檔案: /tmp/vpn-connect.log"
    echo ""
    echo "現在可以 SSH 到 Cisco:"
    echo "  ssh admin@163.17.38.238"
    echo ""
    echo "中斷 VPN: $SCRIPT_DIR/disconnect-vpn.sh"
    echo "查看狀態: $SCRIPT_DIR/show-vpn-status.sh"
    echo "查看日誌: tail -f /tmp/vpn-connect.log"
    echo "=========================================="
    
else
    # 手動輸入密碼模式
    echo ""
    echo "=========================================="
    echo "⚠️  手動輸入密碼模式"
    echo "=========================================="
    echo ""
    echo "原因：YubiKey 未檢測到 或 pass 密碼管理器不可用"
    echo ""
    echo "接下來的操作："
    echo "  1. 進入 screen 會話（背景運行 VPN）"
    echo "  2. 系統會要求輸入 sudo 密碼"
    echo "  3. 然後要求輸入 VPN 密碼（只需密碼，不需帳號）"
    echo ""
    echo "注意事項："
    echo "  • VPN 帳號已在設定檔：jojoboyx"
    echo "  • 看到「VPN account password:」只需輸入密碼"
    echo "  • 密碼輸入時不會顯示（正常安全機制）"
    echo "  • 連接成功後按 Ctrl+A 然後 D 離開"
    echo "  • 使用 'screen -r vpn' 重新連接"
    echo ""
    echo "按 Enter 繼續..."
    read
    echo "=========================================="
    echo ""
    
    # 在 screen 中執行
    screen -S vpn /tmp/vpn-connect-wrapper.sh "$SCRIPT_DIR"
    
    # screen 結束後顯示訊息
    echo ""
    echo "已離開 VPN 會話"
    echo "VPN 正在背景運行，使用 'screen -r vpn' 重新連接"
fi

# 清理臨時腳本（由 trap 自動執行，這裡保留以提高可讀性）
# cleanup 函數會在腳本退出時自動執行
