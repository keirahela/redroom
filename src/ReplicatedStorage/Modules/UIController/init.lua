--[[
Spectate System:
- Listens for PlayerDataUpdated event.
- When is_spectating becomes true, teleports player to SpawnLocation (server), shows SpectateUI, and sets camera to tagged Camera parts.
- Allows switching between cameras with UI buttons.
- Cleans up and restores camera when spectating ends.
]]
-- UIController: Manages all main UI logic and minigame UI switching
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local TweenService = game:GetService("TweenService")
local client = require(ReplicatedStorage:WaitForChild("network"):WaitForChild("client"))
local RunService = game:GetService("RunService")

local Highlight = Instance.new("Highlight")
Highlight.FillColor = Color3.fromRGB(255, 0, 0)
Highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
Highlight.Enabled = false
Highlight.Name = "WinnerHighlight"

local ui = {}
ui.__index = ui

export type UIController = {
    scope: Fusion.Scope,
    game_ui: Instance,
    timer_thread: thread?,
}

local current_controller: UIController? = nil

-- Add a variable to track the last used iteration
local last_screen_iteration = 1

local close_frames = {
    ["GameStart"] = true,
    ["Lives"] = true,
    ["MazeGame"] = true,
    ["RatRaceGuide"] = true,
    ["Tutorial"] = true,
    ["WinLossScreen"] = true,
}

-- Closes all main game frames
function ui.close_all(): boolean
    if current_controller then
        local background = current_controller.game_ui:FindFirstChild("Background")
        assert(background, "game_ui.Background must exist")
        for _, v in background:GetChildren() do
            if close_frames[v.Name] and v:IsA("Frame") then
                v.Visible = false
            end
        end
        return true
    end
    return false
end

-- Starts a countdown timer in the UI
function ui.start_timer(self: UIController, timer: number): boolean
    if not self or not self.game_ui then return false end
    if self.timer_thread then task.cancel(self.timer_thread) end
    self.timer_thread = task.spawn(function()
        for i = timer, 0, -1 do
            local background = self.game_ui and self.game_ui:FindFirstChild("Background")
            local timerFrame = background and background:FindFirstChild("Timer")
            if timerFrame and timerFrame:FindFirstChild("TimerNumber") then
                timerFrame.Visible = true
                timerFrame.TimerNumber.Text = `{i}`
            end
            if i > 0 then task.wait(1) end
        end
        self.timer_thread = nil
        -- Optionally hide the timer after finishing
        local background = self.game_ui and self.game_ui:FindFirstChild("Background")
        local timerFrame = background and background:FindFirstChild("Timer")
        if timerFrame then
            timerFrame.Visible = false
        end
    end)
    return true
end

