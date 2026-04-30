# YubiKey + OpenPGP + FortiGate VPN 自動化系統 - 技術文件

本目錄包含完整的技術文件，記錄從 OpenPGP 加密機制到 YubiKey 整合，再到 VPN 自動化的完整開發過程。

## 文件列表

### [00-overview.adoc](00-overview.adoc) - 總覽
- 專案概述與系統架構
- 開發環境與工具介紹
- 文件結構導覽
- 開發歷程重點

**建議先閱讀此文件以了解整體架構**

### [01-openpgp-encryption.adoc](01-openpgp-encryption.adoc) - OpenPGP 加密機制
- GPG 金鑰對的產生與管理
- 密碼加密的完整流程（混合加密機制）
- 加密檔案的驗證方法
- 實際執行的程式與步驟
- 與 GPG Agent 的互動

**回答問題 (1)：OpenPGP 的運作，對於密碼的加密，實際在執行程式，是要執行哪些程式，步驟為何？**

### [02-yubikey-integration.adoc](02-yubikey-integration.adoc) - YubiKey 整合
- YubiKey OpenPGP 應用程式的架構
- 私鑰轉移的完整步驟
- 為何需要輸入 `key 1` 進入子金鑰編輯
- Admin PIN 的作用與必要性
- 雙 YubiKey 備份策略

**回答問題 (2)：OpenPGP 的機制，是如何和 YubiKey 5C NFC 產生關係，把 key 儲存到 YubiKey 5C NFC 是怎麼做的？為什麼還要輸入 key 1 進到更深的一層？**

### [03-vpn-automation.adoc](03-vpn-automation.adoc) - VPN 自動化
- openfortivpn 的運作原理與設定
- pass 與 openfortivpn 的整合
- YubiKey 自動偵測機制
- 背景程序的 sudo 權限處理
- PID 追蹤與連接管理
- Trap 清理機制

**回答問題 (3)：OpenPGP 的機制建置起來後，是如何讓 openfortivpn 叫用（在 YubiKey 5C NFC 有插入到 Ubuntu Linux 的情況下）？**

### [04-manual-mode.adoc](04-manual-mode.adoc) - 手動輸入模式
- 背景程序的標準輸入問題
- screen 的虛擬終端機制
- 互動式密碼輸入的實作
- screen 會話管理與重新連接
- 包裝腳本的設計理念

**回答問題 (4)：在 Ubuntu Linux 身上沒有接任何 YubiKey 5C NFC 的情況下，為什麼要透過 screen 才有辦法讓 user 輸入密碼？實際上又是如何一步一步的達到這個目標？**

### [05-complete-workflow.adoc](05-complete-workflow.adoc) - 完整工作流程
- 首次設置清單
- 日常使用的標準操作程序
- 完整的故障排除指南
- 安全最佳實踐
- 系統維護建議
- 常用命令速查表

**適合作為日常操作的參考手冊**

## 閱讀建議

### 對於初學者
按順序閱讀所有文件：
1. 總覽 → 理解整體架構
2. OpenPGP 加密 → 理解加密原理
3. YubiKey 整合 → 理解硬體安全
4. VPN 自動化 → 理解系統整合
5. 手動輸入模式 → 理解容錯設計
6. 完整工作流程 → 實際操作

### 對於有經驗的讀者
可根據需求跳讀：
- 只關注 YubiKey：閱讀文件 2
- 只關注 VPN 自動化：閱讀文件 3 和 5
- 只關注 screen 設計：閱讀文件 4

### 對於故障排除
直接查閱文件 5（完整工作流程）的故障排除章節

## 文件格式

所有文件使用 **AsciiDoc** 格式撰寫，具有以下特性：

- 結構化標記，易於閱讀
- 支援語法高亮的程式碼區塊
- 完整的交叉參照連結
- 可轉換為 HTML、PDF 等格式

### 如何閱讀 AsciiDoc

#### 方法 1：直接在文字編輯器中閱讀
AsciiDoc 語法簡潔，即使直接閱讀原始碼也很清楚。

#### 方法 2：使用 VS Code 預覽
安裝 AsciiDoc 擴充套件：
```bash
code --install-extension asciidoctor.asciidoctor-vscode
```

然後按 `Ctrl+Shift+V` 預覽。

#### 方法 3：轉換為 HTML
```bash
# 安裝 asciidoctor
sudo apt install asciidoctor

# 轉換單一檔案
asciidoctor 00-overview.adoc

# 轉換所有檔案
asciidoctor *.adoc

# 開啟 HTML
firefox 00-overview.html
```

#### 方法 4：轉換為 PDF
```bash
# 安裝依賴
sudo apt install asciidoctor ruby-asciidoctor-pdf

# 轉換為 PDF
asciidoctor-pdf 00-overview.adoc
```

## 文件特色

### 鉅細靡遺
- 每個步驟都有詳細說明
- 包含實際執行的命令和輸出
- 解釋背後的原理和設計決策

### 圖文並茂
- ASCII 藝術圖表說明架構
- 程式碼區塊語法高亮
- 清楚的表格對比

### 完整可追溯
- 交叉參照連結
- 從概念到實作的完整流程
- 故障排除與解決方案

### 實用導向
- 提供複製貼上可用的命令
- 真實的輸出範例
- 常見問題的解決方案

## 版本資訊

- **版本**: 1.0
- **日期**: 2026-02-01
- **涵蓋內容**: 完整的開發過程，從 GPG 金鑰產生到雙模式 VPN 自動化

## 相關檔案

文件中提到的實際腳本位於：
```
../scripts/
├── connect-vpn.sh       - VPN 連接腳本（自動偵測 YubiKey）
├── disconnect-vpn.sh    - VPN 中斷腳本
├── show-vpn-status.sh   - VPN 狀態顯示
└── fortigate.conf       - VPN 設定檔
```

## 授權

本文件基於實際專案開發過程撰寫，適用於教育與技術研究用途。

## 致謝

感謝整個開發過程中的指導與協助，特別是：
- OpenPGP/GnuPG 社群的詳細文件
- YubiKey 官方技術文件與工具
- openfortivpn 專案的開源貢獻
- pass 專案對 GPG 整合的優雅實現

---

**開始閱讀**: [00-overview.adoc](00-overview.adoc)
