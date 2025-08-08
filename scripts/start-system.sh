#!/bin/bash

# AI Automation System Startup Script
# Starts all containers in the correct order

set -e

echo "=== Starting AI Automation System ==="
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

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_error "Docker is not running or not accessible"
    exit 1
fi

print_status "Docker is running"

# Create network if it doesn't exist
if ! docker network inspect ai-stack >/dev/null 2>&1; then
    print_status "Creating ai-stack network..."
    docker network create ai-stack
else
    print_status "Network ai-stack already exists"
fi

# Start Qdrant first (dependency for n8n workflows)
print_status "Starting Qdrant vector database..."
if docker ps -q -f name=qdrant | grep -q .; then
    print_warning "Qdrant container already running"
else
    if docker ps -a -q -f name=qdrant | grep -q .; then
        print_status "Starting existing Qdrant container..."
        docker start qdrant
    else
        print_status "Creating new Qdrant container..."
        docker run -d \
            --name qdrant \
            --network ai-stack \
            -p 6333:6333 \
            -v /home/roi12/qdrant_storage:/qdrant/storage \
            --restart unless-stopped \
            qdrant/qdrant
    fi
fi

# Wait for Qdrant to be healthy
print_status "Waiting for Qdrant to be healthy..."
for i in {1..30}; do
    if curl -sf http://localhost:6333/health >/dev/null 2>&1; then
        print_status "Qdrant is healthy"
        break
    fi
    if [ $i -eq 30 ]; then
        print_error "Qdrant failed to start within 30 seconds"
        exit 1
    fi
    sleep 1
done

# Start n8n workflow engine
print_status "Starting n8n workflow engine..."
if docker ps -q -f name=n8n | grep -q .; then
    print_warning "n8n container already running"
else
    if docker ps -a -q -f name=n8n | grep -q .; then
        print_status "Starting existing n8n container..."
        docker start n8n
    else
        print_status "Creating new n8n container..."
        docker run -d \
            --name n8n \
            --network ai-stack \
            -p 5678:5678 \
            -v /home/roi12/.n8n:/home/node/.n8n \
            --restart unless-stopped \
            n8nio/n8n
    fi
fi

# Wait for n8n to be healthy
print_status "Waiting for n8n to be healthy..."
for i in {1..60}; do
    if curl -sf http://localhost:5678/healthz >/dev/null 2>&1; then
        print_status "n8n is healthy"
        break
    fi
    if [ $i -eq 60 ]; then
        print_error "n8n failed to start within 60 seconds"
        exit 1
    fi
    sleep 1
done

# Start Claude admin container if needed
print_status "Checking Claude admin container..."
if docker ps -q -f name=claude-admin | grep -q .; then
    print_status "Claude admin container already running"
else
    if docker ps -a -q -f name=claude-admin | grep -q .; then
        print_status "Starting existing Claude admin container..."
        docker start claude-admin
    else
        print_status "Claude admin container not found (optional)"
    fi
fi

# Display system status
echo ""
print_status "=== System Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
print_status "=== Service URLs ==="
echo "n8n Web Interface: http://localhost:5678"
echo "Qdrant API: http://localhost:6333"
echo "Qdrant Dashboard: http://localhost:6333/dashboard"

echo ""
print_status "=== Next Steps ==="
echo "1. Access n8n at http://localhost:5678"
echo "2. Complete initial setup if first time"
echo "3. Check system health: ./scripts/health-check.sh"
echo "4. View logs: docker logs n8n"

echo ""
print_status "AI Automation System started successfully!"
echo "Use './scripts/stop-system.sh' to stop all services"