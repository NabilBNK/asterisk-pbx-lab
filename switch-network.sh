#!/bin/bash
#
# Quick Network Switch Helper
# Run this when you change networks (home, mobile hotspot, university, etc.)
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================================"
echo "   Network Switch Helper"
echo "================================================"
echo ""

# Detect network change
get_current_ip() {
    local interface=$(ip route | grep default | awk '{print $5}' | head -n 1)
    ip -4 addr show dev "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1
}

NEW_IP=$(get_current_ip)
OLD_IP=""

if [ -f ".current-ip" ]; then
    source .current-ip
    OLD_IP="$ASTERISK_IP"
fi

echo "Network Status:"
if [ -n "$OLD_IP" ]; then
    echo "  Previous IP: $OLD_IP"
fi
echo "  Current IP: $NEW_IP"
echo ""

if [ "$OLD_IP" == "$NEW_IP" ]; then
    echo -e "${GREEN}✓ No IP change detected. Network is unchanged.${NC}"
    exit 0
fi

echo -e "${YELLOW}⚠ Network change detected!${NC}"
echo ""
echo "Actions needed:"
echo "  1. Update Asterisk configuration"
echo "  2. Restart container"
echo "  3. Re-register SIP clients"
echo ""
read -p "Proceed with network reconfiguration? (y/n): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled. Run './configure-ip.sh' manually when ready."
    exit 0
fi

# Run configure-ip.sh
echo ""
./configure-ip.sh

echo ""
echo -e "${GREEN}✓ Network switch complete!${NC}"
echo ""
echo -e "${YELLOW}Important: Update your SIP clients:${NC}"
echo "  New server address: $NEW_IP"
echo "  Port: 5060"
echo ""

