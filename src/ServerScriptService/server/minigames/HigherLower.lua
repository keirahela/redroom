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
	print("[HigherLower] Minigame started.")
	for _, pdata in ipairs(getAlivePlayers()) do
		local player = pdata.player
		player_state[player] = {
			number = 10,
			done = false,
		}
	end
	print("[HigherLower] Alive players at start:")
	for _, pdata in ipairs(getAlivePlayers()) do
		local p = pdata.player
		print("  ", p.Name, "done:", player_state[p] and player_state[p].done)
	end
	if inputConn then
		inputConn()
		inputConn = nil
	end
	inputConn = server.MinigameInput.SetCallback(function(player, input_type, input_data)
		if not player_state[player] or player_state[player].done or not round_active then return end
		if input_type ~= "guess_higher" and input_type ~= "guess_lower" and input_type ~= "guess_timeout" then return end
		if input_type == "guess_timeout" then
			print("[HigherLower] Player timed out:", player.Name)
			player_state[player].done = true
			voted_players[player] = true
			server.UpdateUI.Fire(player, "Game", "HigherLowerResult", { result = "eliminate" })
			if match_ref and match_ref.eliminate_player then
				match_ref:eliminate_player(player)
			end
		else
			print("[HigherLower] Player voted:", player.Name, input_type)
			voted_players[player] = true
			local state = player_state[player]
			local hidden = math.random(1, 20)
			print("[HigherLower] Hidden number for", player.Name, "is", hidden)
			local guess = (input_type == "guess_higher") and "Higher" or "Lower"
			local correct = false
			if guess == "Higher" then
				correct = hidden > state.number
			elseif guess == "Lower" then
				correct = hidden < state.number
			end
			if correct then
				state.number = 10
				server.UpdateUI.Fire(player, "Game", "HigherLowerResult", { result = "advance" })
			else
				state.done = true
				server.UpdateUI.Fire(player, "Game", "HigherLowerResult", { result = "eliminate" })
				if match_ref and match_ref.eliminate_player then
					match_ref:eliminate_player(player)
				end
			end
		end
		-- Check if all alive players have voted
		local all_voted = true
		for _, pdata in ipairs(getAlivePlayers()) do
			if not voted_players[pdata.player] then
				all_voted = false
				break
			end
		end
		if all_voted and round_active then
			print("[HigherLower] All players have voted. Ending minigame.")
			round_active = false
			if typeof(timer_thread) == "thread" then
				coroutine.close(timer_thread)
				timer_thread = nil
			end
			minigame_signal:Fire()
		end
	end)
	-- Start 60s timer
	timer_thread = coroutine.create(function()
		local t = 60
		while t > 0 and round_active do
			t = t - 1
			task.wait(1)
		end
		if round_active then
			print("[HigherLower] Timer expired. Eliminating non-voters and ending minigame.")
			for _, pdata in ipairs(getAlivePlayers()) do
				local player = pdata.player
				if not voted_players[player] then
					player_state[player].done = true
					server.UpdateUI.Fire(player, "Game", "HigherLowerResult", { result = "eliminate" })
					if match_ref and match_ref.eliminate_player then
						match_ref:eliminate_player(player)
					end
				end
			end
			round_active = false
			minigame_signal:Fire()
		end
	end)
	coroutine.resume(timer_thread)
end

function higherlower.stop()
	if inputConn then
		inputConn()
		inputConn = nil
	end
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
