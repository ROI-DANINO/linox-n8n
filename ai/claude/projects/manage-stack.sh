#!/bin/bash

# Docker Stack Management Script
# Manages n8n and qdrant containers

CONTAINERS=("n8n" "qdrant")
LOG_FILE="/workspace/stack.log"
INVENTORY_FILE="/workspace/docker_inventory.txt"
BACKUP_DIR="/workspace/backups"
NETWORK_NAME="ai-stack"

# Container configurations
declare -A CONTAINER_CONFIG
CONTAINER_CONFIG[qdrant_image]="qdrant/qdrant"
CONTAINER_CONFIG[qdrant_ports]="-p 6333:6333"
CONTAINER_CONFIG[qdrant_volumes]="-v /home/roi12/qdrant_storage:/qdrant/storage"
CONTAINER_CONFIG[qdrant_healthcheck]="sh -c 'grep -q :18BD /proc/net/tcp || exit 1'"
CONTAINER_CONFIG[qdrant_healthcheck_interval]="10s"
CONTAINER_CONFIG[qdrant_healthcheck_timeout]="3s"
CONTAINER_CONFIG[qdrant_healthcheck_retries]="3"
CONTAINER_CONFIG[qdrant_data_path]="/qdrant/storage"
CONTAINER_CONFIG[qdrant_host_path]="/home/roi12/qdrant_storage"

CONTAINER_CONFIG[n8n_image]="n8nio/n8n"
CONTAINER_CONFIG[n8n_ports]="-p 5678:5678"
CONTAINER_CONFIG[n8n_volumes]="-v /home/roi12/.n8n:/home/node/.n8n"
CONTAINER_CONFIG[n8n_healthcheck]="sh -c 'nc -z localhost 5678 || exit 1'"
CONTAINER_CONFIG[n8n_healthcheck_interval]="10s"
CONTAINER_CONFIG[n8n_healthcheck_timeout]="3s"
CONTAINER_CONFIG[n8n_healthcheck_retries]="6"
CONTAINER_CONFIG[n8n_data_path]="/home/node/.n8n"
CONTAINER_CONFIG[n8n_host_path]="/home/roi12/.n8n"

# Parse command line flags
RECREATE=false
HARD=false
if [[ "$2" == "--recreate" ]]; then
    RECREATE=true
elif [[ "$2" == "--hard" ]]; then
    HARD=true
fi

show_usage() {
    echo "Usage: ./manage-stack.sh {start|stop|restart|status|preflight|backup|up [--recreate]|down [--hard]}"
}

log_action() {
    local command="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $command executed" >> "$LOG_FILE"
}

start_containers() {
    echo "Starting containers..."
    for container in "${CONTAINERS[@]}"; do
        echo "Starting $container..."
        if docker start "$container" > /dev/null 2>&1; then
            echo "$container started successfully"
        else
            echo "Failed to start $container"
        fi
    done
}

stop_containers() {
    echo "Stopping containers..."
    for container in "${CONTAINERS[@]}"; do
        echo "Stopping $container..."
        if docker stop "$container" > /dev/null 2>&1; then
            echo "$container stopped successfully"
        else
            echo "Failed to stop $container"
        fi
    done
}

restart_containers() {
    echo "Restarting containers..."
    stop_containers
    echo "Waiting 2 seconds..."
    sleep 2
    start_containers
}

