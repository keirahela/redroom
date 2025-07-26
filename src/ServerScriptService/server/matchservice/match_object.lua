--!strict
local DISABLE_DYING_FOR_TESTING = false -- Set to true to disable dying for testing all minigames
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local data = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("data"))
local minigames = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigames"))
local Notification = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Notification"))
local SignalPlus = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("SignalPlus"))
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local CHARACTER_POSITIONS = workspace.Chairs

local match_object = {}
match_object.__index = match_object

-- Add timer and connection management
function match_object:_init_state()
    self.timers = {}
    self.connections = {}
    self.minigame = nil
    self.last_minigame_winner = nil
    self.choosing_active = false
    self.choosingTimerThread = nil
end

export type MatchState = "WAITING" | "STARTING" | "IN_PROGRESS" | "ENDING" | "FINISHED"

export type PlayerData = {
	player: Player,
	is_alive: boolean,
	is_spectating: boolean,
	joined_at: number,
	tv_id: number?,
}

export type MatchObject = {
	players: {[Player]: PlayerData},
	state: MatchState,
	start_time: number?,
	round_number: number,
	max_players: number,
	min_players: number,
	minigames_handler: any, -- Remove explicit MinigameModule type to avoid type errors
	last_minigame_winner: Player?,
	state_changed: SignalPlus.Signal<MatchState>,
	minigame: any?, -- Allow minigame instance
	start: (self: MatchObject) -> (),
	add_player: (self: MatchObject, player: Player) -> boolean,
	remove_player: (self: MatchObject, player: Player) -> boolean,
	reset: (self: MatchObject) -> (),
	get_player_count: (self: MatchObject) -> number,
	get_alive_players: (self: MatchObject) -> {PlayerData},
	get_spectating_players: (self: MatchObject) -> {PlayerData},
	eliminate_player: (self: MatchObject, player: Player) -> (),
	award_coins: (self: MatchObject, player: Player, amount: number) -> (),
	set_state: (self: MatchObject, new_state: MatchState) -> (),
	get_state: (self: MatchObject) -> MatchState,
	is_player_alive: (self: MatchObject, player: Player) -> boolean,
	get_player_data: (self: MatchObject, player: Player) -> PlayerData?,
	cleanup: (self: MatchObject) -> (),
}

function match_object.new(): MatchObject
    local self = setmetatable({}, match_object)
    self.players = {}
    self.state = "WAITING"
    self.start_time = nil
    self.minigames_handler = minigames.new()
    self.round_number = 0
    self.max_players = 6
    self.min_players = 2
    self:_init_state()
    self.last_minigame_winner = nil
    self.state_changed = SignalPlus()
    self.minigame_signal = SignalPlus() -- per-match minigame signal

    print("[MATCH_OBJECT] Created new match_object:", tostring(self), "minigame_signal:", tostring(self.minigame_signal))
    -- Connect minigame_signal to post-minigame flow
    print("[DEBUG] Connecting minigame_signal:", tostring(self.minigame_signal), "for match_object:", tostring(self))
    self.minigame_signal:Connect(function()
        print("[DEBUG] minigame_signal received in match_object:", tostring(self.minigame_signal), "for match_object:", tostring(self))
        print("[DEBUG] minigame_signal fired: raising TVs and starting winner choosing phase")
        -- 1. Raise TVs for all players
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
        -- 2. Start winner choosing phase
        print("[DEBUG] Starting winner choosing phase for match_object:", tostring(self))
        if self.start_winner_choosing_phase then
            self:start_winner_choosing_phase()
        else
            warn("[match_object] start_winner_choosing_phase not implemented!")
        end
    end)
    return self
end

function match_object:stop_minigame()
    if self.minigame and type(self.minigame.stop) == "function" then
        self.minigame:stop()
        self.minigame = nil
    end
end

function match_object:start_timer(name, func)
    self:stop_timer(name)
    local thread = task.spawn(func)
    self.timers[name] = thread
end

function match_object:stop_timer(name)
    local thread = self.timers[name]
    if thread then
        pcall(task.cancel, thread)
        self.timers[name] = nil
    end
end

function match_object:cleanup_timers()
    for name, thread in pairs(self.timers) do
        pcall(task.cancel, thread)
    end
    self.timers = {}
