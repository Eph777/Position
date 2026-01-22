# QGIS Integration Guide - Player Position Visualization

This guide shows you how to connect QGIS 3.44 to your PostgreSQL database to visualize player positions from your Luanti server.

## Overview

QGIS can connect directly to PostgreSQL and display player positions as points on a map, allowing you to:
- Visualize player movement patterns
- Create heat maps of popular areas
- Analyze player trajectories over time
- Export data to various GIS formats

---

## Prerequisites

- QGIS 3.44 installed on your local machine
- PostgreSQL server with player_traces data
- Network access to your PostgreSQL server (if on remote server)

---

## Part 1: Configure PostgreSQL for Remote Access (If Needed)

> [!NOTE]
> Skip this section if QGIS and PostgreSQL are on the same machine.

### Step 1: Allow Remote Connections

On your **PostgreSQL server**, edit the PostgreSQL configuration:

```bash
# Find your PostgreSQL config
PG_CONF=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW config_file;')
echo $PG_CONF

# Edit postgresql.conf
sudo nano $PG_CONF
```

Find and change:
```
#listen_addresses = 'localhost'
```

To:
```
listen_addresses = '*'
```

Save and exit.

### Step 2: Configure Client Authentication

Edit `pg_hba.conf`:

```bash
# Find pg_hba.conf
PG_HBA=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file;')
echo $PG_HBA

# Edit it
sudo nano $PG_HBA
```

Add this line at the end (replace YOUR_LOCAL_IP with your actual IP or network):

```
# Allow connections from your local machine
host    luanti_db       luanti          YOUR_LOCAL_IP/32        md5

# Or allow from entire subnet (less secure)
host    luanti_db       luanti          192.168.1.0/24          md5
# Or allow from everywhere (least secure, simpler for dynamic IPs)
host    luanti_db       luanti          0.0.0.0/0               md5
```

> [!WARNING]
> For security, only allow specific IPs. Never use `0.0.0.0/0` in production!

### Step 3: Configure Firewall

Allow PostgreSQL port 5432:

```bash
sudo ufw allow 5432/tcp
```

### Step 4: Restart PostgreSQL

```bash
sudo systemctl restart postgresql
```

### Step 5: Test Connection from Local Machine

From your **local machine**:

```bash
PGPASSWORD=postgres123 psql -h YOUR_SERVER_IP -U luanti -d luanti_db -c "SELECT COUNT(*) FROM player_traces;"
```

You should see the count of records.

---

## Part 2: Connect QGIS to PostgreSQL

### Step 1: Open QGIS

Launch QGIS 3.44 on your local machine.

### Step 2: Open the Browser Panel

If not visible, go to **View → Panels → Browser**.

### Step 3: Add PostgreSQL Connection

1. In the **Browser** panel, right-click on **PostgreSQL**
2. Select **New Connection...**

### Step 4: Configure Connection

Fill in the connection details:

**Connection Details:**
- **Name**: `Luanti Position Tracker`
- **Host**: `YOUR_SERVER_IP` (e.g., `88.88.88.88`) or `localhost`
- **Port**: `5432`
- **Database**: `luanti_db`

**Authentication:**
- **Username**: `luanti`
- **Password**: `postgres123`
- ☑ **Store** (check this to save password)

**SSL Mode**: `prefer` or `disable` (for development)

### Step 5: Test Connection

Click **Test Connection** button. You should see:
```
Connection to luanti_db was successful
```

Click **OK** to save.

---

## Part 3: Load Player Position Data

### Step 1: Expand the Connection

In the Browser panel, expand:
```
PostgreSQL → Luanti Position Tracker → luanti_db → public
```

### Step 2: Open DB Manager

1. In the top menu bar, go to **Database → DB Manager**.
2. A new window will open.
3. In the left tree, expand **PostGIS** and select **Luanti Position Tracker**.

### Step 3: Create Layer from Query

1. Click the **SQL Window** button (icon with a wrench/spanner) in the DB Manager toolbar.
2. In the query editor, paste this SQL:

