local react = {}
react.__index = react
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Players = game:GetService("Players")

local match_ref = nil
local running = false
local inputConn = nil
local timer_thread = nil
local countdown_thread = nil
local phase = "wait"
local player_results = {}
local player_clicked = {}
local player_failed = {}

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

function react.start(match)
	match_ref = match
	running = false
	player_results = {}
	player_clicked = {}
	player_failed = {}
	phase = "wait"

	if inputConn then inputConn() end
	if timer_thread then coroutine.close(timer_thread) end
	if countdown_thread then coroutine.close(countdown_thread) end

	-- 3 second countdown
	countdown_thread = coroutine.create(function()
		for n = 3, 1, -1 do
			for _, pdata in ipairs(getAlivePlayers()) do
				server.UpdateUI.Fire(pdata.player, "Game", "ReactCountdown", tostring(n))
			end
			task.wait(1)
		end
		for _, pdata in ipairs(getAlivePlayers()) do
			server.UpdateUI.Fire(pdata.player, "Game", "ReactCountdown", "")
		end
		-- Start overall timer
		running = true
		phase = "wait"
		local timeLeft = 60
		timer_thread = coroutine.create(function()
			while timeLeft > 0 and running do
				for _, pdata in ipairs(getAlivePlayers()) do
					server.UpdateUI.Fire(pdata.player, "Game", "ReactTime", timeLeft)
				end
				task.wait(1)
				timeLeft = timeLeft - 1
			end
			if running then
				-- Time's up, fail all who haven't finished
				for _, pdata in ipairs(getAlivePlayers()) do
					if not player_results[pdata.player] then
						player_results[pdata.player] = "timeout"
						server.UpdateUI.Fire(pdata.player, "Game", "ReactResult", { result = "timeout" })
						if match_ref and match_ref.eliminate_player then
							match_ref:eliminate_player(pdata.player)
						end
					end
				end
				task.wait(2)
				minigame_signal:Fire()
			end
		end)
		coroutine.resume(timer_thread)

		-- Random wait before "CLICK!"
		local waitTime = math.random(15, 40) / 10 -- 1.5s to 4s
		for _, pdata in ipairs(getAlivePlayers()) do
			server.UpdateUI.Fire(pdata.player, "Game", "ReactPhase", "wait")
		end
		task.wait(waitTime)
		phase = "click"
		local clickDeadline = os.clock() + 3
		for _, pdata in ipairs(getAlivePlayers()) do
			server.UpdateUI.Fire(pdata.player, "Game", "ReactPhase", "click")
		end

		-- 3s to click
		while os.clock() < clickDeadline and running do
			if #player_clicked >= #getAlivePlayers() then break end
			task.wait(0.05)
		end
		phase = "done"
		for _, pdata in ipairs(getAlivePlayers()) do
			server.UpdateUI.Fire(pdata.player, "Game", "ReactPhase", "done")
		end
		-- Fail anyone who didn't click in time
		for _, pdata in ipairs(getAlivePlayers()) do
			if not player_results[pdata.player] then
				player_results[pdata.player] = "fail_slow"
				server.UpdateUI.Fire(pdata.player, "Game", "ReactResult", { result = "fail_slow" })
				if match_ref and match_ref.eliminate_player then
					match_ref:eliminate_player(pdata.player)
				end
			end
		end
		task.wait(2)
		minigame_signal:Fire()
	end)
	coroutine.resume(countdown_thread)

	-- Listen for player input
	inputConn = server.MinigameInput.SetCallback(function(player, input_type, input_data)
		if not running or player_results[player] then return end
		if input_type == "react_fail" and phase == "wait" then
			player_results[player] = "fail_early"
			server.UpdateUI.Fire(player, "Game", "ReactResult", { result = "fail_early" })
			if match_ref and match_ref.eliminate_player then
				match_ref:eliminate_player(player)
			end
		elseif input_type == "react_click" and phase == "click" then
			player_results[player] = "success"
			table.insert(player_clicked, player)
			server.UpdateUI.Fire(player, "Game", "ReactResult", { result = "success" })
		else
			-- Ignore any other input
		end
	end)
end

function react.stop()
	running = false
	if inputConn then inputConn() inputConn = nil end
	if timer_thread then coroutine.close(timer_thread) timer_thread = nil end
	if countdown_thread then coroutine.close(countdown_thread) countdown_thread = nil end
end

return react
