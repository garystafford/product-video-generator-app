# Docker Quick Start Guide

Quick reference for running the Product Video Generator with Docker Swarm.

## Prerequisites

- Docker Desktop installed and running
- AWS credentials ready
- 4GB+ RAM available

## 30-Second Start

```bash
# 1. Configure AWS credentials
cp .env.example .env
nano .env  # Add your AWS credentials

# 2. Start everything
./docker-start.sh

# 3. Open browser
open http://localhost
```

That's it! 🚀

## Common Commands

### Starting & Stopping

```bash
# Start services
./docker-start.sh

# Refresh AWS credentials and restart
./refresh-credentials.sh

# Stop services
docker stack rm product-videos

# Check status
docker stack services product-videos
docker stack ps product-videos
```

### Viewing Logs

```bash
# Backend logs
docker service logs product-videos_backend

# Frontend logs
docker service logs product-videos_frontend

# Follow logs (live)
docker service logs -f product-videos_backend
docker service logs -f product-videos_frontend

# Last 100 lines
docker service logs --tail=100 product-videos_backend
```

### Checking Status

```bash
# Service status
docker stack services product-videos

# Container status
docker stack ps product-videos

# Detailed view
docker ps --filter "name=product-videos"

# Stack list
docker stack ls
```

### Rebuilding

```bash
# Rebuild all images
docker-compose build

# Rebuild specific service
docker-compose build backend
docker-compose build frontend

# Force rebuild (no cache)
docker-compose build --no-cache

# Redeploy after rebuild
docker stack deploy -c docker-compose.yml product-videos
```

### Scaling Services

```bash
# Scale backend to 3 replicas
docker service scale product-videos_backend=3

# Scale frontend to 2 replicas
docker service scale product-videos_frontend=2

# View replica status
docker stack ps product-videos
```

### Maintenance

```bash
# View disk usage
docker system df

# List volumes
docker volume ls | grep product-videos

# Clean up unused images
docker image prune -a

# Full system cleanup (WARNING: removes all unused resources)
docker system prune -a --volumes

# Backup volumes
docker run --rm -v product-videos_keyframes:/data -v $(pwd):/backup alpine tar czf /backup/keyframes-backup.tar.gz -C /data .
docker run --rm -v product-videos_videos:/data -v $(pwd):/backup alpine tar czf /backup/videos-backup.tar.gz -C /data .
```

## Docker Swarm Management

### Initialize Swarm

```bash
# Initialize (only needed once)
docker swarm init
```

### Deploy Stack

```bash
# Deploy with stack name
docker stack deploy -c docker-compose.yml product-videos

# Update stack (after code changes)
docker-compose build
docker stack deploy -c docker-compose.yml product-videos
```

### Stack Operations

```bash
# List all stacks
docker stack ls

# View services in stack
docker stack services product-videos

# View tasks in stack
docker stack ps product-videos

# Remove stack
docker stack rm product-videos
```

### Service Operations

```bash
# Update service (force restart)
docker service update --force product-videos_backend

# View service details
docker service inspect product-videos_backend

# View service logs
docker service logs product-videos_backend
```

## Troubleshooting

### Services won't start

```bash
# Check service status
docker stack services product-videos

# Check detailed status
docker stack ps product-videos --no-trunc

# Check logs
docker service logs product-videos_backend
docker service logs product-videos_frontend

# Check if ports are in use
lsof -i :80
lsof -i :8000

# Remove and redeploy
docker stack rm product-videos
# Wait 10 seconds
docker stack deploy -c docker-compose.yml product-videos
```

### Out of memory

```bash
# Check Docker resources
docker system df

# Increase Docker memory (Docker Desktop → Settings → Resources)

# Clean up
docker system prune -a --volumes
```

### Cannot connect to backend

```bash
# Check if services are running
docker stack services product-videos

# Check if containers are running
docker ps --filter "name=product-videos"

# Check network
docker network inspect product-videos_video-gen-network

# Restart service
docker service update --force product-videos_backend
```

### AWS credentials not working

