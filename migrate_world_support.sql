-- Migration script for adding world_name support to existing databases
-- Run this on existing databases to add world-specific filtering

-- Step 1: Add world_name columns (allows NULL initially for compatibility)
ALTER TABLE player_traces ADD COLUMN IF NOT EXISTS world_name VARCHAR(100);
ALTER TABLE player_traces_archive ADD COLUMN IF NOT EXISTS world_name VARCHAR(100);

-- Step 2: Set default world for existing records (optional)
-- Uncomment the following lines if you want to assign existing data to a specific world
-- UPDATE player_traces SET world_name = 'default' WHERE world_name IS NULL;
-- UPDATE player_traces_archive SET world_name = 'default' WHERE world_name IS NULL;

-- Step 3: Add indexes for world-based queries
CREATE INDEX IF NOT EXISTS idx_player_traces_world ON player_traces(world_name);
CREATE INDEX IF NOT EXISTS idx_player_traces_archive_world ON player_traces_archive(world_name);
CREATE INDEX IF NOT EXISTS idx_player_traces_world_name ON player_traces(world_name, player_name);

-- Step 4: Update the combined view to include world_name
CREATE OR REPLACE VIEW view_live_positions AS
SELECT DISTINCT ON (player_name, world_name) 
    id, player_name, world_name, x, y, z, timestamp,
    ST_SetSRID(ST_MakePoint(x, z), 0) AS geom
FROM player_traces
WHERE timestamp > NOW() - INTERVAL '60 seconds'
ORDER BY player_name, world_name, timestamp DESC;

-- Step 5: Create the dynamic view generation function
CREATE OR REPLACE FUNCTION create_world_view(world_name_param TEXT) RETURNS TEXT AS $$
DECLARE
    view_name TEXT;
    safe_world_name TEXT;
BEGIN
    -- Sanitize world name for use in identifiers (replace special chars with underscore)
    safe_world_name := regexp_replace(world_name_param, '[^a-zA-Z0-9_]', '_', 'g');
    view_name := 'view_live_positions_' || safe_world_name;
    
    EXECUTE format('
        CREATE OR REPLACE VIEW %I AS
        SELECT DISTINCT ON (player_name) 
            id, player_name, world_name, x, y, z, timestamp,
            ST_SetSRID(ST_MakePoint(x, z), 0) AS geom
        FROM player_traces
        WHERE world_name = %L
          AND timestamp > NOW() - INTERVAL ''60 seconds''
        ORDER BY player_name, timestamp DESC
    ', view_name, world_name_param);
    
    RETURN 'Created view: ' || view_name;
END;
$$ LANGUAGE plpgsql;

-- Migration complete!
-- You can now create world-specific views with: SELECT create_world_view('yourworld');
