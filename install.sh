#!/bin/bash
# NOOBS UPD Installer - Works on Debian/Ubuntu minimal
set -e  # Exit on error

# Colors
G="\e[1;32m"
R="\e[1;31m"
Y="\e[1;33m"
C="\e[1;36m"
NC="\e[0m"

# Root check
if [ "$EUID" -ne 0 ]; then
    echo -e "${R}Please run as root.${NC}"
    exit 1
fi

# Ensure wget and curl are available
echo -e "${Y}[+] Updating package list and installing wget/curl...${NC}"
apt-get update -qq
apt-get install -y -qq wget curl

# OS detection
OS=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
echo -e "${G}[+] OS: $OS${NC}"

# Get server IP and location
echo -e "${Y}[+] Fetching server info...${NC}"
GEO=$(curl -4 -s --max-time 10 "https://ipapi.co/json/" 2>/dev/null || echo '{}')
IP=$(echo "$GEO" | grep -oP '"ip":\s*"\K[^"]+' || echo "N/A")
CITY=$(echo "$GEO" | grep -oP '"city":\s*"\K[^"]+' || echo "Unknown")
COUNTRY=$(echo "$GEO" | grep -oP '"country_name":\s*"\K[^"]+' || echo "Unknown")
ISP=$(echo "$GEO" | grep -oP '"org":\s*"\K[^"]+' || echo "Unknown")
LOC="${CITY}, ${COUNTRY}"

# Banner
clear
echo -e "${G}"
echo "  ____  _____  _   _ _____  ____  "
echo " / __ \|  __ \| | | |  __ \|  _ \ "
echo "| |  | | |__) | | | | |  | | |_) |"
echo "| |  | |  ___/| | | | |  | |  __/ "
echo "| |__| | |    | |_| | |__| | |    "
echo " \____/|_|     \___/|_____/|_|    "
echo -e "${NC}"
echo "---------------------------------------------------"
echo "  OS       : $OS"
echo "  Location : $LOC"
echo "  IP       : $IP"
echo "  ISP      : $ISP"
echo "  Admin    : @Ardvak"
echo "---------------------------------------------------"
echo ""

# Dependencies
echo -e "${Y}[1/6] Installing dependencies...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    jq iptables iptables-persistent netfilter-persistent openssl vnstat bc

# Architecture
echo -e "${Y}[2/6] Detecting architecture...${NC}"
ARCH=$(uname -m)
case $ARCH in
    x86_64|amd64) BIN="amd64" ;;
    aarch64|arm64) BIN="arm64" ;;
    *) echo -e "${R}Unsupported architecture: $ARCH${NC}"; exit 1 ;;
esac
echo -e "${G}   Architecture: $ARCH -> $BIN${NC}"

# Download ZIVPN binary
echo -e "${Y}[3/6] Downloading ZIVPN binary...${NC}"
wget -q --show-progress -O /usr/local/bin/zivpn \
    "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-$BIN" || {
    echo -e "${R}Failed to download ZIVPN binary.${NC}"
    exit 1
}
chmod +x /usr/local/bin/zivpn

# Config & database
echo -e "${Y}[4/6] Setting up config and database...${NC}"
mkdir -p /etc/zivpn
cat <<EOF > /etc/zivpn/config.json
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": []
  }
}
EOF
touch /etc/zivpn/users.db

# SSL certificate
echo -e "${Y}[5/6] Generating SSL certificate...${NC}"
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=GH/ST=Accra/L=Accra/O=Ardvak/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" \
    -out "/etc/zivpn/zivpn.crt" 2>/dev/null

# Firewall
echo -e "${Y}[6/6] Configuring firewall...${NC}"
# Disable UFW if present
if command -v ufw &>/dev/null; then
    ufw disable &>/dev/null
fi
# Allow SSH
iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
# Allow ZIVPN ports
iptables -I INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || true
iptables -I INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null || true
# NAT
iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || true
# Persist rules
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
elif command -v iptables-save &>/dev/null; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
fi

# Systemd service
cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zivpn
systemctl start zivpn

# Install ziudp panel
echo -e "${Y}[+] Installing ziudp panel...${NC}"
wget -qO /usr/local/bin/ziudp \
    https://raw.githubusercontent.com/autobot-sys/NOOBS-UPD/main/ziudp || {
    echo -e "${R}Failed to download ziudp panel.${NC}"
    exit 1
}
chmod +x /usr/local/bin/ziudp

# Summary
echo ""
echo -e "${C}====================================================${NC}"
echo -e "${G}         INSTALLATION COMPLETE!${NC}"
echo -e "${C}====================================================${NC}"
echo -e "${G} Server IP  :${NC} $IP"
echo -e "${G} Location   :${NC} $LOC"
echo -e "${G} ISP        :${NC} $ISP"
echo -e "${G} ZIVPN Port :${NC} 5667 (UDP)"
echo -e "${G} NAT Range  :${NC} 6000 - 19999"
echo -e "${C}====================================================${NC}"
echo -e "${Y} Type 'ziudp' to open the panel.${NC}"
echo -e "${C}====================================================${NC}"
