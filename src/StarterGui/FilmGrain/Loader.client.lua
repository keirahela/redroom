local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Ensure a fullscreen ScreenGui that ignores insets
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FilmGrainEffect"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
screenGui.Parent = player:WaitForChild("PlayerGui")

local Textures = {
	268592485,
	268592462,
	268592427,
	268590007,
}

local Frames = {}

for _, textureId in ipairs(Textures) do
	local image = Instance.new("ImageLabel")
	image.Image = "rbxassetid://" .. textureId
	image.BackgroundTransparency = 1
	image.ImageTransparency = 0.58
	image.Visible = false
	image.Size = UDim2.new(1, 0, 1, 0)
	image.Position = UDim2.new(0, 0, 0, 0)
	image.ScaleType = Enum.ScaleType.Crop
	image.ResampleMode = Enum.ResamplerMode.Pixelated
	image.ZIndex = 999999  -- Make sure it's always on top
	image.Parent = screenGui
	table.insert(Frames, image)
end

local FramesToWait = 3

while true do
	local last
	for _, frame in ipairs(Frames) do
		if last then last.Visible = false end
		frame.Visible = true
		last = frame
		for _ = 1, FramesToWait do
			RunService.RenderStepped:Wait()
		end
	end
	if last then last.Visible = false end
end
