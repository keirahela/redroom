--!strict
local Players = game:GetService("Players")
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local match_object = require(script:WaitForChild("match_object"))
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local SignalPlus = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("SignalPlus"))
local WinnerChosePlayer = SignalPlus()
local Notification = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Notification"))
local Maid = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Maid"))

export type MatchService = {
	__index: MatchService,
    match: any,
    matchMaid: any?,
    start_timer: thread?,
    timer_duration: number,
    player_connection: RBXScriptConnection?,
    player_leaving_connection: RBXScriptConnection?,
    create_new_match: (self: MatchService, with_intermission: boolean) -> (),
    start_timer_logic: (self: MatchService) -> (),
	new: () -> MatchService,
}

local match_service = {} :: MatchService
match_service.__index = match_service

-- Track extermination timer state
local extermination_timer_active = false
local extermination_timer_start = 0
local extermination_timer_duration = 0

local choosing_active = false
local choosingTimerThread: thread? = nil

function match_service.new(): MatchService
    print("[DEBUG][match_service.new] called")
    local self = {
        match = nil,
        matchMaid = nil,
        start_timer = nil,
        timer_duration = 30,
        player_connection = nil,
        player_leaving_connection = nil,
    }
    setmetatable(self, match_service)
    self:create_new_match(false) -- No intermission on first match
    print("[DEBUG][match_service.new] Setting up PlayerAdded connection")
    self.player_connection = Players.PlayerAdded:Connect(function(player)
        print("[DEBUG][PlayerAdded] Player joined:", player and player.Name or tostring(player))
        local added = self.match:add_player(player)
        print("[DEBUG][PlayerAdded] add_player returned:", added)
        if added then
            self:start_timer_logic()
        end
    end)
    print("[DEBUG][match_service.new] PlayerAdded connection set up")
    -- Add all currently present players to the match and start timer logic
    for _, player in ipairs(Players:GetPlayers()) do
        local added = self.match:add_player(player)
        if added then
            self:start_timer_logic()
        end
    end
    return self :: MatchService
end

function match_service:create_new_match(with_intermission: boolean)
    if self.matchMaid then
        self.matchMaid:DoCleaning()
    end
    self.matchMaid = Maid.new()
    self.match = match_object.new()
    -- Set all TVs to their top position instantly
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
        if tv:IsA("BasePart") then
            tv.CFrame = endCFrame
        elseif tv:IsA("Model") then
            tv:PivotTo(endCFrame)
        end
    end
    for _, player in ipairs(Players:GetPlayers()) do
        self.match:add_player(player)
    end
    -- Teleport all players to SpawnLocation immediately
    local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
    for _, player in ipairs(Players:GetPlayers()) do
        if player and player.Character and spawnLocation then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp and hrp:IsA("BasePart") then
                hrp.Anchored = false
                hrp.CFrame = spawnLocation.CFrame + Vector3.new(0, 5, 0)
                hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
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
    local stateChangedConn = self.match.state_changed:Connect(function(new_state)
        if new_state == "WAITING" then
            self:start_timer_logic()
        elseif new_state == "FINISHED" or new_state == "ENDING" then
            task.defer(function()
                self:create_new_match(true) -- Intermission after first round
            end)
        end
    end)
    self.matchMaid:GiveTask(function()
        stateChangedConn:Disconnect()
    end)
    -- At the start of the intermission ("New round starts in"), fire the CancelAllAnimations remote to all clients.
    if with_intermission then
        server.CancelAllAnimations.FireAll()
    end
    if with_intermission then
        local intermission_duration = 30
        task.spawn(function()
            for t = intermission_duration, 1, -1 do
                Notification.ShowAll("New round starts in: " .. t)
                task.wait(1)
            end
            Notification.CloseAll()
            self:start_timer_logic()
        end)
    else
        self:start_timer_logic()
    end
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
    choosing_active = false
    if choosingTimerThread then
        pcall(task.cancel, choosingTimerThread)
        choosingTimerThread = nil
    end
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
        if match.minigames_handler and match.minigames_handler.switch_to_next then
            match.minigames_handler:switch_to_next(match, match.minigame_signal)
        else
            warn("No minigames handler or switch_to_next function!")
        end
    end)
