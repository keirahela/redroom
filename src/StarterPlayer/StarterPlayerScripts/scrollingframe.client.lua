local CollectionService = game:GetService("CollectionService")

local function registerDynamicScrollingFrame(frame)
	local layout = frame:FindFirstChildWhichIsA("UIGridStyleLayout")
	local absoluteContentSize = layout.AbsoluteContentSize
	frame.CanvasSize = UDim2.new(0, 0, 0, absoluteContentSize.Y)
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		local absoluteContentSize = layout.AbsoluteContentSize
		frame.CanvasSize = UDim2.new(0, 0, 0, absoluteContentSize.Y)
	end)
end


CollectionService:GetInstanceAddedSignal("DynamicScrollingFrame"):Connect(registerDynamicScrollingFrame)
for _, frame in ipairs(CollectionService:GetTagged("DynamicScrollingFrame")) do
	registerDynamicScrollingFrame(frame)
end