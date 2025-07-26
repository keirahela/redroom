-- Alice in Borderland HigherLower Minigame UI Controller
local Maid = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Maid"))
local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))
local Players = game:GetService("Players")
local SoundManager = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundManager"))

return function(ui)
    local maid = Maid.new()
    local player = Players.LocalPlayer
    ui.Visible = true
    -- UI references (updated for new names)
    local inputFrame = ui:FindFirstChild("First")
    local textBox = inputFrame and inputFrame:FindFirstChildWhichIsA("TextBox")
    local submitButton = inputFrame and inputFrame:FindFirstChildWhichIsA("TextButton")
    local revealFrame = ui:FindFirstChild("Second")
    local gridParent = revealFrame and revealFrame:FindFirstChild("Frame")
    local gridLayout = gridParent and gridParent:FindFirstChildWhichIsA("UIGridLayout")
    local template = gridLayout and gridLayout:FindFirstChildWhichIsA("TextLabel")
    local resultLabel = revealFrame and revealFrame:FindFirstChild("TextLabel")
    -- State
    local submitted = false
    local myNumber = nil
    local revealEntries = {}
    local winnerIndex = nil
    local target = nil
    -- Camera settings for minigame
    player.CameraMaxZoomDistance = 2
    player.CameraMinZoomDistance = 2
    if player.Character and player.Character:FindFirstChild("Humanoid") then
        player.Character.Humanoid.CameraOffset = Vector3.new(0, 1, -4)
    end
    -- Helper: Reset UI
    local function resetUI()
        if inputFrame then inputFrame.Visible = true end
        if revealFrame then revealFrame.Visible = false end
        if textBox then textBox.Text = ""; textBox.PlaceholderText = "PICK A NUMBER 0-100" end
        if submitButton then submitButton.Active = true; submitButton.BackgroundColor3 = Color3.fromRGB(41,255,17) end
        submitted = false
        myNumber = nil
        winnerIndex = nil
        target = nil
        -- Clear grid
        if gridParent then
            for _, child in ipairs(gridParent:GetChildren()) do
                if child:IsA("TextLabel") and child ~= template then
                    child:Destroy()
                end
            end
        end
        if resultLabel then resultLabel.Text = "" end
    end
    resetUI()
    -- Timer
    local function setTimerText(secs)
        if inputFrame and inputFrame:FindFirstChild("Time") then
            local t = inputFrame.Time
            t.Text = string.format("%02d:%02d", math.floor(secs/60), secs%60)
        end
    end
    -- Input phase
    local function enterInputPhase(time)
        resetUI()
        if inputFrame then inputFrame.Visible = true end
        if revealFrame then revealFrame.Visible = false end
        setTimerText(time or 120)
    end
    -- Reveal phase
    local function enterRevealPhase()
        if inputFrame then inputFrame.Visible = false end
        if revealFrame then revealFrame.Visible = true end
        if resultLabel then resultLabel.Text = "" end
        -- Clear grid except template
        if gridParent then
            for _, child in ipairs(gridParent:GetChildren()) do
                if child:IsA("TextLabel") and child ~= template then
                    child:Destroy()
                end
            end
        end
    end
    -- Handle submit
    if submitButton then
        maid:GiveTask(submitButton.MouseButton1Click:Connect(function()
            if submitted then return end
            local num = tonumber(textBox and textBox.Text)
            if not num or num < 1 or num > 100 then
                if textBox then textBox.Text = ""; textBox.PlaceholderText = "ENTER 0-100!" end
                SoundManager:PlaySFX("Beep")
                return
            end
            submitted = true
            myNumber = num
            submitButton.Active = false
            submitButton.BackgroundColor3 = Color3.fromRGB(128,128,128)
            client.MinigameInput.Fire("submit_number", { zone = "hl_" .. tostring(num) })
            SoundManager:PlaySFX("BeepSound")
        end))
    end
    -- Listen for server events
    maid:GiveTask(client.UpdateUI.On(function(ui_type, element, value)
        if ui_type ~= "Game" then return end
        if element == "HigherLowerPhase" and value and value.phase == "input" then
            enterInputPhase(value.data and value.data.time)
        elseif element == "HigherLowerTimer" and value and value.timeLeft then
            setTimerText(value.timeLeft)
        elseif element == "HigherLowerPhase" and value and value.phase == "reveal" then
            enterRevealPhase()
        elseif element == "HigherLowerReveal" and value and value.submissions then
            enterRevealPhase()
            -- Show each entry in grid
            local entries = value.submissions
            winnerIndex = value.winnerIndex
            target = value.target
            -- Remove old entries
            if gridParent then
                for _, child in ipairs(gridParent:GetChildren()) do
                    if child:IsA("TextLabel") and child ~= template then
                        child:Destroy()
                    end
                end
            end
            -- Add new entries and update resultLabel as numbers appear
            local numbers = {}
            local labelRefs = {}
            for i, entry in ipairs(entries) do
                local label = template:Clone()
                label.Parent = gridParent
                label.Visible = true
                label.Text = tostring(entry.number)
                label.Name = entry.name
                label.BackgroundColor3 = Color3.fromRGB(255,255,255)
                label.TextColor3 = Color3.fromRGB(0,0,0)
                table.insert(numbers, entry.number)
                labelRefs[i] = label
                if resultLabel then
                    resultLabel.Text = table.concat(numbers, " ")
                end
            end
            -- Only run the calculation animation after all numbers are revealed (when winnerIndex and target are present)
            if #entries > 0 and resultLabel and winnerIndex and target then
                task.spawn(function()
                    task.wait(1)
                    local sum = 0
                    for _, n in ipairs(numbers) do sum = sum + n end
                    local count = #numbers
                    resultLabel.Text = tostring(sum)
                    task.wait(1)
                    resultLabel.Text = tostring(sum) .. " /"
                    task.wait(1)
                    resultLabel.Text = tostring(sum) .. " / " .. tostring(count)
                    task.wait(1)
                    local avg = sum / count
                    resultLabel.Text = string.format("%.2f", avg)
                    task.wait(1)
                    resultLabel.Text = string.format("%.2f", avg) .. " *"
                    task.wait(1)
                    resultLabel.Text = string.format("%.2f", avg) .. " * 0.8"
                    task.wait(1)
                    local calcTarget = math.floor(avg * 0.8 + 0.5)
                    resultLabel.Text = tostring(calcTarget)
                    -- Highlight winner now
                    if winnerIndex and labelRefs[winnerIndex] then
                        local label = labelRefs[winnerIndex]
                        label.BackgroundColor3 = Color3.fromRGB(41,255,17)
                        label.TextColor3 = Color3.fromRGB(0,0,0)
                        label.Text = tostring(entries[winnerIndex].number)
                    end
                end)
            end
        end
    end))
    -- Cleanup
    local function cleanup()
        ui.Visible = false
        maid:DoCleaning()
        player.CameraMinZoomDistance = 0.5
        player.CameraMaxZoomDistance = 0.5
        if player.Character and player.Character:FindFirstChild("Humanoid") then
            player.Character.Humanoid.CameraOffset = Vector3.new(0, 0, 0)
        end
    end
    maid:GiveTask(cleanup)
    return cleanup
end 