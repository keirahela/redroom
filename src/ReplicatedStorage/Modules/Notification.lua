-- Notification module usable from both server and client
local Notification = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local function showToPlayer(player, message)
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return end
    local NotificationUI = ReplicatedStorage:FindFirstChild("UI") and ReplicatedStorage.UI:FindFirstChild("NotificationUI")
    if not NotificationUI then return end
    local existing = playerGui:FindFirstChild("NotificationUI")
    if existing then existing:Destroy() end
    local notif = NotificationUI:Clone()
    notif.Parent = playerGui
    notif.Enabled = true
    local label = notif:FindFirstChildWhichIsA("TextLabel", true)
    if label then label.Text = message end
    return notif
end

if RunService:IsServer() then
    function Notification.ShowAll(message)
        for _, player in ipairs(Players:GetPlayers()) do
            showToPlayer(player, message)
        end
    end
    function Notification.ShowPlayer(player, message)
        showToPlayer(player, message)
    end
    function Notification.CloseAll()
        for _, player in ipairs(Players:GetPlayers()) do
            local playerGui = player:FindFirstChild("PlayerGui")
            if playerGui then
                local existing = playerGui:FindFirstChild("NotificationUI")
                if existing then existing:Destroy() end
            end
        end
    end
    function Notification.ClosePlayer(player)
        local playerGui = player:FindFirstChild("PlayerGui")
        if playerGui then
            local existing = playerGui:FindFirstChild("NotificationUI")
            if existing then existing:Destroy() end
        end
    end
else
    function Notification.Show(message)
        local player = Players.LocalPlayer
        showToPlayer(player, message)
    end
    function Notification.Close()
        local player = Players.LocalPlayer
        local playerGui = player:FindFirstChild("PlayerGui")
        if playerGui then
            local existing = playerGui:FindFirstChild("NotificationUI")
            if existing then existing:Destroy() end
        end
    end
end

return Notification 