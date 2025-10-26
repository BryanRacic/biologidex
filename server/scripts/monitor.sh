#!/bin/bash

# BiologiDex System Monitor
# Real-time monitoring dashboard for BiologiDex production deployment
# Usage: ./monitor.sh

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.production.yml"
HEALTH_URL="http://localhost/api/v1/health/"
METRICS_URL="http://localhost/metrics/"

# Functions
print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}║${NC} ${GREEN}BiologiDex System Monitor${NC} - $(date +'%Y-%m-%d %H:%M:%S')"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

check_health() {
    echo -e "${YELLOW}▶ System Health:${NC}"
    HEALTH_STATUS=$(curl -s $HEALTH_URL 2>/dev/null | jq -r '.status' 2>/dev/null || echo "UNKNOWN")

    if [ "$HEALTH_STATUS" = "healthy" ]; then
        echo -e "  Status: ${GREEN}● HEALTHY${NC}"
    else
        echo -e "  Status: ${RED}● UNHEALTHY${NC}"
    fi

    # Show component status
    curl -s $HEALTH_URL 2>/dev/null | jq -r '.checks | to_entries[] | "  \(.key): \(.value.status // .value)"' 2>/dev/null || echo "  Unable to fetch component status"
    echo ""
}

check_containers() {
    echo -e "${YELLOW}▶ Container Status:${NC}"
    docker-compose -f $COMPOSE_FILE ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}" 2>/dev/null | tail -n +2 | while read line; do
        if echo "$line" | grep -q "running"; then
            echo -e "  ${GREEN}●${NC} $line"
        else
            echo -e "  ${RED}●${NC} $line"
        fi
    done
    echo ""
}

check_resources() {
    echo -e "${YELLOW}▶ Resource Usage:${NC}"

    # Database connections
    DB_CONNECTIONS=$(docker-compose -f $COMPOSE_FILE exec -T db psql -U biologidex -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ' || echo "N/A")
    echo "  Database Connections: $DB_CONNECTIONS"

    # Redis memory
    REDIS_MEM=$(docker-compose -f $COMPOSE_FILE exec -T redis redis-cli INFO memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d '\r' || echo "N/A")
    echo "  Redis Memory: $REDIS_MEM"

    # Celery tasks
    CELERY_ACTIVE=$(docker-compose -f $COMPOSE_FILE exec -T celery_worker celery -A biologidex inspect active 2>/dev/null | grep -c "id" || echo "0")
    echo "  Active Celery Tasks: $CELERY_ACTIVE"

    # Disk usage
    DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}')
    echo "  Disk Usage: $DISK_USAGE"

    # Memory usage
    MEM_USAGE=$(free -h | grep Mem | awk '{print $3"/"$2}')
    echo "  Memory: $MEM_USAGE"

    echo ""
}

check_recent_errors() {
    echo -e "${YELLOW}▶ Recent Errors (last 5):${NC}"
    if [ -d "/var/log/biologidex" ]; then
        ERROR_COUNT=$(grep -h ERROR /var/log/biologidex/*.log 2>/dev/null | wc -l || echo "0")
        echo "  Total errors in logs: $ERROR_COUNT"

        if [ "$ERROR_COUNT" -gt 0 ]; then
            grep -h ERROR /var/log/biologidex/*.log 2>/dev/null | tail -5 | while read line; do
                echo "  - $(echo $line | cut -c1-80)..."
            done
        else
            echo "  ${GREEN}No recent errors${NC}"
        fi
    else
        echo "  Log directory not found"
    fi
    echo ""
}

check_metrics() {
    echo -e "${YELLOW}▶ Key Metrics:${NC}"

    # Fetch metrics
    METRICS=$(curl -s $METRICS_URL 2>/dev/null)

    if [ ! -z "$METRICS" ]; then
        # Total requests
        TOTAL_REQUESTS=$(echo "$METRICS" | grep "django_http_requests_total" | grep -v "#" | awk '{sum+=$2} END {printf "%.0f", sum}')
        echo "  Total Requests: $TOTAL_REQUESTS"

        # Active users
        ACTIVE_USERS=$(echo "$METRICS" | grep "^active_users" | grep -v "#" | awk '{print $2}' | head -1)
        echo "  Active Users: ${ACTIVE_USERS:-0}"

        # Total dex entries
        TOTAL_DEX=$(echo "$METRICS" | grep "^total_dex_entries" | grep -v "#" | awk '{print $2}' | head -1)
        echo "  Total Dex Entries: ${TOTAL_DEX:-0}"

        # CV processing jobs
        CV_JOBS=$(echo "$METRICS" | grep "cv_processing_total" | grep -v "#" | awk '{sum+=$2} END {printf "%.0f", sum}')
        echo "  CV Processing Jobs: ${CV_JOBS:-0}"
    else
        echo "  Metrics endpoint not available"
    fi
    echo ""
}

# Main monitoring loop
main() {
    # Check if running with appropriate permissions
    if ! docker-compose -f $COMPOSE_FILE ps >/dev/null 2>&1; then
        echo -e "${RED}Error: Cannot access Docker. Run with appropriate permissions or add user to docker group.${NC}"
        exit 1
    fi

    # Continuous monitoring
    while true; do
        clear
        print_header
        check_health
        check_containers
        check_resources
        check_recent_errors
        check_metrics

        echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "Press ${RED}Ctrl+C${NC} to exit | Refreshing every 5 seconds..."

        sleep 5
    done
}

# Trap Ctrl+C
trap 'echo -e "\n${GREEN}Monitoring stopped.${NC}"; exit 0' INT

# Run main function
main