#!/bin/bash

# Product Video Generator - Startup Script
# This script starts both the backend API server and the frontend React app

echo "=========================================="
echo "Product Video Generator - Starting UI"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed${NC}"
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "${RED}Error: Node.js is not installed${NC}"
    exit 1
fi

# Check if required Python packages are installed
echo -e "${BLUE}Checking Python dependencies...${NC}"
if ! python3 -c "import fastapi" &> /dev/null; then
    echo -e "${RED}FastAPI not found. Installing dependencies...${NC}"
    pip3 install -r requirements.txt
fi

# Check if frontend dependencies are installed
if [ ! -d "frontend/node_modules" ]; then
    echo -e "${BLUE}Installing frontend dependencies...${NC}"
    cd frontend
    npm install
    cd ..
fi

# Create required directories
echo -e "${BLUE}Creating required directories...${NC}"
mkdir -p keyframes videos

# Function to cleanup on exit
cleanup() {
    echo ""
    echo -e "${RED}Shutting down servers...${NC}"
    kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
    exit 0
}

trap cleanup SIGINT SIGTERM

# Start backend server
echo -e "${GREEN}Starting backend server on port 8000...${NC}"
python3 api_server.py local > backend.log 2>&1 &
BACKEND_PID=$!

# Wait for backend to start
sleep 3

# Check if backend started successfully
if ! ps -p $BACKEND_PID > /dev/null; then
    echo -e "${RED}Failed to start backend server. Check backend.log for details.${NC}"
    exit 1
fi

echo -e "${GREEN}Backend server started (PID: $BACKEND_PID)${NC}"

# Start frontend server
echo -e "${GREEN}Starting frontend server on port 3000...${NC}"
cd frontend
npm start > ../frontend.log 2>&1 &
FRONTEND_PID=$!
cd ..

# Wait for frontend to start
sleep 5

# Check if frontend started successfully
if ! ps -p $FRONTEND_PID > /dev/null; then
    echo -e "${RED}Failed to start frontend server. Check frontend.log for details.${NC}"
    kill $BACKEND_PID
    exit 1
fi

echo -e "${GREEN}Frontend server started (PID: $FRONTEND_PID)${NC}"
echo ""
echo "=========================================="
echo -e "${GREEN}✓ Application is running!${NC}"
echo "=========================================="
echo ""
echo -e "Frontend: ${BLUE}http://localhost:3000${NC}"
echo -e "Backend:  ${BLUE}http://localhost:8000${NC}"
echo -e "API Docs: ${BLUE}http://localhost:8000/docs${NC}"
echo ""
echo "Press Ctrl+C to stop all servers"
echo ""
echo "Logs:"
echo "  Backend:  tail -f backend.log"
echo "  Frontend: tail -f frontend.log"
echo ""

# Wait for processes
wait $BACKEND_PID $FRONTEND_PID
