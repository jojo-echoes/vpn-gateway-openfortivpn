# reference/

這個目錄裡的檔案是從 [`netbox-automation`](../../) 專案的 `scripts/` 與 `docs/`
直接複製過來的**早期素材**，當時情境是「**單一使用者在自己 Ubuntu 電腦上以
YubiKey + pass + openfortivpn 連公司 VPN**」，與本專案
（**Site-to-Site VPN 閘道器**）的目標不同。

保留它們的原因：

* `connect-vpn.sh` / `disconnect-vpn.sh` / `show-vpn-status.sh` 對 ppp0 介面、
  openfortivpn 啟動參數的處理邏輯仍可借用
* `docs/03-vpn-automation.adoc` 對 `openfortivpn` 設定項的說明可直接參考
* `setup-yubikey-vpn.sh` 與 OpenPGP 文件，**未來若要把 gateway 上的 VPN
  password 改成存放在 HSM/SmartCard** 可作為起點

注意：**這些腳本不適合直接拿到 vpn-gateway.home.arpa 上跑**，因為它們：

* 假設使用者用 `screen` 互動輸入密碼
* 設定的是 `set-routes = 1`（會綁架 default route，與 gateway 用法相反）
* 預期跑在 desktop session 而非 systemd 服務

正式的 gateway 部署請看 repo 根目錄的 `scripts/`、`config/`、`systemd/`。
