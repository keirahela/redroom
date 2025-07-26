local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))

local PRODUCT_IDS = {
    crate = 2319312761,
    coins5k = 3333567516,
    coins10k = 3333569363,
}
local GAMEPASS_IDS = {
    vip = 1317219848,
    sfx = 1341775757,
}

local shop_controller = {}
local hydrated_shop_ui = nil
local setup_done = false
local fusion_scope = Fusion:scoped()

local function on_product_button_clicked(product_key)
    local product_id = PRODUCT_IDS[product_key]
    if product_id then
        MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product_id)
    end
end

local function on_gamepass_button_clicked(gamepass_key)
    local gamepass_id = GAMEPASS_IDS[gamepass_key]
    if gamepass_id then
        MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, gamepass_id)
    end
end

function shop_controller.show_shop_ui()
    local player = Players.LocalPlayer
    local player_gui = player:WaitForChild("PlayerGui")
    if hydrated_shop_ui and hydrated_shop_ui.Parent then
        hydrated_shop_ui.Enabled = true
        return hydrated_shop_ui
    end
    local main_ui = ReplicatedStorage.UI:WaitForChild("MainUI"):Clone()
    hydrated_shop_ui = fusion_scope:Hydrate(main_ui) {
        Parent = player_gui,
    }
    hydrated_shop_ui.Enabled = true
    shop_controller.setup_shop_ui(hydrated_shop_ui)
    return hydrated_shop_ui
end

function shop_controller.setup_shop_ui(main_ui)
    if setup_done then return end
    main_ui.StoreFrame.StoreFrontFrame.CrateFrame.CrateButton.MouseButton1Click:Connect(function()
        on_product_button_clicked("crate")
    end)
    main_ui.StoreFrame.StoreFrontFrame.VIPFrame.VIPButton.MouseButton1Click:Connect(function()
        on_gamepass_button_clicked("vip")
    end)
    main_ui.StoreFrame.StoreFrontFrame.CoinFrame.CoinButton.MouseButton1Click:Connect(function()
        on_product_button_clicked("coins5k")
    end)
    main_ui.StoreFrame.StoreFrontFrame.CoinFrame2.CoinButton2.MouseButton1Click:Connect(function()
        on_product_button_clicked("coins10k")
    end)
    main_ui.StoreFrame.StoreFrontFrame.SFXFrame.SFXButton.MouseButton1Click:Connect(function()
        on_gamepass_button_clicked("sfx")
    end)
    main_ui.StoreFrame.XButton.MouseButton1Click:Connect(function()
        main_ui.Enabled = false
    end)
    setup_done = true
end

return shop_controller