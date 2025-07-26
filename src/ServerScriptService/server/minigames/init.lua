-- Minigames Module: Handles minigame rotation and management
local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local Blackjack = require(script:WaitForChild("Blackjack"))
local HigherLower = require(script:WaitForChild("HigherLower"))
local Maze = require(script:WaitForChild("Maze"))
local RatRace = require(script:WaitForChild("RatRace"))
local React = require(script:WaitForChild("React"))
local BombGuesser = require(script:WaitForChild("BombGuesser"))
local DragTheLine = require(script:WaitForChild("DragTheLine"))

local MinigamesHandler = {}
MinigamesHandler.__index = MinigamesHandler

local games = {
    DragTheLine,
    Blackjack,
    React,
    HigherLower,
    BombGuesser,
    RatRace,
    Maze,
}

local game_names = {
    "DragTheLine",
    "Blackjack",
    "React",
    "HigherLower",
    "BombGuesser",
    "RatRace",
    "Maze",
}

function MinigamesHandler.new()
    local self = setmetatable({}, MinigamesHandler)
    self.current_game_index = 1
    self.game = nil
    return self
end

function MinigamesHandler:start_game(match, minigame_signal)
    print("[DEBUG] [MinigamesHandler] start_game called. Current game index:", self.current_game_index, "match:", tostring(match), "minigame_signal:", tostring(minigame_signal))
    if match:get_state() ~= "IN_PROGRESS" then
        warn("[minigames.init] Not starting minigame: match state is " .. tostring(match:get_state()))
        return
    end
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
    print("[DEBUG] [MinigamesHandler] Fired MinigameStarted event for:", game_names[self.current_game_index])
    print("[SERVER] [minigames.init] Calling .start on minigame:", game_names[self.current_game_index], "with minigame_signal:", tostring(minigame_signal))
    if match.stop_minigame then match:stop_minigame() end
    local minigameModule = games[self.current_game_index]
    if not minigameModule or type(minigameModule.start) ~= "function" then
        warn("[SERVER] [minigames.init] Minigame module for " .. tostring(game_names[self.current_game_index]) .. " does not have a .start method!")
        return
    end
    self.game = minigameModule
    print("[DEBUG] [MinigamesHandler] Passing minigame_signal to minigame.start:", tostring(minigame_signal))
    minigameModule.start(match, minigame_signal)
    if match then match.minigame = self.game end
end

function MinigamesHandler:switch_to_next(match, minigame_signal)
    print("[DEBUG] [MinigamesHandler] switch_to_next called. Current game index:", self.current_game_index)
    if match.stop_minigame then print("[SERVER] [minigames.init] Stopping current minigame:", game_names[self.current_game_index]) match:stop_minigame() end
    local next_index
    repeat
        next_index = math.random(1, #games)
    until next_index ~= self.current_game_index or #games == 1
    self.current_game_index = next_index
    print("[SERVER] [minigames.init] Switching to next minigame:", game_names[self.current_game_index])
    if match then match.last_minigame_winner = nil end -- Reset winner between minigames
    self:start_game(match, minigame_signal)
end

return MinigamesHandler
