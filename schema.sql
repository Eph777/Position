-- Extension for UUIDs if needed, though Serial is fine for this simple use case
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

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
