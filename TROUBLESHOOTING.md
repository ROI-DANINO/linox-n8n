# Troubleshooting Guide

## Quick Diagnostic Commands

```bash
# System health overview
./scripts/health-check.sh

# Check all containers
docker ps -a

# Check service connectivity
curl -s http://localhost:5678/healthz  # n8n
curl -s http://localhost:6333/health   # Qdrant

# Check resource usage
docker stats --no-stream

# Check logs for errors
docker logs n8n --tail 50
docker logs qdrant --tail 50
```

## Common Issues and Solutions

### 1. Services Won't Start

#### Problem: Containers fail to start
**Symptoms:**
- Docker containers show "Exited" status
- Services not accessible on expected ports
- Error messages during startup

**Diagnostic Steps:**
```bash
# Check container status
docker ps -a

# Check startup logs
docker logs n8n
docker logs qdrant

# Check port conflicts
ss -tlnp | grep -E ':(5678|6333)'

# Check Docker daemon
docker info
```

**Common Causes & Solutions:**

##### Port Already in Use
```bash
# Find process using the port
lsof -i :5678
lsof -i :6333

# Kill conflicting process (if safe)
sudo kill -9 <PID>

# Or restart with different ports
docker run -p 5679:5678 n8nio/n8n
```

##### Insufficient Resources
```bash
# Check system resources
free -h
df -h

# Clean up Docker resources
docker system prune -f
docker volume prune -f
```

##### Network Issues
```bash
# Recreate network
docker network rm ai-stack
docker network create ai-stack

# Restart Docker daemon
sudo systemctl restart docker
```

##### Volume Permission Issues
```bash
# Fix n8n permissions
sudo chown -R 1000:1000 /home/roi12/.n8n/

# Fix Qdrant permissions  
sudo chown -R roi12:roi12 /home/roi12/qdrant_storage/
```

### 2. Service Connectivity Issues

#### Problem: Services running but not accessible
**Symptoms:**
- Containers show "healthy" status
- Cannot access web interfaces
- API calls timeout or fail

**Diagnostic Steps:**
```bash
# Check if ports are listening
ss -tlnp | grep -E ':(5678|6333)'

# Test local connectivity
curl -v http://localhost:5678/healthz
curl -v http://localhost:6333/health

# Check container network
docker network inspect ai-stack

# Test inter-container communication
docker exec n8n ping qdrant
```

**Solutions:**

##### Network Configuration
```bash
# Verify containers are on correct network
docker inspect n8n | grep NetworkMode
docker inspect qdrant | grep NetworkMode

# Reconnect to network if needed
docker network connect ai-stack n8n
docker network connect ai-stack qdrant
```

##### Firewall Issues
```bash
# Check if firewall is blocking
sudo ufw status

# Allow ports if needed
sudo ufw allow 5678
sudo ufw allow 6333
```

##### Container Internal Issues
```bash
# Check if service is running inside container
docker exec n8n ps aux
docker exec qdrant ps aux

# Check service configuration
docker exec n8n cat /etc/hosts
docker exec qdrant cat /etc/hosts
```

### 3. Performance Issues

#### Problem: Slow response times or high resource usage
**Symptoms:**
- Web interface loads slowly
- API calls take longer than usual
- High CPU or memory usage

**Diagnostic Steps:**
```bash
# Check resource usage
docker stats --no-stream

# Check system load
top
htop  # if available

# Check disk I/O
iotop  # if available

# Check application-specific metrics
curl -s http://localhost:6333/metrics
```

**Solutions:**

##### Resource Optimization
```bash
# Set memory limits
docker update --memory="512m" n8n
docker update --memory="256m" qdrant

# Set CPU limits
docker update --cpus="1.0" n8n
docker update --cpus="0.5" qdrant
```

##### Database Optimization
```bash
# Optimize n8n SQLite database
docker exec n8n sqlite3 /home/node/.n8n/database.sqlite "VACUUM;"

# Optimize Qdrant indices
curl -X POST http://localhost:6333/collections/mem_notes_main/index
```

##### Storage Cleanup
```bash
# Clean up old logs
find /home/roi12/.n8n -name "*.log*" -mtime +7 -delete

# Clean up Docker
docker system prune -f
docker logs n8n 2>/dev/null | tail -1000 > /tmp/n8n.log
```

