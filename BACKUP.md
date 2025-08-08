# Backup and Disaster Recovery

## Overview

This document provides comprehensive backup and disaster recovery procedures for the AI Automation System, ensuring data protection and business continuity.

## Backup Strategy

### Backup Types

| Type | Frequency | Retention | Purpose |
|------|-----------|-----------|---------|
| **Full** | Weekly | 4 weeks | Complete system backup |
| **Incremental** | Daily | 2 weeks | Changed files only |
| **Configuration** | Before changes | 10 versions | Settings and metadata |
| **Emergency** | On-demand | Until resolved | Pre-maintenance snapshots |

### What Gets Backed Up

#### n8n Data
- **Database**: `/home/roi12/.n8n/database.sqlite` (workflows, executions, settings)
- **Configuration**: `/home/roi12/.n8n/config` (application settings)
- **Custom Nodes**: `/home/roi12/.n8n/nodes/` (installed community nodes)
- **SSH Keys**: `/home/roi12/.n8n/ssh/` (git repository access)
- **Binary Data**: `/home/roi12/.n8n/binaryData/` (workflow file uploads)

#### Qdrant Data
- **Collections**: `/home/roi12/qdrant_storage/collections/` (vector data and indices)
- **Configuration**: `/home/roi12/qdrant_storage/*/config.json` (collection settings)
- **Metadata**: `/home/roi12/qdrant_storage/raft_state.json` (cluster state)
- **WAL**: `/home/roi12/qdrant_storage/*/wal/` (write-ahead logs)

#### System Configuration
- **Container Configurations**: Docker inspect output for all containers
- **Network Settings**: Docker network configurations
- **Environment Variables**: Container runtime configurations
- **Scripts**: All management and automation scripts

## Backup Procedures

### Automated Backup Setup

#### Daily Incremental Backup
```bash
# Add to crontab
crontab -e

# Add this line for daily backup at 2 AM
0 2 * * * /home/roi12/scripts/backup-system.sh -t incremental >> /home/roi12/backup.log 2>&1
```

#### Weekly Full Backup
```bash
# Add to crontab for weekly full backup on Sundays at 1 AM
0 1 * * 0 /home/roi12/scripts/backup-system.sh -t full -s >> /home/roi12/backup.log 2>&1
```

#### Pre-Change Configuration Backup
```bash
# Before making any system changes
./scripts/backup-system.sh -t config-only
```

### Manual Backup Operations

#### Full System Backup
```bash
# Standard full backup
./scripts/backup-system.sh -t full

# Full backup with service shutdown (most consistent)
./scripts/backup-system.sh -t full -s

# Compressed with xz (smaller size)
./scripts/backup-system.sh -t full -c xz
```

#### Incremental Backup
```bash
# Last 7 days of changes
./scripts/backup-system.sh -t incremental

# Custom timeframe (last 3 days)
./scripts/backup-system.sh -t incremental -d 3
```

#### Emergency Pre-Maintenance Backup
```bash
# Before system updates or major changes
./scripts/backup-system.sh -t full -s
mv /home/roi12/backups/ai-system-backup-* /home/roi12/backups/pre-maintenance-$(date +%Y%m%d)/
```

## Backup Storage

### Local Storage Structure
```
/home/roi12/backups/
├── ai-system-backup-2025-08-08_14-30-15/    # Timestamped backup
│   ├── backup-metadata.json                  # Backup information
│   ├── backup-summary.txt                    # Summary and file list
│   ├── RESTORE-INSTRUCTIONS.md               # Restoration guide
│   ├── n8n-data.tar.gz                      # n8n data archive
│   ├── qdrant-data.tar.gz                   # Qdrant data archive
│   ├── n8n-config.json                      # Container configuration
│   ├── qdrant-config.json                   # Container configuration
│   └── network-config.json                  # Network configuration
├── ai-system-backup-2025-08-07_14-30-15/    # Previous backup
└── ...                                       # Older backups
```

### Storage Locations

#### Primary (Local)
- **Path**: `/home/roi12/backups/`
- **Capacity**: Monitor with `df -h /home/roi12/`
- **Retention**: Automatic cleanup keeps last 10 full backups
- **Access**: Local filesystem access

