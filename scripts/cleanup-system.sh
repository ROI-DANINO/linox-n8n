#!/bin/bash

# AI Automation System Cleanup Script
# Removes containers, networks, and optionally data

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
REMOVE_DATA=false
REMOVE_IMAGES=false
FORCE=false

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -d, --data           Remove data volumes (DESTRUCTIVE!)"
    echo "  -i, --images         Remove Docker images"
    echo "  -f, --force          Skip confirmation prompts"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                   # Remove containers and network only"
    echo "  $0 -d                # Remove containers, network, and data"
    echo "  $0 -i                # Remove containers, network, and images"
    echo "  $0 -d -i -f          # Complete cleanup without prompts"
    echo ""
    echo "WARNING: Using -d will permanently delete all workflow and vector data!"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--data)
            REMOVE_DATA=true
            shift
            ;;
        -i|--images)
            REMOVE_IMAGES=true
            shift
            ;;
        -f|--force)
            FORCE=true
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

echo "=== AI Automation System Cleanup ==="
echo "Timestamp: $(date)"
echo ""

# Show what will be cleaned up
print_info "Cleanup plan:"
echo "  • Stop and remove containers: n8n, qdrant, claude-admin"
echo "  • Remove network: ai-stack"
if [ "$REMOVE_DATA" = true ]; then
    echo "  • Remove data directories (DESTRUCTIVE!)"
fi
if [ "$REMOVE_IMAGES" = true ]; then
    echo "  • Remove Docker images"
fi
echo ""

# Confirmation prompt
if [ "$FORCE" = false ]; then
    if [ "$REMOVE_DATA" = true ]; then
        print_warning "WARNING: This will permanently delete all your workflows and vector data!"
        echo "This action cannot be undone. Make sure you have backups!"
        echo ""
        read -p "Are you absolutely sure you want to proceed? (type 'DELETE' to confirm): " confirm
        if [ "$confirm" != "DELETE" ]; then
            print_info "Cleanup cancelled by user"
            exit 0
        fi
    else
        read -p "Continue with cleanup? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            print_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
fi

# Function to stop and remove container
cleanup_container() {
    local container_name=$1
    
    if docker ps -q -f name=$container_name | grep -q .; then
        print_status "Stopping $container_name..."
        docker stop $container_name >/dev/null 2>&1 || print_warning "Failed to stop $container_name"
    fi
    
    if docker ps -a -q -f name=$container_name | grep -q .; then
        print_status "Removing $container_name..."
        docker rm $container_name >/dev/null 2>&1 || print_warning "Failed to remove $container_name"
    else
        print_info "$container_name container not found"
    fi
}

print_status "Starting cleanup process..."

# Stop and remove containers
containers=("n8n" "qdrant" "claude-admin")
for container in "${containers[@]}"; do
    cleanup_container $container
done

# Remove network
if docker network inspect ai-stack >/dev/null 2>&1; then
    print_status "Removing ai-stack network..."
    docker network rm ai-stack >/dev/null 2>&1 || print_warning "Failed to remove ai-stack network"
else
    print_info "ai-stack network not found"
fi

# Remove data directories if requested
if [ "$REMOVE_DATA" = true ]; then
    print_warning "Removing data directories..."
    
    if [ -d "/home/roi12/.n8n" ]; then
        print_status "Removing n8n data..."
        rm -rf /home/roi12/.n8n
    else
        print_info "n8n data directory not found"
    fi
    
    if [ -d "/home/roi12/qdrant_storage" ]; then
        print_status "Removing Qdrant data..."
        rm -rf /home/roi12/qdrant_storage
    else
        print_info "Qdrant data directory not found"
    fi
    
    print_warning "All data has been permanently deleted!"
fi

# Remove Docker images if requested
if [ "$REMOVE_IMAGES" = true ]; then
    print_status "Removing Docker images..."
    
    images=("n8nio/n8n" "qdrant/qdrant" "node:20-bookworm-slim")
    for image in "${images[@]}"; do
        if docker images -q $image | grep -q .; then
            print_status "Removing image: $image"
            docker rmi $image >/dev/null 2>&1 || print_warning "Failed to remove $image"
        else
            print_info "Image not found: $image"
        fi
    done
fi

# Clean up unused Docker resources
print_status "Cleaning up unused Docker resources..."
docker system prune -f >/dev/null 2>&1 || print_warning "Docker system prune failed"

# Final status check
echo ""
print_status "=== Cleanup Summary ==="

# Check remaining containers
remaining_containers=$(docker ps -a --format "{{.Names}}" | grep -E "(n8n|qdrant|claude-admin)" || echo "")
if [ -z "$remaining_containers" ]; then
    print_status "All AI system containers removed"
else
    print_warning "Some containers still exist: $remaining_containers"
fi

# Check network
if docker network inspect ai-stack >/dev/null 2>&1; then
    print_warning "ai-stack network still exists"
else
    print_status "ai-stack network removed"
fi

# Check data directories
if [ "$REMOVE_DATA" = true ]; then
    if [ -d "/home/roi12/.n8n" ] || [ -d "/home/roi12/qdrant_storage" ]; then
        print_warning "Some data directories still exist"
    else
        print_status "All data directories removed"
    fi
fi

# Check images
if [ "$REMOVE_IMAGES" = true ]; then
    remaining_images=$(docker images --format "{{.Repository}}" | grep -E "(n8n|qdrant)" || echo "")
    if [ -z "$remaining_images" ]; then
        print_status "All AI system images removed"
    else
        print_warning "Some images still exist: $remaining_images"
    fi
fi

echo ""
print_status "Cleanup completed successfully!"

if [ "$REMOVE_DATA" = true ]; then
    print_warning "Remember: All data has been permanently deleted!"
    print_info "To restore from backup, see backup restoration instructions"
else
    print_info "Data directories preserved"
    print_info "To start fresh, use: ./scripts/start-system.sh"
fi

print_info "To recreate the system, use: ./scripts/start-system.sh"