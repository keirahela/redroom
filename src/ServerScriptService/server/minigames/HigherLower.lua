-- Alice in Borderland HigherLower Minigame Server Logic
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

local higherlower = {}

function higherlower.start(match, minigame_signal)
    print("[HigherLower][SERVER] start() called for match:", match, "minigame_signal:", tostring(minigame_signal))
    local player_state = {}
    local submission_order = {}
    local submissions = {}
    local ended = false
    local timer_thread = nil
    local inputConn = nil
    -- Initialize state for all alive players
    for _, pdata in ipairs(match:get_alive_players()) do
        local player = pdata.player
        player_state[player] = {
            number = 0,
            done = false,
        }
    end
    -- Start input timer
    timer_thread = task.spawn(function()
        local timeLeft = 8
        while timeLeft > 0 do
            for _, pdata in ipairs(match:get_alive_players()) do
                server.UpdateUI.Fire(pdata.player, "Game", "HigherLowerTimer", { timeLeft = timeLeft })
            end
            task.wait(1)
            timeLeft -= 1
        end
        -- After timer, process submissions
        if not ended then
            ended = true
            -- Fill in missing submissions with 0
            for player, state in pairs(player_state) do
                if not state.done then
                    state.number = 0
                    state.done = true
                end
            end
            -- Reveal phase
            local entries = {}
            for player, state in pairs(player_state) do
                table.insert(entries, { name = player.Name, number = state.number })
            end
            for _, pdata in ipairs(match:get_alive_players()) do
                server.UpdateUI.Fire(pdata.player, "Game", "HigherLowerPhase", { phase = "reveal" })
                server.UpdateUI.Fire(pdata.player, "Game", "HigherLowerReveal", { submissions = entries, winnerIndex = 1, target = 0 })
            end
            task.wait(2)
            print("[HigherLower][SERVER] Firing minigame_signal for completion!", tostring(minigame_signal))
            if minigame_signal then minigame_signal:Fire() end
        end
    end)
    -- Listen for player submissions
    inputConn = server.MinigameInput.SetCallback(function(player, input_type, input_data)
        if ended then return end
        if not (match and match.is_player_alive and match:is_player_alive(player)) then return end
        if input_type == "submit_number" and input_data and input_data.zone then
            local num = tonumber(tostring(input_data.zone):match("hl_(%d+)$"))
            if not num or num < 1 or num > 100 then return end
            if player_state[player] and not player_state[player].done then
                player_state[player].number = num
                player_state[player].done = true
                table.insert(submission_order, player)
                -- Optionally, check if all players submitted
                local allDone = true
                for _, state in pairs(player_state) do
                    if not state.done then allDone = false break end
                end
                if allDone and not ended then
                    ended = true
                    -- Reveal phase
                    local entries = {}
                    for p, state in pairs(player_state) do
                        table.insert(entries, { name = p.Name, number = state.number })
                    end
                    for _, pdata in ipairs(match:get_alive_players()) do
                        server.UpdateUI.Fire(pdata.player, "Game", "HigherLowerPhase", { phase = "reveal" })
                        server.UpdateUI.Fire(pdata.player, "Game", "HigherLowerReveal", { submissions = entries, winnerIndex = 1, target = 0 })
                    end
                    task.wait(2)
                    print("[HigherLower][SERVER] Firing minigame_signal for completion!", tostring(minigame_signal))
                    if minigame_signal then minigame_signal:Fire() end
                end
            end
        end
    end)
end

return higherlower
