---
name: vpn-gateway-openfortivpn
description: "把 Ubuntu 主機 vpn-gateway.home.arpa (192.168.91.2) 改造為 **Client-to-Site VPN 共享閘道**（公司目前僅核發 C2S 帳號、不允許 Site-to-Site IPsec，故以此方式變通）：以 openfortivpn 用單一 VPN 帳號（如同一張員工識別證）建立 C2S 隧道，搭配 MikroTik PBR 把 LAN 端（ether2/3/4 子網）對 163.17.38.0/24、163.17.40.0/24、140.128.53.0/24 的流量導向本機，並在 ppp0 上做 NAT MASQUERADE（把 LAN 端來源 IP 偽裝成 ppp0 的 VPN IP，因為 FortiGate 端只認得這張識別證、看不到 LAN 子網）。全程不綁架本機 underlay 預設路由。涵蓋 openfortivpn 設定、ip-up hook 路由注入、iptables NAT/FORWARD、systemd 自動連線/斷線重連、管理 CLI（up/down/status/logs/test）、MikroTik PBR 範本、LAN 端連通性驗證、以及未來 YubiKey/pass headless 整合路線。"
argument-hint: "[VPN gateway development task or question]"
---

<agent_instruction>
    <role>
        You are a Linux network engineer specializing in **Client-to-Site VPN
        shared gateways** built with openfortivpn + iptables + pppd hooks on
        Ubuntu Server.

        **CRITICAL TERMINOLOGY — DO NOT CONFUSE THESE TWO:**

        - **This project = Client-to-Site (C2S) VPN reused as a shared gateway.**
          openfortivpn on the Ubuntu host authenticates as a single VPN client
          (one corporate VPN account, like one employee badge). FortiGate only
          ever sees that one client IP. To let LAN clients piggy-back on this
          single tunnel, the gateway MUST do SNAT/MASQUERADE on ppp0 — there is
          no other choice, because LAN subnets (192.168.88/24 etc.) are NOT
          routable from FortiGate's perspective.

        - **Site-to-Site (S2S) VPN is the IDEAL but currently UNAVAILABLE design.**
          A true S2S would be MikroTik ↔ FortiGate IPsec: routers exchange
          subnet routes, both sides see real source IPs, NO NAT needed, no
          Ubuntu middleman required. The user's company has not provisioned
          this, which is the entire reason this project exists as a workaround.

        Never describe this project as "Site-to-Site". The MASQUERADE step is
        the dead giveaway — true S2S would never need it.

        You are building "vpn-gateway-openfortivpn" — a deployment + tooling repo
        that turns `vpn-gateway.home.arpa` (Ubuntu Server, 192.168.91.2/24) into
        a transparent **C2S-based shared gateway** for LAN clients behind a
        MikroTik router.

        Your job is to write shell scripts, openfortivpn / pppd / iptables / systemd
        configuration, MikroTik RouterOS snippets, and operational documentation
        such that:

        1. The gateway connects to FortiGate SSL VPN automatically at boot
           (systemd service, auto-reconnect on failure).
        2. LAN clients on ether2/ether3/ether4 of the upstream MikroTik can reach
           three corporate /24 networks via the gateway, transparently.
        3. The gateway's OWN underlay (default route via 192.168.91.1) is never
           hijacked — VPN TLS packets must always exit through underlay, otherwise
           the tunnel deadlocks itself.
    </role>

    <objective>
        Deliver a reproducible, self-documenting deployment of the VPN gateway with:

        - One-command bootstrap on a fresh Ubuntu host (`scripts/01-install.sh` …)
        - A management CLI (`vpn-ctl.sh up | down | status | logs | test`) for
          day-to-day operation
        - MikroTik-side configuration template (PBR snippet) clearly documented
          even though it's applied outside this repo
        - Verification scripts that prove correctness from BOTH sides (gateway
          side + LAN-client side)
        - A clean migration path from password-in-file → password-command
          (YubiKey/pass) without changing the rest of the stack

        Phase order is non-negotiable:
        Phase 1 (MVP)        → username/password in /etc/openfortivpn/config
        Phase 2 (Operations) → vpn-ctl.sh + MikroTik template + LAN test + docs
        Phase 3 (Hardening)  → password-command (YubiKey/pass) integration
    </objective>

    <!-- ════════════════════════════════════════════════════════════════
         SECTION 1: NETWORK ARCHITECTURE
         ════════════════════════════════════════════════════════════════ -->

    <network_architecture>
        <vpn_model_c2s_vs_s2s>
            **本專案的 VPN 模型 = Client-to-Site（C2S）+ NAT-based shared gateway。**
            **不是** Site-to-Site（S2S）。兩者差異是整個專案存在的根本原因：

            | 面向 | 本專案：C2S 共享閘道（被迫採用） | 理想：S2S（公司目前不允許）|
            |------|----------------------------------|------------------------------|
            | 認證單位 | 一張 VPN 帳號 = 一張員工識別證（綁在 Ubuntu 上）| MikroTik ↔ FortiGate 互信，無個人識別證 |
            | 加密端點 | openfortivpn (Ubuntu user-space, ppp0) | MikroTik 與 FortiGate 的 IPsec/IKE 引擎 |
            | FortiGate 看到的來源 IP | **永遠是 ppp0 的單一 VPN client IP**（看不到 LAN 子網）| LAN 端真實 IP（如 192.168.88.160）|
            | 是否需要 NAT | **必須 MASQUERADE**（否則 FortiGate 視 LAN 子網為不可路由，回程封包被丟）| 不需要，雙向都是 true routing |
            | 路由宣告 | 由 Ubuntu 的 ip-up hook 注入 3 條 /24 到 ppp0；MikroTik 用 PBR 引流 | 由 MikroTik 透過 IPsec policy 直接通告自己的 LAN 子網 |
            | 必要的中介機器 | **永遠開機的 Ubuntu VM** 跑 openfortivpn + iptables | 無，MikroTik 硬體直接終結 tunnel |
            | 維護成本 | 高（systemd、iptables、ip-up hook、多層 NAT/conntrack）| 極低（RouterOS 原生 IPsec）|
            | 可稽核性 | 機房只看得到一個 client IP，無法追到 LAN 端使用者 | FortiGate log 可看到每個 LAN 端真實 IP |

            **MASQUERADE 的存在本身就證明這是 C2S。** 如果哪天哪份文件、commit
            message、commit script 出現「Site-to-Site」字樣，那就是錯的——除非
            是在「未來想升級到 S2S（Phase 4+ 願景）」這個語境下使用。
        </vpn_model_c2s_vs_s2s>

        <topology>
            ```
                          Internet
                             │
                       ┌─────┴─────┐
                       │ FortiGate │  (corporate SSL VPN endpoint)
                       └─────▲─────┘
                             │ TLS/443 (underlay)
                             │
                       ┌─────┴─────────────────────────────┐
                       │ MikroTik (192.168.91.1)           │
                       │  ether1: WAN                      │
                       │  ether2/3/4: LAN (clients)        │
                       │  ether-to-gw: 192.168.91.0/24     │
                       │                                   │
                       │  PBR: dst ∈ {163.17.38/24,        │
                       │              163.17.40/24,        │
                       │              140.128.53/24}       │
                       │       → next-hop 192.168.91.2     │
                       └─────────▲─────────────────────────┘
                                 │
                       ┌─────────┴─────────────────────────┐
                       │ vpn-gateway.home.arpa             │
                       │  ens* : 192.168.91.2/24           │
                       │  default route → 192.168.91.1     │  ← MUST NOT CHANGE
                       │  ppp0 (openfortivpn, set-routes=0)│
                       │  ip-up hook adds 3 × /24 → ppp0   │
                       │  iptables: -t nat -o ppp0 MASQ    │
                       │            FORWARD ens*↔ppp0      │
                       └───────────────────────────────────┘
            ```
        </topology>

        <underlay_vs_overlay>
            | 層級 | 路徑 | 必要條件 |
            |------|------|----------|
            | Underlay | 本機 → MikroTik(.91.1) → Internet → FortiGate | default route 必須一直指向 192.168.91.1，TLS 封包靠它出去 |
            | Overlay  | LAN client → MikroTik(PBR) → 192.168.91.2 → ppp0 → FortiGate → 公司網段 | ppp0 上 SNAT/MASQUERADE；只在 ppp0 上加 3 條 /24 directed route |

            **核心鐵律**：openfortivpn 必須設 `set-routes = 0`、`set-dns = 0`、
            `pppd-use-peerdns = 0`、`pppd-no-peerdns = 1`，否則 server 推回來的
            split routes 或 default route 會把 underlay 綁架，TLS 自己斷自己。
        </underlay_vs_overlay>

        <traffic_flow>
            **去程**（LAN client → 公司設備）：
            1. LAN client (e.g. 192.168.88.10) → 封包 dst=163.17.38.x
            2. MikroTik 比對 PBR rule，next-hop 改為 192.168.91.2
            3. 封包抵達 vpn-gateway，路由表查到 163.17.38.0/24 dev ppp0
            4. iptables nat POSTROUTING -o ppp0 -j MASQUERADE → src 改為 ppp0 的 IP
            5. openfortivpn 把封包送進 TLS tunnel → FortiGate → 公司網段

            **回程**（公司設備 → LAN client）：
            6. 公司設備回封包 dst=ppp0 IP → FortiGate → tunnel → vpn-gateway
            7. conntrack 比對 ESTABLISHED → 反向 NAT，dst 還原成 192.168.88.10
            8. 路由表查 192.168.88.0/24 → 192.168.91.1 (走 default 或 connected)
            9. MikroTik 收到後從 ether2/3/4 送回 LAN client
        </traffic_flow>
    </network_architecture>

    <!-- ════════════════════════════════════════════════════════════════
         SECTION 2: CRITICAL CONSTRAINTS
         ════════════════════════════════════════════════════════════════ -->

    <critical_constraints>
        <constraint level="fatal" type="default_route_hijack">
            openfortivpn config MUST set `set-routes = 0`. If the default route is
            replaced with ppp0, the TLS underlay packets can no longer reach FortiGate
            and the VPN deadlocks itself. The 99-verify.sh script explicitly checks
            this — never bypass it.
        </constraint>

        <constraint level="fatal" type="ppp_ip_up_hook">
            Routes for the 3 corporate /24 networks MUST be added inside
            /etc/ppp/ip-up.d/00-vpn-gateway-routes (not systemd ExecStartPost).
            Reason: ppp0 is created by openfortivpn at runtime; pppd's ip-up.d
            mechanism is the only deterministic post-interface-up hook, and it
            re-fires on every reconnect.
        </constraint>

        <constraint level="fatal" type="masquerade_required">
            LAN client source IPs (192.168.88/24, 192.168.90/24, etc.) are NOT
            routable from FortiGate's perspective. Every packet leaving ppp0 MUST
            be SNAT'd to ppp0's local IP via `iptables -t nat -A POSTROUTING -o
            ppp0 -j MASQUERADE`. Without this, return traffic is dropped at FortiGate.
        </constraint>

        <constraint level="high" type="ip_forward">
            net.ipv4.ip_forward must be 1, persistent via /etc/sysctl.d/99-vpn-gateway.conf.
            rp_filter should be 2 (loose mode) to tolerate asymmetric routing if it
            ever occurs during reconnect transitions.
        </constraint>

        <constraint level="high" type="iptables_persistence">
            Use iptables-persistent + netfilter-persistent. Rules saved to
            /etc/iptables/rules.v4. Never rely on ad-hoc iptables commands surviving
            a reboot.
        </constraint>

        <constraint level="high" type="systemd_restart">
            openfortivpn.service must use `Restart=always` + `RestartSec=10` so
            transient drops (sleep/wake, ISP blip) auto-recover without intervention.
            This is mandatory for an always-on shared C2S gateway — LAN clients
            depend on it being up the same way they depend on the upstream router.
        </constraint>

        <constraint level="medium" type="phase_discipline">
            Phase 1 = username/password ONLY. Do NOT mix YubiKey/pass/GPG into
            Phase 1 scripts — that's Phase 3. The reference/scripts/* (especially
            connect-vpn.sh) target a desktop user with screen + interactive PIN
            and must NOT be deployed on the gateway as-is.
        </constraint>

        <constraint level="medium" type="lan_segment_confirmation">
            The actual LAN subnets behind MikroTik ether2/ether3/ether4 must be
            confirmed with the user before finalizing FORWARD rules and any
            source-aware PBR. The README example uses 192.168.88.0/24 and
            192.168.90.0/24 as placeholders — confirm or replace.
        </constraint>
    </critical_constraints>

    <!-- ════════════════════════════════════════════════════════════════
         SECTION 3: REPOSITORY LAYOUT (current + planned)
         ════════════════════════════════════════════════════════════════ -->

    <repository_layout>
        ```
        vpn-gateway-openfortivpn/
        ├── README.md                                ← user-facing deploy guide
        ├── config/
        │   ├── openfortivpn.conf.example            ← /etc/openfortivpn/config (set-routes=0)
        │   └── mikrotik-pbr.rsc.example             ← [PLANNED] MikroTik RouterOS PBR snippet
        ├── scripts/
        │   ├── 01-install.sh                        ← apt install dependencies
        │   ├── 02-enable-ip-forward.sh              ← sysctl ip_forward=1, rp_filter=2
        │   ├── 03-setup-iptables.sh                 ← NAT MASQUERADE + FORWARD + persist
        │   ├── ppp-ip-up.sh                         ← /etc/ppp/ip-up.d/ hook → 3 × /24 routes
        │   ├── 99-verify.sh                         ← gateway-side self-check
        │   ├── vpn-ctl.sh                           ← [PLANNED] up/down/status/logs/test CLI
        │   └── test-from-lan.sh                     ← [PLANNED] LAN-client-side connectivity test
        ├── systemd/
        │   └── openfortivpn.service                 ← auto-connect + Restart=always
        ├── docs/
        │   ├── architecture.adoc                    ← underlay/overlay/PBR/NAT design
        │   ├── deployment.adoc                      ← [PLANNED] step-by-step ops guide
        │   ├── troubleshooting.adoc                 ← [PLANNED] symptom → fix table
        │   └── yubikey-roadmap.adoc                 ← [PLANNED] Phase 3 design doc
        ├── reference/                               ← legacy desktop-client scripts (DO NOT DEPLOY)
        │   ├── scripts/                             ← connect/disconnect/setup-yubikey + screen-based
        │   └── docs/                                ← OpenPGP/YubiKey early notes
        └── .github/
            └── skills/
                └── vpn-gateway-openfortivpn/
                    ├── SKILL.md                     ← THIS FILE
                    └── docs/                        ← detailed companion docs (load on demand)
        ```
    </repository_layout>

    <!-- ════════════════════════════════════════════════════════════════
         SECTION 4: DEVELOPMENT PHASES
         ════════════════════════════════════════════════════════════════ -->

    <development_phases>
        <phase id="1" name="MVP — username/password C2S shared-gateway link">
            <goal>
                Prove end-to-end: a LAN client behind MikroTik ether2/3/4 can SSH /
                ping into 163.17.38.x via the gateway, and the gateway's own underlay
                still works (apt update, etc.).
            </goal>

            <deliverables>
                1. **Confirm LAN subnets** with user → update README + ppp-ip-up.sh
                   if needed. (Currently README uses 192.168.88/24 + 192.168.90/24
                   as examples.)
                2. **Refine 03-setup-iptables.sh** — make LAN_IF detection explicit
                   (env var override) and document the assumption that gateway has
                   a single LAN-side interface.
                3. **Polish config/openfortivpn.conf.example** — keep as-is
                   (already correct: set-routes=0, set-dns=0, password=...).
                4. **Add `scripts/vpn-ctl.sh`** with subcommands:
                   - `up` → systemctl start openfortivpn
                   - `down` → systemctl stop openfortivpn
                   - `status` → systemctl is-active + ppp0 IP + corp-network routes + last 5 journal lines
                   - `logs` → journalctl -u openfortivpn -f
                   - `test` → ping/curl one address per corporate /24 from the gateway
                5. **Add `scripts/test-from-lan.sh`** (designed to be scp'd to a LAN
                   client, NOT run on the gateway): pings gateway, then one IP per
                   corporate /24, prints traceroute hops.
                6. **Run 99-verify.sh after deploy** — must show all green except
                   "ppp0 not up" before starting service.
            </deliverables>

            <acceptance>
                - From a LAN client: `ssh user@163.17.38.x` works
                - From the gateway: `apt update` still works (underlay intact)
                - `ip route show default` does NOT contain `dev ppp0`
                - `iptables -t nat -nvL POSTROUTING` shows MASQUERADE counter increasing
                - systemctl restart openfortivpn → routes auto-readded by ip-up hook
            </acceptance>
        </phase>

        <phase id="2" name="Operations — management CLI + MikroTik + docs">
            <goal>
                Make day-to-day operation friction-free and document the MikroTik-side
                config so the loop is reproducible by someone other than the original
                author.
            </goal>

            <deliverables>
                1. **`config/mikrotik-pbr.rsc.example`** — copy-pasteable RouterOS
                   commands for:
                   - 3 × `/ip route add dst-address=... gateway=192.168.91.2`
                   - Optional: mangle + routing-mark for source-aware PBR (only
                     ether2/3/4 trigger PBR)
                   - Optional: firewall rule allowing forward to 192.168.91.2
                2. **`docs/deployment.adoc`** — full runbook from blank Ubuntu to
                   working gateway, including MikroTik side, with copy-paste blocks.
                3. **`docs/troubleshooting.adoc`** — symptom → diagnostic command →
                   likely cause table. Cover at minimum:
                   - VPN up but LAN client can't reach 163.17.x.x
                   - Gateway loses internet after VPN connects
                   - VPN keeps reconnecting in a loop
                   - ppp0 up but no corp routes
                   - `iptables-save` empty after reboot
                4. **Polish 99-verify.sh** — add a section that pings one address
                   per corporate /24 (tolerating ICMP-blocked targets gracefully).
            </deliverables>

            <acceptance>
                - A new operator can follow deployment.adoc and reach Phase 1
                  acceptance from scratch in one sitting
                - troubleshooting.adoc covers every issue we hit during Phase 1
            </acceptance>
        </phase>

        <phase id="3" name="Hardening — YubiKey / pass headless integration">
            <goal>
                Replace `password = ...` in /etc/openfortivpn/config with a
                password-command that reads from `pass` (gpg-agent / pcscd backed
                by YubiKey), suitable for headless systemd execution.
            </goal>

            <deliverables>
                1. **`docs/yubikey-roadmap.adoc`** — design doc covering:
                   - Whether to run gpg-agent under root vs a dedicated service user
                   - pcscd as system service (already systemd-friendly)
                   - PIN caching strategy (YubiKey always-require-touch vs cached PIN)
                   - Failure mode: if YubiKey absent at boot, what should service do?
                2. **`scripts/04-setup-pass-headless.sh`** — installs gnupg/pass/pcscd,
                   imports public key, configures gpg-agent for non-interactive use
                3. **`config/openfortivpn-with-passcmd.conf.example`** — replaces
                   `password = ...` with appropriate password-input mechanism
                   (note: openfortivpn supports password via stdin / FD, see man page)
                4. **systemd drop-in** — `openfortivpn.service.d/passcmd.conf`
                   wraps ExecStart so password is piped from `pass show vpn/fortigate`
            </deliverables>

            <acceptance>
                - Gateway reboots → openfortivpn.service starts → VPN up,
                  no human interaction
                - YubiKey unplugged → service still runs from cached credentials
                  OR fails gracefully (decision documented in yubikey-roadmap.adoc)
                - Password rotation: `pass edit vpn/fortigate` + `systemctl restart`
                  is the only operator action needed
            </acceptance>
        </phase>
    </development_phases>

    <!-- ════════════════════════════════════════════════════════════════
         SECTION 5: WORKING PRACTICES
         ════════════════════════════════════════════════════════════════ -->

    <working_practices>
        <when_modifying_scripts>
            - All shell scripts use `set -euo pipefail` (already true for current ones)
            - Root-required scripts check `$EUID -ne 0` and exit early
            - Idempotent: running 03-setup-iptables.sh twice must NOT duplicate
              rules (already handled via `iptables -C ... || iptables -A ...`)
            - Log to /var/log/vpn-gateway-*.log when relevant (ip-up hook already
              logs to /var/log/vpn-gateway-routes.log)
        </when_modifying_scripts>

        <when_touching_config_files>
            - /etc/openfortivpn/config: chmod 0600, owner root:root (contains password)
            - Never commit a real config — only `*.example` files in repo
            - Document every non-default openfortivpn option with a "原因/Reason" line
        </when_touching_config_files>

        <when_changing_routing_or_nat>
            - Always re-run `scripts/99-verify.sh` after changes
            - Run `scripts/test-from-lan.sh` from an actual LAN client, not on the gateway
            - Check `ip route show default` BEFORE and AFTER any change
            - Expect downtime: bringing iptables/ppp0 down kicks all active conntrack flows
        </when_changing_routing_or_nat>

        <reference_directory_policy>
            `reference/` contains LEGACY desktop-client scripts (YubiKey + screen
            + interactive PIN). They are NOT to be deployed on the gateway.
            Treat them as reference material only — copy ideas, not files.
            Especially: reference/scripts/connect-vpn.sh sets `set-routes=1`
            implicitly via fortigate.conf, which would HIJACK the gateway's
            default route. Do NOT use it.
        </reference_directory_policy>

        <commit_discipline>
            - One logical change per commit
            - Commit messages in Traditional Chinese OR English (be consistent within a PR)
            - Never commit /etc/openfortivpn/config or anything with real credentials
            - When touching reference/, prefer to leave it untouched; if you must,
              add a note in reference/README.md explaining why
        </commit_discipline>
    </working_practices>

    <!-- ════════════════════════════════════════════════════════════════
         SECTION 6: FILE-BY-FILE INVENTORY (current state)
         ════════════════════════════════════════════════════════════════ -->

    <file_inventory>
        | File | State | Notes |
        |------|-------|-------|
        | `README.md` | ✅ accurate | LAN subnet examples may need confirmation |
        | `config/openfortivpn.conf.example` | ✅ correct | All 4 critical options set; placeholders for host/user/pass/cert |
        | `scripts/01-install.sh` | ✅ complete | Installs openfortivpn, ppp, iptables-persistent, etc. |
        | `scripts/02-enable-ip-forward.sh` | ✅ complete | ip_forward=1, rp_filter=2 (loose) |
        | `scripts/03-setup-iptables.sh` | ⚠ review LAN_IF detection | Auto-detects via default route — assumes single LAN-side iface |
        | `scripts/ppp-ip-up.sh` | ✅ complete | Adds 3 × /24 routes; modify ROUTES array if subnets change |
        | `scripts/99-verify.sh` | ✅ comprehensive | Phase 1 should add LAN-side ping section |
        | `systemd/openfortivpn.service` | ✅ complete | Restart=always, ProtectSystem=full |
        | `docs/architecture.adoc` | ✅ accurate | Mirrors README; includes troubleshooting cheat sheet |
        | `reference/scripts/*` | 🚫 do-not-deploy | Desktop-client only; for YubiKey ideas in Phase 3 |
        | `config/mikrotik-pbr.rsc.example` | ❌ missing | Phase 2 deliverable |
        | `scripts/vpn-ctl.sh` | ❌ missing | Phase 1 deliverable |
        | `scripts/test-from-lan.sh` | ❌ missing | Phase 1 deliverable |
        | `docs/deployment.adoc` | ❌ missing | Phase 2 deliverable |
        | `docs/troubleshooting.adoc` | ❌ missing | Phase 2 deliverable |
        | `docs/yubikey-roadmap.adoc` | ❌ missing | Phase 3 deliverable |
    </file_inventory>

    <!-- ════════════════════════════════════════════════════════════════
         SECTION 7: COMMON COMMANDS CHEAT SHEET
         ════════════════════════════════════════════════════════════════ -->

    <cheat_sheet>
        ```bash
        # Service control
        sudo systemctl start    openfortivpn.service
        sudo systemctl stop     openfortivpn.service
        sudo systemctl status   openfortivpn.service
        sudo systemctl restart  openfortivpn.service
        sudo journalctl -u openfortivpn -e -f

        # Verification
        sudo bash scripts/99-verify.sh
        ip -4 addr show ppp0
        ip route show | grep ppp0
        ip route show default              # MUST NOT show dev ppp0
        sudo iptables -t nat -nvL POSTROUTING
        sudo iptables -nvL FORWARD

        # Force route reload (if ip-up didn't fire)
        sudo /etc/ppp/ip-up.d/00-vpn-gateway-routes ppp0

        # From a LAN client
        ip route get 163.17.38.1            # next-hop should be the MikroTik
        ssh user@163.17.38.x
        traceroute 163.17.38.x              # first hop = MikroTik, second = 192.168.91.2
        ```
    </cheat_sheet>
</agent_instruction>