### 4. Data Issues

#### Problem: Missing data or corruption
**Symptoms:**
- Workflows disappeared
- Vector collections empty
- Database errors
- Configuration reset

**Diagnostic Steps:**
```bash
# Check data directories
ls -la /home/roi12/.n8n/
ls -la /home/roi12/qdrant_storage/

# Check database integrity
docker exec n8n sqlite3 /home/node/.n8n/database.sqlite "PRAGMA integrity_check;"

# Check Qdrant collections
curl -s http://localhost:6333/collections
curl -s http://localhost:6333/collections/mem_notes_main
```

**Solutions:**

##### Data Recovery
```bash
# Stop services
docker stop n8n qdrant

# Restore from backup
tar -xzf /home/roi12/backups/latest/n8n-data.tar.gz -C /home/roi12/
tar -xzf /home/roi12/backups/latest/qdrant-data.tar.gz -C /home/roi12/

# Fix permissions
chown -R 1000:1000 /home/roi12/.n8n/
chown -R roi12:roi12 /home/roi12/qdrant_storage/

# Start services
docker start qdrant n8n
```

##### Database Repair
```bash
# SQLite database repair
docker exec n8n sqlite3 /home/node/.n8n/database.sqlite ".recover /tmp/recovered.db"

# Qdrant collection recovery
curl -X POST http://localhost:6333/collections/mem_notes_main/snapshots/recover
```

### 5. Authentication Issues

#### Problem: Cannot access services with credentials
**Symptoms:**
- Login fails with correct credentials
- API returns authentication errors
- Session expires immediately

**Diagnostic Steps:**
```bash
# Check n8n authentication configuration
docker exec n8n printenv | grep N8N_BASIC_AUTH

# Test authentication
curl -u admin:password http://localhost:5678/api/v1/workflows

# Check logs for auth failures
docker logs n8n | grep -i auth
```

**Solutions:**

##### Reset Authentication
```bash
# Disable authentication temporarily
docker run -e N8N_BASIC_AUTH_ACTIVE=false n8nio/n8n

# Reset credentials
docker run -e N8N_BASIC_AUTH_USER=newuser \
           -e N8N_BASIC_AUTH_PASSWORD=newpass \
           n8nio/n8n
```

### 6. Network Communication Issues

#### Problem: Containers cannot communicate with each other
**Symptoms:**
- n8n workflows fail when accessing Qdrant
- Connection refused errors
- DNS resolution failures

**Diagnostic Steps:**
```bash
# Test inter-container connectivity
docker exec n8n ping qdrant
docker exec n8n nslookup qdrant

# Check network configuration
docker network inspect ai-stack

# Test service endpoints
docker exec n8n curl http://qdrant:6333/health
```

**Solutions:**

##### Network Troubleshooting
```bash
# Recreate containers with network
docker stop n8n qdrant
docker rm n8n qdrant

# Recreate network
docker network rm ai-stack
docker network create ai-stack

# Start containers with network
./scripts/start-system.sh
```

### 7. Update and Migration Issues

#### Problem: Issues after updating container images
**Symptoms:**
- Services won't start after update
- Configuration incompatibilities
- Data format changes

**Diagnostic Steps:**
```bash
# Check image versions
docker images | grep -E "(n8n|qdrant)"

# Check for breaking changes in logs
docker logs n8n | grep -i "migration\|upgrade\|version"
docker logs qdrant | grep -i "migration\|upgrade\|version"
```

**Solutions:**

##### Rollback Strategy
```bash
# Stop current containers
docker stop n8n qdrant

# Use previous image version
docker run --name n8n-old n8nio/n8n:previous-version

# Or restore from backup
./scripts/backup-system.sh -t full
```

## Error Code Reference

### n8n Error Codes

| Error | Description | Solution |
|-------|-------------|----------|
| 404 | Workflow not found | Check workflow exists and permissions |
| 401 | Authentication failed | Verify credentials, check auth config |
| 500 | Internal server error | Check logs, restart service |
| 503 | Service unavailable | Check if n8n is running and healthy |

### Qdrant Error Codes

| Error | Description | Solution |
|-------|-------------|----------|
| 404 | Collection not found | Create collection or check name |
| 400 | Bad request | Verify API payload format |
| 422 | Invalid vector dimensions | Check vector size configuration |
| 500 | Internal error | Check logs, verify disk space |

