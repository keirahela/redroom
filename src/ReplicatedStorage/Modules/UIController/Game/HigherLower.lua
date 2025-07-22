local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))
local Players = game:GetService("Players")

return function(ui)
	-- ui is the HigherLower Frame
	ui.Visible = true
	if ui.Number then
		ui.Number.Text = "10" -- Always show 10 at the start of each round
	end
	if ui.TextLabel then
		ui.TextLabel.Text = "HIGHER OR LOWER?"
	end

	-- Camera settings for minigame
	local player = Players.LocalPlayer
	player.CameraMaxZoomDistance = 2
	player.CameraMinZoomDistance = 2
	if player.Character and player.Character:FindFirstChild("Humanoid") then
		player.Character.Humanoid.CameraOffset = Vector3.new(0, 1, -4)
	end

	-- Enable buttons
	if ui.Higher then ui.Higher.Visible = true ui.Higher.Active = true end
	if ui.Lower then ui.Lower.Visible = true ui.Lower.Active = true end

	local function onGuess(guess)
		if guess == "Higher" then
			client.MinigameInput.Fire("guess_higher")
		elseif guess == "Lower" then
			client.MinigameInput.Fire("guess_lower")
		end
		if ui.Higher then ui.Higher.Active = false end
		if ui.Lower then ui.Lower.Active = false end
	end

	local higherConn, lowerConn, resultConn
	higherConn = ui.Higher.MouseButton1Click:Connect(function()
		onGuess("Higher")
	end)
	lowerConn = ui.Lower.MouseButton1Click:Connect(function()
		onGuess("Lower")
	end)

	local timerConn = nil
	local timeLeft = 60
	if ui.Time then
		ui.Time.Text = string.format("%02d:%02d", math.floor(timeLeft/60), timeLeft%60)
	end
	local function updateTimer()
		timeLeft = timeLeft - 1
		if ui.Time then
			ui.Time.Text = string.format("%02d:%02d", math.floor(timeLeft/60), timeLeft%60)
		end
		if timeLeft <= 0 then
			if timerConn then timerConn:Disconnect() end
			client.MinigameInput.Fire("guess_timeout")
		end
	end
	timerConn = game:GetService("RunService").RenderStepped:Connect(function(dt)
		-- do nothing, just to keep the connection for cleanup
	end)
	task.spawn(function()
		while timeLeft > 0 do
			task.wait(1)
			timeLeft = timeLeft - 1
			if ui.Time then
				ui.Time.Text = string.format("%02d:%02d", math.floor(timeLeft/60), timeLeft%60)
			end
		end
		if timeLeft <= 0 then
			if typeof(timerConn) == "RBXScriptConnection" then timerConn:Disconnect() end
			client.MinigameInput.Fire("guess_timeout")
		end
	end)

	local function cleanup()
		ui.Visible = false
		if ui.Higher then ui.Higher.Active = false end
		if ui.Lower then ui.Lower.Active = false end
		if typeof(higherConn) == "RBXScriptConnection" then higherConn:Disconnect() end
		if typeof(lowerConn) == "RBXScriptConnection" then lowerConn:Disconnect() end
		if typeof(resultConn) == "RBXScriptConnection" then resultConn:Disconnect() end
		if typeof(timerConn) == "RBXScriptConnection" then timerConn:Disconnect() end
		if ui.Time then ui.Time.Text = "" end
		-- Restore camera settings
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
		if player.Character and player.Character:FindFirstChild("Humanoid") then
			player.Character.Humanoid.CameraOffset = Vector3.new(0, 0, 0)
		end
	end

	resultConn = client.UpdateUI.On(function(ui_type, element, value)
		if ui_type == "Game" and element == "HigherLowerResult" then
			if value and value.result == "advance" then
				if ui.Number then ui.Number.Text = "10" end
				if ui.Higher then ui.Higher.Active = true end
				if ui.Lower then ui.Lower.Active = true end
			elseif value and value.result == "eliminate" then
				cleanup()
			end
		end
	end)

	return cleanup
end 