#### Secondary (Recommended)
```bash
# External storage mount
mkdir -p /mnt/backup-drive
sudo mount /dev/sdX1 /mnt/backup-drive

# Copy backups to external storage
rsync -av /home/roi12/backups/ /mnt/backup-drive/ai-backups/
```

#### Cloud Storage (Production)
```bash
# AWS S3 backup
aws s3 sync /home/roi12/backups/ s3://your-backup-bucket/ai-system/

# Google Cloud Storage
gsutil -m rsync -r /home/roi12/backups/ gs://your-backup-bucket/ai-system/

# Azure Blob Storage
az storage blob upload-batch \
    --destination ai-backups \
    --source /home/roi12/backups/ \
    --account-name yourstorageaccount
```

### Backup Encryption

#### Local Encryption
```bash
# Encrypt backup with GPG
./scripts/backup-system.sh -t full
cd /home/roi12/backups/latest/
tar -czf - *.tar.gz *.json | gpg --cipher-algo AES256 --symmetric > encrypted-backup.tar.gz.gpg

# Decrypt when needed
gpg --decrypt encrypted-backup.tar.gz.gpg | tar -xzf -
```

#### Cloud Encryption
```bash
# Encrypt before cloud upload
gpg --cipher-algo AES256 --symmetric backup-archive.tar.gz
aws s3 cp backup-archive.tar.gz.gpg s3://your-bucket/encrypted/
```

## Restoration Procedures

### Pre-Restoration Checklist
1. ✅ Identify backup to restore from
2. ✅ Verify backup integrity
3. ✅ Stop all services
4. ✅ Create backup of current state (if possible)
5. ✅ Ensure sufficient disk space
6. ✅ Verify restoration permissions

### Full System Restoration

#### Standard Full Restore
```bash
# 1. Stop all services
./scripts/stop-system.sh

# 2. Backup current state (if corrupted but accessible)
./scripts/backup-system.sh -t config-only

# 3. Identify restore point
ls -la /home/roi12/backups/
RESTORE_DIR="/home/roi12/backups/ai-system-backup-2025-08-08_14-30-15"

# 4. Remove current data directories
sudo mv /home/roi12/.n8n /home/roi12/.n8n.old
sudo mv /home/roi12/qdrant_storage /home/roi12/qdrant_storage.old

# 5. Restore data
cd "$RESTORE_DIR"
tar -xzf n8n-data.tar.gz -C /home/roi12/
tar -xzf qdrant-data.tar.gz -C /home/roi12/

# 6. Fix permissions
sudo chown -R 1000:1000 /home/roi12/.n8n/
sudo chown -R roi12:roi12 /home/roi12/qdrant_storage/

# 7. Start services
./scripts/start-system.sh

# 8. Verify restoration
./scripts/health-check.sh
```

#### Encrypted Backup Restoration
```bash
# 1. Decrypt backup
cd /home/roi12/backups/encrypted/
gpg --decrypt encrypted-backup.tar.gz.gpg > restored-backup.tar.gz

# 2. Extract archives
tar -xzf restored-backup.tar.gz

# 3. Follow standard restoration procedure
```

### Selective Data Restoration

#### Restore n8n Data Only
```bash
# Stop n8n service
docker stop n8n

# Backup current n8n data
mv /home/roi12/.n8n /home/roi12/.n8n.backup

# Restore from backup
tar -xzf "$RESTORE_DIR/n8n-data.tar.gz" -C /home/roi12/

# Fix permissions and restart
sudo chown -R 1000:1000 /home/roi12/.n8n/
docker start n8n
```

#### Restore Qdrant Data Only
```bash
# Stop Qdrant service
docker stop qdrant

# Backup current Qdrant data
mv /home/roi12/qdrant_storage /home/roi12/qdrant_storage.backup

# Restore from backup
tar -xzf "$RESTORE_DIR/qdrant-data.tar.gz" -C /home/roi12/

# Fix permissions and restart
sudo chown -R roi12:roi12 /home/roi12/qdrant_storage/
docker start qdrant
```

