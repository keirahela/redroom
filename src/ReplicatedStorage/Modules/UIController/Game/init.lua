local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Fusion"))

local module = {}
module.__index = module

type MinigameType = "Maze" | "HigherLower" | "Blackjack" | "BombGuesser" | "RatRace" | "React"

local singleton = nil

function module.new(scope: Fusion.Scope, main_ui: Instance)
	if singleton then
		return singleton
	end
	
	local self = setmetatable({}, module)
	
	self.scope = scope
	self.games = {}
	self.main_ui = main_ui
	self._cleanup = {}
	
	local background = main_ui:FindFirstChild("Background")
	assert(background and background:IsA("ImageLabel"), "main_ui.Background must exist and be a ImageLabel")
	local gamesFolder = background:FindFirstChild("Games")
	assert(gamesFolder and gamesFolder:IsA("Frame"), "main_ui.Background.Games must exist and be a Frame")
	for _,v in next, gamesFolder:GetChildren() do
		if v:IsA("Frame") then
			self.games[v.Name] = scope:Hydrate(v) {}
		end
	end
	
	singleton = self
	return self
end

function module.start_game(self, current_game: MinigameType)
	module.stop_games(self)
	if not self.games[current_game] then
		warn("tried to play a game that doesn't exist: ", current_game)
		return
	end
	self.games[current_game].Visible = true
	-- Require and run the minigame module dynamically
	local minigameModule = script:FindFirstChild(current_game)
	if minigameModule then
		local cleanup = require(minigameModule)(self.games[current_game])
		self._cleanup[current_game] = cleanup
	end
end

function module.stop_games(self)
	for name, current_game in next, self.games do
		if self._cleanup and self._cleanup[name] then
			self._cleanup[name]()
			self._cleanup[name] = nil
		end
		if current_game then
			current_game.Visible = false
		end
	end
end

return module