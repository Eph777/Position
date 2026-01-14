-- Configuration
-- The URL of the middleware server (Flask app)
local SERVER_URL = "http://localhost:5000/position"
-- How often to send updates (in seconds)
local UPDATE_INTERVAL = 1.0

local timer = 0

-- Check if HTTP is enabled for this mod
local http_api = minetest.request_http_api()

if not http_api then
    minetest.log("error", "[position_tracker] HTTP API not enabled! Add 'position_tracker' to secure.http_mods in minetest.conf")
end

minetest.register_globalstep(function(dtime)
    if not http_api then return end

    timer = timer + dtime
    if timer < UPDATE_INTERVAL then return end
    timer = 0

    local players = minetest.get_connected_players()
    for _, player in ipairs(players) do
        local name = player:get_player_name()
        local pos = player:get_pos()
        
        if name and pos then
            -- Prepare JSON payload
            local data = {
                player = name,
                pos = {
                    x = pos.x,
                    y = pos.y,
                    z = pos.z
                }
            }

            -- Send asynchronous POST request
            http_api.fetch({
                url = SERVER_URL,
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

minetest.log("action", "[position_tracker] Mod loaded and ready to track positions.")