#### Restore Configuration Only
```bash
# Extract specific configurations
cd "$RESTORE_DIR"
tar -xzf n8n-data.tar.gz .n8n/config
tar -xzf qdrant-data.tar.gz qdrant_storage/*/config.json

# Apply configurations selectively
cp -r .n8n/config /home/roi12/.n8n/
find qdrant_storage -name "config.json" -exec cp {} /home/roi12/qdrant_storage/ \;

# Restart services to apply changes
docker restart n8n qdrant
```

### Point-in-Time Recovery

#### Using Incremental Backups
```bash
# 1. Restore from last full backup
FULL_BACKUP="/home/roi12/backups/ai-system-backup-2025-08-01_02-00-00"
tar -xzf "$FULL_BACKUP/n8n-data.tar.gz" -C /home/roi12/
tar -xzf "$FULL_BACKUP/qdrant-data.tar.gz" -C /home/roi12/

# 2. Apply incremental backups in chronological order
for backup in /home/roi12/backups/ai-system-backup-2025-08-0[2-7]*/; do
    echo "Applying incremental backup: $backup"
    if [ -f "$backup/n8n-incremental.tar.gz" ]; then
        tar -xzf "$backup/n8n-incremental.tar.gz" -C /home/roi12/
    fi
    if [ -f "$backup/qdrant-incremental.tar.gz" ]; then
        tar -xzf "$backup/qdrant-incremental.tar.gz" -C /home/roi12/
    fi
done

# 3. Fix permissions and start services
sudo chown -R 1000:1000 /home/roi12/.n8n/
sudo chown -R roi12:roi12 /home/roi12/qdrant_storage/
./scripts/start-system.sh
```

## Disaster Recovery

### Disaster Scenarios

#### Hardware Failure
- **Impact**: Complete system loss
- **RTO**: 4 hours (Recovery Time Objective)
- **RPO**: 24 hours (Recovery Point Objective - daily backups)

#### Data Corruption
- **Impact**: Partial or complete data loss
- **RTO**: 2 hours
- **RPO**: 1 hour (incremental backups)

#### Accidental Deletion
- **Impact**: Specific workflows or collections lost
- **RTO**: 30 minutes
- **RPO**: Previous backup cycle

### Recovery Procedures by Scenario

#### Complete System Loss
```bash
# 1. Set up new system/environment
sudo apt update && sudo apt install docker.io -y

# 2. Clone system repository (if available)
git clone https://github.com/ROI-DANINO/linox-n8n.git
cd linox-n8n

# 3. Retrieve backups from secondary storage
# From external drive:
sudo mount /dev/sdX1 /mnt/backup
cp -r /mnt/backup/ai-backups/* /home/roi12/backups/

# From cloud storage:
aws s3 sync s3://your-backup-bucket/ai-system/ /home/roi12/backups/

# 4. Perform full restoration
./scripts/start-system.sh  # Creates initial containers
./scripts/stop-system.sh   # Stop for restoration
# Follow full restoration procedure above
```

#### Database Corruption
```bash
# 1. Identify corruption
sqlite3 /home/roi12/.n8n/database.sqlite "PRAGMA integrity_check;"

# 2. Stop affected service
docker stop n8n

# 3. Attempt database repair
sqlite3 /home/roi12/.n8n/database.sqlite ".recover /tmp/recovered.db"

# 4. If repair fails, restore from backup
mv /home/roi12/.n8n/database.sqlite /home/roi12/.n8n/database.sqlite.corrupted
tar -xzf "$LATEST_BACKUP/n8n-data.tar.gz" .n8n/database.sqlite -C /home/roi12/

# 5. Restart service
docker start n8n
```

### Business Continuity

#### Backup Validation
```bash
#!/bin/bash
# Backup validation script (run weekly)

echo "=== Backup Validation $(date) ==="

# Find latest backup
LATEST_BACKUP=$(ls -td /home/roi12/backups/ai-system-backup-* | head -1)
echo "Validating backup: $LATEST_BACKUP"

# Check backup integrity
cd "$LATEST_BACKUP"

# Verify archive integrity
for archive in *.tar.gz; do
    if tar -tzf "$archive" >/dev/null 2>&1; then
        echo "✓ $archive - Valid"
    else
        echo "✗ $archive - Corrupted"
    fi
done

# Test restoration (in isolated environment)
# This would typically be done in a separate test environment
```

