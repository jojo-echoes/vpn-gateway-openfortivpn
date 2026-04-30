# vpn-gateway-openfortivpn
Linux site-to-site VPN gateway using openfortivpn — connects a transit-network host (e.g. vpn-gateway.home.arpa, 192.168.91.2) to a FortiGate VPN, performs MASQUERADE on ppp0, and forwards selected LAN-side traffic into the corporate network without hijacking the host's default route.
