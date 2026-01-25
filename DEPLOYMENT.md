# Luanti Player Position Tracker - Production Deployment Guide

This guide provides step-by-step instructions for deploying the Luanti Position Tracker on a production server.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Configuration](#configuration)
- [Service Management](#service-management)
- [Updating](#updating)
- [Troubleshooting](#troubleshooting)
- [Backup and Restore](#backup-and-restore)

## Prerequisites

### System Requirements

- **Operating System**: Ubuntu 20.04+ or Debian 11+
- **RAM**: Minimum 2GB (4GB recommended)
- **Disk Space**: 5GB minimum
- **Network**: Ports 5000, 5432, 8080, 30000-30009 available

### Required Packages

The deployment script will automatically install:
- PostgreSQL 12+ with PostGIS extension
- Python 3.8+
- Luanti game server (via Snap)
- Build tools for map renderer

## Quick Start

### Interactive Installation

For first-time setup with prompts and confirmation:

```bash
# Clone the repository
git clone <repository-url>
cd luanti-position-tracker

# Run interactive deployment
./bin/deploy.sh
```

### Automated Installation (Production)

For non-interactive deployment (CI/CD, remote servers):

```bash
# Clone the repository
git clone <repository-url>
cd luanti-position-tracker

# Run automated deployment
./bin/deploy.sh --auto --world production_world
```

### With Custom Configuration

```bash
# Create configuration file
cp config/.env.example /etc/luanti-tracker/production.env

# Edit configuration
nano /etc/luanti-tracker/production.env

# Deploy with custom config
./bin/deploy.sh --auto --config /etc/luanti-tracker/production.env
```

## Detailed Setup

### Step 1: Database Setup

The deployment script automatically:
1. Installs PostgreSQL with PostGIS extension
2. Creates database and user
3. Configures authentication (SCRAM-SHA-256)
4. Imports schema
5. Sets up remote access (configurable)

**Manual Database Setup** (if needed):

```bash
./scripts/setup/postgresql.sh
```

### Step 2: Backend Migration

Migrates Luanti world backends to SQLite3:

```bash
./scripts/server/migrate-backend.sh myworld
```

### Step 3: Map Renderer Setup

Compiles and installs minetestmapper:

```bash
./scripts/setup/mapper.sh myworld
```

### Step 4: Map Hosting

Sets up auto-rendering service and HTTP server:

```bash
./scripts/map/setup-hosting.sh myworld
```

## Configuration

### Environment Variables

Edit `.env` file in project root:

```bash
# Database Configuration
DB_HOST=localhost
DB_NAME=luanti_db
DB_USER=luanti
DB_PASS=your_secure_password_here
DB_PORT=5432

# Project Configuration
PROJECT_DIR=/home/username/luanti-position-tracker
WORLD_NAME=myworld

# Server Configuration
FLASK_PORT=5000
LUANTI_PORT=30000
MAP_SERVER_PORT=8080

# Map Rendering
MAP_RENDER_INTERVAL=15
```

### Security Recommendations

1. **Change Default Passwords**
   ```bash
   # Generate secure password
   openssl rand -base64 32
   
   # Update .env file
   nano .env
   ```

2. **Restrict PostgreSQL Access**
   
   Edit `/etc/postgresql/*/main/pg_hba.conf`:
   ```
   # Instead of 0.0.0.0/0, use specific subnet
   host    all             all             10.0.0.0/24             scram-sha-256
   ```

3. **Configure Firewall**
   ```bash
   # Allow only specific IPs for PostgreSQL
   sudo ufw delete allow 5432/tcp
   sudo ufw allow from 10.0.0.0/24 to any port 5432
   ```

4. **Enable HTTPS** (for production)
   ```bash
   # Install Nginx with Let's Encrypt
   sudo apt install nginx certbot python3-certbot-nginx
   
   # Configure reverse proxy for Flask server
   # See Nginx configuration example below
   ```

## Service Management

### Systemd Services

The deployment creates three systemd services:

1. **luanti-tracker-postgresql**: Flask position tracking server
2. **luanti-map-render**: Auto-renders maps every 15 seconds
3. **luanti-map-server**: HTTP server for map.png

### Service Commands

```bash
# Check status
sudo systemctl status luanti-tracker-postgresql
sudo systemctl status luanti-map-render
sudo systemctl status luanti-map-server

# Start/Stop services
sudo systemctl start luanti-tracker-postgresql
sudo systemctl stop luanti-tracker-postgresql

# Restart services
sudo systemctl restart luanti-tracker-postgresql

# View logs
sudo journalctl -u luanti-tracker-postgresql -f
```

### Starting Luanti Server

```bash
# Start server manually
~/sls myworld 30000

# Or create systemd service (recommended for production)
sudo cp scripts/server/start-luanti.sh /usr/local/bin/luanti-start
sudo nano /etc/systemd/system/luanti-server@.service
```

Example systemd service for Luanti:
```ini
[Unit]
Description=Luanti Game Server - %i
After=network.target

[Service]
Type=simple
User=your_username
ExecStart=/usr/local/bin/luanti-start %i 30000 --service
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

## Updating

### Update Deployment

```bash
# Pull latest changes and restart services
./bin/deploy.sh --update
```

### Manual Update Steps

```bash
# 1. Pull latest code
git pull

# 2. Update Python dependencies
source venv/bin/activate
pip install --upgrade -r requirements.txt

# 3. Update mod
cp -r mod/* ~/snap/luanti/common/.minetest/mods/position_tracker/

# 4. Restart services
sudo systemctl restart luanti-tracker-postgresql
sudo systemctl restart luanti-map-render
sudo systemctl restart luanti-map-server
```

## Troubleshooting

### Check Deployment Status

```bash
./bin/deploy.sh --status
```

### Common Issues

#### 1. Port Already in Use

```bash
# Check what's using port 5000
sudo lsof -i :5000

# Kill process
sudo kill -9 <PID>
```

#### 2. Database Connection Failed

```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# Test connection
PGPASSWORD=your_password psql -U luanti -d luanti_db -c "SELECT 1;"

# Check pg_hba.conf
sudo cat /etc/postgresql/*/main/pg_hba.conf | grep scram-sha-256
```

#### 3. Service Won't Start

```bash
# View full logs
sudo journalctl -u luanti-tracker-postgresql -n 100 --no-pager

# Check file permissions
ls -la /home/username/luanti-position-tracker/src/server.py

# Verify virtual environment
source venv/bin/activate
python --version
pip list | grep psycopg2
```

#### 4. Map Not Rendering

```bash
# Check mapper executable
ls -la ~/minetest-mapper/minetestmapper

# Check map render service
sudo systemctl status luanti-map-render
sudo journalctl -u luanti-map-render -n 50

# Test manual render
./scripts/map/render.sh myworld
```

## Backup and Restore

### Database Backup

```bash
# Backup database
pg_dump -U luanti -d luanti_db > backup_$(date +%Y%m%d).sql

# Automated backup script
echo "0 2 * * * pg_dump -U luanti -d luanti_db > /backups/luanti_$(date +\%Y\%m\%d).sql" | crontab -
```

### Restore Database

```bash
# Drop and recreate database
sudo -u postgres psql <<EOF
DROP DATABASE luanti_db;
CREATE DATABASE luanti_db;
GRANT ALL PRIVILEGES ON DATABASE luanti_db TO luanti;
EOF

# Restore from backup
psql -U luanti -d luanti_db < backup_20260125.sql
```

### World Backup

```bash
# Backup Luanti world
tar -czf world_backup_$(date +%Y%m%d).tar.gz \
  ~/snap/luanti/common/.minetest/worlds/myworld

# Restore world
tar -xzf world_backup_20260125.tar.gz -C ~/snap/luanti/common/.minetest/worlds/
```

## Monitoring

### Health Checks

```bash
# Check Flask server
curl http://localhost:5000/

# Check position logging
curl -X POST http://localhost:5000/position \
  -H "Content-Type: application/json" \
  -d '{"player":"test","pos":{"x":1,"y":2,"z":3}}'

# Check database
PGPASSWORD=your_password psql -U luanti -d luanti_db \
  -c "SELECT COUNT(*) FROM player_traces;"
```

### Performance Monitoring

```bash
# Watch service logs in real-time
sudo journalctl -u luanti-tracker-postgresql -f

# Monitor database connections
psql -U luanti -d luanti_db -c "SELECT * FROM pg_stat_activity;"

# Check system resources
htop
```

## Security Hardening

1. **SSH Key Authentication Only**
2. **Fail2ban for SSH Protection**
3. **Regular Security Updates**
4. **Database User Restrictions**
5. **HTTPS for Web Services**
6. **Regular Backups**

## Support

For issues and questions:
- Check logs: `sudo journalctl -u luanti-tracker-postgresql`
- Review [README.md](README.md)
- Run: `./bin/deploy.sh --status`