#### Recovery Testing
```bash
# Quarterly disaster recovery test
# 1. Set up isolated test environment
# 2. Restore from backup
# 3. Verify all services functional
# 4. Test data integrity
# 5. Document results and improvements
```

## Monitoring and Alerting

### Backup Monitoring
```bash
# Monitor backup job success
#!/bin/bash
# /home/roi12/scripts/monitor-backups.sh

BACKUP_LOG="/home/roi12/backup.log"
ALERT_EMAIL="admin@example.com"

# Check if backup ran in last 25 hours
LAST_BACKUP=$(find /home/roi12/backups -name "ai-system-backup-*" -mtime -1 | wc -l)

if [ "$LAST_BACKUP" -eq 0 ]; then
    echo "ALERT: No backup found in last 24 hours" | mail -s "Backup Alert" "$ALERT_EMAIL"
fi

# Check backup log for errors
if tail -50 "$BACKUP_LOG" | grep -i "error\|failed" > /dev/null; then
    echo "ALERT: Backup errors detected" | mail -s "Backup Error Alert" "$ALERT_EMAIL"
fi
```

### Storage Monitoring
```bash
# Monitor backup storage usage
BACKUP_SIZE=$(du -sh /home/roi12/backups | cut -f1)
DISK_USAGE=$(df -h /home/roi12 | awk 'NR==2 {print $5}' | sed 's/%//')

if [ "$DISK_USAGE" -gt 85 ]; then
    echo "ALERT: Backup disk usage high: $DISK_USAGE%" | mail -s "Disk Space Alert" admin@example.com
fi
```

## Best Practices

### Backup Best Practices
1. **3-2-1 Rule**: 3 copies, 2 different media types, 1 offsite
2. **Regular Testing**: Test restores quarterly
3. **Automated Monitoring**: Alert on backup failures
4. **Documentation**: Keep restoration procedures updated
5. **Security**: Encrypt sensitive backups

### Operational Procedures
1. **Pre-Change Backups**: Always backup before major changes
2. **Scheduled Maintenance**: Plan backup windows during low usage
3. **Retention Policies**: Balance storage costs with recovery needs
4. **Access Control**: Limit backup access to authorized personnel
5. **Audit Trail**: Log all backup and restore operations

## Troubleshooting Backup Issues

### Common Backup Problems

#### Insufficient Disk Space
```bash
# Check disk usage
df -h /home/roi12

# Clean up old backups
ls -t /home/roi12/backups/ai-system-backup-* | tail -n +6 | xargs rm -rf

# Move backups to external storage
rsync -av /home/roi12/backups/ /mnt/external/backups/
```

#### Permission Errors
```bash
# Fix backup directory permissions
sudo chown -R roi12:roi12 /home/roi12/backups/

# Fix source directory permissions
sudo chown -R 1000:1000 /home/roi12/.n8n/
sudo chown -R roi12:roi12 /home/roi12/qdrant_storage/
```

#### Backup Corruption
```bash
# Verify archive integrity
tar -tzf backup-archive.tar.gz >/dev/null

# If corrupted, use previous backup
ls -t /home/roi12/backups/*/backup-summary.txt | head -5
```

### Restoration Problems

#### Service Won't Start After Restore
```bash
# Check logs
./scripts/health-check.sh
docker logs n8n
docker logs qdrant

# Verify permissions
ls -la /home/roi12/.n8n/
ls -la /home/roi12/qdrant_storage/

# Fix ownership if needed
sudo chown -R 1000:1000 /home/roi12/.n8n/
sudo chown -R roi12:roi12 /home/roi12/qdrant_storage/
```

#### Data Inconsistency After Restore
```bash
# Check database integrity
docker exec n8n sqlite3 /home/node/.n8n/database.sqlite "PRAGMA integrity_check;"

# Verify Qdrant collections
curl -s http://localhost:6333/collections
```

---

**Remember**: Backup procedures are only as good as your ability to restore from them. Regular testing of restoration procedures is essential for effective disaster recovery.