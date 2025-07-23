-- DragTheLine Minigame Server Logic
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local dragtheline = {}
dragtheline.__index = dragtheline

local finished_players = {}
local eliminated_players = {}
local current_match = nil
local zap_connection = nil

function dragtheline.start(match)
    print("[DragTheLine][SERVER] start() called for match:", match)
    finished_players = {}
    eliminated_players = {}
    current_match = match
    zap_connection = server.MinigameInput.SetCallback(function(player, input_type, data)
        print("[DragTheLine][SERVER] MinigameInput callback triggered:", player, input_type)
        if not (current_match and current_match.is_player_alive and current_match:is_player_alive(player)) then return end
        if input_type == "ended" then
            if finished_players[player] then return end
            finished_players[player] = true
            if not current_match then warn("No match object for DragTheLine!") return end
            if not current_match.last_minigame_winner then
                print("[DragTheLine][SERVER] Player won:", player)
                current_match.last_minigame_winner = player
                server.UpdateUI.Fire(player, "Game", "DragTheLineResult", { result = "advance" })
                -- All other players see fail
                for other, _ in pairs(finished_players) do
                    if other ~= player then
                        server.UpdateUI.Fire(other, "Game", "DragTheLineResult", { result = "fail" })
                    end
                end
                minigame_signal:Fire()
            else
                -- Already have a winner, this player sees fail
                server.UpdateUI.Fire(player, "Game", "DragTheLineResult", { result = "fail" })
            end
        end
        -- Remove all elimination logic for any other input_type
    end)
end

function dragtheline.stop()
    print("[DragTheLine][SERVER] stop() called")
    if zap_connection then zap_connection() end
end

return dragtheline 