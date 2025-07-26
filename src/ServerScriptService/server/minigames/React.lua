-- React Minigame Server Logic
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

local react = {}

function react.start(match, minigame_signal)
    print("[React][SERVER] start() called for match:", match, "minigame_signal:", tostring(minigame_signal))
    local player_results = {}
    local ended = false
    local countdown_thread = nil
    local inputConn = nil
    countdown_thread = task.spawn(function()
        for n = 3, 1, -1 do
            for _, pdata in ipairs(match:get_alive_players()) do
                server.UpdateUI.Fire(pdata.player, "Game", "ReactCountdown", tostring(n))
            end
            task.wait(1)
        end
        for _, pdata in ipairs(match:get_alive_players()) do
            server.UpdateUI.Fire(pdata.player, "Game", "ReactCountdown", "")
        end
        -- React phase
        local stillPlaying = {}
        for _, pdata in ipairs(match:get_alive_players()) do
            if not player_results[pdata.player] then
                table.insert(stillPlaying, pdata.player)
            end
        end
        if #stillPlaying == 0 then
            print("[React][SERVER] Firing minigame_signal for completion! (no players left)", tostring(minigame_signal))
            if minigame_signal then minigame_signal:Fire() end
            return
        end
        for _, player in ipairs(stillPlaying) do
            server.UpdateUI.Fire(player, "Game", "ReactPhase", "wait")
        end
        local waitTime = math.random(15, 40) / 10 -- 1.5s to 4s
        task.wait(waitTime)
        for _, player in ipairs(stillPlaying) do
            server.UpdateUI.Fire(player, "Game", "ReactPhase", "click")
        end
        local clickDeadline = os.clock() + 3
        local clicked = {}
        while os.clock() < clickDeadline and not ended do
            for _, player in ipairs(stillPlaying) do
                if player_results[player] == "advance" then
                    clicked[player] = true
                    ended = true
                end
            end
            if next(clicked) then break end
            task.wait(0.05)
        end
        for _, player in ipairs(stillPlaying) do
            server.UpdateUI.Fire(player, "Game", "ReactPhase", "done")
        end
        for _, player in ipairs(stillPlaying) do
            if not player_results[player] then
                server.UpdateUI.Fire(player, "Game", "ReactResult", { result = "fail" })
            end
        end
        task.wait(2)
        print("[React][SERVER] Firing minigame_signal for completion!", tostring(minigame_signal))
        if minigame_signal then minigame_signal:Fire() end
    end)
    inputConn = server.MinigameInput.SetCallback(function(player, input_type, input_data)
        if ended then return end
        if not (match and match.is_player_alive and match:is_player_alive(player)) then return end
        if input_type == "react" or input_type == "react_click" then
            player_results[player] = "advance"
            server.UpdateUI.Fire(player, "Game", "ReactResult", {result = "advance"})
        elseif input_type == "fail" then
            server.UpdateUI.Fire(player, "Game", "ReactResult", {result = "fail"})
            return
        end
    end)
end

return react
