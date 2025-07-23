-- BombGuesser Minigame Server Logic
local bombguesser = {}
bombguesser.__index = bombguesser

local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

local player_state = {}
local match_ref = nil
local inputConn = nil
local round_active = false

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

function bombguesser.start(match)
    player_state = {}
    match_ref = match
    round_active = true
    if inputConn then inputConn(); inputConn = nil end
    for _, pdata in ipairs(getAlivePlayers()) do
        player_state[pdata.player] = { picked = false, dud_index = math.random(1, 3), done = false }
        server.UpdateUI.Fire(pdata.player, "Game", "BombGuesserStart", { numBombs = 3 })
    end
    inputConn = server.MinigameInput.SetCallback(function(player, input_type, input_data)
        if not (match_ref and match_ref.is_player_alive and match_ref:is_player_alive(player)) then return end
        local state = player_state[player]
        if not state or state.done then return end
        if input_type == "guess" then
            if tonumber(input_data) == state.dud_index then
                state.done = true
                round_active = false
                server.UpdateUI.Fire(player, "Game", "BombGuesserResult", {result = "advance", dud = state.dud_index})
                if match_ref and not match_ref.last_minigame_winner then
                    match_ref.last_minigame_winner = player
                    minigame_signal:Fire()
                end
            else
                server.UpdateUI.Fire(player, "Game", "BombGuesserResult", {result = "fail", dud = state.dud_index})
                return
            end
        end
    end)
end

function bombguesser.stop()
    if inputConn then inputConn(); inputConn = nil end
    player_state = {}
    match_ref = nil
    round_active = false
end

return bombguesser