-- Creates a new UIController singleton
function ui.new(): UIController
    if current_controller then return current_controller end
    local self = setmetatable({}, ui)
    self.scope = Fusion:scoped()

    -- Event: Round starting (show timer/countdown)
    client.RoundStarting.On(function(data)
        print(`round starting in {data.duration}`)
        -- Rehydrate main UI if missing or missing Background
        if not self.game_ui or not self.game_ui:FindFirstChild("Background") then
            if self.game_ui then self.game_ui:Destroy() end
            self.game_ui = self.scope:Hydrate(ReplicatedStorage.UI.CRTSurfaceGui:Clone()) {
                Parent = Players.LocalPlayer.PlayerGui,
            }
        end
        self.start_timer(self, data.duration)
        -- Show custom countdown UI only if duration > 3
        local CountdownUI = ReplicatedStorage:FindFirstChild("UI") and ReplicatedStorage.UI:FindFirstChild("CountdownUI")
        local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
        if data.duration and data.duration > 3 then
            if playerGui then
                local old = playerGui:FindFirstChild("CountdownUI")
                if old then old:Destroy() end
            end
            if CountdownUI and playerGui then
                local countdownClone = CountdownUI:Clone()
                countdownClone.Parent = playerGui
                local countdownLabel = countdownClone:FindFirstChild("CountdownText", true)
                local duration = data.duration or 5
                local timer = duration
                local running = true
                task.spawn(function()
                    while timer > 0 and running do
                        if countdownLabel then
                            countdownLabel.Text = "COUNTDOWN TILL EXAMINATION : " .. timer
                        end
                        task.wait(1)
                        timer -= 1
                    end
                    if countdownLabel then
                        countdownLabel.Text = "COUNTDOWN TILL EXAMINATION : 0"
                    end
                    task.wait(0.5)
                    if countdownClone then
                        countdownClone:Destroy()
                    end
                end)
            end
        end
    end)

    -- Event: Game state changed
    client.GameStateChanged.On(function(state, player_count)
        print(`game state changed to {state}`)
        -- Stop/cleanup all minigames when the round ends or is ending
        if (state == "ENDING" or state == "FINISHED") and self.Game and self.Game.force_cleanup_all_games then
            self.Game:force_cleanup_all_games()
        end
    end)

    -- Hydrate main UI
    self.game_ui = self.scope:Hydrate(ReplicatedStorage.UI.CRTSurfaceGui:Clone()) {
        Parent = Players.LocalPlayer.PlayerGui,
    }
    self.close_all()

    -- Event: Minigame started (switch UI)
    client.MinigameStarted.On(function(data)
        -- Rehydrate main UI if missing or missing Background
        if not self.game_ui or not self.game_ui:FindFirstChild("Background") then
            if self.game_ui then self.game_ui:Destroy() end
            self.game_ui = self.scope:Hydrate(ReplicatedStorage.UI.CRTSurfaceGui:Clone()) {
                Parent = Players.LocalPlayer.PlayerGui,
            }
        end
        self.close_all()
        if not self.Game then
            warn("Game ui controller has not been initialized yet")
            return
        end
        -- Pass the correct minigame UI frame to the minigame
        local background = self.game_ui:FindFirstChild("Background")
        local gamesFolder = background and background:FindFirstChild("Games")
        local minigameFrame = gamesFolder and gamesFolder:FindFirstChild(data.type)
        if not minigameFrame then
            warn("Minigame UI frame not found for", data.type)
            return
        end
        self.Game.start_game(self.Game, data.type, minigameFrame)
    end)

    -- Event: Show UI
    client.ShowUI.On(function(ui_type, iteration)
        print("[CLIENT] ShowUI event received. ui_type:", ui_type, "iteration:", iteration, "Player:", Players.LocalPlayer.Name)
        last_screen_iteration = iteration or 1
        -- CLEANUP ALL MINIGAMES FIRST
        if self.Game and self.Game.stop_games then
            print("[CLIENT] Calling stop_games on self.Game")
            self.Game:stop_games()
        end
        -- Now destroy and remake the main UI
        if self.game_ui then
            print("[CLIENT] Destroying old game_ui")
            self.game_ui:Destroy()
        end
        print("[CLIENT] Creating new game_ui")
        self.game_ui = self.scope:Hydrate(ReplicatedStorage.UI.CRTSurfaceGui:Clone()) {
            Parent = Players.LocalPlayer.PlayerGui,
        }
        self.game_ui.Adornee = workspace.Screens:FindFirstChild(`Screen{iteration}`)
        self.close_all()
        local minigameModule = require(script:FindFirstChild(ui_type))
        if minigameModule.reset_singleton then
            print("[CLIENT] Resetting minigame singleton for:", ui_type)
            minigameModule.reset_singleton()
        end
        print("[CLIENT] Creating new minigame controller for:", ui_type)
        self[ui_type] = minigameModule.new(self.scope, self.game_ui)
    end)

    -- Event: Hide UI
    client.HideUI.On(function(ui_type)
        self.close_all()
        if ui_type ~= "Game" then
            self[ui_type].close()
        end
    end)

    -- Event: Play seat animation
    client.PlaySeatAnimation.On(function(animationId)
        local player = Players.LocalPlayer
        local character = player.Character
        if character and character:FindFirstChild("Humanoid") then
            local humanoid = character.Humanoid
            local animator = humanoid:FindFirstChildOfClass("Animator")
            if not animator then
                animator = Instance.new("Animator")
                animator.Parent = humanoid
            end
            local animation = Instance.new("Animation")
            animation.AnimationId = "rbxassetid://" .. animationId
            local track : AnimationTrack = animator:LoadAnimation(animation)
            track.Looped = true
            track:Play()
        end
    end)

    -- Event: Teleport character
    client.TeleportCharacter.On(function(tpCFrame)
        local player = Players.LocalPlayer
        local character = player.Character
        if character and character:FindFirstChild("HumanoidRootPart") then
            character.HumanoidRootPart.Anchored = true
            character:PivotTo(tpCFrame)
            character.HumanoidRootPart.Velocity = Vector3.new(0,0,0)
            character.HumanoidRootPart.Anchored = true
        end
    end)

    -- Event: Wake up transition (fade in/out)
    local fadeGui
    client.WakeUpTransition.On(function(phase, duration)
        local fadeTemplate = ReplicatedStorage:FindFirstChild("UI") and ReplicatedStorage.UI:FindFirstChild("FadeUI")
        if not fadeTemplate then return end
        if phase == "fadeout" then
            if fadeGui then fadeGui:Destroy() end
            fadeGui = fadeTemplate:Clone()
            fadeGui.ResetOnSpawn = false
            fadeGui.Parent = Players.LocalPlayer.PlayerGui
            local fadeFrame = fadeGui:FindFirstChild("FadeThis", true)
            if not fadeFrame then warn("FadeThis frame not found in FadeUI"); return end
            fadeFrame.BackgroundTransparency = 1
            local tween = TweenService:Create(fadeFrame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0})
            tween:Play()
            tween.Completed:Wait()
        elseif phase == "fadein" then
            if not fadeGui then return end
            local fadeFrame = fadeGui:FindFirstChild("FadeThis", true)
            if not fadeFrame then warn("FadeThis frame not found in FadeUI"); return end
            fadeFrame.BackgroundTransparency = 0
            local tween = TweenService:Create(fadeFrame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1})
            tween:Play()
            tween.Completed:Wait()
            fadeGui:Destroy()
            fadeGui = nil
        end
    end)

    -- Event: Update UI (play SFX, winner choosing, etc.)
    client.UpdateUI.On(function(ui_type, element, value)
        if ui_type == "Game" and element == "PlaySFX" and value and value.name then
            local sfxFolder = game:GetService("SoundService"):FindFirstChild("SoundEffects")
            if sfxFolder then
                local soundTemplate = sfxFolder:FindFirstChild(value.name)
                if soundTemplate then
                    local sound = soundTemplate:Clone()
                    sound.Volume = 1
                    if value.pitch then
                        sound.PlaybackSpeed = value.pitch
                    end
                    sound.Parent = game:GetService("SoundService")
                    sound:Play()
                    task.spawn(function()
                        sound.Ended:Wait()
                        sound:Destroy()
                    end)
                end
            end
        end
        if ui_type == "Game" and element == "StartWinnerChoosing" and value and type(value.players) == "table" then
            local Players = game:GetService("Players")
            local Camera = workspace.CurrentCamera
            local localPlayer = Players.LocalPlayer
            local playerList = value.players
            local highlight = Highlight:Clone()
            highlight.Enabled = true
            local ReplicatedStorage = game:GetService("ReplicatedStorage")
            local CountdownUI = ReplicatedStorage:FindFirstChild("UI") and ReplicatedStorage.UI:FindFirstChild("CountdownUI")
            local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
            local countdownClone, countdownLabel
            if CountdownUI and playerGui then
                local old = playerGui:FindFirstChild("CountdownUI")
                if old then old:Destroy() end
                countdownClone = CountdownUI:Clone()
                countdownClone.Parent = playerGui
                countdownLabel = countdownClone:FindFirstChild("CountdownText", true)
            end
            local function getClosestPlayer()
                local closest, closestDist = nil, math.huge
                for _, p in ipairs(playerList) do
                    local target = Players:GetPlayerByUserId(p.UserId)
                    if target and target ~= localPlayer and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(target.Character.HumanoidRootPart.Position)
                        if onScreen then
                            local dist = (Vector2.new(screenPos.X, screenPos.Y) - Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)).Magnitude
                            if dist < closestDist then
                                closest = target
                                closestDist = dist
                            end
                        end
                    end
                end
                return closest
            end
            local t = 20
            local lastTarget = nil
            local conn = RunService.RenderStepped:Connect(function()
                local target = getClosestPlayer()
                if target and target.Character then
                    if highlight.Parent ~= target.Character then
                        highlight.Parent = target.Character
                    end
                    if highlight.Adornee ~= target.Character then
                        highlight.Adornee = target.Character
                    end
                    lastTarget = target
                else
                    highlight.Adornee = nil
                end
            end)
            for i = t, 1, -1 do
                if countdownLabel then
                    countdownLabel.Text = "SELECT A PLAYER : " .. i
                end
                if highlight.Adornee and highlight.Adornee:FindFirstChild("HumanoidRootPart") then
                    -- Optionally show a UI timer
                end
                task.wait(1)
            end
            conn:Disconnect()
            highlight:Destroy()
            if countdownClone then
                countdownClone:Destroy()
            end
            -- Send the selected target to the server
            if lastTarget and client.WinnerChosePlayer then
                client.WinnerChosePlayer.Fire(lastTarget.UserId)
            elseif client.WinnerChosePlayer then
                -- No valid target, fire with 0
                client.WinnerChosePlayer.Fire(0)
            end
        end
    end)

    client.PlayerEliminated.On(function(player, reason)
        if player == Players.LocalPlayer then
            if self.Game and self.Game.force_cleanup_all_games then
                self.Game:force_cleanup_all_games()
            end
        end
    end)

    local Spectate = require(script:FindFirstChild("Spectate") or script.Spectate)
    Spectate.init()

    current_controller = self
    return self :: UIController
end

return ui