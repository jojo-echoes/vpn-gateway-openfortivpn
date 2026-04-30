#!/bin/bash

echo "=========================================="
echo "YubiKey VPN 密碼管理工具"
echo "=========================================="
echo ""

# 檢查是否已經設置完成
ALREADY_SETUP=0
if [ -d "$HOME/.password-store" ] && pass show vpn/fortigate >/dev/null 2>&1; then
    ALREADY_SETUP=1
fi

# 如果已設置，顯示管理選單
if [ $ALREADY_SETUP -eq 1 ]; then
    echo "✓ YubiKey VPN 密碼管理已設置"
    echo ""
    echo "請選擇操作："
    echo "  1) 查看當前密碼"
    echo "  2) 更新 VPN 密碼（密碼更換時使用）"
    echo "  3) 測試密碼讀取"
    echo "  4) 連接 VPN"
    echo "  5) 重新初始化設定"
    echo "  0) 離開"
    echo ""
    read -p "請選擇 (0-5): " -n 1 -r
    echo
    echo ""
    
    case $REPLY in
        1)
            echo "=== 查看當前密碼 ==="
            echo "（需要 YubiKey PIN）"
            pass show vpn/fortigate
            exit 0
            ;;
        2)
            echo "=== 更新 VPN 密碼 ==="
            echo "（需要 YubiKey PIN）"
            echo ""
            echo "請輸入新密碼，然後按 Ctrl+O 存檔，Ctrl+X 離開"
            echo ""
            read -p "按 Enter 繼續..."
            pass edit vpn/fortigate
            echo ""
            echo "✓ 密碼已更新！"
            echo "下次連線將自動使用新密碼"
            exit 0
            ;;
        3)
            echo "=== 測試密碼讀取 ==="
            echo "（需要 YubiKey PIN）"
            if pass show vpn/fortigate >/dev/null 2>&1; then
                echo "✓ 密碼讀取成功！"
                echo ""
                echo "YubiKey 運作正常，可以使用自動連線功能"
            else
                echo "✗ 密碼讀取失敗"
                echo ""
                echo "可能原因："
                echo "  - YubiKey 未插入"
                echo "  - PIN 輸入錯誤"
                echo "  - pcscd 服務未啟動"
            fi
            exit 0
            ;;
        4)
            echo "=== 啟動 VPN 連線 ==="
            echo ""
            SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
            bash "$SCRIPT_DIR/connect-vpn.sh"
            exit 0
            ;;
        5)
            echo "=== 重新初始化 ==="
            echo "⚠️  警告：這將清除現有設定"
            read -p "確定要繼續嗎？(y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "已取消"
                exit 0
            fi
            echo ""
            # 繼續執行初始化流程
            ;;
        0)
            echo "已離開"
            exit 0
            ;;
        *)
            echo "無效的選擇"
            exit 1
            ;;
    esac
fi

# 以下是初次設置流程
echo "此腳本將引導您完成 YubiKey + GPG + pass 的設置"
echo "完成後，VPN 密碼將安全加密儲存在 YubiKey 中"
echo ""

# 檢查是否已插入 YubiKey
echo "=== 步驟 1: 檢查 YubiKey ==="
if ! lsusb | grep -i "yubico\|yubikey" >/dev/null 2>&1; then
    echo "⚠️  警告：未偵測到 YubiKey"
    echo ""
    echo "可能原因："
    echo "  1. YubiKey 未插入電腦"
    echo "  2. 如果您在虛擬機中："
    echo "     - VMware: VM → Removable Devices → Yubico → Connect"
    echo "     - VirtualBox: Devices → USB → Yubico YubiKey"
    echo "  3. USB 權限問題（需要 sudo 或 udev 規則）"
    echo ""
    echo "檢查指令："
    echo "  lsusb | grep -i yubi"
    echo ""
    read -p "按 Enter 繼續（如果已插入）或 Ctrl+C 取消..."
else
    echo "✓ 偵測到 YubiKey"
    lsusb | grep -i "yubico\|yubikey"
fi
echo ""

# 檢查並安裝必要軟體
echo "=== 步驟 2: 檢查必要軟體 ==="

PACKAGES_TO_INSTALL=""

if ! command -v gpg >/dev/null 2>&1; then
    echo "✗ 未安裝 GPG"
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL gnupg"
else
    echo "✓ GPG 已安裝: $(gpg --version | head -1)"
fi

if ! command -v pass >/dev/null 2>&1; then
    echo "✗ 未安裝 pass"
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL pass"
else
    echo "✓ pass 已安裝: $(pass version 2>&1 | head -1)"
fi

