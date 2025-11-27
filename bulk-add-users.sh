#!/bin/bash
#
# Bulk User Import from CSV
# CSV Format: extension,password,fullname,vm_password,email
#

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

CSV_FILE="$1"

echo "================================================"
echo "   Bulk User Import"
echo "================================================"
echo ""

if [ -z "$CSV_FILE" ]; then
    echo -e "${RED}Usage: ./bulk-add-users.sh users.csv${NC}"
    echo ""
    echo "CSV file format:"
    echo "extension,password,fullname,vm_password,email"
    echo "1004,Pass1004,Alice Johnson,5678,alice@example.com"
    echo "1005,Pass1005,Bob Smith,6789,bob@example.com"
    echo ""
    exit 1
fi

if [ ! -f "$CSV_FILE" ]; then
    echo -e "${RED}Error: File $CSV_FILE not found${NC}"
    exit 1
fi

# Count users (skip header)
USER_COUNT=$(tail -n +2 "$CSV_FILE" | wc -l)
echo -e "${YELLOW}Found $USER_COUNT users to import${NC}"
echo ""

# Get Asterisk IP
get_asterisk_ip() {
    if [ -f ".current-ip" ]; then
        source .current-ip
        echo "$ASTERISK_IP"
    else
        local interface=$(ip route | grep default | awk '{print $5}' | head -n 1)
        ip -4 addr show dev "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1
    fi
}

ASTERISK_IP=$(get_asterisk_ip)

# Process each line (skip header)
COUNT=0
FAILED=0

tail -n +2 "$CSV_FILE" | while IFS=',' read -r extension password fullname vm_password email; do
    COUNT=$((COUNT + 1))
    
    echo -e "${YELLOW}[$COUNT/$USER_COUNT] Adding: $extension - $fullname${NC}"
    
    # Check if extension already exists
    if grep -q "^\[$extension\]" config/pjsip.conf; then
        echo -e "${RED}  ✗ Extension $extension already exists, skipping${NC}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Backup configs (only once)
    if [ $COUNT -eq 1 ]; then
        BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
        cp config/pjsip.conf "config/pjsip.conf.backup.$BACKUP_DATE"
        cp config/extensions.conf "config/extensions.conf.backup.$BACKUP_DATE"
        cp config/voicemail.conf "config/voicemail.conf.backup.$BACKUP_DATE"
    fi
    
    # Add to pjsip.conf
    cat >> config/pjsip.conf << PJSIP

; Extension $extension - $fullname
[$extension]
type=endpoint
context=internal
disallow=all
allow=ulaw
allow=alaw
auth=$extension
aors=$extension
direct_media=no

[$extension]
type=auth
auth_type=userpass
password=$password
username=$extension

[$extension]
type=aor
max_contacts=1
remove_existing=yes
PJSIP

    # Add to extensions.conf
    sed -i "/^\[internal\]/a\\
; Extension $extension - $fullname\\
exten => $extension,1,NoOp(Calling $fullname)\\
exten => $extension,2,Dial(PJSIP/$extension,15)\\
exten => $extension,3,VoiceMail(${extension}@main)\\
exten => $extension,4,Hangup()\\
" config/extensions.conf

    # Add to voicemail.conf
    sed -i "/^\[main\]/a\\
$extension => $vm_password,$fullname,$email" config/voicemail.conf

    # Create voicemail directories
    sudo docker exec asterisk-pbx bash -c "
    mkdir -p /var/spool/asterisk/voicemail/main/$extension/{INBOX,Old,tmp,temp}
    chown -R asterisk:asterisk /var/spool/asterisk/voicemail/main/$extension
    chmod -R 755 /var/spool/asterisk/voicemail/main/$extension
    " &>/dev/null
    
    echo -e "${GREEN}  ✓ Added successfully${NC}"
done

# Reload Asterisk once at the end
echo ""
echo -e "${YELLOW}Reloading Asterisk configuration...${NC}"
sudo docker exec asterisk-pbx asterisk -rx "pjsip reload" &>/dev/null
sudo docker exec asterisk-pbx asterisk -rx "dialplan reload" &>/dev/null
sudo docker exec asterisk-pbx asterisk -rx "voicemail reload" &>/dev/null

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}✓ Bulk Import Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Summary:"
echo "  Total processed: $USER_COUNT"
echo "  Server IP: $ASTERISK_IP"
echo ""
echo "Configure SIP clients with:"
echo "  Domain: $ASTERISK_IP"
echo "  Port: 5060"
echo ""
