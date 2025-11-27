#!/bin/bash
#
# Remove User from Asterisk Lab
#

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================================"
echo "   Remove Asterisk User"
echo "================================================"
echo ""

# Get extension to remove
read -p "Enter extension number to remove: " EXTENSION

# Validate extension exists
if ! grep -q "^\[$EXTENSION\]" config/pjsip.conf; then
    echo -e "${RED}Error: Extension $EXTENSION not found${NC}"
    exit 1
fi

# Get user info before removing
FULLNAME=$(grep -A 20 "^\[$EXTENSION\]" config/pjsip.conf | grep "^;" | head -n 1 | sed 's/^; Extension [0-9]* - //')

echo ""
echo -e "${YELLOW}Found user:${NC}"
echo "  Extension: $EXTENSION"
echo "  Name: $FULLNAME"
echo ""
read -p "Are you sure you want to remove this user? (y/n): " CONFIRM

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

# Remove from pjsip.conf (remove all 3 sections: endpoint, auth, aor)
echo -e "${YELLOW}Removing from pjsip.conf...${NC}"
# Remove comment line and all sections for this extension
sed -i "/^; Extension $EXTENSION/d" config/pjsip.conf
# Remove the three [EXTENSION] sections
awk -v ext="[$EXTENSION]" '
    $0 == ext { skip=1; next }
    skip && /^\[/ { skip=0 }
    !skip
' config/pjsip.conf > config/pjsip.conf.tmp && mv config/pjsip.conf.tmp config/pjsip.conf

# Remove from extensions.conf
echo -e "${YELLOW}Removing from extensions.conf...${NC}"
sed -i "/^; Extension $EXTENSION/,/^exten => $EXTENSION,4,Hangup()/d" config/extensions.conf

# Remove from voicemail.conf
echo -e "${YELLOW}Removing from voicemail.conf...${NC}"
sed -i "/^$EXTENSION =>/d" config/voicemail.conf

# Reload Asterisk configs
echo -e "${YELLOW}Reloading Asterisk...${NC}"
sudo docker exec asterisk-pbx asterisk -rx "pjsip reload" &>/dev/null
sudo docker exec asterisk-pbx asterisk -rx "dialplan reload" &>/dev/null
sudo docker exec asterisk-pbx asterisk -rx "voicemail reload" &>/dev/null

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}✓ User Removed Successfully!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Removed: Extension $EXTENSION - $FULLNAME"
echo ""
echo "Note: Voicemail files are preserved in Docker volume."
echo "To completely remove voicemail data, run:"
echo "  sudo docker exec asterisk-pbx rm -rf /var/spool/asterisk/voicemail/main/$EXTENSION"
echo ""
