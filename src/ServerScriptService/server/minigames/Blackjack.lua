local blackjack = {}
blackjack.__index = blackjack

local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

local player_state = {}
local match_ref = nil
local inputConn = nil

local function drawCard()
	return math.random(2, 11) -- 2-11 (11 = Ace, simplified)
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

function blackjack.start(match)
	player_state = {}
	match_ref = match
	if inputConn then
		inputConn()
		inputConn = nil
	end
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
			aiHand = {player_state[player].aiHand[1], 0}, -- Hide AI's second card
		})
	end
	inputConn = server.MinigameInput.SetCallback(function(player, input_type, input_data)
		local state = player_state[player]
		if not state or state.done then return end
		if input_type == "blackjack_hit" then
			table.insert(state.playerHand, drawCard())
			local value = handValue(state.playerHand)
			if value > 21 then
				state.done = true
				-- Animate AI's turn for bust as well
				local aiHand = {unpack(state.aiHand)}
				local function aiTurnOnBust()
					while handValue(aiHand) < 17 do
						table.insert(aiHand, drawCard())
						state.aiHand = aiHand
						server.UpdateUI.Fire(player, "Game", "BlackjackResult", {
							playerHand = state.playerHand,
							aiHand = state.aiHand,
						})
						task.wait(2)
					end
					server.UpdateUI.Fire(player, "Game", "BlackjackResult", {
						playerHand = state.playerHand,
						aiHand = state.aiHand,
						result = "eliminate"
					})
					task.wait(2)
					if match_ref and match_ref.eliminate_player then
						match_ref:eliminate_player(player)
					end
				end
				task.spawn(aiTurnOnBust)
			elseif #state.playerHand >= 5 then -- 5 card charlie rule (optional)
				state.standing = true
			end
			if not state.done and not state.standing then
				server.UpdateUI.Fire(player, "Game", "BlackjackResult", {
					playerHand = state.playerHand,
					aiHand = {state.aiHand[1], 0},
				})
			end
		elseif input_type == "blackjack_stand" or state.standing then
			state.standing = true
			-- AI plays (animated)
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
					result = "eliminate"
					state.done = true
				elseif aiValue > 21 then
					result = "advance"
					state.done = true
				elseif playerValue == aiValue then
					result = "tie"
					state.done = true
				elseif aiValue > playerValue then
					result = "eliminate"
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
				if result == "eliminate" and match_ref and match_ref.eliminate_player then
					match_ref:eliminate_player(player)
				end
			end
			task.spawn(aiTurn)
		end
		-- Check if all players are done
		local all_done = true
		for _, s in pairs(player_state) do
			if not s.done then all_done = false break end
		end
		if all_done then
			minigame_signal:Fire()
		end
	end)
end

function blackjack.stop()
	if inputConn then
		inputConn()
		inputConn = nil
	end
	player_state = {}
	match_ref = nil
end

return blackjack
