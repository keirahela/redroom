-- SoundManager: Handles playing sound effects and music
local SoundService = game:GetService("SoundService")

local SoundManager = {}

-- Plays a sound effect by name from the SoundEffects folder
function SoundManager:PlaySFX(name)
    local sfxFolder = SoundService:FindFirstChild("SoundEffects")
    if not sfxFolder then return end
    local sound = sfxFolder:FindFirstChild(name)
    if sound then
        sound:Stop()
        sound:Play()
    end
end

-- Plays music by name from the music folder (loops by default)
function SoundManager:PlayMusic(name)
    local musicFolder = SoundService:FindFirstChild("music")
    if not musicFolder then return end
    local music = musicFolder:FindFirstChild(name)
    if music then
        music.Looped = true
        music:Play()
    end
end

-- Stops music by name from the music folder
function SoundManager:StopMusic(name)
    local musicFolder = SoundService:FindFirstChild("music")
    if not musicFolder then return end
    local music = musicFolder:FindFirstChild(name)
    if music then
        music:Stop()
    end
end

return SoundManager 