show_status() {
    echo "Docker Container Status"
    echo "======================="
    echo "Generated on: $(date '+%Y-%m-%d')"
    echo ""
    
    # Generate inventory file
    {
        echo "Docker Container Inventory"
        echo "=========================="
        echo "Generated on: $(date '+%Y-%m-%d')"
        echo ""
        
        local running_count=0
        local total_count=0
        
        for container in "${CONTAINERS[@]}"; do
            total_count=$((total_count + 1))
            
            # Get container status
            local status=$(docker ps -a --filter "name=^${container}$" --format "{{.Status}}")
            local networks=$(docker ps -a --filter "name=^${container}$" --format "{{.Networks}}")
            
            echo "Container Name: $container"
            echo "Status: $status"
            echo "Networks: $networks"
            echo "Mounted Volumes:"
            
            # Get mount information
            docker inspect "$container" --format='{{range .Mounts}}  - {{.Source}} -> {{.Destination}} ({{.Type}}){{printf "\n"}}{{end}}' 2>/dev/null || echo "  - No mounts found"
            echo ""
            
            # Count running containers
            if docker ps --filter "name=^${container}$" --format "{{.Names}}" | grep -q "^${container}$"; then
                running_count=$((running_count + 1))
            fi
        done
        
        echo "Summary:"
        echo "- Total containers: $total_count"
        echo "- Running: $running_count"
        echo "- Stopped: $((total_count - running_count))"
    } | tee "$INVENTORY_FILE"
}

preflight_checks() {
    echo "Preflight Checks"
    echo "================"
    local all_ok=true
    
    # Check Docker socket accessibility
    echo -n "Docker socket accessible: "
    if docker version > /dev/null 2>&1; then
        echo "OK"
        log_action "preflight: docker socket accessible"
    else
        echo "FAIL"
        log_action "preflight: docker socket NOT accessible"
        all_ok=false
    fi
    
    # Check/create workspace directory (should already exist)
    echo -n "/workspace directory: "
    if [[ -d "/workspace" ]]; then
        echo "OK"
        log_action "preflight: /workspace directory exists"
    else
        echo "FAIL"
        log_action "preflight: /workspace directory NOT found"
        all_ok=false
    fi
    
    # Check/create backups directory
    echo -n "/workspace/backups directory: "
    if [[ -d "$BACKUP_DIR" ]]; then
        echo "OK"
        log_action "preflight: $BACKUP_DIR directory exists"
    else
        if mkdir -p "$BACKUP_DIR" 2>/dev/null; then
            echo "CREATED"
            log_action "preflight: created $BACKUP_DIR directory"
        else
            echo "FAIL"
            log_action "preflight: failed to create $BACKUP_DIR directory"
            all_ok=false
        fi
    fi
    
    # Check host bind paths using temporary containers
    for container in "${CONTAINERS[@]}"; do
        local host_path="${CONTAINER_CONFIG[${container}_host_path]}"
        echo -n "Host path $host_path: "
        
        # Use a temporary container to check/create the host path
        if docker run --rm -v "$host_path:/mnt_check" alpine sh -c 'ls -d /mnt_check > /dev/null 2>&1' 2>/dev/null; then
            echo "OK"
            log_action "preflight: host path $host_path exists"
        else
            # Try to create it
            if docker run --rm -v "$(dirname "$host_path"):/mnt_parent" alpine sh -c "mkdir -p /mnt_parent/$(basename "$host_path")" 2>/dev/null; then
                echo "CREATED"
                log_action "preflight: created host path $host_path"
            else
                echo "FAIL"
                log_action "preflight: failed to verify/create host path $host_path"
                all_ok=false
            fi
        fi
    done
    
    # Check/create Docker network
    echo -n "Docker network $NETWORK_NAME: "
    if docker network ls --format "{{.Name}}" | grep -q "^${NETWORK_NAME}$"; then
        echo "OK"
        log_action "preflight: network $NETWORK_NAME exists"
    else
        if docker network create "$NETWORK_NAME" > /dev/null 2>&1; then
            echo "CREATED"
            log_action "preflight: created network $NETWORK_NAME"
        else
            echo "FAIL"
            log_action "preflight: failed to create network $NETWORK_NAME"
            all_ok=false
        fi
    fi
    
    echo ""
    if $all_ok; then
        echo "All preflight checks passed."
        log_action "preflight: all checks passed"
    else
        echo "Some preflight checks failed. See details above."
        log_action "preflight: some checks failed"
        return 1
    fi
}

