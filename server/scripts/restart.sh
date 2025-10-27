#!/bin/bash
# Restart BiologiDex with all third-party services optional

echo "=== BiologiDex Restart with Optional Services ==="
echo "This script will restart the stack with all third-party services optional"
echo ""

# 1. Check and update .env to disable/skip third-party services
echo "1. Checking .env configuration..."

# Backup current .env
if [ -f .env ]; then
    cp .env .env.backup
    echo "   ✓ Backed up .env to .env.backup"
fi

# Check if DB_PASSWORD is set
if ! grep -q "^DB_PASSWORD=" .env 2>/dev/null; then
    echo "   ⚠ ERROR: DB_PASSWORD not found in .env!"
    echo "     Please add DB_PASSWORD to .env"
    exit 1
elif grep -q "^DB_PASSWORD=secure-database-password" .env 2>/dev/null; then
    echo "   ⚠ WARNING: Using default DB_PASSWORD 'secure-database-password'"
    echo "     For production, please change this to a secure password"
else
    echo "   ✓ DB_PASSWORD is configured"
fi

# Disable Sentry by commenting out the DSN if it has the default placeholder
if grep -q "^SENTRY_DSN=https://your-sentry-dsn@sentry.io/project-id" .env 2>/dev/null; then
    sed -i 's|^SENTRY_DSN=https://your-sentry-dsn@sentry.io/project-id|# SENTRY_DSN= # Disabled - not configured|' .env
    echo "   ✓ Disabled Sentry (placeholder DSN found)"
elif grep -q "^SENTRY_DSN=" .env 2>/dev/null; then
    echo "   ℹ Sentry DSN found - will be handled gracefully if invalid"
else
    echo "   ℹ Sentry not configured"
fi

# Check OpenAI API key
if grep -q "^OPENAI_API_KEY=your-openai-api-key" .env 2>/dev/null; then
    echo "   ⚠ WARNING: OpenAI API key not configured - CV identification will not work!"
    echo "     To enable animal identification, set OPENAI_API_KEY in .env"
elif grep -q "^OPENAI_API_KEY=" .env 2>/dev/null; then
    echo "   ✓ OpenAI API key configured"
else
    echo "   ⚠ OpenAI API key not found - CV identification will not work"
fi

# Check Email configuration
if grep -q "^EMAIL_HOST_USER=your-email@gmail.com" .env 2>/dev/null || \
   ! grep -q "^EMAIL_HOST_USER=" .env 2>/dev/null; then
    echo "   ℹ Email not configured - will use console backend"
else
    echo "   ✓ Email appears to be configured"
fi

# Check GCS configuration
if grep -q "^GCS_BUCKET_NAME=biologidex-media" .env 2>/dev/null && \
   grep -q "^GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json" .env 2>/dev/null; then
    echo "   ℹ GCS not configured (placeholder values) - will use local storage"
elif grep -q "^GCS_BUCKET_NAME=" .env 2>/dev/null; then
    echo "   ✓ GCS appears to be configured"
else
    echo "   ℹ GCS not configured - will use local storage"
fi

# 2. Stop all services
echo ""
echo "2. Stopping all Docker services..."
docker-compose -f docker-compose.production.yml down

# 2a. Check if we need to reset the database (if password mismatch)
echo ""
echo "2a. Checking database connection..."
# Try to connect to existing database if it's running
if docker ps | grep -q server_db_1; then
    echo "   Database container is running, checking connection..."
    DB_USER=$(grep "^DB_USER=" .env | cut -d'=' -f2 || echo "biologidex")
    DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d'=' -f2)
    DB_NAME=$(grep "^DB_NAME=" .env | cut -d'=' -f2 || echo "biologidex")

    if docker exec server_db_1 psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" 2>/dev/null >/dev/null; then
        echo "   ✓ Database connection successful"
    else
        echo "   ⚠ Database connection failed - password mismatch detected"
        echo "   The database was initialized with a different password."
        echo ""
        echo "   Choose an option:"
        echo "   1) Reset database (WARNING: This will DELETE all data)"
        echo "   2) Update .env with the correct password"
        echo "   3) Exit and fix manually"
        echo ""
        read -p "   Enter choice (1-3): " choice

        case $choice in
            1)
                echo "   Resetting database..."
                docker-compose -f docker-compose.production.yml down -v
                echo "   ✓ Database volumes removed. Will recreate with new password."
                ;;
            2)
                echo "   Please edit .env and update DB_PASSWORD to match the existing database"
                echo "   Then run this script again."
                exit 0
                ;;
            3)
                echo "   Exiting. Please fix the database password manually."
                exit 0
                ;;
            *)
                echo "   Invalid choice. Exiting."
                exit 1
                ;;
        esac
    fi
