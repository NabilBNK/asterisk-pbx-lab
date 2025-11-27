#!/bin/bash
#
# Asterisk User Addition Script (Dynamic IP Version)
# Automatically detects current server IP
#

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to get current Asterisk IP
get_asterisk_ip() {
    # Try to read from .current-ip file first
    if [ -f ".current-ip" ]; then
        source .current-ip
        echo "$ASTERISK_IP"
    else
        # Fallback: detect IP dynamically
        local interface=$(ip route | grep default | awk '{print $5}' | head -n 1)
        if [ -z "$interface" ]; then
            echo "127.0.0.1"
            return
        fi
        ip -4 addr show dev "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1
    fi
}

# Function to get SIP port from config
get_sip_port() {
    grep -oP 'bind=0\.0\.0\.0:\K[0-9]+' config/pjsip.conf | head -n 1 || echo "5060"
}

echo "================================================"
echo "   Asterisk User Addition Script"
echo "================================================"
echo ""

# Detect current IP and port
ASTERISK_IP=$(get_asterisk_ip)
SIP_PORT=$(get_sip_port)

if [ -z "$ASTERISK_IP" ] || [ "$ASTERISK_IP" == "127.0.0.1" ]; then
    echo -e "${YELLOW}Warning: Could not detect IP address${NC}"
    echo -e "${YELLOW}Run ./configure-ip.sh first to set up networking${NC}"
    echo ""
    read -p "Enter Asterisk server IP manually: " ASTERISK_IP
fi

echo -e "${GREEN}Current Server Configuration:${NC}"
echo "  IP Address: $ASTERISK_IP"
echo "  SIP Port: $SIP_PORT"
echo ""

# Validation functions
validate_extension() {
    if ! [[ "$1" =~ ^[0-9]{4}$ ]]; then
        echo -e "${RED}Error: Extension must be exactly 4 digits${NC}"
        exit 1
    fi
}

check_duplicate() {
    local ext=$1
    if grep -q "^\[$ext\]" config/pjsip.conf; then
        echo -e "${RED}Error: Extension $ext already exists${NC}"
        exit 1
    fi
}

# Get user input
read -p "Enter extension number (4 digits): " EXTENSION
validate_extension "$EXTENSION"
check_duplicate "$EXTENSION"

read -p "Enter SIP password: " PASSWORD
read -p "Enter user's full name: " FULLNAME
read -p "Enter voicemail password (4 digits): " VM_PASSWORD
read -p "Enter user's email: " EMAIL

echo ""
echo -e "${YELLOW}Adding user:${NC}"
echo "  Extension: $EXTENSION"
echo "  Name: $FULLNAME"
echo "  Email: $EMAIL"
echo ""
read -p "Confirm? (y/n): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Backup configs
echo -e "${YELLOW}Creating backups...${NC}"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
cp config/pjsip.conf "config/pjsip.conf.backup.$BACKUP_DATE"
cp config/extensions.conf "config/extensions.conf.backup.$BACKUP_DATE"
cp config/voicemail.conf "config/voicemail.conf.backup.$BACKUP_DATE"

# Add to pjsip.conf
echo -e "${YELLOW}Updating configurations...${NC}"
cat >> config/pjsip.conf << PJSIP

; Extension $EXTENSION - $FULLNAME
[$EXTENSION]
type=endpoint
context=internal
disallow=all
allow=ulaw
allow=alaw
auth=$EXTENSION
aors=$EXTENSION
direct_media=no

[$EXTENSION]
type=auth
auth_type=userpass
password=$PASSWORD
username=$EXTENSION

[$EXTENSION]
type=aor
max_contacts=1
remove_existing=yes
PJSIP

# Add to extensions.conf
sed -i "/^\[internal\]/a\\
; Extension $EXTENSION - $FULLNAME\\
exten => $EXTENSION,1,NoOp(Calling $FULLNAME)\\
exten => $EXTENSION,2,Dial(PJSIP/$EXTENSION,15)\\
exten => $EXTENSION,3,VoiceMail(${EXTENSION}@main)\\
exten => $EXTENSION,4,Hangup()\\
" config/extensions.conf

# Add to voicemail.conf
sed -i "/^\[main\]/a\\
$EXTENSION => $VM_PASSWORD,$FULLNAME,$EMAIL" config/voicemail.conf

# Create voicemail directories
echo -e "${YELLOW}Creating voicemail directories...${NC}"
sudo docker exec asterisk-pbx bash -c "
mkdir -p /var/spool/asterisk/voicemail/main/$EXTENSION/{INBOX,Old,tmp,temp}
chown -R asterisk:asterisk /var/spool/asterisk/voicemail/main/$EXTENSION
chmod -R 755 /var/spool/asterisk/voicemail/main/$EXTENSION
"

# Reload Asterisk
echo -e "${YELLOW}Reloading Asterisk...${NC}"
sudo docker exec asterisk-pbx asterisk -rx "pjsip reload"
sudo docker exec asterisk-pbx asterisk -rx "dialplan reload"
sudo docker exec asterisk-pbx asterisk -rx "voicemail reload"

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}✓ User Added Successfully!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "User Details:"
echo "  Extension: $EXTENSION"
echo "  Name: $FULLNAME"
echo "  Email: $EMAIL"
echo ""
echo "SIP Client Configuration:"
echo "  ┌─────────────────────────────────────────┐"
echo "  │ Server/Domain: $ASTERISK_IP"
echo "  │ Port: $SIP_PORT"
echo "  │ Username: $EXTENSION"
echo "  │ Password: $PASSWORD"
echo "  │ Transport: UDP"
echo "  └─────────────────────────────────────────┘"
echo ""
echo "Voicemail:"
echo "  Dial *97 from extension"
echo "  Password: $VM_PASSWORD"
echo ""
echo -e "${BLUE}Verification commands:${NC}"
echo "  sudo docker exec asterisk-pbx asterisk -rx 'pjsip show endpoints'"
echo "  sudo docker exec asterisk-pbx asterisk -rx 'voicemail show users'"
echo ""

