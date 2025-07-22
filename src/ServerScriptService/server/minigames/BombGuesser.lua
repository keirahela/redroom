local bombguesser = {}
bombguesser.__index = bombguesser
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

local player_state = {}
local match_ref = nil
local inputConn = nil
local dud_index = nil
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

function bombguesser.start(match)
	print("[BombGuesser][SERVER] Starting BombGuesser minigame")
	player_state = {}
	match_ref = match
	dud_index = math.random(1, 3)
	round_active = true
	if inputConn then
		inputConn()
		inputConn = nil
	end
	for _, pdata in ipairs(getAlivePlayers()) do
		player_state[pdata.player] = { picked = false }
		server.UpdateUI.Fire(pdata.player, "Game", "BombGuesserStart", { numBombs = 3 })
	end
	inputConn = server.MinigameInput.SetCallback(function(player, input_type, input_data)
		print("[BombGuesser] Received input:", player and player.Name, input_type, input_data and (typeof(input_data) == "table" and input_data.zone or tostring(input_data)))
		if not round_active or not player_state[player] or player_state[player].picked then
			print("[BombGuesser] Ignored input: round_active=", round_active, "picked=", player_state[player] and player_state[player].picked)
			return
		end
		if input_type == "bomb_pick" and type(input_data) == "table" and input_data.zone then
			local pick = tonumber(input_data.zone:match("%d+"))
			print("[BombGuesser] Parsed pick:", pick, "dud_index:", dud_index)
			if not pick then print("[BombGuesser] Invalid pick!"); return end
			player_state[player].picked = true
			if pick == dud_index then
				print("[BombGuesser] Player survived! Sending advance.")
				server.UpdateUI.Fire(player, "Game", "BombGuesserResult", { result = "advance", dud = dud_index, pick = pick })
			else
				print("[BombGuesser] Player exploded! Sending eliminate.")
				server.UpdateUI.Fire(player, "Game", "BombGuesserResult", { result = "eliminate", dud = dud_index, pick = pick })
				if match_ref and match_ref.eliminate_player then
					match_ref:eliminate_player(player)
				end
			end
		end
		-- Check if all alive players have picked
		local all_picked = true
		for _, pdata in ipairs(getAlivePlayers()) do
			if not player_state[pdata.player] or not player_state[pdata.player].picked then
				all_picked = false
				break
			end
		end
		if all_picked and round_active then
			round_active = false
			print("[BombGuesser] All players picked. Ending minigame.")
			minigame_signal:Fire()
		end
	end)
	print("[BombGuesser][SERVER] SetCallback registered for BombGuesser")
	-- Timeout after 20 seconds
	timer_thread = coroutine.create(function()
		local t = 20
		while t > 0 and round_active do
			for _, pdata in ipairs(getAlivePlayers()) do
				local player = pdata.player
				server.UpdateUI.Fire(player, "Game", "BombGuesserTime", { time = t })
			end
			t = t - 1
			task.wait(1)
		end
		if round_active then
			for _, pdata in ipairs(getAlivePlayers()) do
				local player = pdata.player
				if not player_state[player] or not player_state[player].picked then
					server.UpdateUI.Fire(player, "Game", "BombGuesserResult", { result = "eliminate", dud = dud_index, pick = nil })
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

function bombguesser.stop()
	if inputConn then
		inputConn()
		inputConn = nil
	end
	player_state = {}
	match_ref = nil
	dud_index = nil
	round_active = false
	if typeof(timer_thread) == "thread" then
		coroutine.close(timer_thread)
		timer_thread = nil
	end
end

return bombguesser
