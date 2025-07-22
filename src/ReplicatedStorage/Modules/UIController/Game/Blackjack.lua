local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))
local Players = game:GetService("Players")

return function(ui)
	print("[Blackjack] UI shown")
	ui.Visible = true
	if ui.TextLabel then
		ui.TextLabel.Text = "TEST YOUR LUCK AND GET 21!"
	end

	-- Camera settings for minigame
	local player = Players.LocalPlayer
	player.CameraMinZoomDistance = 2
	player.CameraMaxZoomDistance = 2
	if player.Character and player.Character:FindFirstChild("Humanoid") then
		player.Character.Humanoid.CameraOffset = Vector3.new(0, 0, -4)
	end

	-- Helper to clear cards
	local function clearCards(scrollingFrame)
		for _, child in ipairs(scrollingFrame:GetChildren()) do
			if child.Name == "Card" then
				child:Destroy()
			end
		end
	end

	-- Helper to add a card
	local function addCard(scrollingFrame, template, value)
		local card = template:Clone()
		card.Name = "Card"
		card.Parent = scrollingFrame
		card.Visible = true
		local label = card:FindFirstChildWhichIsA("TextLabel")
		if label then
			label.Text = tostring(value)
		end
	end

	local function updateCards(playerHand, aiHand, showAllAI)
		print("[Blackjack] updateCards", playerHand, aiHand, showAllAI)
		local playerFrame = ui.CardsetPlayer.CardList.ScrollingFrame
		local playerTemplate = playerFrame.UIListLayout:FindFirstChild("Template")
		clearCards(playerFrame)
		for _, v in ipairs(playerHand) do
			addCard(playerFrame, playerTemplate, v)
		end

		local aiFrame = ui.CardsetAI.ScrollingFrame
		local aiTemplate = aiFrame.UIListLayout:FindFirstChild("Template")
		clearCards(aiFrame)
		if showAllAI then
			for _, v in ipairs(aiHand) do
				addCard(aiFrame, aiTemplate, v)
			end
		else
			if aiHand[1] then addCard(aiFrame, aiTemplate, aiHand[1]) end
			if #aiHand > 1 then addCard(aiFrame, aiTemplate, "?") end
		end
	end

	local hitButton = ui.CardsetPlayer.ButtonContainer and ui.CardsetPlayer.ButtonContainer:FindFirstChild("HitButton")
	local standButton = ui.CardsetPlayer.ButtonContainer and ui.CardsetPlayer.ButtonContainer:FindFirstChild("StandStand")
	print("[Blackjack] hitButton:", hitButton, "standButton:", standButton)

	local actionCooldown = false

	local function setButtonsEnabled(enabled)
		if hitButton then hitButton.Active = enabled end
		if standButton then standButton.Active = enabled end
	end

	local function cooldown()
		actionCooldown = true
		setButtonsEnabled(false)
		task.delay(2, function()
			actionCooldown = false
			setButtonsEnabled(true)
		end)
	end

	local function onHit()
		if actionCooldown then return end
		print("[Blackjack] Hit clicked")
		client.MinigameInput.Fire("blackjack_hit")
		cooldown()
	end
	local function onStand()
		if actionCooldown then return end
		print("[Blackjack] Stand clicked")
		client.MinigameInput.Fire("blackjack_stand")
		cooldown()
	end

	if hitButton then
		hitButton.MouseButton1Click:Connect(onHit)
	end
	if standButton then
		standButton.MouseButton1Click:Connect(onStand)
	end

	local resultConn
	resultConn = client.UpdateUI.On(function(ui_type, element, value)
		print("[Blackjack] UpdateUI", ui_type, element, value)
		if ui_type == "Game" and element == "BlackjackResult" then
			if value and value.playerHand and value.aiHand then
				local showAllAI = #value.aiHand > 1 or value.result ~= nil
				updateCards(value.playerHand, value.aiHand, showAllAI)
			end
			if value and value.result == "advance" then
				ui.TextLabel.Text = "You win!"
				setButtonsEnabled(false)
			elseif value and value.result == "eliminate" then
				ui.TextLabel.Text = "You lose!"
				setButtonsEnabled(false)
			elseif value and value.result == "tie" then
				ui.TextLabel.Text = "It's a tie!"
				setButtonsEnabled(false)
			end
		end
	end)

	local function cleanup()
		ui.Visible = false
		if resultConn and typeof(resultConn) == "RBXScriptConnection" then resultConn:Disconnect() end
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
		if player.Character and player.Character:FindFirstChild("Humanoid") then
			player.Character.Humanoid.CameraOffset = Vector3.new(0, 0, 0)
		end
		local playerFrame = ui.CardsetPlayer.CardList.ScrollingFrame
		local aiFrame = ui.CardsetAI.ScrollingFrame
		if playerFrame then clearCards(playerFrame) end
		if aiFrame then clearCards(aiFrame) end
	end

	return cleanup
end 