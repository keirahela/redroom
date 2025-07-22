local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Blackjack = require(script:WaitForChild("Blackjack"))
local HigherLower = require(script:WaitForChild("HigherLower"))
local Maze = require(script:WaitForChild("Maze"))
local RatRace = require(script:WaitForChild("RatRace"))
local React = require(script:WaitForChild("React"))
local BombGuesser = require(script:WaitForChild("BombGuesser"))
local module : MinigameModule = {} :: MinigameModule
module.__index = module

type MinigameType = "Maze" | "HigherLower" | "Blackjack" | "BombGuesser" | "RatRace" | "React"

export type MinigameModule = {
	__index: MinigameModule,
	new: () -> MinigameModule,
	start_game: (self: MinigameModule, match: any) -> (),
	switch_to_next: (self: MinigameModule, match: any) -> (),
	
	current_game_index: number,
	game: any,
}

local games = {
	Maze,
	HigherLower,
	Blackjack,
	BombGuesser,
	RatRace,
	React,
}

local game_names = {
	"Maze",
	"HigherLower", 
	"Blackjack",
	"BombGuesser",
	"RatRace",
	"React",
}

local singleton: MinigameModule? = nil
local last_game_index = nil

function module.new(): MinigameModule
	if singleton then
		return singleton
	end
	local self = setmetatable({} :: any, module) :: MinigameModule
	
	self.current_game_index = 1
	self.game = games[self.current_game_index]
	
	singleton = self
	return self :: MinigameModule
end

function module.start_game(self: MinigameModule, match)
	server.MinigameStarted.FireAll({
		duration = 1,
		instructions = "test",
		parameters = "test",
		type = game_names[self.current_game_index]
	})
	self.game.start(match)
end

function module.switch_to_next(self: MinigameModule, match)
	if self.game and self.game.stop then
		self.game.stop()
	end
	-- Pick a random game index, not the same as last_game_index
	local next_index
	repeat
		next_index = math.random(1, #games)
	until next_index ~= self.current_game_index or #games == 1
	self.current_game_index = next_index
	last_game_index = next_index
	self.game = games[self.current_game_index]
	print("[Minigames] Switching to next minigame:", game_names[self.current_game_index])
	self.start_game(self, match)
end

return module
