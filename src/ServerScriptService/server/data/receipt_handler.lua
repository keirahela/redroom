local marketplace = game:GetService("MarketplaceService")
local players = game:GetService("Players")

local shop_receipt = {}

local profiles = nil

local product_ids = {
    [2319312761] = function(profile) profile.Data.Crates = (profile.Data.Crates or 0) + 1 end,
    [3333567516] = function(profile) profile.Data.Coins = (profile.Data.Coins or 0) + 5000 end,
    [3333569363] = function(profile) profile.Data.Coins = (profile.Data.Coins or 0) + 10000 end,
}
local gamepass_ids = {
    [1317219848] = function(profile) profile.Data.HasVIP = true end,
    [1341775757] = function(profile) profile.Data.HasSFX = true end,
}

local function grant_product(player, product_id)
    local profile = profiles[player]
    local fn = product_ids[product_id]
    if profile and fn then
        print("[shop_receipt] granted dev product", product_id, "to", player.Name)
        fn(profile)
    end
end

local function grant_gamepass(player, gamepass_id)
    local profile = profiles[player]
    local fn = gamepass_ids[gamepass_id]
    if profile and fn then
        print("[shop_receipt] granted gamepass", gamepass_id, "to", player.Name)
        fn(profile)
    end
end

function shop_receipt.grant_gamepasses(player)
    local profile = profiles[player]
    if not profile then return end
    for id, fn in pairs(gamepass_ids) do
        local ok, has = pcall(function()
            return marketplace:UserOwnsGamePassAsync(player.UserId, id)
        end)
        if ok and has then fn(profile) end
    end
end

-- Listen for in-game gamepass purchases on the server
marketplace.PromptGamePassPurchaseFinished:Connect(function(player, gamepass_id, was_purchased)
    if was_purchased and gamepass_ids[gamepass_id] then
        print("[shop_receipt] PromptGamePassPurchaseFinished: granting gamepass", gamepass_id, "to", player.Name)
        grant_gamepass(player, gamepass_id)
    end
end)

local function purchase_id_check_async(profile, purchase_id, grant_fn)
    if not profile:IsActive() then return Enum.ProductPurchaseDecision.NotProcessedYet end
    local meta = profile.MetaData
    local ids = meta.MetaTags.ProfilePurchaseIds
    if not ids then
        ids = {}
        meta.MetaTags.ProfilePurchaseIds = ids
    end
    if not table.find(ids, purchase_id) then
        while #ids >= 50 do table.remove(ids, 1) end
        table.insert(ids, purchase_id)
        task.spawn(grant_fn)
    end
    local result
    local function check()
        local saved = meta.MetaTagsLatest.ProfilePurchaseIds
        if saved and table.find(saved, purchase_id) then
            result = Enum.ProductPurchaseDecision.PurchaseGranted
        end
    end
    check()
    local conn = profile.MetaTagsUpdated:Connect(function()
        check()
        if not profile:IsActive() and not result then
            result = Enum.ProductPurchaseDecision.NotProcessedYet
        end
    end)
    while not result do task.wait() end
    conn:Disconnect()
    return result
end

local function process_receipt(receipt)
    local player = players:GetPlayerByUserId(receipt.PlayerId)
    if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
    local profile = profiles[player]
    if profile then
        if product_ids[receipt.ProductId] then
            return purchase_id_check_async(profile, receipt.PurchaseId, function()
                grant_product(player, receipt.ProductId)
            end)
        end
        return Enum.ProductPurchaseDecision.PurchaseGranted
    else
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end

function shop_receipt.setup(profiles_table)
    profiles = profiles_table
    marketplace.ProcessReceipt = process_receipt
end

return shop_receipt

--[[
usage (in your data module):
local shop_receipt = require(path.to.ShopReceiptHandler)
shop_receipt.setup(profiles)
-- after you set profiles[player] = profile:
shop_receipt.grant_gamepasses(player)
-- gamepasses are also granted instantly after in-game purchase
]] 