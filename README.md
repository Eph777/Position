# Luanti Player Position Tracker

A system for tracking and storing player positions from a Luanti (formerly Minetest) game server using **PostgreSQL**.

> [!NOTE]
> This project uses **PostgreSQL** for data storage, leveraging its advanced GIS capabilities (PostGIS) for efficient spatial tracking.

## System Architecture

```
Luanti Game Server (with mod) → Python Flask Server → PostgreSQL Database
```

The system consists of three components:

1. **Luanti Mod** (`mod/`): Tracks player positions every second and sends them to the Flask server
2. **Python Flask Server** (`server.py`): Receives HTTP requests and stores data in PostgreSQL
3. **PostgreSQL Database**: Stores player position traces with timestamps

## Quick Start

### Prerequisites

- Python 3.8+
- PostgreSQL 12+ (with PostGIS extension)
- Luanti game server

### Installation

1. **Clone the repository**:
   ```bash
   cd ~/Position
   ```

2. **Install Python dependencies**:
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   pip install -r requirements.txt
   ```

3. **Set up PostgreSQL database**:
   ```bash
   chmod +x setup_postgresql.sh
   ./setup_postgresql.sh
   ```
   Or follow the manual [SETUP_GUIDE.md](SETUP_GUIDE.md).

4. **Run the Flask server**:
   ```bash
   export $(cat .env | xargs)
   python3 server.py
   ```

### Luanti Mod Installation

1. Copy the `mod` folder to your Luanti mods directory:
   ```bash
   cp -r mod ~/.luanti/mods/position_tracker
   ```

2. Edit `~/.luanti/mods/position_tracker/init.lua` and update `SERVER_URL`:
   ```lua
   local SERVER_URL = "http://your_server_ip:5000/position"
   ```

3. Enable HTTP for the mod in `~/.luanti/minetest.conf`:
   ```ini
   secure.http_mods = position_tracker
   ```

4. Enable the mod in your world's `world.mt` file:
   ```
   load_mod_position_tracker = true
   ```

## Documentation

- **[SETUP_GUIDE.md](SETUP_GUIDE.md)**: Comprehensive setup guide with step-by-step instructions for remote deployment
- **[schema.sql](schema.sql)**: PostgreSQL database schema
- **[.env.example](.env.example)**: Environment variable template

## Usage

Once everything is set up:

1. Start the Flask server (or systemd service on production)
2. Start your Luanti server with the mod enabled
3. Connect with Luanti client and play
4. Player positions are automatically tracked and stored in PostgreSQL

### Querying Data

Connect to PostgreSQL and query player traces:

```bash
psql -U luanti -d luanti_db
```

```sql
-- View recent traces
SELECT * FROM player_traces ORDER BY timestamp DESC LIMIT 10;

-- Count traces by player
SELECT player_name, COUNT(*) as trace_count 
FROM player_traces 
GROUP BY player_name;
```

## API Endpoints

### `GET /`
Health check endpoint.

**Response:**
```json
{"status": "running"}
```

### `POST /position`
Log player position.

**Request:**
```json
{
  "player": "player_name",
  "pos": {
    "x": 10.5,
    "y": 20.0,
    "z": -5.3
  }
}
```

**Response:**
```json
{"status": "success"}
```

## Production Deployment

For production deployment on a remote server:

1. Follow the comprehensive [SETUP_GUIDE.md](SETUP_GUIDE.md)
2. Set up systemd service for automatic startup
3. Configure firewall rules
4. Enable HTTPS with SSL/TLS certificates
5. Set up regular database backups
6. Consider using a production WSGI server (Gunicorn)

## License

This project is open source and available for educational and personal use.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Acknowledgments

- Built for Luanti (formerly Minetest): https://www.luanti.org/
- Uses Flask web framework: https://flask.palletsprojects.com/
- PostgreSQL: https://www.postgresql.org/
