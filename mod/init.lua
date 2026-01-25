-- Copyright (C) 2026 Ephraim BOURIAHI
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

-- Configuration
-- The Base URL of the middleware server (Flask app)
local SERVER_BASE_URL = "http://localhost:5000"
local POSITION_URL = SERVER_BASE_URL .. "/position"
local LOGOUT_URL = SERVER_BASE_URL .. "/logout"
local CREATE_VIEW_URL = SERVER_BASE_URL .. "/create_world_view"

-- How often to send updates (in seconds)
local UPDATE_INTERVAL = 1.0

local timer = 0
local leaving_players = {} -- Track players who are logging out to prevent race conditions

-- Detect world name from world path
local world_path = minetest.get_worldpath()
local WORLD_NAME = "default"

-- Extract world name from path (e.g., /path/to/worlds/myworld -> myworld)
if world_path then
    WORLD_NAME = string.match(world_path, "([^/]+)$") or "default"
    minetest.log("action", "[position_tracker] Detected world: " .. WORLD_NAME)
end

-- Check if HTTP is enabled for this mod
local http_api = minetest.request_http_api()

if not http_api then
    minetest.log("error", "[position_tracker] HTTP API not enabled! Add 'position_tracker' to secure.http_mods in minetest.conf")
end

-- Clear leaving flag when player joins (in case they reconnect quickly)
minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    if name then leaving_players[name] = nil end
end)

minetest.register_globalstep(function(dtime)
    if not http_api then return end

    timer = timer + dtime
    if timer < UPDATE_INTERVAL then return end
    timer = 0

    local players = minetest.get_connected_players()
    for _, player in ipairs(players) do
        local name = player:get_player_name()
        local pos = player:get_pos()
        
        -- Check using the leaving_players table to prevent race conditions
        if name and leaving_players[name] then
            -- SAFETY NET: If the player is marked as leaving but still being processed in globalstep,
            -- force another delete/archive request to ensure no "zombie" points remain in the active table.
            local data = { player = name }
            http_api.fetch({
                url = LOGOUT_URL,
                method = "POST",
                data = minetest.write_json(data),
                timeout = 5,
                extra_headers = { "Content-Type: application/json" }
            }, function(res) end) -- fire and forget
        
        elseif name and pos then
            -- Normal case: Player is active, send position update
            local data = {
                player = name,
                world = WORLD_NAME,
                pos = {
                    x = pos.x+9,
                    y = pos.y,
                    z = pos.z+7
                }
            }

            -- Send asynchronous POST request
            -- Note: We don't log success to avoid spamming debug log every second
            http_api.fetch({
                url = POSITION_URL,
                method = "POST",
                data = minetest.write_json(data),
                timeout = 5,
                extra_headers = {
                    "Content-Type: application/json"
                }
            }, function(res)
                if res.code ~= 201 and res.code ~= 200 then
                    minetest.log("warning", "[position_tracker] Failed to send position for " .. name .. ": " .. (res.code or "unknown"))
                end
            end)
        end
    end
end)

-- Trigger archiving when player leaves
minetest.register_on_leaveplayer(function(player)
    if not http_api then return end
    
    local name = player:get_player_name()
    if not name then return end
    
    -- Mark player as leaving to stop position updates instantly
    leaving_players[name] = true
    
    minetest.log("action", "[position_tracker] Player " .. name .. " left, archiving traces...")
    
    local data = {
        player = name
    }
    
    http_api.fetch({
        url = LOGOUT_URL,
        method = "POST",
        data = minetest.write_json(data),
        timeout = 5,
        extra_headers = {
            "Content-Type: application/json"
        }
    }, function(res)
        if res.code ~= 200 then
             minetest.log("warning", "[position_tracker] Failed to archive for " .. name .. ": " .. (res.code or "unknown"))
        else
             minetest.log("action", "[position_tracker] Successfully archived traces for " .. name)
        end
    end)
end)

minetest.log("action", "[position_tracker] Mod loaded and ready to track positions.")

-- Create world-specific QGIS view on mod load
if http_api then
    http_api.fetch({
        url = CREATE_VIEW_URL .. "/" .. WORLD_NAME,
        method = "POST",
        timeout = 5
    }, function(res)
        if res.code == 201 or res.code == 200 then
            minetest.log("action", "[position_tracker] Created QGIS view for world: " .. WORLD_NAME)
        else
            minetest.log("warning", "[position_tracker] Failed to create QGIS view: " .. (res.code or "unknown"))
        end
    end)
end
