# System Architecture Documentation

## Overview

The AI Automation System is built using a microservices architecture with Docker containers orchestrated to provide workflow automation and vector database capabilities.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Host System                          │
│                     (Linux/WSL2)                           │
├─────────────────────────────────────────────────────────────┤
│                    Docker Engine                            │
├─────────────────────────────────────────────────────────────┤
│                  ai-stack Network                           │
│                  (172.18.0.0/16)                          │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │     n8n     │  │   Qdrant    │  │Claude Admin │        │
│  │ 172.18.0.3  │  │ 172.18.0.4  │  │ 172.18.0.2  │        │
│  │   :5678     │  │   :6333     │  │     -       │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│        │                 │                 │               │
│        │                 │                 │               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │  n8n Data   │  │ Qdrant Data │  │ Admin Utils │        │
│  │   Volume    │  │   Volume    │  │   (Temp)    │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Container Specifications

### n8n Workflow Engine
- **Image**: `n8nio/n8n:latest`
- **Container ID**: `87fc1ebb3a8b`
- **Network**: `ai-stack` (172.18.0.3)
- **Ports**: 5678:5678 (HTTP API/Web UI)
- **Status**: Healthy, Up 3 hours
- **Resources**: ~211MB RAM, <0.1% CPU
- **Health Check**: Built-in HTTP endpoint monitoring

#### Volume Mounts
- **Source**: `/home/roi12/.n8n`
- **Target**: `/home/node/.n8n`
- **Type**: Bind mount
- **Permissions**: Read/Write

#### Data Structure
```
/home/roi12/.n8n/
├── binaryData/           # Binary file storage
├── config               # n8n configuration
├── database.sqlite      # Workflow and execution data
├── nodes/              # Custom node modules
│   └── node_modules/
│       └── n8n-nodes-qdrant/  # Qdrant integration
├── ssh/                # SSH keys for git operations
├── git/                # Git repository configurations
└── *.log               # Application logs
```

### Qdrant Vector Database
- **Image**: `qdrant/qdrant:latest`
- **Container ID**: `c9268f801752`
- **Network**: `ai-stack` (172.18.0.4)
- **Ports**: 6333:6333 (HTTP API), 6334 (gRPC, internal)
- **Status**: Healthy, Up 3 hours
- **Resources**: ~50MB RAM, <0.2% CPU
- **Health Check**: Built-in API endpoint monitoring

#### Volume Mounts
- **Source**: `/home/roi12/qdrant_storage`
- **Target**: `/qdrant/storage`
- **Type**: Bind mount
- **Permissions**: Read/Write

#### Data Structure
```
/home/roi12/qdrant_storage/
├── collections/
│   ├── mem_notes_main/     # AI memory vectors (1536d, Cosine)
│   │   ├── 0/             # Shard 0
│   │   │   ├── segments/   # Vector segments
│   │   │   └── wal/       # Write-ahead log
│   │   └── config.json    # Collection configuration
│   └── notes/             # Test collection (3d, Cosine)
│       └── [similar structure]
├── aliases/               # Collection aliases
└── raft_state.json       # Cluster state
```

### Claude Admin Container
- **Image**: `node:20-bookworm-slim`
- **Container ID**: `fe7a94fa3d24`
- **Network**: `ai-stack` (172.18.0.2)
- **Ports**: None exposed
- **Status**: Running, Up 3 hours
- **Resources**: ~3MB RAM, minimal CPU
- **Purpose**: Administrative utilities and tools

## Network Architecture

### ai-stack Bridge Network
- **Subnet**: 172.18.0.0/16
- **Gateway**: 172.18.0.1
- **Driver**: bridge
- **DNS**: Docker embedded DNS resolver
- **Isolation**: Services isolated from host network

#### IP Address Allocation
| Container | IP Address | Hostname |
|-----------|------------|----------|
| claude-admin | 172.18.0.2 | claude-admin |
| n8n | 172.18.0.3 | n8n |
| qdrant | 172.18.0.4 | qdrant |

### Port Mapping
| Service | Internal Port | External Port | Protocol | Purpose |
|---------|---------------|---------------|----------|---------|
| n8n | 5678 | 5678 | HTTP | Web UI & API |
| qdrant | 6333 | 6333 | HTTP | REST API |
| qdrant | 6334 | - | gRPC | Internal (not exposed) |

### Service Discovery
- **Internal Communication**: Container names as hostnames
- **Example**: n8n can reach Qdrant at `http://qdrant:6333`
- **DNS Resolution**: Automatic via Docker's embedded DNS

