-- Maze Minigame Server Logic
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

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

function maze.start(match, minigame_signal)
    finished_players = {}
    current_match = match
    local eliminated_players = {}
    starttime = tick()
    local ended = false
    zap_connection = server.MinigameInput.SetCallback(function(player, input_type, data)
        if ended then return end
        local pdata = current_match and current_match.get_player_data and current_match:get_player_data(player)
        if not (pdata and pdata.is_alive) then return end
        if input_type == "ended" then
            print("[Maze][SERVER] Received 'ended' input from", player.Name)
            if finished_players[player] then
                print("[Maze][SERVER] Player already finished:", player.Name)
                return
            end
            finished_players[player] = true
            if not current_match then warn("No match object found for Maze minigame!") return end
            if not current_match.last_minigame_winner then
                print("[Maze][SERVER] Setting last_minigame_winner to", player.Name)
                current_match.last_minigame_winner = player
                ended = true
                print("[Maze][SERVER] Firing minigame_signal for completion!", tostring(minigame_signal))
                if minigame_signal then minigame_signal:Fire() end
            else
                print("[Maze][SERVER] last_minigame_winner already set to", tostring(current_match.last_minigame_winner and current_match.last_minigame_winner.Name))
            end
        elseif input_type == "eliminated" then
            -- Do nothing: failing does not eliminate the player, just reset on client
        elseif input_type == "maze_zone" and type(data) == "table" then
            local zoneData = (data :: {zone: string})
            if not zoneData.zone then return end
            if finished_players[player] then
                print("[Maze][SERVER] Player already finished (maze_zone):", player.Name)
                return
            end
            if zoneData.zone == "End" then
                finished_players[player] = true
                if not current_match then warn("No match object found for Maze minigame!") return end
                if not current_match.last_minigame_winner then
                    print("[Maze][SERVER] Setting last_minigame_winner to", player.Name, "(maze_zone)")
                    current_match.last_minigame_winner = player
                    ended = true
                    print("[Maze][SERVER] Firing minigame_signal for completion! (maze_zone)")
                    if minigame_signal then minigame_signal:Fire() end
                else
                    print("[Maze][SERVER] last_minigame_winner already set to", tostring(current_match.last_minigame_winner and current_match.last_minigame_winner.Name))
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