```sql
SELECT 
    id,
    player_name,
    x,
    y,
    z,
    timestamp,
    ST_SetSRID(ST_MakePoint(x, z), 0) AS geom
FROM player_traces
ORDER BY timestamp DESC
```


**Note:** We use SRID 0 because Luanti uses a flat coordinate system (meters), not Latitude/Longitude. If you use 4326, points > 180 will disappear!

3. Click **Execute (F5)** to check if it runs.
4. Check the box **Load as new layer**.
5. Fill in the details:
   - **Column with unique values**: `id`
   - **Geometry column**: `geom`
   - **Layer name**: `Player Positions`
6. Click **Load**.


---

## Part 4: Visualize the Data

### Option A: Simple Points

The layer will appear with default styling. You'll see all player positions as points.

### Option B: Color by Player

1. Right-click the layer → **Properties**
2. Go to **Symbology**
3. Change from **Single Symbol** to **Categorized**
4. **Value**: `player_name`
5. Click **Classify**
6. Click **OK**

Now each player has a different color!

### Option C: Heat Map

1. Right-click the layer → **Duplicate Layer**
2. Right-click the duplicate → **Properties**
3. Go to **Symbology**
4. Change to **Heatmap**
5. Adjust **Radius** to taste (start with 50)
6. Click **OK**

This shows "hot spots" where players spend most time.

### Option D: Trajectory Lines

To show player movement over time:

Create a new SQL layer with this query:

```sql
SELECT 
    player_name,
    ST_MakeLine(
        ST_SetSRID(ST_MakePoint(x, z), 4326) 
        ORDER BY timestamp
    ) AS geom
FROM player_traces
GROUP BY player_name
```

This creates lines showing each player's path.

---

## Part 5: Advanced Visualizations

### Time-based Animation

1. Right-click layer → **Properties** → **Temporal**
2. ☑ **Dynamic Temporal Control**
3. **Configuration**: `Single Field with Date/Time`
4. **Field**: `timestamp`
5. Click **OK**

6. Enable **Temporal Controller** panel: **View → Panels → Temporal Controller**
7. Click the green play button to animate player movement over time!

### Filter by Time Range

Create filtered layer with SQL:

```sql
SELECT 
    id,
    player_name,
    x, y, z,
    timestamp,
    ST_SetSRID(ST_MakePoint(x, z), 4326) AS geom
FROM player_traces
WHERE timestamp > NOW() - INTERVAL '1 hour'
ORDER BY timestamp DESC
```

This shows only positions from the last hour.

### Player Statistics

Create a virtual layer showing player activity:

**Layer → Create Layer → New Virtual Layer**

SQL:
```sql
SELECT 
    player_name,
    COUNT(*) as position_count,
    MIN(timestamp) as first_seen,
    MAX(timestamp) as last_seen
FROM player_traces
GROUP BY player_name
```

---

## Part 6: Export and Share

### Export to Shapefile

1. Right-click layer → **Export → Save Features As...**
2. **Format**: `ESRI Shapefile`
3. **File name**: Choose location
4. Click **OK**

### Export to GeoJSON

1. Right-click layer → **Export → Save Features As...**
2. **Format**: `GeoJSON`
3. **File name**: Choose location
4. Click **OK**

### Create a Map

1. **Project → New Print Layout**
2. Add map, legend, scale bar, etc.
3. **Layout → Export as Image/PDF**

---

## Part 7: Dynamic Map Background (Satellite View)

This section adds a top-down "Game Map" optimized for QGIS that aligns perfectly with your player data.

### Step 1: Install and Run the Mapper

On your server, we need to install the mapper tool and generate the map.

1. **Install the Mapper**:
   ```bash
   ./setup_mapper.sh
   # This compiles minetest-mapper (takes a few minutes)
   ```

2. **Generate the Initial Map**:
   ```bash
   ./render_map.sh
   # key output: ~/Position/map_output/map.png AND map.pgw
   ```

