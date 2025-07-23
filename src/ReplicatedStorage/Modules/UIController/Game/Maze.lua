-- Maze Minigame UI Controller
local Maid = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Maid"))
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))
local GAME_DATA = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Data"):WaitForChild("GAME_DATA"))
local SoundManager = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundManager"))

return function(ui)
    print("[Maze] Minigame UI logic started", debug.traceback())
    local maid = Maid.new()
    local connections = {}
    local mouseInStart = false
    local currentDifficulty = 1
    local gameTimer = nil
    local gameActive = false
    local maxDifficulty = 3
    local setupDangerZone
    -- Format seconds as MM:SS
    local function formatTime(seconds)
        local mins = math.floor(seconds / 60)
        local secs = math.floor(seconds % 60)
        return string.format("%02d:%02d", mins, secs)
    end
    local function cleanup()
        gameActive = false
        mouseInStart = false
        stopTimer()
        maid:DoCleaning()
        if ui then ui.Visible = false end
        Players.LocalPlayer.CameraMinZoomDistance = 0.5
        Players.LocalPlayer.CameraMaxZoomDistance = 0.5
        if Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("Humanoid") then
            Players.LocalPlayer.Character.Humanoid.CameraOffset = Vector3.new(0, 0, 0)
        end
        print("Maze game stopped!")
    end
    -- Generate maze UI for current difficulty
    local function generateMaze(ui, setupDangerZone)
        for _, child in pairs(ui:GetChildren()) do
            if child.Name == "Danger" then
                child:Destroy()
            end
        end
        local difficulty = GAME_DATA.maze_difficulties[currentDifficulty]
        for _, dangerConfig in ipairs(difficulty.dangers) do
            local danger = Instance.new("Frame")
            danger.Name = "Danger"
            danger.Parent = ui
            danger.Active = true
            danger.BackgroundColor3 = Color3.fromRGB(255, 0, 4)
            danger.BorderSizePixel = 0
            danger.Position = dangerConfig.position
            danger.Size = dangerConfig.size
            setupDangerZone(danger)
        end
        if ui and ui.Time then
            print("[Maze] Accessing ui.Time", ui.Time)
            ui.Time.Text = formatTime(10)
        end
    end
    local function stopTimer()
        if gameTimer then
            if typeof(gameTimer) == "RBXScriptConnection" then
                gameTimer:Disconnect()
            else
                pcall(function() task.cancel(gameTimer) end)
            end
            gameTimer = nil
        end
    end
    local function startTimer(ui, onTimeout)
        stopTimer()
        local timeLeft = 10
        if ui and ui.Time then
            print("[Maze] Accessing ui.Time", ui.Time)
            ui.Time.Text = formatTime(timeLeft)
        end
        gameTimer = RunService.Heartbeat:Connect(function(dt)
            timeLeft = timeLeft - dt
            if ui and ui.Time then
                print("[Maze] Accessing ui.Time", ui.Time)
                ui.Time.Text = formatTime(math.max(0, timeLeft))
            end
            if timeLeft <= 0 then
                gameTimer:Disconnect()
                gameTimer = nil
                onTimeout()
            end
        end)
        maid:GiveTask(gameTimer)
    end
    local function eliminatePlayer(ui, onElimination)
        gameActive = false
        stopTimer()
        if ui and ui.Time then
            print("[Maze] Accessing ui.Time", ui.Time)
            ui.Time.Text = ""
        end
        for _, child in pairs(ui:GetChildren()) do
            if child.Name == "Danger" then
                local flash = TweenService:Create(child, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 5, true), {BackgroundColor3 = Color3.fromRGB(150, 0, 0)})
                flash:Play()
            end
        end
        SoundManager:PlaySFX("Beep")
        SoundManager:PlaySFX("NormalDeathSFX")
        client.MinigameInput.Fire("eliminated", nil)
        mouseInStart = false
        gameActive = true
        startTimer(ui, function()
            eliminatePlayer(ui, onElimination)
        end)
    end
    local function playerWin(ui, onWin, setupDangerZone)
        gameActive = false
        stopTimer()
        if ui and ui.Time then
            print("[Maze] Accessing ui.Time", ui.Time)
            ui.Time.Text = ""
        end
        local endZone = ui:FindFirstChild("End")
        if endZone then
            local victory = TweenService:Create(endZone, TweenInfo.new(0.2, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.fromRGB(100, 255, 100)})
            victory:Play()
        end
        SoundManager:PlaySFX("BeepSound")
        if currentDifficulty >= maxDifficulty then
            print("completed all levels")
            client.MinigameInput.Fire("ended", nil)
            task.delay(0.6, function() cleanup() end)
            return
        end
        currentDifficulty = currentDifficulty + 1
        task.wait(1)
        if onWin then onWin(false) end
        generateMaze(ui, setupDangerZone)
        mouseInStart = false
        gameActive = true
        startTimer(ui, function()
            eliminatePlayer(ui, function() end)
        end)
    end
    local function setupGUIEvents(ui, onElimination, onWin)
        local startZone = ui:FindFirstChild("Start")
        if startZone then
            startZone.BackgroundColor3 = Color3.fromRGB(0, 0, 255)
            startZone.Active = true
            table.insert(connections, startZone.MouseEnter:Connect(function()
                if not mouseInStart and gameActive then
                    mouseInStart = true
                end
            end))
        end
        local endZone = ui:FindFirstChild("End")
        if endZone then
            endZone.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
            endZone.Active = true
            table.insert(connections, endZone.MouseEnter:Connect(function()
                if mouseInStart and gameActive then
                    playerWin(ui, onWin, setupDangerZone)
                end
            end))
            table.insert(connections, endZone.MouseMoved:Connect(function()
                if mouseInStart and gameActive then
                    playerWin(ui, onWin, setupDangerZone)
                end
            end))
            table.insert(connections, endZone.MouseLeave:Connect(function()
                if mouseInStart and gameActive then
                    playerWin(ui, onWin, setupDangerZone)
                end
            end))
        end
        function setupDangerZone(dangerFrame)
            table.insert(connections, dangerFrame.MouseEnter:Connect(function()
                if mouseInStart and gameActive then
                    eliminatePlayer(ui, onElimination)
                end
            end))
        end
        return setupDangerZone
    end
    mouseInStart = false
    gameActive = true
    currentDifficulty = 1
    stopTimer()
    Players.LocalPlayer.CameraMaxZoomDistance = 2
    Players.LocalPlayer.CameraMinZoomDistance = 2
    Players.LocalPlayer.Character.Humanoid.CameraOffset = Vector3.new(0, 1, -4)
    local mouse = Players.LocalPlayer:GetMouse()
    function onElimination() end
    local function onWin(fullCompletion)
        if fullCompletion then
            Players.LocalPlayer.Character.Humanoid.CameraOffset = Vector3.new(0, 0, 0)
            Players.LocalPlayer.CameraMinZoomDistance = 0.5
            Players.LocalPlayer.CameraMaxZoomDistance = 0.5
        else
            gameActive = true
        end
    end
    setupDangerZone = setupGUIEvents(ui, onElimination, onWin)
    generateMaze(ui, setupDangerZone)
    startTimer(ui, function() eliminatePlayer(ui, onElimination) end)
    local renderConn
    renderConn = RunService.RenderStepped:Connect(function()
        if mouseInStart and gameActive then
            local camera = workspace.CurrentCamera
            if camera then
                local mousePos = Vector2.new(mouse.X, mouse.Y)
                local unitRay = camera:ScreenPointToRay(mousePos.X, mousePos.Y)
                local rayOrigin = unitRay.Origin
                local rayDirection = unitRay.Direction * 1000
                local raycastParams = RaycastParams.new()
                raycastParams.FilterDescendantsInstances = {Players.LocalPlayer.Character}
                raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
                if result then
                    local hit = result.Instance
                    if not (hit and string.find(hit.Name, "Screen")) then
                        eliminatePlayer(ui, onElimination)
                    end
                else
                    eliminatePlayer(ui, onElimination)
                end
            end
        end
    end)
    maid:GiveTask(renderConn)
    maid:GiveTask(client.UpdateUI.On(function(ui_type, element, value)
        print("[Maze] client.UpdateUI.On handler called", ui_type, element)
        if ui_type == "Game" and element == "EndGame" then
            print("[Maze] EndGame event received, calling cleanup")
            cleanup()
            if ui then ui.Visible = false end
        end
    end))
    for _, conn in ipairs(connections) do
        maid:GiveTask(conn)
    end
    return cleanup
end