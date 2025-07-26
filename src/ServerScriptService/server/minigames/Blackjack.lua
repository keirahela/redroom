-- Blackjack Minigame Server Logic
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

local blackjack = {}

local function drawCard()
    return math.random(2, 11)
end

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

local player_state = {}
local inputConn = nil
local ended = false
local status_requested = {}
local current_match = nil

function blackjack.start(match, minigame_signal)
    print("[Blackjack][SERVER] start() called for match:", match, "minigame_signal:", tostring(minigame_signal))
    player_state = {}
    ended = false
    status_requested = {}
    current_match = match
    if inputConn then inputConn(); inputConn = nil end
    for _, pdata in ipairs(match:get_alive_players()) do
        local player = pdata.player
        player_state[player] = {
            playerHand = {drawCard(), drawCard()},
            aiHand = {drawCard(), drawCard()},
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
        if not (match and match.is_player_alive and match:is_player_alive(player)) then return end
        local state = player_state[player]
        if input_type == "blackjack_status" then
            if status_requested[player] then return end
            status_requested[player] = true
            if state then
                server.UpdateUI.Fire(player, "Game", "BlackjackResult", {
                    playerHand = state.playerHand,
                    aiHand = {state.aiHand[1], 0},
                })
            end
            return
        end
        if input_type == "blackjack_replay" then
            player_state[player] = {
                playerHand = {drawCard(), drawCard()},
                aiHand = {drawCard(), drawCard()},
                done = false,
                standing = false,
            }
            server.UpdateUI.Fire(player, "Game", "BlackjackResult", {
                playerHand = player_state[player].playerHand,
                aiHand = {player_state[player].aiHand[1], 0},
            })
            return
        end
        if not state or state.done then return end
        if input_type == "blackjack_hit" then
            table.insert(state.playerHand, drawCard())
            local value = handValue(state.playerHand)
            if value > 21 then
                state.done = true
                server.UpdateUI.Fire(player, "Game", "BlackjackResult", {
                    playerHand = state.playerHand,
                    aiHand = state.aiHand,
                    result = "fail"
                })
                return
            elseif #state.playerHand >= 5 then
                state.standing = true
            end
            if not state.done and not state.standing then
                server.UpdateUI.Fire(player, "Game", "BlackjackResult", {
                    playerHand = state.playerHand,
                    aiHand = {state.aiHand[1], 0},
                })
                return
            end
        end
        if input_type == "blackjack_stand" or (input_type == "blackjack_hit" and (state.done or state.standing)) then
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
                    result = "fail"
                    state.done = true
                elseif playerValue > aiValue then
                    result = "advance"
                    state.done = true
                else
                    result = "fail"
                    state.done = true
                end
                server.UpdateUI.Fire(player, "Game", "BlackjackResult", {
                    playerHand = state.playerHand,
                    aiHand = state.aiHand,
                    result = result,
                })
                if not current_match.last_minigame_winner and result == "advance" then
                    print("[Blackjack][SERVER] Firing minigame_signal for completion!", tostring(minigame_signal))
                    current_match.last_minigame_winner = player
                    ended = true
                    if minigame_signal then minigame_signal:Fire() end
                end
                if result == "fail" then
                    state.playerHand = {drawCard(), drawCard()}
                    state.aiHand = {drawCard(), drawCard()}
                    state.done = false
                    state.standing = false
                    server.UpdateUI.Fire(player, "Game", "BlackjackResult", {
                        playerHand = state.playerHand,
                        aiHand = {state.aiHand[1], 0},
                    })
                end
            end
            task.spawn(aiTurn)
        end
    end)
end

function blackjack.stop()
    if inputConn then inputConn(); inputConn = nil end
    player_state = {}
    ended = false
    status_requested = {}
    current_match = nil
end

return blackjack
