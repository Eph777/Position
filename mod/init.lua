-- Configuration
local SERVER_BASE_URL = "http://localhost:5000"
local API_JOIN = SERVER_BASE_URL .. "/api/join"
local API_SYNC = SERVER_BASE_URL .. "/sync/player"

local UPDATE_INTERVAL = 1.0
local timer = 0
local player_inventory_dirty = {} -- Set of players whose inventory needs syncing

-- Check http
local http_api = minetest.request_http_api()
if not http_api then
    minetest.log("error", "[position_tracker] HTTP API not enabled! Add to secure.http_mods")
end

-- Helper: Send Inventory
local function sync_inventory(player_name)
    local player = minetest.get_player_by_name(player_name)
    if not player then return end
    
    local inv = player:get_inventory()
    local list = inv:get_list("main")
    local json_inv = {}
    
    if list then
        for i, stack in ipairs(list) do
            if not stack:is_empty() then
                json_inv[tostring(i)] = stack:to_string()
            end
        end
    end

    local data = {
        player = player_name,
        inventory = json_inv
    }
    
    http_api.fetch({
        url = API_SYNC,
        method = "POST",
        data = minetest.write_json(data),
        timeout = 5,
        extra_headers = { "Content-Type: application/json" }
    }, function(res)
        -- Ignore response
    end)
end

-- Command: /join <team>
minetest.register_chatcommand("join", {
    params = "<team_name>",
    description = "Request to join a tactical team",
    func = function(name, param)
        if not http_api then return false, "HTTP API disabled" end
        if not param or param == "" then
            return false, "Usage: /join <team_name>"
        end
        
        local data = {
            player = name,
            team = param
        }
        
        http_api.fetch({
            url = API_JOIN,
            method = "POST",
            data = minetest.write_json(data),
            timeout = 5,
            extra_headers = { "Content-Type: application/json" }
        }, function(res)
            if res.code == 200 then
                 minetest.chat_send_player(name, "[System] Join request sent to " .. param .. ". Wait for approval.")
            else
                 minetest.chat_send_player(name, "[System] Error: " .. (res.code or "Unknown"))
            end
        end)
        
        return true
    end
})

-- Globalstep: Position Sync
minetest.register_globalstep(function(dtime)
    if not http_api then return end
    
    timer = timer + dtime
    if timer < UPDATE_INTERVAL then return end
    timer = 0
    
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local pos = player:get_pos()
        
        if name and pos then
            local data = {
                player = name,
                pos = { x = pos.x, y = pos.y, z = pos.z }
            }
            
            -- If inventory dirty, include it (optimization: piggyback on pos update? 
            -- No, server handles them separately easily, or we merge them.
            -- Server Pydantic model allows both. Let's merge if dirty.)
            if player_inventory_dirty[name] then
                 local inv = player:get_inventory()
                 local list = inv:get_list("main")
                 local json_inv = {}
                 if list then
                    for i, stack in ipairs(list) do
                        if not stack:is_empty() then
                            json_inv[tostring(i)] = stack:to_string()
                        end
                    end
                 end
                 data.inventory = json_inv
                 player_inventory_dirty[name] = nil -- Clear dirty flag
            end

            http_api.fetch({
                url = API_SYNC,
                method = "POST",
                data = minetest.write_json(data),
                timeout = 5,
                extra_headers = { "Content-Type: application/json" }
            }, function(res)
                if res.code == 200 then
                    local body = minetest.parse_json(res.data)
                    if body and body.code == "NO_TEAM" then
                        -- Throttle spam?
                        if math.random() < 0.1 then
                            minetest.chat_send_player(name, "[System] You are not in a team! Use /join <team>")
                        end
                    elseif body and body.player_status == "pending" then
                        -- Optional: Indication of pending
                    end
                end
            end)
        end
    end
end)

-- Inventory Listeners
minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    player_inventory_dirty[name] = true 
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    -- Force sync immediately on leave (cannot use async callback reliably maybe? 
    -- http fetch in on_leaveplayer is usually race-condition prone but minetest attempts to send it)
    sync_inventory(name)
end)

-- Detect inventory changes
-- We hook into the standard callbacks. 
-- Note: usage of minetest.register_on_player_inventory_action is good
minetest.register_on_player_inventory_action(function(player, action, inventory, inventory_info)
    local name = player:get_player_name()
    player_inventory_dirty[name] = true
end)

minetest.log("action", "[position_tracker] Mod loaded (FastAPI/RLS version)")
