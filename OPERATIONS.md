# Operations Manual

## Daily Operations

### System Health Monitoring

#### Quick Health Check
```bash
# Check all container status
docker ps

# Check resource usage
docker stats --no-stream

# Check specific service health
curl -s http://localhost:5678/healthz  # n8n
curl -s http://localhost:6333/health   # Qdrant
```

#### Expected Output
- All containers should show "healthy" status
- n8n: ~211MB RAM, <0.1% CPU
- Qdrant: ~50MB RAM, <0.2% CPU
- Response time: <100ms for health endpoints

### Service Management

#### Starting Services
```bash
# Individual containers
docker start n8n
docker start qdrant
docker start claude-admin

# All services (if using compose)
# Note: No docker-compose.yml found - services started individually
```

#### Stopping Services
```bash
# Graceful shutdown (recommended)
docker stop n8n
docker stop qdrant
docker stop claude-admin

# Force stop (if needed)
docker kill n8n qdrant claude-admin
```

#### Restarting Services
```bash
# Restart individual service
docker restart n8n

# Restart all services
docker restart n8n qdrant claude-admin
```

### Container Management

#### Viewing Logs
```bash
# Real-time logs
docker logs -f n8n
docker logs -f qdrant

# Recent logs (last 100 lines)
docker logs --tail 100 n8n

# Logs with timestamps
docker logs -t n8n
```

#### Executing Commands in Containers
```bash
# n8n container shell
docker exec -it n8n /bin/sh

# Qdrant container shell (if needed)
docker exec -it qdrant /bin/sh

# Run specific command
docker exec n8n n8n --version
```

### Data Management

#### Volume Locations
- **n8n Data**: `/home/roi12/.n8n/`
- **Qdrant Data**: `/home/roi12/qdrant_storage/`

#### Disk Usage Monitoring
```bash
# Check volume sizes
du -sh /home/roi12/.n8n/
du -sh /home/roi12/qdrant_storage/

# Check available disk space
df -h /home/roi12/

# Check specific database sizes
ls -lh /home/roi12/.n8n/database.sqlite
du -sh /home/roi12/qdrant_storage/collections/
```

### Workflow Operations

#### n8n Workflow Management
```bash
# Access n8n web interface
open http://localhost:5678

# Export workflows (via API)
curl -X GET http://localhost:5678/api/v1/workflows \
  -H "Content-Type: application/json"

# Check active workflows
curl -X GET http://localhost:5678/api/v1/workflows/active
```

#### Qdrant Collection Management
```bash
# List collections
curl -X GET http://localhost:6333/collections

# Get collection info
curl -X GET http://localhost:6333/collections/mem_notes_main

# Get collection statistics
curl -X GET http://localhost:6333/collections/mem_notes_main/points

# Check cluster info
curl -X GET http://localhost:6333/cluster
```

## Weekly Operations

### System Maintenance

#### Container Updates
```bash
# Pull latest images
docker pull n8nio/n8n:latest
docker pull qdrant/qdrant:latest

# Stop services
docker stop n8n qdrant

# Remove old containers
docker rm n8n qdrant

# Recreate with new images
# Note: Use original docker run commands with new images
```

#### Log Rotation
```bash
# Check log sizes
docker logs n8n 2>/dev/null | wc -l
docker logs qdrant 2>/dev/null | wc -l

# Docker log cleanup (if needed)
docker system prune --volumes -f

# Application log cleanup
find /home/roi12/.n8n/ -name "*.log*" -mtime +7 -delete
```

#### Performance Optimization
```bash
# Optimize Qdrant indices
curl -X POST http://localhost:6333/collections/mem_notes_main/index

# n8n database optimization
docker exec n8n sqlite3 /home/node/.n8n/database.sqlite "VACUUM;"

# Docker system cleanup
docker system prune -f
```

## Monthly Operations

### Backup Procedures

#### Full System Backup
```bash
# Create backup directory
mkdir -p /home/roi12/backups/$(date +%Y-%m-%d)

# Stop services for consistent backup
docker stop n8n qdrant

# Backup data volumes
tar -czf /home/roi12/backups/$(date +%Y-%m-%d)/n8n-data.tar.gz -C /home/roi12 .n8n
tar -czf /home/roi12/backups/$(date +%Y-%m-%d)/qdrant-data.tar.gz -C /home/roi12 qdrant_storage

# Backup container configurations
docker inspect n8n > /home/roi12/backups/$(date +%Y-%m-%d)/n8n-config.json
docker inspect qdrant > /home/roi12/backups/$(date +%Y-%m-%d)/qdrant-config.json

# Restart services
docker start qdrant n8n
```

#### Incremental Backup
```bash
# Backup only changed files (last 7 days)
find /home/roi12/.n8n -mtime -7 -type f | tar -czf /home/roi12/backups/n8n-incremental-$(date +%Y-%m-%d).tar.gz -T -
find /home/roi12/qdrant_storage -mtime -7 -type f | tar -czf /home/roi12/backups/qdrant-incremental-$(date +%Y-%m-%d).tar.gz -T -
```

### Security Updates

#### Container Security Scan
```bash
# Scan images for vulnerabilities (if trivy installed)
trivy image n8nio/n8n:latest
trivy image qdrant/qdrant:latest

# Check for exposed ports
nmap -p 1-10000 localhost

# Review container permissions
docker exec n8n id
docker exec qdrant id
```

#### Access Review
```bash
# Check file permissions
ls -la /home/roi12/.n8n/
ls -la /home/roi12/qdrant_storage/

# Review Docker daemon access
docker version
docker info | grep -i security
```

