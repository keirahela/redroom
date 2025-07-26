-- RatRace Minigame Server Logic
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

local RAT_COUNT = 6
local TRACK_LENGTH = 0.9
local ENCOURAGE_BOOST = 0.02
local ENCOURAGE_COOLDOWN = 2
local RAT_MOVE_MIN = 0.003
local RAT_MOVE_MAX = 0.01

local ratrace = {}

function ratrace.start(match, minigame_signal)
    print("[RatRace][SERVER] start() called for match:", match, "minigame_signal:", tostring(minigame_signal))
    local rat_positions = {}
    local player_choices = {}
    local encourage_timestamps = {}
    local ended = false
    local update_thread = nil
    local inputConn = nil
    for i = 1, RAT_COUNT do rat_positions[i] = 0 end
    for _, pdata in ipairs(match:get_alive_players()) do
        player_choices[pdata.player] = nil
        encourage_timestamps[pdata.player] = 0
        server.UpdateUI.Fire(pdata.player, "Game", "RatRaceReset", {})
    end
    inputConn = server.MinigameInput.SetCallback(function(player, input_type, input_data)
        if ended then return end
        if not (match and match.is_player_alive and match:is_player_alive(player)) then return end
        if not player_choices[player] and input_type == "rat_select" and input_data and input_data.zone then
            local ratIdx = tonumber(input_data.zone:match("rat(%d)"))
            if ratIdx and ratIdx >= 1 and ratIdx <= RAT_COUNT then
                for _, chosen in pairs(player_choices) do
                    if chosen == ratIdx then return end
                end
                player_choices[player] = ratIdx
                for _, pdata in ipairs(match:get_alive_players()) do
                    local p = pdata.player
                    server.UpdateUI.Fire(p, "Game", "RatRaceTakenRats", { takenRats = player_choices, yourRat = player_choices[p] })
                end
                -- If all players have selected, start the race
                local allSelected = true
                for _, pdata in ipairs(match:get_alive_players()) do
                    if not player_choices[pdata.player] then allSelected = false break end
                end
                if allSelected and not ended then
                    ended = true
                    update_thread = task.spawn(function()
                        for n = 3, 1, -1 do
                            for _, pdata in ipairs(match:get_alive_players()) do
                                server.UpdateUI.Fire(pdata.player, "Game", "Countdown", tostring(n))
                            end
                            task.wait(1)
                        end
                        for _, pdata in ipairs(match:get_alive_players()) do
                            server.UpdateUI.Fire(pdata.player, "Game", "Countdown", "")
                        end
                        -- Start race
                        local winnerRat = nil
                        while not winnerRat do
                            for i = 1, RAT_COUNT do
                                local move = math.random() * (RAT_MOVE_MAX - RAT_MOVE_MIN) + RAT_MOVE_MIN
                                rat_positions[i] = math.min(rat_positions[i] + move, TRACK_LENGTH)
                                if rat_positions[i] >= TRACK_LENGTH and not winnerRat then
                                    winnerRat = i
                                end
                            end
                            local positions = {}
                            for i = 1, RAT_COUNT do table.insert(positions, rat_positions[i]) end
                            for _, pdata in ipairs(match:get_alive_players()) do
                                server.UpdateUI.Fire(pdata.player, "Game", "RatRacePositions", positions)
                            end
                            task.wait(0.1)
                        end
                        -- Determine winner
                        local winners = {}
                        for player, ratIdx in pairs(player_choices) do
                            if ratIdx == winnerRat then
                                table.insert(winners, player)
                            end
                        end
                        local winnerPlayer = nil
                        if #winners > 0 then
                            winnerPlayer = winners[math.random(1, #winners)]
                        end
                        if winnerPlayer and match and not match.last_minigame_winner then
                            match.last_minigame_winner = winnerPlayer
                        end
                        task.wait(2)
                        print("[RatRace][SERVER] Firing minigame_signal for completion!", tostring(minigame_signal))
                        if minigame_signal then minigame_signal:Fire() end
                    end)
                end
            end
        elseif input_type == "encourage_rat" and input_data and input_data.zone then
            local ratIdx = tonumber(input_data.zone:match("encourage(%d)"))
            if ratIdx and ratIdx >= 1 and ratIdx <= RAT_COUNT then
                if player_choices[player] == ratIdx and not ended then
                    local now = os.clock()
                    if now - (encourage_timestamps[player] or 0) >= ENCOURAGE_COOLDOWN then
                        encourage_timestamps[player] = now
                        rat_positions[ratIdx] = math.min(rat_positions[ratIdx] + ENCOURAGE_BOOST, TRACK_LENGTH)
                    end
                end
            end
        end
    end)
end

return ratrace