3. **CRITICAL: Download the Map to your Computer**:
   The map is a **file**, not a database entry. You must download it to your local machine to see it in QGIS.
   
   Open a terminal on your **local computer** (not the server) and run:
   ```bash
   # Replace YOUR_SERVER_IP with your actual IP, e.g. 88.88.88.88
   scp -r root@YOUR_SERVER_IP:~/Position/map_output ./
   ```
   You will now have a `map_output` folder on your computer containing `map.png`.

### Step 2: Define Custom CRS in QGIS

Luanti uses a flat coordinate system (1 node = 1 meter), which doesn't match standard Lat/Lon. We must tell QGIS how to interpret it.

1. Go to **Settings → Custom Projections...**
2. Click **+** to add a new CRS.
3. **Name**: `Luanti World`
4. **Format**: `WKT` (Recommended) or `Proj String`
5. **Parameters**:
   Enter this Proj String:
   ```
   +proj=ortho +lat_0=0 +lon_0=0 +x_0=0 +y_0=0 +a=6371000 +b=6371000 +units=m +no_defs
   ```
6. Click **Validate** and **OK**.

### Step 3: Import the Map (Raster Layer)

1. **Project → Properties → CRS**: Search for your `Luanti World` CRS and select it. Apply.
2. **Layer → Add Layer → Add Raster Layer...**
3. Browse to the `map_output/map.png` file you downloaded.
4. Click **Add**.

**Important**: Because we generated a `.pgw` file alongside it, QGIS automatically places it at the exact coordinates!
*   **Verify**: Hover over the center of the map. Coordinates should be near `0,0`.
*   **Layer Order**: Make sure `map.png` is at the **bottom** of your Layers list, so the player dots appear on top of it.

### Step 4: Real-Time Auto-Refresh

Now that you have the background, let's make the player dots move live!

1. **Add the Optimized View**:
   Instead of the raw table, add the view we created:
   ```sql
   SELECT 
       id, player_name, x, y, z, timestamp,
       ST_SetSRID(ST_MakePoint(x, z), 0) AS geom 
   FROM view_live_positions
   ```
   *(Note: SRID 0 is often used for generic cartesian, or use a custom ID matches your Custom CRS)*

2. **Enable Auto-Update**:
   1. Right-click the `view_live_positions` layer.
   2. Select **Properties**.
   3. Go to the **Rendering** tab.
   4. Check ☑ **Refresh layer at interval**.
   5. Set to **2.0 seconds**.
   6. Click **OK**.

### Step 5: Real-Time Map Sync (HTTP)

To have the map update automatically every 15 seconds without creating a new file layer manually:

1.  **Set up the Hosting Service (Server-side)**:
    Run this new script on your server:
    ```bash
    ./setup_map_hosting.sh
    ```
    This does two things:
    - Starts a background loop that re-renders the map every 15 seconds.
    - Starts a lightweight Web Server on port **8080**.

2.  **Add HTTP Layer in QGIS**:
    1.  Go to **Layer → Add Layer → Add Raster Layer...**
    2.  **Source Type**: Select `Protocol: HTTP(W), HTTPS, FTP...`
    3.  **Type**: `HTTP/HTTPS/FTP`
    4.  **URL**: `http://YOUR_SERVER_IP:8080/map.png`
    5.  Click **Add**.

3.  **Set Auto-Refresh**:
    1.  Right-click the new `map` layer.
    2.  **Properties** → **Rendering**.
    3.  Check **Refresh layer at interval**.
    4.  Set to **15 seconds** (matching your server render time).

Now QGIS will re-download the map image every 15 seconds, keeping your Mission Control view perfectly in sync with the live game world!

---

## Resources

- **QGIS Documentation**: https://docs.qgis.org/
- **PostGIS Functions**: https://postgis.net/docs/reference.html
- **PostgreSQL Spatial**: https://www.postgresql.org/docs/current/functions-geometry.html
