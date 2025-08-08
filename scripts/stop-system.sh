#!/bin/bash

# AI Automation System Shutdown Script
# Gracefully stops all containers

set -e

echo "=== Stopping AI Automation System ==="
echo "Timestamp: $(date)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to gracefully stop a container
stop_container() {
    local container_name=$1
    local timeout=${2:-30}
    
    if docker ps -q -f name=$container_name | grep -q .; then
        print_status "Stopping $container_name (timeout: ${timeout}s)..."
        if timeout $timeout docker stop $container_name >/dev/null 2>&1; then
            print_status "$container_name stopped successfully"
        else
            print_warning "$container_name did not stop gracefully, forcing..."
            docker kill $container_name >/dev/null 2>&1 || true
        fi
    else
        print_warning "$container_name is not running"
    fi
}

# Stop containers in reverse dependency order
print_status "Stopping containers..."

# Stop n8n first (depends on Qdrant)
stop_container "n8n" 60

# Stop Qdrant
stop_container "qdrant" 30

# Stop admin container
stop_container "claude-admin" 10

# Display final status
echo ""
print_status "=== Final Container Status ==="
containers=$(docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep -E "(n8n|qdrant|claude-admin)" || echo "No AI system containers found")
echo "$containers"

echo ""
print_status "AI Automation System stopped successfully!"
echo "Use './scripts/start-system.sh' to restart all services"
echo "Use './scripts/cleanup-system.sh' to remove containers completely"