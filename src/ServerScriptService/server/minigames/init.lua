-- Minigames Module: Handles minigame rotation and management
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Blackjack = require(script:WaitForChild("Blackjack"))
local HigherLower = require(script:WaitForChild("HigherLower"))
local Maze = require(script:WaitForChild("Maze"))
local RatRace = require(script:WaitForChild("RatRace"))
local React = require(script:WaitForChild("React"))
local BombGuesser = require(script:WaitForChild("BombGuesser"))
local DragTheLine = require(script:WaitForChild("DragTheLine"))

local module = {}
module.__index = module

type MinigameType = "Maze" | "HigherLower" | "Blackjack" | "BombGuesser" | "RatRace" | "React" | "DragTheLine"

export type MinigameModule = {
    __index: MinigameModule,
    new: () -> MinigameModule,
    start_game: (self: MinigameModule, match: any) -> (),
    switch_to_next: (self: MinigameModule, match: any) -> (),
    current_game_index: number,
    game: any,
}

local games = {
    RatRace,
    DragTheLine,
    Maze,
    HigherLower,
    Blackjack,
    BombGuesser,
    React,
}

local game_names = {
    "RatRace",
    "DragTheLine",
    "Maze",
    "HigherLower",
    "Blackjack",
    "BombGuesser",
    "React",
}

local singleton: MinigameModule? = nil
local last_game_index = nil

-- Create a new minigame module (singleton)
function module.new(): MinigameModule
    if singleton then return singleton end
    local self = setmetatable({} :: any, module) :: MinigameModule
    self.current_game_index = 1
    self.game = games[self.current_game_index]
    singleton = self
    return self :: MinigameModule
end

-- Start the current minigame
function module.start_game(self: MinigameModule, match)
    print("[SERVER] [minigames.init] start_game called for:", game_names[self.current_game_index], "Match state:", match:get_state())
    print("[SERVER] [minigames.init] Players to receive MinigameStarted:")
    for _, pdata in ipairs(match:get_alive_players()) do
        print("[SERVER]   ", pdata.player.Name)
    end
    server.MinigameStarted.FireAll({
        duration = 1,
        instructions = "test",
        parameters = "test",
        type = game_names[self.current_game_index],
    })
    print("[SERVER] [minigames.init] Calling .start on minigame:", game_names[self.current_game_index])
    self.game.start(match)
end

-- Switch to the next minigame (random, not repeating last)
function module.switch_to_next(self: MinigameModule, match)
    print("[SERVER] [minigames.init] switch_to_next called")
    if self.game and self.game.stop then print("[SERVER] [minigames.init] Stopping current minigame:", game_names[self.current_game_index]) self.game.stop() end
    local next_index
    repeat
        next_index = math.random(1, #games)
    until next_index ~= self.current_game_index or #games == 1
    self.current_game_index = next_index
    last_game_index = next_index
    self.game = games[self.current_game_index]
    print("[SERVER] [minigames.init] Switching to next minigame:", game_names[self.current_game_index])
    self.start_game(self, match)
end

return module
