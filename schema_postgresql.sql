-- PostgreSQL Schema for Luanti Player Position Tracker
-- This schema stores player position traces with timestamps

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

-- Index on player_name and timestamp for faster querying of traces for specific players
CREATE INDEX IF NOT EXISTS idx_player_traces_archive_name_time ON player_traces_archive(player_name, timestamp);

-- Create optimized view for QGIS live tracking (latest position per player)
-- This view allows QGIS to see the latest position of each active player as a spatial layer
CREATE OR REPLACE VIEW view_live_positions AS
SELECT DISTINCT ON (player_name) 
    id, player_name, x, y, z, timestamp,
    ST_SetSRID(ST_MakePoint(x, z), 0) AS geom
FROM player_traces
WHERE timestamp > NOW() - INTERVAL '1 seconds'
ORDER BY player_name, timestamp DESC;
