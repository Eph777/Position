# Automated Setup Scripts

This directory contains automated setup scripts to simplify the deployment process.

## Available Scripts

### PostgreSQL Setup
```bash
chmod +x setup_postgresql.sh
./setup_postgresql.sh
```

**What it does:**
- Updates system packages
- Installs PostgreSQL, Python, Git, and Snap
- Configures PostgreSQL database with user `luanti` and password `postgres123`
- Sets up Python virtual environment and installs dependencies
- Installs Luanti server via Snap
- Downloads Minetest Game content
- Configures and installs the position tracker mod
- Creates and starts systemd service
- Configures firewall rules
- Creates Luanti server start script

## Prerequisites

1. **Fresh Ubuntu 20.04+ server**
2. **Regular user with sudo privileges** (do NOT run as root)
3. **Position folder uploaded to `~/luanti-qgis`** before running the script

## Usage

1. Upload the Position folder to your server:
   ```bash
   scp -r /path/to/Position your_user@your_server_ip:~/
   ```

2. Connect to your server:
   ```bash
   ssh your_user@your_server_ip
   ```

3. Navigate to the Position directory:
   ```bash
   cd ~/Position
   ```

4. Make the script executable and run it:
   ```bash
   chmod +x setup_postgresql.sh
   ./setup_postgresql.sh
   ```

5. Follow the on-screen prompts

## After Installation

Once the script completes:

1. **Test the Flask server:**
   ```bash
   curl http://localhost:5000/
   ```

2. **Test position logging:**
   ```bash
   curl -X POST http://localhost:5000/position \
     -H "Content-Type: application/json" \
     -d '{"player":"test","pos":{"x":1,"y":2,"z":3}}'
   ```

3. **Verify database:**
   
   ```bash
   PGPASSWORD=postgres123 psql -U luanti -d luanti_db -c "SELECT * FROM player_traces;"
   ```

4. **Start Luanti server:**
   ```bash
   ~/start-luanti-server.sh
   ```

5. **Connect from your Luanti client** using your server's IP address and port 30000

## Default Credentials

### PostgreSQL
- Database: `luanti_db`
- User: `luanti`
- Password: `postgres123`

> [!WARNING]
> These are development passwords. Change them for production use!

## Troubleshooting

If the script fails:

1. **Check the error message** - the script will stop at the first error
2. **Ensure you have sudo privileges**
3. **Verify the Position folder is in ~/Position**
4. **Check system logs:**
   ```bash
   sudo journalctl -u luanti-tracker-postgresql -n 50
   ```

## Manual Setup

If you prefer manual setup, refer to:
- [SETUP_GUIDE.md](SETUP_GUIDE.md) for MySQL
- [SETUP_GUIDE_POSTGRESQL.md](SETUP_GUIDE_POSTGRESQL.md) for PostgreSQL
