#!/bin/bash

# BiologiDex Production Setup Script
# This script prepares a fresh Ubuntu server for BiologiDex deployment
# Run with: sudo bash setup.sh

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    log_error "Please run this script with sudo"
    exit 1
fi

log_info "Starting BiologiDex production setup..."

# Update system
log_info "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install essential packages
log_info "Installing essential packages..."
apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    htop \
    net-tools \
    vim \
    ufw \
    fail2ban

# Install Docker
log_info "Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh

    # Add current user to docker group
    usermod -aG docker $SUDO_USER
    log_info "Added $SUDO_USER to docker group"
else
    log_info "Docker already installed"
fi

# Install Docker Compose
log_info "Installing Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
else
    log_info "Docker Compose already installed"
fi

# Install Python and Poetry (for local management scripts)
log_info "Installing Python 3.12..."
add-apt-repository ppa:deadsnakes/ppa -y
apt-get update
apt-get install -y python3.12 python3.12-venv python3.12-dev python3-pip

# Install Poetry
log_info "Installing Poetry..."
if ! command -v poetry &> /dev/null; then
    curl -sSL https://install.python-poetry.org | python3 -
    echo 'export PATH="/root/.local/bin:$PATH"' >> /home/$SUDO_USER/.bashrc
else
    log_info "Poetry already installed"
fi

# Install PostgreSQL client tools
log_info "Installing PostgreSQL client..."
apt-get install -y postgresql-client

# Install Redis tools
log_info "Installing Redis tools..."
apt-get install -y redis-tools

# Install Nginx (optional, if not using Docker Nginx)
log_info "Installing Nginx..."
apt-get install -y nginx

# Install monitoring tools
log_info "Installing monitoring tools..."
apt-get install -y prometheus-node-exporter

# Setup firewall
log_info "Configuring firewall..."
ufw --force enable
ufw allow 22/tcp  # SSH
ufw allow 80/tcp  # HTTP
ufw allow 443/tcp # HTTPS
ufw allow 9090/tcp # Prometheus (restrict to monitoring server IP in production)
ufw allow 3000/tcp # Grafana (restrict to monitoring server IP in production)
ufw reload

# Setup fail2ban
log_info "Configuring fail2ban..."
systemctl enable fail2ban
systemctl start fail2ban

# Create application directories
log_info "Creating application directories..."
mkdir -p /opt/biologidex
mkdir -p /var/log/biologidex
mkdir -p /var/lib/biologidex/media
mkdir -p /var/lib/biologidex/static
mkdir -p /var/lib/biologidex/backups
mkdir -p /etc/biologidex

# Set permissions
chown -R $SUDO_USER:$SUDO_USER /opt/biologidex
chown -R $SUDO_USER:$SUDO_USER /var/log/biologidex
chown -R $SUDO_USER:$SUDO_USER /var/lib/biologidex

# Install Cloudflare Tunnel (optional)
log_info "Installing Cloudflare Tunnel..."
if ! command -v cloudflared &> /dev/null; then
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i cloudflared-linux-amd64.deb
    rm cloudflared-linux-amd64.deb
    log_info "Cloudflare Tunnel installed. Configure with: cloudflared tunnel login"
else
    log_info "Cloudflare Tunnel already installed"
fi

# Setup log rotation
log_info "Configuring log rotation..."
cat > /etc/logrotate.d/biologidex << EOF
/var/log/biologidex/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 640 $SUDO_USER $SUDO_USER
    sharedscripts
    postrotate
        docker exec biologidex-web kill -USR1 1
    endscript
}
EOF

# Setup systemd service for Docker Compose
log_info "Creating systemd service..."
cat > /etc/systemd/system/biologidex.service << EOF
[Unit]
Description=BiologiDex Application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=$SUDO_USER
Group=$SUDO_USER
WorkingDirectory=/opt/biologidex/server
ExecStart=/usr/local/bin/docker-compose -f docker-compose.production.yml up -d
ExecStop=/usr/local/bin/docker-compose -f docker-compose.production.yml down
ExecReload=/usr/local/bin/docker-compose -f docker-compose.production.yml restart

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable biologidex

# Setup backup cron job
log_info "Setting up backup cron job..."
cat > /etc/cron.d/biologidex-backup << EOF
# Backup BiologiDex database daily at 2 AM
0 2 * * * $SUDO_USER /opt/biologidex/server/scripts/backup.sh > /var/log/biologidex/backup.log 2>&1
EOF

# Install additional security tools
log_info "Installing additional security tools..."
apt-get install -y \
    rkhunter \
    chkrootkit \
    aide \
    auditd

# Initialize AIDE
log_info "Initializing AIDE (file integrity monitoring)..."
aideinit

# Create swap file if not exists
log_info "Checking swap configuration..."
if [ ! -f /swapfile ]; then
    log_info "Creating 4GB swap file..."
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
else
    log_info "Swap file already exists"
fi

# Optimize system settings
log_info "Optimizing system settings..."
cat >> /etc/sysctl.conf << EOF

# BiologiDex Production Optimizations
# Network optimizations
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# File system
fs.file-max = 2097152
fs.nr_open = 1048576

# Virtual memory
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF

sysctl -p

# Setup environment file template
log_info "Creating environment file template..."
if [ ! -f /opt/biologidex/server/.env.production ]; then
    cp /opt/biologidex/server/.env.production.example /opt/biologidex/server/.env.production
    log_warning "Please edit /opt/biologidex/server/.env.production with your configuration"
fi

# Final instructions
echo ""
echo "=================================================="
echo -e "${GREEN}BiologiDex production setup complete!${NC}"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. Clone the repository to /opt/biologidex:"
echo "   cd /opt && git clone https://github.com/yourusername/biologidex.git"
echo ""
echo "2. Configure environment variables:"
echo "   cd /opt/biologidex/server"
echo "   cp .env.production.example .env.production"
echo "   nano .env.production"
echo ""
echo "3. Start the application:"
echo "   cd /opt/biologidex/server"
echo "   docker-compose -f docker-compose.production.yml up -d"
echo ""
echo "4. Run database migrations:"
echo "   docker-compose -f docker-compose.production.yml exec web python manage.py migrate"
echo ""
echo "5. Create superuser:"
echo "   docker-compose -f docker-compose.production.yml exec web python manage.py createsuperuser"
echo ""
echo "6. Collect static files:"
echo "   docker-compose -f docker-compose.production.yml exec web python manage.py collectstatic"
echo ""
echo "7. Configure Cloudflare Tunnel (optional):"
echo "   cloudflared tunnel login"
echo "   cloudflared tunnel create biologidex"
echo ""
echo "8. Start the systemd service:"
echo "   systemctl start biologidex"
echo ""
echo "=================================================="
log_warning "Remember to:"
log_warning "- Change all default passwords in .env.production"
log_warning "- Configure SSL certificates"
log_warning "- Set up monitoring and alerting"
log_warning "- Configure backup destinations"
log_warning "- Review and adjust firewall rules for your environment"
echo "=================================================="