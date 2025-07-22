local react = {}
react.__index = react
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))

function react.start()
	-- TODO: Call this when the minigame actually ends
	-- minigame_signal:Fire()
end

function react.stop()
	
end

return react
