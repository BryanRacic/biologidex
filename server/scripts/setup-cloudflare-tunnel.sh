#!/bin/bash
# BiologiDex Cloudflare Tunnel Setup Script
# Sets up secure tunnel for exposing local server to internet

set -euo pipefail

# Configuration
TUNNEL_NAME="${TUNNEL_NAME:-biologidex-tunnel}"
DOMAIN="${DOMAIN:-biologidex.example.com}"
CONFIG_DIR="/etc/cloudflared"
SERVICE_NAME="cloudflared"
LOG_FILE="/var/log/cloudflared.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

# Install cloudflared
install_cloudflared() {
    log "Installing cloudflared..."

    # Detect OS and architecture
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            error "Unsupported architecture: $ARCH"
            ;;
    esac

    # Download and install cloudflared
    if ! command -v cloudflared &> /dev/null; then
        DOWNLOAD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-${OS}-${ARCH}"

        if [[ "$OS" == "linux" ]]; then
            # Download the binary
            wget -q --show-progress -O /tmp/cloudflared "$DOWNLOAD_URL"
            chmod +x /tmp/cloudflared
            mv /tmp/cloudflared /usr/local/bin/

            # Verify installation
            if cloudflared version; then
                log "cloudflared installed successfully"
            else
                error "Failed to install cloudflared"
            fi
        else
            error "This script currently supports Linux only"
        fi
    else
        log "cloudflared is already installed"
        cloudflared version
    fi
}

# Authenticate with Cloudflare
authenticate_cloudflare() {
    log "Authenticating with Cloudflare..."

    # Check if already authenticated
    if [ -f "$CONFIG_DIR/cert.pem" ]; then
        info "Already authenticated with Cloudflare"
        read -p "Do you want to re-authenticate? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    fi

    # Create config directory
    mkdir -p "$CONFIG_DIR"

    # Authenticate
    info "Please login to your Cloudflare account in the browser that opens..."
    cloudflared tunnel login

    if [ -f "$HOME/.cloudflared/cert.pem" ]; then
        mv "$HOME/.cloudflared/cert.pem" "$CONFIG_DIR/"
        log "Authentication successful"
    else
        error "Authentication failed"
    fi
}

# Create tunnel
create_tunnel() {
    log "Creating Cloudflare tunnel..."

    # Check if tunnel already exists
    if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
        info "Tunnel '$TUNNEL_NAME' already exists"
        read -p "Do you want to delete and recreate it? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cloudflared tunnel delete "$TUNNEL_NAME"
        else
            return
        fi
    fi

    # Create new tunnel
    cloudflared tunnel create "$TUNNEL_NAME"

    # Get tunnel ID
    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')

    if [ -z "$TUNNEL_ID" ]; then
        error "Failed to create tunnel"
    fi

    log "Tunnel created with ID: $TUNNEL_ID"

    # Move credentials to config directory
    if [ -f "$HOME/.cloudflared/${TUNNEL_ID}.json" ]; then
        mv "$HOME/.cloudflared/${TUNNEL_ID}.json" "$CONFIG_DIR/"
    fi
}

