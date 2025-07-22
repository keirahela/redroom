local server = require(game:GetService("ReplicatedStorage"):WaitForChild("network"):WaitForChild("server"))
local minigame_signal = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("minigame_signal"))
local maze = {}
maze.__index = maze

-- Fire MazeLayout event to all players in the match
local function sendMazeLayout(match, layout)
	for _, pdata in ipairs(match:get_alive_players()) do
		local player = pdata.player
		server.UpdateUI.Fire(player, "Game", "MazeLayout", layout)
	end
end

local starttime = nil
local zap_connection = nil
-- local matchservice = require(game:GetService("ServerScriptService"):WaitForChild("server"):WaitForChild("matchservice"))
local finished_players = {}
local current_match = nil

function maze.start(match)
	finished_players = {}
	current_match = match
	local eliminated_players = {}
	starttime = tick()

	-- Generate and send maze layout

	zap_connection = server.MinigameInput.SetCallback(function(player: Player, input_type: string, data: unknown)
		if input_type == "ended" then
			if finished_players[player] or eliminated_players[player] then
				-- Already finished or eliminated, ignore
				return
			end
			finished_players[player] = true
			if not current_match then
				warn("No match object found for Maze minigame!")
				return
			end
			local alive_players = current_match:get_alive_players()
			local all_done = true
			for _, pdata in ipairs(alive_players) do
				if not finished_players[pdata.player] then
					all_done = false
					break
				end
			end
			if all_done then
				minigame_signal:Fire()
			end
		elseif input_type == "eliminated" then
			if eliminated_players[player] or finished_players[player] then
				-- Already eliminated or finished, ignore
				return
			end
			eliminated_players[player] = true
			if current_match then
				current_match:eliminate_player(player)
			else
				warn("No match object found for Maze minigame (elimination)!")
			end
		elseif input_type == "maze_zone" and type(data) == "table" then
			local zoneData = (data :: {zone: string})
			if not zoneData.zone then return end
			if finished_players[player] or eliminated_players[player] then
				return
			end
			if zoneData.zone == "End" then
				finished_players[player] = true
				if not current_match then
					warn("No match object found for Maze minigame!")
					return
				end
				local alive_players = current_match:get_alive_players()
				local all_done = true
				for _, pdata in ipairs(alive_players) do
					if not finished_players[pdata.player] then
						all_done = false
						break
					end
				end
				if all_done then
					minigame_signal:Fire()
				end
			elseif zoneData.zone == "Danger" then
				eliminated_players[player] = true
				if current_match then
					current_match:eliminate_player(player)
				else
					warn("No match object found for Maze minigame (elimination)!")
				end
			end
		end
	end)
end

function maze.stop()
	if zap_connection then
		zap_connection()
	end
end

return maze
