--!strict
local Players = game:GetService("Players")
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local match_object = require(script:WaitForChild("match_object"))
local minigame_signal =
	require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local SignalPlus = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("SignalPlus"))
local WinnerChosePlayer = SignalPlus()

local match_service = {}
match_service.__index = match_service
local singleton = nil

export type MatchService = {
	match: match_object.MatchObject,
	player_connection: RBXScriptConnection?,
	player_leaving_connection: RBXScriptConnection?,
	start_timer: thread?,
	timer_duration: number,

	start_game: (self: MatchService) -> (),
	reset: (self: MatchService) -> (),
	destroy: (self: MatchService) -> (),
	get_match: (self: MatchService) -> match_object.MatchObject,
	start_timer_logic: (self: MatchService) -> (),
	cancel_timer: (self: MatchService) -> (),
}

function match_service.new(): MatchService
	if singleton then
		return singleton
	end
	local self = setmetatable({} :: any, match_service) :: MatchService

	self.match = match_object.new()
	self.start_timer = nil
	self.timer_duration = 30

	self.player_connection = Players.PlayerAdded:Connect(function(player)
		local added = self.match:add_player(player)
		if added then
			self:start_timer_logic()
		end
	end)

	self.player_leaving_connection = Players.PlayerRemoving:Connect(function(player)
		local removed = self.match:remove_player(player)
		if removed then
			self:start_timer_logic()
		end
	end)

	for _, player in pairs(Players:GetPlayers()) do
		local added = self.match:add_player(player)
		if added then
			self:start_timer_logic()
		end
	end

	singleton = self
	_G.matchservice = self
	return self :: any
end

-- Helper function to reset player state without LoadCharacter
local function reset_player_state(player)
    local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
    if player and player.Character and spawnLocation then
        local hrp = player.Character:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then
            hrp.Anchored = false
            hrp.CFrame = spawnLocation.CFrame + Vector3.new(0, 5, 0)
            hrp.Velocity = Vector3.new(0,0,0)
        end
        local humanoid = player.Character:FindFirstChild("Humanoid")
        if humanoid and humanoid:IsA("Humanoid") then
            humanoid.WalkSpeed = 16
            humanoid.JumpHeight = 7.2
            humanoid.AutoRotate = true
            humanoid.CameraOffset = Vector3.new(0,0,0)
        end
    end
end

local function cleanup_all_minigames_and_players(match)
    print("[SERVER] [matchservice] cleanup_all_minigames_and_players: starting cleanup for match state:", match:get_state())
    if match.minigames_handler and match.minigames_handler.game and match.minigames_handler.game.stop then
        print("[SERVER] [matchservice] Stopping current minigame")
        match.minigames_handler.game.stop()
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if match.players[player] then
            print("[SERVER] [matchservice] Resetting player:", player.Name)
            reset_player_state(player)
            print("[SERVER] [matchservice] Firing HideUI for player:", player.Name)
            server.HideUI.Fire(player, "Game")
        end
    end
    print("[SERVER] [matchservice] Scheduling match reset and re-add in 2 seconds")
    task.delay(2, function()
        if singleton then
            print("[SERVER] [matchservice] Resetting match object")
            singleton:reset()
            for _, player in ipairs(Players:GetPlayers()) do
				server.PlayerDataUpdated.Fire(player, player, {
					is_alive = true,
					is_spectating = false
				})
                print("[SERVER] [matchservice] Adding player to new match:", player.Name)
                singleton.match:add_player(player)
            end
			
            singleton.timer_duration = 30
            print("[SERVER] [matchservice] Starting timer logic for new round")
            singleton:start_timer_logic()
        else
            print("[SERVER] [matchservice] Singleton is nil, cannot reset match!")
        end
    end)
end

server.WinnerChosePlayer.SetCallback(function(sender, chosenUserId)
    local match = singleton.match
    if not match then
        return
    end

    -- Only allow if last_minigame_winner is set and sender is the winner
    local winner = match.last_minigame_winner
    if not winner then
        warn("[SECURITY] WinnerChosePlayer called but no last_minigame_winner is set.")
        return
    end
    if typeof(sender) ~= "Instance" or not sender:IsA("Player") or sender ~= winner then
        local senderName = (typeof(sender) == "Instance" and sender:IsA("Player") and sender.Name) or tostring(sender)
        warn("[SECURITY] Non-winner tried to choose a player for elimination:", senderName)
        return
    end

    -- If no player was chosen (chosenUserId is nil or 0), check if only one player is alive
    if not chosenUserId or chosenUserId == 0 then
        local alive_players = match:get_alive_players()
        if #alive_players == 1 then
            print("[MatchService] Only one player left, declaring them the winner and ending match.")
            match:set_state("ENDING")
            cleanup_all_minigames_and_players(match)
            return
        else
            warn("[MatchService] WinnerChosePlayer called with no player, but more than one player is alive.")
            match.last_minigame_winner = nil
            WinnerChosePlayer:Fire()
            return
        end
    end

    -- Validate chosen player
    local alive_players = match:get_alive_players()
    local chosenPlayer = game:GetService("Players"):GetPlayerByUserId(chosenUserId)
    if chosenPlayer == sender then
        warn("[SECURITY] Winner tried to select themselves for elimination.")
        return
    end
    local isValidTarget = false
    for _, pdata in ipairs(alive_players) do
        if pdata.player == chosenPlayer and chosenPlayer ~= winner then
            isValidTarget = true
            break
        end
    end
    if not isValidTarget then
        warn("[SECURITY] Winner tried to choose invalid target:", chosenUserId)
        match.last_minigame_winner = nil
        -- Continue to next minigame
        WinnerChosePlayer:Fire()
        return
    end

    -- Eliminate the chosen player
    if match.eliminate_player then
        match:eliminate_player(chosenPlayer)
    end
    -- Prevent further eliminations until next minigame
    match.last_minigame_winner = nil
    -- Continue to next minigame
    WinnerChosePlayer:Fire()
end)

