-- Blackjack Minigame UI Controller
local Maid = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Maid"))
local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))
local Players = game:GetService("Players")
local SoundManager = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundManager"))

return function(ui)
    local maid = Maid.new()
    ui.Visible = true
    if ui.TextLabel then ui.TextLabel.Text = "TEST YOUR LUCK AND GET 21!" end
    -- Camera settings for minigame
    local player = Players.LocalPlayer
    player.CameraMaxZoomDistance = 2
    player.CameraMinZoomDistance = 2
    if player.Character and player.Character:FindFirstChild("Humanoid") then
        player.Character.Humanoid.CameraOffset = Vector3.new(0, 1, -4)
    end
    -- Helper to clear cards
    local function clearCards(scrollingFrame)
        for _, child in ipairs(scrollingFrame:GetChildren()) do
            if child.Name == "Card" then child:Destroy() end
        end
    end
    -- Helper to add a card
    local function addCard(scrollingFrame, template, value)
        local card = template:Clone()
        card.Name = "Card"
        card.Parent = scrollingFrame
        card.Visible = true
        local label = card:FindFirstChildWhichIsA("TextLabel")
        if label then label.Text = tostring(value) end
        SoundManager:PlaySFX("CardFlipping")
    end
    -- Update card visuals for player and AI
    local function updateCards(playerHand, aiHand, showAllAI)
        local playerFrame = ui.CardsetPlayer.CardList.ScrollingFrame
        local playerTemplate = playerFrame.UIListLayout:FindFirstChild("Template")
        clearCards(playerFrame)
        for _, v in ipairs(playerHand) do addCard(playerFrame, playerTemplate, v) end
        local aiFrame = ui.CardsetAI.ScrollingFrame
        local aiTemplate = aiFrame.UIListLayout:FindFirstChild("Template")
        clearCards(aiFrame)
        if showAllAI then
            for _, v in ipairs(aiHand) do addCard(aiFrame, aiTemplate, v) end
        else
            if aiHand[1] then addCard(aiFrame, aiTemplate, aiHand[1]) end
            if #aiHand > 1 then addCard(aiFrame, aiTemplate, "?") end
        end
    end
    local hitButton = ui.CardsetPlayer.ButtonContainer and ui.CardsetPlayer.ButtonContainer:FindFirstChild("HitButton")
    local standButton = ui.CardsetPlayer.ButtonContainer and ui.CardsetPlayer.ButtonContainer:FindFirstChild("StandStand")
    local actionCooldown = false
    local function setButtonsEnabled(enabled)
        if hitButton then hitButton.Active = enabled end
        if standButton then standButton.Active = enabled end
    end
    local function cooldown()
        actionCooldown = true
        setButtonsEnabled(false)
        local thread = task.delay(2, function()
            actionCooldown = false
            setButtonsEnabled(true)
        end)
        maid:GiveTask(function() task.cancel(thread) end)
    end
    local function onHit()
        if actionCooldown then return end
        client.MinigameInput.Fire("blackjack_hit")
        SoundManager:PlaySFX("BeepSound")
        cooldown()
    end
    local function onStand()
        if actionCooldown then return end
        client.MinigameInput.Fire("blackjack_stand")
        SoundManager:PlaySFX("BeepSound")
        cooldown()
    end
    local function resetBlackjack()
        if ui.TextLabel then ui.TextLabel.Text = "TEST YOUR LUCK AND GET 21!" end
        if ui.CardsetPlayer and ui.CardsetPlayer.CardList and ui.CardsetPlayer.CardList.ScrollingFrame then
            clearCards(ui.CardsetPlayer.CardList.ScrollingFrame)
        end
        if ui.CardsetAI and ui.CardsetAI.ScrollingFrame then
            clearCards(ui.CardsetAI.ScrollingFrame)
        end
        if hitButton then hitButton.Active = true end
        if standButton then standButton.Active = true end
    end
    local function cleanup()
        ui.Visible = false
        maid:DoCleaning()
        player.CameraMinZoomDistance = 0.5
        player.CameraMaxZoomDistance = 0.5
        if player.Character and player.Character:FindFirstChild("Humanoid") then
            player.Character.Humanoid.CameraOffset = Vector3.new(0, 0, 0)
        end
        resetBlackjack()
    end
    if hitButton then maid:GiveTask(hitButton.MouseButton1Click:Connect(onHit)) end
    if standButton then maid:GiveTask(standButton.MouseButton1Click:Connect(onStand)) end
    -- Show result message
    local function showResultMessage(result)
        if ui.TextLabel then
            if result == "advance" then
                ui.TextLabel.Text = "You won!"
            elseif result == "eliminate" then
                ui.TextLabel.Text = "You lost!"
            elseif result == "tie" then
                ui.TextLabel.Text = "It's a tie!"
            end
        end
    end
    -- Listen for result and endgame events
    local resultConn
    resultConn = client.UpdateUI.On(function(ui_type, element, value)
        if ui_type == "Game" and element == "BlackjackResult" then
            if value and value.playerHand and value.aiHand then
                local showAllAI = #value.aiHand > 1 or value.result ~= nil
                updateCards(value.playerHand, value.aiHand, showAllAI)
            end
            if value and value.result then
                showResultMessage(value.result)
                setButtonsEnabled(false)
                if value.result == "eliminate" or value.result == "fail" then
                    -- Reset and start a new round for this player
                    task.wait(1)
                    resetBlackjack()
                    -- Optionally, send a message to the server to start a new round for this player
                end
            end
        end
    end)
    maid:GiveTask(resultConn)
    maid:GiveTask(client.UpdateUI.On(function(ui_type, element, value)
        if ui_type == "Game" and element == "EndGame" then
            cleanup()
            if ui then ui.Visible = false end
        end
    end))
    return cleanup
end 