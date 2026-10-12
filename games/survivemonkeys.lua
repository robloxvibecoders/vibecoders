if not game:IsLoaded() then game.Loaded:Wait() end

local VERSION = 2.2
local env = (getgenv and getgenv()) or _G
if (env.MonkeyVersion or 0) > VERSION then return end
env.MonkeyVersion = VERSION
if env.MonkeyCleanup then pcall(env.MonkeyCleanup) end
env.MonkeyGen = (env.MonkeyGen or 0) + 1
local gen = env.MonkeyGen
local function alive() return env.MonkeyGen == gen end

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

local function httpGet(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" and #body > 0 then return body end
    local req = request or http_request or (syn and syn.request) or (fluxus and fluxus.request)
    if req then
        local ok2, res = pcall(req, { Url = url, Method = "GET" })
        if ok2 and type(res) == "table" and type(res.Body) == "string" and #res.Body > 0
            and (type(res.StatusCode) ~= "number" or (res.StatusCode >= 200 and res.StatusCode < 300)) then
            return res.Body
        end
    end
end

local CONFIG = {
    -- Lobby only. Any other PlaceId is treated as a match (see IN_LOBBY); the match PlaceId is not referenced.
    LobbyPlace = 99409088950210,
    Map = "Laboratory",
    DeathSpot = Vector3.new(64, 5, 20),
    SourceURL = "https://raw.githubusercontent.com/robloxvibecoders/vibecoders/main/games/survivemonkeys.lua",
}
local IN_LOBBY = game.PlaceId == CONFIG.LobbyPlace

local SAFE_FALL_Y = 3.5
local SEMI = {
    Depth = 3.5,
    YLimit = 20,
    XZLimit = 12,
    Rings = { 4, 8, 12 },
    Angles = 16,
    LeadPad = 0.05,
    Window = 0.2,
    RayLength = 500,
    RayEvery = 0.1,
    StaleAfter = 0.2,
}
local MAPS = {
    Cove = {
        Stage = Vector3.new(66, 5, 53),
        SafeSpot = Vector3.new(67, -2, 41),
        DeathSpot = CONFIG.DeathSpot,
        Fly = true,
        Ramp = true,
        Dodge = true,
        FallY = -25,
        FloorY = -49,
    },
    Laboratory = {
        Stage = Vector3.new(-37, -3, -61),
        SafeSpot = Vector3.new(-37, -10, -61),
        Fly = true,
        Settle = 18,
        AbilityHop = false,
        Dodge = true,
        FallY = -25,
        FloorY = -49,
        Fade = {
            { index = 132, pos = Vector3.new(-36.6749878, -6.61671448, -7.79998779) },
            { index = 121, pos = Vector3.new(-36.6749878, -6.61671448, -60.2999878) },
        },
        Remove = { { index = 117, pos = Vector3.new(-36.6749878, -3.61671829, -7.79998779) } },
    },
}

local function getSafeSpot()
    local m = MAPS[CONFIG.Map]
    return m and m.SafeSpot or nil
end

local function getFallY()
    local m = MAPS[CONFIG.Map]
    return m and m.FallY or SAFE_FALL_Y
end

local function getDeathSpot()
    local m = MAPS[CONFIG.Map]
    return m and m.DeathSpot or nil
end

local S = {
    AutoKill = false, SafeSpot = false, AutoSkip = false, Upgrades = {}, Abilities = {},
    Autofarm = false, Difficulty = "Normal", StopWave = 20,
}
local Rayfield, held, abilityDropdown, autofarmToggle, toggleGui
local killToggle, safeToggle, skipToggle, mapDropdown, upgradeDropdown
local uiReady = false
local uiTrackAt = math.huge
local conns = {}

local suspended = false
local toolBusy = false
local lastEquip = 0
local Lab = { busy = false, dodging = false, char = nil, token = 0, settleFrom = os.clock() }

local function settleLeft()
    local m = MAPS[CONFIG.Map]
    if IN_LOBBY or not (m and m.Settle) then return 0 end
    return m.Settle - (os.clock() - Lab.settleFrom)
end

local Semi = {
    on = false, hookReady = false, capable = false, warned = false, handled = false,
    shifted = false, shiftedAt = 0, real = CFrame.new(), moved = CFrame.new(), root = nil,
    groundAt = 0, groundY = nil,
}
env.MonkeySemi = Semi

local function realCF(root)
    if Semi.shifted and root == Semi.root then
        local cf = root.CFrame
        if (cf.Position - Semi.moved.Position).Magnitude < 0.01 then return Semi.real end
        return cf
    end
    return root.CFrame
end

local syncing = false
local function syncUI()
    local map = { AutoKill = killToggle, SafeSpot = safeToggle, AutoSkip = skipToggle }
    syncing = true
    for key, t in pairs(map) do
        if t then pcall(function() t:Set(S[key]) end) end
    end
    syncing = false
    if upgradeDropdown then
        local list = {}
        for kind, on in pairs(S.Upgrades) do
            if on then list[#list + 1] = kind end
        end
        pcall(function() upgradeDropdown:Set(list) end)
    end
end

local state, saveState, persistAutofarm, RESUMING = {}
do
    local STATE_DIR, STATE_FILE = "MonkeyHorde", "MonkeyHorde/state.json"
    local HAS_FILES = writefile ~= nil and readfile ~= nil and isfile ~= nil
    local RESUME_WINDOW = 600

    local function loadState()
        if not HAS_FILES or not isfile(STATE_FILE) then return end
        local ok, t = pcall(function() return HttpService:JSONDecode(readfile(STATE_FILE)) end)
        if ok and type(t) == "table" then state = t end
    end

    function saveState()
        if not writefile then return end
        pcall(function()
            if makefolder and isfolder and not isfolder(STATE_DIR) then makefolder(STATE_DIR) end
            writefile(STATE_FILE, HttpService:JSONEncode(state))
        end)
    end

    loadState()

    if type(state.map) == "string" and MAPS[state.map] then CONFIG.Map = state.map end
    S.StopWave = tonumber(state.stopWave) or tonumber(env.MonkeyStopWave) or S.StopWave

    function persistAutofarm(on)
        state.autofarm = on
        state.autofarmAt = os.time()
        saveState()
    end

    local function resumeWanted()
        if not HAS_FILES then return env.MonkeyAutofarm == true end
        return state.autofarm == true
            and type(state.autofarmAt) == "number"
            and os.time() - state.autofarmAt < RESUME_WINDOW
    end

    RESUMING = resumeWanted()
end

S.NextMap = CONFIG.Map

local earlyActive = RESUMING and not IN_LOBBY

if earlyActive then
    S.SafeSpot = true
    task.spawn(function()
        local stop = os.clock() + 30
        while alive() and earlyActive and S.SafeSpot and not suspended and os.clock() < stop do
            local ch = LocalPlayer.Character
            local root = ch and ch:FindFirstChild("HumanoidRootPart")
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            local spot = getSafeSpot()
            local cfg = MAPS[CONFIG.Map]
            if spot and not (cfg and cfg.Fly)
                and root and hum and hum.Health > 0 and (realCF(root).Position - spot).Magnitude > 10 then
                ch:PivotTo(CFrame.new(spot))
                root.AssemblyLinearVelocity = Vector3.zero
            end
            task.wait(0.05)
        end
    end)
end

local function waitPath(root, timeout, ...)
    local node, deadline = root, os.clock() + timeout
    for _, name in ipairs({ ... }) do
        node = node:WaitForChild(name, math.max(0.1, deadline - os.clock()))
        if not node then return nil end
    end
    return node
end

local function findPath(root, ...)
    local node = root
    for _, name in ipairs({ ... }) do
        node = node and node:FindFirstChild(name)
    end
    return node
end

if not IN_LOBBY then
    local deadline, seenAt, found = os.clock() + 25, nil, nil
    while alive() and not found and os.clock() < deadline do
        local ground = findPath(workspace, "Map", "Ground")
        if ground then
            seenAt = seenAt or os.clock()
            if ground:FindFirstChild("AcidPit") or ground:FindFirstChild("CryoRoom") then
                found = "Laboratory"
            elseif os.clock() - seenAt >= 6 then
                found = "Cove"
            end
        end
        if not found then task.wait(0.25) end
    end
    if found then CONFIG.Map = found end
end

local function requireNode(node)
    if not node then return end
    local ok, m = pcall(require, node)
    if ok and type(m) == "table" then return m end
end

local function loadMod(...) return requireNode(waitPath(RS, 10, ...)) end

local GunRig, TargetWorld, UnitView, Ballistics, Catalog, AoePatterns
if not IN_LOBBY then
    GunRig = loadMod("GunKit", "Controllers", "GunRigController")
    TargetWorld = loadMod("GunKit", "Shared", "Weapons", "TargetWorld")
    UnitView = requireNode(waitPath(LocalPlayer, 10, "PlayerScripts", "Client", "Controllers", "UnitViewController"))
    Ballistics = loadMod("GunKit", "Shared", "Weapons", "Ballistics")
    Catalog = loadMod("Shared", "Content", "Catalog")
    AoePatterns = loadMod("Shared", "Content", "AoePatterns")
    local ch = LocalPlayer.Character
    local charDeadline = os.clock() + 30
    while not ch and os.clock() < charDeadline do
        task.wait(0.25)
        ch = LocalPlayer.Character
    end
    if ch then ch:WaitForChild("HumanoidRootPart", 15) end
end
-- A newer execution may have superseded this one during the startup waits above.
if not alive() then return end
local PEN = (Ballistics and Ballistics.Penetration) or 10

local function getRoot()
    local ch = LocalPlayer.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local ch = LocalPlayer.Character
    return ch and ch:FindFirstChildOfClass("Humanoid")
end

local function currentTool()
    local ch = LocalPlayer.Character
    local tool = ch and ch:FindFirstChildOfClass("Tool")
    return tool and tool:FindFirstChild("WeaponConfig") and tool or nil
end

local function inventoryTool(name)
    local ch = LocalPlayer.Character
    local pack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local tool = (ch and ch:FindFirstChild(name)) or (pack and pack:FindFirstChild(name))
    return tool and tool:IsA("Tool") and tool or nil
end

local function playerGui() return LocalPlayer:FindFirstChild("PlayerGui") end

local function notify(title, content)
    if not Rayfield then return end
    pcall(function()
        Rayfield:Notify({ Title = title, Content = content, Duration = 6 })
    end)
end

local function loop(interval, fn)
    task.spawn(function()
        while alive() do
            local ok, err = pcall(fn)
            if not ok then
                if env.MonkeyDebug == true then warn("[Monkey] loop error:", err) end
                task.wait(1)
            end
            task.wait(interval)
        end
    end)
end

local function toList(opt)
    if type(opt) == "table" then return opt end
    return { opt }
end

local nearestUnits, pickTarget, toolInfo
local Aim = {}
do
    local toolInfoCache = setmetatable({}, { __mode = "k" })
    local lastTargetId
    local unitBuf, nearP, nearD = {}, {}, {}

    local function scanFolder(folder, out)
        for _, m in ipairs(folder:GetChildren()) do
            if m:IsA("Model") then
                local p = m:FindFirstChild("Unit")
                if p and p:IsA("BasePart") and p:GetAttribute("UnitId") ~= nil and p.LocalTransparencyModifier < 1 then
                    out[#out + 1] = p
                end
            end
        end
    end

    local function collectUnits(out)
        table.clear(out)
        local views = workspace:FindFirstChild("UnitViews")
        if not views then return end
        scanFolder(views, out)
        local flash = views:FindFirstChild("UnitFlash")
        if flash then scanFolder(flash, out) end
    end

    function nearestUnits(pivot, k)
        collectUnits(unitBuf)
        table.clear(nearP)
        table.clear(nearD)
        for i = 1, #unitBuf do
            local p = unitBuf[i]
            local d = (p.Position - pivot).Magnitude
            local n = #nearP
            if n < k or d < nearD[n] then
                local j = math.min(n + 1, k)
                while j > 1 and nearD[j - 1] > d do
                    nearP[j] = nearP[j - 1]
                    nearD[j] = nearD[j - 1]
                    j = j - 1
                end
                nearP[j] = p
                nearD[j] = d
            end
        end
        return nearP
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.IgnoreWater = true
    local penParams = RaycastParams.new()
    penParams.FilterType = Enum.RaycastFilterType.Include
    penParams.IgnoreWater = true

    local ignoreList, ignoreAt = {}, 0
    local function getIgnore()
        local now = os.clock()
        if now - ignoreAt < 1 and #ignoreList > 0 then return ignoreList end
        table.clear(ignoreList)
        local function add(x) if x then ignoreList[#ignoreList + 1] = x end end
        add(LocalPlayer.Character)
        add(workspace:FindFirstChild("UnitViews"))
        add(workspace:FindFirstChild("ClientBullets"))
        local map = workspace:FindFirstChild("Map")
        add(map and map:FindFirstChild("Blockers"))
        ignoreAt = now
        rayParams.FilterDescendantsInstances = ignoreList
        return ignoreList
    end

    local BLAST_SLACK = 12
    local DEBUG = env.MonkeyDebug == true
    local dbgAt = 0
    local function dbg(...)
        if DEBUG and os.clock() - dbgAt > 1 then
            dbgAt = os.clock()
            print("[Monkey]", ...)
        end
    end

    local penFilter = {}
    local function canReach(from, to, blast, blastRadius)
        local dir = to - from
        local total = dir.Magnitude
        if total < 0.1 then return true end
        local unit = dir.Unit
        getIgnore()
        local pos, travelled = from, 0
        for _ = 1, 8 do
            local rem = total - travelled
            if rem <= 0.05 then return true end
            local hit = workspace:Raycast(pos, unit * rem, rayParams)
            if not hit then return true end
            if blast then
                local d = (to - hit.Position).Magnitude
                local ok = d <= (blastRadius or 0) * 0.8 + BLAST_SLACK
                if not ok then
                    dbg("blast blocked by", hit.Instance:GetFullName(), "dist to target", math.floor(d))
                end
                return ok
            end
            local off = unit * PEN
            penFilter[1] = hit.Instance
            penParams.FilterDescendantsInstances = penFilter
            local exit = workspace:Raycast(hit.Position + off, -off, penParams)
            if not exit then return false end
            pos = exit.Position + unit * 0.05
            local nt = (pos - from):Dot(unit)
            if nt <= travelled then return false end
            travelled = nt
        end
        return false
    end

    local defaultInfo = { range = 300, blast = false, blastRadius = 0, fireMode = "Semi" }
    function toolInfo(tool)
        if not tool then return defaultInfo end
        local cached = toolInfoCache[tool]
        if cached then return cached end
        local info = { range = 300, blast = false, blastRadius = 0, fireMode = "Semi" }
        local cfg = tool:FindFirstChild("WeaponConfig")
        if cfg and cfg:IsA("ModuleScript") then
            local ok, c = pcall(require, cfg)
            if ok and type(c) == "table" and type(c.projectile) == "table" then
                local pr = c.projectile
                if pr.fireMode then info.fireMode = pr.fireMode end
                if type(pr.maxRange) == "number" then info.range = pr.maxRange end
                if type(pr.blast) == "table" then
                    info.blast = true
                    if type(pr.blast.radius) == "number" then info.blastRadius = pr.blast.radius end
                else
                    info.blast = pr.blast ~= nil and pr.blast ~= false
                end
            end
        end
        toolInfoCache[tool] = info
        return info
    end

    local function tryCone(fn, self, ...)
        local ok, pos, id = pcall(fn, ...)
        if ok and pos then return pos, id end
        if self then
            ok, pos, id = pcall(fn, self, ...)
            if ok and pos then return pos, id end
        end
    end

    local function reachable(pos, pivot, info)
        return (pos - pivot).Magnitude <= info.range and canReach(pivot, pos, info.blast, info.blastRadius)
    end

    local scanPart, scanAt, emptyAt = nil, 0, 0

    function pickTarget(camPos, look, pivot, speed, tool)
        local info = toolInfo(tool)

        local pos, id
        if UnitView and UnitView.coneTarget then
            pos, id = tryCone(UnitView.coneTarget, nil, camPos, look, lastTargetId, pivot, speed, -1)
        end
        if not pos then
            local world = TargetWorld and TargetWorld.current
            if world and world.coneTarget then
                pos, id = tryCone(world.coneTarget, world, camPos, look, lastTargetId, pivot, speed, -1)
            end
        end
        if pos and reachable(pos, pivot, info) then
            lastTargetId = id
            return pos
        end
        lastTargetId = nil

        local now = os.clock()
        if scanPart and now - scanAt < 0.15 and scanPart.Parent and scanPart:GetAttribute("UnitId") ~= nil then
            return scanPart.Position
        end
        if now - emptyAt < 0.15 then return nil end
        local near = nearestUnits(pivot, 8)
        for i = 1, #near do
            if reachable(near[i].Position, pivot, info) then
                scanPart, scanAt = near[i], now
                return near[i].Position
            end
        end
        scanPart, emptyAt = nil, now
    end

    function Aim.resetTarget()
        lastTargetId, scanPart, emptyAt = nil, nil, 0
    end

    function Aim.resetIgnore()
        ignoreAt = 0
    end

    function Aim.ground(from)
        getIgnore()
        local hit = workspace:Raycast(from, Vector3.new(0, -SEMI.RayLength, 0), rayParams)
        return hit and hit.Position.Y or nil
    end

    function Aim.clear()
        table.clear(unitBuf)
        table.clear(nearP)
        table.clear(nearD)
        table.clear(ignoreList)
    end
end

env.MonkeyAim = function(tool, camPos, look, pivot, speed)
    if not (alive() and S.AutoKill and not suspended) or settleLeft() > 0 then return nil end
    local ok, pos = pcall(pickTarget, camPos, look, pivot, speed, tool)
    return ok and pos or nil
end

if GunRig and GunRig.AddAimOverride and env.MonkeyAimOn ~= GunRig then
    env.MonkeyAimOn = GunRig
    GunRig.AddAimOverride(function(...)
        local fn = env.MonkeyAim
        if fn then return fn(...) end
    end)
end

local function release()
    if held then
        pcall(function() held:Deactivate() end)
        held = nil
    end
end

local function equipOnce()
    if settleLeft() > 0 or toolBusy then return end
    local hum, pack = getHumanoid(), LocalPlayer:FindFirstChildOfClass("Backpack")
    if not (hum and pack and hum.Health > 0) or currentTool() then return end
    for _, t in ipairs(pack:GetChildren()) do
        if t:IsA("Tool") and t:FindFirstChild("WeaponConfig") then
            hum:EquipTool(t)
            return
        end
    end
end

local function activateTool(tool, delay)
    local ch, hum = LocalPlayer.Character, getHumanoid()
    if not (ch and hum and hum.Health > 0) then return end
    toolBusy = true
    release()
    pcall(function()
        if tool.Parent ~= ch then hum:EquipTool(tool) end
        local deadline = os.clock() + 1
        while tool.Parent ~= ch and os.clock() < deadline do task.wait(0.05) end
        if tool.Parent == ch then
            tool:Activate()
            task.wait(delay + 0.2)
        end
    end)
    toolBusy = false
    equipOnce()
end

loop(0.05, function()
    if not (S.AutoKill and not suspended and GunRig) or settleLeft() > 0 or toolBusy then return release() end
    local hum, root = getHumanoid(), getRoot()
    if not (hum and root) or hum.Health <= 0 then return release() end
    local tool = currentTool()
    local cam = workspace.CurrentCamera
    if not tool then
        local now = os.clock()
        if now - lastEquip > 0.75 then
            lastEquip = now
            equipOnce()
        end
        return release()
    end
    if not cam then return release() end
    local pivot = realCF(root).Position + Vector3.new(0, 1, 0)
    if not pickTarget(cam.CFrame.Position, cam.CFrame.LookVector, pivot, nil, tool) then
        return release()
    end
    pcall(GunRig.PushAim, GunRig)
    tool:Activate()
    held = tool
    if toolInfo(tool).fireMode == "Semi" then
        task.wait(0.02)
        tool:Deactivate()
        held = nil
    end
end)

local setSafe, cleanupSafe
do
    local STAIR_TRANSPARENCY = 0.7
    local safeActive, origin, noclipConn, partConn, trackedChar = false, nil, nil, nil, nil
    local charParts = {}
    local savedCollide = setmetatable({}, { __mode = "k" })
    local stairOrig = setmetatable({}, { __mode = "k" })
    local stairCol = setmetatable({}, { __mode = "k" })

    local function trackCharacter(ch)
        table.clear(charParts)
        if partConn then
            partConn:Disconnect()
            partConn = nil
        end
        for _, p in ipairs(ch:GetDescendants()) do
            if p:IsA("BasePart") then charParts[#charParts + 1] = p end
        end
        partConn = ch.DescendantAdded:Connect(function(p)
            if p:IsA("BasePart") then charParts[#charParts + 1] = p end
        end)
    end

    local function stopNoclip()
        if noclipConn then
            noclipConn:Disconnect()
            noclipConn = nil
        end
        if partConn then
            partConn:Disconnect()
            partConn = nil
        end
        for p in pairs(savedCollide) do
            if p.Parent then pcall(function() p.CanCollide = true end) end
        end
        table.clear(savedCollide)
        table.clear(charParts)
    end

    local function noclipStep()
        if not alive() then return stopNoclip() end
        local i = #charParts
        while i > 0 do
            local p = charParts[i]
            if p.Parent then
                if p.CanCollide then
                    savedCollide[p] = true
                    p.CanCollide = false
                end
            else
                charParts[i] = charParts[#charParts]
                charParts[#charParts] = nil
            end
            i = i - 1
        end
    end

    local function startNoclip(ch)
        trackCharacter(ch)
        if not noclipConn then
            noclipConn = RunService.Stepped:Connect(noclipStep)
        end
    end

    local function applyStairs()
        local stairs = findPath(workspace, "Map", "Ground", "BigStaircase")
        if not stairs then return end
        for _, p in ipairs(stairs:GetDescendants()) do
            if p:IsA("BasePart") and p.Name == "Stair" then
                if stairOrig[p] == nil then stairOrig[p] = p.Transparency end
                if stairCol[p] == nil then stairCol[p] = { p.CanCollide, p.CanQuery } end
                p.Transparency = STAIR_TRANSPARENCY
                p.CanCollide = false
                p.CanQuery = false
            end
        end
    end

    local function restoreStairs()
        for p, t in pairs(stairOrig) do
            if p.Parent then pcall(function() p.Transparency = t end) end
        end
        table.clear(stairOrig)
        for p, c in pairs(stairCol) do
            if p.Parent then
                pcall(function()
                    p.CanCollide = c[1]
                    p.CanQuery = c[2]
                end)
            end
        end
        table.clear(stairCol)
    end

    local mapWarned = false
    do
        local HOP_WAIT = 0.25
        local STAGE_WAIT = 2
        local flyGyro, flyVel, flyHum, flyWasPlat = nil, nil, nil, false
        local labOrig = setmetatable({}, { __mode = "k" })
        local labCol = setmetatable({}, { __mode = "k" })
        local removedParts = {}
        local rampPart, rampWas
        local hazards = {}
        local FULL_CIRCLE = { { Angle = 360, Yaw = 0 } }

        local function nodePos(n)
            if n:IsA("BasePart") then return n.Position end
            if n:IsA("Model") then
                local ok, p = pcall(function() return n:GetPivot().Position end)
                return ok and p or nil
            end
        end

        local function findLabNode(def)
            local ground = findPath(workspace, "Map", "Ground")
            if not ground then return nil end
            local kids = ground:GetChildren()
            local function matches(n)
                local pos = n and nodePos(n)
                return pos ~= nil and (pos - def.pos).Magnitude < 0.1
            end
            if matches(kids[def.index]) then return kids[def.index] end
            for _, n in ipairs(kids) do
                if matches(n) then return n end
            end
        end

        local function fadeNode(n)
            local parts = n:IsA("BasePart") and { n } or n:GetDescendants()
            for _, p in ipairs(parts) do
                if p:IsA("BasePart") then
                    if labOrig[p] == nil then labOrig[p] = p.Transparency end
                    if labCol[p] == nil then labCol[p] = { p.CanCollide, p.CanQuery } end
                    p.Transparency = STAIR_TRANSPARENCY
                    p.CanCollide = false
                    p.CanQuery = false
                end
            end
        end

        local function applyLabParts(cfg)
            for _, def in ipairs(cfg.Fade or {}) do
                local n = findLabNode(def)
                if n then fadeNode(n) end
            end
            for _, def in ipairs(cfg.Remove or {}) do
                local n = findLabNode(def)
                if n and n.Parent then
                    removedParts[#removedParts + 1] = { node = n, parent = n.Parent }
                    n.Parent = nil
                end
            end
        end

        local function stopFly()
            if flyGyro then pcall(function() flyGyro:Destroy() end) end
            if flyVel then pcall(function() flyVel:Destroy() end) end
            flyGyro, flyVel = nil, nil
            if flyHum then
                local hum, was = flyHum, flyWasPlat
                pcall(function() hum.PlatformStand = was end)
            end
            flyHum = nil
        end

        local function startFly(ch)
            stopFly()
            local hum = ch:FindFirstChildOfClass("Humanoid")
            local root = ch:FindFirstChild("HumanoidRootPart")
            if not (hum and root) then return end
            flyHum, flyWasPlat = hum, hum.PlatformStand
            hum.PlatformStand = true
            local gyro = Instance.new("BodyGyro")
            gyro.P = 9e4
            gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            gyro.CFrame = realCF(root)
            gyro.Parent = root
            local vel = Instance.new("BodyVelocity")
            vel.Velocity = Vector3.zero
            vel.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            vel.Parent = root
            flyGyro, flyVel = gyro, vel
        end

        local function syncFly(root)
            if flyGyro and flyGyro.Parent then flyGyro.CFrame = realCF(root) end
        end

        Lab.sync = syncFly

        function Lab.restore()
            table.clear(hazards)
            Lab.dodging = false
            stopFly()
            for p, t in pairs(labOrig) do
                if p.Parent then pcall(function() p.Transparency = t end) end
            end
            table.clear(labOrig)
            for p, c in pairs(labCol) do
                if p.Parent then
                    pcall(function()
                        p.CanCollide = c[1]
                        p.CanQuery = c[2]
                    end)
                end
            end
            table.clear(labCol)
            if rampPart then
                if rampPart.Parent then pcall(function() rampPart.CanCollide = rampWas end) end
                rampPart, rampWas = nil, nil
            end
            for i = #removedParts, 1, -1 do
                local r = removedParts[i]
                if r.parent and r.parent.Parent then
                    pcall(function() r.node.Parent = r.parent end)
                end
            end
            table.clear(removedParts)
        end

        function Lab.run(ch, cfg)
            if Lab.busy then return end
            Lab.busy = true
            local my = Lab.token
            task.spawn(function()
                pcall(function()
                    local hum = ch:FindFirstChildOfClass("Humanoid")
                    local root = ch:FindFirstChild("HumanoidRootPart")
                    if not (hum and root) then return end
                    local function valid()
                        return alive() and Lab.token == my and safeActive and LocalPlayer.Character == ch
                            and hum.Health > 0 and root.Parent ~= nil
                    end
                    applyLabParts(cfg)
                    if cfg.Ramp and not rampPart then
                        local ramp = findPath(workspace, "Map", "Ramps", "Part")
                        if ramp and ramp:IsA("BasePart") then
                            rampPart, rampWas = ramp, ramp.CanCollide
                            ramp.CanCollide = false
                        end
                    end
                    for _ = 1, 3 do
                        if cfg.Stage then
                            stopFly()
                            stopNoclip()
                            ch:PivotTo(CFrame.new(cfg.Stage))
                            root.AssemblyLinearVelocity = Vector3.zero
                            root.AssemblyAngularVelocity = Vector3.zero
                            task.wait(STAGE_WAIT)
                            if not valid() then return end
                        end
                        startFly(ch)
                        startNoclip(ch)
                        noclipStep()
                        ch:PivotTo(CFrame.new(cfg.SafeSpot))
                        root.AssemblyLinearVelocity = Vector3.zero
                        syncFly(root)
                        task.wait(0.4)
                        if not valid() then return end
                        if (realCF(root).Position - cfg.SafeSpot).Magnitude <= 10 then break end
                    end
                    syncFly(root)
                    Lab.char = ch
                end)
                if Lab.token == my then Lab.busy = false end
            end)
        end

        function Lab.hop(fn)
            local cfg = MAPS[CONFIG.Map]
            local ch, root = LocalPlayer.Character, getRoot()
            if not (cfg and cfg.AbilityHop and safeActive and not Lab.busy and ch and root and Lab.char == ch) then
                return fn()
            end
            local target = nearestUnits(cfg.SafeSpot, 1)[1]
            if not target then return fn() end
            if Lab.dodging or Lab.covered(cfg.SafeSpot) or Lab.covered(target.Position) then return end
            Lab.busy = true
            pcall(function()
                ch:PivotTo(CFrame.new(target.Position))
                root.AssemblyLinearVelocity = Vector3.zero
                syncFly(root)
                task.wait(HOP_WAIT)
                fn()
                task.wait(0.1)
            end)
            pcall(function()
                ch:PivotTo(CFrame.new(cfg.SafeSpot))
                root.AssemblyLinearVelocity = Vector3.zero
                syncFly(root)
            end)
            Lab.busy = false
        end

        local MARGIN = 3
        local CLEARANCE = 0.1
        local DODGE_DROP = 3
        local DODGE_LEAD = 0.7
        local DODGE_LINGER = 0.6
        local MIN_DWELL = 0.5
        local RETURN_CLEAR = 1.2
        local RINGS = { 8, 12, 16, 22, 30, 40, 52, 66, 80 }
        local lastMove = 0

        local function pad(size) return MARGIN + size * CLEARANCE end

        local function segDist(px, pz, ax, az, bx, bz)
            local dx, dz = bx - ax, bz - az
            local len2 = dx * dx + dz * dz
            local t = len2 > 0 and math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1) or 0
            local cx, cz = ax + dx * t, az + dz * t
            return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
        end

        local function inAoe(h, x, z)
            local dx, dz = x - h.x, z - h.z
            local pattern = h.pattern
            if pattern.Kind == "Rect" then
                local s, c = math.sin(h.yaw), math.cos(h.yaw)
                local along = dx * s + dz * c
                local across = math.abs(dx * c - dz * s)
                return along >= -MARGIN and along <= h.r + pad(h.r) and across <= h.w * 0.5 + pad(h.w)
            end
            local dist = math.sqrt(dx * dx + dz * dz)
            local m = pad(h.r)
            if dist > h.r + m then return false end
            local bearing = math.atan2(dx, dz)
            for _, wedge in ipairs(pattern) do
                if not wedge.Inner or dist >= wedge.Inner * h.r - m then
                    if wedge.Angle >= 360 then return true end
                    local half = math.rad(wedge.Angle) * 0.5 + math.atan2(m, math.max(dist, 0.01))
                    local diff = (bearing - h.yaw - math.rad(wedge.Yaw) + math.pi) % (2 * math.pi) - math.pi
                    if math.abs(diff) <= half then return true end
                end
            end
            return false
        end

        local function inHazard(h, x, z)
            if h.kind == "aoe" then return inAoe(h, x, z) end
            if h.kind == "circle" then
                local dx, dz = x - h.x, z - h.z
                return dx * dx + dz * dz <= (h.r + pad(h.r)) ^ 2
            end
            local pts = h.pts
            local reach = h.w + pad(h.w)
            for i = 1, #pts - 1 do
                if segDist(x, z, pts[i].X, pts[i].Z, pts[i + 1].X, pts[i + 1].Z) <= reach then return true end
            end
            return false
        end

        local function covered(x, z, t, t1)
            t1 = t1 or t
            for _, h in ipairs(hazards) do
                if h.to + DODGE_LINGER > t and (h.from or -math.huge) <= t1 and inHazard(h, x, z) then return true end
            end
            return false
        end

        function Lab.covered(v)
            return covered(v.X, v.Z, workspace:GetServerTimeNow() + 0.6)
        end

        local function addHazard(h)
            local now = workspace:GetServerTimeNow()
            for i = #hazards, 1, -1 do
                if hazards[i].to < now - 1 then table.remove(hazards, i) end
            end
            if h.key then
                for i, x in ipairs(hazards) do
                    if x.key == h.key then
                        hazards[i] = h
                        return
                    end
                end
            end
            hazards[#hazards + 1] = h
        end

        local function findHazard(key)
            for _, x in ipairs(hazards) do
                if x.key == key then return x end
            end
        end

        local function flat(v) return Vector3.new(v.X, 0, v.Z) end

        local function landTime(land, now)
            if type(land) ~= "number" or land < now - 5 or land > now + 30 then return now + 1 end
            return land
        end

        local function onFx(...)
            local cfg = MAPS[CONFIG.Map]
            if not (cfg and cfg.Dodge) then return end
            local a = table.pack(...)
            local effect, attack, data = a[3], a[4], a[5]
            if type(effect) ~= "string" then return end
            local now = workspace:GetServerTimeNow()
            local spot = cfg.SafeSpot
            local isTable = type(data) == "table"

            if effect == "Shot" and isTable and data.At then
                local land = landTime(data.Land, now)
                if attack == "BananaBarrage" then
                    addHazard({ kind = "circle", x = data.At.X, z = data.At.Z, r = data.Radius or 6, from = land - DODGE_LEAD, to = land + 0.25 })
                else
                    addHazard({ kind = "circle", x = data.At.X, z = data.At.Z, r = data.Radius or 8, from = land - DODGE_LEAD, to = land + 0.7 })
                end
            elseif effect == "Residue" and isTable and data.At then
                addHazard({ kind = "circle", x = data.At.X, z = data.At.Z, r = data.Radius or 6, to = (data.Ends or now + 3) + 0.15 })
            elseif effect == "Lock" and attack == "UnstableRush" and isTable and data.At then
                local root = getRoot()
                local from = root and realCF(root).Position or spot
                local dx, dz = from.X - data.At.X, from.Z - data.At.Z
                local m = math.sqrt(dx * dx + dz * dz)
                if m > 0.1 then
                    local a0 = flat(data.At)
                    addHazard({ key = "rush", kind = "line", pts = { a0, a0 + Vector3.new(dx / m, 0, dz / m) * 60 }, w = 18, to = now + 1.9 })
                end
            elseif effect == "Charge" and attack == "UnstableRush" and isTable and data.At and data.Direction then
                local d = flat(data.Direction)
                if d.Magnitude > 0.01 then
                    local a0 = flat(data.At)
                    local cur = findHazard("rush")
                    addHazard({
                        key = "rush", kind = "line", w = math.max(14, cur and cur.w or 0),
                        pts = { a0, a0 + d.Unit * ((data.Distance or 50) + 6) },
                        to = (data.Start or now) + (data.Duration or 0.3) + 0.5,
                    })
                end
            elseif effect == "Acid" and isTable and type(data.Points) == "table" then
                local pts = {}
                for _, pt in ipairs(data.Points) do pts[#pts + 1] = flat(pt) end
                if #pts == 1 then pts[2] = pts[1] end
                if #pts >= 2 then
                    addHazard({ kind = "line", pts = pts, w = (data.Width or 20) / 2 + 1, to = (data.Ends or now + 6) + 0.15 })
                end
            elseif attack == "MutagenHammer" then
                local cur = findHazard("hammer")
                if effect == "Windup" and not (cur and cur.to > now) then
                    addHazard({ key = "hammer", kind = "circle", x = spot.X, z = spot.Z, r = 60, to = now + 6 })
                elseif effect == "Impact" and isTable and data.At then
                    addHazard({ key = "hammer", kind = "circle", x = data.At.X, z = data.At.Z, r = 32, to = cur and cur.to or now + 4 })
                elseif effect == "Recovery" and cur then
                    cur.to = now + 0.4
                end
            elseif attack == "MutagenOverload" then
                local cur = findHazard("overload")
                if effect == "Windup" then
                    addHazard({ key = "overload", kind = "circle", x = spot.X, z = spot.Z, r = 60, to = now + 8 })
                elseif effect == "Recovery" and cur then
                    cur.to = now + 0.4
                end
            end
        end

        local function onAoe(...)
            local cfg = MAPS[CONFIG.Map]
            if not (cfg and cfg.Dodge) then return end
            local a = table.pack(...)
            local now = workspace:GetServerTimeNow()
            if type(a[1]) == "number" then
                local cur = findHazard("aoe" .. a[1])
                if not cur then return end
                if typeof(a[2]) == "Vector3" then
                    cur.x, cur.z = a[2].X, a[2].Z
                    if type(a[3]) == "number" then cur.yaw = a[3] end
                    if type(a[4]) == "number" then cur.r = a[4] end
                else
                    cur.to = math.min(cur.to, now)
                end
                return
            end
            local at, yaw, shape, radius, width = a[1], a[2], a[3], a[4], a[8]
            local pattern = (AoePatterns and AoePatterns.Patterns[shape]) or (shape == "Circle" and FULL_CIRCLE) or nil
            if typeof(at) ~= "Vector3" or type(radius) ~= "number" or not pattern then return end
            if pattern.Kind == "Rect" and type(width) ~= "number" then return end
            local land = landTime(a[5], now)
            addHazard({
                key = type(a[7]) == "number" and "aoe" .. a[7] or nil,
                kind = "aoe", pattern = pattern, x = at.X, z = at.Z,
                yaw = type(yaw) == "number" and yaw or 0, r = radius, w = width,
                from = land - DODGE_LEAD, to = land + 0.3,
            })
        end

        local function free(x, z, t)
            return not covered(x, z, t, t + 1.4)
        end

        local function pickDest(center, pos, t)
            for _, r in ipairs(RINGS) do
                local best, bestD
                for i = 0, 15 do
                    local ang = i * math.pi / 8
                    local x, z = center.X + math.cos(ang) * r, center.Z + math.sin(ang) * r
                    if free(x, z, t) then
                        local d = (x - pos.X) ^ 2 + (z - pos.Z) ^ 2
                        if not bestD or d < bestD then best, bestD = Vector3.new(x, center.Y - DODGE_DROP, z), d end
                    end
                end
                if best then return best end
            end
        end

        local function moveTo(ch, root, pos)
            local spot = getSafeSpot()
            local y = spot and math.min(pos.Y, spot.Y) or pos.Y
            ch:PivotTo(CFrame.new(pos.X, y, pos.Z))
            root.AssemblyLinearVelocity = Vector3.zero
            syncFly(root)
            lastMove = os.clock()
        end

        local semiOff, semiAt = Vector3.zero, 0

        function Lab.serverDodge(pos)
            local cfg = MAPS[CONFIG.Map]
            if not (cfg and cfg.Dodge) then
                semiOff = Vector3.zero
                return semiOff
            end
            local now = workspace:GetServerTimeNow()
            for i = #hazards, 1, -1 do
                if hazards[i].to < now - 1 then table.remove(hazards, i) end
            end
            local t0 = now + LocalPlayer:GetNetworkPing() + SEMI.LeadPad
            local t1 = t0 + SEMI.Window
            local px, pz = pos.X, pos.Z
            local clock = os.clock()
            local limit = SEMI.XZLimit
            local prev = semiOff
            local atHome = prev.X * prev.X + prev.Z * prev.Z < 0.01
            if not covered(px, pz, t0, t1) then
                if atHome then return prev end
                if clock - semiAt >= MIN_DWELL and not covered(px, pz, t0, t0 + RETURN_CLEAR) then
                    semiOff, semiAt = Vector3.zero, clock
                    return semiOff
                end
            end
            if not atHome and not covered(px + prev.X, pz + prev.Z, t0, t1) then
                return prev
            end
            local bx, bz, bestD
            for _, r in ipairs(SEMI.Rings) do
                for i = 0, SEMI.Angles - 1 do
                    local ang = i * 2 * math.pi / SEMI.Angles
                    local ox = math.clamp(math.cos(ang) * r, -limit, limit)
                    local oz = math.clamp(math.sin(ang) * r, -limit, limit)
                    if not covered(px + ox, pz + oz, t0, t1) then
                        local d = (ox - prev.X) ^ 2 + (oz - prev.Z) ^ 2
                        if not bestD or d < bestD then bx, bz, bestD = ox, oz, d end
                    end
                end
            end
            if bx then
                semiOff = Vector3.new(bx, 0, bz)
                semiAt = clock
                return semiOff
            end
            semiOff = Vector3.zero
            return nil
        end

        loop(0.05, function()
            local cfg = MAPS[CONFIG.Map]
            if IN_LOBBY or not (cfg and cfg.Dodge) then return end
            local ch, hum, root = LocalPlayer.Character, getHumanoid(), getRoot()
            if not (safeActive and ch and hum and root and hum.Health > 0 and Lab.char == ch) then
                Lab.dodging = false
                return
            end
            if Lab.busy then return end
            local now = workspace:GetServerTimeNow()
            for i = #hazards, 1, -1 do
                if hazards[i].to < now - 1 then table.remove(hazards, i) end
            end
            local spot, pos = cfg.SafeSpot, realCF(root).Position
            if covered(pos.X, pos.Z, now, now + 0.15) then
                if not Semi.handled then
                    local dest = pickDest(spot, pos, now)
                    if dest then
                        moveTo(ch, root, dest)
                        Lab.dodging = true
                    end
                end
            elseif Lab.dodging and os.clock() - lastMove >= MIN_DWELL
                and not covered(spot.X, spot.Z, now, now + RETURN_CLEAR) then
                moveTo(ch, root, spot)
                Lab.dodging = false
            end
        end)

        local function hookRemote(handler, ...)
            local path = { ... }
            while alive() do
                local r = waitPath(RS, 30, table.unpack(path))
                if not alive() then return end
                if r and r:IsA("RemoteEvent") then
                    conns[#conns + 1] = r.OnClientEvent:Connect(function(...) pcall(handler, ...) end)
                    return
                end
                task.wait(2)
            end
        end

        task.spawn(function()
            if IN_LOBBY then return end
            local cfg = MAPS[CONFIG.Map]
            if not (cfg and cfg.Dodge) then return end
            task.spawn(hookRemote, onFx, "Shared", "Bosses", "Fx")
            hookRemote(onAoe, "Shared", "Effects", "Aoe")
        end)
    end

    local function goSpot()
        local ch, root = LocalPlayer.Character, getRoot()
        if not (ch and root) then return end
        local spot = getSafeSpot()
        if not spot then return end
        local cfg = MAPS[CONFIG.Map]
        if Lab.dodging and Lab.char == ch then return end
        if cfg.Fly and Lab.char ~= ch then
            Lab.run(ch, cfg)
            return
        end
        ch:PivotTo(CFrame.new(spot))
        root.AssemblyLinearVelocity = Vector3.zero
        if Lab.sync then Lab.sync(root) end
        if not cfg.Fly then Lab.char = ch end
    end

    local calmUntil = 0

    local function earlyNoclip(ch)
        local cfg = MAPS[CONFIG.Map]
        if not (cfg and cfg.Fly) then startNoclip(ch) end
    end

    function setSafe(on)
        if on then
            if safeActive then return end
            if not getSafeSpot() then
                if not mapWarned then
                    mapWarned = true
                    notify("Safe Spot", "No Safe Spot is configured for map '" .. tostring(CONFIG.Map) .. "', so it stays off.")
                end
                return
            end
            local ch, root = LocalPlayer.Character, getRoot()
            if not (ch and root) then return end
            local rcf = realCF(root)
            Lab.token = Lab.token + 1
            Lab.busy = false
            safeActive = true
            trackedChar = ch
            origin = rcf.Position.Y >= SAFE_FALL_Y and rcf or nil
            applyStairs()
            earlyNoclip(ch)
            goSpot()
        else
            if not safeActive then return end
            safeActive = false
            Lab.token = Lab.token + 1
            Lab.busy = false
            trackedChar = nil
            Lab.char = nil
            local ch, root, cfg = LocalPlayer.Character, getRoot(), MAPS[CONFIG.Map]
            local back = origin or (cfg and cfg.Stage and CFrame.new(cfg.Stage))
            if ch and root and back then
                ch:PivotTo(back)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
            origin = nil
            calmUntil = os.clock() + 2
            stopNoclip()
            restoreStairs()
            Lab.restore()
        end
    end

    function cleanupSafe()
        pcall(stopNoclip)
        pcall(restoreStairs)
        pcall(Lab.restore)
    end

    conns[#conns + 1] = RunService.Heartbeat:Connect(function()
        if not alive() then return end
        if not safeActive and os.clock() >= calmUntil then return end
        local ch, root, hum = LocalPlayer.Character, getRoot(), getHumanoid()
        if root and (safeActive or os.clock() < calmUntil) then
            local v = root.AssemblyLinearVelocity
            if v.Y > 100 or Vector3.new(v.X, 0, v.Z).Magnitude > 100 then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end
        if not safeActive then return end
        local cfg = MAPS[CONFIG.Map]
        if not (cfg and cfg.Fly and cfg.FloorY and ch and root and hum and hum.Health > 0) then return end
        if realCF(root).Position.Y >= cfg.FloorY then return end
        root.AssemblyLinearVelocity = Vector3.zero
        ch:PivotTo(CFrame.new(cfg.Stage or cfg.SafeSpot))
        if Lab.sync then Lab.sync(root) end
        if Lab.busy then return end
        Lab.char = nil
        Lab.dodging = false
        goSpot()
    end)

    earlyActive = false

    loop(0.1, function()
        if IN_LOBBY then return end
        local ch, hum, root = LocalPlayer.Character, getHumanoid(), getRoot()
        local want = S.SafeSpot and not suspended and settleLeft() <= 0

        if want and not safeActive then
            if hum and root and hum.Health > 0 then setSafe(true) end
            return
        elseif not want and safeActive then
            setSafe(false)
            return
        end
        if not safeActive then return end

        if ch and root and ch ~= trackedChar then
            trackedChar = ch
            earlyNoclip(ch)
            goSpot()
            return
        end
        if Lab.busy or Lab.dodging then return end
        local spot = getSafeSpot()
        if not spot then return end
        if hum and root and hum.Health > 0 then
            local rpos = realCF(root).Position
            if rpos.Y < getFallY() then
                Lab.char = nil
                Lab.dodging = false
                goSpot()
            elseif (rpos - spot).Magnitude > 10 then
                goSpot()
            end
        end
    end)

    conns[#conns + 1] = LocalPlayer.CharacterAdded:Connect(function(ch)
        if not alive() then return end
        Aim.resetIgnore()
        ch:WaitForChild("HumanoidRootPart", 10)
        if not alive() then return end
        if S.SafeSpot and safeActive then
            trackedChar = ch
            earlyNoclip(ch)
            goSpot()
        end
        task.wait(1.5)
        if not alive() then return end
        if S.SafeSpot and safeActive then goSpot() end
        if S.AutoKill and not suspended then equipOnce() end
    end)
end

do
    local toolConns = {}
    local hasToolUsed = false
    local BIND_NAME = "MonkeySemiRestore" .. gen

    local function semiRestore()
        if not Semi.shifted then return end
        Semi.shifted = false
        local root = Semi.root
        if root and root.Parent and (root.CFrame.Position - Semi.moved.Position).Magnitude < 0.01 then
            root.CFrame = Semi.real
        end
    end

    Semi.capable = hookmetamethod ~= nil and newcclosure ~= nil and checkcaller ~= nil

    -- The __index hook sits on every property read in the game, so it is only
    -- installed when the experimental toggle is first turned on (see Semi.setOn).
    local function installHook()
        if env.MonkeySemiHooked then return true end
        local ok = pcall(function()
            local old
            old = hookmetamethod(game, "__index", newcclosure(function(self, key)
                if key == "CFrame" or key == "Position" then
                    local st = env.MonkeySemi
                    if st and st.on and st.shifted and self == st.root and not checkcaller() then
                        local raw = old(self, "CFrame")
                        if (raw.Position - st.moved.Position).Magnitude < 0.01 then
                            if key == "CFrame" then return st.real end
                            return st.real.Position
                        end
                        if key == "CFrame" then return raw end
                        return raw.Position
                    end
                end
                return old(self, key)
            end))
        end)
        env.MonkeySemiHooked = ok
        return ok
    end

    if IN_LOBBY then
        Semi.hookReady = Semi.capable
    elseif Semi.capable and env.MonkeySemiHooked then
        Semi.hookReady = true
    end

    local watchedTools = setmetatable({}, { __mode = "k" })

    local function clearTools()
        for _, c in ipairs(toolConns) do pcall(function() c:Disconnect() end) end
        table.clear(toolConns)
        table.clear(watchedTools)
    end

    local function watchTool(tool)
        if hasToolUsed or watchedTools[tool] or not (tool:IsA("Tool") and tool:FindFirstChild("WeaponConfig")) then return end
        watchedTools[tool] = true
        toolConns[#toolConns + 1] = tool.Activated:Connect(semiRestore)
    end

    local function watchCharacter(ch)
        clearTools()
        Semi.root = nil
        for _, child in ipairs(ch:GetChildren()) do watchTool(child) end
        toolConns[#toolConns + 1] = ch.ChildAdded:Connect(watchTool)
    end

    local function step()
        if not alive() then return end
        if Semi.shifted then
            if os.clock() - Semi.shiftedAt > SEMI.StaleAfter then semiRestore() end
            return
        end
        if not Semi.on then
            Semi.handled = false
            return
        end
        local hum, root = getHumanoid(), getRoot()
        if not (hum and root and hum.Health > 0) or root.Anchored then
            Semi.handled = false
            return
        end
        local rc = root.CFrame
        local rp = rc.Position
        local dodge = Lab.serverDodge(rp)
        Semi.handled = dodge ~= nil
        local clock = os.clock()
        if hum.FloorMaterial ~= Enum.Material.Air then
            local stand = hum.RigType == Enum.HumanoidRigType.R6 and 3 or hum.HipHeight + root.Size.Y / 2
            Semi.groundY = rp.Y - stand
            Semi.groundAt = clock
        elseif clock - Semi.groundAt >= SEMI.RayEvery then
            Semi.groundAt = clock
            Semi.groundY = Aim.ground(rp)
        end
        local oy = Semi.groundY and (Semi.groundY - SEMI.Depth - rp.Y) or -SEMI.Depth
        oy = math.clamp(oy, -SEMI.YLimit, SEMI.YLimit)
        local ox = dodge and math.clamp(dodge.X, -SEMI.XZLimit, SEMI.XZLimit) or 0
        local oz = dodge and math.clamp(dodge.Z, -SEMI.XZLimit, SEMI.XZLimit) or 0
        Semi.root = root
        Semi.real = rc
        Semi.moved = rc + Vector3.new(ox, oy, oz)
        Semi.shiftedAt = clock
        Semi.shifted = true
        root.CFrame = Semi.moved
    end

    if not IN_LOBBY then
        local used = findPath(RS, "GunKit", "Shared", "ToolUsed")
        hasToolUsed = used ~= nil and used:IsA("BindableEvent")
        if hasToolUsed then
            conns[#conns + 1] = used.Event:Connect(semiRestore)
        end
        pcall(function()
            RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.First.Value, semiRestore)
        end)
        conns[#conns + 1] = RunService.Heartbeat:Connect(function()
            pcall(step)
        end)
        conns[#conns + 1] = LocalPlayer.CharacterRemoving:Connect(function()
            semiRestore()
            clearTools()
            Semi.root = nil
            Semi.handled = false
        end)
        conns[#conns + 1] = LocalPlayer.CharacterAdded:Connect(watchCharacter)
        if LocalPlayer.Character then watchCharacter(LocalPlayer.Character) end
    end

    function Semi.setOn(v)
        if v and not Semi.hookReady and Semi.capable and not IN_LOBBY then
            Semi.hookReady = installHook()
        end
        if v and not Semi.hookReady then
            v = false
            if not Semi.warned then
                Semi.warned = true
                notify("Desync Semi Godmode", "This needs hookmetamethod, newcclosure and checkcaller, and the hook could not be installed, so it stays off.")
            end
            if Semi.toggle then pcall(function() Semi.toggle:Set(false) end) end
        end
        Semi.on = v
        if not v then
            semiRestore()
            Semi.handled = false
        end
    end

    function Semi.cleanup()
        Semi.on = false
        semiRestore()
        pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
        clearTools()
        Semi.handled = false
        Semi.toggle = nil
        if env.MonkeySemi == Semi then env.MonkeySemi = nil end
    end
end

local function setAutoSkip(on)
    if settleLeft() > 0 then return end
    local vote = findPath(RS, "Shared", "Waves", "Vote")
    if vote then pcall(function() vote:FireServer("Auto", on) end) end
end

loop(2, function()
    if S.AutoSkip and LocalPlayer:GetAttribute("AutoSkip") ~= true then setAutoSkip(true) end
end)

local Abil = {}
do
    local PLACEMENTS = { Barricade = true }
    local TOOL_AFTER = { Detonator = "Satchel" }

    local abilityIds, toolAbilities, toolOrder = {}, {}, {}
    if Catalog and Catalog.Abilities then
        pcall(function()
            for _, a in Catalog.Abilities.All do
                if type(a.Id) == "string" then
                    local display = type(a.Display) == "table" and a.Display.Name
                    local gameplay = type(a.Gameplay) == "table" and a.Gameplay
                    abilityIds[a.Id:lower()] = a.Id
                    if type(display) == "string" then abilityIds[display:lower()] = a.Id end
                    if gameplay and type(gameplay.Tool) == "string" then
                        toolAbilities[a.Id] = {
                            tool = gameplay.Tool,
                            name = type(display) == "string" and display or a.Id,
                            delay = type(gameplay.DetonateDelay) == "number" and gameplay.DetonateDelay or 0,
                        }
                        toolOrder[#toolOrder + 1] = a.Id
                    end
                end
            end
        end)
        table.sort(toolOrder)
    end

    local SLOTS = {
        ["Ability 1"] = { motion = "Ability1MotionSlot", inner = "Ability1" },
        ["Ability 2"] = { motion = "Ability2MotionSlot", inner = "Ability2" },
        ["Ultimate"] = { motion = "UltimateMotionSlot", inner = "Ultimate", ultimate = true },
    }
    local SLOT_ORDER = { "Ability 1", "Ability 2", "Ultimate" }
    local SKIP_LABELS = { Percentage = true, Cooldown = true, Key = true, Hotkey = true, Keybind = true }

    local function slotRoot(slot)
        local gui = playerGui()
        return gui and findPath(gui, "Game", "RightMenu", slot.motion, slot.inner)
    end

    local function cleanName(text)
        if type(text) ~= "string" then return nil end
        text = text:gsub("^%s+", ""):gsub("%s+$", "")
        if #text < 3 or not text:match("^%a[%a ]*$") then return nil end
        if text == text:upper() then
            text = text:sub(1, 1) .. text:sub(2):lower()
        end
        return text
    end

    local function abilityName(slot)
        local root = slotRoot(slot)
        if not root then return nil end
        local label
        if slot.ultimate then
            label = findPath(root, "Folder", "Label", "AbilityName")
        else
            local kid = root:GetChildren()[4]
            label = kid and kid:FindFirstChild("TextLabel")
        end
        local name = label and label:IsA("TextLabel") and cleanName(label.Text)
        if name then return name end
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("TextLabel") and not SKIP_LABELS[d.Name] then
                local n = cleanName(d.Text)
                if n then return n end
            end
        end
    end

    local function slotReady(slot)
        local root = slotRoot(slot)
        if not root then return false end
        if slot.ultimate then
            local pct = findPath(root, "MeterNumber", "Percentage")
            local n = pct and tonumber(tostring(pct.Text):match("%d+%.?%d*"))
            return n ~= nil and n >= 100
        end
        local overlay = findPath(root, "Frame", "CooldownOverlay")
        if not overlay then return false end
        return (not overlay.Visible) or overlay.AbsoluteSize.Y < 1
    end

    local function abilityId(label)
        local squeezed = label:gsub("%s", "")
        return abilityIds[label:lower()] or abilityIds[squeezed:lower()] or squeezed
    end

    local function useAbility(name)
        local id = abilityId(name)
        if PLACEMENTS[name] then
            local place = findPath(RS, "Shared", "Placements", "Place")
            if place then place:FireServer(name, 0) end
        else
            local use = findPath(RS, "Shared", "Abilities", "Use")
            if use then use:FireServer(id) end
        end
        return id
    end

    local keyByName, lastSignature = {}, nil

    local function refreshAbilityOptions()
        local options, map = {}, {}
        for _, key in ipairs(SLOT_ORDER) do
            local name = abilityName(SLOTS[key])
            if name and not map[name] then
                options[#options + 1] = name
                map[name] = key
            end
        end
        for _, id in ipairs(toolOrder) do
            local info = toolAbilities[id]
            if not map[info.name] and (S.Abilities[id] or inventoryTool(info.tool)) then
                options[#options + 1] = info.name
                map[info.name] = id
            end
        end
        local signature = table.concat(options, "|")
        if signature == lastSignature then return options end
        lastSignature = signature
        keyByName = map
        if abilityDropdown then
            local keep = {}
            for name, key in pairs(map) do
                if S.Abilities[key] then keep[#keep + 1] = name end
            end
            abilityDropdown:Refresh(options)
            abilityDropdown:Set(keep)
        end
        return options
    end

    loop(2, refreshAbilityOptions)

    local lastUse, placed = {}, {}

    local function useSlot(key)
        local slot = SLOTS[key]
        if os.clock() - (lastUse[key] or 0) <= 1.5 or not slotReady(slot) then return end
        local name = abilityName(slot)
        if not name then return end
        Lab.hop(function()
            local id = useAbility(name)
            local now = os.clock()
            lastUse[key] = now
            placed[id] = now
        end)
    end

    local function useToolAbility(id)
        local info, after = toolAbilities[id], TOOL_AFTER[id]
        local now = os.clock()
        if not info or now - (lastUse[id] or 0) <= 1.5 then return end
        if after and (placed[after] or 0) <= (lastUse[id] or 0) then return end
        local tool = inventoryTool(info.tool)
        if not tool then return end
        lastUse[id] = now
        activateTool(tool, info.delay)
    end

    loop(0.4, function()
        if next(S.Abilities) == nil or settleLeft() > 0 or toolBusy then return end
        local hum = getHumanoid()
        if not hum or hum.Health <= 0 then return end
        for _, key in ipairs(SLOT_ORDER) do
            if S.Abilities[key] then pcall(useSlot, key) end
        end
        for _, id in ipairs(toolOrder) do
            if S.Abilities[id] then pcall(useToolAbility, id) end
        end
    end)

    Abil.refresh = refreshAbilityOptions

    function Abil.select(names)
        local available, set = {}, {}
        for _, key in pairs(keyByName) do available[key] = true end
        for _, name in ipairs(names) do
            local key = keyByName[name]
            if key then set[key] = true end
        end
        for key, on in pairs(S.Abilities) do
            if on and not available[key] then set[key] = true end
        end
        S.Abilities = set
    end

    function Abil.resetSignature()
        lastSignature = nil
    end

    function Abil.clear()
        table.clear(lastUse)
        table.clear(placed)
    end
end

local MULT = { K = 1e3, M = 1e6, B = 1e9, T = 1e12 }

local function parseAmount(text)
    if type(text) ~= "string" then return nil end
    local num, suf = text:match("%$%s*([%d,%.]+)([KkMmBbTt]?)")
    if not num then num, suf = text:match("([%d,%.]+)([KkMmBbTt]?)") end
    if not num then return nil end
    local n = tonumber((num:gsub(",", "")))
    if not n then return nil end
    return n * (MULT[(suf or ""):upper()] or 1)
end

local function readAmount(path)
    local gui = playerGui()
    local label = gui and findPath(gui, table.unpack(path))
    return label and parseAmount(label.Text)
end

local CASH_PATH = { "Game", "CashContainer", "Background", "Amount" }
local COST_PATH = {
    Weapon = { "Game", "LeftMenu", "WeaponMotionSlot", "Weapon", "Frame", "Cost" },
    Health = { "Game", "LeftMenu", "HealthMotionSlot", "Health", "Frame", "Cost" },
}
local UPGRADE_KINDS = { "Weapon", "Health" }

local function readCash()
    local c = LocalPlayer:GetAttribute("Cash")
    if type(c) == "number" then return c end
    return readAmount(CASH_PATH)
end

loop(0.3, function()
    if next(S.Upgrades) == nil or settleLeft() > 0 then return end
    local remote = findPath(RS, "Remotes", "UpgradeRequest")
    if not remote then return end
    for _, kind in ipairs(UPGRADE_KINDS) do
        if S.Upgrades[kind] then
            local have, cost = readCash(), readAmount(COST_PATH[kind])
            if have and cost and cost > 0 and have >= cost then
                remote:FireServer(kind)
                task.wait(0.5)
            end
        end
    end
end)

local queueWarned = false

local function queueReexec()
    if env.MonkeyQueuedJob == game.JobId then return end
    local queue = queue_on_teleport or queueonteleport
        or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
    if not queue then
        if not queueWarned then
            queueWarned = true
            notify("Autofarm", "Your executor has no queue_on_teleport, so Autofarm cannot restart itself after a teleport.")
        end
        return
    end
    local base = CONFIG.SourceURL
    if type(base) ~= "string" or not base:match("^https?://") then
        if not queueWarned then
            queueWarned = true
            notify("Autofarm", "CONFIG.SourceURL is not set, so Autofarm cannot restart itself after a teleport.")
        end
        return
    end
    local url = base .. (base:find("?", 1, true) and "&cb=" or "?cb=") .. tostring(os.time())
    local src = string.format([[
local u = %q
local ok, s = pcall(function() return game:HttpGet(u) end)
if not ok or type(s) ~= "string" or #s == 0 then
    s = nil
    local req = request or http_request or (syn and syn.request) or (fluxus and fluxus.request)
    local ok2, r = pcall(function() return req and req({ Url = u, Method = "GET" }) end)
    if ok2 and type(r) == "table" and type(r.Body) == "string" and #r.Body > 0
        and (type(r.StatusCode) ~= "number" or (r.StatusCode >= 200 and r.StatusCode < 300)) then
        s = r.Body
    end
end
if not s then return warn("[Monkey] re-exec download failed: " .. u) end
local fn, err = loadstring(s)
if not fn then return warn("[Monkey] re-exec compile failed: " .. tostring(err)) end
fn()
]], url)
    if pcall(queue, src) then
        env.MonkeyQueuedJob = game.JobId
    elseif not queueWarned then
        queueWarned = true
        notify("Autofarm", "Could not queue the script for the next teleport.")
    end
end

local function clickButton(btn)
    for _, name in ipairs({ "Activated", "MouseButton1Click" }) do
        local sig = btn[name]
        if firesignal then
            pcall(firesignal, sig)
        elseif getconnections then
            for _, c in ipairs(getconnections(sig)) do pcall(function() c:Fire() end) end
        end
    end
end

local function lobbyHitbox(l)
    local hb = l:FindFirstChild("LobbyHitbox", true)
    return hb and hb:IsA("BasePart") and hb or nil
end

local function lobbyPos(l)
    local hb = lobbyHitbox(l)
    if hb then return hb.Position end
    if l:IsA("BasePart") then return l.Position end
    if l:IsA("Model") then return l:GetPivot().Position end
    local part = l:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position
end

local function emptyLobbies()
    local folder = workspace:FindFirstChild("Lobbies")
    local out = {}
    for _, l in ipairs(folder and folder:GetChildren() or {}) do
        local label = findPath(l, "Attachment", "BillboardGui", "Frame", "PlayerCount")
        local text = label and label:IsA("TextLabel") and label.Text
        if text and text:match("^%s*0%s*/") then out[#out + 1] = l end
    end
    table.sort(out, function(a, b) return a.Name < b.Name end)
    return out
end

local function enterLobby(lobby)
    local ch, root, pos = LocalPlayer.Character, getRoot(), lobbyPos(lobby)
    if not (ch and root and pos) then return end
    ch:PivotTo(CFrame.new(pos + Vector3.new(0, 1, 0)))
    root.AssemblyLinearVelocity = Vector3.zero
end

local function pokeLobby(lobby)
    local root = getRoot()
    if not root then return end
    local nodes = lobby:GetDescendants()
    nodes[#nodes + 1] = lobby
    for _, d in ipairs(nodes) do
        if fireproximityprompt and d:IsA("ProximityPrompt") then pcall(fireproximityprompt, d) end
        if firetouchinterest and d:IsA("BasePart") and d:FindFirstChildOfClass("TouchInterest") then
            pcall(firetouchinterest, root, d, 0)
        end
    end
end

local afStatus = "Autofarm off"

local function sendCreate(request, difficulty)
    request:FireServer("Create", {
        Map = CONFIG.Map, Difficulty = difficulty, Access = "Public", MaxPlayers = 1,
    })
end

local function startRun()
    local remotes = RS:WaitForChild("Remotes", 20)
    local request = remotes and remotes:WaitForChild("LobbyRequest", 10)
    local lobbyState = remotes and remotes:WaitForChild("LobbyState", 10)
    local lobbies = workspace:WaitForChild("Lobbies", 20)
    if not (request and lobbyState and lobbies and getRoot()) then
        afStatus = "Waiting for the lobby to load"
        return
    end

    local configuring
    local conn = lobbyState.OnClientEvent:Connect(function(kind, a)
        if kind == "HostConfiguring" then configuring = a end
    end)

    local function waitConfiguring(seconds)
        local t0 = os.clock()
        while not configuring and os.clock() - t0 < seconds do task.wait(0.1) end
        return configuring
    end

    local function tryCreate(difficulty)
        for _ = 1, 2 do
            if not (S.Autofarm and alive()) then return end
            sendCreate(request, difficulty)
            task.wait(5)
        end
    end

    pcall(function()
        local list = emptyLobbies()
        if #list == 0 then afStatus = "No empty lobby, waiting" end
        for _, lobby in ipairs(list) do
            if not (S.Autofarm and alive()) then break end
            afStatus = "Joining " .. lobby.Name
            configuring = nil
            enterLobby(lobby)
            if not waitConfiguring(3) then
                pokeLobby(lobby)
                waitConfiguring(3)
            end

            if configuring then
                afStatus = "Lobby open, creating"
                task.wait(1.2)
                local pos, root, hb = lobbyPos(lobby), getRoot(), lobbyHitbox(lobby)
                local reach = hb and (math.max(hb.Size.X, hb.Size.Z) / 2 + 4) or 12
                if pos and root and (realCF(root).Position - pos).Magnitude > reach then
                    enterLobby(lobby)
                    task.wait(0.5)
                end

                if state.map ~= CONFIG.Map then
                    state.map = CONFIG.Map
                    saveState()
                end
                queueReexec()

                local want = S.Difficulty
                if want == "Hardcore" and state.hardcoreFailed then want = "Normal" end
                afStatus = "Creating (" .. want .. ")"
                tryCreate(want)
                if want == "Hardcore" and S.Autofarm and alive() then
                    state.hardcoreFailed = true
                    saveState()
                    afStatus = "Creating (Normal)"
                    tryCreate("Normal")
                end
            end
        end
    end)

    conn:Disconnect()
end

local function applyAutofarmDefaults()
    S.AutoKill = true
    S.SafeSpot = true
    S.AutoSkip = state.autoSkipOff ~= true
    S.Upgrades.Weapon = true
    if not IN_LOBBY then
        equipOnce()
        setAutoSkip(S.AutoSkip)
    end
end

local function stopFeatures()
    S.AutoKill, S.SafeSpot, S.AutoSkip = false, false, false
    release()
    pcall(setAutoSkip, false)
    pcall(setSafe, false)
    syncUI()
end

local resetWatch, statusLabel
do
    local OUT_OF_MAP_Y = -100
    local STALL_TIMEOUT = 50
    local BOSS_STALL_TIMEOUT = 240
    local HEARTBEAT_SAVE = 30
    local REPLAY_DELAY = 8
    local NEWRUN_FALLBACK = 10

    local function currentWave()
        local waves = findPath(RS, "Shared", "Waves")
        local n = waves and waves:GetAttribute("Number")
        if type(n) == "number" and n > 0 then return n end
        local gui = playerGui()
        local label = gui and findPath(gui, "Game", "Top", "NextWave", "Countdown", "TextLabel")
        local m = label and tostring(label.Text):upper():match("^%s*WAVE%s+(%d+)")
        return m and tonumber(m)
    end

    local function bossBarPct()
        local gui = playerGui()
        local label = gui and findPath(gui, "Game", "BossHealthBar", "Backdrop", "BarBackground", "HealthShadow", "Health")
        if not (label and label:IsA("TextLabel")) then return nil end
        local node = label
        while node and node ~= gui do
            if node:IsA("GuiObject") and not node.Visible then return nil end
            if node:IsA("ScreenGui") and not node.Enabled then return nil end
            node = node.Parent
        end
        local m = tostring(label.Text):match("([%d%.]+)%s*%%")
        return m and tonumber(m) or nil
    end

    local finishing, ended, finishAt = false, false, 0
    local selfReason
    local endedAt, lastReplay, firstReplayAt = 0, 0, 0
    local endedChar, endedWave, staleWave, lastWaveSeen = nil, nil, nil, nil
    local deadAttrStale, skipAsserted = false, false
    local stallAt, stallStage, lastCash, lastWave, lastBoss, lastBossProg = os.clock(), 0, nil, nil, nil, nil
    local noCharSince, lastRejoin = nil, -math.huge
    local runCounter, appliedRun = 0, nil

    function resetWatch()
        stallAt, stallStage, lastCash, lastWave, lastBoss, lastBossProg, noCharSince = os.clock(), 0, nil, nil, nil, nil, nil
    end

    local function rejoinLobby()
        local now = os.clock()
        if now - lastRejoin < 20 then return end
        lastRejoin = now
        afStatus = "Stuck, returning to the lobby"
        queueReexec()
        local ok = pcall(function() TeleportService:Teleport(CONFIG.LobbyPlace, LocalPlayer) end)
        if not ok then afStatus = "Teleport to the lobby failed" end
    end

    local function fireReplay(now)
        if now - lastReplay < 4 then return end
        lastReplay = now
        if firstReplayAt == 0 then firstReplayAt = now end
        local action = findPath(RS, "Remotes", "GameAction")
        if action then pcall(function() action:FireServer("Replay") end) end
    end

    local function finishRun()
        suspended = true
        release()
        pcall(setSafe, false)
        local ch = LocalPlayer.Character
        local deathSpot = getDeathSpot()
        if ch and deathSpot then
            ch:PivotTo(CFrame.new(deathSpot))
        else
            local hum = getHumanoid()
            if hum then hum.Health = 0 end
        end
    end

    local function watchProgress(hum, wave, now)
        if not S.AutoKill then
            stallAt, stallStage = now, 0
            return
        end
        local cash = readCash()
        if cash == nil and wave == nil then
            stallAt, stallStage = now, 0
            return
        end
        local boss = bossBarPct()
        local waves = findPath(RS, "Shared", "Waves")
        local bprog = waves and waves:GetAttribute("BossProgress")
        if cash ~= lastCash or wave ~= lastWave or boss ~= lastBoss or bprog ~= lastBossProg then
            lastCash, lastWave, lastBoss, lastBossProg, stallAt, stallStage = cash, wave, boss, bprog, now, 0
            return
        end
        local bossAlive = boss ~= nil or (type(bprog) == "number" and bprog >= 1)
        local base = bossAlive and BOSS_STALL_TIMEOUT or STALL_TIMEOUT
        local limit = stallStage == 0 and base or base / 2
        if now - stallAt < limit then return end
        if stallStage == 0 then
            stallStage, stallAt = 1, now
            afStatus = "Stalled, restarting the run"
            selfReason = "stalled"
            hum.Health = 0
        else
            rejoinLobby()
        end
    end

    local function gameOverRevealed(gui)
        local g = gui and findPath(gui, "End", "GameOver")
        if not g then return false end
        local ok, r = pcall(function()
            return g.Visible and g.GroupTransparency == 0 and g.Parent.Enabled
        end)
        return ok and r == true
    end

    local function gameOverShown(gui)
        local g = gui and findPath(gui, "End", "GameOver")
        if not g then return false end
        local ok, r = pcall(function()
            local screen = g.Parent
            if screen and screen:IsA("ScreenGui") and not screen.Enabled then return false end
            if g:IsA("GuiObject") and not g.Visible then return false end
            if g:IsA("CanvasGroup") and g.GroupTransparency >= 1 then return false end
            return true
        end)
        return ok and r == true
    end

    local function newRunSignal(hum, root, ch, wave, now, shown)
        if firstReplayAt == 0 then return nil end
        if not (hum and root and hum.Health > 0) then return nil end
        if shown then return nil end
        local novel = ch ~= endedChar
            or (wave ~= nil and endedWave ~= nil and wave < endedWave)
        if novel and LocalPlayer:GetAttribute("Dead") ~= true then return "signals" end
        if now - firstReplayAt >= NEWRUN_FALLBACK then return "timeout" end
        return nil
    end

    local function matchStep()
        local hum, root, gui = getHumanoid(), getRoot(), playerGui()
        local ch = LocalPlayer.Character
        local now = os.clock()
        local revealed = gameOverRevealed(gui)
        local shown = revealed or gameOverShown(gui)
        local deadAttr = LocalPlayer:GetAttribute("Dead") == true
        if not deadAttr then deadAttrStale = false end
        local isDead = (deadAttr and not deadAttrStale) or (hum ~= nil and hum.Health <= 0)
        local wave = currentWave()
        if wave and not ended then lastWaveSeen = wave end

        if not ended then
            if revealed or isDead then
                local reason = selfReason or (revealed and "game over screen" or "player died")
                selfReason = nil
                state.lastEnd = string.format("%s | wave %s | stop wave %s", reason, tostring(wave or lastWaveSeen), tostring(S.StopWave))
                saveState()
                notify("Run ended", state.lastEnd)
                ended, endedAt, lastReplay, firstReplayAt = true, now, 0, 0
                endedChar, endedWave = ch, wave or lastWaveSeen
                suspended = true
                release()
            end
        else
            local via = newRunSignal(hum, root, ch, wave, now, shown)
            if via then
                ended, finishing, finishAt = false, false, 0
                suspended = false
                Lab.settleFrom = now
                runCounter = runCounter + 1
                staleWave = endedWave
                deadAttrStale = deadAttr
                skipAsserted = false
                Aim.resetTarget()
                resetWatch()
            end
        end

        if ended then
            queueReexec()
            local waited = now - endedAt
            if waited < REPLAY_DELAY then
                afStatus = string.format("Run over, collecting rewards (%ds)", math.ceil(REPLAY_DELAY - waited))
            elseif not revealed and waited < REPLAY_DELAY + 7 then
                afStatus = "Waiting for the results screen"
            elseif S.NextMap ~= CONFIG.Map then
                afStatus = "Map changed, returning to the lobby"
                local btn = gui and findPath(gui, "Overview", "Lobby")
                if btn then clickButton(btn) end
                if waited > 20 then rejoinLobby() end
            elseif waited > 60 then
                rejoinLobby()
            elseif waited > 30 then
                afStatus = "Replay failed, going back to the lobby"
                local btn = gui and findPath(gui, "Overview", "Lobby")
                if btn then clickButton(btn) end
            else
                afStatus = "Run over, replaying"
                fireReplay(now)
            end
            return
        end

        if not (hum and root) then
            noCharSince = noCharSince or now
            local gap = now - noCharSince
            if gap > 45 then
                rejoinLobby()
            elseif gap > 15 then
                afStatus = "No character, replaying"
                fireReplay(now)
            else
                afStatus = "Waiting for the character"
            end
            return
        end
        noCharSince = nil

        local left = settleLeft()
        if left > 0 then
            afStatus = string.format("Waiting for the cutscene (%ds)", math.ceil(left))
            stallAt, stallStage = now, 0
            return
        end

        if realCF(root).Position.Y < OUT_OF_MAP_Y then
            afStatus = "Out of the map, restarting the run"
            selfReason = "out of map"
            hum.Health = 0
            return
        end

        local trusted = wave
        if wave and staleWave then
            if wave == staleWave then trusted = nil else staleWave = nil end
        end
        if trusted and not skipAsserted then
            skipAsserted = true
            if S.AutoSkip then setAutoSkip(true) end
        end

        if not finishing then
            afStatus = string.format("Wave %s / %d", wave and tostring(wave) or "?", S.StopWave)
            local b = bossBarPct()
            if type(b) == "number" then
                afStatus = afStatus .. (b >= 0 and string.format(" | Boss %d%%", math.floor(b)) or " | Boss")
            end
            if trusted and trusted >= S.StopWave then
                finishing, finishAt = true, now
                selfReason = "reached stop wave"
                finishRun()
                return
            end
            watchProgress(hum, wave, now)
            return
        end

        afStatus = "Reached wave " .. S.StopWave .. ", dying"
        local deathSpot = getDeathSpot()
        if deathSpot then
            if (realCF(root).Position - deathSpot).Magnitude > 15 then
                LocalPlayer.Character:PivotTo(CFrame.new(deathSpot))
            end
        else
            hum.Health = 0
        end
        if now - finishAt > 25 then hum.Health = 0 end
    end

    local starting, lastStatus = false, nil

    loop(1, function()
        if S.Autofarm then
            if os.time() - (state.autofarmAt or 0) >= HEARTBEAT_SAVE then persistAutofarm(true) end
            if IN_LOBBY then
                if not starting then
                    starting = true
                    task.spawn(function()
                        local ok, err = pcall(startRun)
                        if not ok then
                            afStatus = "Lobby step failed, retrying"
                            if env.MonkeyDebug == true then warn("[Monkey] startRun error:", err) end
                        end
                        task.wait(5)
                        starting = false
                    end)
                end
            else
                matchStep()
            end
        else
            afStatus = "Autofarm off"
            ended, finishing, suspended = false, false, false
        end
        if statusLabel and afStatus ~= lastStatus then
            lastStatus = afStatus
            pcall(function() statusLabel:Set("Status: " .. afStatus) end)
        end
    end)

    local function runReady()
        if IN_LOBBY then return true end
        if ended or finishing or suspended or settleLeft() > 0 then return false end
        local hum, root = getHumanoid(), getRoot()
        return hum ~= nil and root ~= nil and hum.Health > 0
    end

    local initFails = 0
    loop(0.25, function()
        if not S.Autofarm then
            appliedRun, initFails = nil, 0
            return
        end
        if runCounter == appliedRun then return end
        if not runReady() then return end
        if not pcall(applyAutofarmDefaults) then
            initFails = initFails + 1
            if initFails < 20 then return end
        end
        appliedRun, initFails = runCounter, 0
        syncUI()
    end)
end

conns[#conns + 1] = LocalPlayer.Idled:Connect(function()
    if not alive() then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    pcall(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), cam.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), cam.CFrame)
    end)
end)

env.MonkeyCleanup = function()
    env.MonkeyGen = (env.MonkeyGen or 0) + 1
    env.MonkeyAim = nil
    S.AutoKill, S.AutoSkip, S.Autofarm, S.SafeSpot = false, false, false, false
    S.Upgrades, S.Abilities = {}, {}
    pcall(setAutoSkip, false)
    release()
    pcall(Semi.cleanup)
    pcall(setSafe, false)
    cleanupSafe()
    Lab.char = nil
    toolBusy = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(conns)
    Aim.clear()
    Abil.clear()
    if toggleGui then pcall(function() toggleGui:Destroy() end) end
    if Rayfield then pcall(function() Rayfield:Destroy() end) end
    env.MonkeyCleanup = nil
end

if RESUMING then
    S.Autofarm = true
    env.MonkeyAutofarm = true
    applyAutofarmDefaults()
end

local function loadRayfield()
    for _ = 1, 3 do
        local ok, result = pcall(function()
            local body = httpGet("https://sirius.menu/rayfield")
            local fn = body and loadstring(body)
            return fn and fn()
        end)
        if ok and type(result) == "table" then return result end
        if not alive() then return nil end
        task.wait(2)
    end
end

local lib = loadRayfield()
if not lib then
    if alive() then
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "Survive a Million Monkeys",
                Text = "Could not load the UI library. Autofarm still runs; re-run the script to get the menu back.",
                Duration = 8,
            })
        end)
    end
    return
end
Rayfield = lib

local initialOptions = Abil.refresh()
if not IN_LOBBY then
    local deadline = os.clock() + 6
    while alive() and #initialOptions == 0 and os.clock() < deadline do
        task.wait(0.5)
        Abil.resetSignature()
        initialOptions = Abil.refresh()
    end
end
if not alive() then
    pcall(function() Rayfield:Destroy() end)
    return
end
if #initialOptions == 0 then initialOptions = { "Waiting for abilities" } end

do
    local Window = Rayfield:CreateWindow({
        Name = "Survive a Million Monkeys",
        LoadingTitle = "Survive a Million Monkeys",
        LoadingSubtitle = "youtube.com/@robloxvibecoder",
        ShowText = "Monkey Menu",
        ToggleUIKeybind = "K",
        ConfigurationSaving = { Enabled = true, FolderName = "MonkeyHorde", FileName = "Config" },
        KeySystem = false,
    })

    local Combat = Window:CreateTab("Combat", 4483362458)
    killToggle = Combat:CreateToggle({
        Name = "Auto Kill Monkeys", CurrentValue = S.AutoKill,
        Callback = function(v)
            S.AutoKill = v
            if v then
                if not IN_LOBBY then equipOnce() end
            else
                release()
            end
        end,
    })
    safeToggle = Combat:CreateToggle({
        Name = "Safe Spot", CurrentValue = S.SafeSpot,
        Callback = function(v)
            S.SafeSpot = v
        end,
    })
    skipToggle = Combat:CreateToggle({
        Name = "Auto Skip Wave", CurrentValue = S.AutoSkip,
        Callback = function(v)
            if uiReady and not syncing and S.Autofarm and v ~= S.AutoSkip then
                state.autoSkipOff = not v
                saveState()
            end
            S.AutoSkip = v
            if not IN_LOBBY then setAutoSkip(v) end
        end,
    })
    abilityDropdown = Combat:CreateDropdown({
        Name = "Auto Use Abilities",
        Options = initialOptions,
        CurrentOption = {},
        MultipleOptions = true,
        Flag = "AutoAbilities",
        Callback = function(opt)
            Abil.select(toList(opt))
        end,
    })

    local Upgrades = Window:CreateTab("Upgrades", 4483362458)
    upgradeDropdown = Upgrades:CreateDropdown({
        Name = "Auto Upgrade",
        Options = UPGRADE_KINDS,
        CurrentOption = {},
        MultipleOptions = true,
        Flag = "AutoUpgrade",
        Callback = function(opt)
            local set = {}
            for _, name in ipairs(toList(opt)) do set[name] = true end
            S.Upgrades = set
        end,
    })

    local Autofarm = Window:CreateTab("Autofarm", 4483362458)
    autofarmToggle = Autofarm:CreateToggle({
        Name = "Autofarm Toggle", CurrentValue = S.Autofarm,
        Callback = function(v)
            S.Autofarm = v
            env.MonkeyAutofarm = v
            if uiReady then persistAutofarm(v) end
            if v then
                resetWatch()
                queueReexec()
                if uiReady then
                    applyAutofarmDefaults()
                    syncUI()
                end
            elseif uiReady then
                stopFeatures()
            end
        end,
    })
    local mapOptions = {}
    for name in pairs(MAPS) do mapOptions[#mapOptions + 1] = name end
    table.sort(mapOptions)
    mapDropdown = Autofarm:CreateDropdown({
        Name = "Map",
        Options = mapOptions,
        CurrentOption = { S.NextMap },
        MultipleOptions = false,
        Callback = function(opt)
            local name = toList(opt)[1]
            if not MAPS[name] or name == S.NextMap then return end
            S.NextMap = name
            state.map = name
            saveState()
            if IN_LOBBY then CONFIG.Map = name end
        end,
    })
    Autofarm:CreateDropdown({
        Name = "Difficulty",
        Options = { "Normal", "Hardcore" },
        CurrentOption = { "Normal" },
        MultipleOptions = false,
        Flag = "AutofarmDifficulty",
        Callback = function(opt)
            local name = toList(opt)[1]
            if name ~= "Normal" and name ~= "Hardcore" then return end
            if uiReady and name ~= S.Difficulty and state.hardcoreFailed then
                state.hardcoreFailed = nil
                saveState()
            end
            S.Difficulty = name
        end,
    })
    Autofarm:CreateInput({
        Name = "Stop at wave",
        CurrentValue = tostring(S.StopWave),
        PlaceholderText = "Type a wave number",
        RemoveTextAfterFocusLost = false,
        Flag = "StopWaveInput",
        Callback = function(text)
            local n = tonumber(text)
            if n and n >= 1 then
                S.StopWave = math.floor(n)
                state.stopWave, env.MonkeyStopWave = S.StopWave, S.StopWave
                saveState()
            end
        end,
    })
    statusLabel = Autofarm:CreateLabel("Status: " .. afStatus)

    local Misc = Window:CreateTab("Misc", 4483362458)
    Misc:CreateLabel("YouTube: @robloxvibecoder")
    Misc:CreateLabel("Script version: v" .. VERSION)
    Semi.toggle = Misc:CreateToggle({
        Name = " (EXPERIMENTAL) Desync Semi Godmode", CurrentValue = false,
        Callback = function(v)
            Semi.setOn(v)
        end,
    })
    Misc:CreateButton({
        Name = "Unload Script",
        Callback = function()
            persistAutofarm(false)
            env.MonkeyAutofarm = false
            if env.MonkeyCleanup then env.MonkeyCleanup() end
        end,
    })
end

do
    local function parentGui(gui)
        local candidates = {
            function() return gethui and gethui() end,
            function() return game:GetService("CoreGui") end,
            function() return playerGui() end,
        }
        for _, get in ipairs(candidates) do
            local ok = pcall(function()
                local p = get()
                if p then gui.Parent = p end
            end)
            if ok and gui.Parent then return true end
        end
        return false
    end

    toggleGui = Instance.new("ScreenGui")
    toggleGui.Name = "MonkeyToggle"
    toggleGui.ResetOnSpawn = false
    toggleGui.DisplayOrder = 999

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(90, 36)
    btn.Position = UDim2.new(0, 10, 0.5, 0)
    btn.Text = "Menu"
    btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Parent = toggleGui
    btn.Activated:Connect(function()
        pcall(function() Rayfield:SetVisibility(not Rayfield:IsVisible()) end)
    end)

    if not parentGui(toggleGui) then
        pcall(function() toggleGui:Destroy() end)
        toggleGui = nil
    end
end

loop(1, function()
    if not (Rayfield and uiReady) or os.clock() < uiTrackAt then return end
    local ok, vis = pcall(function() return Rayfield:IsVisible() end)
    if ok and type(vis) == "boolean" and (state.uiHidden == true) == vis then
        state.uiHidden = not vis
        saveState()
    end
end)

pcall(function() Rayfield:LoadConfiguration() end)
task.delay(3, function()
    if not alive() then return end
    uiReady = true
    if state.uiHidden then pcall(function() Rayfield:SetVisibility(false) end) end
    uiTrackAt = os.clock() + 2
    do
        local checks = {
            { "writefile", writefile ~= nil },
            { "queue_on_teleport", (queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)) ~= nil },
            { "firesignal/getconnections", (firesignal or getconnections) ~= nil },
            { "gethui", gethui ~= nil },
        }
        local missing = {}
        for _, c in ipairs(checks) do
            if not c[2] then missing[#missing + 1] = c[1] end
        end
        local exec = identifyexecutor and identifyexecutor() or "unknown"
        if #missing > 0 then
            notify("Executor: " .. tostring(exec), "Missing: " .. table.concat(missing, ", "))
        end
    end
    if not IN_LOBBY and not GunRig then
        notify("Auto Kill", "The weapon module was not found, so Auto Kill cannot fire.")
    end
    if RESUMING then
        notify("Autofarm resumed", "Auto Kill, Safe Spot" .. (S.AutoSkip and ", Auto Skip" or "") .. " enabled")
    end
    if S.Autofarm then
        applyAutofarmDefaults()
        pcall(function() autofarmToggle:Set(true) end)
        syncUI()
    end
end)