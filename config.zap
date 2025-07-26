opt server_output = "./src/ReplicatedStorage/network/server.lua"
opt client_output = "./src/ReplicatedStorage/network/client.lua"

-- Enums for game states and UI management
type GameState = enum { "WAITING", "STARTING", "IN_PROGRESS", "FINISHED", "ENDING" }
type MinigameType = enum { "Maze", "HigherLower", "Blackjack", "RatRace", "React", "BombGuesser", "DragTheLine" }
type UIType = enum { "MainMenu", "Shop", "Settings", "CrateOpening", "Spectator", "Game", "Lobby" }
type NotificationType = enum { "Info", "Warning", "Success", "Error" }

-- Structs for complex data
type PlayerData = struct {
    is_alive: boolean,
    is_spectating: boolean
}

type CountdownData = struct {
    duration: u8(1..60),
    title: string.utf8(1..50),
    description: string.utf8(0..100)
}

type MinigameData = struct {
    type: MinigameType,
    duration: u8(1..120),
    instructions: string.utf8(1..500),
    parameters: unknown
}

type NotificationData = struct {
    type: NotificationType,
    title: string.utf8(1..50),
    message: string.utf8(1..200),
    duration: u8(1..30)
}

type CrateReward = struct {
    name: string.utf8(1..50),
    rarity: string.utf8(1..20),
    value: u32
}

-- ===== GAME STATE EVENTS =====

-- Server -> Client: Game state changes
event GameStateChanged = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (state: GameState, player_count: u8)
}

-- Server -> Client: Round starting with countdown
event RoundStarting = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: CountdownData
}

event CancelAllAnimations = {
    from: Server,
    type: Reliable,
    call: ManyAsync
}

-- Server -> Client: Round ended with results
event RoundEnded = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (winner_count: u8, coins_awarded: u32)
}

-- ===== MINIGAME EVENTS =====

-- Server -> Client: Start specific minigame
event MinigameStarted = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: MinigameData
}

-- Client -> Server: Player input for minigame
event MinigameInput = {
    from: Client,
    type: Reliable,
    call: SingleAsync,
    data: (input_type: string.utf8(1..20), input_data: struct { zone: string.utf8(3..10) }?)
}

-- Server -> Client: Minigame timer update
event MinigameTimer = {
    from: Server,
    type: Unreliable,
    call: ManyAsync,
    data: u8
}

-- Server -> Client: Player eliminated from minigame
event PlayerEliminated = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (player: Instance.Player, reason: string.utf8(1..50))
}

-- Client -> Server: Winner sends chosen player for elimination
event WinnerChosePlayer = {
    from: Client,
    type: Reliable,
    call: SingleAsync,
    data: (chosenUserId: u32)
}

-- ===== UI MANAGEMENT EVENTS =====

-- Server -> Client: Show specific UI
event ShowUI = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (ui_type: UIType, data: unknown)
}

-- Server -> Client: Hide specific UI
event HideUI = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: UIType
}

-- Client -> Server: UI interaction
event UIInteraction = {
    from: Client,
    type: Reliable,
    call: SingleAsync,
    data: (ui_type: UIType, action: string.utf8(1..30), data: unknown)
}

-- Server -> Client: Update UI element
event UpdateUI = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (ui_type: UIType, element: string.utf8(1..30), value: unknown)
}

-- ===== PLAYER DATA EVENTS =====

-- Server -> Client: Player data updated
event PlayerDataUpdated = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (player: Instance.Player, data: PlayerData)
}

-- Server -> Client: Coins awarded to player
event CoinsAwarded = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (player: Instance.Player, amount: u32, reason: string.utf8(1..50))
}

-- ===== NOTIFICATION SYSTEM =====

-- Server -> Client: Show notification
event ShowNotification = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: NotificationData
}

-- Server -> Client: Show popup message
event ShowPopup = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (title: string.utf8(1..50), message: string.utf8(1..200), buttons: string.utf8[])
}

-- Client -> Server: Popup response
event PopupResponse = {
    from: Client,
    type: Reliable,
    call: SingleAsync,
    data: (popup_id: string.utf8(1..20), button_index: u8(0..2))
}

-- ===== SPECTATING SYSTEM =====

-- Client -> Server: Request to spectate player
event SpectateRequest = {
    from: Client,
    type: Reliable,
    call: SingleAsync,
    data: Instance.Player?
}

-- Server -> Client: Spectating target changed
event SpectateChanged = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (spectator: Instance.Player, target: Instance.Player?)
}

-- ===== SHOP & ECONOMY =====

-- Client -> Server: Purchase crate
event PurchaseCrate = {
    from: Client,
    type: Reliable,
    call: SingleAsync,
    data: string.utf8(1..20)  -- crate type
}

-- Server -> Client: Crate opening result
event CrateOpened = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (player: Instance.Player, reward: CrateReward)
}

-- Client -> Server: Settings changed
event SettingsChanged = {
    from: Client,
    type: Reliable,
    call: SingleAsync,
    data: (setting_name: string.utf8(1..30), value: unknown)
}

-- ===== EFFECTS & VISUALS =====

-- Server -> Client: Trigger visual effect
event TriggerEffect = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (effect_name: string.utf8(1..30), target: Instance?, data: unknown)
}

-- Server -> Client: Screen transition
event ScreenTransition = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (transition_type: string.utf8(1..20), duration: u8(1..10))
}

-- Server -> Client: Waking up effect
event WakeUpTransition = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (phase: string.utf8(1..10), duration: u8(1..5))
}

-- Server -> Client: Play seat animation when player is pivoted
event PlaySeatAnimation = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (animationId: string.utf8(10..20))
}

-- Server -> Client: Teleport character to a specific CFrame
event TeleportCharacter = {
    from: Server,
    type: Reliable,
    call: ManyAsync,
    data: (cframe: CFrame)
}