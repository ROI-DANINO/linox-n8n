# Management Scripts

This directory contains management and automation scripts for the AI Automation System.

## Available Scripts

### System Management

#### `start-system.sh`
**Purpose**: Start all AI automation services in the correct order
**Usage**:
```bash
./scripts/start-system.sh
```
**Features**:
- Creates Docker network if needed
- Starts services with health checks
- Waits for services to be ready
- Provides service URLs and status
- Colorized output with progress indicators

#### `stop-system.sh`
**Purpose**: Gracefully stop all services
**Usage**:
```bash
./scripts/stop-system.sh
```
**Features**:
- Graceful shutdown with timeouts
- Force kill if graceful shutdown fails
- Status reporting
- Reverse dependency order shutdown

#### `health-check.sh`
**Purpose**: Comprehensive system health monitoring
**Usage**:
```bash
./scripts/health-check.sh
```
**Features**:
- Docker environment validation
- Container health checks
- Service accessibility tests
- Resource usage monitoring
- Network connectivity verification
- Data volume validation
- Error log analysis
- Health scoring and recommendations

**Exit Codes**:
- `0`: Excellent health (90%+ checks passed)
- `1`: Degraded health (50-89% checks passed)
- `2`: Critical issues (<50% checks passed)

### Data Management

#### `backup-system.sh`
**Purpose**: Create comprehensive system backups
**Usage**:
```bash
# Full backup
./scripts/backup-system.sh -t full

# Incremental backup (last 7 days)
./scripts/backup-system.sh -t incremental

# Configuration only
./scripts/backup-system.sh -t config-only

# Full backup with service shutdown
./scripts/backup-system.sh -t full -s

# Compressed backup
./scripts/backup-system.sh -t full -c xz
```

**Options**:
- `-t, --type`: Backup type (full, incremental, config-only)
- `-c, --compression`: Compression type (gzip, xz, none)
- `-s, --stop-services`: Stop services during backup
- `-h, --help`: Show help message

**Features**:
- Multiple backup strategies
- Metadata and restoration instructions
- Container configuration backup
- Compression options
- Automatic cleanup of old backups
- Backup verification

### System Maintenance

#### `cleanup-system.sh`
**Purpose**: Remove containers, networks, and optionally data
**Usage**:
```bash
# Remove containers and network only
./scripts/cleanup-system.sh

# Remove containers, network, and data (DESTRUCTIVE!)
./scripts/cleanup-system.sh -d

# Remove everything including Docker images
./scripts/cleanup-system.sh -d -i

# Force cleanup without prompts
./scripts/cleanup-system.sh -d -i -f
```

**Options**:
- `-d, --data`: Remove data volumes (DESTRUCTIVE!)
- `-i, --images`: Remove Docker images
- `-f, --force`: Skip confirmation prompts
- `-h, --help`: Show help message

**⚠️ WARNING**: Using `-d` flag permanently deletes all workflows and vector data!

## Usage Examples

### Daily Operations
```bash
# Start system
./scripts/start-system.sh

# Check system health
./scripts/health-check.sh

# Stop system for maintenance
./scripts/stop-system.sh
```

### Backup Operations
```bash
# Daily incremental backup (automated via cron)
./scripts/backup-system.sh -t incremental

# Weekly full backup (automated via cron)
./scripts/backup-system.sh -t full -s

# Pre-maintenance backup
./scripts/backup-system.sh -t full -s
```

### System Maintenance
```bash
# Health monitoring
./scripts/health-check.sh && echo "System healthy" || echo "Issues detected"

# Complete system reset (DESTRUCTIVE!)
./scripts/cleanup-system.sh -d -f
./scripts/start-system.sh
```

## Automation Setup

### Cron Job Examples
```bash
# Edit crontab
crontab -e

# Add these lines for automation:

# Daily incremental backup at 2 AM
0 2 * * * /home/roi12/scripts/backup-system.sh -t incremental >> /home/roi12/backup.log 2>&1

# Weekly full backup on Sundays at 1 AM
0 1 * * 0 /home/roi12/scripts/backup-system.sh -t full -s >> /home/roi12/backup.log 2>&1

# Health check every 15 minutes
*/15 * * * * /home/roi12/scripts/health-check.sh >> /home/roi12/health.log 2>&1

# Daily cleanup at 3 AM
0 3 * * * docker system prune -f >> /home/roi12/cleanup.log 2>&1
```

### Monitoring Integration
```bash
# Health check with alerting
./scripts/health-check.sh || echo "ALERT: System health check failed" | mail -s "AI System Alert" admin@example.com

# Backup monitoring
if [ $(find /home/roi12/backups -name "ai-system-backup-*" -mtime -1 | wc -l) -eq 0 ]; then
    echo "ALERT: No backup created in last 24 hours" | mail -s "Backup Alert" admin@example.com
fi
```

## Script Permissions

All scripts are executable. If needed, fix permissions:
```bash
chmod +x /home/roi12/scripts/*.sh
```

## Logging

Scripts generate logs in various locations:
- **Health checks**: `/home/roi12/health.log`
- **Backups**: `/home/roi12/backup.log`
- **Cleanup**: `/home/roi12/cleanup.log`
- **Script output**: Sent to stdout/stderr

## Error Handling

Scripts include comprehensive error handling:
- Exit codes indicate success/failure status
- Colorized output for easy identification
- Detailed error messages
- Rollback procedures where applicable
- Safe defaults for destructive operations

## Customization

Scripts can be customized by modifying:
- **Paths**: Update directory paths for different installations
- **Timeouts**: Adjust service startup/shutdown timeouts
- **Retention**: Modify backup retention policies
- **Compression**: Change default compression settings
- **Alerting**: Add email notifications or webhook calls

## Troubleshooting

### Common Issues

#### Permission Denied
```bash
# Fix script permissions
chmod +x /home/roi12/scripts/*.sh

# Fix data directory permissions
sudo chown -R roi12:roi12 /home/roi12/qdrant_storage/
sudo chown -R 1000:1000 /home/roi12/.n8n/
```

#### Docker Not Accessible
```bash
# Check Docker daemon status
sudo systemctl status docker

# Start Docker if needed
sudo systemctl start docker

# Add user to docker group (requires logout/login)
sudo usermod -aG docker $USER
```

#### Scripts Not Found
```bash
# Ensure you're in the correct directory
cd /home/roi12
pwd

# Check script existence
ls -la scripts/
```

### Getting Help

Each script includes built-in help:
```bash
./scripts/start-system.sh --help
./scripts/backup-system.sh --help
./scripts/cleanup-system.sh --help
```

For additional help, see:
- [TROUBLESHOOTING.md](../TROUBLESHOOTING.md)
- [OPERATIONS.md](../OPERATIONS.md)
- Script source code (well-commented)

---

These scripts provide a complete toolkit for managing your AI Automation System effectively.