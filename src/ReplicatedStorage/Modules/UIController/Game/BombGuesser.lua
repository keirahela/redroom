local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))
local Players = game:GetService("Players")

return function(ui)
	print("[BombGuesser] UI shown")
	ui.Visible = true
	if ui["Pick One"] then
		ui["Pick One"].Text = "Pick The Dud :]"
	end

	local bombsFolder = ui:FindFirstChild("Bombs")
	assert(bombsFolder, "Bombs folder missing in UI")
	local bombButtons = {
		bombsFolder:FindFirstChild("1"),
		bombsFolder:FindFirstChild("2"),
		bombsFolder:FindFirstChild("3"),
	}
	local arrowLabels = {
		bombButtons[1] and bombButtons[1]:FindFirstChild("Arrows"),
		bombButtons[2] and bombButtons[2]:FindFirstChild("Arrows"),
		bombButtons[3] and bombButtons[3]:FindFirstChild("Arrows"),
	}

	local connections = {}
	local picked = false

	local hoveredIndex = nil

	local function setArrows(index)
		hoveredIndex = index
		for i, arrow in ipairs(arrowLabels) do
			if arrow then
				arrow.Visible = (i == index)
			end
			if bombButtons[i] then
				bombButtons[i].BackgroundTransparency = (i == index) and 0.7 or 1
			end
		end
	end

	local function setButtonsEnabled(enabled)
		for _, btn in ipairs(bombButtons) do
			if btn then
				btn.Active = enabled
			end
		end
	end

	local function cleanup()
		ui.Visible = false
		for _, conn in ipairs(connections) do
			if conn and typeof(conn) == "RBXScriptConnection" then
				conn:Disconnect()
			end
		end
		setButtonsEnabled(false)
		for _, arrow in ipairs(arrowLabels) do
			if arrow then
				arrow.Visible = false
			end
		end
	end

	-- Hover logic
	for i, btn in ipairs(bombButtons) do
		if btn then
			local enter = btn.MouseEnter:Connect(function()
				if not picked then
					setArrows(i)
				end
			end)
			local leave = btn.MouseLeave:Connect(function()
				task.defer(function()
					if not picked and hoveredIndex == i then
						setArrows(nil)
					end
				end)
			end)
			table.insert(connections, enter)
			table.insert(connections, leave)
		end
	end

	-- Click logic
	for i, btn in ipairs(bombButtons) do
		if btn then
			local click = btn.MouseButton1Click:Connect(function()
				if picked then
					return
				end
				picked = true
				setButtonsEnabled(false)
				setArrows(i)
				print("[BombGuesser][CLIENT] About to fire bomb_pick", i, "zone:", "bomb" .. tostring(i))
				client.MinigameInput.Fire("bomb_pick", { zone = "bomb" .. tostring(i) })
				print("[BombGuesser][CLIENT] Fired bomb_pick")
			end)
			table.insert(connections, click)
		end
	end

	-- Listen for server events
	local resultConn, startConn
	startConn = client.UpdateUI.On(function(ui_type, element, value)
		if ui_type == "Game" and element == "BombGuesserStart" then
			picked = false
			setButtonsEnabled(true)
			setArrows(nil)
			if ui["Pick One"] then
				ui["Pick One"].Text = "Pick The Dud :]"
			end
		end
	end)
	resultConn = client.UpdateUI.On(function(ui_type, element, value)
		if ui_type == "Game" and element == "BombGuesserResult" then
			setButtonsEnabled(false)
			if value and value.result == "advance" then
				if ui["Pick One"] then
					ui["Pick One"].Text = "You survived!"
				end
			elseif value and value.result == "eliminate" then
				if ui["Pick One"] then
					ui["Pick One"].Text = "You exploded!"
				end
			end
			-- Reveal dud visually
			for i, btn in ipairs(bombButtons) do
				if btn then
					if value and value.dud == i then
						btn.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
					else
						btn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
					end
				end
			end
		end
	end)
	table.insert(connections, resultConn)
	table.insert(connections, startConn)

	local timeConn

	timeConn = client.UpdateUI.On(function(ui_type, element, value)
		if ui_type == "Game" and element == "BombGuesserTime" and value and value.time then
			print("[BombGuesser][CLIENT] Received BombGuesserTime", value.time, ui.Time)
			if ui.Time then
				ui.Time.Text = tostring(value.time)
			end
		end
	end)
	table.insert(connections, timeConn)

	return cleanup
end
