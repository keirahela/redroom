--!strict
local DISABLE_DYING_FOR_TESTING = true -- Set to true to disable dying for testing all minigames
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local data = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("data"))
local minigames = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigames"))
local match_object = {}
match_object.__index = match_object

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
	minigames_handler: minigames.MinigameModule,
	last_minigame_winner: Player?,
	
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
}

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local CHARACTER_POSITIONS = workspace.Chairs
local Players = game:GetService("Players")

function match_object.new(): MatchObject
	local self = setmetatable({}, match_object)
	
	self.players = {}
	self.state = "WAITING"
	self.start_time = nil
	self.minigames_handler = minigames.new()
	self.round_number = 0
	self.max_players = 6
	self.min_players = 1
	self.last_minigame_winner = nil
	
	return self :: any
end

function match_object.start(self: MatchObject): ()
	if self.state ~= "WAITING" then
		return
	end
	
	local player_count = self:get_player_count()
	
	if player_count < self.min_players then
		return
	end
	
	self.last_minigame_winner = nil -- Reset winner at the start of each round
	self:set_state("STARTING")
	self.start_time = tick()
	self.round_number = 1
	
	for player, data in pairs(self.players) do
		data.is_alive = true
		data.is_spectating = false

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
		task.spawn(function()
			local character = player.Character
			if not character then
				character = player.CharacterAdded:Wait()
			end

			if not character then
				return
			end

			local targetCFrame: CFrame = CHARACTER_POSITIONS:FindFirstChild(tostring(iteration)).CFrame * CFrame.new(0, 2, 0)
			if not targetCFrame then
				return
			end

			local pos = targetCFrame.Position
			local orientation = targetCFrame - pos
			local tpCFrame = CFrame.new(pos.X, 8.7, pos.Z) * orientation

			server.ShowUI.Fire(player, "Game", iteration)
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
			task.wait()
			if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
				humanoidRootPart.Anchored = true
			end
			-- Store the chair/tv id for this player
			self.players[player].tv_id = iteration
		end)
	end

	-- Fire PlaySeatAnimation event ONCE for all clients, now only passing animationId
	server.PlaySeatAnimation.FireAll("71528301881949")

	-- Fade in (waking up)
	task.wait(1)
	server.WakeUpTransition.FireAll("fadein", 3)

	-- Wait for fade in and 15s before starting minigame
	task.delay(3 + 15, function()
		-- Lower all TVs (tagged 'TV') using Heartbeat loop for both BaseParts and Models
		-- Play MonitorsBeingLifted sound for all players at default speed (0.45)
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

		self:set_state("IN_PROGRESS")
		self.minigames_handler.start_game(self.minigames_handler, self)
	end)
end

function match_object.add_player(self: MatchObject, player: Player): boolean
	if not player or not player.Parent then
		return false
	end
	
	if self.players[player] then
		return false
	end
	
	local player_data: PlayerData = {
		player = player,
		is_alive = self.state == "WAITING",
		is_spectating = self.state ~= "WAITING",
		joined_at = tick()
	}
	
	self.players[player] = player_data
	
	print(`{player.Name} was added`)
	
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

-- Only keep the reset_player_state logic here, do not reference singleton
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
		
		self.award_coins(self, player, 10)
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
				self.award_coins(self, winner.player, 50)
				
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

function match_object.set_state(self: MatchObject, new_state: MatchState): ()
	local old_state = self.state
	self.state = new_state
	print("Match state changed: " .. old_state .. " -> " .. new_state)
	
	server.GameStateChanged.FireAll(self.state, self:get_player_count())
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

return match_object