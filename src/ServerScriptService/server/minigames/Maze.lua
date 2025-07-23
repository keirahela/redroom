-- Maze Minigame Server Logic
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local maze = {}
maze.__index = maze

-- Fire MazeLayout event to all players in the match
local function sendMazeLayout(match, layout)
    for _, pdata in ipairs(match:get_alive_players()) do
        local player = pdata.player
        server.UpdateUI.Fire(player, "Game", "MazeLayout", layout)
    end
end

local starttime = nil
local zap_connection = nil
local finished_players = {}
local current_match = nil

function maze.start(match)
    finished_players = {}
    current_match = match
    local eliminated_players = {}
    starttime = tick()
    local ended = false
    zap_connection = server.MinigameInput.SetCallback(function(player, input_type, data)
        if ended then return end
        if input_type == "ended" then
            if finished_players[player] then return end
            finished_players[player] = true
            if not current_match then warn("No match object found for Maze minigame!") return end
            if not current_match.last_minigame_winner then
                current_match.last_minigame_winner = player
                ended = true
                minigame_signal:Fire()
            end
        elseif input_type == "eliminated" then
            -- Do nothing: failing does not eliminate the player, just reset on client
        elseif input_type == "maze_zone" and type(data) == "table" then
            local zoneData = (data :: {zone: string})
            if not zoneData.zone then return end
            if finished_players[player] then return end
            if zoneData.zone == "End" then
                finished_players[player] = true
                if not current_match then warn("No match object found for Maze minigame!") return end
                if not current_match.last_minigame_winner then
                    current_match.last_minigame_winner = player
                    ended = true
                    minigame_signal:Fire()
                end
            elseif zoneData.zone == "Danger" then
                -- Do nothing: failing does not eliminate the player, just reset on client
            end
        end
    end)
end

function maze.stop()
    if zap_connection then zap_connection() end
end

return maze
