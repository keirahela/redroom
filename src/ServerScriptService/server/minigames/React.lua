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
        running = true
        -- Start the main loop for all players who haven't succeeded
        local function runReactCycle()
            while running do
                local stillPlaying = {}
                for _, pdata in ipairs(getAlivePlayers()) do
                    if not player_results[pdata.player] then
                        table.insert(stillPlaying, pdata.player)
                    end
                end
                if #stillPlaying == 0 then break end
                -- Send 'wait' phase
                for _, player in ipairs(stillPlaying) do
                    server.UpdateUI.Fire(player, "Game", "ReactPhase", "wait")
                end
                local waitTime = math.random(15, 40) / 10 -- 1.5s to 4s
                task.wait(waitTime)
                -- Send 'click' phase
                for _, player in ipairs(stillPlaying) do
                    server.UpdateUI.Fire(player, "Game", "ReactPhase", "click")
                end
                local clickDeadline = os.clock() + 3
                local clicked = {}
                while os.clock() < clickDeadline and running do
                    for _, player in ipairs(stillPlaying) do
                        if player_results[player] == "advance" then
                            clicked[player] = true
                        end
                    end
                    if next(clicked) then break end
                    task.wait(0.05)
                end
                -- Set phase to done for all still playing
                for _, player in ipairs(stillPlaying) do
                    server.UpdateUI.Fire(player, "Game", "ReactPhase", "done")
                end
                -- For those who didn't click, send fail and let them try again
                for _, player in ipairs(stillPlaying) do
                    if not player_results[player] then
                        server.UpdateUI.Fire(player, "Game", "ReactResult", { result = "fail" })
                    end
                end
                -- If any player succeeded, end the minigame
                if next(clicked) then
                    break
                end
            end
        end
        runReactCycle()
        -- End the minigame if anyone succeeded
        for _, pdata in ipairs(getAlivePlayers()) do
            if player_results[pdata.player] == "advance" then
                task.wait(2)
                minigame_signal:Fire()
                break
            end
        end
    end)
    coroutine.resume(countdown_thread)
    -- Listen for player input
    inputConn = server.MinigameInput.SetCallback(function(player, input_type, input_data)
        if not (match_ref and match_ref.is_player_alive and match_ref:is_player_alive(player)) then return end
        if player_results[player] == "advance" then return end
        if input_type == "react" then
            player_results[player] = "advance"
            server.UpdateUI.Fire(player, "Game", "ReactResult", {result = "advance"})
        elseif input_type == "fail" then
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