minigame_signal:Connect(function()
	local service = singleton
	if not service or not service.match then
		warn("No match object found for minigame end event!")
		return
	end
	local match = service.match
	if match:get_state() == "FINISHED" or match:get_state() == "ENDING" then
		print("[MatchService] Not switching minigame: match is finished or ending.")
		cleanup_all_minigames_and_players(match)
		return
	end
	-- Lerp all TVs up for all players after each minigame
	server.UpdateUI.FireAll("Game", "PlaySFX", { name = "MonitorsBeingLifted" })
	local soundDuration = 2.926 / 0.65
	for _, tv in ipairs(CollectionService:GetTagged("TV")) do
		local startCFrame
		if tv:IsA("BasePart") then
			tv.Anchored = true
			startCFrame = tv.CFrame
		elseif tv:IsA("Model") then
			startCFrame = tv:GetPivot()
		else
			continue
		end
		local startPos = startCFrame.Position
		local targetY = tv:IsA("BasePart") and 20.095 or 30.765
		local endCFrame = CFrame.new(startPos.X, targetY, startPos.Z) * (startCFrame - startPos)
		local startTime = tick()
		local duration = soundDuration
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local alpha = math.clamp((tick() - startTime) / duration, 0, 1)
			if tv:IsA("BasePart") then
				tv.CFrame = startCFrame:Lerp(endCFrame, alpha)
			elseif tv:IsA("Model") then
				tv:PivotTo(startCFrame:Lerp(endCFrame, alpha))
			end
			if alpha >= 1 then
				conn:Disconnect()
			end
		end)
	end
	-- Wait for TVs to finish raising
	task.wait(soundDuration)
	-- Find the winner (use last_minigame_winner if set)
	local winner = match.last_minigame_winner
	local alive_players = match:get_alive_players()
	if not winner then
		winner = alive_players[1] and alive_players[1].player
		warn("[MatchService] No last_minigame_winner set, falling back to first alive player.")
	end
	local others = {}
	for _, pdata in ipairs(alive_players) do
		if pdata.player ~= winner then
			table.insert(others, { UserId = pdata.player.UserId, Name = pdata.player.Name })
		end
	end
	if winner then
		server.UpdateUI.Fire(winner, "Game", "StartWinnerChoosing", { players = others })
	end
	print("[MatchService] Waiting for winner to choose a player...")
	WinnerChosePlayer:Wait()
	print("[MatchService] Winner chose a player, starting next minigame.")
	-- Check match state again before switching to next minigame
	if match:get_state() == "FINISHED" or match:get_state() == "ENDING" then
		print("[MatchService] Not switching minigame after match end. Running cleanup.")
		cleanup_all_minigames_and_players(match)
		return
	end
	if match.minigames_handler and match.minigames_handler.switch_to_next then
		match.minigames_handler:switch_to_next(match)
	else
		warn("No minigames handler or switch_to_next function!")
	end
end)

-- Stub: Call this function when the winner has chosen and the TV is lowered
function match_service.winner_chose_player()
	WinnerChosePlayer:Fire()
end

function match_service.start_timer_logic(self: any): ()
	local player_count = self.match:get_player_count()

	-- Cancel any existing timer
	self:cancel_timer()

	-- Only start timer if match is in WAITING state
	if self.match:get_state() ~= "WAITING" then
		return
	end

	if player_count < self.match.min_players then
		-- not enough players, no timer needed
		return
	elseif player_count >= self.match.max_players then
		-- max players reached, start with short timer
		self.timer_duration = 10
		print(`Max players ({self.match.max_players}) reached! Starting in {self.timer_duration} seconds...`)

		server.RoundStarting.FireAll({
			description = `Game starting in {self.timer_duration} seconds`,
			duration = self.timer_duration,
			title = "Game Starting",
		})
	else
		-- 2+ players but not max, use longer timer
		self.timer_duration = 30
		print(`{player_count} players joined. Game will start in {self.timer_duration} seconds if no one else joins...`)

		server.RoundStarting.FireAll({
			description = `Game starting in {self.timer_duration} seconds`,
			duration = self.timer_duration,
			title = "Game Starting",
		})
	end

	-- Start the timer
	self.start_timer = task.spawn(function()
		task.wait(self.timer_duration)

		-- Double check we still have enough players and are in waiting state
		if self.match:get_player_count() >= self.match.min_players and self.match:get_state() == "WAITING" then
			print("Timer expired, starting game...")
			self:start_game()
		end

		self.start_timer = nil
	end)
end

function match_service.cancel_timer(self: MatchService): ()
	if self.start_timer then
		coroutine.close(self.start_timer)
		self.start_timer = nil
		print("Timer cancelled")
	end
end

function match_service.start_game(self: MatchService): ()
	if self.match:get_player_count() < self.match.min_players then
		return
	end

	self.match:start()
end

function match_service.reset(self: MatchService): ()
	self:cancel_timer()
	self.match:reset()
end

function match_service.destroy(self: MatchService): ()
	self:cancel_timer()

	if self.player_connection then
		self.player_connection:Disconnect()
		self.player_connection = nil
	end

	if self.player_leaving_connection then
		self.player_leaving_connection:Disconnect()
		self.player_leaving_connection = nil
	end

	self.match:reset()
end

function match_service:get_match(): match_object.MatchObject
	return self.match
end

return match_service
