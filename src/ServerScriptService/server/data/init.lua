local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local Packages = ReplicatedStorage.Packages

local ProfileService = require(Packages.ProfileService)
local DEFAULT_DATA = require(Modules.Data.DEFAULT_DATA)
local receipt_handler = require(script.receipt_handler)

local ProfileStore = ProfileService.GetProfileStore("PlayerData", DEFAULT_DATA)

local Profiles = {}
receipt_handler.setup(Profiles)

local function player_added(player: Player)
	local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)
	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()
		
		profile:ListenToRelease(function()
			Profiles[player] = nil
			player:Kick("Data failed to load.")
		end)
		
		if player:IsDescendantOf(Players) == true then
			Profiles[player] = profile
            receipt_handler.grant_gamepasses(player)
			print(profile.Data)
		else
			profile:Release()
		end
	else
		player:Kick()
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(player_added, player)
end

Players.PlayerAdded:Connect(player_added)

Players.PlayerRemoving:Connect(function(player)
	local profile = Profiles[player]
	if profile ~= nil then
		profile:Release()
	end
end)

local module = {}

function module.addCoins(player: Player, amount: number): boolean
	local profile = Profiles[player]
	if profile == nil then
		return false
	else
		profile.Data.Coins += amount
		return true
	end
end

function module.takeLives(player: Player, amount: number): typeof(DEFAULT_DATA)?
	local profile = Profiles[player]
	if profile == nil then
		return nil
	else
		profile.Data.Lives = math.clamp(profile.Data.Lives - amount, 0, 3)
		return profile.Data
	end
end

function module.addLives(player: Player, amount: number): typeof(DEFAULT_DATA)?
	local profile = Profiles[player]
	if profile == nil then
		return nil
	else
		profile.Data.Lives = math.clamp(profile.Data.Lives + amount, 0, 3)
		return profile.Data
	end
end

return module