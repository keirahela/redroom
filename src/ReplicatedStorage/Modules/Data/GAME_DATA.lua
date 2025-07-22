local difficulties = {
	{
		-- Easy - single danger zone in middle
		dangers = {
			{position = UDim2.new(0.5, 0, 0, 0), size = UDim2.new(0.15, 0, 0.7, 0)}
		}
	},
	{
		-- Medium - two danger zones
		dangers = {
			{position = UDim2.new(0.3, 0, 0, 0), size = UDim2.new(0.15, 0, 0.5, 0)},
			{position = UDim2.new(0.6, 0, 0.3, 0), size = UDim2.new(0.15, 0, 0.7, 0)}
		}
	},
	{
		-- Hard - three danger zones forming a maze
		dangers = {
			{position = UDim2.new(0.25, 0, 0, 0), size = UDim2.new(0.1, 0, 0.6, 0)},
			{position = UDim2.new(0.5, 0, 0.2, 0), size = UDim2.new(0.1, 0, 1, 0)},
			{position = UDim2.new(0.65, 0, 0, 0), size = UDim2.new(0.1, 0, 0.5, 0)}
		}
	}
}

return {
	maze_difficulties = difficulties
}