if ! command -v pcscd >/dev/null 2>&1; then
    echo "✗ 未安裝 pcscd (智慧卡服務)"
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL pcscd"
else
    echo "✓ pcscd 已安裝"
fi

if [ -n "$PACKAGES_TO_INSTALL" ]; then
    echo ""
    echo "需要安裝以下套件: $PACKAGES_TO_INSTALL"
    read -p "是否要安裝？(y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo apt update
        sudo apt install -y $PACKAGES_TO_INSTALL
        
        # 啟動 pcscd 服務
        sudo systemctl start pcscd
        sudo systemctl enable pcscd
    else
        echo "已取消安裝"
        exit 1
    fi
fi
echo ""

# 檢查 GPG 金鑰
echo "=== 步驟 3: 檢查 GPG 金鑰 ==="
if gpg --list-secret-keys | grep -q "sec"; then
    echo "✓ 已有 GPG 金鑰"
    gpg --list-secret-keys --keyid-format SHORT
    echo ""
    read -p "是否要使用現有金鑰？(Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        USE_EXISTING_KEY=1
    fi
fi

if [ -z "$USE_EXISTING_KEY" ]; then
    echo ""
    echo "請選擇 GPG 金鑰設置方式："
    echo "1) 在 YubiKey 上生成新金鑰（推薦，最安全）"
    echo "2) 在電腦上生成新金鑰，然後移動到 YubiKey"
    echo "3) 手動設置（已有金鑰或需要自訂）"
    echo ""
    read -p "請選擇 (1-3): " -n 1 -r
    echo
    
    case $REPLY in
        1)
            echo ""
            echo "=== 在 YubiKey 上生成 GPG 金鑰 ==="
            echo "請參考以下指令："
            echo ""
            echo "  gpg --card-edit"
            echo "  > admin"
            echo "  > generate"
            echo "  > (按照提示操作)"
            echo ""
            echo "詳細教學: https://github.com/drduh/YubiKey-Guide"
            ;;
        2)
            echo ""
            echo "=== 生成 GPG 金鑰 ==="
            gpg --full-generate-key
            echo ""
            echo "金鑰生成完成！"
            echo ""
            echo "接下來需要將金鑰移動到 YubiKey："
            echo "  gpg --edit-key YOUR_KEY_ID"
            echo "  > keytocard"
            ;;
        3)
            echo ""
            echo "請手動完成 GPG 設置後重新執行此腳本"
            exit 0
            ;;
    esac
    
    echo ""
    read -p "按 Enter 繼續設置 pass..."
fi
echo ""

# 初始化 pass
echo "=== 步驟 4: 初始化 pass ==="
if [ -d "$HOME/.password-store" ]; then
    echo "✓ pass 已初始化"
else
    echo "請輸入要用於 pass 的 GPG Key ID："
    gpg --list-secret-keys --keyid-format SHORT
    echo ""
    read -p "GPG Key ID: " GPG_KEY_ID
    
    if [ -n "$GPG_KEY_ID" ]; then
        pass init "$GPG_KEY_ID"
        echo "✓ pass 已初始化"
    else
        echo "✗ 未輸入 Key ID"
        exit 1
    fi
fi
echo ""

# 儲存 VPN 密碼
echo "=== 步驟 5: 儲存 VPN 密碼 ==="
if pass show vpn/fortigate >/dev/null 2>&1; then
    echo "✓ VPN 密碼已存在"
    read -p "是否要更新密碼？(y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass edit vpn/fortigate
    fi
else
    echo "請輸入 Fortigate VPN 密碼（會安全地儲存在 YubiKey 中）："
    pass insert vpn/fortigate
fi
echo ""

# 測試
echo "=== 步驟 6: 測試設定 ==="
echo "嘗試讀取密碼（會要求 YubiKey PIN）..."
if pass show vpn/fortigate >/dev/null 2>&1; then
    echo "✓ 密碼讀取成功！"
else
    echo "✗ 密碼讀取失敗"
    echo "請檢查 YubiKey 是否已插入，以及 PIN 是否正確"
    exit 1
fi
echo ""

# 完成
echo "=========================================="
echo "✓ 設置完成！"
echo "=========================================="
echo ""
echo "現在可以使用 YubiKey 自動連接 VPN："
echo "  bash ./connect-vpn.sh"
echo ""
echo "密碼管理（重新執行此腳本即可）："
echo "  bash ./setup-yubikey-vpn.sh"
echo ""
echo "常用操作："
echo "  查看密碼: pass show vpn/fortigate"
echo "  更新密碼: pass edit vpn/fortigate"
echo "    或執行: bash ./setup-yubikey-vpn.sh（選擇選項 2）"
echo "  新增其他密碼: pass insert 名稱"
echo "  列出所有密碼: pass"
echo ""

