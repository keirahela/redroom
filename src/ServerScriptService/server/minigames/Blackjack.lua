-- Blackjack Minigame Server Logic
local blackjack = {}
blackjack.__index = blackjack

local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

local player_state = {}
local match_ref = nil
local inputConn = nil
local ended = false

-- Draw a card (2-11, 11 = Ace)
local function drawCard()
    return math.random(2, 11)
end

-- Calculate hand value, handling Aces
local function handValue(hand)
    local total = 0
    local aces = 0
    for _, v in ipairs(hand) do
        total = total + v
        if v == 11 then aces = aces + 1 end
    end
    while total > 21 and aces > 0 do
        total = total - 10
        aces = aces - 1
    end
    return total
end

function blackjack.start(match)
    player_state = {}
    match_ref = match
    ended = false
    if inputConn then inputConn(); inputConn = nil end
    for _, pdata in ipairs(match:get_alive_players()) do
        local player = pdata.player
        player_state[player] = {
            playerHand = {drawCard()},
            aiHand = {drawCard()},
            done = false,
            standing = false,
        }
        server.UpdateUI.Fire(player, "Game", "BlackjackResult", {
            playerHand = player_state[player].playerHand,
            aiHand = {player_state[player].aiHand[1], 0},
        })
    end
    inputConn = server.MinigameInput.SetCallback(function(player, input_type, input_data)
        if ended then return end
        local state = player_state[player]
        if not state or state.done then return end
        if input_type == "blackjack_hit" then
            table.insert(state.playerHand, drawCard())
            local value = handValue(state.playerHand)
            if value > 21 then
                state.done = true
                return
            elseif #state.playerHand >= 5 then
                state.standing = true
            end
            if not state.done and not state.standing then
                server.UpdateUI.Fire(player, "Game", "BlackjackResult", {
                    playerHand = state.playerHand,
                    aiHand = {state.aiHand[1], 0},
                })
            end
            state.standing = true
            local aiHand = {unpack(state.aiHand)}
            local function aiTurn()
                while handValue(aiHand) < 17 do
                    table.insert(aiHand, drawCard())
                    state.aiHand = aiHand
                    server.UpdateUI.Fire(player, "Game", "BlackjackResult", {
                        playerHand = state.playerHand,
                        aiHand = state.aiHand,
                    })
                    task.wait(2)
                end
                local playerValue = handValue(state.playerHand)
                local aiValue = handValue(aiHand)
                local result
                if playerValue > 21 then
                    result = "fail"
                    state.done = true
                elseif aiValue > 21 then
                    result = "advance"
                    state.done = true
                elseif playerValue == aiValue then
                    result = "tie"
                    state.done = true
                elseif aiValue > playerValue then
                    result = "fail"
                    state.done = true
                else
                    result = "advance"
                    state.done = true
                end
                server.UpdateUI.Fire(player, "Game", "BlackjackResult", {
                    playerHand = state.playerHand,
                    aiHand = state.aiHand,
                    result = result
                })
                task.wait(2)
                if (result == "advance" or result == "tie") and match_ref and not match_ref.last_minigame_winner then
                    match_ref.last_minigame_winner = player
                    ended = true
                    minigame_signal:Fire()
                end
            end
            task.spawn(aiTurn)
        end
    end)
end

function blackjack.stop()
    if inputConn then inputConn(); inputConn = nil end
    player_state = {}
    match_ref = nil
end

return blackjack
