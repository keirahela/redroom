local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))
local GAME_DATA = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Data"):WaitForChild("GAME_DATA"))

local connections = {}
local mouseInStart = false
local currentDifficulty = 1
local gameTimer = nil
local gameActive = false
local maxDifficulty = 3

local setupDangerZone

local function formatTime(seconds)
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%02d:%02d", mins, secs)
end

local function generateMaze(ui, setupDangerZone)
	-- Clear existing danger zones
	for _, child in pairs(ui:GetChildren()) do
		if child.Name == "Danger" then
			child:Destroy()
		end
	end

	-- Use current difficulty level (1, 2, or 3) instead of random
	local difficulty = GAME_DATA.maze_difficulties[currentDifficulty]

	-- Create danger zones based on difficulty
	for i, dangerConfig in ipairs(difficulty.dangers) do
		local danger = Instance.new("Frame")
		danger.Name = "Danger"
		danger.Parent = ui
		danger.Active = true
		danger.BackgroundColor3 = Color3.fromRGB(255, 0, 4)
		danger.BorderSizePixel = 0
		danger.Position = dangerConfig.position
		danger.Size = dangerConfig.size
		-- Setup mouse events for this danger zone
		setupDangerZone(danger)
	end

	-- Set timer UI to full time (10 seconds)
	if ui.Time then
		ui.Time.Text = formatTime(10)
	end
end

local function stopTimer()
	if gameTimer then
		if typeof(gameTimer) == "RBXScriptConnection" then
			gameTimer:Disconnect()
		else
			pcall(function()
				task.cancel(gameTimer)
			end)
		end
		gameTimer = nil
	end
end

local function startTimer(ui, onTimeout)
	stopTimer()
	local timeLeft = 10
	if ui.Time then
		ui.Time.Text = formatTime(timeLeft)
	end
	gameTimer = RunService.Heartbeat:Connect(function(dt)
		timeLeft = timeLeft - dt
		if ui.Time then
			ui.Time.Text = formatTime(math.max(0, timeLeft))
		end
		if timeLeft <= 0 then
			gameTimer:Disconnect()
			gameTimer = nil
			onTimeout()
		end
	end)
end

local function eliminatePlayer(ui, onElimination)
	gameActive = false
	stopTimer()
	if ui.Time then
		ui.Time.Text = ""
	end

	-- Flash red effect on danger zones
	for _, child in pairs(ui:GetChildren()) do
		if child.Name == "Danger" then
			local flash = TweenService:Create(child, 
				TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 5, true),
				{BackgroundColor3 = Color3.fromRGB(150, 0, 0)}
			)
			flash:Play()
		end
	end

	-- Notify server of elimination
	client.MinigameInput.Fire("eliminated", nil)

	-- Hide UI after flashing
	task.delay(0.6, function()
		if ui then
			ui.Visible = false
		end
	end)

	-- Do not restart the maze or call onElimination
end

