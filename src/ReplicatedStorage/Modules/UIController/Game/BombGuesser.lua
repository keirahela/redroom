-- BombGuesser Minigame UI Controller
local Maid = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Maid"))
local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))
local Players = game:GetService("Players")
local SoundManager = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundManager"))

return function(ui)
    local maid = Maid.new()
    -- Show and initialize UI
    ui.Visible = true
    if ui["Pick One"] then ui["Pick One"].Text = "Pick The Dud :]" end
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
    local picked = false
    local hoveredIndex = nil
    local function setArrows(index)
        hoveredIndex = index
        for i, arrow in ipairs(arrowLabels) do
            if arrow then arrow.Visible = (i == index) end
            if bombButtons[i] then bombButtons[i].BackgroundTransparency = (i == index) and 0.7 or 1 end
        end
    end
    local function setButtonsEnabled(enabled)
        for _, btn in ipairs(bombButtons) do
            if btn then btn.Active = enabled end
        end
    end
    local player = Players.LocalPlayer
    player.CameraMaxZoomDistance = 2
    player.CameraMinZoomDistance = 2
    if player.Character and player.Character:FindFirstChild("Humanoid") then
        player.Character.Humanoid.CameraOffset = Vector3.new(0, 1, -4)
    end
    local function cleanup()
        ui.Visible = false
        maid:DoCleaning()
        setButtonsEnabled(false)
        for _, arrow in ipairs(arrowLabels) do if arrow then arrow.Visible = false end end
        player.CameraMinZoomDistance = 0.5
        player.CameraMaxZoomDistance = 0.5
        if player.Character and player.Character:FindFirstChild("Humanoid") then
            player.Character.Humanoid.CameraOffset = Vector3.new(0, 0, 0)
        end
    end
    for i, btn in ipairs(bombButtons) do
        if btn then
            maid:GiveTask(btn.MouseEnter:Connect(function()
                if not picked then setArrows(i) end
            end))
            maid:GiveTask(btn.MouseLeave:Connect(function()
                task.defer(function()
                    if not picked and hoveredIndex == i then setArrows(nil) end
                end)
            end))
        end
    end
    for i, btn in ipairs(bombButtons) do
        if btn then
            maid:GiveTask(btn.MouseButton1Click:Connect(function()
                if picked then return end
                picked = true
                setButtonsEnabled(false)
                setArrows(i)
                client.MinigameInput.Fire("bomb_pick", { zone = "bomb" .. tostring(i) })
                SoundManager:PlaySFX("BeepSound")
            end))
        end
    end
    local startConn, resultConn, timeConn
    startConn = client.UpdateUI.On(function(ui_type, element, value)
        if ui_type == "Game" and element == "BombGuesserStart" then
            picked = false
            setButtonsEnabled(true)
            setArrows(nil)
            if ui["Pick One"] then ui["Pick One"].Text = "Pick The Dud :]" end
        end
    end)
    resultConn = client.UpdateUI.On(function(ui_type, element, value)
        if ui_type == "Game" and element == "BombGuesserResult" then
            setButtonsEnabled(false)
            if value and value.result == "advance" then
                if ui["Pick One"] then ui["Pick One"].Text = "You survived!" end
                SoundManager:PlaySFX("CardFlipping")
            elseif value and value.result == "eliminate" then
                if ui["Pick One"] then ui["Pick One"].Text = "You exploded!" end
                SoundManager:PlaySFX("Beep")
            end
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
    timeConn = client.UpdateUI.On(function(ui_type, element, value)
        if ui_type == "Game" and element == "BombGuesserTime" and value and value.time then
            if ui.Time then ui.Time.Text = tostring(value.time) end
        end
    end)
    maid:GiveTask(startConn)
    maid:GiveTask(resultConn)
    maid:GiveTask(timeConn)
    maid:GiveTask(client.UpdateUI.On(function(ui_type, element, value)
        if ui_type == "Game" and element == "EndGame" then
            cleanup()
            if ui then ui.Visible = false end
        end
    end))
    return cleanup
end
