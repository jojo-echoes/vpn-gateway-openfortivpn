# Fortigate VPN 連接腳本

## 快速開始

### 方案 A: 使用 YubiKey 自動化（推薦）

**一個腳本搞定所有操作**：

```bash
bash ./setup-yubikey-vpn.sh
```

| 使用場景 | 操作 |
|---------|------|
| **初次設置** | 執行腳本 → 按照引導完成設置 |
| **更新密碼** | 執行腳本 → 選擇「2) 更新 VPN 密碼」 |
| **查看密碼** | 執行腳本 → 選擇「1) 查看當前密碼」 |
| **測試連線** | 執行腳本 → 選擇「3) 測試密碼讀取」 |
| **連接 VPN** | 執行腳本 → 選擇「4) 連接 VPN」<br>或直接執行 `bash ./connect-vpn.sh` |

### 方案 B: 手動輸入密碼（不使用 YubiKey）

如果不想設置 YubiKey，可以直接使用（每次需要手動輸入密碼）：
```bash
bash ./connect-vpn.sh
```

---

## 使用方式

### ⚠️ 重要：必須用 bash 執行

```bash
# ✅ 正確
bash ./connect-vpn.sh

# ❌ 錯誤（會出現 "Bad substitution" 錯誤）
sh ./connect-vpn.sh
```

### 連接 VPN

```bash
bash ./connect-vpn.sh
```

- 會提示輸入密碼（安全起見，不儲存密碼）
- VPN 在 `screen` 會話中運行，可用 `Ctrl+A` 然後 `D` 離開
- 使用 `screen -r vpn` 重新連接到 VPN 會話

### 檢查 VPN 狀態

```bash
bash ./show-vpn-status.sh
```

### 中斷 VPN

```bash
bash ./disconnect-vpn.sh
```

## 設定說明

### fortigate.conf 關鍵設定

```conf
# ✅ 接收 Server 推送的路由（重要！）
set-routes = 1
half-internet-routes = 0

# ✅ 不修改 DNS 設定
set-dns = 0
pppd-use-peerdns = 0
```

### 為什麼 `set-routes = 1` 很重要？

當 `set-routes = 1` 時，Fortigate Server 會自動推送所有需要的路由：
- `140.128.x.x` 網段
- `163.17.x.x` 網段  
- `210.69.115.x` 網段
- 其他機房網段

這樣當公司網段變更時，**不需要修改腳本**，Server 會自動更新。

### Windows FortiClient 的行為

Windows 上的 FortiClient 使用相同機制：
- VPN Server 推送路由表
- Client 自動套用路由
- 不修改預設閘道（Split Tunneling）

## 故障排除

### 執行時出現 "Bad substitution"

**原因**：使用了 `sh` 而不是 `bash`

**解決**：
```bash
bash ./connect-vpn.sh  # 而不是 sh ./connect-vpn.sh
```

### VPN 可以連接但無法訪問某些網段

**檢查**：`fortigate.conf` 中的 `set-routes` 必須是 `1`

**驗證**：
```bash
bash ./show-vpn-status.sh
```

查看「VPN 相關路由」是否包含所有需要的網段。

### 密碼輸入在哪裡？

密碼輸入在 `screen` 會話內部。如果您直接按 `Ctrl+A D` 離開，VPN 會連接失敗。

**正確流程**：
1. 執行 `bash ./connect-vpn.sh`
2. 等待出現密碼提示
3. **輸入密碼**（或使用 YubiKey 自動認證）
4. 看到「VPN 連接完成」後，按 `Ctrl+A` 然後 `D` 離開

---

## YubiKey 密碼管理

### 統一管理入口

所有 YubiKey 相關操作都可以通過一個腳本完成：

```bash
bash ./setup-yubikey-vpn.sh
```

執行後會顯示選單：
1. 查看當前密碼
2. **更新 VPN 密碼**（密碼更換時使用）← 最常用！
3. 測試密碼讀取
4. 連接 VPN
5. 重新初始化設定

### 為什麼要用 YubiKey？

✅ **安全**：密碼加密儲存，需要實體金鑰 + PIN  
✅ **方便**：自動連線，無需每次輸入密碼  
✅ **可維護**：密碼更換超簡單（選單選項 2）  
✅ **多用途**：可管理所有密碼（SSH、API、資料庫等）

### 密碼更換流程

**方法 1: 使用管理腳本（推薦）**

```bash
bash ./setup-yubikey-vpn.sh
# 選擇「2) 更新 VPN 密碼」
# 輸入新密碼 → 存檔 → 完成！
```

**方法 2: 直接使用 pass 指令**

```bash
pass edit vpn/fortigate
# 輸入新密碼 → 存檔 → 完成！
```

**不需要修改任何腳本或設定檔！** 下次連線自動使用新密碼。

### 其他常用 pass 指令

```bash
# 查看密碼
pass show vpn/fortigate

# 新增其他密碼
pass insert ssh/router1
pass insert database/mysql

# 列出所有儲存的密碼
pass

# 產生隨機密碼
pass generate vpn/fortigate 20
```

---