## Troubleshooting Procedures

### Common Issues

#### Service Won't Start
```bash
# Check container status
docker ps -a

# Check container logs
docker logs n8n
docker logs qdrant

# Check port conflicts
netstat -tlnp | grep -E ':(5678|6333)'
lsof -i :5678
lsof -i :6333

# Restart Docker daemon (if needed)
sudo systemctl restart docker
```

#### Performance Issues
```bash
# Check system resources
free -h
df -h
top

# Check container resources
docker stats

# Check for memory leaks
docker exec n8n ps aux
docker exec qdrant ps aux

# Restart affected services
docker restart n8n qdrant
```

#### Data Corruption
```bash
# Check SQLite database integrity
docker exec n8n sqlite3 /home/node/.n8n/database.sqlite "PRAGMA integrity_check;"

# Check Qdrant collection status
curl -X GET http://localhost:6333/collections/mem_notes_main

# Restore from backup (if needed)
# See backup restore procedures below
```

### Recovery Procedures

#### Service Recovery
```bash
# Force restart all services
docker kill n8n qdrant claude-admin
docker start qdrant n8n claude-admin

# Recreate network if needed
docker network rm ai-stack
docker network create ai-stack
# Note: Containers need to be recreated to join new network
```

#### Data Recovery
```bash
# Stop services
docker stop n8n qdrant

# Restore from latest backup
tar -xzf /home/roi12/backups/YYYY-MM-DD/n8n-data.tar.gz -C /home/roi12/
tar -xzf /home/roi12/backups/YYYY-MM-DD/qdrant-data.tar.gz -C /home/roi12/

# Set correct permissions
chown -R 1000:1000 /home/roi12/.n8n/
chown -R 1000:1000 /home/roi12/qdrant_storage/

# Start services
docker start qdrant n8n
```

## Monitoring and Alerting

### Health Monitoring Setup
```bash
# Create monitoring script
cat > /home/roi12/monitor-health.sh << 'EOF'
#!/bin/bash
# Basic health monitoring
set -e

echo "=== System Health Check $(date) ==="

# Check containers
docker ps | grep -E "(n8n|qdrant|claude-admin)" || echo "ERROR: Missing containers"

# Check services
curl -f -s http://localhost:5678/healthz > /dev/null && echo "✓ n8n healthy" || echo "✗ n8n unhealthy"
curl -f -s http://localhost:6333/health > /dev/null && echo "✓ Qdrant healthy" || echo "✗ Qdrant unhealthy"

# Check disk space
df -h /home/roi12 | awk 'NR==2 {if ($5+0 > 80) print "⚠ Disk usage high: " $5; else print "✓ Disk usage OK: " $5}'

# Check memory
free -m | awk 'NR==2 {if ($3/$2*100 > 80) print "⚠ Memory usage high: " $3/$2*100 "%"; else print "✓ Memory usage OK: " $3/$2*100 "%"}'

echo "=== End Health Check ==="
EOF

chmod +x /home/roi12/monitor-health.sh
```

### Log Monitoring
```bash
# Create log monitoring script
cat > /home/roi12/check-errors.sh << 'EOF'
#!/bin/bash
# Check for errors in logs
echo "=== Error Check $(date) ==="

# Check n8n logs for errors
docker logs n8n --since 1h | grep -i error | tail -5

# Check Qdrant logs for errors
docker logs qdrant --since 1h | grep -i error | tail -5

# Check application-specific logs
tail -20 /home/roi12/.n8n/n8nEventLog.log | grep -i error

echo "=== End Error Check ==="
EOF

chmod +x /home/roi12/check-errors.sh
```

### Automated Monitoring
```bash
# Add to crontab for regular checks
crontab -l | { cat; echo "*/15 * * * * /home/roi12/monitor-health.sh >> /home/roi12/health.log 2>&1"; } | crontab -
crontab -l | { cat; echo "0 */6 * * * /home/roi12/check-errors.sh >> /home/roi12/errors.log 2>&1"; } | crontab -
```

## Performance Tuning

### Resource Optimization

#### Memory Optimization
```bash
# Set memory limits for containers
docker update --memory="512m" n8n
docker update --memory="256m" qdrant

# Configure Qdrant memory usage
curl -X PUT http://localhost:6333/collections/mem_notes_main \
  -H "Content-Type: application/json" \
  -d '{"optimizer_config": {"memmap_threshold": 20000}}'
```

#### Storage Optimization
```bash
# Enable Qdrant compression
curl -X PUT http://localhost:6333/collections/mem_notes_main/index \
  -H "Content-Type: application/json" \
  -d '{"compression": {"enabled": true}}'

# n8n database optimization
docker exec n8n sqlite3 /home/node/.n8n/database.sqlite "ANALYZE; VACUUM;"
```

## Scaling Considerations

### Vertical Scaling
- Increase container memory limits
- Add CPU cores to Docker daemon
- Expand storage volumes

### Horizontal Scaling
- Deploy multiple n8n instances with load balancer
- Configure Qdrant cluster mode
- Implement shared storage for data

### Load Testing
```bash
# Simple load test for n8n
for i in {1..10}; do
  curl -X GET http://localhost:5678/healthz &
done
wait

# Simple load test for Qdrant
for i in {1..100}; do
  curl -X GET http://localhost:6333/collections &
done
wait
```

---

This operations manual provides comprehensive procedures for managing your AI automation system effectively.