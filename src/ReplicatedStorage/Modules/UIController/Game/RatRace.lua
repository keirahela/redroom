local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))
local Players = game:GetService("Players")

-- Helper to convert index to ordinal string
local function ordinal(n)
	local ordinals = {"FIRST", "SECOND", "THIRD", "FOURTH", "FIFTH", "SIXTH"}
	return ordinals[n] or tostring(n)
end

local function formatTime(seconds)
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%02d:%02d", mins, secs)
end

return function(ui)
	ui.Visible = true

	-- Camera settings for minigame
	local player = Players.LocalPlayer
	player.CameraMaxZoomDistance = 2
	player.CameraMinZoomDistance = 2
	if player.Character and player.Character:FindFirstChild("Humanoid") then
		player.Character.Humanoid.CameraOffset = Vector3.new(0, 1, -4)
	end

	local rats = {ui.Rat1, ui.Rat2, ui.Rat3, ui.Rat4, ui.Rat5, ui.Rat6}
	local selectedRat = nil
	local encourageCooldown = false
	local raceStarted = false
	local connections = {}
	local timerThread = nil
	local countdownThread = nil

	ui.Encourage.Active = false
	ui.Encourage.Visible = false
	if ui.Countdown then ui.Countdown.Visible = false end
	if ui.Time then ui.Time.Visible = true; ui.Time.Text = formatTime(60) end

	-- Enable rat selection
	for i, ratBtn in ipairs(rats) do
		ratBtn.Active = true
		ratBtn.ImageTransparency = 0
		table.insert(connections, ratBtn.MouseEnter:Connect(function()
			ratBtn.BackgroundTransparency = 0.7
		end))
		table.insert(connections, ratBtn.MouseLeave:Connect(function()
			ratBtn.BackgroundTransparency = 1
		end))
		table.insert(connections, ratBtn.MouseButton1Click:Connect(function()
			if selectedRat or raceStarted then return end
			selectedRat = i
			ui.YoureRatLabel.Text = "YOUR RAT: " .. ordinal(i)
			for j, btn in ipairs(rats) do
				btn.Active = false
				if j ~= i then
					btn.ImageTransparency = 0.5
				else
					btn.ImageTransparency = 0
				end
			end
			ui.Encourage.Active = true
			ui.Encourage.Visible = true
			ui.Encourage.BackgroundTransparency = 0.2
			client.MinigameInput.Fire("rat_select", {zone = "rat" .. i})
		end))
	end

	-- Encourage button
	ui.Encourage.MouseButton1Click:Connect(function()
		if not selectedRat or encourageCooldown or not raceStarted then return end
		encourageCooldown = true
		ui.Encourage.Text = "Cheering!"
		client.MinigameInput.Fire("encourage_rat", {zone = "encourage" .. selectedRat})
		task.delay(2, function()
			encourageCooldown = false
			ui.Encourage.Text = "Encourage Rat"
		end)
	end)

	-- Cleanup
	local ratUpdateConn -- declare before cleanup so it's in scope
	local function cleanup()
		ui.Visible = false
		for _, conn in ipairs(connections) do
			if conn and typeof(conn) == "RBXScriptConnection" then
				conn:Disconnect()
			end
		end
		if ratUpdateConn and typeof(ratUpdateConn) == "RBXScriptConnection" then
			ratUpdateConn:Disconnect()
		end
		if timerThread then pcall(function() task.cancel(timerThread) end) end
		if countdownThread then pcall(function() task.cancel(countdownThread) end) end
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
		if player.Character and player.Character:FindFirstChild("Humanoid") then
			player.Character.Humanoid.CameraOffset = Vector3.new(0, 0, 0)
		end
	end

	ratUpdateConn = client.UpdateUI.On(function(ui_type, element, value)
		if ui_type == "Game" and element == "RatRacePositions" and type(value) == "table" then
			for i, pos in ipairs(value) do
				if rats[i] then
					rats[i].Position = UDim2.new(pos, 0, rats[i].Position.Y.Scale, rats[i].Position.Y.Offset)
				end
			end
		end
		if ui_type == "Game" and element == "Countdown" then
			if ui.Countdown then
				if value and value ~= "" then
					ui.Countdown.Visible = true
					ui.Countdown.Text = tostring(value)
					raceStarted = false
				else
					ui.Countdown.Visible = false
					raceStarted = true
				end
			end
		end
		if ui_type == "Game" and element == "RatRaceTime" and ui.Time then
			ui.Time.Text = formatTime(value)
		end
		if ui_type == "Game" and element == "RatRaceResult" and value and (value.result == "timeout" or value.result == "eliminated") then
			cleanup()
		end
	end)

	return cleanup
end 