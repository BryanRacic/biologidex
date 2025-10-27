#!/bin/bash
# Reset database for BiologiDex when password is incorrect

echo "=== BiologiDex Database Reset Script ==="
echo "WARNING: This will DELETE all database data!"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "ERROR: .env file not found!"
    exit 1
fi

# Get database credentials from .env
DB_USER=$(grep "^DB_USER=" .env | cut -d'=' -f2 || echo "biologidex")
DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d'=' -f2)
DB_NAME=$(grep "^DB_NAME=" .env | cut -d'=' -f2 || echo "biologidex")

echo "Current database configuration:"
echo "  DB_NAME: $DB_NAME"
echo "  DB_USER: $DB_USER"
echo "  DB_PASSWORD: [hidden]"
echo ""

read -p "Are you sure you want to reset the database? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "1. Stopping all services..."
docker-compose -f docker-compose.production.yml down

echo ""
echo "2. Removing database volume..."
docker-compose -f docker-compose.production.yml down -v

echo ""
echo "3. Starting only the database service..."
docker-compose -f docker-compose.production.yml up -d db

echo ""
echo "4. Waiting for database to initialize (15 seconds)..."
sleep 15

echo ""
echo "5. Testing database connection..."
if PGPASSWORD="$DB_PASSWORD" docker-compose -f docker-compose.production.yml exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" 2>/dev/null >/dev/null; then
    echo "✓ Database reset successful!"
    echo ""
    echo "Now you can run:"
    echo "  ./restart_with_optional_services.sh"
    echo ""
    echo "To apply Django migrations:"
    echo "  docker-compose -f docker-compose.production.yml exec web python manage.py migrate"
else
    echo "✗ Database connection still failing!"
    echo ""
    echo "Please check your .env file and ensure DB_PASSWORD is set correctly."
fi