## Data Flow Architecture

```
┌─────────────┐    HTTP/REST     ┌─────────────┐
│     n8n     │ ────────────────► │   Qdrant    │
│  Workflows  │                  │   Vector    │
│             │ ◄──────────────── │  Database   │
└─────────────┘    Responses     └─────────────┘
       │                                │
       │                                │
       ▼                                ▼
┌─────────────┐                  ┌─────────────┐
│ SQLite DB   │                  │  File       │
│ Workflows   │                  │  Storage    │
│ Executions  │                  │  Vectors    │
│ Settings    │                  │  Indices    │
└─────────────┘                  └─────────────┘
```

### Data Persistence Strategy
- **n8n**: SQLite database for workflow definitions and execution history
- **Qdrant**: File-based storage with WAL (Write-Ahead Logging)
- **Volumes**: Host-mounted for persistence across container restarts
- **Backup**: File-level backup of mounted volumes

## Integration Patterns

### n8n → Qdrant Communication
1. **HTTP REST API**: Primary communication method
2. **Custom Node**: `n8n-nodes-qdrant` package installed
3. **Operations Supported**:
   - Vector insertion and updates
   - Similarity search queries
   - Collection management
   - Point filtering and retrieval

### Workflow Triggers
- **Webhook endpoints**: External system integration
- **Schedule triggers**: Time-based automation
- **Manual triggers**: Development and testing
- **File watchers**: Filesystem event triggers

## Security Architecture

### Network Security
- **Container Isolation**: Services run in isolated network
- **Port Exposure**: Only necessary ports exposed to host
- **Internal Communication**: Encrypted at application layer

### Data Security
- **Volume Permissions**: Restricted to container user
- **API Access**: No authentication configured (development setup)
- **File System**: Host-level access controls apply

### Configuration Security
- **Secrets Management**: Environment variables and files
- **API Keys**: Stored in n8n credential system
- **Database**: Local file-based, no network exposure

## Performance Characteristics

### Resource Utilization
- **Memory**: 264MB total footprint
- **CPU**: <1% average utilization
- **Disk I/O**: Minimal (logging and checkpoints)
- **Network**: Internal communication only

### Scaling Considerations
- **Horizontal**: Multiple container instances possible
- **Vertical**: Resource limits configurable
- **Storage**: Volume expansion supported
- **Load Balancing**: Reverse proxy integration ready

### Bottlenecks
- **SQLite Concurrency**: Single-writer limitation
- **Vector Storage**: Memory usage scales with data
- **Network Bandwidth**: Container-to-container communication

## Monitoring and Observability

### Health Checks
- **n8n**: HTTP endpoint `/healthz`
- **Qdrant**: HTTP endpoint `/health`
- **Frequency**: Every 30 seconds
- **Failure Threshold**: 3 consecutive failures

### Logging
- **n8n Logs**: `/home/node/.n8n/*.log`
- **Qdrant Logs**: Container stdout/stderr
- **Docker Logs**: `docker logs <container>`
- **Retention**: Docker default (limited)

### Metrics
- **Container Stats**: CPU, memory, network, disk I/O
- **Application Metrics**: Via REST API endpoints
- **Custom Monitoring**: Extensible via n8n workflows

## Deployment Architecture

### Development Environment
- **Single Host**: All services on one machine
- **Local Volumes**: Direct host filesystem access
- **No Load Balancing**: Direct port access
- **Development Tools**: Included in containers

### Production Considerations
- **Multi-Host**: Service distribution
- **Shared Storage**: Network-attached volumes
- **Load Balancing**: Reverse proxy integration
- **Monitoring**: Comprehensive observability stack
- **Security**: Authentication, encryption, access control

## Extension Points

### Custom Nodes
- **Directory**: `/home/roi12/.n8n/nodes/`
- **Package Manager**: npm-based installation
- **Development**: TypeScript/JavaScript
- **Integration**: Docker volume restart required

### API Integration
- **n8n Webhooks**: External system triggers
- **Qdrant REST API**: Direct vector operations
- **Custom Endpoints**: n8n workflow exposure

### Data Connectors
- **Database**: Multiple database node types
- **Cloud Services**: AWS, GCP, Azure integrations
- **Messaging**: Queue and pub/sub systems
- **File Systems**: Local and cloud storage

---

This architecture is designed for flexibility and extensibility while maintaining simplicity for development and testing scenarios.