### Docker Error Codes

| Error | Description | Solution |
|-------|-------------|----------|
| 125 | Docker daemon error | Restart Docker daemon |
| 126 | Container command not executable | Check image and command |
| 127 | Container command not found | Verify image contains required binary |
| 1 | General errors | Check container logs |

## Advanced Troubleshooting

### Container Deep Dive
```bash
# Enter container for debugging
docker exec -it n8n /bin/sh
docker exec -it qdrant /bin/sh

# Check container configuration
docker inspect n8n
docker inspect qdrant

# Check container resource limits
docker stats --no-stream n8n qdrant

# Check container processes
docker exec n8n ps aux
docker exec qdrant ps aux
```

### Network Analysis
```bash
# Network packet capture
docker exec n8n tcpdump -i any -w /tmp/n8n-traffic.pcap

# Network connectivity matrix
for container in n8n qdrant; do
  echo "=== $container ==="
  docker exec $container ping -c 1 n8n 2>/dev/null && echo "✓ n8n" || echo "✗ n8n"
  docker exec $container ping -c 1 qdrant 2>/dev/null && echo "✓ qdrant" || echo "✗ qdrant"
done
```

### Performance Analysis
```bash
# Resource monitoring over time
watch -n 5 'docker stats --no-stream'

# Process monitoring inside containers
docker exec n8n top -b -n1
docker exec qdrant top -b -n1

# Disk usage analysis
docker exec n8n du -sh /home/node/.n8n/*
docker exec qdrant du -sh /qdrant/storage/*
```

## Recovery Procedures

### Complete System Recovery
```bash
# 1. Stop all services
./scripts/stop-system.sh

# 2. Backup current state (if possible)
./scripts/backup-system.sh -t config-only

# 3. Clean up system
./scripts/cleanup-system.sh -f

# 4. Restore from known good backup
tar -xzf /home/roi12/backups/good-state/n8n-data.tar.gz -C /home/roi12/
tar -xzf /home/roi12/backups/good-state/qdrant-data.tar.gz -C /home/roi12/

# 5. Fix permissions
sudo chown -R 1000:1000 /home/roi12/.n8n/
sudo chown -R roi12:roi12 /home/roi12/qdrant_storage/

# 6. Start system
./scripts/start-system.sh

# 7. Verify recovery
./scripts/health-check.sh
```

### Emergency Access
```bash
# Access n8n database directly
sqlite3 /home/roi12/.n8n/database.sqlite

# Access Qdrant data directory
find /home/roi12/qdrant_storage -name "*.json" -exec cat {} \;

# Manual container startup with debugging
docker run -it --rm --entrypoint /bin/sh n8nio/n8n
docker run -it --rm --entrypoint /bin/sh qdrant/qdrant
```

## Prevention Strategies

### Monitoring Setup
```bash
# Create monitoring cron job
crontab -e
# Add: */5 * * * * /home/roi12/scripts/health-check.sh >> /home/roi12/health-monitoring.log 2>&1
```

### Regular Maintenance
```bash
# Weekly maintenance script
#!/bin/bash
echo "=== Weekly Maintenance $(date) ===" >> /home/roi12/maintenance.log

# Health check
./scripts/health-check.sh >> /home/roi12/maintenance.log 2>&1

# Backup
./scripts/backup-system.sh -t incremental >> /home/roi12/maintenance.log 2>&1

# Cleanup
docker system prune -f >> /home/roi12/maintenance.log 2>&1
```

### Documentation Updates
- Keep this troubleshooting guide updated with new issues
- Document all configuration changes
- Maintain a change log for system modifications
- Record all incident resolutions

## Getting Help

### Information to Gather
Before seeking help, collect:
1. Output of `./scripts/health-check.sh`
2. Container logs: `docker logs n8n` and `docker logs qdrant`
3. System information: `docker info` and `docker version`
4. Error messages and timestamps
5. Recent changes or updates made

### Support Resources
- n8n Documentation: https://docs.n8n.io
- Qdrant Documentation: https://qdrant.tech/documentation
- Docker Documentation: https://docs.docker.com
- Community Forums and GitHub Issues
- Local system administrator

---

**Remember**: Always create a backup before attempting major troubleshooting steps, and document any changes made during the resolution process.