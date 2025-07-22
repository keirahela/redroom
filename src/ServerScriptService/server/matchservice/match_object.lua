--!strict
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
}

export type MatchObject = {
	players: {[Player]: PlayerData},
	state: MatchState,
	start_time: number?,
	round_number: number,
	max_players: number,
	min_players: number,
	minigames_handler: minigames.MinigameModule,
	
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

local CHARACTER_POSITIONS = workspace.Chairs

function match_object.new(): MatchObject
	local self = setmetatable({}, match_object)
	
	self.players = {}
	self.state = "WAITING"
	self.start_time = nil
	self.minigames_handler = minigames.new()
	self.round_number = 0
	self.max_players = 6
	self.min_players = 1
	
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
	
	self:set_state("STARTING")
	self.start_time = tick()
	self.round_number = 1
	
	for player, data in pairs(self.players) do
		data.is_alive = true
		data.is_spectating = false
	end
	
	server.RoundStarting.FireAll({
		description = "Game is starting in 3 seconds",
		duration = 3,
		title = "Match Starting"
	})
	
	local iteration = 1
	for player, data in next, self.players do
		task.spawn(function()
			local character = player.Character
			if not character then
				character = player.CharacterAdded:Wait()
			end

			if not character then
				return
			end

			local targetCFrame = CHARACTER_POSITIONS:FindFirstChild(tostring(iteration)).CFrame * CFrame.new(0, 2, 0)
			if not targetCFrame then
				return
			end

			server.ShowUI.Fire(player, "Game", iteration)
			
			character.Humanoid.WalkSpeed = 0
			character.Humanoid.JumpHeight = 0
			character.Humanoid.AutoRotate = false

			character:PivotTo(targetCFrame)
			task.wait()
			character.HumanoidRootPart.Anchored = true
			iteration += 1
		end)
	end
	
	task.delay(3, function()
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
	
	self.players[player] = nil
	
	print(`{player.Name} was removed`)
	
	if self.state == "IN_PROGRESS" and self:get_player_count() <= 1 then
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

function match_object.eliminate_player(self: MatchObject, player: Player): ()
	local player_data = self.players[player]
	if not player_data then
		return
	end
	
	local data = data.takeLives(player, 1)
	
	local lives = 0
	if data and data.Lives then
		lives = data.Lives
	end
	
	if lives <= 0 then
		player_data.is_alive = false
		player_data.is_spectating = true
		
		server.PlayerEliminated.FireAll(player, "died")
		
		server.PlayerDataUpdated.Fire(player, player, {
			is_alive = player_data.is_alive,
			is_spectating = player_data.is_spectating
		})
		
		self.award_coins(self, player, 10)
		self.remove_player(self, player)
		
		server.CoinsAwarded.Fire(player, player, 10, "died")
		
		local alive_players = self:get_alive_players()
		
		if #alive_players <= 1 and self.state == "IN_PROGRESS" then
			self:set_state("ENDING")
			
			print("game is ending")
			
			if #alive_players == 1 then
				local winner = alive_players[1]
				self.award_coins(self, winner.player, 50)
				
				server.CoinsAwarded.Fire(player, player, 50, "won")
				
				
			end
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