end

local function startExterminationTimer(duration)
	extermination_timer_active = true
	extermination_timer_start = os.clock()
	extermination_timer_duration = duration
    for t = duration, 1, -1 do
        Notification.ShowAll("Extermination in: " .. t)
        task.wait(1)
    end
    Notification.CloseAll()
	extermination_timer_active = false
	extermination_timer_start = 0
	extermination_timer_duration = 0
end

local function handleWinnerChoice(winner, chosenUserId, others)
    -- Your existing logic for processing the choice
    WinnerChosePlayer:Fire(chosenUserId)
end

local function startPlayerChoosingTimer(winner, others, duration)
    choosing_active = true
    local conn
    conn = WinnerChosePlayer:Connect(function(chosenUserId)
        if not choosing_active then return end
        if self.match:get_state() ~= "IN_PROGRESS" then return end
        -- Check winner is still present
        local winnerStillAlive = false
        for _, pdata in ipairs(self.match:get_alive_players()) do
            if pdata.player == winner then
                winnerStillAlive = true
                break
            end
        end
        if not winnerStillAlive then
            choosing_active = false
            if conn then conn:Disconnect() end
            Notification.CloseAll()
            for _, p in ipairs(Players:GetPlayers()) do
                server.HideUI.Fire(p, "Game")
            end
            self.match:set_state("ENDING")
            self.match:cleanup()
            return
        end
        choosing_active = false
        if conn then conn:Disconnect() end
        handleWinnerChoice(winner, chosenUserId, others)
    end)
    choosingTimerThread = task.spawn(function()
        for t = duration, 1, -1 do
            Notification.ShowAll(winner.Name .. " is choosing player: " .. t)
            if not choosing_active then break end
            task.wait(1)
        end
        Notification.CloseAll()
        if choosing_active then
            choosing_active = false
            if conn then conn:Disconnect() end
            local validTargets = {}
            for _, p in ipairs(others) do
                if p.UserId ~= winner.UserId then
                    table.insert(validTargets, p)
                end
            end
            if #validTargets > 0 then
                local randomTarget = validTargets[math.random(1, #validTargets)]
                handleWinnerChoice(winner, randomTarget.UserId, others)
            else
                handleWinnerChoice(winner, 0, others)
            end
        end
    end)
end

-- Remove the guarded WinnerChosePlayer:Connect block entirely
WinnerChosePlayer:Connect(function(chosenUserId)
    if not self.match or self.match:get_state() ~= "IN_PROGRESS" then
        warn("[MatchService] Ignoring WinnerChosePlayer: match is not in progress.")
        return
    end
    if not self.match.last_minigame_winner then
        warn("[MatchService] Ignoring WinnerChosePlayer: no last_minigame_winner set.")
        return
    end
    choosing_active = false
    local match = self.match

    -- Only allow if last_minigame_winner is set and sender is the winner
    local winner = match.last_minigame_winner
    if not winner then
        warn("[SECURITY] WinnerChosePlayer called but no last_minigame_winner is set.")
        return
    end
    if typeof(winner) ~= "Instance" or not winner:IsA("Player") then
        local winnerName = (typeof(winner) == "Instance" and winner:IsA("Player") and winner.Name) or tostring(winner)
        warn("[SECURITY] Non-winner tried to choose a player for elimination:", winnerName)
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
    if chosenPlayer == winner then
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
    print("[MatchService][DEBUG] minigame_signal received. Processing minigame end...")
    local service = match_service
    if not service or not service.match then
        warn("No match object found for minigame end event!")
        return
    end
    local match = service.match
    print("[MatchService][DEBUG] Current match state:", match:get_state())
	if match:get_state() == "FINISHED" or match:get_state() == "ENDING" then
		print("[MatchService] Not switching minigame: match is finished or ending.")
		match:cleanup()
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
		Notification.ShowAll(winner.Name .. " won the minigame, choosing player")
		server.UpdateUI.Fire(winner, "Game", "StartWinnerChoosing", { players = others })
		-- Replicate timer to all non-winners
		task.spawn(function()
			local winner: Player? = match.last_minigame_winner
			Notification.ShowAll((winner and winner.Name or "") .. " won the minigame, choosing player")
			server.UpdateUI.Fire(winner, "Game", "StartWinnerChoosing", { players = others })
			-- Replicate timer to all non-winners
			startPlayerChoosingTimer(winner, others, 20)
		end)
	end
	print("[MatchService] Waiting for winner to choose a player...")
	WinnerChosePlayer:Wait()
	print("[MatchService] Winner chose a player, starting next minigame.")
	-- Check match state again before switching to next minigame
	if match:get_state() == "FINISHED" or match:get_state() == "ENDING" then
		print("[MatchService] Not switching minigame after match end. Running cleanup.")
		match:cleanup()
		return
	end
	-- Lower all TVs before starting the next minigame
	server.UpdateUI.FireAll("Game", "PlaySFX", { name = "MonitorsBeingLifted" })
	local lowerSoundDuration = 2.926 / 0.65
	for _, tv in ipairs(CollectionService:GetTagged("TV")) do
		local startCFrame
		if tv:IsA("BasePart") then
			startCFrame = tv.CFrame
		elseif tv:IsA("Model") then
			startCFrame = tv:GetPivot()
		else
			continue
		end
		local startPos = startCFrame.Position
		local targetY = tv:IsA("BasePart") and 9.69 or 20.36
		local endCFrame = CFrame.new(startPos.X, targetY, startPos.Z) * (startCFrame - startPos)
		local startTime = tick()
		local duration = lowerSoundDuration
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
	task.wait(lowerSoundDuration)
	if match.minigames_handler and match.minigames_handler.switch_to_next then
		match.minigames_handler:switch_to_next(match, match.minigame_signal)
	else
		warn("No minigames handler or switch_to_next function!")
	end
end)

-- Stub: Call this function when the winner has chosen and the TV is lowered
function match_service.winner_chose_player()
	WinnerChosePlayer:Fire()
end

function match_service.start_timer_logic(self: MatchService): ()
    local player_count = self.match:get_player_count()
    print("[DEBUG][start_timer_logic] player_count:", player_count, "min_players:", self.match.min_players, "state:", self.match:get_state())
    -- Cancel any existing timer
    self:cancel_timer()
    -- Only start timer if match is in WAITING state
    if self.match:get_state() ~= "WAITING" then
        print("[DEBUG][start_timer_logic] Not in WAITING state, aborting timer logic.")
        return
    end
    if player_count < self.match.min_players then
        print("[DEBUG][start_timer_logic] Not enough players, no timer started.")
        return
    elseif player_count >= self.match.max_players then
        self.timer_duration = 10
        print("[DEBUG][start_timer_logic] Max players reached! Starting in", self.timer_duration, "seconds...")
        task.spawn(function()
            startExterminationTimer(self.timer_duration)
        end)
        server.RoundStarting.FireAll({
            description = `Game starting in {self.timer_duration} seconds`,
            duration = self.timer_duration,
            title = "Game Starting",
        })
    else
        self.timer_duration = 5
        print("[DEBUG][start_timer_logic] Enough players. Game will start in", self.timer_duration, "seconds if no one else joins...")
        task.spawn(function()
            startExterminationTimer(self.timer_duration)
        end)
        server.RoundStarting.FireAll({
            description = `Game starting in {self.timer_duration} seconds`,
            duration = self.timer_duration,
            title = "Game Starting",
        })
    end
    self.start_timer = task.spawn(function()
        task.wait(self.timer_duration)
        print("[DEBUG][start_timer_logic] Timer expired. player_count:", self.match:get_player_count(), "state:", self.match:get_state())
        if self.match:get_player_count() >= self.match.min_players and self.match:get_state() == "WAITING" then
            print("[DEBUG][start_timer_logic] Timer expired, starting game...")
            self:start_game()
        else
            print("[DEBUG][start_timer_logic] Timer expired, but not enough players or not in WAITING state.")
        end
        self.start_timer = nil
    end)
end

function match_service.cancel_timer(self: MatchService): ()
	if self.start_timer then
		pcall(task.cancel, self.start_timer)
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