end

function match_object:connect(name, conn)
    self:disconnect(name)
    self.connections[name] = conn
end

function match_object:disconnect(name)
    local conn = self.connections[name]
    if conn then
        conn:Disconnect()
        self.connections[name] = nil
    end
end

function match_object:cleanup_connections()
    for name, conn in pairs(self.connections) do
        conn:Disconnect()
    end
    self.connections = {}
end

local function reset_player_state(player)
    local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
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

function match_object:cleanup()
    self:stop_minigame()
    self:cleanup_timers()
    self:cleanup_connections()
    self.last_minigame_winner = nil
    self.choosing_active = false
    self.choosingTimerThread = nil
    for player, _ in pairs(self.players) do
        reset_player_state(player)
    end
    self.players = {}
    self.state = "WAITING"
    self.start_time = nil
    self.round_number = 0
    -- Do not attempt to reset/reuse this object after cleanup; let match_service create a new one.
end

match_object.cleanup = match_object.cleanup

function match_object.start(self: MatchObject): ()
    if self.state ~= "WAITING" then
        print("[DEBUG] start() called but state is not WAITING, aborting")
        return
    end
    print("[DEBUG] Starting new round, resetting player states...")
    local player_count = self:get_player_count()
    if player_count < self.min_players then
        print("[DEBUG] Not enough players to start round: " .. tostring(player_count))
        return
    end
    self.last_minigame_winner = nil -- Reset winner at the start of each round
    self:set_state("STARTING")
    self.start_time = tick()
    self.round_number = 1
    for player, data in pairs(self.players) do
        data.is_alive = true
        data.is_spectating = false
        print("[DEBUG] Setting player state to alive for:", player.Name)
        server.PlayerDataUpdated.Fire(player, player, {
            is_alive = data.is_alive,
            is_spectating = data.is_spectating,
        })
    end
    server.RoundStarting.FireAll({
        description = "Game is starting in 3 seconds",
        duration = 3,
        title = "Match Starting"
    })
    -- Fade to black before pivoting players
    server.WakeUpTransition.FireAll("fadeout", 2)
    task.wait(2)
    local iteration = 0
    for player, data in next, self.players do
        iteration += 1
        local this_iteration = iteration
        task.spawn(function()
            local character = player.Character
            if not character then
                character = player.CharacterAdded:Wait()
            end
            if not character then
                print("[DEBUG] No character for player:", player.Name)
                return
            end
            local targetCFrame: CFrame = CHARACTER_POSITIONS:FindFirstChild(tostring(this_iteration)).CFrame * CFrame.new(0, 2, 0)
            if not targetCFrame then
                print("[DEBUG] No chair for player:", player.Name)
                return
            end
            local pos = targetCFrame.Position
            local orientation = targetCFrame - pos
            local tpCFrame = CFrame.new(pos.X, 8.7, pos.Z) * orientation
            server.ShowUI.Fire(player, "Game", this_iteration)
            print("[DEBUG] ShowUI fired for player:", player.Name)
            local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChild("Humanoid")
            if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
                humanoidRootPart.Anchored = true
                humanoidRootPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
            end
            if humanoid and humanoid:IsA("Humanoid") then
                humanoid.WalkSpeed = 0
                humanoid.JumpHeight = 0
                humanoid.AutoRotate = false
            end
            character:PivotTo(tpCFrame)
            server.TeleportCharacter.Fire(player, tpCFrame)
            print("[DEBUG] TeleportCharacter fired for player:", player.Name)
            task.wait()
            if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
                humanoidRootPart.Anchored = true
            end
            self.players[player].tv_id = this_iteration
        end)
    end
    server.PlaySeatAnimation.FireAll("71528301881949")
    task.wait(1)
    server.WakeUpTransition.FireAll("fadein", 3)
    -- Wait for fade in and 15s before starting minigame
    task.delay(3 + 15, function()
        print("[DEBUG] Lowering TVs and starting minigame...")
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
            local targetY = tv:IsA("BasePart") and 9.69 or 20.36
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
        self.last_minigame_winner = nil -- Reset winner before each minigame
        self:set_state("IN_PROGRESS")
        print("[DEBUG] Calling minigames_handler.start_game...")
        self.minigames_handler.start_game(self.minigames_handler, self, self.minigame_signal)
        print("[DEBUG] minigames_handler.start_game called.")
        self.minigame = self.minigames_handler.game
        print("[DEBUG] minigame instance set.")
        if self.minigame and self.minigame.inputConn then
            print("[DEBUG] minigame input callback set.")
        else
            print("[DEBUG] minigame input callback NOT set!")
        end
    end)