```bash
# Verify .env file
cat .env

# Check environment in container
BACKEND_ID=$(docker ps -q --filter "name=product-videos_backend" | head -1)
docker exec $BACKEND_ID env | grep AWS

# Test AWS connection
docker exec $BACKEND_ID python -c "import boto3; print(boto3.client('sts').get_caller_identity())"

# Refresh credentials
./refresh-credentials.sh
```

### Keyframes or videos not showing

```bash
# Run migration to populate database
./run-migration.sh

# Check volumes
docker volume ls | grep product-videos

# Inspect volume contents
BACKEND_ID=$(docker ps -q --filter "name=product-videos_backend" | head -1)
docker exec $BACKEND_ID ls -la /app/keyframes
docker exec $BACKEND_ID ls -la /app/videos
docker exec $BACKEND_ID cat /app/data/database.json
```

### Reset everything

```bash
# Remove stack
docker stack rm product-videos

# Wait for cleanup
sleep 15

# Remove volumes (WARNING: deletes all data)
docker volume rm product-videos_keyframes
docker volume rm product-videos_videos
docker volume rm product-videos_uploads
docker volume rm product-videos_data

# Rebuild and redeploy
./docker-start.sh
```

## Port Reference

| Service  | Port | URL                          |
|----------|------|------------------------------|
| Frontend | 80   | http://localhost             |
| Backend  | 8000 | http://localhost:8000        |
| API Docs | 8000 | http://localhost:8000/docs   |

## Volume Reference

| Volume                    | Purpose                        |
|---------------------------|--------------------------------|
| product-videos_keyframes  | Start/end frame images        |
| product-videos_videos     | Generated videos              |
| product-videos_uploads    | User uploads                  |
| product-videos_data       | Database and metadata         |

```bash
# List all volumes
docker volume ls | grep product-videos

# Inspect a volume
docker volume inspect product-videos_keyframes
```

## Environment Variables

Required in `.env`:

```bash
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
AWS_SESSION_TOKEN=your-token  # if using SSO
AWS_DEFAULT_REGION=us-west-2
AWS_REGION=us-west-2
```

## Development Workflow

```bash
# 1. Make code changes
nano api_server.py

# 2. Rebuild
docker-compose build backend

# 3. Redeploy
docker stack deploy -c docker-compose.yml product-videos

# 4. View logs
docker service logs -f product-videos_backend

# 5. Test
curl http://localhost:8000/
open http://localhost
```

## Diagnostic Tools

```bash
# Run comprehensive diagnostics
./docker-diagnose.sh

# View all Swarm nodes
docker node ls

# Check Swarm status
docker info | grep Swarm

# View resource usage
docker stats
```

## Production Best Practices

- ✅ Use `.env` file with actual AWS credentials
- ✅ Use `./refresh-credentials.sh` for SSO credentials
- ✅ Resource limits are configured in `docker-compose.yml`
- ✅ Persistent volumes for data
- ✅ Overlay network for service communication
- ✅ Health checks configured
- ✅ Rolling updates supported

### Additional Recommendations

- Set up log aggregation (ELK, CloudWatch)
- Enable TLS/SSL for production domains
- Use Docker secrets for sensitive data
- Implement backup strategy for volumes
- Monitor resource usage
- Set up alerts for service failures

## Quick Links

- Frontend: http://localhost
- Backend API: http://localhost:8000
- API Documentation: http://localhost:8000/docs
- UI Guide: [UI_README.md](UI_README.md)
- Main Documentation: [README.md](README.md)

## Helper Scripts

| Script                    | Purpose                              |
|---------------------------|--------------------------------------|
| `./docker-start.sh`       | Initialize and start the stack       |
| `./refresh-credentials.sh`| Refresh AWS credentials and restart  |
| `./docker-diagnose.sh`    | Run diagnostics                      |
| `./run-migration.sh`      | Migrate existing data to database    |

## Getting Help

```bash
# Docker Swarm help
docker stack --help
docker service --help

# View helper script info
./docker-start.sh --help
./docker-diagnose.sh

# Check logs
docker service logs product-videos_backend
docker service logs product-videos_frontend
```
