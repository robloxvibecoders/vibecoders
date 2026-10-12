if not game:IsLoaded() then game.Loaded:Wait() end

local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local StarterGui       = game:GetService("StarterGui")
local Workspace        = game:GetService("Workspace")

local isMobile = (
    typeof(UserInputService.TouchEnabled) == "boolean"
    and UserInputService.TouchEnabled
    and not UserInputService.KeyboardEnabled
)

local hasHookMeta    = hookmetamethod ~= nil
local hasCheckcaller = checkcaller    ~= nil
local hasGethui      = gethui         ~= nil
local hasGetreg      = getreg         ~= nil

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid  = character:WaitForChild("Humanoid")
local rootPart  = character:WaitForChild("HumanoidRootPart")
local Camera    = Workspace.CurrentCamera

local State = {
    InfAmmo    = false,
    InfDamage  = false,
    Speed      = false,
    Noclip     = false,
    RainbowGun = false,
    FOVEnabled = false,
    FOVValue   = 70,
    MenuOpen   = false,
}

local Config = {
    Transparency = 0.4,
    Reflectance  = 0.2,
    Material     = Enum.Material.Glass,
}

local originalFOV      = Camera.FieldOfView
local _ammoRunning     = true
local originalPartData = {}
local modelPartCache   = {}
local modelCacheConns  = {}

local function getRGBColor()
    return Color3.fromHSV(tick() % 5 / 5, 1, 1)
end

local function evictModelCache(model)
    if modelCacheConns[model] then
        for _, c in ipairs(modelCacheConns[model]) do
            pcall(function() c:Disconnect() end)
        end
        modelCacheConns[model] = nil
    end
    modelPartCache[model] = nil
end

local function getModelParts(model)
    if modelPartCache[model] then
        return modelPartCache[model]
    end

    local parts = {}
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            parts[#parts + 1] = desc
        end
    end
    modelPartCache[model] = parts

    local c1 = model.DescendantAdded:Connect(function() evictModelCache(model) end)
    local c2 = model.DescendantRemoving:Connect(function() evictModelCache(model) end)
    local c3 = model.AncestryChanged:Connect(function()
        if not model.Parent then evictModelCache(model) end
    end)
    modelCacheConns[model] = { c1, c2, c3 }

    return parts
end

local function applyEffectToPart(part, color)
    if not part or not part.Parent then return end
    pcall(function()
        if not originalPartData[part] then
            originalPartData[part] = {
                Material     = part.Material,
                Transparency = part.Transparency,
                Reflectance  = part.Reflectance,
                Color        = part.Color,
            }
        end
        part.Material     = Config.Material
        part.Transparency = Config.Transparency
        part.Reflectance  = Config.Reflectance
        part.Color        = color
        for _, child in ipairs(part:GetChildren()) do
            if child:IsA("Decal") or child:IsA("Texture") then
                child.Transparency = Config.Transparency
            end
        end
    end)
end

local function restoreAllParts()
    for part, orig in pairs(originalPartData) do
        pcall(function()
            if part and part.Parent then
                part.Material     = orig.Material
                part.Transparency = orig.Transparency
                part.Reflectance  = orig.Reflectance
                part.Color        = orig.Color
                for _, child in ipairs(part:GetChildren()) do
                    if child:IsA("Decal") or child:IsA("Texture") then
                        child.Transparency = 0
                    end
                end
            end
        end)
    end
    table.clear(originalPartData)
end

RunService.RenderStepped:Connect(function()
    if not State.RainbowGun then return end
    local frameColor   = getRGBColor()
    local ignoreFolder = Workspace:FindFirstChild("Ignore")
    if not ignoreFolder then return end
    local playerFolder = ignoreFolder:FindFirstChild("PlayerFolder")
    if not playerFolder then return end
    for _, child in ipairs(playerFolder:GetChildren()) do
        local wn = child:GetAttribute("WeaponName")
        if child:IsA("Model") and wn ~= nil and wn ~= "Knife" then
            for _, part in ipairs(getModelParts(child)) do
                applyEffectToPart(part, frameColor)
            end
        end
    end
end)

RunService.RenderStepped:Connect(function()
    if State.MenuOpen and not isMobile then
        pcall(function()
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end)
    end
    if State.FOVEnabled then
        pcall(function()
            Camera.FieldOfView = State.FOVValue
        end)
    end
end)

if hasHookMeta and hasCheckcaller then
    local origNewIndex
    origNewIndex = hookmetamethod(game, "__newindex", newcclosure(function(self, key, value)
        if not checkcaller() and self == Camera and key == "FieldOfView" and State.FOVEnabled then
            return origNewIndex(self, key, State.FOVValue)
        end
        return origNewIndex(self, key, value)
    end))
end

RunService.RenderStepped:Connect(function()
    if State.Speed and character and humanoid then
        character:TranslateBy(humanoid.MoveDirection * 0.45)
    end
    if State.Noclip and character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end
end)

if hasHookMeta then
    local OldNamecall
    OldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args   = { ... }
        if not checkcaller() then
            if method == "FireServer"
                and self.Name == "Damage"
                and State.InfDamage
                and type(args[1]) == "table" then
                args[1]["Damage"] = 999999
                return OldNamecall(self, unpack(args))
            end
        end
        return OldNamecall(self, ...)
    end))
end

