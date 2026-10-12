if not game:IsLoaded() then game.Loaded:Wait() end
if getgenv and getgenv().StoneSkippingUnload then pcall(getgenv().StoneSkippingUnload) end

local okLib, UILib = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
if not okLib or not UILib then return end

local Players         = game:GetService("Players")
local RS              = game:GetService("ReplicatedStorage")
local RunService      = game:GetService("RunService")
local UIS             = game:GetService("UserInputService")
local Lighting        = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local VirtualUser     = game:GetService("VirtualUser")
local Workspace       = game:GetService("Workspace")
local LocalPlayer     = Players.LocalPlayer

local VERSION = "v1"
local AUTO_KEY = "__auto"
local AUTO_LABEL = "Best Unlocked (Auto)"

local Setup = {
    ThrowDelay   = 0.6,
    TrainDelay   = 2,
    RebirthDelay = 2,
    BuyDelay     = 2,
    EquipDelay   = 20,
    HatchDelay   = 1.5,
    MoveSpeed    = 70,
    World1Launch = Vector3.new(0.5, 7, -5.5),
}

local Cfg = {
    AutoThrow = false, AutoTrain = false, AutoRebirth = false, AutoBuy = false,
    AutoHatch = false, AutoEquip = false, AutoFreeReward = false,
    ZoneName = AUTO_KEY, EggId = "", HatchCount = 1, Code = "",
    WalkSpeedOn = false, WalkSpeed = 50, Fly = false, FlySpeed = 60,
    NoClip = false, InfJump = false, InstantPP = false,
    AntiAfk = true, FpsBoost = false, Disable3D = false, AutoReconnect = false,
}
local S = {}
local Alive = true
local Net = {}
local links = {}
local Gen = {}
local function keep(c) table.insert(links, c) return c end

local function toast(t, d)
    pcall(function() UILib:Notify({Title = "+1 Stone Skipping", Content = t, Duration = d or 3}) end)
end
local lastToast = 0
local function softToast(t)
    if os.clock() - lastToast > 3 then
        lastToast = os.clock()
        toast(t)
    end
end

local function relay(action, payload)
    local r = Net.Request
    if not r then return false end
    return pcall(function() r:FireServer(action, payload) end)
end

local STATE_KEYS = {"Level", "NextRebirthLevel", "Rebirths", "Activity"}

local function onServerEvent(name, p)
    if name == "State" and type(p) == "table" then
        for _, k in ipairs(STATE_KEYS) do
            if p[k] ~= nil then S[k] = p[k] end
        end
    elseif name == "ThrowRejected" and type(p) == "table" and p.Message then
        softToast("Throw rejected: " .. tostring(p.Message))
    elseif name == "CodeResult" then
        local msg = type(p) == "table" and p.Message or (type(p) == "string" and p) or nil
        if msg then toast("Code: " .. tostring(msg), 4) end
    elseif name == "HatchResult" and type(p) == "table" and p.Success == false
        and p.Message and p.Message ~= "" then
        softToast("Hatch: " .. tostring(p.Message))
    end
end

task.spawn(function()
    local root = RS:WaitForChild("SkippingNetwork", 15)
    if not root then return end
    Net.Request = root:WaitForChild("Request", 10)
    Net.Event   = root:WaitForChild("Event", 10)
    if Net.Event then keep(Net.Event.OnClientEvent:Connect(onServerEvent)) end
    relay("Sync")
end)

