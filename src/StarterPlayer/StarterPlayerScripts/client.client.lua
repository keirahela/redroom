local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIController = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIController"))

for _,v: ModuleScript in ReplicatedStorage.Modules:GetChildren() do
	if v:IsA("ModuleScript") then
		pcall(require, v)
	end
end

UIController.new()

local success = false
while not success do
	success = pcall(function()
		game:GetService("StarterGui"):SetCore("ResetButtonCallback", false)
	end)
	if not success then
		task.wait()
	end
end