# Luanti Player Position Tracker

A system for tracking and storing player positions from a Luanti (formerly Minetest) game server using **MySQL** or **PostgreSQL** database.

> [!NOTE]
> This project supports both **MySQL** and **PostgreSQL**. Choose the database that best fits your needs:
> - **MySQL**: [SETUP_GUIDE.md](SETUP_GUIDE.md) - Simpler setup, widely available
> - **PostgreSQL**: [SETUP_GUIDE_POSTGRESQL.md](SETUP_GUIDE_POSTGRESQL.md) - Advanced features, better timezone handling

## System Architecture

```
Luanti Game Server (with mod) → Python Flask Server → MySQL Database
```

The system consists of three components:

1. **Luanti Mod** (`mod/`): Tracks player positions every second and sends them to the Flask server
2. **Python Flask Server** (`server.py`): Receives HTTP requests and stores data in MySQL
3. **MySQL Database**: Stores player position traces with timestamps

## Quick Start

### Prerequisites

- Python 3.8+
- MySQL 5.7+ or 8.0+
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

3. **Set up MySQL database**:
   ```bash
   mysql -u root -p
   ```
   
   Then run:
   ```sql
   CREATE DATABASE luanti_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   CREATE USER 'luanti'@'localhost' IDENTIFIED BY 'luanti123';
   GRANT ALL PRIVILEGES ON luanti_db.* TO 'luanti'@'localhost';
   FLUSH PRIVILEGES;
   EXIT;
   ```

4. **Import database schema**:
   ```bash
   mysql -u luanti -p luanti_db < schema.sql
   ```

5. **Configure environment variables**:
   ```bash
   cp .env.example .env  # For MySQL
   # OR
   cp .env.example.postgresql .env  # For PostgreSQL
   nano .env  # Update with your credentials
   ```

6. **Run the Flask server**:
   ```bash
   export $(cat .env | xargs)
   python3 server.py  # For MySQL
   # OR
   python3 server_postgresql.py  # For PostgreSQL
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

- **[SETUP_GUIDE.md](SETUP_GUIDE.md)**: MySQL setup guide with step-by-step instructions for remote deployment
- **[SETUP_GUIDE_POSTGRESQL.md](SETUP_GUIDE_POSTGRESQL.md)**: PostgreSQL setup guide with step-by-step instructions  
- **[schema.sql](schema.sql)**: MySQL database schema
- **[schema_postgresql.sql](schema_postgresql.sql)**: PostgreSQL database schema
- **[.env.example](.env.example)**: MySQL environment variable template
- **[.env.example.postgresql](.env.example.postgresql)**: PostgreSQL environment variable template

## Usage

Once everything is set up:

1. Start the Flask server (or systemd service on production)
2. Start your Luanti server with the mod enabled
3. Connect with Luanti client and play
4. Player positions are automatically tracked and stored in MySQL

### Querying Data

Connect to MySQL and query player traces:

```bash
mysql -u luanti -p luanti_db
```

```sql
-- View recent traces
SELECT * FROM player_traces ORDER BY timestamp DESC LIMIT 10;

-- Count traces by player
SELECT player_name, COUNT(*) as trace_count 
FROM player_traces 
GROUP BY player_name;

-- Get player positions in a time range
SELECT * FROM player_traces 
WHERE player_name = 'YourName' 
  AND timestamp BETWEEN '2026-01-20 00:00:00' AND '2026-01-20 23:59:59'
ORDER BY timestamp;
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

## Database Schema

```sql
CREATE TABLE player_traces (
    id INT AUTO_INCREMENT PRIMARY KEY,
    player_name VARCHAR(100) NOT NULL,
    x DOUBLE NOT NULL,
    y DOUBLE NOT NULL,
    z DOUBLE NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_player_traces_name_time (player_name, timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

## Production Deployment

For production deployment on a remote server:

1. Follow the comprehensive [SETUP_GUIDE.md](SETUP_GUIDE.md)
2. Set up systemd service for automatic startup
3. Configure firewall rules
4. Enable HTTPS with SSL/TLS certificates
5. Set up regular database backups

## Security

- Never expose MySQL port (3306) to the internet
- Use strong passwords for database users
- Keep `.env` file out of version control
- Consider using a production WSGI server (Gunicorn) instead of Flask development server
- Regularly update all dependencies

## Troubleshooting

### Flask server won't start
```bash
# Check logs
sudo journalctl -u luanti-tracker -n 50

# Verify MySQL is running
sudo systemctl status mysql

# Test database connection
mysql -u luanti -p luanti_db
```

### Luanti mod not sending data
```bash
# Check Luanti logs
cat ~/.luanti/debug.txt | grep position_tracker

# Verify mod is enabled
grep position_tracker ~/.luanti/minetest.conf
```

### No data in database
```bash
# Test API manually
curl -X POST http://localhost:5000/position \
  -H "Content-Type: application/json" \
  -d '{"player":"test","pos":{"x":1,"y":2,"z":3}}'

# Check database
mysql -u luanti -p luanti_db -e "SELECT COUNT(*) FROM player_traces;"
```

For more troubleshooting help, see [SETUP_GUIDE.md](SETUP_GUIDE.md#troubleshooting).

## License

This project is open source and available for educational and personal use.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Acknowledgments

- Built for Luanti (formerly Minetest): https://www.luanti.org/
- Uses Flask web framework: https://flask.palletsprojects.com/
- MySQL database: https://www.mysql.com/
