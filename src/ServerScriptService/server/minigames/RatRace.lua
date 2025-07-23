-- RatRace Minigame Server Logic
local ratrace = {}
ratrace.__index = ratrace
ratrace._inputConn = nil -- Explicitly declare _inputConn for linter
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

local RAT_COUNT = 6
local TRACK_LENGTH = 0.9 -- UDim2 X scale for finish line
local TICK_RATE = 0.1
local ENCOURAGE_BOOST = 0.02
local ENCOURAGE_COOLDOWN = 2
local RAT_MOVE_MIN = 0.003
local RAT_MOVE_MAX = 0.01

local rat_positions = {}
local player_choices = {}
local encourage_timestamps = {}
local running = false
local match_ref = nil
local update_thread = nil
local countdown_thread = nil

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

-- Check if all players have selected a rat
local function allPlayersSelected()
    for _, pdata in ipairs(getAlivePlayers()) do
        if not player_choices[pdata.player] then
            return false
        end
    end
    return true
end

-- Helper to build taken rats table
local function getTakenRats()
    local taken = {}
    for _, ratIdx in pairs(player_choices) do
        if ratIdx then taken[ratIdx] = true end
    end
    return taken
end

function ratrace.start(match)
    match_ref = match
    rat_positions = {}
    player_choices = {}
    encourage_timestamps = {}
    running = false
    for i = 1, RAT_COUNT do rat_positions[i] = 0 end
    for _, pdata in ipairs(getAlivePlayers()) do
        player_choices[pdata.player] = nil
        encourage_timestamps[pdata.player] = 0
    end
    if update_thread then coroutine.close(update_thread) end
    if countdown_thread then coroutine.close(countdown_thread) end
    if ratrace._inputConn then ratrace._inputConn() end
    ratrace._inputConn = server.MinigameInput.SetCallback(function(player, input_type, input_data)
        if running then return end
        if not (match_ref and match_ref.is_player_alive and match_ref:is_player_alive(player)) then return end
        if not player_choices[player] and input_type == "rat_select" and input_data and input_data.zone then
            local ratIdx = tonumber(input_data.zone:match("rat(%d)"))
            print("[RatRace][SERVER] Player", player.Name, "selected rat", ratIdx)
            if ratIdx and ratIdx >= 1 and ratIdx <= RAT_COUNT then
                for _, chosen in pairs(player_choices) do
                    if chosen == ratIdx then return end
                end
                player_choices[player] = ratIdx
                print("[RatRace][SERVER] player_choices:", player_choices)
                server.UpdateUI.FireAll("Game", "RatRaceTakenRats", getTakenRats())
                if allPlayersSelected() and not running then
                    print("[RatRace][SERVER] All players selected. Starting countdown.")
                    running = true
                    countdown_thread = coroutine.create(function()
                        for n = 3, 1, -1 do
                            for _, pdata in ipairs(getAlivePlayers()) do
                                server.UpdateUI.Fire(pdata.player, "Game", "Countdown", tostring(n))
                            end
                            task.wait(1)
                        end
                        for _, pdata in ipairs(getAlivePlayers()) do
                            server.UpdateUI.Fire(pdata.player, "Game", "Countdown", "")
                        end
                        print("[RatRace][SERVER] Countdown finished. Starting race.")
                        startRace()
                    end)
                    coroutine.resume(countdown_thread)
                end
            end
        elseif input_type == "encourage_rat" and input_data and input_data.zone then
            local ratIdx = tonumber(input_data.zone:match("encourage(%d)"))
            if ratIdx and ratIdx >= 1 and ratIdx <= RAT_COUNT then
                if player_choices[player] == ratIdx and running then
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

function startRace()
    if update_thread then coroutine.close(update_thread) end
    update_thread = coroutine.create(function()
        while true do
            local winnerRat = nil
            for i = 1, RAT_COUNT do
                local move = math.random() * (RAT_MOVE_MAX - RAT_MOVE_MIN) + RAT_MOVE_MIN
                rat_positions[i] = math.min(rat_positions[i] + move, TRACK_LENGTH)
                if rat_positions[i] >= TRACK_LENGTH and not winnerRat then
                    winnerRat = i
                end
            end
            local positions = {}
            for i = 1, RAT_COUNT do table.insert(positions, rat_positions[i]) end
            for _, pdata in ipairs(getAlivePlayers()) do
                server.UpdateUI.Fire(pdata.player, "Game", "RatRacePositions", positions)
            end
            if winnerRat then
                print("[RatRace][SERVER] Race finished. Winning rat:", winnerRat)
                -- Find all players who picked the winning rat
                local winners = {}
                for player, ratIdx in pairs(player_choices) do
                    if ratIdx == winnerRat then
                        table.insert(winners, player)
                    end
                end
                if #winners == 0 then
                    -- No one picked the winning rat, find the player whose rat is furthest ahead
                    local furthest = -1
                    local furthestPlayers = {}
                    for player, ratIdx in pairs(player_choices) do
                        if ratIdx and rat_positions[ratIdx] then
                            if rat_positions[ratIdx] > furthest then
                                furthest = rat_positions[ratIdx]
                                furthestPlayers = {player}
                            elseif rat_positions[ratIdx] == furthest then
                                table.insert(furthestPlayers, player)
                            end
                        end
                    end
                    if #furthestPlayers > 0 then
                        winners = furthestPlayers
                    end
                end
                -- If still tied, pick randomly
                local winnerPlayer = nil
                if #winners > 0 then
                    winnerPlayer = winners[math.random(1, #winners)]
                end
                print("[RatRace][SERVER] Winner(s):", winners, "Chosen winner:", winnerPlayer)
                if winnerPlayer and match_ref and not match_ref.last_minigame_winner then
                    match_ref.last_minigame_winner = winnerPlayer
                end
                for player, ratIdx in pairs(player_choices) do
                    if ratIdx == winnerRat then
                        server.UpdateUI.Fire(player, "Game", "RatRaceResult", { result = "advance", rat = ratIdx })
                    else
                        server.UpdateUI.Fire(player, "Game", "RatRaceResult", { result = "fail", rat = ratIdx })
                    end
                end
                task.wait(2)
                minigame_signal:Fire() -- Only call once
                break
            end
            task.wait(TICK_RATE)
        end
    end)
    coroutine.resume(update_thread)
end

function ratrace.stop()
    running = false
    if ratrace._inputConn then ratrace._inputConn(); ratrace._inputConn = nil end
    if update_thread then coroutine.close(update_thread); update_thread = nil end
    if countdown_thread then coroutine.close(countdown_thread); countdown_thread = nil end
end

return ratrace
