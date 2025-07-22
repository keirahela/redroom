local ratrace = {}
ratrace.__index = ratrace
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))

function ratrace.start()
	-- TODO: Call this when the minigame actually ends
	-- minigame_signal:Fire()
end

function ratrace.stop()
	
end

return ratrace
