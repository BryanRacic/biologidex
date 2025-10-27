# BiologiDex Server Scripts Guide

All operational scripts have been organized in the `scripts/` directory. See `scripts/README.md` for comprehensive documentation.

## Quick Start

### Most Common Operations

**Restart services after configuration changes:**
```bash
./scripts/restart.sh
```

**Check system health:**
```bash
./scripts/diagnose.sh
```

**Monitor system performance:**
```bash
./scripts/monitor.sh
```

## Available Scripts

| Script | Purpose | Use When |
|--------|---------|----------|
| `restart.sh` ⭐ | Restart with health checks | Config changes, troubleshooting |
| `reset_database.sh` | Reset database | Password mismatches, fresh start |
| `setup.sh` | Initial server setup | New server installation |
| `deploy.sh` | Production deployment | Code updates |
| `backup.sh` | Backup database & media | Regular backups, before updates |
| `monitor.sh` | Real-time monitoring | Performance checking |
| `diagnose.sh` | System diagnostics | Troubleshooting |
| `setup-cloudflare-tunnel.sh` | Cloudflare setup | External access |

## Notes

- All scripts are executable and located in `scripts/`
- The main `.env` file must be in the server root directory
- Services gracefully handle missing third-party credentials
- See `scripts/README.md` for detailed documentation

## Environment Variables

Required:
- `DB_PASSWORD`, `DB_USER`, `DB_NAME`
- `REDIS_PASSWORD`
- `SECRET_KEY`

Optional (gracefully disabled if not configured):
- `SENTRY_DSN` - Error tracking
- `OPENAI_API_KEY` - CV identification
- `GCS_BUCKET_NAME` - Cloud storage
- `EMAIL_HOST`, `EMAIL_HOST_USER` - Email

## Troubleshooting

1. **Services won't start**: Run `./scripts/diagnose.sh`
2. **Database errors**: Check `.env` password, run `./scripts/reset_database.sh` if needed
3. **Slow requests**: Normal for health checks, regular API is fast

For complete documentation, see: `scripts/README.md`