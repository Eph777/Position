-- PostgreSQL Schema for Luanti Player Position Tracker
-- This schema stores player position traces with timestamps
-- AND manages teams, persistent player state, and inventory

-- Extension: Enable PostGIS for spatial queries
CREATE EXTENSION IF NOT EXISTS postgis;

-- 1. Trace Tables (Legacy/History Tracking)
CREATE TABLE IF NOT EXISTS player_traces (
    id SERIAL PRIMARY KEY,
    player_name VARCHAR(100) NOT NULL,
    x DOUBLE PRECISION NOT NULL,
    y DOUBLE PRECISION NOT NULL,
    z DOUBLE PRECISION NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS player_traces_archive (
    id SERIAL PRIMARY KEY,
    player_name VARCHAR(100) NOT NULL,
    x DOUBLE PRECISION NOT NULL,
    y DOUBLE PRECISION NOT NULL,
    z DOUBLE PRECISION NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_player_traces_archive_name_time ON player_traces_archive(player_name, timestamp);

-- 2. Team Management
CREATE TABLE IF NOT EXISTS teams (
    team_id SERIAL PRIMARY KEY,
    team_name TEXT UNIQUE NOT NULL,
    leader_name TEXT NOT NULL,
    password_hash TEXT NOT NULL
);

-- 3. Player State (Current State & Inventory)
CREATE TABLE IF NOT EXISTS players (
    player_name TEXT PRIMARY KEY,
    team_id INT REFERENCES teams(team_id) ON DELETE SET NULL,
    pos_x DOUBLE PRECISION NOT NULL DEFAULT 0,
    pos_y DOUBLE PRECISION NOT NULL DEFAULT 0,
    pos_z DOUBLE PRECISION NOT NULL DEFAULT 0,
    inventory_data JSONB,
    last_update TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. Visualization Views

-- Legacy View (if needed)
CREATE OR REPLACE VIEW view_live_positions AS
SELECT DISTINCT ON (player_name) 
    id, player_name, x, y, z, timestamp,
    ST_SetSRID(ST_MakePoint(x, z), 4326) AS geom
FROM player_traces
WHERE timestamp > NOW() - INTERVAL '1 seconds'
ORDER BY player_name, timestamp DESC;

-- New Tactical Map View (Joined with Teams)
-- Projects pos_x and pos_z into PostGIS GEOMETRY(POINT, 4326)
CREATE OR REPLACE VIEW v_tactical_map AS
SELECT
    p.player_name,
    p.team_id,
    t.team_name,
    p.pos_x,
    p.pos_y,
    p.pos_z,
    p.last_update,
    ST_SetSRID(ST_MakePoint(p.pos_x, p.pos_z), 4326) AS geom
FROM players p
LEFT JOIN teams t ON p.team_id = t.team_id;
