-- HigherLower Minigame Server Logic
local higherlower = {}
higherlower.__index = higherlower

local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

local player_state = {}
local match_ref = nil
local inputConn = nil
local voted_players = {}
local round_active = false
local timer_thread = nil
local ended = false

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

-- Check if all players are done
local function allPlayersDone()
    for _, pdata in ipairs(getAlivePlayers()) do
        if not player_state[pdata.player] or not player_state[pdata.player].done then
            return false
        end
    end
    return true
end

function higherlower.start(match)
    player_state = {}
    match_ref = match
    voted_players = {}
    round_active = true
    ended = false
    for _, pdata in ipairs(getAlivePlayers()) do
        local player = pdata.player
        player_state[player] = {
            number = 10,
            done = false,
        }
    end
    if inputConn then inputConn(); inputConn = nil end
    inputConn = server.MinigameInput.SetCallback(function(player, input_type, input_data)
        if ended then return end
        local state = player_state[player]
        if not state or state.done then return end
        if input_type == "guess" then
            if input_data == state.answer then
                state.done = true
                server.UpdateUI.Fire(player, "Game", "HigherLowerResult", {result = "advance"})
                if match_ref and not match_ref.last_minigame_winner then
                    match_ref.last_minigame_winner = player
                    ended = true
                    minigame_signal:Fire()
                end
            else
                state.done = true
                server.UpdateUI.Fire(player, "Game", "HigherLowerResult", {result = "fail"})
                return
            end
        end
    end)
end

function higherlower.stop()
    if inputConn then inputConn(); inputConn = nil end
    player_state = {}
    match_ref = nil
    voted_players = {}
    round_active = false
    if typeof(timer_thread) == "thread" then
        coroutine.close(timer_thread)
        timer_thread = nil
    end
end

return higherlower