backup_containers() {
    echo "Backing up containers..."
    echo "========================"
    local timestamp=$(date '+%Y%m%d-%H%M%S')
    local backup_created=false
    
    for container in "${CONTAINERS[@]}"; do
        echo -n "Checking $container: "
        
        # Check if container is running
        if docker ps --filter "name=^${container}$" --format "{{.Names}}" | grep -q "^${container}$"; then
            echo "running, creating backup..."
            
            local data_path="${CONTAINER_CONFIG[${container}_data_path]}"
            local backup_file="${BACKUP_DIR}/${container}-${timestamp}.tar.gz"
            
            # Create backup using docker exec and tar
            if docker exec "$container" tar -czf - -C "$(dirname "$data_path")" "$(basename "$data_path")" > "$backup_file" 2>/dev/null; then
                local size=$(du -h "$backup_file" | cut -f1)
                echo "  Created: $backup_file ($size)"
                log_action "backup: created $backup_file for $container"
                backup_created=true
            else
                echo "  Failed to create backup for $container"
                log_action "backup: failed to create backup for $container"
                rm -f "$backup_file" 2>/dev/null
            fi
        else
            echo "not running, skipping backup"
            log_action "backup: skipped $container (not running)"
        fi
    done
    
    echo ""
    if $backup_created; then
        echo "Backup completed. Archives saved to $BACKUP_DIR"
    else
        echo "No backups created (no running containers or backup failures)"
    fi
}

up_containers() {
    echo "Bringing up containers..."
    echo "========================="
    local actions_summary=()
    
    for container in "${CONTAINERS[@]}"; do
        echo "Processing $container..."
        
        local image="${CONTAINER_CONFIG[${container}_image]}"
        local ports="${CONTAINER_CONFIG[${container}_ports]}"
        local volumes="${CONTAINER_CONFIG[${container}_volumes]}"
        local healthcheck_cmd="${CONTAINER_CONFIG[${container}_healthcheck]}"
        local healthcheck_interval="${CONTAINER_CONFIG[${container}_healthcheck_interval]}"
        local healthcheck_timeout="${CONTAINER_CONFIG[${container}_healthcheck_timeout]}"
        local healthcheck_retries="${CONTAINER_CONFIG[${container}_healthcheck_retries]}"
        
        # Check if container exists
        if docker ps -a --filter "name=^${container}$" --format "{{.Names}}" | grep -q "^${container}$"; then
            # Container exists, check its status
            local status=$(docker ps -a --filter "name=^${container}$" --format "{{.Status}}")
            
            if docker ps --filter "name=^${container}$" --format "{{.Names}}" | grep -q "^${container}$"; then
                # Container is running, check configuration
                echo "  Container running, checking configuration..."
                
                # Check restart policy
                local current_restart=$(docker inspect "$container" --format '{{.HostConfig.RestartPolicy.Name}}')
                local has_healthcheck=$(docker inspect "$container" --format '{{.Config.Healthcheck}}')
                
                if [[ "$current_restart" != "unless-stopped" ]] || [[ "$has_healthcheck" == "<nil>" ]]; then
                    if $RECREATE; then
                        echo "  Recreating container with correct configuration..."
                        docker stop "$container" > /dev/null 2>&1
                        docker rm "$container" > /dev/null 2>&1
                        
                        # Create new container
                        docker run -d \
                            --name "$container" \
                            --network "$NETWORK_NAME" \
                            --restart unless-stopped \
                            --health-cmd="$healthcheck_cmd" \
                            --health-interval="$healthcheck_interval" \
                            --health-timeout="$healthcheck_timeout" \
                            --health-retries="$healthcheck_retries" \
                            $ports \
                            $volumes \
                            "$image" > /dev/null 2>&1
                        
                        actions_summary+=("$container: recreated with correct configuration")
                        log_action "up: recreated $container with correct configuration"
                    else
                        echo "  Warning: missing restart policy or healthcheck (use --recreate to fix)"
                        actions_summary+=("$container: running but missing restart policy/healthcheck")
                        log_action "up: $container running but configuration incomplete"
                    fi
                else
                    echo "  Container already running with correct configuration"
                    actions_summary+=("$container: already running correctly")
                    log_action "up: $container already running correctly"
                fi
            else
                # Container exists but is stopped
                echo "  Starting stopped container..."
                if docker start "$container" > /dev/null 2>&1; then
                    actions_summary+=("$container: started")
                    log_action "up: started existing $container"
                else
                    actions_summary+=("$container: failed to start")
                    log_action "up: failed to start $container"
                fi
            fi
        else
            # Container doesn't exist, create it
            echo "  Creating new container..."
            
            if docker run -d \
                --name "$container" \
                --network "$NETWORK_NAME" \
                --restart unless-stopped \
                --health-cmd="$healthcheck_cmd" \
                --health-interval="$healthcheck_interval" \
                --health-timeout="$healthcheck_timeout" \
                --health-retries="$healthcheck_retries" \
                $ports \
                $volumes \
                "$image" > /dev/null 2>&1; then
                
                actions_summary+=("$container: created and started")
                log_action "up: created and started $container"
            else
                actions_summary+=("$container: failed to create")
                log_action "up: failed to create $container"
            fi
        fi
    done
    
    echo ""
    echo "Summary:"
    for summary in "${actions_summary[@]}"; do
        echo "  $summary"
    done
}