local function playerWin(ui, onWin, setupDangerZone)
	gameActive = false
	stopTimer()
	if ui.Time then
		ui.Time.Text = ""
	end

	-- Victory effect on end zone
	local endZone = ui:FindFirstChild("End")
	if endZone then
		local victory = TweenService:Create(endZone, 
			TweenInfo.new(0.2, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
			{BackgroundColor3 = Color3.fromRGB(100, 255, 100)}
		)
		victory:Play()
	end

	-- Check if this was the final difficulty
	if currentDifficulty >= maxDifficulty then
		print("completed all levels")
		client.MinigameInput.Fire("ended", nil)
		-- Hide UI after win
		task.delay(0.6, function()
			if ui then
				ui.Visible = false
			end
		end)
		-- Do not restart the maze or call onWin again
		return
	end

	-- Advance to next difficulty
	currentDifficulty = currentDifficulty + 1
	task.wait(1) -- Brief pause before next level

	if onWin then
		onWin(false) -- false indicates continue to next level
	end

	-- Generate next difficulty maze
	generateMaze(ui, setupDangerZone)
	mouseInStart = false -- Reset start flag for new maze
	gameActive = true
	startTimer(ui, function()
		eliminatePlayer(ui, onElimination)
	end)
end

local function setupGUIEvents(ui, onElimination, onWin)
	-- Setup start zone
	local startZone = ui:FindFirstChild("Start")
	if startZone then
		startZone.BackgroundColor3 = Color3.fromRGB(0, 0, 255)
		startZone.Active = true
		table.insert(connections, startZone.MouseEnter:Connect(function()
			if not mouseInStart and gameActive then
				mouseInStart = true
				-- Timer now starts immediately, not here
			end
		end))
	end

	-- Setup end zone
	local endZone = ui:FindFirstChild("End")
	if endZone then
		-- Ensure end zone is green and active
		endZone.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
		endZone.Active = true

		table.insert(connections, endZone.MouseEnter:Connect(function()
			if mouseInStart and gameActive then
				playerWin(ui, onWin, setupDangerZone)
			end
		end))

		-- Add additional detection for better reliability
		table.insert(connections, endZone.MouseMoved:Connect(function()
			if mouseInStart and gameActive then
				playerWin(ui, onWin, setupDangerZone)
			end
		end))
		
		table.insert(connections, endZone.MouseLeave:Connect(function()
			if mouseInStart and gameActive then
				playerWin(ui, onWin, setupDangerZone)
			end
		end))
	end

	-- Setup danger zones (will be called after maze generation)
	function setupDangerZone(dangerFrame)
		table.insert(connections, dangerFrame.MouseEnter:Connect(function()
			if mouseInStart and gameActive then
				eliminatePlayer(ui, onElimination)
			end
		end))
	end
	
	return setupDangerZone
end

local function makePlayerInvisible()
	local player = Players.LocalPlayer
	if player.Character then
		for _, part in pairs(player.Character:GetChildren()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				part.Transparency = 1

				-- Hide decals (like face)
				for _, decal in pairs(part:GetChildren()) do
					if decal:IsA("Decal") then
						decal.Transparency = 1
					end
				end
			elseif part:IsA("Accessory") then
				for _, accessoryPart in pairs(part:GetChildren()) do
					if accessoryPart:IsA("BasePart") then
						accessoryPart.Transparency = 1

						-- Hide decals on accessories
						for _, decal in pairs(accessoryPart:GetChildren()) do
							if decal:IsA("Decal") then
								decal.Transparency = 1
							end
						end
					end
				end
			end
		end
	end
end

local function makePlayerVisible()
	local player = Players.LocalPlayer
	if player.Character then
		for _, part in pairs(player.Character:GetChildren()) do
			if part:IsA("BasePart") then
				part.Transparency = 0

				-- Show decals (like face)
				for _, decal in pairs(part:GetChildren()) do
					if decal:IsA("Decal") then
						decal.Transparency = 0
					end
				end
			elseif part:IsA("Accessory") then
				for _, accessoryPart in pairs(part:GetChildren()) do
					if accessoryPart:IsA("BasePart") then
						accessoryPart.Transparency = 0

						-- Show decals on accessories
						for _, decal in pairs(accessoryPart:GetChildren()) do
							if decal:IsA("Decal") then
								decal.Transparency = 0
							end
						end
					end
				end
			end
		end
	end
end

return function(ui)
	-- Reset game state
	mouseInStart = false
	gameActive = true
	currentDifficulty = 1
	stopTimer()
	
	makePlayerInvisible()
	Players.LocalPlayer.CameraMinZoomDistance = 2
	Players.LocalPlayer.CameraMaxZoomDistance = 2
	
	Players.LocalPlayer.Character.Humanoid.CameraOffset = Vector3.new(0, 0, -4)
	
	local mouse = game.Players.LocalPlayer:GetMouse()

	-- Callback functions
	function onElimination()
		-- Do nothing; wait for server to start a new minigame
	end

	local function onWin(fullCompletion)
		if fullCompletion then
			-- Player completed all difficulties
			Players.LocalPlayer.Character.Humanoid.CameraOffset = Vector3.new(0, 0, 0)
			Players.LocalPlayer.CameraMinZoomDistance = 0.5
			Players.LocalPlayer.CameraMaxZoomDistance = 0.5

			makePlayerVisible()
			-- Do nothing else; wait for server to start a new minigame
		else
			-- Continue to next difficulty (already handled in playerWin)
			gameActive = true
		end
	end

	-- Generate initial maze and setup events
	setupDangerZone = setupGUIEvents(ui, onElimination, onWin)
	-- Generate maze with event setup
	generateMaze(ui, setupDangerZone)
	startTimer(ui, function()
		eliminatePlayer(ui, onElimination)
	end)

	return function()
		gameActive = false
		mouseInStart = false
		stopTimer()

		-- Clean up connections
		for _, connection in pairs(connections) do
			if connection then
				connection:Disconnect()
			end
		end
		connections = {}

		-- Hide GUI
		if ui then
			ui.Visible = false
		end

		print("Maze game stopped!")
	end
end