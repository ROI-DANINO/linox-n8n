#!/bin/bash

# AI Automation System Health Check Script
# Comprehensive health monitoring for all services

set -e

echo "=== AI Automation System Health Check ==="
echo "Timestamp: $(date)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Health check summary
total_checks=0
passed_checks=0
failed_checks=0

# Function to run a check
run_check() {
    local check_name="$1"
    local check_command="$2"
    
    total_checks=$((total_checks + 1))
    
    if eval "$check_command" >/dev/null 2>&1; then
        print_status "$check_name"
        passed_checks=$((passed_checks + 1))
        return 0
    else
        print_error "$check_name"
        failed_checks=$((failed_checks + 1))
        return 1
    fi
}

echo ""
echo "=== Docker Environment ==="

# Check Docker daemon
run_check "Docker daemon accessible" "docker info"

# Check Docker version
docker_version=$(docker --version 2>/dev/null || echo "Unknown")
print_info "Docker version: $docker_version"

echo ""
echo "=== Network Status ==="

# Check ai-stack network
run_check "ai-stack network exists" "docker network inspect ai-stack"

# Check network connectivity
network_subnet=$(docker network inspect ai-stack --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "N/A")
print_info "Network subnet: $network_subnet"

echo ""
echo "=== Container Status ==="

# Check container existence and status
containers=("n8n" "qdrant" "claude-admin")
running_containers=0

for container in "${containers[@]}"; do
    if docker ps -q -f name=$container | grep -q .; then
        run_check "$container container running" "true"
        running_containers=$((running_containers + 1))
        
        # Check container health if available
        health_status=$(docker inspect $container --format '{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")
        if [ "$health_status" = "healthy" ]; then
            print_status "$container health check: healthy"
        elif [ "$health_status" = "unhealthy" ]; then
            print_error "$container health check: unhealthy"
        else
            print_info "$container health check: not configured"
        fi
    else
        run_check "$container container running" "false"
    fi
done

print_info "Running containers: $running_containers/3"

echo ""
echo "=== Service Health ==="

# Check n8n service
if run_check "n8n HTTP API accessible" "curl -sf http://localhost:5678/healthz"; then
    # Get n8n version if available
    n8n_version=$(docker exec n8n n8n --version 2>/dev/null | head -1 || echo "Unknown")
    print_info "n8n version: $n8n_version"
fi

# Check Qdrant service
if run_check "Qdrant HTTP API accessible" "curl -sf http://localhost:6333/health"; then
    # Get Qdrant info
    qdrant_version=$(curl -sf http://localhost:6333/ 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "Unknown")
    print_info "Qdrant version: $qdrant_version"
    
    # Check collections
    collections=$(curl -sf http://localhost:6333/collections 2>/dev/null | grep -o '"name":"[^"]*"' | wc -l || echo "0")
    print_info "Qdrant collections: $collections"
fi

echo ""
echo "=== Resource Usage ==="

# Check system resources
if command -v free >/dev/null 2>&1; then
    memory_usage=$(free -m | awk 'NR==2{printf "%.1f%%", $3*100/$2}')
    print_info "System memory usage: $memory_usage"
fi

if command -v df >/dev/null 2>&1; then
    disk_usage=$(df -h /home/roi12 | awk 'NR==2{print $5}')
    print_info "Disk usage (/home/roi12): $disk_usage"
fi

# Container resource usage
echo ""
print_info "Container resource usage:"
docker stats --no-stream --format "  {{.Name}}: {{.CPUPerc}} CPU, {{.MemUsage}}" 2>/dev/null || print_warning "Could not get container stats"

echo ""
echo "=== Port Status ==="

# Check port availability
ports=("5678" "6333")
for port in "${ports[@]}"; do
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        run_check "Port $port is listening" "true"
    else
        run_check "Port $port is listening" "false"
    fi
done

echo ""
echo "=== Data Volumes ==="

# Check volume mounts and sizes
volumes=(
    "/home/roi12/.n8n:n8n data"
    "/home/roi12/qdrant_storage:Qdrant data"
)

for volume_info in "${volumes[@]}"; do
    IFS=':' read -r path description <<< "$volume_info"
    if [ -d "$path" ]; then
        run_check "$description directory exists" "true"
        if command -v du >/dev/null 2>&1; then
            size=$(du -sh "$path" 2>/dev/null | cut -f1 || echo "Unknown")
            print_info "$description size: $size"
        fi
    else
        run_check "$description directory exists" "false"
    fi
done

echo ""
echo "=== Recent Errors ==="

# Check for recent errors in logs
error_count=0

if docker ps -q -f name=n8n | grep -q .; then
    n8n_errors=$(docker logs n8n --since 1h 2>&1 | grep -i error | wc -l || echo "0")
    if [ "$n8n_errors" -gt 0 ]; then
        print_warning "n8n has $n8n_errors error(s) in last hour"
        error_count=$((error_count + n8n_errors))
    else
        print_status "No recent errors in n8n logs"
    fi
fi

if docker ps -q -f name=qdrant | grep -q .; then
    qdrant_errors=$(docker logs qdrant --since 1h 2>&1 | grep -i error | wc -l || echo "0")
    if [ "$qdrant_errors" -gt 0 ]; then
        print_warning "Qdrant has $qdrant_errors error(s) in last hour"
        error_count=$((error_count + qdrant_errors))
    else
        print_status "No recent errors in Qdrant logs"
    fi
fi

echo ""
echo "=== Health Summary ==="

health_percentage=$(( passed_checks * 100 / total_checks ))

print_info "Total checks: $total_checks"
print_info "Passed: $passed_checks"
print_info "Failed: $failed_checks"
print_info "Success rate: ${health_percentage}%"

if [ $health_percentage -ge 90 ]; then
    print_status "System health: EXCELLENT"
    exit_code=0
elif [ $health_percentage -ge 75 ]; then
    print_warning "System health: GOOD (some issues detected)"
    exit_code=0
elif [ $health_percentage -ge 50 ]; then
    print_warning "System health: DEGRADED (multiple issues)"
    exit_code=1
else
    print_error "System health: CRITICAL (major issues)"
    exit_code=2
fi

echo ""
echo "=== Recommendations ==="

if [ $failed_checks -gt 0 ]; then
    echo "Some checks failed. Consider:"
    echo "• Check container logs: docker logs <container-name>"
    echo "• Restart services: ./scripts/restart-system.sh"
    echo "• Review troubleshooting guide: TROUBLESHOOTING.md"
fi

if [ $error_count -gt 5 ]; then
    echo "High error count detected. Consider:"
    echo "• Reviewing application logs"
    echo "• Checking system resources"
    echo "• Restarting affected services"
fi

echo ""
print_info "Health check completed at $(date)"

exit $exit_code