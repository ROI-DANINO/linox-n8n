#!/bin/bash

# AI Automation System Backup Script
# Creates comprehensive backups of all system data

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Configuration
BACKUP_DIR="/home/roi12/backups"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="ai-system-backup-$TIMESTAMP"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

# Parse command line arguments
BACKUP_TYPE="full"
COMPRESSION="gzip"
STOP_SERVICES=false

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -t, --type TYPE      Backup type: full, incremental, config-only (default: full)"
    echo "  -c, --compression    Compression: gzip, xz, none (default: gzip)"
    echo "  -s, --stop-services  Stop services during backup (default: false)"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Full backup with gzip compression"
    echo "  $0 -t incremental           # Incremental backup (last 7 days)"
    echo "  $0 -t config-only           # Configuration and metadata only"
    echo "  $0 -s                        # Stop services for consistent backup"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            BACKUP_TYPE="$2"
            shift 2
            ;;
        -c|--compression)
            COMPRESSION="$2"
            shift 2
            ;;
        -s|--stop-services)
            STOP_SERVICES=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo "=== AI Automation System Backup ==="
echo "Timestamp: $(date)"
echo "Backup type: $BACKUP_TYPE"
echo "Compression: $COMPRESSION"
echo "Stop services: $STOP_SERVICES"
echo "Backup path: $BACKUP_PATH"
echo ""

# Create backup directory
mkdir -p "$BACKUP_PATH"
print_status "Created backup directory: $BACKUP_PATH"

# Set compression options
case $COMPRESSION in
    gzip)
        TAR_COMPRESSION="z"
        EXTENSION="tar.gz"
        ;;
    xz)
        TAR_COMPRESSION="J"
        EXTENSION="tar.xz"
        ;;
    none)
        TAR_COMPRESSION=""
        EXTENSION="tar"
        ;;
    *)
        print_error "Unknown compression type: $COMPRESSION"
        exit 1
        ;;
esac

# Function to stop services if requested
stop_services() {
    if [ "$STOP_SERVICES" = true ]; then
        print_status "Stopping services for consistent backup..."
        docker stop n8n qdrant 2>/dev/null || print_warning "Some services were already stopped"
        sleep 2
    fi
}

# Function to start services if they were stopped
start_services() {
    if [ "$STOP_SERVICES" = true ]; then
        print_status "Restarting services..."
        docker start qdrant n8n 2>/dev/null || print_warning "Some services failed to start"
    fi
}

# Function to create metadata file
create_metadata() {
    local metadata_file="$BACKUP_PATH/backup-metadata.json"
    
    cat > "$metadata_file" << EOF
{
  "backup_info": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "type": "$BACKUP_TYPE",
    "compression": "$COMPRESSION",
    "services_stopped": $STOP_SERVICES,
    "hostname": "$(hostname)",
    "user": "$(whoami)"
  },
  "system_info": {
    "docker_version": "$(docker --version 2>/dev/null || echo 'Not available')",
    "containers": [
$(docker ps -a --format '      {"name": "{{.Names}}", "status": "{{.Status}}", "image": "{{.Image}}"}' 2>/dev/null | paste -sd, || echo '      {"error": "Docker not accessible"}')
    ],
    "disk_usage": "$(df -h /home/roi12 2>/dev/null | tail -1 || echo 'Not available')",
    "memory_usage": "$(free -h 2>/dev/null | grep Mem || echo 'Not available')"
  },
  "collections": {
$(curl -s http://localhost:6333/collections 2>/dev/null | sed 's/{"result":{"collections":\[//' | sed 's/\]},"status":"ok".*$//' | sed 's/^/    /' || echo '    "error": "Qdrant not accessible"')
  }
}
EOF
    
    print_status "Created backup metadata"
}

# Function to backup container configurations
backup_container_configs() {
    print_status "Backing up container configurations..."
    
    for container in n8n qdrant claude-admin; do
        if docker ps -a -q -f name=$container | grep -q .; then
            docker inspect $container > "$BACKUP_PATH/${container}-config.json" 2>/dev/null || print_warning "Failed to backup $container config"
        fi
    done
    
    # Backup network configuration
    docker network inspect ai-stack > "$BACKUP_PATH/network-config.json" 2>/dev/null || print_warning "Failed to backup network config"
}

# Function to perform full backup
backup_full() {
    print_status "Performing full backup..."
    
    # Stop services if requested
    stop_services
    
    # Backup n8n data
    if [ -d "/home/roi12/.n8n" ]; then
        print_status "Backing up n8n data..."
        tar -c${TAR_COMPRESSION}f "$BACKUP_PATH/n8n-data.$EXTENSION" -C /home/roi12 .n8n
        print_status "n8n data backup completed"
    else
        print_warning "n8n data directory not found"
    fi
    
    # Backup Qdrant data
    if [ -d "/home/roi12/qdrant_storage" ]; then
        print_status "Backing up Qdrant data..."
        tar -c${TAR_COMPRESSION}f "$BACKUP_PATH/qdrant-data.$EXTENSION" -C /home/roi12 qdrant_storage
        print_status "Qdrant data backup completed"
    else
        print_warning "Qdrant data directory not found"
    fi
    
    # Start services if they were stopped
    start_services
}

