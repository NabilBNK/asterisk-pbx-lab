#!/bin/bash
#
# Asterisk Lab IP Configuration Script
# Automatically detects current IP and updates all config files
#

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "================================================"
echo "   Asterisk Lab IP Configuration"
echo "================================================"
echo ""

# Function to detect primary network interface
get_primary_interface() {
    ip route | grep default | awk '{print $5}' | head -n 1
}

# Function to get IP address from interface
get_ip_address() {
    local interface=$(get_primary_interface)
    if [ -z "$interface" ]; then
        echo -e "${RED}Error: No active network interface found${NC}"
        exit 1
    fi
    
    # Get IPv4 address using multiple methods (fallback if one fails)
    local ip=$(ip -4 addr show dev "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    
    if [ -z "$ip" ]; then
        # Fallback method
        ip=$(hostname -I | awk '{print $1}')
    fi
    
    if [ -z "$ip" ]; then
        echo -e "${RED}Error: Could not detect IP address${NC}"
        exit 1
    fi
    
    echo "$ip"
}

# Get current IP address
CURRENT_IP=$(get_ip_address)
CURRENT_INTERFACE=$(get_primary_interface)

echo -e "${BLUE}Network Detection:${NC}"
echo "  Interface: $CURRENT_INTERFACE"
echo "  IP Address: $CURRENT_IP"
echo ""

# Check if IP is already set in pjsip.conf
OLD_IP=$(grep -oP 'external_media_address=\K[0-9.]+' config/pjsip.conf | head -n 1)

if [ "$OLD_IP" == "$CURRENT_IP" ]; then
    echo -e "${GREEN}✓ IP address is already up to date ($CURRENT_IP)${NC}"
    echo ""
    exit 0
fi

if [ -n "$OLD_IP" ]; then
    echo -e "${YELLOW}Old IP detected: $OLD_IP${NC}"
    echo -e "${YELLOW}New IP detected: $CURRENT_IP${NC}"
    echo ""
    read -p "Update configuration to new IP? (y/n): " CONFIRM
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
else
    echo -e "${YELLOW}No IP configured yet. Setting up for first time...${NC}"
fi

# Backup configuration files
echo ""
echo -e "${YELLOW}Creating backups...${NC}"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
cp config/pjsip.conf "config/pjsip.conf.backup.$BACKUP_DATE"
cp config/rtp.conf "config/rtp.conf.backup.$BACKUP_DATE" 2>/dev/null || true

# Update pjsip.conf
echo -e "${YELLOW}Updating pjsip.conf...${NC}"

# Update or add external_media_address
if grep -q "external_media_address=" config/pjsip.conf; then
    sed -i "s/external_media_address=.*/external_media_address=$CURRENT_IP/" config/pjsip.conf
else
    # Add to [transport-udp] section
    sed -i "/^\[transport-udp\]/a external_media_address=$CURRENT_IP" config/pjsip.conf
fi

# Update or add external_signaling_address
if grep -q "external_signaling_address=" config/pjsip.conf; then
    sed -i "s/external_signaling_address=.*/external_signaling_address=$CURRENT_IP/" config/pjsip.conf
else
    sed -i "/^\[transport-udp\]/a external_signaling_address=$CURRENT_IP" config/pjsip.conf
fi

# Update bind address if using specific IP (optional)
if grep -q "bind=0.0.0.0:5060" config/pjsip.conf; then
    echo "  ✓ Bind address set to 0.0.0.0 (listens on all interfaces)"
else
    echo "  Note: Using specific bind address"
fi

# Restart Asterisk to apply changes
echo ""
echo -e "${YELLOW}Restarting Asterisk container...${NC}"
sudo docker restart asterisk-pbx

# Wait for Asterisk to start
echo -e "${YELLOW}Waiting for Asterisk to start...${NC}"
sleep 5

# Verify Asterisk is running
if sudo docker exec asterisk-pbx asterisk -rx "core show version" &>/dev/null; then
    echo -e "${GREEN}✓ Asterisk restarted successfully${NC}"
else
    echo -e "${RED}Warning: Asterisk may not have started properly${NC}"
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}✓ IP Configuration Updated!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "New Configuration:"
echo "  Server IP: $CURRENT_IP"
echo "  SIP Port: 5060"
echo "  RTP Ports: 10000-10099"
echo ""
echo "Update your SIP clients to use:"
echo "  Domain/Server: $CURRENT_IP"
echo ""

# Create IP info file for other scripts to read
cat > .current-ip << IP_INFO
ASTERISK_IP=$CURRENT_IP
ASTERISK_INTERFACE=$CURRENT_INTERFACE
UPDATED=$(date)
IP_INFO

echo -e "${BLUE}Tip: Run this script whenever you change networks!${NC}"
echo ""

