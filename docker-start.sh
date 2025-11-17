#!/bin/bash

# Quick Start Script for Docker Deployment
# Product Video Generator

set -e

echo "========================================"
echo "Product Video Generator - Docker Setup"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    echo "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker is not running${NC}"
    echo "Please start Docker Desktop and try again"
    exit 1
fi

echo -e "${GREEN}✓ Docker is installed and running${NC}"
echo ""

# # Check for .env file
# if [ ! -f .env ]; then
#     echo -e "${YELLOW}⚠ No .env file found${NC}"
#     echo "Creating .env from .env.example..."

#     if [ -f .env.example ]; then
#         cp .env.example .env
#         echo -e "${YELLOW}Please edit .env with your AWS credentials before proceeding${NC}"
#         echo ""
#         read -p "Press Enter to open .env in default editor, or Ctrl+C to exit..."
#         ${EDITOR:-nano} .env
#     else
#         echo -e "${RED}Error: .env.example not found${NC}"
#         exit 1
#     fi
# fi

# echo -e "${GREEN}✓ Configuration file found${NC}"
# echo ""

# # Check if AWS credentials are set
# if grep -q "your-access-key-id" .env || grep -q "your-secret-access-key" .env; then
#     echo -e "${RED}⚠ WARNING: AWS credentials are not configured in .env${NC}"
#     echo "Video generation will fail without valid AWS credentials"
#     read -p "Continue anyway? [y/N] " -n 1 -r
#     echo
#     if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#         exit 1
#     fi
# fi

# Docker Swarm mode (default)
echo ""
echo -e "${BLUE}Deploying with Docker Swarm...${NC}"
echo ""

STACK_NAME="product-videos"

# Check if Swarm is initialized
echo -e "${BLUE}Initializing Docker Swarm (if needed)...${NC}"
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "  Swarm not active, initializing..."
    docker swarm init
    echo -e "${GREEN}✓ Swarm initialized${NC}"
else
    echo -e "${GREEN}✓ Swarm already active${NC}"
fi
echo ""

echo -e "${BLUE}Stack name: ${STACK_NAME}${NC}"
echo ""

echo -e "${BLUE}Building Docker images...${NC}"
docker-compose build
echo -e "${GREEN}✓ Images built${NC}"
echo ""

echo -e "${BLUE}Deploying stack...${NC}"
docker stack deploy -c docker-compose.yml $STACK_NAME

echo ""
echo -e "${GREEN}✓ Stack deployed successfully!${NC}"
echo ""

echo -e "${BLUE}Waiting for services to start...${NC}"
sleep 10

# Check service status
echo ""
echo "Service Status:"
docker stack services $STACK_NAME

echo ""
echo "=========================================="
echo -e "${GREEN}Application is running!${NC}"
echo "=========================================="
echo ""
echo -e "Frontend:  ${BLUE}http://localhost${NC}"
echo -e "Backend:   ${BLUE}http://localhost:8000${NC}"
echo -e "API Docs:  ${BLUE}http://localhost:8000/docs${NC}"
echo ""
echo "Useful Docker Swarm commands:"
echo "  docker stack ls"
echo "  docker stack services $STACK_NAME"
echo "  docker stack ps $STACK_NAME"
echo ""
echo "View logs:"
echo "  docker service logs ${STACK_NAME}_backend"
echo "  docker service logs ${STACK_NAME}_frontend"
echo "  docker service logs -f ${STACK_NAME}_backend  # follow"
echo ""
echo "Scale services:"
echo "  docker service scale ${STACK_NAME}_backend=3"
echo ""
echo "Remove stack:"
echo "  docker stack rm $STACK_NAME"
echo ""

# Ask if user wants to view logs
read -p "View live logs now? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Showing backend logs (press Ctrl+C to exit)..."
    docker service logs -f ${STACK_NAME}_backend
fi
