-- React Minigame Server Logic
local react = {}
react.__index = react
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

local match_ref = nil
local running = false
local inputConn = nil
local timer_thread = nil
local countdown_thread = nil
local phase = "wait"
local player_results = {}
local player_clicked = {}
local player_failed = {}

-- Get all alive players for the match
local function getAlivePlayers()
    if match_ref and match_ref.get_alive_players then
        return match_ref:get_alive_players()
    else
        local alive = {}
        for _, player in ipairs(Players:GetPlayers()) do
            table.insert(alive, { player = player })
        end
        return alive
    end
end

function react.start(match)
    match_ref = match
    running = false
    player_results = {}
    player_clicked = {}
    player_failed = {}
    phase = "wait"
    if inputConn then inputConn() end
    if timer_thread then coroutine.close(timer_thread) end
    if countdown_thread then coroutine.close(countdown_thread) end
    -- 3 second countdown
    countdown_thread = coroutine.create(function()
        for n = 3, 1, -1 do
            for _, pdata in ipairs(getAlivePlayers()) do
                server.UpdateUI.Fire(pdata.player, "Game", "ReactCountdown", tostring(n))
            end
            task.wait(1)
        end
        for _, pdata in ipairs(getAlivePlayers()) do
            server.UpdateUI.Fire(pdata.player, "Game", "ReactCountdown", "")
        end
        -- Start overall timer
        running = true
        phase = "wait"
        local timeLeft = 60
        timer_thread = coroutine.create(function()
            while timeLeft > 0 and running do
                for _, pdata in ipairs(getAlivePlayers()) do
                    server.UpdateUI.Fire(pdata.player, "Game", "ReactTime", timeLeft)
                end
                task.wait(1)
                timeLeft = timeLeft - 1
            end
            if running then
                -- Time's up, fail all who haven't finished
                for _, pdata in ipairs(getAlivePlayers()) do
                    if not player_results[pdata.player] then
                        player_results[pdata.player] = "timeout"
                        server.UpdateUI.Fire(pdata.player, "Game", "ReactResult", { result = "timeout" })
                    end
                end
                task.wait(2)
                minigame_signal:Fire()
            end
        end)
        coroutine.resume(timer_thread)
        -- Random wait before "CLICK!"
        local waitTime = math.random(15, 40) / 10 -- 1.5s to 4s
        for _, pdata in ipairs(getAlivePlayers()) do
            server.UpdateUI.Fire(pdata.player, "Game", "ReactPhase", "wait")
        end
        task.wait(waitTime)
        phase = "click"
        local clickDeadline = os.clock() + 3
        for _, pdata in ipairs(getAlivePlayers()) do
            server.UpdateUI.Fire(pdata.player, "Game", "ReactPhase", "click")
        end
        -- 3s to click
        while os.clock() < clickDeadline and running do
            if #player_clicked >= #getAlivePlayers() then break end
            task.wait(0.05)
        end
        phase = "done"
        for _, pdata in ipairs(getAlivePlayers()) do
            server.UpdateUI.Fire(pdata.player, "Game", "ReactPhase", "done")
        end
        -- Instead of eliminating or ending, just reset players who didn't react
        for _, pdata in ipairs(getAlivePlayers()) do
            if not player_results[pdata.player] then
                player_results[pdata.player] = nil -- reset state
                server.UpdateUI.Fire(pdata.player, "Game", "ReactResult", { result = "fail" })
            end
        end
        -- Do NOT call minigame_signal:Fire() here; only end when someone reacts
    end)
    coroutine.resume(countdown_thread)
    -- Listen for player input
    inputConn = server.MinigameInput.SetCallback(function(player, input_type, input_data)
        local state = player_results[player]
        if not state or state.done then return end
        if input_type == "react" then
            state.done = true
            server.UpdateUI.Fire(player, "Game", "ReactResult", {result = "advance"})
            if match_ref and not match_ref.last_minigame_winner then
                match_ref.last_minigame_winner = player
                minigame_signal:Fire()
            end
        elseif input_type == "fail" then
            state.done = true
            server.UpdateUI.Fire(player, "Game", "ReactResult", {result = "fail"})
            return
        end
    end)
end

function react.stop()
    running = false
    if inputConn then inputConn() inputConn = nil end
    if timer_thread then coroutine.close(timer_thread) timer_thread = nil end
    if countdown_thread then coroutine.close(countdown_thread) countdown_thread = nil end
end

return react
