-- Spectate Module: Handles spectate UI and camera switching
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Maid = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Maid"))
local client = require(ReplicatedStorage:WaitForChild("network"):WaitForChild("client"))
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Spectate = {}
Spectate.__index = Spectate

local maid = Maid.new()
local spectateUI = nil
local cameraParts = {}
local currentCameraIndex = 1

local function createSpectateUI()
	if spectateUI then spectateUI:Destroy() end
	-- Provided Gui-to-Lua snippet
	local ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Name = "SpectateUI"
	ScreenGui.Enabled = false
	ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	ScreenGui.Parent = localPlayer:WaitForChild("PlayerGui")

	local BackwardsButton = Instance.new("ImageButton")
	BackwardsButton.Name = "BackwardsButton"
	BackwardsButton.Parent = ScreenGui
	BackwardsButton.AnchorPoint = Vector2.new(0.5, 0.5)
	BackwardsButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	BackwardsButton.BackgroundTransparency = 1.000
	BackwardsButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	BackwardsButton.BorderSizePixel = 0
	BackwardsButton.Position = UDim2.new(0.378, 0, 0.883, 0)
	BackwardsButton.Size = UDim2.new(0.043, 0, 0.094, 0)
	BackwardsButton.Image = "rbxassetid://107044600796242"
	BackwardsButton.ImageColor3 = Color3.fromRGB(0, 255, 0)
	BackwardsButton.ScaleType = Enum.ScaleType.Fit

	local PersonName = Instance.new("TextLabel")
	PersonName.Name = "PersonName"
	PersonName.Parent = ScreenGui
	PersonName.AnchorPoint = Vector2.new(0.5, 0.5)
	PersonName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	PersonName.BackgroundTransparency = 1.000
	PersonName.BorderColor3 = Color3.fromRGB(0, 0, 0)
	PersonName.BorderSizePixel = 0
	PersonName.Position = UDim2.new(0.501, 0, 0.882, 0)
	PersonName.Size = UDim2.new(0.196, 0, 0.122, 0)
	PersonName.Font = Enum.Font.Unknown
	PersonName.Text = "SPECTATINGNAMEHERE"
	PersonName.TextColor3 = Color3.fromRGB(0, 255, 0)
	PersonName.TextScaled = true
	PersonName.TextSize = 14.000
	PersonName.TextWrapped = true

	local UITextSizeConstraint = Instance.new("UITextSizeConstraint")
	UITextSizeConstraint.Parent = PersonName
	UITextSizeConstraint.MaxTextSize = 50

	local ForwardsButton = Instance.new("ImageButton")
	ForwardsButton.Name = "ForwardsButton"
	ForwardsButton.Parent = ScreenGui
	ForwardsButton.AnchorPoint = Vector2.new(0.5, 0.5)
	ForwardsButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ForwardsButton.BackgroundTransparency = 1.000
	ForwardsButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ForwardsButton.BorderSizePixel = 0
	ForwardsButton.Position = UDim2.new(0.621, 0, 0.883, 0)
	ForwardsButton.Size = UDim2.new(0.043, 0, 0.094, 0)
	ForwardsButton.Image = "rbxassetid://133742372514080"
	ForwardsButton.ImageColor3 = Color3.fromRGB(0, 255, 0)
	ForwardsButton.ScaleType = Enum.ScaleType.Fit

	spectateUI = ScreenGui
	return ScreenGui, BackwardsButton, ForwardsButton, PersonName
end

local function updateCamera()
	if #cameraParts == 0 then return end
	currentCameraIndex = math.clamp(currentCameraIndex, 1, #cameraParts)
	local camPart = cameraParts[currentCameraIndex]
	if camPart and camPart:IsA("BasePart") then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = camPart.CFrame
	end
end

local function setSpectateUIVisible(visible)
	if spectateUI then
		spectateUI.Enabled = visible
	end
end

local function refreshCameraParts()
	cameraParts = CollectionService:GetTagged("Camera")
	if #cameraParts == 0 then
		cameraParts = {}
	end
end

local function cleanupSpectate()
	setSpectateUIVisible(false)
	maid:DoCleaning()
	if camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function onPlayerDataUpdated(player, data)
	if player ~= localPlayer then return end
	if data.is_spectating then
		refreshCameraParts()
		if #cameraParts == 0 then
			cleanupSpectate()
			return
		end
		currentCameraIndex = 1
		local ui, backBtn, fwdBtn, nameLbl = createSpectateUI()
		setSpectateUIVisible(true)
		maid:GiveTask(function()
			if ui then ui:Destroy() end
		end)
		maid:GiveTask(RunService.RenderStepped:Connect(function()
			updateCamera()
		end))
		maid:GiveTask(backBtn.MouseButton1Click:Connect(function()
			currentCameraIndex = (currentCameraIndex - 2) % #cameraParts + 1
			updateCamera()
			if nameLbl then nameLbl.Text = "CAMERA " .. tostring(currentCameraIndex) end
		end))
		maid:GiveTask(fwdBtn.MouseButton1Click:Connect(function()
			currentCameraIndex = (currentCameraIndex) % #cameraParts + 1
			updateCamera()
			if nameLbl then nameLbl.Text = "CAMERA " .. tostring(currentCameraIndex) end
		end))
		if nameLbl then nameLbl.Text = "CAMERA " .. tostring(currentCameraIndex) end
		updateCamera()
	else
		cleanupSpectate()
	end
end

function Spectate.init()
	maid:DoCleaning()
	client.PlayerDataUpdated.On(onPlayerDataUpdated)
end

return Spectate 