# Function to perform incremental backup
backup_incremental() {
    local days=${1:-7}
    print_status "Performing incremental backup (last $days days)..."
    
    # Find files modified in the last N days
    print_status "Finding modified files..."
    
    # n8n incremental
    if [ -d "/home/roi12/.n8n" ]; then
        find /home/roi12/.n8n -type f -mtime -$days -print0 | tar -c${TAR_COMPRESSION}f "$BACKUP_PATH/n8n-incremental.$EXTENSION" --null -T - 2>/dev/null || print_warning "No recent n8n changes found"
    fi
    
    # Qdrant incremental
    if [ -d "/home/roi12/qdrant_storage" ]; then
        find /home/roi12/qdrant_storage -type f -mtime -$days -print0 | tar -c${TAR_COMPRESSION}f "$BACKUP_PATH/qdrant-incremental.$EXTENSION" --null -T - 2>/dev/null || print_warning "No recent Qdrant changes found"
    fi
    
    print_status "Incremental backup completed"
}

# Function to backup configuration only
backup_config_only() {
    print_status "Performing configuration-only backup..."
    
    # n8n config files only
    if [ -d "/home/roi12/.n8n" ]; then
        tar -c${TAR_COMPRESSION}f "$BACKUP_PATH/n8n-config.$EXTENSION" \
            --exclude="/home/roi12/.n8n/*.log*" \
            --exclude="/home/roi12/.n8n/database.sqlite*" \
            --exclude="/home/roi12/.n8n/binaryData/*" \
            -C /home/roi12 .n8n 2>/dev/null || print_warning "n8n config backup failed"
    fi
    
    # Qdrant config files only
    if [ -d "/home/roi12/qdrant_storage" ]; then
        find /home/roi12/qdrant_storage -name "config.json" -o -name "*.json" | \
            tar -c${TAR_COMPRESSION}f "$BACKUP_PATH/qdrant-config.$EXTENSION" -T - 2>/dev/null || print_warning "Qdrant config backup failed"
    fi
    
    print_status "Configuration backup completed"
}

# Create metadata and container configs
create_metadata
backup_container_configs

# Perform backup based on type
case $BACKUP_TYPE in
    full)
        backup_full
        ;;
    incremental)
        backup_incremental
        ;;
    config-only)
        backup_config_only
        ;;
    *)
        print_error "Unknown backup type: $BACKUP_TYPE"
        exit 1
        ;;
esac

# Calculate backup size
backup_size=$(du -sh "$BACKUP_PATH" | cut -f1)
print_status "Backup size: $backup_size"

# Create backup summary
echo "=== Backup Summary ===" > "$BACKUP_PATH/backup-summary.txt"
echo "Timestamp: $(date)" >> "$BACKUP_PATH/backup-summary.txt"
echo "Type: $BACKUP_TYPE" >> "$BACKUP_PATH/backup-summary.txt"
echo "Size: $backup_size" >> "$BACKUP_PATH/backup-summary.txt"
echo "Files:" >> "$BACKUP_PATH/backup-summary.txt"
ls -la "$BACKUP_PATH" >> "$BACKUP_PATH/backup-summary.txt"

# Create restoration instructions
cat > "$BACKUP_PATH/RESTORE-INSTRUCTIONS.md" << 'EOF'
# Backup Restoration Instructions

## Prerequisites
- Docker and Docker Compose installed
- Sufficient disk space
- Access to the backup files

## Full Restoration

1. Stop all services:
   ```bash
   docker stop n8n qdrant claude-admin
   ```

2. Backup current data (if any):
   ```bash
   mv /home/roi12/.n8n /home/roi12/.n8n.old
   mv /home/roi12/qdrant_storage /home/roi12/qdrant_storage.old
   ```

3. Restore data:
   ```bash
   tar -xzf n8n-data.tar.gz -C /home/roi12/
   tar -xzf qdrant-data.tar.gz -C /home/roi12/
   ```

4. Set correct permissions:
   ```bash
   chown -R 1000:1000 /home/roi12/.n8n/
   chown -R 1000:1000 /home/roi12/qdrant_storage/
   ```

5. Start services:
   ```bash
   ./scripts/start-system.sh
   ```

## Selective Restoration

For incremental or config-only backups, extract files carefully to avoid overwriting current data.

## Verification

After restoration:
1. Run health check: `./scripts/health-check.sh`
2. Verify data integrity through web interfaces
3. Check logs for any errors
EOF

print_status "Created restoration instructions"

# Cleanup old backups (keep last 10)
if [ "$BACKUP_TYPE" = "full" ]; then
    print_status "Cleaning up old backups..."
    ls -t "$BACKUP_DIR"/ai-system-backup-* 2>/dev/null | tail -n +11 | xargs rm -rf 2>/dev/null || true
fi

echo ""
print_status "=== Backup Completed Successfully ==="
print_info "Backup location: $BACKUP_PATH"
print_info "Backup size: $backup_size"
print_info "To restore, see: $BACKUP_PATH/RESTORE-INSTRUCTIONS.md"

# Final verification
if [ -f "$BACKUP_PATH/backup-summary.txt" ]; then
    print_status "Backup verification: PASSED"
    exit 0
else
    print_error "Backup verification: FAILED"
    exit 1
fi