#!/bin/bash

# BiologiDex Diagnostics Script
# Comprehensive system diagnostics for troubleshooting
# Usage: ./diagnose.sh [--full]

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.production.yml"
FULL_MODE=false

# Parse arguments
if [ "${1:-}" = "--full" ]; then
    FULL_MODE=true
fi

# Functions
print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}║${NC} ${GREEN}BiologiDex System Diagnostics${NC}"
    echo -e "${BLUE}║${NC} $(date +'%Y-%m-%d %H:%M:%S')"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

check_status() {
    local status=$1
    local service=$2

    if [ $status -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $service"
    else
        echo -e "${RED}✗${NC} $service"
    fi
}

# System checks
echo ""
print_header
echo ""

echo -e "${YELLOW}1. System Information${NC}"
echo "   OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "   Kernel: $(uname -r)"
echo "   Uptime: $(uptime -p)"
echo ""

echo -e "${YELLOW}2. Docker Environment${NC}"
docker version --format 'Docker Engine: {{.Server.Version}}' 2>/dev/null && check_status 0 "Docker Engine" || check_status 1 "Docker Engine"
docker-compose version --short 2>/dev/null | xargs printf "Docker Compose: %s\n" && check_status 0 "Docker Compose" || check_status 1 "Docker Compose"
echo ""

echo -e "${YELLOW}3. Container Status${NC}"
CONTAINERS=$(docker-compose -f $COMPOSE_FILE ps -q 2>/dev/null | wc -l)
RUNNING=$(docker-compose -f $COMPOSE_FILE ps -q 2>/dev/null | xargs docker inspect -f '{{.State.Running}}' 2>/dev/null | grep true | wc -l)
echo "   Total containers: $CONTAINERS"
echo "   Running: $RUNNING"

if [ $CONTAINERS -ne $RUNNING ]; then
    echo -e "   ${RED}Warning: Not all containers are running!${NC}"
    docker-compose -f $COMPOSE_FILE ps --format "table {{.Name}}\t{{.State}}" 2>/dev/null | grep -v running || true
fi
echo ""

echo -e "${YELLOW}4. Service Health Checks${NC}"
# Database
docker-compose -f $COMPOSE_FILE exec -T db pg_isready -U biologidex >/dev/null 2>&1 && check_status 0 "PostgreSQL" || check_status 1 "PostgreSQL"

# Redis
docker-compose -f $COMPOSE_FILE exec -T redis redis-cli ping >/dev/null 2>&1 && check_status 0 "Redis" || check_status 1 "Redis"

# Django
curl -sf http://localhost/health/ >/dev/null 2>&1 && check_status 0 "Django Application" || check_status 1 "Django Application"

# Nginx
docker-compose -f $COMPOSE_FILE exec -T nginx nginx -t >/dev/null 2>&1 && check_status 0 "Nginx Configuration" || check_status 1 "Nginx Configuration"

# Celery
docker-compose -f $COMPOSE_FILE exec -T celery_worker celery -A biologidex inspect ping >/dev/null 2>&1 && check_status 0 "Celery Workers" || check_status 1 "Celery Workers"
echo ""

echo -e "${YELLOW}5. Resource Usage${NC}"
echo "   CPU Load: $(uptime | awk -F'load average:' '{print $2}')"
echo "   Memory:"
free -h | grep Mem | awk '{printf "     Total: %s, Used: %s, Free: %s (%.1f%%)\n", $2, $3, $4, ($3/$2)*100}'

echo "   Disk:"
df -h / | tail -1 | awk '{printf "     Total: %s, Used: %s, Available: %s (%s)\n", $2, $3, $4, $5}'

echo "   Docker:"
docker system df 2>/dev/null | tail -n +2 | awk '{printf "     %s: %s\n", $1, $3}'
echo ""

echo -e "${YELLOW}6. Network Connectivity${NC}"
# Check ports
netstat -tuln 2>/dev/null | grep -q ":80 " && check_status 0 "Port 80 (HTTP)" || check_status 1 "Port 80 (HTTP)"
netstat -tuln 2>/dev/null | grep -q ":443 " && check_status 0 "Port 443 (HTTPS)" || check_status 1 "Port 443 (HTTPS)"
netstat -tuln 2>/dev/null | grep -q ":5432 " && check_status 0 "Port 5432 (PostgreSQL)" || check_status 1 "Port 5432 (PostgreSQL)"
netstat -tuln 2>/dev/null | grep -q ":6379 " && check_status 0 "Port 6379 (Redis)" || check_status 1 "Port 6379 (Redis)"
echo ""

echo -e "${YELLOW}7. Recent Errors${NC}"
if [ -d "/var/log/biologidex" ]; then
    ERROR_COUNT=$(find /var/log/biologidex -name "*.log" -mtime -1 -exec grep -h ERROR {} \; 2>/dev/null | wc -l)
    echo "   Errors in last 24 hours: $ERROR_COUNT"

    if [ $ERROR_COUNT -gt 0 ]; then
        echo "   Most recent errors:"
        find /var/log/biologidex -name "*.log" -mtime -1 -exec grep -h ERROR {} \; 2>/dev/null | tail -3 | while read line; do
            echo "     $(echo $line | cut -c1-70)..."
        done
    fi
else
    echo "   Log directory not found"
fi
echo ""

echo -e "${YELLOW}8. Database Status${NC}"
DB_SIZE=$(docker-compose -f $COMPOSE_FILE exec -T db psql -U biologidex -t -c "SELECT pg_database_size('biologidex')/1024/1024 as size_mb;" 2>/dev/null | tr -d ' ' || echo "N/A")
DB_CONN=$(docker-compose -f $COMPOSE_FILE exec -T db psql -U biologidex -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ' || echo "N/A")
echo "   Database size: ${DB_SIZE} MB"
echo "   Active connections: $DB_CONN"
echo ""

if [ "$FULL_MODE" = true ]; then
    echo -e "${YELLOW}9. Full Container Logs (last 20 lines each)${NC}"
    for service in web celery_worker nginx db redis; do
        echo -e "\n   ${BLUE}$service logs:${NC}"
        docker-compose -f $COMPOSE_FILE logs --tail=20 $service 2>/dev/null | sed 's/^/     /'
    done
    echo ""

    echo -e "${YELLOW}10. Environment Variables Check${NC}"
    ENV_FILE=".env"
    if [ -f "$ENV_FILE" ]; then
        echo "   Required variables:"
        for var in SECRET_KEY DB_PASSWORD REDIS_PASSWORD OPENAI_API_KEY; do
            if grep -q "^$var=" "$ENV_FILE"; then
                check_status 0 "$var is set"
            else
                check_status 1 "$var is NOT set"
            fi
        done
    else
        echo -e "   ${RED}Warning: .env file not found!${NC}"
    fi
    echo ""

    echo -e "${YELLOW}11. SSL/TLS Status${NC}"
    if [ -d "ssl" ]; then
        for cert in ssl/*.crt ssl/*.pem; do
            if [ -f "$cert" ]; then
                EXPIRY=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
                echo "   $cert expires: $EXPIRY"
            fi
        done
    else
        echo "   No SSL certificates found (using HTTP only or Cloudflare)"
    fi
    echo ""
fi

echo -e "${YELLOW}9. API Endpoint Tests${NC}"
# Test key endpoints
for endpoint in "/api/v1/health/" "/api/docs/" "/metrics/"; do
    if curl -sf "http://localhost$endpoint" -o /dev/null -w "%{http_code}" | grep -q "200\|301\|302"; then
        check_status 0 "$endpoint"
    else
        check_status 1 "$endpoint"
    fi
done
echo ""

# Generate summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Diagnostics Summary:${NC}"

ISSUES=0

# Check for critical issues
if [ $RUNNING -lt $CONTAINERS ]; then
    echo -e "${RED}● Critical: Not all containers are running${NC}"
    ISSUES=$((ISSUES + 1))
fi

if ! curl -sf http://localhost/health/ >/dev/null 2>&1; then
    echo -e "${RED}● Critical: Application health check failing${NC}"
    ISSUES=$((ISSUES + 1))
fi

if [ "$ERROR_COUNT" -gt 100 ]; then
    echo -e "${YELLOW}● Warning: High error count in logs${NC}"
    ISSUES=$((ISSUES + 1))
fi

DISK_PERCENT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [ $DISK_PERCENT -gt 80 ]; then
    echo -e "${YELLOW}● Warning: Disk usage above 80%${NC}"
    ISSUES=$((ISSUES + 1))
fi

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}● All systems operational${NC}"
else
    echo -e "\n${YELLOW}Found $ISSUES issue(s) requiring attention${NC}"
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Provide recommendations
if [ $ISSUES -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Recommendations:${NC}"

    if [ $RUNNING -lt $CONTAINERS ]; then
        echo "  • Run: docker-compose -f $COMPOSE_FILE up -d"
    fi

    if [ "$ERROR_COUNT" -gt 100 ]; then
        echo "  • Check logs: tail -f /var/log/biologidex/error.log"
    fi

    if [ $DISK_PERCENT -gt 80 ]; then
        echo "  • Clean up disk space or expand storage"
        echo "  • Run: docker system prune -a"
    fi
fi

echo ""
echo "Run with --full flag for extended diagnostics"
echo ""