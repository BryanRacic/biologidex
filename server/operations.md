# BiologiDex Operations Guide

Complete guide for operating, monitoring, and troubleshooting the BiologiDex production deployment.

## Table of Contents

1. [Nginx Operations](#nginx-operations)
2. [Gunicorn Management](#gunicorn-management)
3. [Prometheus Metrics](#prometheus-metrics)
4. [Cloudflare Tunnel](#cloudflare-tunnel)
5. [Health Checks](#health-checks)
6. [Log Management](#log-management)
7. [Database Operations](#database-operations)
8. [Redis Operations](#redis-operations)
9. [Celery Management](#celery-management)
10. [Troubleshooting Guide](#troubleshooting-guide)

---

## Nginx Operations

### Configuration Management

**Location**: `server/nginx/nginx.conf`

**View current configuration:**
```bash
docker-compose -f docker-compose.production.yml exec nginx cat /etc/nginx/nginx.conf
```

**Test configuration:**
```bash
docker-compose -f docker-compose.production.yml exec nginx nginx -t
```

**Reload configuration without downtime:**
```bash
docker-compose -f docker-compose.production.yml exec nginx nginx -s reload
```

### Nginx Logs

**Access logs:**
```bash
# Real-time access logs
docker-compose -f docker-compose.production.yml logs -f nginx

# Access log file
tail -f /var/log/biologidex/nginx/access.log

# Filter by status code
grep "404" /var/log/biologidex/nginx/access.log
grep "5[0-9][0-9]" /var/log/biologidex/nginx/access.log  # 5xx errors
```

**Error logs:**
```bash
# View error logs
tail -f /var/log/biologidex/nginx/error.log

# Search for specific errors
grep "upstream" /var/log/biologidex/nginx/error.log
```

### Nginx Performance Monitoring

**Check connections:**
```bash
docker-compose -f docker-compose.production.yml exec nginx sh -c 'netstat -an | grep :80 | wc -l'
```

**View nginx status (if status module enabled):**
```bash
curl http://localhost/nginx_status
```

### Common Nginx Issues

| Issue | Solution |
|-------|----------|
| **502 Bad Gateway** | Check if Django app is running: `docker-compose ps web` |
| **504 Gateway Timeout** | Increase proxy timeout in nginx.conf |
| **413 Request Entity Too Large** | Increase `client_max_body_size` in nginx.conf |
| **Connection refused** | Verify upstream server is running and port is correct |

---

## Gunicorn Management

### Configuration

**Location**: `server/gunicorn.conf.py`

**Key settings:**
- Workers: `CPU cores * 2 + 1`
- Timeout: 60 seconds
- Max requests per worker: 1000

### Monitoring Gunicorn Workers

**View worker status:**
```bash
# List all workers
docker-compose -f docker-compose.production.yml exec web ps aux | grep gunicorn

# Check worker memory usage
docker-compose -f docker-compose.production.yml exec web sh -c 'ps aux | grep "gunicorn: worker" | awk "{sum+=\$6} END {print sum/1024 \" MB\"}"'
```

**Worker logs:**
```bash
# View Gunicorn access logs
tail -f /var/log/biologidex/gunicorn-access.log

# View Gunicorn error logs
tail -f /var/log/biologidex/gunicorn-error.log

# Monitor slow requests (>1s)
grep -E "\"[0-9]{4,}\"$" /var/log/biologidex/gunicorn-access.log
```

### Reload Workers

**Graceful reload (zero downtime):**
```bash
docker-compose -f docker-compose.production.yml exec web kill -HUP 1
```

**Hard restart:**
```bash
docker-compose -f docker-compose.production.yml restart web
```

### Performance Tuning

**Adjust worker count:**
```bash
# Edit gunicorn.conf.py or set via environment
export GUNICORN_WORKERS=8
docker-compose -f docker-compose.production.yml up -d web
```

**Monitor worker performance:**
```bash
# Check request rate
docker-compose -f docker-compose.production.yml exec web sh -c 'tail -n 1000 /app/logs/gunicorn-access.log | grep "$(date +"%d/%b/%Y:%H")" | wc -l'
```

---

## Prometheus Metrics

### Accessing Metrics

**View raw metrics:**
```bash
curl http://localhost/metrics/
```

**Available metrics:**
- `django_http_requests_total` - Total HTTP requests
- `django_http_request_duration_seconds` - Request duration histogram
- `api_requests_total` - API-specific requests
- `cv_processing_total` - Computer vision processing jobs
- `celery_tasks_total` - Celery task counts
- `django_db_queries_total` - Database query counts
- `django_cache_operations_total` - Cache operations
- `active_users` - Currently active users
- `total_dex_entries` - Total dex entries in system

### Setting Up Prometheus

**Install Prometheus:**
```bash
# Create prometheus.yml
cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'biologidex'
    static_configs:
      - targets: ['localhost:80']
    metrics_path: '/metrics/'
EOF

# Run Prometheus
docker run -d \
  --name prometheus \
  -p 9090:9090 \
  -v /etc/prometheus:/etc/prometheus \
  prom/prometheus
```

**Query examples in Prometheus:**
```promql
# Request rate (requests per second)
rate(django_http_requests_total[5m])

# Average response time
rate(django_http_request_duration_seconds_sum[5m]) / rate(django_http_request_duration_seconds_count[5m])

# Error rate
sum(rate(django_http_requests_total{status_code=~"5.."}[5m])) / sum(rate(django_http_requests_total[5m]))

# CV processing cost
increase(cv_processing_cost_usd[1h])

# Active Celery tasks
active_celery_tasks
```

### Setting Up Grafana

**Install Grafana:**
```bash
docker run -d \
  --name grafana \
  -p 3000:3000 \
  grafana/grafana
```

**Import dashboard:**
1. Access Grafana at http://localhost:3000 (admin/admin)
2. Add Prometheus data source (http://prometheus:9090)
3. Import dashboard JSON from `server/monitoring/grafana-dashboard.json`

---

## Cloudflare Tunnel

### Initial Setup

**Install cloudflared:**
```bash
# Already installed via setup.sh, or manually:
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb
```

**Authenticate:**
```bash
cloudflared tunnel login
```

**Create tunnel:**
```bash
cloudflared tunnel create biologidex
```

### Configuration

**Create config file:**
```yaml
# /etc/cloudflared/config.yml
tunnel: biologidex
credentials-file: /etc/cloudflared/credentials.json

ingress:
  # API endpoints
  - hostname: api.biologidex.example.com
    service: http://localhost:80
    originRequest:
      noTLSVerify: false
      connectTimeout: 30s

  # Admin panel (optional separate subdomain)
  - hostname: admin.biologidex.example.com
    service: http://localhost:80
    path: /admin/*
    originRequest:
      noTLSVerify: false

  # Catch-all
  - service: http_status:404
```

**Start tunnel:**
```bash
# Test mode
cloudflared tunnel run biologidex

# As a service
cloudflared service install
systemctl start cloudflared
systemctl enable cloudflared
```

### Managing Tunnel

**View tunnel status:**
```bash
cloudflared tunnel info biologidex
```

**List all tunnels:**
```bash
cloudflared tunnel list
```

**View tunnel logs:**
```bash
journalctl -u cloudflared -f
```

**Update DNS:**
```bash
cloudflared tunnel route dns biologidex api.biologidex.example.com
```

### Troubleshooting Cloudflare Tunnel

| Issue | Solution |
|-------|----------|
| **Tunnel offline** | Check `systemctl status cloudflared` |
| **502 errors** | Verify local service is running on specified port |
| **Authentication failed** | Re-run `cloudflared tunnel login` |
| **DNS not resolving** | Check DNS records in Cloudflare dashboard |
| **Slow performance** | Check origin server response time, enable caching |

---

## Health Checks

### Available Endpoints

**1. Comprehensive Health Check:**
```bash
curl http://localhost/api/v1/health/ | jq .
```

Response includes:
- Database connectivity
- Redis availability
- Celery worker status
- Storage accessibility
- Response times for each component

**2. Liveness Check:**
```bash
curl http://localhost/health/
```
Simple check if application is running.

**3. Readiness Check:**
```bash
curl http://localhost/ready/
```
Verifies application is ready to serve traffic.

### Monitoring Health

**Continuous monitoring:**
```bash
# Check every 10 seconds
while true; do
  curl -s http://localhost/api/v1/health/ | jq '.status'
  sleep 10
done
```

**Alert on unhealthy:**
```bash
#!/bin/bash
HEALTH=$(curl -s http://localhost/api/v1/health/ | jq -r '.status')
if [ "$HEALTH" != "healthy" ]; then
  echo "System unhealthy! Check logs."
  # Send alert (email, Slack, etc.)
fi
```

---

## Log Management

### Log Locations

| Component | Location | Purpose |
|-----------|----------|---------|
| Django App | `/var/log/biologidex/app.log` | Application logs |
| Errors | `/var/log/biologidex/error.log` | Error logs only |
| Gunicorn Access | `/var/log/biologidex/gunicorn-access.log` | HTTP requests |
| Gunicorn Error | `/var/log/biologidex/gunicorn-error.log` | Server errors |
| Celery | `/var/log/biologidex/celery.log` | Task processing |
| Nginx Access | `/var/log/biologidex/nginx/access.log` | Proxy requests |
| Nginx Error | `/var/log/biologidex/nginx/error.log` | Proxy errors |

### Viewing Logs

**Real-time log viewing:**
```bash
# All logs from Docker Compose
docker-compose -f docker-compose.production.yml logs -f

# Specific service
docker-compose -f docker-compose.production.yml logs -f web
docker-compose -f docker-compose.production.yml logs -f celery_worker

# Last 100 lines
docker-compose -f docker-compose.production.yml logs --tail=100 web
```

**Search logs:**
```bash
# Find errors
grep ERROR /var/log/biologidex/*.log

# Find by timestamp
grep "2024-10-26 14:" /var/log/biologidex/app.log

# Find slow requests
awk '$NF > 1000' /var/log/biologidex/gunicorn-access.log  # Requests > 1s

# Find failed CV processing
grep "AnalysisJob.*failed" /var/log/biologidex/celery.log
```

### Log Analysis

**Request statistics:**
```bash
# Top 10 slowest endpoints
awk '{print $7, $NF}' /var/log/biologidex/gunicorn-access.log | sort -k2 -rn | head -10

# Request count by endpoint
awk '{print $7}' /var/log/biologidex/gunicorn-access.log | sort | uniq -c | sort -rn | head -20

# Status code distribution
awk '{print $9}' /var/log/biologidex/gunicorn-access.log | sort | uniq -c

# Requests per minute
awk '{print $4}' /var/log/biologidex/gunicorn-access.log | cut -d: -f1-3 | uniq -c
```

---

## Database Operations

### PostgreSQL Management

**Connect to database:**
```bash
# Via Docker
docker-compose -f docker-compose.production.yml exec db psql -U biologidex

# Direct connection
psql -h localhost -U biologidex -d biologidex
```

**Common queries:**
```sql
-- Database size
SELECT pg_database_size('biologidex')/1024/1024 as size_mb;

-- Table sizes
SELECT schemaname,tablename,pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
FROM pg_tables ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 10;

-- Active connections
SELECT count(*) FROM pg_stat_activity;

-- Long running queries
SELECT pid, now() - query_start as duration, query
FROM pg_stat_activity
WHERE state != 'idle' AND now() - query_start > interval '1 minute';

-- Kill long query
SELECT pg_terminate_backend(pid);

-- Check indexes usage
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

### Database Backup

**Manual backup:**
```bash
# Full backup
docker-compose -f docker-compose.production.yml exec db pg_dump -U biologidex biologidex > backup_$(date +%Y%m%d_%H%M%S).sql

# Compressed backup
docker-compose -f docker-compose.production.yml exec db pg_dump -U biologidex -Fc biologidex > backup_$(date +%Y%m%d_%H%M%S).dump

# Backup specific tables
docker-compose -f docker-compose.production.yml exec db pg_dump -U biologidex -t animals_animal -t dex_dexentry biologidex > partial_backup.sql
```

**Restore:**
```bash
# From SQL file
docker-compose -f docker-compose.production.yml exec -T db psql -U biologidex biologidex < backup.sql

# From compressed dump
docker-compose -f docker-compose.production.yml exec -T db pg_restore -U biologidex -d biologidex backup.dump
```

### pgBouncer Connection Pooling

**Check pool status:**
```bash
# Connect to pgBouncer admin
docker-compose -f docker-compose.production.yml exec pgbouncer psql -h localhost -p 6432 -U biologidex pgbouncer

# Show pools
SHOW POOLS;

# Show clients
SHOW CLIENTS;

# Show server connections
SHOW SERVERS;
```

---

## Redis Operations

### Redis Management

**Connect to Redis:**
```bash
# Via Docker
docker-compose -f docker-compose.production.yml exec redis redis-cli

# With authentication
docker-compose -f docker-compose.production.yml exec redis redis-cli -a $REDIS_PASSWORD
```

**Common commands:**
```bash
# Check server info
INFO

# Memory usage
INFO memory

# Check keys
KEYS *
DBSIZE

# Monitor commands in real-time
MONITOR

# Clear cache (careful!)
FLUSHDB

# View specific key
GET cache_key_name
TTL cache_key_name

# Set memory limit
CONFIG SET maxmemory 512mb
```

### Cache Analysis

**Cache hit rate:**
```bash
docker-compose -f docker-compose.production.yml exec redis redis-cli INFO stats | grep keyspace_hits
```

**Find large keys:**
```bash
docker-compose -f docker-compose.production.yml exec redis redis-cli --bigkeys
```

**Memory usage by pattern:**
```bash
docker-compose -f docker-compose.production.yml exec redis redis-cli --memkeys
```

---

## Celery Management

### Worker Management

**View worker status:**
```bash
# List active workers
docker-compose -f docker-compose.production.yml exec celery_worker celery -A biologidex inspect active

# Worker statistics
docker-compose -f docker-compose.production.yml exec celery_worker celery -A biologidex inspect stats

# Registered tasks
docker-compose -f docker-compose.production.yml exec celery_worker celery -A biologidex inspect registered
```

**Control workers:**
```bash
# Shutdown workers gracefully
docker-compose -f docker-compose.production.yml exec celery_worker celery -A biologidex control shutdown

# Cancel specific task
docker-compose -f docker-compose.production.yml exec celery_worker celery -A biologidex control revoke task_id

# Purge all tasks
docker-compose -f docker-compose.production.yml exec celery_worker celery -A biologidex purge

# Scale workers
docker-compose -f docker-compose.production.yml up -d --scale celery_worker=3
```

### Monitor Tasks

**View task queue:**
```bash
# Check queue length
docker-compose -f docker-compose.production.yml exec redis redis-cli LLEN celery

# View failed tasks
docker-compose -f docker-compose.production.yml exec celery_worker celery -A biologidex inspect reserved
```

**Task logs:**
```bash
# Real-time task logs
docker-compose -f docker-compose.production.yml logs -f celery_worker

# Search for specific task
grep "process_analysis_job" /var/log/biologidex/celery.log
```

---

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. Application Won't Start

**Symptoms:** 502 Bad Gateway, containers not running

**Diagnosis:**
```bash
# Check container status
docker-compose -f docker-compose.production.yml ps

# View logs
docker-compose -f docker-compose.production.yml logs web

# Check environment variables
docker-compose -f docker-compose.production.yml config
```

**Solutions:**
- Verify `.env` exists and has all required variables
- Check database connectivity
- Ensure migrations have run
- Verify SECRET_KEY is set

#### 2. High Memory Usage

**Symptoms:** OOM kills, slow performance

**Diagnosis:**
```bash
# Check memory usage
docker stats

# Check Gunicorn workers
ps aux | grep gunicorn

# Check Redis memory
docker-compose -f docker-compose.production.yml exec redis redis-cli INFO memory
```

**Solutions:**
- Reduce Gunicorn workers
- Clear Redis cache: `FLUSHDB`
- Increase swap space
- Scale horizontally

#### 3. Slow API Responses

**Symptoms:** Timeouts, high latency

**Diagnosis:**
```bash
# Check slow queries
docker-compose -f docker-compose.production.yml exec db psql -U biologidex -c "SELECT query, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"

# Check Gunicorn timeout
grep timeout /var/log/biologidex/gunicorn-error.log

# Check CPU usage
top -b -n 1 | head -20
```

**Solutions:**
- Add database indexes
- Implement caching
- Optimize queries (use select_related/prefetch_related)
- Increase worker timeout in gunicorn.conf.py

#### 4. Database Connection Errors

**Symptoms:** "FATAL: too many connections", "could not connect to server"

**Diagnosis:**
```bash
# Check connection count
docker-compose -f docker-compose.production.yml exec db psql -U biologidex -c "SELECT count(*) FROM pg_stat_activity;"

# Check pgBouncer
docker-compose -f docker-compose.production.yml exec pgbouncer psql -h localhost -p 6432 -U biologidex pgbouncer -c "SHOW POOLS;"
```

**Solutions:**
- Increase max_connections in PostgreSQL
- Configure pgBouncer properly
- Use connection pooling in Django (CONN_MAX_AGE)
- Close idle connections

#### 5. Celery Tasks Not Processing

**Symptoms:** Tasks stuck in queue, CV processing not working

**Diagnosis:**
```bash
# Check worker status
docker-compose -f docker-compose.production.yml exec celery_worker celery -A biologidex inspect active

# Check Redis connectivity
docker-compose -f docker-compose.production.yml exec celery_worker redis-cli ping

# View queue
docker-compose -f docker-compose.production.yml exec redis redis-cli LLEN celery
```

**Solutions:**
- Restart Celery workers
- Clear stuck tasks
- Check Redis memory limit
- Verify CELERY_BROKER_URL in environment

#### 6. Static Files Not Loading

**Symptoms:** 404 errors for CSS/JS, broken styling

**Diagnosis:**
```bash
# Check static files directory
ls -la /var/www/biologidex/static/

# Check Nginx configuration
docker-compose -f docker-compose.production.yml exec nginx nginx -t

# Check collectstatic ran
docker-compose -f docker-compose.production.yml exec web python manage.py collectstatic --dry-run
```

**Solutions:**
- Run `collectstatic` command
- Fix Nginx static files path
- Check STATIC_ROOT setting
- Verify volume mounts

### Emergency Procedures

#### Complete System Restart
```bash
# Stop everything
docker-compose -f docker-compose.production.yml down

# Clear volumes (careful - data loss!)
docker volume prune

# Restart
docker-compose -f docker-compose.production.yml up -d

# Check health
curl http://localhost/api/v1/health/
```

#### Rollback Deployment
```bash
# Use deployment script
./scripts/deploy.sh --rollback

# Or manually
git checkout HEAD~1
docker-compose -f docker-compose.production.yml build
docker-compose -f docker-compose.production.yml up -d
```

#### Clear All Caches
```bash
# Redis cache
docker-compose -f docker-compose.production.yml exec redis redis-cli FLUSHALL

# Django cache
docker-compose -f docker-compose.production.yml exec web python manage.py shell -c "from django.core.cache import cache; cache.clear()"
```

#### Emergency Database Backup
```bash
# Quick backup before emergency maintenance
docker-compose -f docker-compose.production.yml exec db pg_dump -U biologidex biologidex | gzip > emergency_backup_$(date +%Y%m%d_%H%M%S).sql.gz
```

---

## Performance Monitoring Checklist

### Daily Checks
- [ ] Check health endpoints
- [ ] Review error logs for anomalies
- [ ] Monitor disk space
- [ ] Check backup completion
- [ ] Review Prometheus metrics

### Weekly Checks
- [ ] Analyze slow queries
- [ ] Review cache hit rates
- [ ] Check SSL certificate expiry
- [ ] Review security logs
- [ ] Test backup restoration

### Monthly Checks
- [ ] Full system performance review
- [ ] Database vacuum and analyze
- [ ] Update dependencies
- [ ] Security audit
- [ ] Capacity planning review

---

## Useful Scripts

### Monitor All Services
```bash
#!/bin/bash
# save as monitor.sh

while true; do
  clear
  echo "=== BiologiDex System Monitor ==="
  echo ""

  # Health check
  echo "Health Status:"
  curl -s http://localhost/api/v1/health/ | jq -r '.status'
  echo ""

  # Container status
  echo "Containers:"
  docker-compose -f docker-compose.production.yml ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}"
  echo ""

  # Database connections
  echo "DB Connections:"
  docker-compose -f docker-compose.production.yml exec -T db psql -U biologidex -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null

  # Redis memory
  echo "Redis Memory:"
  docker-compose -f docker-compose.production.yml exec -T redis redis-cli INFO memory | grep used_memory_human | cut -d: -f2

  # Celery tasks
  echo "Active Celery Tasks:"
  docker-compose -f docker-compose.production.yml exec -T celery_worker celery -A biologidex inspect active 2>/dev/null | grep -c "task"

  sleep 5
done
```

### Quick Diagnostics
```bash
#!/bin/bash
# save as diagnose.sh

echo "Running BiologiDex diagnostics..."
echo ""

# Check services
echo "1. Checking services..."
docker-compose -f docker-compose.production.yml ps

# Check health
echo -e "\n2. Health check..."
curl -s http://localhost/api/v1/health/ | jq .

# Check recent errors
echo -e "\n3. Recent errors (last 10)..."
grep ERROR /var/log/biologidex/*.log | tail -10

# Check disk space
echo -e "\n4. Disk space..."
df -h | grep -E "/$|/var"

# Check memory
echo -e "\n5. Memory usage..."
free -h

# Database status
echo -e "\n6. Database status..."
docker-compose -f docker-compose.production.yml exec -T db psql -U biologidex -c "SELECT pg_database_size('biologidex')/1024/1024 as size_mb;"

echo -e "\nDiagnostics complete!"
```

---

## Contact and Support

For additional support or questions not covered in this guide:

1. Check the logs first - most issues are apparent in logs
2. Review the troubleshooting section
3. Consult the main README.md
4. Create an issue on GitHub with:
   - Error messages
   - Relevant log excerpts
   - Steps to reproduce
   - System environment details

Remember to never share sensitive information like API keys or passwords in support requests!