local ratrace = {}
ratrace.__index = ratrace
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

local RAT_COUNT = 6
local TRACK_LENGTH = 0.9 -- UDim2 X scale for finish line
local TICK_RATE = 0.1
local ENCOURAGE_BOOST = 0.02 -- slower boost
local ENCOURAGE_COOLDOWN = 2
local RAT_MOVE_MIN = 0.003 -- much slower
local RAT_MOVE_MAX = 0.01

local rat_positions = {}
local player_choices = {}
local encourage_timestamps = {}
local running = false
local match_ref = nil
local update_thread = nil
local countdown_thread = nil

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

local function allPlayersSelected()
	for _, pdata in ipairs(getAlivePlayers()) do
		if not player_choices[pdata.player] then
			return false
		end
	end
	return true
end

function ratrace.start(match)
	match_ref = match
	rat_positions = {}
	player_choices = {}
	encourage_timestamps = {}
	running = false
	for i = 1, RAT_COUNT do
		rat_positions[i] = 0
	end
	for _, pdata in ipairs(getAlivePlayers()) do
		player_choices[pdata.player] = nil
		encourage_timestamps[pdata.player] = 0
	end

	if update_thread then
		coroutine.close(update_thread)
	end
	if countdown_thread then
		coroutine.close(countdown_thread)
	end

	-- Listen for player input
	if ratrace._inputConn then
		ratrace._inputConn()
	end
	ratrace._inputConn = server.MinigameInput.SetCallback(function(player, input_type, input_data)
		if running then return end
		if not player_choices[player] and input_type == "rat_select" and input_data and input_data.zone then
			local ratIdx = tonumber(input_data.zone:match("rat(%d)"))
			if ratIdx and ratIdx >= 1 and ratIdx <= RAT_COUNT then
				player_choices[player] = ratIdx
				-- Check if all players have selected
				if allPlayersSelected() and not running then
					running = true
					-- 3 second countdown, broadcast to all
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
						-- Start race
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

	-- Start overall timer (60s)
	task.spawn(function()
		local timeLeft = 60
		while timeLeft > 0 and not running do
			for _, pdata in ipairs(getAlivePlayers()) do
				server.UpdateUI.Fire(pdata.player, "Game", "RatRaceTime", timeLeft)
			end
			task.wait(1)
			timeLeft = timeLeft - 1
		end
		if not running then
			-- Eliminate players who didn't pick
			for _, pdata in ipairs(getAlivePlayers()) do
				if not player_choices[pdata.player] then
					if match_ref and match_ref.eliminate_player then
						match_ref:eliminate_player(pdata.player)
					end
					server.UpdateUI.Fire(pdata.player, "Game", "RatRaceResult", { result = "timeout" })
				end
			end
			-- Start race with remaining players
			if allPlayersSelected() then
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
					startRace()
				end)
				coroutine.resume(countdown_thread)
			else
				-- If no one left, just end minigame
				task.wait(2)
				minigame_signal:Fire()
			end
		end
	end)
end

function startRace()
	if update_thread then coroutine.close(update_thread) end
	update_thread = coroutine.create(function()
		while true do
			local winner = nil
			for i = 1, RAT_COUNT do
				local move = math.random() * (RAT_MOVE_MAX - RAT_MOVE_MIN) + RAT_MOVE_MIN
				rat_positions[i] = math.min(rat_positions[i] + move, TRACK_LENGTH)
				if rat_positions[i] >= TRACK_LENGTH and not winner then
					winner = i
				end
			end
			local positions = {}
			for i = 1, RAT_COUNT do
				table.insert(positions, rat_positions[i])
			end
			for _, pdata in ipairs(getAlivePlayers()) do
				server.UpdateUI.Fire(pdata.player, "Game", "RatRacePositions", positions)
			end
			if winner then
				-- Find last place rat (lowest position)
				local lastPos = math.huge
				local lastRats = {}
				for i = 1, RAT_COUNT do
					if rat_positions[i] < lastPos then
						lastPos = rat_positions[i]
					end
				end
				for i = 1, RAT_COUNT do
					if math.abs(rat_positions[i] - lastPos) < 1e-4 then
						table.insert(lastRats, i)
					end
				end
				-- Eliminate all players who picked a last-place rat
				for player, ratIdx in pairs(player_choices) do
					if ratIdx and table.find(lastRats, ratIdx) then
						if match_ref and match_ref.eliminate_player then
							match_ref:eliminate_player(player)
						end
						server.UpdateUI.Fire(player, "Game", "RatRaceResult", { result = "eliminated", rat = ratIdx })
					else
						server.UpdateUI.Fire(player, "Game", "RatRaceResult", { result = "safe", rat = ratIdx })
					end
				end
				task.wait(2)
				minigame_signal:Fire()
				break
			end
			task.wait(TICK_RATE)
		end
	end)
	coroutine.resume(update_thread)
end

function ratrace.stop()
	running = false
	if ratrace._inputConn then
		ratrace._inputConn()
		ratrace._inputConn = nil
	end
	if update_thread then
		coroutine.close(update_thread)
		update_thread = nil
	end
	if countdown_thread then
		coroutine.close(countdown_thread)
		countdown_thread = nil
	end
end

return ratrace