down_containers() {
    echo "Bringing down containers..."
    echo "==========================="
    
    for container in "${CONTAINERS[@]}"; do
        echo -n "Processing $container: "
        
        # Check if container exists and is running
        if docker ps --filter "name=^${container}$" --format "{{.Names}}" | grep -q "^${container}$"; then
            # Container is running, stop it
            if docker stop "$container" > /dev/null 2>&1; then
                echo -n "stopped"
                log_action "down: stopped $container"
                
                if $HARD; then
                    # Also remove the container
                    if docker rm "$container" > /dev/null 2>&1; then
                        echo ", removed"
                        log_action "down: removed $container"
                    else
                        echo ", failed to remove"
                        log_action "down: failed to remove $container"
                    fi
                else
                    echo ""
                fi
            else
                echo "failed to stop"
                log_action "down: failed to stop $container"
            fi
        elif docker ps -a --filter "name=^${container}$" --format "{{.Names}}" | grep -q "^${container}$"; then
            # Container exists but is not running
            if $HARD; then
                if docker rm "$container" > /dev/null 2>&1; then
                    echo "removed (was already stopped)"
                    log_action "down: removed $container (was stopped)"
                else
                    echo "failed to remove (was already stopped)"
                    log_action "down: failed to remove $container (was stopped)"
                fi
            else
                echo "already stopped"
                log_action "down: $container already stopped"
            fi
        else
            echo "does not exist"
            log_action "down: $container does not exist"
        fi
    done
    
    echo ""
    if $HARD; then
        echo "Containers stopped and removed (data preserved on host)"
    else
        echo "Containers stopped (use --hard to also remove containers)"
    fi
}

# Main script logic
case "$1" in
    start)
        start_containers
        log_action "start"
        ;;
    stop)
        stop_containers
        log_action "stop"
        ;;
    restart)
        restart_containers
        log_action "restart"
        ;;
    status)
        show_status
        log_action "status"
        ;;
    preflight)
        preflight_checks
        log_action "preflight"
        ;;
    backup)
        backup_containers
        log_action "backup"
        ;;
    up)
        up_containers
        log_action "up"
        ;;
    down)
        down_containers
        log_action "down"
        ;;
    *)
        show_usage
        exit 1
        ;;
esac

exit 0