local reqCache = {}
local GameReady = false
local function util(name)
    if not GameReady then return nil end
    if reqCache[name] ~= nil then return reqCache[name] or nil end
    local result, done = nil, false
    task.spawn(function()
        local ok, mod = pcall(function()
            local shared = RS:WaitForChild("Shared", 5)
            return require(shared.Util[name])
        end)
        result = ok and mod or nil
        done = true
    end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < 6 do task.wait() end
    reqCache[name] = result or false
    return result
end

local function worldConfig()
    local WM = util("WorldMap")
    if not WM then return nil end
    local ok, cfg = pcall(WM.GetConfig, LocalPlayer)
    return ok and cfg or nil
end

local function worldModel()
    local WM = util("WorldMap")
    if not WM then return nil end
    local ok, m = pcall(WM.GetModel, LocalPlayer)
    return ok and m or nil
end

local function currentWorld()
    local m = worldModel()
    if m then return m end
    local folder = Workspace:FindFirstChild("SkippingWorlds")
    if folder then
        for _, c in ipairs(folder:GetChildren()) do
            if c:FindFirstChild("TrainingZones") then return c end
        end
    end
    return nil
end

local function inLaunchZone()
    local LZ, c = util("LaunchZone"), LocalPlayer.Character
    if not (LZ and c) then return nil end
    local ok, r = pcall(LZ.Contains, c)
    if ok then return r end
    return nil
end

local function getChar() return LocalPlayer.Character end
local function getHum()  local c = getChar() return c and c:FindFirstChildOfClass("Humanoid") end
local function getRoot() local c = getChar() return c and c:FindFirstChild("HumanoidRootPart") end

local function myRebirths()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local r = ls and ls:FindFirstChild("Rebirths")
    local v = r and tonumber(r.Value)
    return v or tonumber(S.Rebirths) or 0
end

local function glideTo(pos, speed, stop, exact)
    speed = speed or Setup.MoveSpeed
    local t0 = os.clock()
    while Alive do
        local root = getRoot()
        if not root then return false end
        if stop and stop() then return false end
        local delta = pos - root.Position
        local dist = delta.Magnitude
        if dist < 0.5 then break end
        local dt = RunService.Heartbeat:Wait()
        local step = math.min(dist, speed * dt)
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = root.CFrame + delta.Unit * step
        if os.clock() - t0 > 30 then break end
    end
    local root = getRoot()
    if root and Alive and not (stop and stop()) then
        if exact then
            root.AssemblyLinearVelocity = Vector3.zero
            root.CFrame = CFrame.new(pos) * (root.CFrame - root.CFrame.Position)
        else
            local hum = getHum()
            if hum then hum:MoveTo(pos) end
        end
    end
    return true
end

local function cycle(flag, delay, fn)
    Gen[flag] = (Gen[flag] or 0) + 1
    local my = Gen[flag]
    task.spawn(function()
        while Alive and Cfg[flag] and Gen[flag] == my do
            pcall(fn)
            task.wait(delay)
        end
    end)
end

local function boundsOf(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst.CFrame, inst.Size end
    if inst:IsA("Model") then
        local ok, cf, size = pcall(inst.GetBoundingBox, inst)
        if ok then return cf, size end
        return nil
    end
    if inst:IsA("SurfaceGui") or inst:IsA("BillboardGui") then
        local a = inst.Adornee or inst.Parent
        if a and a:IsA("BasePart") then return a.CFrame, a.Size end
        return nil
    end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") then return d.CFrame, d.Size end
    end
    return nil
end

local function standPoint(inst)
    local cf, size = boundsOf(inst)
    if not cf then return nil end
    local hum, root = getHum(), getRoot()
    local lift = (hum and root) and (hum.HipHeight + root.Size.Y / 2) or 3
    return cf.Position + Vector3.new(0, size.Y / 2 + lift + 1, 0)
end

local beginThrowFn
local function getBeginThrow()
    if beginThrowFn then return beginThrowFn end
    if not (getgc and debug and debug.info) then return nil end
    for _, f in ipairs(getgc(true)) do
        if type(f) == "function" then
            local ok, name = pcall(debug.info, f, "n")
            if ok and name == "beginThrow" then
                local ok2, src = pcall(debug.info, f, "s")
                if (not ok2) or (type(src) == "string" and src:find("GameplayController")) then
                    beginThrowFn = f
                    return f
                end
            end
        end
    end
    return nil
end

local function launchPoints()
    local list = {}
    local model = currentWorld()
    if not model then return list end
    local zone = model:FindFirstChild("LaunchZone")
    if zone then
        local surface = zone:FindFirstChild("ThrowZoneSurface", true)
        local p = surface and standPoint(surface)
        if not p then
            for _, d in ipairs(zone:GetDescendants()) do
                if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text:upper():find("THROW ZONE", 1, true) then
                    local anc = d:FindFirstAncestorWhichIsA("BasePart")
                        or d:FindFirstAncestorWhichIsA("SurfaceGui")
                        or d:FindFirstAncestorWhichIsA("BillboardGui")
                    p = anc and standPoint(anc)
                    if p then break end
                end
            end
        end
        if p then table.insert(list, p) end
        local zp = standPoint(zone)
        if zp then table.insert(list, zp) end
    end
    if model.Name == "World1" then table.insert(list, Setup.World1Launch) end
    return list
end

local function atLaunch()
    local root = getRoot()
    if not root then return false end
    local inside = inLaunchZone()
    if inside ~= nil then return inside end
    local target = launchPoints()[1]
    if not target then return false end
    local flat = Vector3.new(root.Position.X - target.X, 0, root.Position.Z - target.Z).Magnitude
    return flat < 8 and math.abs(root.Position.Y - target.Y) < 8
end

local function runThrow()
    cycle("AutoThrow", Setup.ThrowDelay, function()
        if S.Activity == "Practice" then
            relay("StopPractice", nil)
            return
        end
        if not atLaunch() then
            local points = launchPoints()
            if #points == 0 then
                softToast("Couldn't find the launch zone in this world.")
                return
            end
            for _, p in ipairs(points) do
                if not Cfg.AutoThrow then return end
                glideTo(p, Setup.MoveSpeed, function() return not Cfg.AutoThrow end, true)
                task.wait(0.2)
                if atLaunch() then break end
            end
            if not atLaunch() then
                softToast("Couldn't reach the launch zone.")
                return
            end
        end
        local fn = getBeginThrow()
        if fn then fn() end
    end)
end

local Zones, ZoneByName = {}, {}
local labelCache = setmetatable({}, {__mode = "k"})
local failedAt = {}
local SUFFIX = {K = 1e3, M = 1e6, B = 1e9}

local function prettyName(id)
    local nm = id:gsub("^TrainingZone_?", "")
    if nm == "" then return "Basic" end
    nm = nm:gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
    return nm
end

local function parseMult(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("<[^>]+>", "")
    local num, suf = text:match("(%d[%d%.,]*)%s*([KkMmBb]?)%s*[xX]")
    if not num then return nil end
    local value = tonumber((num:gsub(",", "")))
    if not value then return nil end
    suf = suf:upper()
    return num .. suf, value * (SUFFIX[suf] or 1)
end

local function parseNumber(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("<[^>]+>", "")
    local num, suf = text:match("(%d[%d%.,]*)([KkMmBb]?)")
    if not num then return nil end
    local value = tonumber((num:gsub(",", "")))
    if not value then return nil end
    return value * (SUFFIX[suf:upper()] or 1)
end

local function zoneLabelsOf(obj)
    local now = os.clock()
    local c = labelCache[obj]
    if c then
        local dead = (c.gain and not c.gain.Parent) or (c.status and not c.status.Parent)
            or (c.count and not c.count.Parent)
        local missing = not (c.gain and c.status and c.count)
        if not dead and not (missing and now - c.t > 10) then return c end
    end
    c = {t = now}
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            if d.Name == "Gain" then
                c.gain = c.gain or d
            elseif d.Name == "UnlockStatus" then
                c.status = c.status or d
            elseif d.Name == "Count" and d.Parent and d.Parent.Name == "RebirthRequirement" then
                c.count = c.count or d
            end
        end
    end
    labelCache[obj] = c
    return c
end

local function buildZones()
    local model = currentWorld()
    local folder = model and model:FindFirstChild("TrainingZones")
    local cfg = worldConfig()
    local bonuses = cfg and cfg.Practice and cfg.Practice.ZoneBonuses
    local rebirths = myRebirths()
    local list = {}
    if folder then
        for _, c in ipairs(folder:GetChildren()) do
            local z = {id = c.Name, name = prettyName(c.Name), obj = c}
            local ls = zoneLabelsOf(c)

            local shown, value = parseMult(ls.gain and ls.gain.Text)
            if not shown then
                local b = type(bonuses) == "table" and bonuses[c.Name] or nil
                if b then shown, value = ("%g"):format(1 + b), 1 + b end
            end
            z.mult = shown
            z.sort = value or (c.Name == "TrainingZone" and 1 or 1e12)

            local st = ls.status and ls.status.Text or ""
            st = st:gsub("<[^>]+>", ""):upper()
            local lockedByStatus = st:find("LOCKED", 1, true) ~= nil and st:find("UNLOCKED", 1, true) == nil
            local req = parseNumber(ls.count and ls.count.Text)
            z.req = req
            z.locked = lockedByStatus or (req ~= nil and rebirths < req)

            table.insert(list, z)
        end
    end
    table.sort(list, function(a, b)
        if a.sort ~= b.sort then return a.sort < b.sort end
        return a.name < b.name
    end)
    Zones, ZoneByName = list, {}
    local labels = {}
    for _, z in ipairs(list) do
        local label = z.mult and ("%s - %sx"):format(z.name, z.mult) or z.name
        if z.locked then label = label .. " [Locked]" end
        z.label = label
        ZoneByName[z.name] = z
        table.insert(labels, label)
    end
    return labels
end

local function labelToName(label)
    if type(label) ~= "string" then return nil end
    if label == AUTO_LABEL then return AUTO_KEY end
    label = label:gsub(" %[Locked%]$", "")
    local base = label:match("^(.-) %- ") or label
    return ZoneByName[base] and base or nil
end

local function pickZone()
    if Cfg.ZoneName == AUTO_KEY then
        local best
        for _, z in ipairs(Zones) do
            local failed = failedAt[z.id] and os.clock() - failedAt[z.id] < 60
            if not z.locked and not failed then best = z end
        end
        return best or Zones[1], true
    end
    return ZoneByName[Cfg.ZoneName] or Zones[1], false
end

local function deckPoint(z)
    local deck = z.obj:FindFirstChild("ThrowingDeck")
    local target = deck and (deck:FindFirstChild("Planks") or deck) or z.obj
    return standPoint(target)
end

local trainMisses = 0
local autoPicked
local function runTrain()
    trainMisses = 0
    autoPicked = nil
    cycle("AutoTrain", Setup.TrainDelay, function()
        if S.Activity and S.Activity ~= "Idle" and S.Activity ~= "Practice" then return end
        buildZones()
        local z, auto = pickZone()
        if not z then
            softToast("No training zones found in this world.")
            return
        end
        if auto and autoPicked ~= z.id then
            autoPicked = z.id
            toast("Auto Train: " .. z.name)
        end
        local pos = deckPoint(z)
        local root = getRoot()
        if not (pos and root) then
            if not pos then softToast("Deck not found for: " .. z.name) end
            return
        end

        local dist = (root.Position - pos).Magnitude
        if S.Activity == "Practice" and dist <= 5 then
            trainMisses = 0
            return
        end

        if dist > 5 then
            trainMisses = 0
            if S.Activity == "Practice" then
                relay("StopPractice", nil)
                local h = getHum()
                if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
                task.wait(0.4)
            end
            glideTo(pos, Setup.MoveSpeed, function() return not Cfg.AutoTrain end, true)
            return
        end

        trainMisses = trainMisses + 1
        if trainMisses >= 2 then
            root.CFrame = CFrame.new(pos + Vector3.new(0, 0, 6))
            task.wait(0.3)
            local r2 = getRoot()
            if r2 then
                r2.AssemblyLinearVelocity = Vector3.zero
                r2.CFrame = CFrame.new(pos)
            end
        end
        if trainMisses >= 5 then
            if auto then
                failedAt[z.id] = os.clock()
                trainMisses = 0
                softToast(z.name .. " won't start, using a lower zone for now.")
            elseif trainMisses == 5 then
                softToast(z.name .. ": training won't start. You may not own this treadmill or have enough rebirths.")
            end
        end
    end)
end

local function runRebirth()
    cycle("AutoRebirth", Setup.RebirthDelay, function()
        if not (S.Level and S.NextRebirthLevel and S.Rebirths) then
            relay("Sync")
            return
        end
        local okActivity = (S.Activity == "Idle" or S.Activity == "Practice")
        if okActivity and S.Level >= S.NextRebirthLevel then
            relay("Rebirth", S.Rebirths)
        end
    end)
end

local function runBuy()
    cycle("AutoBuy", Setup.BuyDelay, function()
        local cfg = worldConfig()
        local ids = cfg and cfg.StoneIds
        if type(ids) ~= "table" then return end
        for i = #ids, 1, -1 do
            if not (Alive and Cfg.AutoBuy) then break end
            local v = ids[i]
            local id = (type(v) == "table") and (v.Id or v.id) or v
            relay("Buy", id)
            task.wait(0.15)
        end
    end)
end

local function eggDisplay(id)
    local model = currentWorld()
    local shop = model and model:FindFirstChild("EggShop")
    local disp = shop and shop:FindFirstChild("Displays")
    return disp and disp:FindFirstChild(id)
end

local function eggIds()
    local ids, seen = {}, {}
    local model = currentWorld()
    local shop = model and model:FindFirstChild("EggShop")
    local disp = shop and shop:FindFirstChild("Displays")
    if disp then
        for _, c in ipairs(disp:GetChildren()) do
            if not seen[c.Name] then seen[c.Name] = true table.insert(ids, c.Name) end
        end
    end
    if #ids == 0 then
        local assets = RS:FindFirstChild("Assets")
        local eggs = assets and assets:FindFirstChild("Eggs")
        if eggs then
            for _, c in ipairs(eggs:GetChildren()) do
                if not seen[c.Name] then seen[c.Name] = true table.insert(ids, c.Name) end
            end
        end
    end
    return ids
end

local hatchReq = 1000000
local function runHatch()
    cycle("AutoHatch", Setup.HatchDelay, function()
        local egg = Cfg.EggId
        if egg == "" then return end
        if S.Activity == "Practice" then
            relay("StopPractice", nil)
            task.wait(0.5)
        elseif S.Activity and S.Activity ~= "Idle" then
            return
        end

        local d = eggDisplay(egg)
        local root = getRoot()
        if d and root then
            local okPivot, pivot = pcall(function() return d:GetPivot() end)
            if okPivot then
                local target = pivot.Position + Vector3.new(0, 4, 0)
                if (root.Position - target).Magnitude > 12 then
                    glideTo(target, Setup.MoveSpeed, function() return not Cfg.AutoHatch end)
                    if not Cfg.AutoHatch then return end
                end
            end
        elseif not d then
            softToast("Egg not found: " .. egg)
        end

        hatchReq = hatchReq + 1
        relay("HatchEgg", {EggId = egg, Count = Cfg.HatchCount, RequestId = hatchReq})
    end)
end

local function runEquip()
    cycle("AutoEquip", Setup.EquipDelay, function()
        if S.Activity and S.Activity ~= "Idle" then return end
        relay("PetEquipment", {Kind = "Best"})
    end)
end

local function runFreeReward()
    cycle("AutoFreeReward", 30, function()
        relay("ClaimFreeReward", nil)
    end)
end

keep(RunService.Heartbeat:Connect(function()
    if Cfg.WalkSpeedOn then
        local h = getHum()
        if h then h.WalkSpeed = Cfg.WalkSpeed end
    end
end))

local flightLink
local function toggleFlight(on)
    Cfg.Fly = on
    if flightLink then flightLink:Disconnect() flightLink = nil end
    if not on then
        local h = getHum()
        if h then h.PlatformStand = false end
        return
    end
    flightLink = RunService.RenderStepped:Connect(function()
        local root, hum, cam = getRoot(), getHum(), Workspace.CurrentCamera
        if not (root and hum and cam) then return end
        if UIS:GetFocusedTextBox() then return end
        hum.PlatformStand = true
        local dir = Vector3.zero
        if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
        if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end
        root.AssemblyLinearVelocity = dir.Magnitude > 0 and dir.Unit * Cfg.FlySpeed or Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end

keep(RunService.Stepped:Connect(function()
    if not Cfg.NoClip then return end
    local c = getChar()
    if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
    end
end))

keep(UIS.JumpRequest:Connect(function()
    if Cfg.InfJump then
        local h = getHum()
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end))

local ppHold = setmetatable({}, {__mode = "k"})
local function zeroHold(pp)
    if not pp:IsA("ProximityPrompt") then return end
    if ppHold[pp] == nil then ppHold[pp] = pp.HoldDuration end
    pp.HoldDuration = 0
end
local ppLink
local function toggleQuickPrompt(on)
    Cfg.InstantPP = on
    if ppLink then ppLink:Disconnect() ppLink = nil end
    if on then
        for _, d in ipairs(Workspace:GetDescendants()) do zeroHold(d) end
        ppLink = Workspace.DescendantAdded:Connect(zeroHold)
    else
        for pp, hd in pairs(ppHold) do
            if pp.Parent then pp.HoldDuration = hd end
        end
    end
end

keep(LocalPlayer.Idled:Connect(function()
    if Cfg.AntiAfk then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end))

local perfSave = {parts = setmetatable({}, {__mode = "k"}), light = nil}
local function togglePerf(on)
    Cfg.FpsBoost = on
    if on then
        perfSave.light = {GlobalShadows = Lighting.GlobalShadows, FogEnd = Lighting.FogEnd}
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam")
               or d:IsA("Smoke") or d:IsA("Fire") or d:IsA("Sparkles") then
                perfSave.parts[d] = d.Enabled
                d.Enabled = false
            end
        end
    else
        if perfSave.light then
            Lighting.GlobalShadows = perfSave.light.GlobalShadows
            Lighting.FogEnd = perfSave.light.FogEnd
        end
        for d, en in pairs(perfSave.parts) do
            if d.Parent then d.Enabled = en end
        end
    end
end
keep(Workspace.DescendantAdded:Connect(function(d)
    if Cfg.FpsBoost and (d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam")) then
        perfSave.parts[d] = d.Enabled
        d.Enabled = false
    end
end))

local function toggleRender(on)
    Cfg.Disable3D = on
    pcall(function() RunService:Set3dRenderingEnabled(not on) end)
end

local rejoinBound = false
local function toggleRejoin(on)
    Cfg.AutoReconnect = on
    if on and not rejoinBound then
        rejoinBound = true
        pcall(function()
            local gui = game:GetService("CoreGui"):FindFirstChild("RobloxPromptGui", true)
            local overlay = gui and gui:FindFirstChild("promptOverlay")
            if overlay then
                keep(overlay.ChildAdded:Connect(function(c)
                    if Cfg.AutoReconnect and c.Name == "ErrorPrompt" then
                        task.wait(2)
                        pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
                    end
                end))
            end
        end)
    end
end

local Hub = UILib:CreateWindow({
    Name = "+1 Stone Skipping Script " .. VERSION,
    LoadingTitle = "+1 Stone Skipping Script",
    LoadingSubtitle = "by @robloxvibe coder | " .. VERSION,
    ConfigurationSaving = {Enabled = true, FolderName = "PlusOneStoneSkipping", FileName = "config_v1"},
    KeySystem = false,
})

local function withAuto(labels)
    local out = {AUTO_LABEL}
    for _, l in ipairs(labels) do table.insert(out, l) end
    return out
end

local zoneLabels = buildZones()
local eggList = {}
local lastSig = table.concat(zoneLabels, "|")
local ThrowToggle, TrainToggle, HatchToggle, ZoneDrop, EggDrop

local function turnOffOthers(except)
    local group = {
        AutoThrow = function() return ThrowToggle end,
        AutoTrain = function() return TrainToggle end,
        AutoHatch = function() return HatchToggle end,
    }
    for flag, getT in pairs(group) do
        if flag ~= except and Cfg[flag] then
            Cfg[flag] = false
            local t = getT()
            if t then pcall(function() t:Set(false) end) end
            toast((flag:gsub("^Auto", "Auto ")) .. " turned off (only one of Throw / Train / Hatch at a time)")
        end
    end
end

local Grind = Hub:CreateTab("Grind", "gamepad-2")
Grind:CreateSection("Farming (Throw, Train and Hatch can't run together)")

ThrowToggle = Grind:CreateToggle({Name = "Auto Throw", CurrentValue = false, Flag = "AutoThrow", Callback = function(v)
    Cfg.AutoThrow = v
    if not v then return end
    turnOffOthers("AutoThrow")
    if not getBeginThrow() then
        Cfg.AutoThrow = false
        if ThrowToggle then ThrowToggle:Set(false) end
        toast("Auto Throw isn't supported by your executor (needs getgc + debug.info).", 5)
        return
    end
    runThrow()
end})

TrainToggle = Grind:CreateToggle({Name = "Auto Train", CurrentValue = false, Flag = "AutoTrain", Callback = function(v)
    Cfg.AutoTrain = v
    if not v then return end
    turnOffOthers("AutoTrain")
    runTrain()
end})
ZoneDrop = Grind:CreateDropdown({Name = "Train Zone", Options = withAuto(zoneLabels),
    CurrentOption = {AUTO_LABEL}, MultipleOptions = false, Flag = "TrainZone",
    Callback = function(o)
        local v = type(o) == "table" and o[1] or o
        local name = labelToName(v)
        if name then Cfg.ZoneName = name end
    end})

HatchToggle = Grind:CreateToggle({Name = "Auto Hatch", CurrentValue = false, Flag = "AutoHatch", Callback = function(v)
    Cfg.AutoHatch = v
    if not v then return end
    turnOffOthers("AutoHatch")
    runHatch()
end})
EggDrop = Grind:CreateDropdown({Name = "Egg", Options = {"(loading)"},
    CurrentOption = {"(loading)"}, MultipleOptions = false, Flag = "EggChoice",
    Callback = function(o)
        local v = type(o) == "table" and o[1] or o
        if v and v ~= "(loading)" and v ~= "(none found)" then Cfg.EggId = v end
    end})
Grind:CreateSlider({Name = "Hatch Count", Range = {1, 5}, Increment = 1, CurrentValue = 1,
    Flag = "HatchCount", Callback = function(v) Cfg.HatchCount = v end})

local function applyZoneList(zl)
    lastSig = table.concat(zl, "|")
    local currentLabel = AUTO_LABEL
    if Cfg.ZoneName ~= AUTO_KEY then
        local z = ZoneByName[Cfg.ZoneName]
        if z then
            currentLabel = z.label
        else
            Cfg.ZoneName = AUTO_KEY
        end
    end
    pcall(function()
        ZoneDrop:Refresh(withAuto(zl))
        ZoneDrop:Set({currentLabel})
    end)
end

local function refreshLists(notify)
    applyZoneList(buildZones())

    eggList = eggIds()
    local keepEgg = table.find(eggList, Cfg.EggId) and Cfg.EggId or eggList[1]
    Cfg.EggId = keepEgg or ""
    pcall(function()
        EggDrop:Refresh(#eggList > 0 and eggList or {"(none found)"})
        EggDrop:Set({keepEgg or "(none found)"})
    end)
    if notify then toast(("Found %d zones, %d eggs"):format(#Zones, #eggList)) end
end
Grind:CreateButton({Name = "Refresh Zones & Eggs", Callback = function()
    refreshLists(true)
end})

Grind:CreateSection("Progression")
Grind:CreateToggle({Name = "Auto Rebirth", CurrentValue = false, Flag = "AutoRebirth", Callback = function(v)
    Cfg.AutoRebirth = v
    if v then relay("Sync") runRebirth() end
end})
Grind:CreateToggle({Name = "Server Auto Rebirth (if you own it)", CurrentValue = false, Flag = "ServerAutoRebirth",
    Callback = function(v) relay("SetAutoRebirth", v) end})
Grind:CreateToggle({Name = "Auto Buy Stones", CurrentValue = false, Flag = "AutoBuy", Callback = function(v)
    Cfg.AutoBuy = v
    if v then runBuy() end
end})
Grind:CreateToggle({Name = "Auto Equip Best Pets", CurrentValue = false, Flag = "AutoEquip", Callback = function(v)
    Cfg.AutoEquip = v
    if v then runEquip() end
end})

local Mobility = Hub:CreateTab("Movement", "person-standing")
Mobility:CreateSection("Speed")
Mobility:CreateToggle({Name = "WalkSpeed", CurrentValue = false, Flag = "WSOn", Callback = function(v)
    Cfg.WalkSpeedOn = v
    if not v then local h = getHum() if h then h.WalkSpeed = 16 end end
end})
Mobility:CreateSlider({Name = "WalkSpeed Amount", Range = {16, 300}, Increment = 1, CurrentValue = 50,
    Flag = "WSAmt", Callback = function(v) Cfg.WalkSpeed = v end})
Mobility:CreateSection("Flight & Collision (turn NoClip off while farming)")
Mobility:CreateToggle({Name = "Fly", CurrentValue = false, Flag = "Fly", Callback = function(v) toggleFlight(v) end})
Mobility:CreateSlider({Name = "Fly Speed", Range = {10, 300}, Increment = 1, CurrentValue = 60,
    Flag = "FlySpeed", Callback = function(v) Cfg.FlySpeed = v end})
Mobility:CreateToggle({Name = "NoClip", CurrentValue = false, Flag = "NoClip", Callback = function(v) Cfg.NoClip = v end})
Mobility:CreateToggle({Name = "Infinite Jump", CurrentValue = false, Flag = "InfJump", Callback = function(v)
    Cfg.InfJump = v end})
Mobility:CreateToggle({Name = "Instant ProximityPrompt", CurrentValue = false, Flag = "InstantPP", Callback = function(v)
    toggleQuickPrompt(v) end})

local Extras = Hub:CreateTab("Extras", "sparkles")
Extras:CreateToggle({Name = "Anti-AFK", CurrentValue = true, Flag = "AntiAfk", Callback = function(v)
    Cfg.AntiAfk = v end})
Extras:CreateToggle({Name = "Auto Reconnect on Kick", CurrentValue = false, Flag = "AutoReconnect",
    Callback = function(v) toggleRejoin(v) end})
Extras:CreateToggle({Name = "FPS Boost", CurrentValue = false, Flag = "FpsBoost", Callback = function(v) togglePerf(v) end})
Extras:CreateToggle({Name = "Disable 3D Rendering", CurrentValue = false, Flag = "Disable3D", Callback = function(v)
    toggleRender(v) end})
Extras:CreateSection("Rewards")
Extras:CreateToggle({Name = "Auto Claim Free Reward", CurrentValue = false, Flag = "AutoFreeReward", Callback = function(v)
    Cfg.AutoFreeReward = v
    if v then runFreeReward() end
end})
Extras:CreateInput({Name = "Code", PlaceholderText = "enter a code", RemoveTextAfterFocusLost = false,
    Callback = function(t) Cfg.Code = t end})
Extras:CreateButton({Name = "Redeem Code", Callback = function()
    if Cfg.Code == "" then toast("Type a code first") return end
    relay("RedeemCode", Cfg.Code)
end})
Extras:CreateSection("Utility")
Extras:CreateButton({Name = "Rejoin Place", Callback = function()
    TeleportService:Teleport(game.PlaceId, LocalPlayer) end})
Extras:CreateButton({Name = "Copy Job ID", Callback = function()
    if setclipboard then setclipboard(game.JobId) toast("Copied Job ID") end end})

local function unload()
    Alive = false
    for k, v in pairs(Cfg) do if type(v) == "boolean" then Cfg[k] = false end end
    pcall(toggleFlight, false)
    pcall(toggleQuickPrompt, false)
    pcall(togglePerf, false)
    pcall(toggleRender, false)
    for _, c in ipairs(links) do pcall(function() c:Disconnect() end) end
    pcall(function() UILib:Destroy() end)
end
if getgenv then getgenv().StoneSkippingUnload = unload end
Extras:CreateButton({Name = "Unload Script", Callback = unload})

GameReady = true
task.spawn(function()
    refreshLists(false)
    local lastWorld = currentWorld()
    local t0 = os.clock()
    while Alive and not Net.Request and os.clock() - t0 < 10 do task.wait(0.2) end
    if not Alive then return end
    pcall(function() UILib:LoadConfiguration() end)
    toast("Loaded " .. VERSION .. " by @robloxvibe coder", 4)
    while Alive do
        task.wait(3)
        local w = currentWorld()
        if w ~= lastWorld then
            lastWorld = w
            task.wait(1)
            refreshLists(false)
        else
            local zl = buildZones()
            if table.concat(zl, "|") ~= lastSig then applyZoneList(zl) end
        end
    end
end)