local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Fusion"))
local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))
local ui = {}
ui.__index = ui

export type UIController = {
	scope: Fusion.Scope,
	game_ui: Instance,
	timer_thread: thread?
}

local current_controller: UIController? = nil

local close_frames = {
	["GameStart"] = true,
	["Lives"] = true,
	["MazeGame"] = true,
	["RatRaceGuide"] = true,
	["Tutorial"] = true,
	["WinLossScreen"] = true
}

function ui.close_all(): boolean
	if current_controller then
		for _, v in current_controller.game_ui.Background:GetChildren() do
			if close_frames[v.Name] and v:IsA("Frame") then
				v.Visible = false
			end
		end
		return true
	end
	return false
end

function ui.start_timer(self: UIController, timer: number): boolean
	if not self then
		return false
	end
	
	if not self.game_ui then
		return false
	end
	
	if self.timer_thread then
		task.cancel(self.timer_thread)
	end
	
	self.game_ui.Background.Timer:WaitForChild("TimerNumber").Text = `{timer}`
	
	self.timer_thread = task.spawn(function()
		for i = timer, 0, -1 do
			self.game_ui.Background.Timer.TimerNumber.Text = `{i}`

			if i > 0 then
				task.wait(1)
			end
		end

		self.timer_thread = nil
	end)

	return true
end

function ui.new(): UIController
	if current_controller then
		return current_controller
	end
	
	local self = setmetatable({}, ui)
	
	self.scope = Fusion:scoped()
	
	client.RoundStarting.On(function(data)
		print(`round starting in {data.duration}`)
		self.start_timer(self, data.duration)
	end)
	
	client.GameStateChanged.On(function(state, player_count)
		print(`game state changed to {state}`)
	end)
	
	self.game_ui = self.scope:Hydrate(ReplicatedStorage.UI.CRTSurfaceGui:Clone()) {
		Parent = Players.LocalPlayer.PlayerGui
	}

	self.close_all()
	
	client.MinigameStarted.On(function(data)
		if not self.Game then
			warn("Game ui controller has not been initialized yet")
			return
		end
		
		self.Game.start_game(self.Game, data.type)
	end)
	
	client.ShowUI.On(function(ui_type, iteration)
		self.game_ui.Adornee = workspace.Screens:FindFirstChild(`Screen{iteration}`)
		self.close_all()
		
		self[ui_type] = require(script:FindFirstChild(ui_type)).new(self.scope, self.game_ui)
	end)
	
	client.HideUI.On(function(ui_type)
		self.close_all()
		
		if ui_type ~= "Game" then
			self[ui_type].close()
		end
	end)
		
	current_controller = self
	return self :: UIController
end

return ui