# Configure tunnel
configure_tunnel() {
    log "Configuring tunnel..."

    # Get tunnel ID if not set
    if [ -z "${TUNNEL_ID:-}" ]; then
        TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    fi

    # Create configuration file
    cat > "$CONFIG_DIR/config.yml" <<EOF
# Cloudflare Tunnel Configuration for BiologiDex
tunnel: $TUNNEL_ID
credentials-file: $CONFIG_DIR/${TUNNEL_ID}.json

# Logging
loglevel: info
logfile: $LOG_FILE

# Metrics server (for monitoring)
metrics: 127.0.0.1:2000

# Ingress rules
ingress:
  # API endpoints
  - hostname: api.$DOMAIN
    service: http://localhost:8000
    originRequest:
      connectTimeout: 30s
      noTLSVerify: false
      keepAliveConnections: 1024
      keepAliveTimeout: 90s
      httpHostHeader: api.$DOMAIN
      originServerName: api.$DOMAIN

  # Admin panel (with IP restrictions)
  - hostname: admin.$DOMAIN
    service: http://localhost:8000
    path: /admin/*
    originRequest:
      connectTimeout: 30s
      access:
        required: true
        teamName: "biologidex-admins"

  # API documentation
  - hostname: docs.$DOMAIN
    service: http://localhost:8000
    path: /api/docs/*

  # Static files (if not using CDN)
  - hostname: static.$DOMAIN
    service: http://localhost:80
    path: /static/*

  # Media files (if not using cloud storage)
  - hostname: media.$DOMAIN
    service: http://localhost:80
    path: /media/*

  # Grafana monitoring (optional)
  - hostname: monitoring.$DOMAIN
    service: http://localhost:3000
    originRequest:
      access:
        required: true
        teamName: "biologidex-admins"

  # Main domain
  - hostname: $DOMAIN
    service: http://localhost:8000

  # Catch-all rule
  - service: http_status:404
EOF

    log "Tunnel configuration created at $CONFIG_DIR/config.yml"

    # Validate configuration
    if cloudflared tunnel ingress validate "$CONFIG_DIR/config.yml"; then
        log "Configuration is valid"
    else
        error "Configuration validation failed"
    fi
}

# Configure DNS
configure_dns() {
    log "Configuring DNS..."

    info "Please add the following CNAME records to your DNS:"
    echo
    echo "  api.$DOMAIN    -> $TUNNEL_ID.cfargotunnel.com"
    echo "  admin.$DOMAIN  -> $TUNNEL_ID.cfargotunnel.com"
    echo "  docs.$DOMAIN   -> $TUNNEL_ID.cfargotunnel.com"
    echo "  static.$DOMAIN -> $TUNNEL_ID.cfargotunnel.com"
    echo "  media.$DOMAIN  -> $TUNNEL_ID.cfargotunnel.com"
    echo "  $DOMAIN        -> $TUNNEL_ID.cfargotunnel.com"
    echo
    echo "Or run this command to automatically configure DNS (requires DNS API access):"
    echo "  cloudflared tunnel route dns $TUNNEL_NAME $DOMAIN"
    echo "  cloudflared tunnel route dns $TUNNEL_NAME api.$DOMAIN"
    echo "  cloudflared tunnel route dns $TUNNEL_NAME admin.$DOMAIN"
    echo

    read -p "Do you want to automatically configure DNS? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN" || warning "Failed to configure DNS for $DOMAIN"
        cloudflared tunnel route dns "$TUNNEL_NAME" "api.$DOMAIN" || warning "Failed to configure DNS for api.$DOMAIN"
        cloudflared tunnel route dns "$TUNNEL_NAME" "admin.$DOMAIN" || warning "Failed to configure DNS for admin.$DOMAIN"
        cloudflared tunnel route dns "$TUNNEL_NAME" "docs.$DOMAIN" || warning "Failed to configure DNS for docs.$DOMAIN"
        cloudflared tunnel route dns "$TUNNEL_NAME" "static.$DOMAIN" || warning "Failed to configure DNS for static.$DOMAIN"
        cloudflared tunnel route dns "$TUNNEL_NAME" "media.$DOMAIN" || warning "Failed to configure DNS for media.$DOMAIN"
        cloudflared tunnel route dns "$TUNNEL_NAME" "monitoring.$DOMAIN" || warning "Failed to configure DNS for monitoring.$DOMAIN"
    fi
}

# Create systemd service
create_systemd_service() {
    log "Creating systemd service..."

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Cloudflare Tunnel for BiologiDex
After=network.target

[Service]
Type=notify
User=cloudflared
Group=cloudflared
ExecStart=/usr/local/bin/cloudflared tunnel --config $CONFIG_DIR/config.yml run
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cloudflared
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

    # Create cloudflared user if it doesn't exist
    if ! id "cloudflared" &>/dev/null; then
        useradd -r -s /bin/false -d /var/lib/cloudflared cloudflared
    fi

    # Set proper permissions
    chown -R cloudflared:cloudflared "$CONFIG_DIR"
    chmod 600 "$CONFIG_DIR"/*.json
    chmod 644 "$CONFIG_DIR/config.yml"

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}.service"

    log "Systemd service created and enabled"
}

# Start tunnel
start_tunnel() {
    log "Starting Cloudflare tunnel..."

    systemctl start "${SERVICE_NAME}.service"

    # Wait for service to start
    sleep 3

    # Check status
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        log "Cloudflare tunnel started successfully"
        systemctl status "${SERVICE_NAME}.service" --no-pager
    else
        error "Failed to start Cloudflare tunnel"
        journalctl -u "${SERVICE_NAME}.service" --no-pager -n 50
    fi
}

# Test tunnel
test_tunnel() {
    log "Testing tunnel connectivity..."

    # Wait for DNS propagation
    info "Waiting 30 seconds for DNS propagation..."
    sleep 30

    # Test each endpoint
    endpoints=(
        "https://$DOMAIN/api/v1/health/"
        "https://api.$DOMAIN/api/v1/health/"
        "https://docs.$DOMAIN/api/docs/"
    )

    for endpoint in "${endpoints[@]}"; do
        info "Testing $endpoint..."
        if curl -s -o /dev/null -w "%{http_code}" "$endpoint" | grep -q "200\|301\|302"; then
            log "✓ $endpoint is accessible"
        else
            warning "✗ $endpoint is not accessible yet"
        fi
    done
}

# Show summary
show_summary() {
    echo
    echo "========================================"
    echo "   Cloudflare Tunnel Setup Complete"
    echo "========================================"
    echo
    echo "Tunnel Name: $TUNNEL_NAME"
    echo "Tunnel ID: $TUNNEL_ID"
    echo "Domain: $DOMAIN"
    echo
    echo "Accessible URLs:"
    echo "  - https://$DOMAIN"
    echo "  - https://api.$DOMAIN"
    echo "  - https://admin.$DOMAIN"
    echo "  - https://docs.$DOMAIN"
    echo "  - https://static.$DOMAIN"
    echo "  - https://media.$DOMAIN"
    echo "  - https://monitoring.$DOMAIN"
    echo
    echo "Service Management:"
    echo "  - Start:   systemctl start $SERVICE_NAME"
    echo "  - Stop:    systemctl stop $SERVICE_NAME"
    echo "  - Restart: systemctl restart $SERVICE_NAME"
    echo "  - Status:  systemctl status $SERVICE_NAME"
    echo "  - Logs:    journalctl -u $SERVICE_NAME -f"
    echo
    echo "Configuration Files:"
    echo "  - Tunnel Config: $CONFIG_DIR/config.yml"
    echo "  - Credentials:   $CONFIG_DIR/${TUNNEL_ID}.json"
    echo "  - Service:       /etc/systemd/system/${SERVICE_NAME}.service"
    echo
    echo "Monitoring:"
    echo "  - Metrics available at: http://localhost:2000/metrics"
    echo
}

# Main setup process
main() {
    log "=== Starting Cloudflare Tunnel Setup ==="

    # Check prerequisites
    check_root

    # Get domain from user if not set
    if [ "$DOMAIN" == "biologidex.example.com" ]; then
        read -p "Enter your domain name (e.g., biologidex.com): " user_domain
        if [ -n "$user_domain" ]; then
            DOMAIN="$user_domain"
        else
            error "Domain name is required"
        fi
    fi

    # Run setup steps
    install_cloudflared
    authenticate_cloudflare
    create_tunnel
    configure_tunnel
    configure_dns
    create_systemd_service
    start_tunnel
    test_tunnel
    show_summary

    log "=== Setup Complete ==="
}

# Run main function
main "$@"