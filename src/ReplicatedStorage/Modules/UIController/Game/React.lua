local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))
local Players = game:GetService("Players")

local function formatTime(seconds)
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%02d:%02d", mins, secs)
end

return function(ui)
	ui.Visible = true

	local player = Players.LocalPlayer
	player.CameraMaxZoomDistance = 2
	player.CameraMinZoomDistance = 2
	if player.Character and player.Character:FindFirstChild("Humanoid") then
		player.Character.Humanoid.CameraOffset = Vector3.new(0, 1, -4)
	end

	local connections = {}
	local timerThread = nil
	local countdownThread = nil
	local reactPhase = false
	local finished = false

	if ui.Countdown then ui.Countdown.Visible = false end
	if ui.Time then ui.Time.Visible = true; ui.Time.Text = formatTime(60) end
	if ui.TextButton then ui.TextButton.Visible = false end

	local function cleanup()
		ui.Visible = false
		for _, conn in ipairs(connections) do
			if conn and typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
		end
		if timerThread then pcall(function() task.cancel(timerThread) end) end
		if countdownThread then pcall(function() task.cancel(countdownThread) end) end
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
		if player.Character and player.Character:FindFirstChild("Humanoid") then
			player.Character.Humanoid.CameraOffset = Vector3.new(0, 0, 0)
		end
	end

	local function showResultAndCleanup(result)
		if ui.TextInfo then
			if result == "success" then
				ui.TextInfo.Text = "You won!"
			else
				ui.TextInfo.Text = "You lost!"
			end
		end
		task.wait(2.5)
		cleanup()
	end

	-- Listen for server events
	local reactConn
	reactConn = client.UpdateUI.On(function(ui_type, element, value)
		if ui_type == "Game" and element == "ReactCountdown" then
			if ui.Countdown then
				if value and value ~= "" then
					ui.Countdown.Visible = true
					ui.Countdown.Text = tostring(value)
				else
					ui.Countdown.Visible = false
				end
			end
		end
		if ui_type == "Game" and element == "ReactTime" and ui.Time then
			ui.Time.Text = formatTime(value)
		end
		if ui_type == "Game" and element == "ReactPhase" and ui.TextButton then
			if value == "wait" then
				ui.TextButton.Visible = true
				ui.TextButton.Text = "Wait..."
				reactPhase = false
			elseif value == "click" then
				ui.TextButton.Visible = true
				ui.TextButton.Text = "CLICK!"
				reactPhase = true
			elseif value == "done" then
				ui.TextButton.Visible = false
			end
		end
		if ui_type == "Game" and element == "ReactResult" and value then
			showResultAndCleanup(value.result)
		end
	end)

table.insert(connections, reactConn)

	table.insert(connections, ui.TextButton.MouseButton1Click:Connect(function()
		if finished then return end
		if not reactPhase then
			client.MinigameInput.Fire("react_fail", {zone = "fail_early"})
			finished = true
			return
		end
		client.MinigameInput.Fire("react_click", {zone = "clicked"})
		finished = true
	end))

	return cleanup
end 