task.spawn(function()
    while _ammoRunning and task.wait(0.5) do
        if not State.InfAmmo then continue end
        if hasGetreg then
            pcall(function()
                for _, v in next, getreg() do
                    if type(v) == "table" then
                        pcall(function()
                            if rawget(v, "Ammo") ~= nil then
                                rawset(v, "Ammo", 99)
                            end
                        end)
                    end
                end
            end)
        else
            pcall(function()
                for _, v in ipairs(Workspace:GetDescendants()) do
                    if (v:IsA("IntValue") or v:IsA("NumberValue")) and v.Name:lower():find("ammo") then
                        v.Value = 99
                    end
                end
            end)
        end
    end
end)

player.CharacterAdded:Connect(function(char)
    table.clear(originalPartData)
    for model in pairs(modelPartCache) do
        evictModelCache(model)
    end
    character = char
    humanoid  = char:WaitForChild("Humanoid")
    rootPart  = char:WaitForChild("HumanoidRootPart")
    if not State.Speed then
        humanoid.WalkSpeed = 16
    end
end)

local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

pcall(function()
    if hasGethui then
        task.delay(0.5, function()
            local gui = player.PlayerGui:FindFirstChild("WindUI")
                     or player.PlayerGui:FindFirstChild("Wind")
            if gui then
                gui.Parent = gethui()
            end
        end)
    end
end)

local windowConfig = {
    Title       = "subscribe to @robloxvibecoder",
    Icon        = "zap",
    Author      = "by @robloxvibecoder",
    Folder      = "LazarusHub",
    Transparent = true,
    Theme       = "Dark",
}

if isMobile then
    windowConfig.Size      = UDim2.fromOffset(480, 520)
    windowConfig.MinSize   = Vector2.new(340, 380)
    windowConfig.Resizable = true
else
    windowConfig.Size      = UDim2.fromOffset(580, 460)
    windowConfig.ToggleKey = Enum.KeyCode.K
end

local Window = WindUI:CreateWindow(windowConfig)

if not isMobile then
    UserInputService.InputBegan:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.RightShift then
            State.MenuOpen = not State.MenuOpen
        end
    end)
end

if isMobile then
    State.MenuOpen = true
end

task.spawn(function()
    task.wait(0.1)
    local guiParent = hasGethui and gethui() or player.PlayerGui
    for _, gui in ipairs(guiParent:GetChildren()) do
        if gui:IsA("ScreenGui") and (gui.Name:find("Wind") or gui.Name:find("wind")) then
            gui.DisplayOrder   = 9999
            gui.IgnoreGuiInset = true
            break
        end
    end
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, true)
    end)
end)

local MainTab = Window:Tab({ Title = "Main", Icon = "home" })
task.defer(function() MainTab:Select() end)

MainTab:Toggle({
    Title    = "Infinite Ammo",
    Desc     = "shoot forever lmao",
    Icon     = "package",
    Value    = false,
    Callback = function(state) State.InfAmmo = state end,
})

MainTab:Toggle({
    Title    = "Infinite Damage",
    Desc     = "kills zombies in 1 bullet",
    Icon     = "sword",
    Value    = false,
    Callback = function(state) State.InfDamage = state end,
})

local MiscTab = Window:Tab({ Title = "Misc", Icon = "settings" })

MiscTab:Toggle({
    Title    = "Speed",
    Desc     = "run really fast",
    Icon     = "wind",
    Value    = false,
    Callback = function(state) State.Speed = state end,
})

MiscTab:Toggle({
    Title    = "Noclip",
    Desc     = "walk through walls",
    Icon     = "ghost",
    Value    = false,
    Callback = function(state) State.Noclip = state end,
})

MiscTab:Divider()

MiscTab:Toggle({
    Title    = "Rainbow Gun",
    Desc     = "yea rainbow guns wtv",
    Icon     = "sparkles",
    Value    = false,
    Callback = function(state)
        State.RainbowGun = state
        if not state then restoreAllParts() end
    end,
})

MiscTab:Divider()

MiscTab:Toggle({
    Title    = "FOV Changer",
    Desc     = "field of view changer duhhh",
    Icon     = "eye",
    Value    = false,
    Callback = function(state)
        State.FOVEnabled = state
        if not state then
            pcall(function() Camera.FieldOfView = originalFOV end)
        else
            pcall(function() Camera.FieldOfView = State.FOVValue end)
        end
    end,
})

MiscTab:Slider({
    Title    = "FOV Value",
    Desc     = "Your custom field of view.",
    Icon     = "move",
    Value    = { Min = 1, Max = 120, Default = 70 },
    Callback = function(value)
        State.FOVValue = value
        if State.FOVEnabled then
            pcall(function() Camera.FieldOfView = value end)
        end
    end,
})

local SettingsTab = Window:Tab({ Title = "Settings", Icon = "settings-2" })

SettingsTab:Keybind({
    Title    = "Menu Keybind",
    Desc     = "Current keybind: K",
    Icon     = "keyboard",
    Value    = "K",
    Callback = function(v)
        pcall(function()
            Window:SetToggleKey(Enum.KeyCode[v])
        end)
    end,
})

SettingsTab:Divider()

SettingsTab:Button({
    Title    = "Unload Script",
    Desc     = "Stops all scripts and destroys the UI.",
    Icon     = "power",
    Callback = function()
        _ammoRunning = false

        for k in pairs(State) do
            if type(State[k]) == "boolean" then
                State[k] = false
            end
        end

        restoreAllParts()

        for model in pairs(modelPartCache) do
            evictModelCache(model)
        end

        pcall(function() Camera.FieldOfView = originalFOV end)
        pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
        pcall(function() UserInputService.MouseIconEnabled = true end)
        pcall(function() game:GetService("GuiService"):SetMenuOpen(false) end)
        pcall(function() Window:Destroy() end)
    end,
})