end

function match_object.add_player(self: MatchObject, player: Player): boolean
    print("[DEBUG][add_player] Adding player:", player and player.Name or tostring(player))
    if not player or not player.Parent then
        print("[DEBUG][add_player] Player is nil or not parented.")
        return false
    end
    if self.players[player] then
        print("[DEBUG][add_player] Player already in match.")
        return false
    end
    local player_data: PlayerData = {
        player = player,
        is_alive = self.state == "WAITING",
        is_spectating = self.state ~= "WAITING",
        joined_at = tick()
    }
    server.PlayerDataUpdated.Fire(player, player, {
        is_alive = self.state == "WAITING",
        is_spectating = self.state ~= "WAITING"
    })
    self.players[player] = player_data
    print("[DEBUG][add_player] Player added. Total players:", self:get_player_count(), "State:", self.state)
    return true
end

function match_object.remove_player(self: MatchObject, player: Player): boolean
	if not self.players[player] then
		return false
	end
	
	-- Lerp TV up for this player (in case of disconnect)
	local player_data = self.players[player]
	local tv_id = player_data and player_data.tv_id
	if tv_id then
		-- Play MonitorsBeingLifted sound for all players at default speed (0.45)
		server.UpdateUI.FireAll("Game", "PlaySFX", { name = "MonitorsBeingLifted" })
		local soundDuration = 2.926 / 0.65
		for _, tv in ipairs(CollectionService:GetTagged("TV")) do
			local tvId = tv:GetAttribute("id")
			if tostring(tvId) == tostring(tv_id) then
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
		end
	end
	self.players[player] = nil
	
	print(`{player.Name} was removed`)
	
	if self:get_state() == "IN_PROGRESS" and self:get_player_count() <= 1 then
		self:set_state("FINISHED")
	end
	
	return true
end

function match_object.reset(self: MatchObject): ()
	for player, data in pairs(self.players) do
		server.HideUI.Fire(player, "Game")
	end
	self.players = {}
	self.state = "WAITING"
	self.start_time = nil
	self.round_number = 0
	self.last_minigame_winner = nil -- Also reset winner on full match reset
	-- Re-add all players and set them alive/not spectating
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		self:add_player(player)
	end

	if self.state_changed then
		self.state_changed:Fire(self.state)
	end
end

function match_object.get_player_count(self: MatchObject): number
	local count = 0
	for _ in pairs(self.players) do
		count += 1
	end
	
	return count
end

function match_object.get_alive_players(self: MatchObject): { PlayerData }
	local alive_players = {}
	
	for player, data in pairs(self.players) do
		if data.is_alive then
			table.insert(alive_players, data)
		end
	end
	
	return alive_players
end

