--!strict
local Players = game:GetService("Players")
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local match_object = require(script:WaitForChild("match_object"))
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))

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

-- Listen for minigame end events (outside of new, so singleton is accessible)
minigame_signal:Connect(function()
	local service = singleton
	if not service or not service.match then
		warn("No match object found for minigame end event!")
		return
	end
	local match = service.match
	-- Prevent continuing if match is finished or ending
	if match.state == "FINISHED" or match.state == "ENDING" then
		print("[MatchService] Not switching minigame: match is finished or ending.")
		return
	end
	local alive_players = match:get_alive_players()
	-- TESTING: Always go to next minigame, do not end when only one player left
	-- if #alive_players <= 1 then
	-- 	match:set_state("ENDING")
	-- 	print("Match ending: only one player left alive.")
	-- else
	if match.minigames_handler and match.minigames_handler.switch_to_next then
		match.minigames_handler:switch_to_next(match)
	else
		warn("No minigames handler or switch_to_next function!")
	end
	-- end
end)

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
			title = "Game Starting"
		})
	else
		-- 2+ players but not max, use longer timer
		self.timer_duration = 5
		print(`{player_count} players joined. Game will start in {self.timer_duration} seconds if no one else joins...`)
		
		server.RoundStarting.FireAll({
			description = `Game starting in {self.timer_duration} seconds`,
			duration = self.timer_duration,
			title = "Game Starting"
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