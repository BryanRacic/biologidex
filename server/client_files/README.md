# Client Files Directory

This directory contains the exported Godot web client files served by nginx.

## Contents

After running `./scripts/export-to-prod.sh`, this directory will contain:
- `index.html` - Main entry point
- `index.wasm` - WebAssembly binary
- `index.pck` - Game data package
- `index.js` - JavaScript loader
- PWA assets (manifest, service worker, icons)

## Deployment

To deploy a new version:
```bash
cd server
./scripts/export-to-prod.sh
```

## Nginx Configuration

This directory is mounted in the nginx container and served at the root path `/`.

See `nginx/nginx.conf` for the complete configuration.

## Backups

Previous deployments are automatically backed up to `client_files_backup/` with timestamps.
