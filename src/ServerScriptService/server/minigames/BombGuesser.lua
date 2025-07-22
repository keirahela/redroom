local bombguesser = {}
bombguesser.__index = bombguesser
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

local player_state = {}
local match_ref = nil
local inputConn = nil
-- Remove global dud_index, now each player gets their own
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
	round_active = true
	if inputConn then
		inputConn()
		inputConn = nil
	end
	for _, pdata in ipairs(getAlivePlayers()) do
		-- Give each player their own random dud
		player_state[pdata.player] = { picked = false, dud_index = math.random(1, 3) }
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
			local player_dud = player_state[player].dud_index
			print("[BombGuesser] Parsed pick:", pick, "player_dud_index:", player_dud)
			if not pick then print("[BombGuesser] Invalid pick!"); return end
			player_state[player].picked = true
			if pick == player_dud then
				print("[BombGuesser] Player survived! Sending advance.")
				server.UpdateUI.Fire(player, "Game", "BombGuesserResult", { result = "advance", dud = player_dud, pick = pick })
			else
				print("[BombGuesser] Player exploded! Sending eliminate.")
				server.UpdateUI.Fire(player, "Game", "BombGuesserResult", { result = "eliminate", dud = player_dud, pick = pick })
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
			print("[BombGuesser] All players picked. Adding 3 second delay before ending minigame.")
			-- Add 3 second delay to show "You survived!" message using coroutine
			task.spawn(function()
				task.wait(3)
				minigame_signal:Fire()
			end)
		end
	end)
	print("[BombGuesser][SERVER] SetCallback registered for BombGuesser")
	-- Timeout after 60 seconds (changed from 20)
	timer_thread = coroutine.create(function()
		local t = 60
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
					local player_dud = player_state[player] and player_state[player].dud_index or math.random(1, 3)
					server.UpdateUI.Fire(player, "Game", "BombGuesserResult", { result = "eliminate", dud = player_dud, pick = nil })
					if match_ref and match_ref.eliminate_player then
						match_ref:eliminate_player(player)
					end
				end
			end
			round_active = false
			-- Add delay here too for timer expiry case using coroutine
			task.spawn(function()
				task.wait(3)
				minigame_signal:Fire()
			end)
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
	round_active = false
	if typeof(timer_thread) == "thread" then
		coroutine.close(timer_thread)
		timer_thread = nil
	end
end

return bombguesser
