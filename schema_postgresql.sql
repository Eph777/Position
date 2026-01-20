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

-- Index on player_name and timestamp for faster querying of traces for specific players
CREATE INDEX IF NOT EXISTS idx_player_traces_name_time ON player_traces(player_name, timestamp);
