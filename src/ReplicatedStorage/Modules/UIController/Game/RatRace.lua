-- RatRace Minigame UI Controller
local Maid = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Maid"))
local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))
local Players = game:GetService("Players")
local SoundManager = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundManager"))

-- Helper to convert index to ordinal string
local function ordinal(n)
    local ordinals = {"FIRST", "SECOND", "THIRD", "FOURTH", "FIFTH", "SIXTH"}
    return ordinals[n] or tostring(n)
end

-- Format seconds as MM:SS
local function formatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", mins, secs)
end

return function(ui)
    local maid = Maid.new()
    local yourRat = nil
    local function cleanup()
        ui.Visible = false
        maid:DoCleaning()
        local player = Players.LocalPlayer
        player.CameraMinZoomDistance = 0.5
        player.CameraMaxZoomDistance = 0.5
        if player.Character and player.Character:FindFirstChild("Humanoid") then
            player.Character.Humanoid.CameraOffset = Vector3.new(0, 0, 0)
        end
    end
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
    local takenRats = {}
    ui.Encourage.Active = false
    ui.Encourage.Visible = false
    if ui.Countdown then ui.Countdown.Visible = false end
    if ui.Time then ui.Time.Visible = true; ui.Time.Text = formatTime(60) end
    local function resetRatRaceUI()
        for i, btn in ipairs(rats) do
            btn.BackgroundColor3 = Color3.fromRGB(255,255,255)
            btn.BackgroundTransparency = 1
            btn.Active = true
            btn.ImageTransparency = 0
        end
        selectedRat = nil
        ui.YoureRatLabel.Text = "PICK YOUR RAT"
        ui.Encourage.Active = false
        ui.Encourage.Visible = false
        ui.Encourage.Text = "Encourage Rat"
        if ui.Countdown then ui.Countdown.Visible = false end
        if ui.Time then ui.Time.Visible = true; ui.Time.Text = formatTime(60) end
    end
    local function updateRatUI()
        print("[RatRace][CLIENT] updateRatUI called. takenRats:", takenRats)
        local player = Players.LocalPlayer
        local found = false
        for i, btn in ipairs(rats) do
            local key = tostring(i)
            if takenRats[key] then
                print("[RatRace][CLIENT] Disabling rat", i)
                btn.BackgroundColor3 = Color3.fromRGB(255,0,0)
                btn.BackgroundTransparency = 0.7
                btn.Active = false
                btn.ImageTransparency = 0.5 -- Always dim taken rats
                if selectedRat == i then found = true end
            else
                btn.BackgroundColor3 = Color3.fromRGB(255,255,255)
                btn.BackgroundTransparency = 1
                btn.Active = true
                btn.ImageTransparency = 0.5 -- Default for available rats, will be set to 0 for selected
            end
        end
        -- Only clear selection if yourRat is nil or does not match selectedRat
        if selectedRat and (yourRat == nil or yourRat ~= selectedRat) then
            print("[RatRace][CLIENT] Our selected rat is no longer ours. Clearing selection.")
            selectedRat = nil
            resetRatRaceUI()
        end
        -- Only highlight the local player's rat
        if selectedRat then
            for j, btn in ipairs(rats) do
                if j == selectedRat then
                    btn.ImageTransparency = 0
                else
                    btn.ImageTransparency = 0.5
                end
            end
            ui.YoureRatLabel.Text = "YOUR RAT: " .. ordinal(selectedRat)
            ui.Encourage.Active = true
            ui.Encourage.Visible = true
            ui.Encourage.BackgroundTransparency = 0.2
        end
    end
    maid:GiveTask(client.UpdateUI.On(function(ui_type, element, value)
        if ui_type == "Game" and element == "RatRaceTakenRats" and type(value) == "table" then
            print("[RatRace][CLIENT] Received takenRats from server:", value)
            takenRats = value.takenRats or value
            yourRat = value.yourRat
            selectedRat = yourRat
            updateRatUI()
            -- Only lock in selection if server confirms it
            if selectedRat and (yourRat == nil or yourRat ~= selectedRat) then
                print("[RatRace][CLIENT] Server did not confirm our selection. Clearing selectedRat.")
                selectedRat = nil
            end
        elseif ui_type == "Game" and element == "RatRaceReset" then
            -- Reset all rat positions to the beginning
            for i, rat in ipairs(rats) do
                if rat then
                    rat.Position = UDim2.new(0, 0, rat.Position.Y.Scale, rat.Position.Y.Offset)
                end
            end
        end
    end))
    for i, ratBtn in ipairs(rats) do
        ratBtn.Active = true
        ratBtn.ImageTransparency = 0
        maid:GiveTask(ratBtn.MouseEnter:Connect(function()
            if takenRats[tostring(i)] then return end -- Do not change appearance on hover if taken
            ratBtn.BackgroundTransparency = 0.7
            SoundManager:PlaySFX("BeepSound")
        end))
        maid:GiveTask(ratBtn.MouseLeave:Connect(function()
            if takenRats[tostring(i)] then return end -- Do not change appearance on hover if taken
            ratBtn.BackgroundTransparency = 1
        end))
        maid:GiveTask(ratBtn.MouseButton1Click:Connect(function()
            print("[RatRace][CLIENT] Player selected rat", i)
            if selectedRat or raceStarted or takenRats[tostring(i)] then return end
            -- Only send request, do not lock in selection yet
            client.MinigameInput.Fire("rat_select", {zone = "rat" .. i})
            SoundManager:PlaySFX("BeepSound")
        end))
    end
    maid:GiveTask(ui.Encourage.MouseButton1Click:Connect(function()
        if not selectedRat or encourageCooldown or not raceStarted then return end
        encourageCooldown = true
        ui.Encourage.Text = "Cheering!"
        client.MinigameInput.Fire("encourage_rat", {zone = "encourage" .. selectedRat})
        SoundManager:PlaySFX("BeepSound")
        local thread = task.delay(2, function()
            encourageCooldown = false
            ui.Encourage.Text = "Encourage Rat"
        end)
        maid:GiveTask(function() task.cancel(thread) end)
    end))
    local timerThread, countdownThread
    local ratUpdateConn
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
                    SoundManager:PlaySFX("GameSelecting")
                    raceStarted = false
                else
                    ui.Countdown.Visible = false
                    raceStarted = true
                    SoundManager:PlaySFX("Spinning")
                end
            end
        end
        if ui_type == "Game" and element == "RatRaceTime" and ui.Time then
            ui.Time.Text = formatTime(value)
        end
        if ui_type == "Game" and element == "RatRaceResult" and value then
            if value.result == "advance" or value.result == "fail" or value.result == "timeout" then
                resetRatRaceUI()
            end
        end
    end)
    maid:GiveTask(ratUpdateConn)
    maid:GiveTask(client.UpdateUI.On(function(ui_type, element, value)
        if ui_type == "Game" and element == "EndGame" then
            cleanup()
            if ui then ui.Visible = false end
        end
    end))
    return cleanup
end 