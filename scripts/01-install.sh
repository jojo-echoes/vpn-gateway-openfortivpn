#!/bin/bash
# 01-install.sh — 安裝 openfortivpn gateway 需要的所有套件
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "請以 root / sudo 執行" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    openfortivpn \
    ppp \
    iptables \
    iptables-persistent \
    netfilter-persistent \
    iproute2 \
    ca-certificates \
    curl

systemctl enable netfilter-persistent.service

echo "✓ 套件安裝完成"
openfortivpn --version || true
