# vpn-gateway-openfortivpn

將一台 Linux 主機（例：`vpn-gateway.home.arpa`，IP `192.168.91.2/24`）改造成
**Client-to-Site VPN 共享閘道**：以 [`openfortivpn`](https://github.com/adrienverge/openfortivpn)
用**單一 C2S 帳號**連線至公司 FortiGate SSL VPN，對 LAN 端來自其他子網
（如 `192.168.88.0/24`、`192.168.90.0/24`）且目的地為公司網段
（`163.17.38.0/24`、`163.17.40.0/24`、`140.128.53.0/24`）的流量執行
**NAT (MASQUERADE)** 並由 `ppp0` 隧道轉送，**且不綁架本機原本的預設閘道**。

> **為什麼是 C2S 而不是 Site-to-Site？** S2S（MikroTik ↔ FortiGate IPsec）才是
> 理想設計——雙向 true routing、不需 NAT、可稽核 LAN 端真實 IP——但公司目前
> **僅核發 C2S 帳號**，所以只能以這台 Ubuntu 跑 openfortivpn 當「人肉 IPsec 閘道」
> 的方式變通。`ppp0` 上的 `MASQUERADE` 就是 C2S 的鐵證：S2S 永遠不需要它。
> 詳見 `docs/architecture.adoc` 與 `.github/skills/vpn-gateway-openfortivpn/SKILL.md`。

---

## 1. 網路架構（Underlay / Overlay 分離）

```
                 ┌─────────────────────────────┐
                 │    Internet (FortiGate)     │
                 └──────────────▲──────────────┘
                                │ underlay (TCP/443 SSL VPN)
                                │ via 192.168.91.1 (default route)
                                │
LAN clients                 ┌───┴───────────────┐
192.168.88.0/24 ─┐          │  vpn-gateway      │
192.168.90.0/24 ─┼──► MikroTik ──► 192.168.91.2 │ ppp0 (overlay)
                 │   (PBR: 只把 163.17.38.0/24, │ ──► 公司網段
                 │    163.17.40.0/24,           │     (SNAT MASQUERADE)
                 │    140.128.53.0/24 → .91.2)  │
                 └───────────────────┘
```

* **Underlay**：本機 default route 必須保持指向 `192.168.91.1`（MikroTik），
  讓 openfortivpn 的 TLS 封包能出網際網路。
* **Overlay**：MikroTik 上做 policy-based routing，只把目的地為公司 3 個網段的流量
  導向本機；本機收到後在 `ppp0` 上 MASQUERADE 出去。

---

## 2. 部署步驟（在 vpn-gateway.home.arpa 上執行）

```bash
# 0. clone
git clone https://github.com/jojo-echoes/vpn-gateway-openfortivpn.git
cd vpn-gateway-openfortivpn

# 1. 安裝依賴（openfortivpn, iptables-persistent, ...）
sudo bash scripts/01-install.sh

# 2. 建立 openfortivpn 設定
sudo install -d -m 0750 /etc/openfortivpn
sudo cp config/openfortivpn.conf.example /etc/openfortivpn/config
sudo chmod 0600 /etc/openfortivpn/config
sudo $EDITOR /etc/openfortivpn/config   # 填入 host/port/username/password/trusted-cert

# 3. 啟用 IPv4 forwarding
sudo bash scripts/02-enable-ip-forward.sh

# 4. 安裝 ppp ip-up hook（VPN 上線時自動加 3 條 /24 路由到 ppp0）
sudo install -m 0755 scripts/ppp-ip-up.sh /etc/ppp/ip-up.d/00-vpn-gateway-routes

# 5. 套用並持久化 iptables (NAT MASQUERADE on ppp0 + FORWARD)
sudo bash scripts/03-setup-iptables.sh

# 6. 安裝 systemd 服務（自動連線、斷線重連）
sudo cp systemd/openfortivpn.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now openfortivpn.service

# 7. 驗證
sudo bash scripts/99-verify.sh
```

---

## 3. 關鍵設定要點

### `/etc/openfortivpn/config`

| 設定 | 值 | 原因 |
|------|----|------|
| `set-routes` | **`0`** | 不讓 openfortivpn 推 default route 進系統，避免綁架 underlay |
| `set-dns` | **`0`** | 不要動 `/etc/resolv.conf` |
| `pppd-use-peerdns` | **`0`** | 同上，不接受 server 推的 DNS |
| `host` / `port` / `username` / `password` / `trusted-cert` | — | 依公司 FortiGate 填入 |

### 公司網段路由（由 `ppp-ip-up.sh` 自動加）

```
ip route add 163.17.38.0/24  dev ppp0
ip route add 163.17.40.0/24  dev ppp0
ip route add 140.128.53.0/24 dev ppp0
```

### NAT / Forwarding

```
# /etc/sysctl.d/99-vpn-gateway.conf
net.ipv4.ip_forward = 1

# iptables (持久化於 /etc/iptables/rules.v4)
-t nat -A POSTROUTING -o ppp0 -j MASQUERADE
-A FORWARD -i ens* -o ppp0 -j ACCEPT
-A FORWARD -i ppp0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

---

## 4. 目錄結構

```
.
├── README.md                       ← 你正在讀
├── config/
│   └── openfortivpn.conf.example   ← /etc/openfortivpn/config 範本（set-routes=0）
├── scripts/
│   ├── 01-install.sh               ← apt install 依賴
│   ├── 02-enable-ip-forward.sh     ← sysctl ip_forward=1
│   ├── 03-setup-iptables.sh        ← NAT + FORWARD + iptables-persistent
│   ├── ppp-ip-up.sh                ← /etc/ppp/ip-up.d/ 鉤子，新增 3 條 /24 路由
│   └── 99-verify.sh                ← 一鍵自我檢測
├── systemd/
│   └── openfortivpn.service        ← 自動連線 / 失敗重連
├── docs/
│   └── architecture.adoc           ← 設計說明（underlay/overlay、PBR、NAT）
└── reference/                      ← 從 netbox-automation 複製過來的參考素材
    ├── scripts/                    ← 早期單機 client 用的腳本（YubiKey/pass 整合等）
    └── docs/                       ← 早期 OpenPGP/YubiKey/openfortivpn 開發文件
```

---

## 5. 後續開發

之後將以 VS Code Remote-SSH 連到 `vpn-gateway.home.arpa`，
搭配 `@journal` chat participant 在該主機上繼續開發、調整與驗證。

## 6. 授權

MIT（除 `reference/` 內保留原 netbox-automation 專案的素材作為參考）
