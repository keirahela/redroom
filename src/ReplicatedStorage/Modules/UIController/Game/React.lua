-- React Minigame UI Controller
local Maid = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Maid"))
local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))
local Players = game:GetService("Players")
local SoundManager = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundManager"))

-- Format seconds as MM:SS
local function formatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", mins, secs)
end

return function(ui)
    local maid = Maid.new()
    ui.Visible = true
    local player = Players.LocalPlayer
    player.CameraMaxZoomDistance = 2
    player.CameraMinZoomDistance = 2
    if player.Character and player.Character:FindFirstChild("Humanoid") then
        player.Character.Humanoid.CameraOffset = Vector3.new(0, 1, -4)
    end
    local reactPhase = false
    local finished = false
    if ui.Countdown then ui.Countdown.Visible = false end
    if ui.Time then ui.Time.Visible = false end -- Remove timer UI
    if ui.TextButton then ui.TextButton.Visible = false end
    -- Timer and countdown threads
    local timerThread, countdownThread
    -- Cleanup function
    local function cleanup()
        ui.Visible = false
        maid:DoCleaning()
        player.CameraMinZoomDistance = 0.5
        player.CameraMaxZoomDistance = 0.5
        if player.Character and player.Character:FindFirstChild("Humanoid") then
            player.Character.Humanoid.CameraOffset = Vector3.new(0, 0, 0)
        end
    end
    -- Show result and maybe cleanup
    local function showResultAndMaybeCleanup(result)
        if result == "advance" then
            if ui.TextInfo then
                ui.TextInfo.Text = "You won!"
                SoundManager:PlaySFX("BeepSound")
            end
            maid:GiveTask(task.spawn(function()
                task.wait(2.5)
                cleanup()
            end))
        elseif result == "fail" then
            if ui.TextInfo then ui.TextInfo.Text = "Try again!" end
            if ui.TextButton then
                ui.TextButton.Visible = true
                ui.TextButton.Text = "Wait..."
                reactPhase = false
            end
            SoundManager:PlaySFX("Beep")
            finished = false -- Allow clicking again
        end
    end
    -- Listen for server events
    local reactConn
    reactConn = client.UpdateUI.On(function(ui_type, element, value)
        if ui_type == "Game" and element == "ReactCountdown" then
            if ui.Countdown then
                if value and value ~= "" then
                    ui.Countdown.Visible = true
                    ui.Countdown.Text = tostring(value)
                    SoundManager:PlaySFX("GameSelecting")
                else
                    ui.Countdown.Visible = false
                end
            end
        end
        -- REMOVE TIMER: do not update ui.Time
        -- if ui_type == "Game" and element == "ReactTime" and ui.Time then
        --     ui.Time.Text = formatTime(value)
        -- end
        if ui_type == "Game" and element == "ReactPhase" and ui.TextButton then
            if value == "wait" then
                ui.TextButton.Visible = true
                ui.TextButton.Text = "Wait..."
                reactPhase = false
            elseif value == "click" then
                ui.TextButton.Visible = true
                ui.TextButton.Text = "CLICK!"
                reactPhase = true
                SoundManager:PlaySFX("Spinning")
            elseif value == "done" then
                ui.TextButton.Visible = false
            end
        end
        if ui_type == "Game" and element == "ReactResult" and value then
            showResultAndMaybeCleanup(value.result)
        end
    end)
    maid:GiveTask(reactConn)
    maid:GiveTask(client.UpdateUI.On(function(ui_type, element, value)
        if ui_type == "Game" and element == "EndGame" then
            cleanup()
            if ui then ui.Visible = false end
        end
    end))
    maid:GiveTask(ui.TextButton.MouseButton1Click:Connect(function()
        if finished then return end
        if not reactPhase then
            client.MinigameInput.Fire("react_fail", {zone = "fail_early"})
            -- Do not set finished=true, allow retry
            return
        end
        client.MinigameInput.Fire("react_click", {zone = "clicked"})
        finished = true
    end))
    return cleanup
end 