-- In eliminate_player, only call reset_player_state(player) and do not reference singleton
function match_object.eliminate_player(self: MatchObject, player: Player): ()
    if DISABLE_DYING_FOR_TESTING then
        print("[TESTING] Dying is disabled. Skipping elimination for", player.Name)
        return
    end
    local player_data = self.players[player]
    if not player_data then
        return
    end

    local current_data = data.takeLives(player, 1)
    local lives = 0
    if current_data and current_data.Lives then
        lives = current_data.Lives
    end

    if lives > 0 then
        -- Player lost a life but is not eliminated
        server.PlayerDataUpdated.Fire(player, player, {
            is_alive = player_data.is_alive,
            is_spectating = player_data.is_spectating,
            lives = lives
        })
        -- Optionally notify the player/UI that they lost a life
        return
    elseif lives <= 0 then
		player_data.is_alive = false
		player_data.is_spectating = true
		
		server.PlayerEliminated.FireAll(player, "died")
		
		server.PlayerDataUpdated.Fire(player, player, {
			is_alive = player_data.is_alive,
			is_spectating = player_data.is_spectating
		})
		
		self:award_coins(player, 10)
		-- Lerp TV up for this player using tv_id
		local tv_id = player_data.tv_id
		if tv_id then
			-- Play MonitorsBeingLifted sound for all players at default speed (0.45)
			server.UpdateUI.FireAll("Game", "PlaySFX", { name = "MonitorsBeingLifted" })
			local soundDuration = 2.926 / 0.65
			for _, tv in ipairs(CollectionService:GetTagged("TV")) do
				local tvId = tv:GetAttribute("id")
				if tostring(tvId) == tostring(tv_id) then
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
			end
			-- Chain logic: find both Chain-tagged parts with matching id
			local matchingChains = {}
			for _, chain in ipairs(CollectionService:GetTagged("Chain")) do
				local chainId = chain:GetAttribute("id")
				if tostring(chainId) == tostring(tv_id) then
					table.insert(matchingChains, chain)
				end
			end
			if #matchingChains == 2 then
				local TweenService = game:GetService("TweenService")
				local function tweenToClosed(chainNameLow, closedName)
					for _, chain in ipairs(matchingChains) do
						if string.find(chain.Name, chainNameLow) then
							local parent = chain.Parent
							if parent then
								for _, sibling in ipairs(parent:GetChildren()) do
									if sibling:IsA("BasePart") and string.find(sibling.Name, closedName) then
										local tween = TweenService:Create(chain, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = sibling.CFrame})
										tween:Play()
										break
									end
								end
							end
						end
					end
				end
				tweenToClosed("HeadChainR_low", "HeadChainR_closed")
				tweenToClosed("HeadChainL_low", "HeadChainL_closed")
			end
		end
		-- Reset player state instead of LoadCharacter
		reset_player_state(player)
		--self.remove_player(self, player)
		
		server.CoinsAwarded.Fire(player, player, 10, "died")
		
		local alive_players = self:get_alive_players()
		
		if #alive_players <= 1 and self:get_state() == "IN_PROGRESS" then
			self:set_state("ENDING")
			
			print("game is ending")
			
			if #alive_players == 1 then
				local winner = alive_players[1]
				self:award_coins(winner.player, 50)
				
				server.CoinsAwarded.Fire(player, player, 50, "won")
				
			end
		elseif #alive_players == 0 and self:get_state() == "IN_PROGRESS" then
			self:set_state("ENDING")
			print("game is ending: no players left alive")
		end
	end
end

function match_object.award_coins(self: MatchObject, player: Player, amount: number): ()
	local player_data = self.players[player]
	if not player_data then
		warn("Cannot award coins - player not in match: " .. (player.Name or "Unknown"))
		return
	end
	
	data.addCoins(player, amount)
end

function match_object:set_state(new_state: MatchState)
    local old_state = self.state
    self.state = new_state
    print("Match state changed: " .. old_state .. " -> " .. new_state)
    if self.state_changed then
        self.state_changed:Fire(new_state)
    end
    server.GameStateChanged.FireAll(self.state, self:get_player_count())
    if new_state == "FINISHED" or new_state == "ENDING" then
        -- Show notification for winner(s) using get_alive_players
        local alive_players = self:get_alive_players()
        if #alive_players > 0 then
            local winner_names = {}
            for _, pdata in ipairs(alive_players) do
                if pdata.player and pdata.player.Name then
                    table.insert(winner_names, pdata.player.Name)
                end
            end
            if #winner_names > 0 then
                Notification.ShowAll(table.concat(winner_names, ", ") .. " has won the round!")
                task.wait(5)
                Notification.CloseAll()
            end
        end
        -- Clean up ALL players (reset state, unanchor, restore walkspeed, etc.)
        for player, _ in pairs(self.players) do
            reset_player_state(player)
            server.HideUI.Fire(player, "Game")
        end
        self:reset()
        return
    end
    -- No TV lowering or minigame start here
end

function match_object.get_state(self: MatchObject): MatchState
	return self.state
end

function match_object.is_player_alive(self: MatchObject, player: Player): boolean
	local player_data = self.players[player]
	return player_data ~= nil and player_data.is_alive