fi

# 3. Ensure directories exist with proper permissions
echo ""
echo "3. Creating required directories..."
mkdir -p logs logs/nginx media static
chmod 777 logs logs/nginx
echo "   ✓ Directories created with proper permissions"

# 4. Rebuild images to pick up the configuration changes
echo ""
echo "4. Rebuilding Docker images with updated configuration..."
docker-compose -f docker-compose.production.yml build web celery_worker

# 5. Start all services
echo ""
echo "5. Starting all services..."
docker-compose -f docker-compose.production.yml up -d

# 6. Wait for services to initialize
echo ""
echo "6. Waiting for services to initialize (25 seconds)..."
sleep 25

# 7. Check service status
echo ""
echo "=== Service Status ==="
docker-compose -f docker-compose.production.yml ps

# 8. Detailed health check
echo ""
echo "=== Health Check ==="
services=(db redis web celery_worker celery_beat nginx pgbouncer)
all_healthy=true

for service in "${services[@]}"; do
    container=$(docker-compose -f docker-compose.production.yml ps -q $service 2>/dev/null)
    if [ -n "$container" ]; then
        status=$(docker inspect $container --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
        health=$(docker inspect $container --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' 2>/dev/null || echo "unknown")

        # Format output
        if [[ "$status" == "running" ]] && ([[ "$health" == "healthy" ]] || [[ "$health" == "no healthcheck" ]]); then
            printf "%-15s ✓ Status: %-10s Health: %s\n" "$service:" "$status" "$health"
        else
            printf "%-15s ✗ Status: %-10s Health: %s\n" "$service:" "$status" "$health"
            all_healthy=false

            # Show last logs for unhealthy services
            if [[ "$status" == "restarting" ]] || [[ "$health" == "unhealthy" ]]; then
                echo "  Last log entries:"
                docker-compose -f docker-compose.production.yml logs --tail 3 $service 2>&1 | sed 's/^/    /'
            fi
        fi
    else
        # celery_beat might not be running if web is unhealthy, which is expected
        if [[ "$service" == "celery_beat" ]]; then
            echo "$service: Not running (depends on web service)"
        else
            echo "$service: Not found"
            all_healthy=false
        fi
    fi
done

# 9. Quick functionality tests
echo ""
echo "=== Functionality Tests ==="

# Redis test
echo -n "Redis connection: "
if docker-compose -f docker-compose.production.yml exec -T redis redis-cli -a "${REDIS_PASSWORD:-defaultpass123}" ping 2>/dev/null | grep -q PONG; then
    echo "✓ Working"
else
    echo "✗ Failed"
fi

# PostgreSQL test
echo -n "PostgreSQL connection: "
DB_USER=$(grep "^DB_USER=" .env | cut -d'=' -f2 || echo "biologidex")
DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d'=' -f2)
DB_NAME=$(grep "^DB_NAME=" .env | cut -d'=' -f2 || echo "biologidex")

if docker-compose -f docker-compose.production.yml exec -T db pg_isready -U "$DB_USER" 2>/dev/null | grep -q "accepting connections"; then
    echo "✓ Accepting connections"

    # Test actual authentication
    echo -n "PostgreSQL authentication: "
    if PGPASSWORD="$DB_PASSWORD" docker-compose -f docker-compose.production.yml exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" 2>/dev/null >/dev/null; then
        echo "✓ Authentication successful"
    else
        echo "✗ Authentication failed"
        echo "  ERROR: Cannot authenticate to database with current credentials"
        echo "  Check that DB_PASSWORD in .env matches the database password"
    fi
else
    echo "✗ Not ready"
fi

# Web API test
echo -n "Web API health: "
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/api/v1/health/ 2>/dev/null)
if [ "$response" = "200" ]; then
    echo "✓ Healthy (HTTP 200)"

    # Show detailed health info
    echo ""
    echo "Detailed health status:"
    curl -s http://localhost:8000/api/v1/health/ | python3 -m json.tool 2>/dev/null | head -20 || echo "Could not parse JSON response"
