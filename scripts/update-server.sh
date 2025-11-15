set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== BiologiDex Server Update ===${NC}"
echo ""

# Step 1: Pull latest code from git
echo -e "${BLUE}[1/6] Pulling latest code from git...${NC}"
cd ~/Development/biologidex/
git pull

# Step 2: Copy files to production directory
echo ""
echo -e "${BLUE}[2/6] Copying files to /opt/biologidex/...${NC}"
cp -r * /opt/biologidex/

# Step 3: Navigate to server directory
echo ""
echo -e "${BLUE}[3/6] Navigating to production server directory...${NC}"
cd /opt/biologidex/server

# Step 4: Stop existing containers
echo ""
echo -e "${BLUE}[4/6] Stopping existing containers...${NC}"
docker-compose -f docker-compose.production.yml down

# Step 5: Rebuild containers with updated code
echo ""
echo -e "${BLUE}[5/6] Rebuilding Docker containers...${NC}"
docker-compose -f docker-compose.production.yml build

# Step 6: Start services
echo ""
echo "Start services:    docker-compose -f docker-compose.production.yml up -d"