# reference/

這個目錄裡的檔案是從 [`netbox-automation`](../../) 專案的 `scripts/` 與 `docs/`
直接複製過來的**早期素材**，當時情境是「**單一使用者在自己 Ubuntu 電腦上以
YubiKey + pass + openfortivpn 連公司 VPN**」。

雖然 netbox-automation 的原始用途與本專案
（**Client-to-Site VPN 共享閘道**——以單一 VPN 帳號讓 LAN 端多台主機共用
同一條 openfortivpn 隧道，並在 ppp0 上做 MASQUERADE）的部署目標不同，
兩者底層仍同樣是「在 Ubuntu 上用 openfortivpn 撥 FortiGate SSL VPN」，
所以許多細節仍可借鏡。

> 註：本專案**不是** Site-to-Site VPN（理想狀態應為 MikroTik ↔ FortiGate
> IPsec、雙方互通子網路由、不需 NAT），而是因為公司目前僅核發 C2S 帳號
> 才不得不採用的變通方案。MASQUERADE 的存在本身就是 C2S 的鐵證。
> 詳見根目錄 `docs/architecture.adoc` 與 `.github/skills/vpn-gateway-openfortivpn/SKILL.md`。

保留它們的原因：

* `connect-vpn.sh` / `disconnect-vpn.sh` / `show-vpn-status.sh` 對 ppp0 介面、
  openfortivpn 啟動參數的處理邏輯仍可借用
* `docs/03-vpn-automation.adoc` 對 `openfortivpn` 設定項的說明可直接參考
* `setup-yubikey-vpn.sh` 與 OpenPGP 文件，**未來若要把 gateway 上的 VPN
  password 改成存放在 HSM/SmartCard** 可作為起點

注意：**這些腳本不適合直接拿到 vpn-gateway.home.arpa 上跑**，因為它們：

* 假設使用者用 `screen` 互動輸入密碼（gateway 必須是 headless、systemd 啟動）
* 設定的是 `set-routes = 1`（會綁架 default route——對 desktop 使用者沒差，
  但對 C2S 共享閘道是災難：default route 一旦改走 ppp0，openfortivpn 自己
  的 TLS 封包就送不到 FortiGate，整條隧道立刻崩）
* 預期跑在 desktop session 而非 systemd 服務

正式的 gateway 部署請看 repo 根目錄的 `scripts/`、`config/`、`systemd/`。
