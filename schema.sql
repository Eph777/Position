-- PostgreSQL Schema for Luanti Tactical Team Management System
-- Enable PostGIS for spatial operations
CREATE EXTENSION IF NOT EXISTS postgis;

-- Table: Teams (Metadata)
CREATE TABLE IF NOT EXISTS teams (
    name VARCHAR(100) PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Table: Players
-- Stores player position, inventory, and team affiliation
CREATE TABLE IF NOT EXISTS players (
    player_name VARCHAR(100) PRIMARY KEY,
    team_name VARCHAR(100) REFERENCES teams(name) ON DELETE CASCADE,
    x DOUBLE PRECISION NOT NULL,
    y DOUBLE PRECISION NOT NULL,
    z DOUBLE PRECISION NOT NULL,
    inventory_json JSONB DEFAULT '{}'::jsonb,
    status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'active'
    last_update TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraint: team_name must NOT be null (every player must try to join a team)
    CONSTRAINT fk_team FOREIGN KEY (team_name) REFERENCES teams(name)
);

-- Indices for performance
CREATE INDEX IF NOT EXISTS idx_players_team ON players(team_name);
CREATE INDEX IF NOT EXISTS idx_players_status ON players(status);

-- Enable Row-Level Security (RLS)
ALTER TABLE players ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Team Isolation
-- A user can only SEE rows where team_name matches their database username.
-- Note: 'current_user' returns the name of the database user.
-- The Table Owner (middleware user) bypasses this by default.
CREATE POLICY team_isolation_policy ON players
    FOR SELECT
    USING (team_name = current_user);

-- PostGIS View: v_tactical_map
-- Projects player positions to Geometry for QGIS visualization.
-- This view effectively inherits RLS from the underlying 'players' table
-- because Views in Postgres (unless defined with security_barrier) check underlying permissions.
-- However, for RLS to apply to the view user, it normally works if the view is just a simple selection.
-- We will rely on the user having SELECT permission on the table OR strict RLS on the table.
-- Best practice: Give SELECT on the View, and the View queries the Table using the invoker's rights.
CREATE OR REPLACE VIEW v_tactical_map AS
SELECT
    player_name,
    team_name,
    status,
    last_update,
    inventory_json,
    -- Create 2D Point (X, Z) - assuming Y is elevation
    ST_SetSRID(ST_MakePoint(x, z), 4326) AS geom
FROM players
WHERE status = 'active'; -- Only show active players on the map

-- Grant usage on schemas and defaults
-- (Specific grants for team users will be handled by Middleware)