end

function match_object.get_player_data(self: MatchObject, player: Player): PlayerData?
	return self.players[player]
end

function match_object:start_winner_choosing_phase()
    print("[DEBUG] start_winner_choosing_phase called")
    local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
    local Players = game:GetService("Players")
    local Notification = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Notification"))
    local alive_players = self:get_alive_players()
    if #alive_players == 0 then
        warn("[match_object] No alive players for winner choosing phase!")
        return
    end
    local winner = self.last_minigame_winner or (alive_players[1] and alive_players[1].player)
    if not winner then
        warn("[match_object] No winner found for winner choosing phase!")
        return
    end
    print("[DEBUG] Winner for choosing phase:", winner.Name)
    -- Prepare list of other players
    local others = {}
    for _, pdata in ipairs(alive_players) do
        if pdata.player ~= winner then
            table.insert(others, { UserId = pdata.player.UserId, Name = pdata.player.Name })
            -- Fire ShowUI for all non-winner players to trigger cleanup
            local tv_id = self.players[pdata.player] and self.players[pdata.player].tv_id or 1
            server.ShowUI.Fire(pdata.player, "Game", tv_id)
        end
    end
    -- Show UI to winner and notification to all
    Notification.ShowAll(winner.Name .. " won the minigame, choosing player")
    server.UpdateUI.Fire(winner, "Game", "StartWinnerChoosing", { players = others })
    -- Start a timer for choosing
    local choosing_active = true
    local chosenUserId = nil
    local timerThread = task.spawn(function()
        for t = 20, 1, -1 do
            Notification.ShowAll(winner.Name .. " is choosing player: " .. t)
            if not choosing_active then break end
            task.wait(1)
        end
        Notification.CloseAll()
        if choosing_active then
            print("[DEBUG] Winner did not choose in time, picking random target")
            choosing_active = false
            if #others > 0 then
                local randomTarget = others[math.random(1, #others)]
                chosenUserId = randomTarget.UserId
            else
                chosenUserId = 0
            end
            self:_handle_winner_choice(chosenUserId, alive_players, winner)
        end
    end)
    -- Listen for winner's choice from client
    local disconnectWinnerChose = server.WinnerChosePlayer.SetCallback(function(player, userId)
        if not choosing_active then return end
        if player ~= winner then return end
        print("[DEBUG] Winner chose player:", userId)
        choosing_active = false
        chosenUserId = userId
        Notification.CloseAll()
        self:_handle_winner_choice(chosenUserId, alive_players, winner)
    end)
end

-- Helper to lower all TVs
local function lower_tvs()
    print("[DEBUG] Lowering TVs before next minigame...")
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
        local targetY = tv:IsA("BasePart") and 9.69 or 20.36
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
    server.UpdateUI.FireAll("Game", "PlaySFX", { name = "MonitorsBeingLifted" })
end

function match_object:_handle_winner_choice(chosenUserId, alive_players, winner)
    print("[DEBUG] _handle_winner_choice called with:", chosenUserId)
    -- Eliminate the chosen player
    if chosenUserId and chosenUserId ~= 0 then
        local chosenPlayer = nil
        for _, pdata in ipairs(alive_players) do
            if pdata.player.UserId == chosenUserId then
                chosenPlayer = pdata.player
                break
            end
        end
        if chosenPlayer then
            print("[DEBUG] Eliminating chosen player:", chosenPlayer.Name)
            self:eliminate_player(chosenPlayer)
        end
    else
        print("[DEBUG] No valid player to eliminate, skipping elimination")
    end
    -- Advance the match
    local remaining = self:get_alive_players()
    if #remaining > 1 then
        print("[DEBUG] More than one player remains, starting next minigame")
        lower_tvs()
        if self.minigames_handler and self.minigames_handler.switch_to_next then
            self.minigames_handler:switch_to_next(self, self.minigame_signal)
        end
    else
        print("[DEBUG] Only one player remains, ending match")
        -- Teleport the winner back to the lobby and trigger UI cleanup
        if #remaining == 1 then
            local winner = remaining[1].player
            server.ShowUI.Fire(winner, "Lobby")
        end
        self:set_state("ENDING")
    end
end

return match_object