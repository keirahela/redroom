-- DragTheLine Minigame UI Controller
local Maid = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Maid"))
local Players = game:GetService("Players")
local SoundManager = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundManager"))
local client = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("client"))

return function(ui)
    local maid = Maid.new()
    ui.Visible = true
    -- Camera settings for minigame
    local player = game:GetService("Players").LocalPlayer
    player.CameraMaxZoomDistance = 2
    player.CameraMinZoomDistance = 2
    if player.Character and player.Character:FindFirstChild("Humanoid") then
        player.Character.Humanoid.CameraOffset = Vector3.new(0, 1, -4)
    end
    -- Defensive check for UI structure
    local children = ui:GetChildren()
    if #children == 0 then
        warn("[DragTheLine] UI has no children!", ui)
        return
    end
    local DraggingBackGround = ui:FindFirstChild("DraggingBackGround")
    if not DraggingBackGround then
        warn("[DragTheLine] DraggingBackGround missing in UI!", ui)
        return
    end
    local Draggable = DraggingBackGround:FindFirstChild("Draggable")
    if not Draggable then
        warn("[DragTheLine] Draggable missing in DraggingBackGround!", DraggingBackGround)
        return
    end
    local ToDraggedto = DraggingBackGround:FindFirstChild("ToDraggedto")
    if not ToDraggedto then
        warn("[DragTheLine] ToDraggedto missing in DraggingBackGround!", DraggingBackGround)
        return
    end
    local Info = ui:FindFirstChild("Info")
    if not Info then
        warn("[DragTheLine] Info missing in UI!", ui)
        return
    end
    local dragging = false
    local overGoal = false
    -- Helper to check if a point is inside a frame
    local function isPointInFrame(point, frame)
        local absPos = frame.AbsolutePosition
        local absSize = frame.AbsoluteSize
        return point.X >= absPos.X and point.X <= absPos.X + absSize.X and point.Y >= absPos.Y and point.Y <= absPos.Y + absSize.Y
    end
    -- Reset draggable position
    local function resetDraggable()
        Draggable.Position = UDim2.new(0.03, 0, 0.5, 0)
    end
    -- Handle player win
    local function cleanup()
        ui.Visible = false
        maid:DoCleaning()
        player.CameraMinZoomDistance = 0.5
        player.CameraMaxZoomDistance = 0.5
        if player.Character and player.Character:FindFirstChild("Humanoid") then
            player.Character.Humanoid.CameraOffset = Vector3.new(0, 0, 0)
        end
    end
    local function win()
        SoundManager:PlaySFX("BeepSound")
        if Info then Info.Text = "You won!" end
        print("[DragTheLine][CLIENT] Firing MinigameInput 'ended' event")
        client.MinigameInput.Fire("ended", nil)
        local thread = task.spawn(function()
            task.wait(1)
            cleanup()
        end)
        maid:GiveTask(function()
            if coroutine.status(thread) ~= "dead" then
                pcall(task.cancel, thread)
            end
        end)
    end
    -- Track if mouse is over the goal
    maid:GiveTask(ToDraggedto.MouseEnter:Connect(function() overGoal = true end))
    maid:GiveTask(ToDraggedto.MouseLeave:Connect(function() overGoal = false end))
    -- Eliminate if mouse leaves background while dragging
    local function onBackgroundLeave()
        if dragging then resetDraggable() end
    end
    maid:GiveTask(DraggingBackGround.MouseLeave:Connect(onBackgroundLeave))
    -- Simple drag logic using UI events (no raycasting, no timer)
    maid:GiveTask(Draggable.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            Draggable.ZIndex = 3
        end
    end))
    maid:GiveTask(DraggingBackGround.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local absPos = DraggingBackGround.AbsolutePosition
            local absSize = DraggingBackGround.AbsoluteSize
            local localX = input.Position.X - absPos.X
            local relX = math.clamp(localX / absSize.X, 0.03, 0.97)
            Draggable.Position = UDim2.new(relX, 0, 0.5, 0)
        end
    end))
    maid:GiveTask(Draggable.InputEnded:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
            Draggable.ZIndex = 2
            if overGoal then
                win()
            else
                resetDraggable()
            end
        end
    end))
    resetDraggable()
    return cleanup
end
