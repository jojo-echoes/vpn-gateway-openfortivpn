#!/bin/bash
# VPN 腳本路徑測試工具

echo "=========================================="
echo "VPN 腳本路徑驗證"
echo "=========================================="
echo ""

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

echo "專案根目錄: $PROJECT_ROOT"
echo "腳本目錄: $SCRIPT_DIR"
echo ""

echo "檢查腳本檔案："
echo ""

# 檢查必要的腳本
files=(
    "connect-vpn.sh"
    "disconnect-vpn.sh"
    "show-vpn-status.sh"
    "fortigate.conf"
    "fortigate.conf.example"
)

for file in "${files[@]}"; do
    if [ -f "$SCRIPT_DIR/$file" ]; then
        echo "  ✓ $file"
    else
        if [ "$file" = "fortigate.conf" ]; then
            echo "  ⚠ $file (需要從 fortigate.conf.example 複製)"
        else
            echo "  ✗ $file (缺少)"
        fi
    fi
done

echo ""
echo "檢查執行權限："
echo ""

for script in "connect-vpn.sh" "disconnect-vpn.sh" "show-vpn-status.sh"; do
    if [ -x "$SCRIPT_DIR/$script" ]; then
        echo "  ✓ $script 可執行"
    else
        echo "  ✗ $script 不可執行 (執行: chmod +x scripts/$script)"
    fi
done

echo ""
echo "測試 SCRIPT_DIR 變數在各腳本中的使用："
echo ""

# 測試 connect-vpn.sh 中的 SCRIPT_DIR
if grep -q 'SCRIPT_DIR=$(cd' "$SCRIPT_DIR/connect-vpn.sh"; then
    echo "  ✓ connect-vpn.sh 使用 SCRIPT_DIR 變數"
else
    echo "  ✗ connect-vpn.sh 未正確設定 SCRIPT_DIR"
fi

# 檢查是否還有 ~/.vpn/ 引用
echo ""
echo "檢查舊路徑引用 (~/.vpn/)："
echo ""

for script in "connect-vpn.sh" "disconnect-vpn.sh" "show-vpn-status.sh"; do
    count=$(grep -c '~/.vpn/' "$SCRIPT_DIR/$script" 2>/dev/null || echo 0)
    if [ "$count" -eq 0 ]; then
        echo "  ✓ $script 無舊路徑引用"
    else
        echo "  ⚠ $script 還有 $count 處舊路徑引用"
        grep -n '~/.vpn/' "$SCRIPT_DIR/$script" | sed 's/^/    /'
    fi
done

echo ""
echo "=========================================="
echo "建議執行："
echo ""
echo "1. 複製設定檔："
echo "   cp scripts/fortigate.conf.example scripts/fortigate.conf"
echo ""
echo "2. 編輯設定檔填入真實資訊"
echo ""
echo "3. 測試連線："
echo "   ./scripts/connect-vpn.sh"
echo ""
echo "=========================================="
