-- Configuration
local SERVER_BASE_URL = "http://localhost:5000"
local SYNC_URL = SERVER_BASE_URL .. "/sync/player"
local AUTH_URL = SERVER_BASE_URL .. "/auth/leader"
local CREATE_TEAM_URL = SERVER_BASE_URL .. "/team/create"
local ROSTER_URL_TEMPLATE = SERVER_BASE_URL .. "/team/roster/" -- + leader_name

-- Update interval (1 second as requested)
local UPDATE_INTERVAL = 1.0

local http_api = minetest.request_http_api()

if not http_api then
    minetest.log("error", "[position_tracker] HTTP API not enabled! Add 'position_tracker' to secure.http_mods")
end

local timer = 0
local leaving_players = {}

-- Helper: serialize inventory
local function get_inventory_json(player)
    local inv = player:get_inventory()
    if not inv then return "{}" end
    local lists = inv:get_lists()
    local data = {}
    for listname, stack_list in pairs(lists) do
        data[listname] = {}
        for i, stack in ipairs(stack_list) do
            data[listname][i] = stack:to_string()
        end
    end
    return minetest.write_json(data)
end

-- Module C & D: Tracker Loop and Inventory Security
minetest.register_globalstep(function(dtime)
    if not http_api then return end

    timer = timer + dtime
    if timer < UPDATE_INTERVAL then return end
    timer = 0

    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local pos = player:get_pos()
        
        if name and not leaving_players[name] and pos then
            -- Sync Player (Position + Inventory)
            local data = {
                player_name = name,
                x = pos.x,
                y = pos.y,
                z = pos.z,
                inventory_json = get_inventory_json(player)
            }
            
            http_api.fetch({
                url = SYNC_URL,
                method = "POST",
                data = minetest.write_json(data),
                timeout = 5,
                extra_headers = { "Content-Type: application/json" }
            }, function(res)
                -- Silent failure to avoid spam
            end)
        end
    end
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    if name then
        leaving_players[name] = true
        -- Final Sync
        if http_api then
           -- We can re-use the sync logic or a specific logout endpoint. 
           -- The current requirement says "Force immediate sync to API" on leave.
           -- Our /sync/player accepts inventory, so we send it one last time.
           -- Note: We can't get player position reliably if they are already gone, 
           -- but the object might still be valid in on_leaveplayer.
           local pos = player:get_pos() or {x=0, y=0, z=0}
           local data = {
                player_name = name,
                x = pos.x,
                y = pos.y,
                z = pos.z,
                inventory_json = get_inventory_json(player)
            }
            http_api.fetch({
                url = SYNC_URL,
                method = "POST",
                data = minetest.write_json(data),
                timeout = 2,
                extra_headers = { "Content-Type: application/json" }
            }, function(res) end)
        end
    end
end)

minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    if name then leaving_players[name] = nil end
    -- Note: Inventory overwrite from API on join is requested but implementation 
    -- requires fetching FROM api. 
    -- For now, we will just start syncing. 
    -- TODO: Implement fetching inventory if persistent state is desired *from* DB to *game*.
    -- The requirement "on_joinplayer: Fetch inventory from API and overwrite local state"
    -- implies we need a GET endpoint or use the sync response?
    -- Currently /sync/player is POST.
end)


-- Module A & B: Team Management & Auth

-- Helper to show roster formspec
local function show_roster(player_name, leader_name, team_id, members)
    local form = "size[8,9]" ..
                 "label[0.5,0.5;Team Roster (Leader: " .. minetest.formspec_escape(leader_name) .. ")]" ..
                 "textlist[0.5,1.5;7,6;members;"
    
    local list_items = ""
    for i, m in ipairs(members) do
        local entry = m.name .. " (" .. math.floor(m.x)..","..math.floor(m.y)..","..math.floor(m.z) .. ")"
        if i > 1 then list_items = list_items .. "," end
        list_items = list_items .. minetest.formspec_escape(entry)
    end
    
    form = form .. list_items .. "]"
    form = form .. "button_exit[2.5,8;3,0.8;close;Close]"
    
    minetest.show_formspec(player_name, "position_tracker:roster", form)
end

-- Command: /create_team <name> <password>
minetest.register_chatcommand("create_team", {
    params = "<team_name> <password>",
    description = "Create a new tactical team",
    func = function(name, param)
        if not http_api then return false, "API disabled" end
        
        local team_name, password = param:match("^(%S+)%s+(%S+)$")
        if not team_name or not password then
            return false, "Usage: /create_team <team_name> <password>"
        end
        
        local data = {
            team_name = team_name,
            leader_name = name,
            password = password
        }
        
        http_api.fetch({
            url = CREATE_TEAM_URL,
            method = "POST",
            data = minetest.write_json(data),
            timeout = 5,
            extra_headers = { "Content-Type: application/json" }
        }, function(res)
            if res.code == 201 then
                minetest.chat_send_player(name, "Team '" .. team_name .. "' created successfully!")
            else
                minetest.chat_send_player(name, "Failed to create team. Error: " .. (res.code or "unknown"))
            end
        end)
        return true
    end
})

-- Command: /team_menu -> Opens Login Form
minetest.register_chatcommand("team_menu", {
    description = "Open team management menu",
    func = function(name, param)
        local form = "size[6,4]" ..
                     "label[0.5,0.5;Team Login]" ..
                     "field[0.8,1.5;4.5,0.8;leader;Leader Name;" .. minetest.formspec_escape(name) .. "]" ..
                     "field[0.8,2.5;4.5,0.8;password;Password;]" ..
                     "button[0.5,3.2;5,0.8;login;View Roster]"
        minetest.show_formspec(name, "position_tracker:login", form)
    end
})

-- Formspec Handler
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname == "position_tracker:login" then
        if fields.login then
            local leader = fields.leader
            local password = fields.password
            local player_name = player:get_player_name()
            
            if not leader or leader == "" or not password or password == "" then
                minetest.chat_send_player(player_name, "Missing credentials.")
                return
            end

            -- 1. Authenticate
            http_api.fetch({
                url = AUTH_URL,
                method = "POST",
                data = minetest.write_json({ leader_name = leader, password = password }),
                timeout = 5,
                extra_headers = { "Content-Type: application/json" }
            }, function(res)
                if res.code == 200 then
                    -- 2. Fetch Roster
                    http_api.fetch({
                        url = ROSTER_URL_TEMPLATE .. leader,
                        method = "GET",
                        timeout = 5
                    }, function(res2)
                        if res2.code == 200 then
                            local data = minetest.parse_json(res2.data)
                            if data and data.members then
                                show_roster(player_name, leader, data.team_id, data.members)
                            end
                        else
                             minetest.chat_send_player(player_name, "Login success, but failed to fetch roster.")
                        end
                    end)
                else
                    minetest.chat_send_player(player_name, "Authentication failed.")
                end
            end)
        end
    end
end)

minetest.log("action", "[position_tracker] Tactical Team System Loaded")
