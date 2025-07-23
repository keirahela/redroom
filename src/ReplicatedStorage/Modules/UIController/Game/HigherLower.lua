-- HigherLower Minigame UI Controller
local Maid = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Maid"))
local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))
local Players = game:GetService("Players")
local SoundManager = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundManager"))

return function(ui)
    print("[HigherLower] Minigame UI logic started", debug.traceback())
    local maid = Maid.new()
    -- Show and initialize UI
    ui.Visible = true
    if ui.Number then ui.Number.Text = "10" end -- Always show 10 at the start
    if ui.TextLabel then ui.TextLabel.Text = "HIGHER OR LOWER?" end

    -- Camera settings for minigame
    local player = Players.LocalPlayer
    player.CameraMaxZoomDistance = 2
    player.CameraMinZoomDistance = 2
    if player.Character and player.Character:FindFirstChild("Humanoid") then
        player.Character.Humanoid.CameraOffset = Vector3.new(0, 1, -4)
    end

    -- Enable buttons
    if ui.Higher then ui.Higher.Visible = true; ui.Higher.Active = true end
    if ui.Lower then ui.Lower.Visible = true; ui.Lower.Active = true end

    -- Handle guess input
    local function onGuess(guess)
        client.MinigameInput.Fire("guess", guess)
        SoundManager:PlaySFX("BeepSound")
        if ui.Higher then ui.Higher.Active = false end
        if ui.Lower then ui.Lower.Active = false end
    end

    local higherConn, lowerConn, resultConn
    higherConn = ui.Higher.MouseButton1Click:Connect(function() onGuess("Higher") end)
    lowerConn = ui.Lower.MouseButton1Click:Connect(function() onGuess("Lower") end)
    maid:GiveTask(higherConn)
    maid:GiveTask(lowerConn)

    -- Timer logic
    local timeLeft = 60
    if ui and ui.Time then
        ui.Time.Text = string.format("%02d:%02d", math.floor(timeLeft/60), timeLeft%60)
    end
    local timerThread = task.spawn(function()
        while timeLeft > 0 do
            task.wait(1)
            timeLeft = timeLeft - 1
            if ui and ui.Time then
                ui.Time.Text = string.format("%02d:%02d", math.floor(timeLeft/60), timeLeft%60)
            end
        end
        if timeLeft <= 0 then
            client.MinigameInput.Fire("guess_timeout")
        end
    end)
    maid:GiveTask(function() task.cancel(timerThread) end)

    -- Cleanup function
    local function cleanup()
        ui.Visible = false
        if ui.Higher then ui.Higher.Active = false end
        if ui.Lower then ui.Lower.Active = false end
        maid:DoCleaning()
        if ui and ui.Time then ui.Time.Text = "" end
        -- Restore camera settings
        player.CameraMinZoomDistance = 0.5
        player.CameraMaxZoomDistance = 0.5
        if player.Character and player.Character:FindFirstChild("Humanoid") then
            player.Character.Humanoid.CameraOffset = Vector3.new(0, 0, 0)
        end
    end

    -- Listen for result and endgame events
    resultConn = client.UpdateUI.On(function(ui_type, element, value)
        print("[HigherLower] client.UpdateUI.On handler called", ui_type, element)
        if ui_type == "Game" and element == "HigherLowerResult" then
            if value and value.result == "advance" then
                if ui.Number then ui.Number.Text = "10" end
                if ui.Higher then ui.Higher.Active = true end
                if ui.Lower then ui.Lower.Active = true end
                SoundManager:PlaySFX("CardFlipping")
            elseif value and value.result == "eliminate" then
                cleanup()
                SoundManager:PlaySFX("Beep")
            end
        end
    end)
    maid:GiveTask(resultConn)
    maid:GiveTask(client.UpdateUI.On(function(ui_type, element, value)
        print("[HigherLower] client.UpdateUI.On handler called", ui_type, element)
        if ui_type == "Game" and element == "EndGame" then
            print("[HigherLower] EndGame event received, calling cleanup")
            cleanup()
            if ui then ui.Visible = false end
        end
    end))
    return cleanup
end 