#!/bin/bash
# Asterisk Lab Backup Script

BACKUP_DIR="$HOME/asterisk-backups"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="asterisk-lab-backup-$BACKUP_DATE"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

echo "Creating backup: $BACKUP_NAME"
mkdir -p "$BACKUP_PATH"

# Stop the container for consistent backup
echo "Stopping Asterisk container..."
cd ~/asterisk-pbx-lab
sudo docker compose down

# 1. Backup configuration files
echo "Backing up configuration files..."
cp -r config "$BACKUP_PATH/"
cp docker-compose.yml "$BACKUP_PATH/"
cp docker-compose.yml.backup "$BACKUP_PATH/" 2>/dev/null

# 2. Backup Docker volume (voicemail)
echo "Backing up voicemail volume..."
sudo docker run --rm -v asterisk-voicemail:/data -v "$BACKUP_PATH":/backup \
    alpine tar czf /backup/voicemail-data.tar.gz -C /data .

# 3. Backup sound files (if customized)
if [ -d "sounds" ]; then
    echo "Backing up custom sounds..."
    cp -r sounds "$BACKUP_PATH/"
fi

# 4. Create backup info file
echo "Creating backup info..."
cat > "$BACKUP_PATH/backup-info.txt" << INFO
Asterisk Lab Backup
Date: $(date)
Hostname: $(hostname)
VM IP: 192.168.100.34
Asterisk Version: 22.6.0
Docker Image: andrius/asterisk:latest

Contents:
- Configuration files (config/)
- Docker compose file
- Voicemail data (voicemail-data.tar.gz)
- Sound files (if any)
INFO

# 5. Create compressed archive
echo "Creating compressed archive..."
cd "$BACKUP_DIR"
tar czf "$BACKUP_NAME.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_NAME"

# Restart container
echo "Restarting Asterisk container..."
cd ~/asterisk-pbx-lab
sudo docker compose up -d

echo "Backup completed: $BACKUP_DIR/$BACKUP_NAME.tar.gz"
ls -lh "$BACKUP_DIR/$BACKUP_NAME.tar.gz"