else
    echo "✗ Not healthy (HTTP $response)"
fi

# Django check
echo ""
echo -n "Django configuration: "
if docker-compose -f docker-compose.production.yml exec -T web python manage.py check --deploy 2>&1 | grep -q "System check identified no issues"; then
    echo "✓ Valid"
else
    echo "⚠ Has warnings (this is normal for local deployment)"
fi

# 10. Check configuration output from containers
echo ""
echo "=== Service Configuration Status ==="
echo "Checking service logs for configuration messages..."
docker-compose -f docker-compose.production.yml logs web 2>&1 | grep -E "(Sentry|Email|OpenAI|Google Cloud Storage|Prometheus)" | tail -10

# 11. Summary
echo ""
echo "=========================================="
if [ "$all_healthy" = true ] && [ "$response" = "200" ]; then
    echo "✅ SUCCESS! All services are running properly!"
    echo ""
    echo "Configuration Summary:"

    # Check OpenAI status
    if docker-compose -f docker-compose.production.yml logs web 2>&1 | tail -50 | grep -q "OpenAI API configured"; then
        echo "  ✓ OpenAI: Configured (CV identification enabled)"
    else
        echo "  ℹ OpenAI: Not configured (CV identification disabled)"
    fi

    # Check Sentry status
    if docker-compose -f docker-compose.production.yml logs web 2>&1 | tail -50 | grep -q "Sentry error tracking enabled"; then
        echo "  ✓ Sentry: Enabled"
    else
        echo "  ℹ Sentry: Disabled"
    fi

    # Check Email status
    if docker-compose -f docker-compose.production.yml logs web 2>&1 | tail -50 | grep -q "Email configured with SMTP"; then
        echo "  ✓ Email: SMTP configured"
    else
        echo "  ℹ Email: Console backend (no emails sent)"
    fi

    # Check Storage
    if docker-compose -f docker-compose.production.yml logs web 2>&1 | tail -50 | grep -q "Google Cloud Storage configured"; then
        echo "  ✓ Storage: Google Cloud Storage"
    else
        echo "  ℹ Storage: Local filesystem"
    fi

    echo ""
    echo "Access your BiologiDex application at:"
    echo "  🌐 Main API: http://localhost/api/v1/"
    echo "  🔗 Direct API: http://localhost:8000/api/v1/"
    echo "  📚 API Documentation: http://localhost/api/docs/"
    echo "  📊 Prometheus Metrics: http://localhost:8000/metrics/"
    echo ""
    echo "Note: Services without credentials will gracefully fall back to:"
    echo "  - Local file storage (instead of GCS)"
    echo "  - Console email output (instead of SMTP)"
    echo "  - No error tracking (if Sentry not configured)"
    echo "  - CV identification disabled (if OpenAI not configured)"
else
    echo "⚠️  Some services may still be starting or need attention"
    echo ""
    echo "Please check the logs for more details:"
    echo "  docker-compose -f docker-compose.production.yml logs web"
    echo "  docker-compose -f docker-compose.production.yml logs celery_worker"
    echo ""
    echo "If services are restarting, it's likely due to missing credentials."
    echo "Check the configuration messages above for details."
fi
echo "=========================================="

echo ""
echo "To monitor logs in real-time:"
echo "  docker-compose -f docker-compose.production.yml logs -f"