local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

do
    local previous = (getgenv and getgenv() or _G).AeryTASRecorder
    if type(previous) == "table" and previous.Unloaded ~= true and type(previous.hasUnsavedRun) == "function" and previous.hasUnsavedRun() then
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", { Title = "AeryTAS", Text = "AeryTAS is already open and its run isn't saved. Save it or close AeryTAS first.", Duration = 6 })
        end)
        return
    end
end

local Linoria, LinoriaOptions = (function()
    local env = getgenv()
    local saved = { env.Library, env.Toggles, env.Options }
    local ok, library, options = pcall(function()
        local source = game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/1be38aa599bb1f6a7c28f47e6fc13ade52dd0acd/Library.lua")
        local first = source:find("            task.spawn(function()\n                -- TODO: add cursor fade?", 1, true)
        local last = first and select(2, source:find("                CursorOutline:Remove();\n            end);", first, true))
        if not last then
            error("unexpected library source")
        end
        source = source:sub(1, first - 1) .. source:sub(last + 1)
        return loadstring(source, "=Linoria")(), env.Options
    end)
    env.Library, env.Toggles, env.Options = saved[1], saved[2], saved[3]
    if not ok or type(library) ~= "table" then
        error("Couldn't load the Linoria UI library (" .. tostring(library) .. ")")
    end
    return library, options
end)()

local Library = { Unloaded = false, Toggled = true, unloadCallbacks = {}, hasUnsavedRun = function()
    return false
end }
local Options, Toggles = HttpService:JSONDecode("{}"), HttpService:JSONDecode("{}")

function Library:OnUnload(callback)
    table.insert(self.unloadCallbacks, callback)
end

function Library:Unload()
    if self.Unloaded then
        return
    end
    self.Unloaded = true
    for _, callback in ipairs(self.unloadCallbacks) do
        pcall(callback)
    end
end

local TEA_GAME_ID = 5488708927
local IS_TOR = game.GameId == 10768640243
local IS_ASTN = game.GameId == 5865880597
local DEFAULT_FPS = 120
local FRAME_RATES = { "30", "40", "48", "60", "80", "90", "120", "144", "160", "240" }
local TAS_FOLDER = "Aery Hub/TAS"
local STATUS_COLORS = { Idle = "#A8A8A8", Stopped = "#C0C0C0", Paused = "#DCDCDC", Recording = "#FFFFFF", Viewing = "#E6E6E6" }

local savestates = {}
local currentSegment = {}
local started = false
local runSaved = true
local confirmNewRunUntil = 0
local paused = true
local runTower
local cursor
local placeFileName
local lastAutoName
local kitController
local recordTime = 0
local sampleAccumulator = 0
local originalFpsCap

local steppingForward = false
local steppingBack = false
local seekDirection = 0
local viewPaused = false
local View = { index = 1, step = false }
local viewingTas = false
local viewConnection
local connections = {}

local statusLabel, timeLabel, framesLabel, savestatesLabel, fpsLabel, objectsLabel
local viewObjects, viewAnims
local pauseButton, viewButton
local hud
local gameFps = 0

local liveStart, liveStop, liveFreeze, liveShowState, liveSnapshot, liveStep
local resumeMotion
local runFpsWarned = false

local Scroll = { folder = "Aery Hub/TAS/AHK", request = "Aery Hub/TAS/AHK/Request", pending = {} }

function Scroll.available()
    local ok, exists = pcall(function()
        return isfolder(Scroll.folder)
    end)
    return ok and exists == true
end

function Scroll.send(text)
    if text == "" or not Scroll.available() then
        return false
    end
    pcall(function()
        local existing = isfile(Scroll.request) and readfile(Scroll.request) or ""
        writefile(Scroll.request, existing ~= "" and existing .. "," .. text or text)
    end)
    return true
end

function Scroll.clear()
    if Scroll.available() then
        pcall(writefile, Scroll.request, "")
    end
end

local function notify(title, description, time)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", { Title = title, Text = description, Duration = time or 3 })
    end)
end

local function plural(count, word)
    return count .. " " .. word .. (count == 1 and "" or "s")
end

local function currentKitTower()
    if game.GameId == TEA_GAME_ID or IS_TOR or IS_ASTN then
        local tower = LocalPlayer:GetAttribute(IS_TOR and "CurrentObby" or "Tower")
        if type(tower) == "string" and tower ~= "" then
            return tower
        end
        return nil
    end
    if not kitController then
        local ok, module = pcall(function()
            return require(ReplicatedStorage.Framework.Scripts.Client.Controller.KitController)
        end)
        if not ok or type(module) ~= "table" then
            return nil
        end
        kitController = module
    end
    local tower = kitController.Tower
    if type(tower) == "string" and tower ~= "" then
        return tower
    end
    return nil
end

local function getCharacter()
    return LocalPlayer.Character
end

local function getHumanoid()
    local character = LocalPlayer.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoidState()
    local humanoid = getHumanoid()
    return humanoid and humanoid:GetState().Name or "Running"
end

local collisionEdits = setmetatable({}, { __mode = "k" })

local function toggleCollisionUnderMouse()
    local target = Mouse.Target
    if not (target and target:IsA("BasePart")) then
        return
    end
    local original = collisionEdits[target]
    if original then
        collisionEdits[target] = nil
        target.CanCollide = original.canCollide
        target.Transparency = original.transparency
        return
    end
    collisionEdits[target] = { canCollide = target.CanCollide, transparency = target.Transparency }
    target.CanCollide = not target.CanCollide
    target.Transparency = target.CanCollide and 0 or 0.7
end

local OBJECT_INTERVAL = 0.033

local ObjectRecorder = {
    ids = {},
    keys = {},
    parts = {},
    origins = {},
    lastSeen = setmetatable({}, { __mode = "k" }),
    nextId = 1,
    count = 0,
    forceFull = false,
    lastSample = -1,
    cache = {},
    cachedAt = -math.huge,
    cursor = 1,
    movers = setmetatable({}, { __mode = "k" }),
    active = {},
}

local objectOverlap = OverlapParams.new()
objectOverlap.FilterType = Enum.RaycastFilterType.Exclude

local function resetObjectRecorder()
    ObjectRecorder.ids = {}
    ObjectRecorder.keys = {}
    ObjectRecorder.parts = {}
    ObjectRecorder.origins = {}
    ObjectRecorder.lastSeen = setmetatable({}, { __mode = "k" })
    ObjectRecorder.nextId = 1
    ObjectRecorder.count = 0
    ObjectRecorder.forceFull = false
    ObjectRecorder.lastSample = -1
    ObjectRecorder.cache = {}
    ObjectRecorder.cachedAt = -math.huge
    ObjectRecorder.cursor = 1
    ObjectRecorder.movers = setmetatable({}, { __mode = "k" })
    ObjectRecorder.active = {}
end

local function objectKey(part)
    local segments = {}
    local node = part
    while node ~= Workspace do
        local parent = node.Parent
        if not parent then
            return nil
        end
        local index = 0
        for _, child in ipairs(parent:GetChildren()) do
            if child.Name == node.Name then
                index = index + (1)
            end
            if child == node then
                break
            end
        end
        table.insert(segments, 1, node.Name .. "[" .. index .. "]")
        node = parent
    end
    return table.concat(segments, "/")
end

local function roundTo(value, scale)
    return math.floor(value * scale + 0.5) / scale
end

local function objectState(cframe, transparency, canCollide)
    local axis, angle = cframe:ToAxisAngle()
    local rotation = axis * angle
    local position = cframe.Position
    return {
        roundTo(position.X, 1000),
        roundTo(position.Y, 1000),
        roundTo(position.Z, 1000),
        roundTo(rotation.X, 100000),
        roundTo(rotation.Y, 100000),
        roundTo(rotation.Z, 100000),
        roundTo(transparency, 100),
        canCollide and 1 or 0,
    }
end

local objectChanged = function(part, seen)
    local cframe = part.CFrame
    if cframe ~= seen.cframe then
        if (cframe.Position - seen.cframe.Position).Magnitude > 0.005 then
            return true
        end
        if cframe.LookVector:Dot(seen.cframe.LookVector) < 0.99999 or cframe.UpVector:Dot(seen.cframe.UpVector) < 0.99999 then
            return true
        end
    end
    return part.Transparency ~= seen.transparency or part.CanCollide ~= seen.canCollide
end

function ObjectRecorder.nearby(rootPart)
    local exclude = { Workspace.CurrentCamera }
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(exclude, player.Character)
        end
    end
    objectOverlap.FilterDescendantsInstances = exclude
    local radius = Options.ObjectRadius and tonumber(Options.ObjectRadius.Value) or 150
    local ok, parts = pcall(function()
        return Workspace:GetPartBoundsInRadius(rootPart.Position, radius, objectOverlap)
    end)
    if ok then
        return parts
    end
    return nil
end

ObjectRecorder.check = function(part, forceFull, states)
    local seen = ObjectRecorder.lastSeen[part]
    local id = ObjectRecorder.ids[part]
    local record = false
    if not seen then
        seen = { cframe = part.CFrame, transparency = part.Transparency, canCollide = part.CanCollide }
        ObjectRecorder.lastSeen[part] = seen
        record = forceFull and id ~= nil
    elseif objectChanged(part, seen) then
        record = true
        if not ObjectRecorder.movers[part] then
            ObjectRecorder.movers[part] = true
            table.insert(ObjectRecorder.active, part)
        end
    elseif forceFull and id ~= nil then
        record = true
    end
    if record then
        if not id then
            local key = objectKey(part)
            if key then
                id = "o" .. ObjectRecorder.nextId
                ObjectRecorder.nextId = ObjectRecorder.nextId + (1)
                ObjectRecorder.ids[part] = id
                ObjectRecorder.keys[id] = key
                ObjectRecorder.parts[id] = part
                ObjectRecorder.origins[id] = objectState(seen.cframe, seen.transparency, seen.canCollide)
                ObjectRecorder.count = ObjectRecorder.count + (1)
            end
        end
        if id then
            states[id] = objectState(part.CFrame, part.Transparency, part.CanCollide)
            seen.cframe = part.CFrame
            seen.transparency = part.Transparency
            seen.canCollide = part.CanCollide
            return true
        end
    end
    return false
end

local sampleObjects = function()
    local rootPart = getRootPart()
    if not rootPart then
        return nil
    end
    local forceFull = ObjectRecorder.forceFull
    if forceFull or os.clock() - ObjectRecorder.cachedAt >= 1 then
        local parts = ObjectRecorder.nearby(rootPart)
        if not parts then
            return nil
        end
        ObjectRecorder.cache = parts
        ObjectRecorder.cachedAt = os.clock()
        ObjectRecorder.cursor = 1
        ObjectRecorder.active = {}
        for _, part in ipairs(parts) do
            if ObjectRecorder.movers[part] then
                table.insert(ObjectRecorder.active, part)
            end
        end
    end
    ObjectRecorder.forceFull = false
    local cache = ObjectRecorder.cache
    local states, any = {}, false
    if forceFull then
        for _, part in ipairs(cache) do
            if ObjectRecorder.check(part, true, states) then
                any = true
            end
        end
    else
        for _, part in ipairs(ObjectRecorder.active) do
            if ObjectRecorder.check(part, false, states) then
                any = true
            end
        end
        local last = math.min(ObjectRecorder.cursor + 1499, #cache)
        for index = ObjectRecorder.cursor, last do
            local part = cache[index]
            if not ObjectRecorder.movers[part] and ObjectRecorder.check(part, false, states) then
                any = true
            end
        end
        ObjectRecorder.cursor = last >= #cache and 1 or last + 1
    end
    if any then
        return states
    end
    return nil
end

local OBJECT_LERP_GAP = 0.1
local OBJECT_KEY_DISTANCE = 300
local OBJECT_NEAR_DISTANCE = 60

local function decodeObjectCFrame(state)
    local base = CFrame.new(state[1], state[2], state[3])
    local rotation = Vector3.new(state[4], state[5], state[6])
    local angle = rotation.Magnitude
    if angle < 0.000001 then
        return base
    end
    return base * CFrame.fromAxisAngle(rotation / angle, angle)
end

local function resolveObjectKey(key)
    local node = workspace
    for segment in key:gmatch("[^/]+") do
        local name, index = segment:match("^(.*)%[(%d+)%]$")
        if not name then
            return nil
        end
        local wanted = tonumber(index)
        local count = 0
        local found
        for _, child in ipairs(node:GetChildren()) do
            if child.Name == name then
                count = count + (1)
                if count == wanted then
                    found = child
                    break
                end
            end
        end
        if not found then
            return nil
        end
        node = found
    end
    if node:IsA("BasePart") then
        return node
    end
    return nil
end

local function findObjectPart(playback, track)
    local first = track.samples[1].state
    local origin = Vector3.new(first[1], first[2], first[3])
    local best, bestDistance
    local part = resolveObjectKey(track.key)
    if part and not playback.claimed[part] and (part.Position - origin).Magnitude <= OBJECT_KEY_DISTANCE then
        best, bestDistance = part, (part.Position - origin).Magnitude
    end
    local parentName, name = track.key:match("([^/]+)%[%d+%]/([^/]+)%[%d+%]$")
    if not name then
        name = track.key:match("^([^/]+)%[%d+%]$")
    end
    if not name then
        return best
    end
    local ok, nearby = pcall(function()
        return workspace:GetPartBoundsInRadius(origin, OBJECT_NEAR_DISTANCE)
    end)
    if not ok then
        return best
    end
    for _, candidate in ipairs(nearby) do
        local parent = candidate.Parent
        if candidate.Name == name and not playback.claimed[candidate] and (not parentName or (parent and parent.Name == parentName)) then
            local distance = (candidate.Position - origin).Magnitude
            if not bestDistance or distance < bestDistance then
                best, bestDistance = candidate, distance
            end
        end
    end
    return best
end

local function buildObjectPlayback(frames)
    local first = frames[1]
    local keys = first and first.OKeys
    if type(keys) ~= "table" then
        return nil
    end
    local playback = { tracks = {}, claimed = {}, count = 0 }
    for _, frame in ipairs(frames) do
        local objects = frame.OObjects
        if type(objects) == "table" then
            for id, state in pairs(objects) do
                local key = keys[id]
                if type(key) == "string" and type(state) == "table" and #state >= 8 then
                    local track = playback.tracks[id]
                    if not track then
                        track = {
                            key = key,
                            samples = {},
                            index = 1,
                            appliedIndex = 0,
                            part = nil,
                            retryAt = 0,
                            originalAnchored = nil,
                            originalCFrame = nil,
                            originalTransparency = nil,
                            originalCanCollide = nil,
                        }
                        playback.tracks[id] = track
                        playback.count = playback.count + (1)
                    end
                    table.insert(track.samples, { time = frame.time or 0, state = state, cframe = nil })
                end
            end
        end
    end
    if playback.count == 0 then
        return nil
    end
    return playback
end

local function applyObjectPlayback(playback, elapsed)
    local now = os.clock()
    local resolves = 0
    for _, track in pairs(playback.tracks) do
        local samples = track.samples
        if elapsed >= samples[1].time then
            while samples[track.index + 1] and samples[track.index + 1].time <= elapsed do
                track.index = track.index + (1)
            end
            local part = track.part
            if part and not part.Parent then
                playback.claimed[part] = nil
                part = nil
                track.part = nil
                track.appliedIndex = 0
            end
            if not part and now >= track.retryAt and resolves < 10 then
                resolves = resolves + 1
                track.retryAt = now + math.random() * 0.5 + 1
                part = findObjectPart(playback, track)
                if part then
                    track.part = part
                    playback.claimed[part] = true
                    track.originalAnchored = part.Anchored
                    track.originalCFrame = part.CFrame
                    track.originalTransparency = part.Transparency
                    track.originalCanCollide = part.CanCollide
                    part.Anchored = true
                end
            end
            if part then
                local current = samples[track.index]
                local nextSample = samples[track.index + 1]
                local gap = nextSample and nextSample.time - current.time or OBJECT_LERP_GAP
                current.cframe = current.cframe or decodeObjectCFrame(current.state)
                if gap < OBJECT_LERP_GAP then
                    nextSample.cframe = nextSample.cframe or decodeObjectCFrame(nextSample.state)
                    local alpha = math.clamp((elapsed - current.time) / gap, 0, 1)
                    part.CFrame = current.cframe:Lerp(nextSample.cframe, alpha)
                else
                    part.CFrame = current.cframe
                end
                if track.appliedIndex ~= track.index then
                    part.Transparency = current.state[7]
                    part.CanCollide = current.state[8] == 1
                    track.appliedIndex = track.index
                end
            end
        end
    end
end

local function stopObjectPlayback(playback)
    if not playback then
        return
    end
    for _, track in pairs(playback.tracks) do
        local part = track.part
        if part and part.Parent and track.originalAnchored ~= nil then
            pcall(function()
                if track.originalCFrame then
                    part.CFrame = track.originalCFrame
                end
                if track.originalTransparency ~= nil then
                    part.Transparency = track.originalTransparency
                end
                if track.originalCanCollide ~= nil then
                    part.CanCollide = track.originalCanCollide
                end
                part.Anchored = track.originalAnchored
            end)
        end
        track.part = nil
        track.index = 1
        track.appliedIndex = 0
        track.retryAt = 0
    end
    playback.claimed = {}
end

local ObjectHold = { active = false, parts = {} }

ObjectHold.pin = function()
    for part, hold in pairs(ObjectHold.parts) do
        if part.Parent then
            if not part.Anchored then
                part.Anchored = true
            end
            if part.CFrame ~= hold.cframe then
                part.CFrame = hold.cframe
            end
            if part.Transparency ~= hold.transparency then
                part.Transparency = hold.transparency
            end
            if part.CanCollide ~= hold.canCollide then
                part.CanCollide = hold.canCollide
            end
        end
    end
end

function ObjectHold.begin()
    local held = {}
    local function add(part)
        if held[part] or not part.Parent then
            return
        end
        held[part] = {
            cframe = part.CFrame,
            transparency = part.Transparency,
            canCollide = part.CanCollide,
            anchored = part.Anchored,
            velocity = part.AssemblyLinearVelocity,
            angular = part.AssemblyAngularVelocity,
            moved = false,
        }
    end
    for part in pairs(ObjectRecorder.ids) do
        add(part)
    end
    local rootPart = getRootPart()
    local nearby = rootPart and ObjectRecorder.nearby(rootPart)
    if nearby then
        for _, part in ipairs(nearby) do
            if not part.Anchored then
                add(part)
            end
        end
    end
    ObjectHold.parts = held
    ObjectHold.active = true
    ObjectHold.pin()
    RunService:BindToRenderStep("AeryTASObjectHold", Enum.RenderPriority.Last.Value, ObjectHold.pin)
end

function ObjectHold.release()
    pcall(function()
        RunService:UnbindFromRenderStep("AeryTASObjectHold")
    end)
    for part, hold in pairs(ObjectHold.parts) do
        if part.Parent then
            part.Anchored = hold.anchored
            if not hold.anchored and not hold.moved then
                part.AssemblyLinearVelocity = hold.velocity
                part.AssemblyAngularVelocity = hold.angular
            end
        end
    end
    ObjectHold.parts = {}
    ObjectHold.active = false
end

function ObjectHold.stateAt(index)
    local states = {}
    for id, state in pairs(ObjectRecorder.origins) do
        states[id] = state
    end
    local segments = {}
    for _, segment in ipairs(savestates) do
        table.insert(segments, segment)
    end
    table.insert(segments, currentSegment)
    local count = 0
    for _, segment in ipairs(segments) do
        for _, frame in ipairs(segment) do
            count = count + (1)
            if count > index then
                return states
            end
            if frame.Objects then
                for id, state in pairs(frame.Objects) do
                    states[id] = state
                end
            end
        end
    end
    return states
end

function ObjectHold.seek(index)
    if not ObjectHold.active then
        return
    end
    for id, state in pairs(ObjectHold.stateAt(index)) do
        local part = ObjectRecorder.parts[id]
        local hold = part and ObjectHold.parts[part]
        if hold then
            hold.cframe = decodeObjectCFrame(state)
            hold.transparency = state[7]
            hold.canCollide = state[8] == 1
            hold.moved = true
        end
    end
    ObjectHold.pin()
end

function ObjectHold.sync()
    local wanted = started and paused and not viewingTas and not Library.Unloaded
        and (not Toggles.RecordObjects or Toggles.RecordObjects.Value)
    if wanted and not ObjectHold.active then
        ObjectHold.begin()
    elseif not wanted and ObjectHold.active then
        ObjectHold.release()
    end
end

local CameraHold = { active = false, cframe = nil, cameraType = nil, mouseBehavior = nil, zoom = nil }

CameraHold.pin = function()
    local camera = Workspace.CurrentCamera
    if not camera or not CameraHold.cframe then
        return
    end
    camera.CFrame = CameraHold.cframe
    if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCurrentPosition then
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
    end
end

function CameraHold.begin()
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end
    CameraHold.active = true
    CameraHold.cframe = CameraHold.cframe or camera.CFrame
    CameraHold.cameraType = camera.CameraType
    CameraHold.mouseBehavior = UserInputService.MouseBehavior
    CameraHold.pin()
    RunService:BindToRenderStep("AeryTASPausedCamera", Enum.RenderPriority.Camera.Value + 10, CameraHold.pin)
end

function CameraHold.release()
    pcall(function()
        RunService:UnbindFromRenderStep("AeryTASPausedCamera")
    end)
    if CameraHold.active then
        local camera = Workspace.CurrentCamera
        if camera then
            local restore = CameraHold.cameraType
            if not restore or restore == Enum.CameraType.Scriptable then
                restore = Enum.CameraType.Custom
            end
            camera.CameraType = restore
            local humanoid = getHumanoid()
            if humanoid then
                camera.CameraSubject = humanoid
            end
            if CameraHold.cframe then
                camera.CFrame = CameraHold.cframe
            end
        end
        if CameraHold.mouseBehavior then
            UserInputService.MouseBehavior = CameraHold.mouseBehavior
        end
    end
    CameraHold.active = false
    CameraHold.cframe = nil
    CameraHold.cameraType = nil
    CameraHold.mouseBehavior = nil
    CameraHold.zoom = nil
end

function CameraHold.sync()
    local wanted = started and paused and not viewingTas and not Library.Unloaded
        and not (Toggles.MoveCameraWhilePaused and Toggles.MoveCameraWhilePaused.Value)
    if wanted and not CameraHold.active then
        CameraHold.begin()
    elseif not wanted and CameraHold.active then
        CameraHold.release()
    end
end

local function serializeRun()
    local frames = {}
    local lastZoom, lastLock, lastMouse
    local function packCFrame(cframe)
        local components = { cframe:GetComponents() }
        for index = 1, 12 do
            components[index] = roundTo(components[index], index <= 3 and 1000 or 100000)
        end
        return components
    end
    local segments = {}
    for _, segment in ipairs(savestates) do
        table.insert(segments, segment)
    end
    table.insert(segments, currentSegment)
    for _, segment in ipairs(segments) do
        for _, frame in ipairs(segment) do
            local zoom
            if frame.Zoom and (not lastZoom or math.abs(frame.Zoom - lastZoom) >= 0.05) then
                zoom = frame.Zoom
                lastZoom = zoom
            end
            local lock
            if frame.Lock ~= nil and frame.Lock ~= lastLock then
                lock = frame.Lock and 1 or 0
                lastLock = frame.Lock
            end
            local mouse
            if frame.Mouse and not (lastMouse and lastMouse[1] == frame.Mouse[1] and lastMouse[2] == frame.Mouse[2]) then
                mouse = frame.Mouse
                lastMouse = mouse
            end
            table.insert(frames, {
                CCFrame = packCFrame(frame.CFrame),
                CCameraCFrame = packCFrame(frame.CameraCFrame),
                VVelocity = { roundTo(frame.Velocity.X, 100), roundTo(frame.Velocity.Y, 100), roundTo(frame.Velocity.Z, 100) },
                SState = frame.State,
                OObjects = frame.Objects,
                AAnim = frame.Anim,
                WWheel = frame.Wheel,
                KKeys = frame.Keys,
                LLock = lock,
                MMouse = mouse,
                ZZoom = zoom,
                time = roundTo(frame.Time, 10000),
            })
        end
    end
    if frames[1] and next(ObjectRecorder.keys) then
        frames[1].OKeys = ObjectRecorder.keys
    end
    return frames
end

local function totalFrames()
    local count = #currentSegment
    for _, segment in ipairs(savestates) do
        count = count + (#segment)
    end
    return count
end

Library.hasUnsavedRun = function()
    return not runSaved and totalFrames() > 1
end

local function formatTime(seconds)
    local minutes = math.floor(seconds / 60)
    local wholeSeconds = math.floor(seconds % 60)
    local milliseconds = math.floor(seconds * 1000 % 1000)
    return string.format("%d:%02d.%03d", minutes, wholeSeconds, milliseconds)
end

local function currentStatus()
    if viewingTas then
        return "Viewing"
    end
    if not started then
        return #savestates > 0 and "Stopped" or "Idle"
    end
    return paused and "Paused" or "Recording"
end

local function updateHud()
    if hud then
        local total = totalFrames()
        hud:SetText(table.concat({
            formatTime(recordTime) .. "  |  " .. currentStatus(),
            "Frame " .. (cursor or total) .. " / " .. total .. "  |  " .. plural(#savestates, "savestate"),
            plural(ObjectRecorder.count, "object") .. "  |  " .. gameFps .. " FPS",
        }, "\n"))
    end
end

local function updateStatus()
    local status = currentStatus()
    if statusLabel then
        statusLabel:SetText(('Status: <font color="%s">%s</font>'):format(STATUS_COLORS[status], status))
    end
    if pauseButton then
        local text = "Start Recording"
        if started then
            text = paused and "Resume" or "Pause"
        end
        pauseButton:SetText(text)
    end
    if viewButton then
        viewButton:SetText(viewingTas and "Stop Viewing" or "View TAS")
    end
    updateHud()
end

local function updateCounters()
    if savestatesLabel then
        savestatesLabel:SetText("Savestates: " .. #savestates)
    end
    if framesLabel then
        local total = totalFrames()
        framesLabel:SetText("Frame: " .. (cursor or total) .. " / " .. total)
    end
    if objectsLabel then
        objectsLabel:SetText("Objects: " .. ObjectRecorder.count)
    end
    updateHud()
end

local function updateTimeLabel()
    if timeLabel then
        timeLabel:SetText("Time: " .. formatTime(recordTime))
    end
    updateHud()
end

local Physics = {
    active = false,
    appliedScale = 1,
    originalGravity = nil,
    humanoid = nil,
    originalWalkSpeed = nil,
    originalJumpPower = nil,
    originalJumpHeight = nil,
    rootPart = nil,
    originalProperties = nil,
    propertiesKey = nil,
    custom = { WalkSpeed = nil, JumpPower = nil, Gravity = nil, Friction = nil, Density = nil },
    written = { Gravity = nil, WalkSpeed = nil, JumpPower = nil, JumpHeight = nil },
}

local function slowMotionScale()
    if not (Toggles.SlowMotion and Toggles.SlowMotion.Value) or viewingTas or (started and paused) then
        return 1
    end
    local option = Options.SlowMotionSpeed
    return math.clamp((option and tonumber(option.Value) or 50) / 100, 0.1, 1)
end

local function setIfChanged(object, property, value)
    if value ~= nil and math.abs(object[property] - value) > 1e-4 then
        object[property] = value
    end
end

function Physics.follow(object, property, originalKey)
    local written = Physics.written[property]
    if written ~= nil and math.abs(object[property] - written) > 1e-4 then
        Physics[originalKey] = object[property]
    end
end

function Physics.write(object, property, value)
    setIfChanged(object, property, value)
    Physics.written[property] = object[property]
end

local function restoreRootProperties()
    if Physics.rootPart and Physics.rootPart.Parent and Physics.propertiesKey then
        Physics.rootPart.CustomPhysicalProperties = Physics.originalProperties
    end
    Physics.rootPart = nil
    Physics.originalProperties = nil
    Physics.propertiesKey = nil
end

local function restorePhysics()
    if Physics.active then
        if Physics.originalGravity then
            Workspace.Gravity = Physics.originalGravity
        end
        local humanoid = Physics.humanoid
        if humanoid and humanoid.Parent then
            humanoid.WalkSpeed = Physics.originalWalkSpeed
            humanoid.JumpPower = Physics.originalJumpPower
            if Physics.originalJumpHeight then
                pcall(function()
                    humanoid.JumpHeight = Physics.originalJumpHeight
                end)
            end
        end
    end
    restoreRootProperties()
    for key in pairs(Physics.written) do
        Physics.written[key] = nil
    end
    Physics.active = false
    Physics.appliedScale = 1
    Physics.humanoid = nil
    Physics.originalGravity = nil
end

local function updatePhysics()
    local custom = Physics.custom
    local scale = slowMotionScale()
    local hasCustom = custom.WalkSpeed or custom.JumpPower or custom.Gravity or custom.Friction or custom.Density
    if scale >= 1 and not hasCustom then
        if Physics.active or Physics.propertiesKey then
            local rootPart = getRootPart()
            if rootPart and not rootPart.Anchored and math.abs(Physics.appliedScale - 1) > 1e-6 then
                local ratio = (Physics.appliedScale) ^ -1
                rootPart.AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity * ratio
                rootPart.AssemblyAngularVelocity = rootPart.AssemblyAngularVelocity * ratio
            end
            restorePhysics()
        end
        return
    end
    local humanoid = getHumanoid()
    local rootPart = getRootPart()
    if not humanoid or not rootPart then
        return
    end
    if not Physics.active then
        Physics.active = true
        Physics.originalGravity = Workspace.Gravity
    end
    if Physics.humanoid ~= humanoid then
        Physics.humanoid = humanoid
        Physics.originalWalkSpeed = humanoid.WalkSpeed
        Physics.originalJumpPower = humanoid.JumpPower
        Physics.originalJumpHeight = nil
        pcall(function()
            Physics.originalJumpHeight = humanoid.JumpHeight
        end)
        Physics.appliedScale = 1
        Physics.written.WalkSpeed = nil
        Physics.written.JumpPower = nil
        Physics.written.JumpHeight = nil
    end
    if math.abs(scale - Physics.appliedScale) > 1e-6 then
        local ratio = scale / Physics.appliedScale
        if not rootPart.Anchored then
            rootPart.AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity * ratio
            rootPart.AssemblyAngularVelocity = rootPart.AssemblyAngularVelocity * ratio
        end
        Physics.appliedScale = scale
    end
    Physics.follow(Workspace, "Gravity", "originalGravity")
    Physics.follow(humanoid, "WalkSpeed", "originalWalkSpeed")
    Physics.follow(humanoid, "JumpPower", "originalJumpPower")
    pcall(Physics.follow, humanoid, "JumpHeight", "originalJumpHeight")
    Physics.write(Workspace, "Gravity", (custom.Gravity or Physics.originalGravity) * scale * scale)
    Physics.write(humanoid, "WalkSpeed", (custom.WalkSpeed or Physics.originalWalkSpeed) * scale)
    Physics.write(humanoid, "JumpPower", (custom.JumpPower or Physics.originalJumpPower) * scale)
    if Physics.originalJumpHeight and not custom.JumpPower then
        pcall(Physics.write, humanoid, "JumpHeight", Physics.originalJumpHeight)
    end

    if custom.Friction or custom.Density then
        if Physics.rootPart ~= rootPart then
            restoreRootProperties()
            Physics.rootPart = rootPart
            Physics.originalProperties = rootPart.CustomPhysicalProperties
        end
        local base = Physics.originalProperties or PhysicalProperties.new(rootPart.Material)
        local density = custom.Density or base.Density
        local friction = custom.Friction or base.Friction
        local key = density .. "/" .. friction
        if Physics.propertiesKey ~= key then
            Physics.propertiesKey = key
            rootPart.CustomPhysicalProperties = PhysicalProperties.new(density, friction, base.Elasticity, base.FrictionWeight, base.ElasticityWeight)
        end
    elseif Physics.propertiesKey then
        restoreRootProperties()
    end
end

local TasMotion = { zoomActive = false, minZoom = nil, maxZoom = nil, releaseAt = nil, humanoid = nil, platformStand = nil, lockController = nil, lockBefore = nil, intro = nil, cameraModule = nil }

function TasMotion.isolated(callback, ...)
    local args = table.pack(...)
    local results
    task.spawn(function()
        results = table.pack(pcall(callback, table.unpack(args, 1, args.n)))
    end)
    if not results then
        return false
    end
    return table.unpack(results, 1, results.n)
end

function TasMotion.mouseLockController()
    local cached = TasMotion.lockController
    if cached then
        return cached
    end
    local ok, controller = TasMotion.isolated(function()
        local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
        local module = scripts and scripts:FindFirstChild("PlayerModule")
        local cameras = module and require(module):GetCameras()
        return cameras and cameras.activeMouseLockController
    end)
    if ok and type(controller) == "table" and controller.GetIsMouseLocked and controller.DoMouseLockSwitch then
        TasMotion.lockController = controller
        return controller
    end
    return nil
end

function TasMotion.isShiftLocked()
    local controller = TasMotion.mouseLockController()
    if not controller then
        return nil
    end
    local ok, locked = TasMotion.isolated(controller.GetIsMouseLocked, controller)
    if ok then
        return locked == true
    end
    return nil
end

function TasMotion.setShiftLock(state)
    local current = TasMotion.isShiftLocked()
    if current == nil or current == state then
        return
    end
    if TasMotion.lockBefore == nil then
        TasMotion.lockBefore = current
    end
    local controller = TasMotion.lockController
    TasMotion.isolated(controller.DoMouseLockSwitch, controller, "MouseLockSwitchAction", Enum.UserInputState.Begin, nil)
end

function TasMotion.restoreShiftLock()
    local before = TasMotion.lockBefore
    if before == nil then
        return
    end
    TasMotion.setShiftLock(before)
    TasMotion.lockBefore = nil
end

function TasMotion.setZoomRange(minimum, maximum)
    if minimum > LocalPlayer.CameraMaxZoomDistance then
        LocalPlayer.CameraMaxZoomDistance = maximum
        LocalPlayer.CameraMinZoomDistance = minimum
    else
        LocalPlayer.CameraMinZoomDistance = minimum
        LocalPlayer.CameraMaxZoomDistance = maximum
    end
end

function TasMotion.lockZoom(distance, holdFor)
    if type(distance) ~= "number" or distance ~= distance then
        return
    end
    distance = math.max(distance, 0.5)
    if not TasMotion.zoomActive then
        TasMotion.zoomActive = true
        local shared = TasMotion.shared()
        shared.zoomHolders = shared.zoomHolders + 1
        if shared.zoomHolders == 1 then
            shared.minZoom = LocalPlayer.CameraMinZoomDistance
            shared.maxZoom = LocalPlayer.CameraMaxZoomDistance
        end
        TasMotion.minZoom = shared.minZoom
        TasMotion.maxZoom = shared.maxZoom
    end
    pcall(TasMotion.setZoomRange, distance, distance)
    TasMotion.releaseAt = holdFor and os.clock() + holdFor or nil
end

function TasMotion.unlockZoom()
    if TasMotion.zoomActive then
        TasMotion.zoomActive = false
        local shared = TasMotion.shared()
        shared.zoomHolders = math.max(shared.zoomHolders - 1, 0)
        if shared.zoomHolders == 0 then
            pcall(TasMotion.setZoomRange, shared.minZoom or TasMotion.minZoom, shared.maxZoom or TasMotion.maxZoom)
        end
    end
    TasMotion.releaseAt = nil
end

function TasMotion.shared()
    local env = getgenv and getgenv() or _G
    local shared = env.AeryTASMotion
    if type(shared) ~= "table" then
        shared = { zoomHolders = 0, minZoom = nil, maxZoom = nil, standHolders = 0, standHumanoid = nil, standOriginal = nil }
        env.AeryTASMotion = shared
    end
    return shared
end

function TasMotion.releaseStand()
    local humanoid = TasMotion.humanoid
    if humanoid then
        local shared = TasMotion.shared()
        if shared.standHumanoid == humanoid then
            shared.standHolders = math.max(shared.standHolders - 1, 0)
            if shared.standHolders == 0 then
                if humanoid.Parent and shared.standOriginal ~= nil then
                    humanoid.PlatformStand = shared.standOriginal
                end
                shared.standHumanoid = nil
                shared.standOriginal = nil
            end
        elseif humanoid.Parent and TasMotion.platformStand ~= nil then
            humanoid.PlatformStand = TasMotion.platformStand
        end
    end
    TasMotion.humanoid = nil
    TasMotion.platformStand = nil
end

function TasMotion.hold()
    local humanoid = getHumanoid()
    if humanoid and TasMotion.humanoid ~= humanoid then
        TasMotion.releaseStand()
        local shared = TasMotion.shared()
        if shared.standHumanoid ~= humanoid then
            shared.standHumanoid = humanoid
            shared.standHolders = 0
            shared.standOriginal = humanoid.PlatformStand
        end
        shared.standHolders = shared.standHolders + 1
        TasMotion.humanoid = humanoid
        TasMotion.platformStand = shared.standOriginal
    end
    if humanoid then
        humanoid.PlatformStand = true
    end
end

function TasMotion.release()
    TasMotion.intro = nil
    TasMotion.releaseStand()
    TasMotion.restoreShiftLock()
    TasMotion.unlockZoom()
end

function TasMotion.handOff(frame)
    if not frame or not getRootPart() then
        return
    end
    local velocity = TasMotion.decode(frame).velocity
    local function push()
        local root = getRootPart()
        if root and velocity then
            root.AssemblyLinearVelocity = velocity
            root.AssemblyAngularVelocity = Vector3.new()
        end
    end
    push()
    local humanoid = getHumanoid()
    local stateName = frame.SState
    if humanoid and type(stateName) == "string" and stateName ~= "Dead" and stateName ~= "Physics" then
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType[stateName])
        end)
    end
    task.spawn(function()
        RunService.Heartbeat:Wait()
        push()
    end)
end

function TasMotion.decode(frame)
    if not frame.decoded then
        frame.decoded = {
            root = frame.CCFrame and CFrame.new(table.unpack(frame.CCFrame, 1, 12)) or nil,
            camera = frame.CCameraCFrame and CFrame.new(table.unpack(frame.CCameraCFrame, 1, 12)) or nil,
            velocity = frame.VVelocity and Vector3.new(frame.VVelocity[1] or 0, frame.VVelocity[2] or 0, frame.VVelocity[3] or 0) or nil,
        }
    end
    return frame.decoded
end

function TasMotion.prepare(frameList)
    local zoom, lock, previous
    for _, frame in ipairs(frameList) do
        if type(frame.ZZoom) == "number" then
            zoom = frame.ZZoom
        end
        if frame.LLock ~= nil then
            lock = frame.LLock == 1
        end
        frame.zoom = zoom
        frame.lock = lock
        local raw = frame.time or 0
        local motionTime = raw
        if previous then
            local step = raw - (previous.time or 0)
            local before = TasMotion.decode(previous)
            local now = TasMotion.decode(frame)
            if before.root and now.root and before.velocity and now.velocity then
                local speed = ((before.velocity + now.velocity) / 2).Magnitude
                if speed > 6 then
                    step = (now.root.Position - before.root.Position).Magnitude / speed
                end
            end
            motionTime = math.clamp(previous.motionTime + step, raw - 0.008, raw + 0.008)
            motionTime = math.max(motionTime, previous.motionTime)
        end
        frame.motionTime = motionTime
        previous = frame
    end
    TasMotion.intro = nil
    local camera = Workspace.CurrentCamera
    local first = frameList[1] and TasMotion.decode(frameList[1]).camera
    if camera and first and (first.Position - camera.CFrame.Position).Magnitude <= 60 and camera.CFrame.LookVector:Dot(first.LookVector) >= math.cos(math.rad(50)) then
        TasMotion.intro = { from = camera.CFrame, start = os.clock() }
    end
end

function TasMotion.zoomOf(frame)
    if frame.zoom then
        return frame.zoom
    end
    local decoded = TasMotion.decode(frame)
    if decoded.camera and decoded.root then
        return (decoded.camera.Position - decoded.root.Position - Vector3.new(0, 1.5, 0)).Magnitude
    end
    return nil
end

function TasMotion.apply(frameList, index, elapsed)
    local current = frameList[index]
    local root = getRootPart()
    if not current or not root then
        return
    end
    while index > 1 and current.motionTime and current.motionTime > elapsed do
        index = index - (1)
        current = frameList[index]
    end
    local following = frameList[index + 1]
    while following and following.motionTime and following.motionTime <= elapsed do
        index = index + (1)
        current = following
        following = frameList[index + 1]
    end
    local now = TasMotion.decode(current)
    local after = following and TasMotion.decode(following)
    local alpha = 0
    if following then
        local startsAt = current.motionTime or current.time or 0
        local gap = (following.motionTime or following.time or 0) - startsAt
        if gap > 0 then
            alpha = math.clamp((elapsed - startsAt) / gap, 0, 1)
        end
    end
    if now.root and after and after.root and (after.root.Position - now.root.Position).Magnitude > 30 then
        alpha = 0
    end
    if now.root then
        root.CFrame = (after and after.root) and now.root:Lerp(after.root, alpha) or now.root
    end
    if now.velocity then
        root.AssemblyLinearVelocity = now.velocity
        root.AssemblyAngularVelocity = Vector3.new()
    end
    local camera = Workspace.CurrentCamera
    if camera and now.camera then
        camera.CFrame = (after and after.camera) and now.camera:Lerp(after.camera, alpha) or now.camera
    end
    local intro = TasMotion.intro
    if camera and intro then
        local t = math.clamp((os.clock() - intro.start) / 0.35, 0, 1)
        camera.CFrame = intro.from:Lerp(camera.CFrame, t * t * (-t * 2 + 3))
        if t >= 1 then
            TasMotion.intro = nil
        end
    end
    local zoom = TasMotion.zoomOf(current)
    local nextZoom = following and TasMotion.zoomOf(following)
    if zoom and nextZoom and math.abs(nextZoom - zoom) <= 4 then
        zoom = zoom + (nextZoom - zoom) * alpha
    end
    TasMotion.lockZoom(zoom)
    if current.lock ~= nil then
        TasMotion.setShiftLock(current.lock)
    end
end

local TasInput = { held = {}, pending = {}, warned = false, resumePending = false, cameraKeys = { LeftShift = true, RightShift = true, b2 = true, Left = true, Right = true }, VK = {
    Space = 32, Tab = 9, Backspace = 8, Return = 13,
    LeftShift = 160, RightShift = 161, LeftControl = 162, RightControl = 163,
    Left = 37, Up = 38, Right = 39, Down = 40,
} }

do
    local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    for index = 1, #letters do
        TasInput.VK[letters:sub(index, index)] = index + 64
    end
    for index, name in ipairs({ "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }) do
        TasInput.VK[name] = index + 47
    end
    for index = 1, 12 do
        TasInput.VK["F" .. index] = index + 111
    end
end

function TasInput.available()
    return type(keypress) == "function" and type(keyrelease) == "function"
        and type(mouse1press) == "function" and type(mouse1release) == "function"
        and type(mouse2press) == "function" and type(mouse2release) == "function"
        and type(mousemoveabs) == "function"
end

function TasInput.blocked()
    local keys = {}
    for _, option in pairs(Options) do
        if type(option) == "table" and option.Type == "KeyPicker" and type(option.Value) == "string" then
            keys[option.Value] = true
        end
    end
    return keys
end

function TasInput.press(name, down)
    if name == "b1" then
        pcall(down and mouse1press or mouse1release)
    elseif name == "b2" then
        pcall(down and mouse2press or mouse2release)
    elseif TasInput.VK[name] then
        pcall(down and keypress or keyrelease, TasInput.VK[name])
    else
        return
    end
    TasInput.held[name] = down or nil
end

function TasInput.send(list)
    local blocked = TasInput.blocked()
    for entry in string.gmatch(list, "[^,]+") do
        local name = entry:sub(2)
        local down = entry:sub(1, 1) == "+"
        local overMenu = down and (name == "b1" or name == "b2") and Library.Toggled
        if not blocked[name] and not overMenu and not TasInput.cameraKeys[name] then
            TasInput.press(name, down)
        end
    end
end

function TasInput.restore(frames, upTo, enabled)
    if not enabled or not TasInput.available() then
        return
    end
    local state = {}
    for index = 1, math.min(upTo - 1, #frames) do
        local list = frames[index].KKeys
        if type(list) == "string" then
            for entry in string.gmatch(tostring(list), "[^,]+") do
                state[entry:sub(2)] = entry:sub(1, 1) == "+"
            end
        end
    end
    local presses = {}
    for name, down in pairs(state) do
        if down and not TasInput.held[name] then
            table.insert(presses, "+" .. name)
        end
    end
    if #presses > 0 then
        TasInput.send(table.concat(presses, ","))
    end
end

function TasInput.releaseAll()
    local names = {}
    for name in pairs(TasInput.held) do
        table.insert(names, name)
    end
    for _, name in ipairs(names) do
        TasInput.press(name, false)
    end
    table.clear(TasInput.held)
end

function TasInput.moveMouse(point)
    local camera = Workspace.CurrentCamera
    if not camera or type(point) ~= "table" then
        return
    end
    local size = camera.ViewportSize
    pcall(mousemoveabs, math.floor(size.X * (point[1] or 0.5) + 0.5), math.floor(size.Y * (point[2] or 0.5) + 0.5))
end

function TasInput.mouseSample()
    local camera = Workspace.CurrentCamera
    if not camera or UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
        return nil
    end
    local size = camera.ViewportSize
    if size.X <= 0 or size.Y <= 0 then
        return nil
    end
    local location = UserInputService:GetMouseLocation()
    return { math.floor(location.X / size.X * 1000 + 0.5) / 1000, math.floor(location.Y / size.Y * 1000 + 0.5) / 1000 }
end

function TasInput.play(enabled, keys, mouse)
    if not enabled or (#keys == 0 and not mouse) then
        return
    end
    if not TasInput.available() then
        if not TasInput.warned then
            TasInput.warned = true
            notify("AeryTAS", "Your executor can't send mouse or key input, so it won't be replayed.", 5)
        end
        return
    end
    if #keys > 0 then
        TasInput.send(table.concat(keys, ","))
    end
    if mouse then
        TasInput.moveMouse(mouse)
    end
end

function TasMotion.cameraController()
    if TasMotion.cameraModule == nil then
        local found, cameras = TasMotion.isolated(function()
            local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
            local module = scripts and scripts:FindFirstChild("PlayerModule")
            return module and require(module):GetCameras()
        end)
        TasMotion.cameraModule = found and type(cameras) == "table" and cameras or false
    end
    local controller = TasMotion.cameraModule and TasMotion.cameraModule.activeCameraController
    if type(controller) == "table" then
        return controller
    end
    return nil
end

function TasMotion.setZoom(distance)
    local controller = TasMotion.cameraController()
    if not (controller and controller.SetCameraToSubjectDistance) then
        return false
    end
    return TasMotion.isolated(controller.SetCameraToSubjectDistance, controller, distance) == true
end

local function getCameraZoom()
    local camera = Workspace.CurrentCamera
    if not camera then
        return nil
    end
    local controller = TasMotion.cameraController()
    local distance
    if controller and controller.GetCameraToSubjectDistance then
        local ok, value = TasMotion.isolated(controller.GetCameraToSubjectDistance, controller)
        if ok and type(value) == "number" and value == value then
            distance = value
        end
    end
    distance = distance or (camera.CFrame.Position - camera.Focus.Position).Magnitude
    return math.floor(distance * 100 + 0.5) / 100
end

local function getRootCFrame()
    local rootPart = getRootPart()
    return rootPart and rootPart.CFrame or CFrame.new()
end

local function getRootVelocity()
    local rootPart = getRootPart()
    return rootPart and rootPart.Velocity or Vector3.new()
end

local function getCameraCFrame()
    return Workspace.CurrentCamera.CFrame
end

local function captureFrame()
    return {
        CFrame = getRootCFrame(),
        CameraCFrame = getCameraCFrame(),
        Velocity = getRootVelocity() / Physics.appliedScale,
        State = getHumanoidState(),
        Zoom = getCameraZoom(),
        Lock = TasMotion.isShiftLocked(),
        Mouse = TasInput.mouseSample(),
        Time = recordTime,
    }
end

local function applyFrame(frame)
    local rootPart = getRootPart()
    if not rootPart or not getHumanoid() then
        return
    end
    rootPart.CFrame = frame.CFrame
    rootPart.Velocity = frame.Velocity * Physics.appliedScale
    resumeMotion = { velocity = frame.Velocity, state = frame.State, lock = frame.Lock }
    Workspace.CurrentCamera.CFrame = frame.CameraCFrame
    if CameraHold.active then
        CameraHold.cframe = frame.CameraCFrame
    end
    if frame.Zoom then
        if CameraHold.active then
            CameraHold.zoom = frame.Zoom
        end
        if not TasMotion.setZoom(frame.Zoom) then
            TasMotion.lockZoom(frame.Zoom, 0.25)
        end
    end
    if liveShowState then
        liveShowState(frame)
    end
end

local function recordFps()
    local option = Options.RecordRate
    return option and tonumber(option.Value) or DEFAULT_FPS
end

local function applyFpsCap()
    if not setfpscap then
        return
    end
    if Toggles.LockFps and Toggles.LockFps.Value then
        if originalFpsCap == nil then
            originalFpsCap = getfpscap and getfpscap() or 0
        end
        pcall(setfpscap, recordFps())
    elseif originalFpsCap ~= nil then
        pcall(setfpscap, originalFpsCap)
        originalFpsCap = nil
    end
end

local function setPaused(state)
    local wasPaused = paused
    local rootPart = getRootPart()
    if state and not wasPaused and rootPart and not rootPart.Anchored then
        resumeMotion = { velocity = rootPart.AssemblyLinearVelocity / Physics.appliedScale, state = getHumanoidState(), lock = TasMotion.isShiftLocked() }
    end
    paused = state
    sampleAccumulator = 0
    if not state then
        ObjectRecorder.forceFull = true
    end
    if rootPart then
        rootPart.Anchored = paused
    end
    if not state and wasPaused and rootPart and resumeMotion then
        rootPart.AssemblyLinearVelocity = resumeMotion.velocity
        rootPart.AssemblyAngularVelocity = Vector3.new()
        local humanoid = getHumanoid()
        local stateName = resumeMotion.state
        if humanoid and type(stateName) == "string" and stateName ~= "Dead" then
            pcall(function()
                humanoid:ChangeState(Enum.HumanoidStateType[stateName])
            end)
        end
    end
    ObjectHold.sync()
    CameraHold.sync()
    if not state and wasPaused and resumeMotion and resumeMotion.lock ~= nil then
        TasMotion.setShiftLock(resumeMotion.lock)
        TasMotion.lockBefore = nil
    end
    if liveFreeze then
        liveFreeze(state)
    end
    updateStatus()
end

local function frameAt(index)
    local remaining = index
    for _, segment in ipairs(savestates) do
        if remaining <= #segment then
            return segment[remaining]
        end
        remaining = remaining - (#segment)
    end
    return currentSegment[remaining]
end

local function truncateAfter(index)
    local remaining = index
    for i, segment in ipairs(savestates) do
        if remaining <= #segment then
            local kept = {}
            for k = 1, remaining do
                kept[k] = segment[k]
            end
            for k = #savestates, i, -1 do
                savestates[k] = nil
            end
            if remaining == #segment then
                table.insert(savestates, kept)
                currentSegment = {}
            else
                currentSegment = kept
            end
            return
        end
        remaining = remaining - (#segment)
    end
    local kept = {}
    for k = 1, math.min(remaining, #currentSegment) do
        kept[k] = currentSegment[k]
    end
    currentSegment = kept
end

local function forgetObjectStates()
    ObjectRecorder.lastSeen = setmetatable({}, { __mode = "k" })
    ObjectRecorder.forceFull = true
end

local function commitCursor()
    if cursor then
        runSaved = false
        truncateAfter(cursor)
        cursor = nil
        forgetObjectStates()
        updateCounters()
    end
end

local function seekTo(index)
    local total = totalFrames()
    if index < 1 or index > total then
        return
    end
    local frame = frameAt(index)
    if not frame then
        return
    end
    if not paused then
        setPaused(true)
    end
    cursor = index < total and index or nil
    recordTime = frame.Time
    applyFrame(frame)
    ObjectHold.seek(index)
    updateTimeLabel()
    updateCounters()
end

local function startRecording()
    if started then
        return
    end
    local humanoid = getHumanoid()
    if not getRootPart() or not humanoid or humanoid.Health <= 0 then
        notify("AeryTAS", "You need to be alive to start recording. Wait until you respawn.", 4)
        return
    end
    if #savestates > 0 and not runSaved and os.clock() > confirmNewRunUntil then
        confirmNewRunUntil = os.clock() + 4
        notify("AeryTAS", "The stopped run isn't saved. Start again within 4 seconds to replace it.", 4)
        return
    end
    confirmNewRunUntil = 0
    resetObjectRecorder()
    runSaved = false
    cursor = nil
    recordTime = 0
    currentSegment = {}
    Scroll.pending = {}
    TasInput.pending = {}
    resumeMotion = nil
    runFpsWarned = false
    liveStart()
    local firstFrame = captureFrame()
    liveSnapshot(firstFrame, true)
    savestates = { { firstFrame } }
    started = true
    runTower = currentKitTower()
    setPaused(false)
    updateTimeLabel()
    updateCounters()
end

local function togglePause()
    if viewingTas then
        return
    end
    if not started then
        startRecording()
        return
    end
    if paused then
        commitCursor()
    end
    setPaused(not paused)
end

local function addSavestate()
    if viewingTas or not started then
        return
    end
    commitCursor()
    if #currentSegment == 0 then
        return
    end
    table.insert(savestates, currentSegment)
    currentSegment = {}
    updateCounters()
end

local function lastFrameOfLastSavestate()
    for index = #savestates, 1, -1 do
        local segment = savestates[index]
        if #segment > 0 then
            return segment[#segment]
        end
    end
    return nil
end

local function lastRecordedFrame()
    if #currentSegment > 0 then
        return currentSegment[#currentSegment]
    end
    return lastFrameOfLastSavestate()
end

local function goToLastSavestate()
    if viewingTas or not started then
        return
    end
    local frame = #savestates > 0 and lastFrameOfLastSavestate()
    if not frame then
        return
    end
    cursor = nil
    runSaved = false
    currentSegment = {}
    forgetObjectStates()
    setPaused(true)
    recordTime = frame.Time
    applyFrame(frame)
    ObjectHold.seek(totalFrames())
    updateTimeLabel()
    updateCounters()
end

local function removeSavestate()
    if viewingTas or not started or #savestates <= 1 then
        return
    end
    table.remove(savestates)
    runSaved = false
    cursor = nil
    currentSegment = {}
    forgetObjectStates()
    local frame = lastFrameOfLastSavestate()
    setPaused(true)
    if frame then
        recordTime = frame.Time
        applyFrame(frame)
        ObjectHold.seek(totalFrames())
    else
        recordTime = 0
    end
    updateTimeLabel()
    updateCounters()
end

local function frameAdvance()
    if viewingTas then
        if viewPaused then
            View.step = true
        end
        return
    end
    if not started then
        return
    end
    if cursor then
        seekTo(cursor + 1)
        return
    end
    if not paused then
        setPaused(true)
        return
    end
    local before = totalFrames()
    setPaused(false)
    local waited = 0
    repeat
        RunService.Heartbeat:Wait()
        waited = waited + (1)
    until totalFrames() > before or waited >= 30 or viewingTas or not started
    if started and not viewingTas then
        setPaused(true)
    end
    updateCounters()
end

local function latestSavestateIndex()
    local count = 0
    for _, segment in ipairs(savestates) do
        count = count + (#segment)
    end
    return math.max(count, 1)
end

local function frameBack()
    if viewingTas or not started then
        return
    end
    local target = (cursor or totalFrames()) - 1
    if target < latestSavestateIndex() then
        return
    end
    seekTo(target)
end

local function holdFrameAdvance()
    steppingForward = true
    frameAdvance()
    while task.wait() and steppingForward do
        frameAdvance()
    end
end

local function holdFrameBack()
    steppingBack = true
    frameBack()
    while task.wait() and steppingBack do
        frameBack()
    end
end

local function holdSeek(direction)
    if viewingTas or not started then
        return
    end
    seekDirection = direction
    while seekDirection == direction and started and not viewingTas and not Library.Unloaded do
        local total = totalFrames()
        local current = cursor or total
        local target = math.clamp(current + direction * 3, math.min(latestSavestateIndex(), total), total)
        if target == current then
            break
        end
        seekTo(target)
        RunService.Heartbeat:Wait()
    end
end

local TAS_JUMP_FROM = 5
local TAS_JUMP_TO = 25
local TAS_JUMP_DURATION = 0.3
local TAS_DEFAULT_ANIMATIONS = {
    idle = "180435571", walk = "180426354", run = "180426354", jump = "125750702",
    fall = "180436148", climb = "180436334", sit = "178130996", toolnone = "182393478",
}
local TAS_FADES = { idle = 0.1, walk = 0.1, run = 0.1, jump = 0.1, fall = 0.3, climb = 0.1, sit = 0.5 }
local TAS_GROUND_STATES = { Running = true, RunningNoPhysics = true, Landed = true, Swimming = true }
local TAS_AIR_STATES = { Jumping = true, Freefall = true }
local TAS_AIR_DELAY = 0.12
local TAS_FOOT_OFFSETS = {
    Vector3.new(0, 0, 0),
    Vector3.new(0.9, 0, 0.45),
    Vector3.new(-0.9, 0, 0.45),
    Vector3.new(0.9, 0, -0.45),
    Vector3.new(-0.9, 0, -0.45),
}

local TasAnimator = {
    character = nil,
    loader = nil,
    animate = nil,
    animateWasDisabled = false,
    tracks = {},
    currentName = nil,
    jumpUntil = -1,
    pose = "none",
    airSince = -1,
    byId = {},
    slots = {},
    extras = {},
    frozen = false,
    session = 0,
    stopForeign = nil,
    pendingSeeks = {},
}

function TasAnimator.stopForeign()
    local loader = TasAnimator.loader
    if not loader then
        return
    end
    local ours = {}
    for _, slot in pairs(TasAnimator.slots) do
        if slot.track then
            ours[slot.track] = true
        end
    end
    for _, entry in pairs(TasAnimator.extras) do
        if entry.track then
            ours[entry.track] = true
        end
    end
    for _, track in pairs(TasAnimator.tracks) do
        ours[track] = true
    end
    local ok, playing = pcall(function()
        return loader:GetPlayingAnimationTracks()
    end)
    if not ok then
        return
    end
    for _, track in ipairs(playing) do
        if not ours[track] then
            pcall(function()
                if track.WeightTarget > 0 then
                    track:Stop(0)
                end
            end)
        end
    end
end

local tasRayParams = RaycastParams.new()
tasRayParams.FilterType = Enum.RaycastFilterType.Exclude
tasRayParams.RespectCanCollide = true

local tasOverlapParams = OverlapParams.new()
tasOverlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function tasJumped(previous, frame)
    if frame.SState then
        return frame.SState == "Jumping" and not (previous and previous.SState == "Jumping")
    end
    local before = previous and previous.VVelocity and previous.VVelocity[2] or 0
    local after = frame.VVelocity and frame.VVelocity[2] or 0
    return before <= TAS_JUMP_FROM and after >= TAS_JUMP_TO
end

local function tasAnimation(name)
    local animate = TasAnimator.animate
    local folder = animate and animate:FindFirstChild(name)
    local best, bestWeight
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Animation") then
                local weightValue = child:FindFirstChild("Weight")
                local weight = weightValue and tonumber(weightValue.Value) or 1
                if not best or weight > bestWeight then
                    best, bestWeight = child, weight
                end
            end
        end
    end
    if not best then
        best = Instance.new("Animation")
        best.AnimationId = "rbxassetid://" .. TAS_DEFAULT_ANIMATIONS[name]
    end
    return best
end

local function tasTrack(name)
    local track = TasAnimator.tracks[name]
    if not track and TasAnimator.loader then
        local ok, loaded = pcall(function()
            return TasAnimator.loader:LoadAnimation(tasAnimation(name))
        end)
        if ok and loaded then
            track = loaded
            track.Priority = name == "toolnone" and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Core
            track.Looped = name ~= "jump"
            TasAnimator.tracks[name] = track
        end
    end
    return track
end

local function tasPlay(name, speed)
    if TasAnimator.currentName ~= name then
        local fade = name and TAS_FADES[name] or 0.1
        local old = TasAnimator.currentName and TasAnimator.tracks[TasAnimator.currentName]
        if old then
            old:Stop(fade)
        end
        local track = name and tasTrack(name)
        if track then
            track:Play(fade)
        end
        TasAnimator.currentName = name
    end
    local current = name and TasAnimator.tracks[name]
    if current then
        current:AdjustSpeed(speed)
    end
end

local function stopTasAnimator()
    for _, track in pairs(TasAnimator.tracks) do
        pcall(function()
            track:Stop(0.1)
            track:Destroy()
        end)
    end
    for _, track in pairs(TasAnimator.byId) do
        pcall(function()
            track:Stop(0.1)
            track:Destroy()
        end)
    end
    TasAnimator.tracks = {}
    TasAnimator.currentName = nil
    TasAnimator.jumpUntil = -1
    TasAnimator.pose = "none"
    TasAnimator.airSince = -1
    TasAnimator.byId = {}
    TasAnimator.slots = {}
    TasAnimator.extras = {}
    TasAnimator.pendingSeeks = {}
    TasAnimator.frozen = false
    local animate = TasAnimator.animate
    if animate and animate.Parent then
        animate.Disabled = TasAnimator.animateWasDisabled
    end
    TasAnimator.animate = nil
    TasAnimator.character = nil
    TasAnimator.loader = nil
end

local function startTasAnimator()
    stopTasAnimator()
    local character = getCharacter()
    local humanoid = getHumanoid()
    if not character or not humanoid then
        return false
    end
    local loader = humanoid:FindFirstChildOfClass("Animator") or humanoid
    local animate = character:FindFirstChild("Animate")
    if animate and animate:IsA("BaseScript") then
        TasAnimator.animate = animate
        TasAnimator.animateWasDisabled = animate.Disabled
        animate.Disabled = true
    end
    for _, track in ipairs(loader:GetPlayingAnimationTracks()) do
        track:Stop(0.1)
    end
    TasAnimator.character = character
    TasAnimator.loader = loader
    TasAnimator.session = TasAnimator.session + 1
    return true
end

local function tasGrounded(cframe, humanoid, centerOnly)
    local root = getRootPart()
    local depth = humanoid.RigType == Enum.HumanoidRigType.R6 and 3 or humanoid.HipHeight + (root and root.Size.Y / 2 or 1)
    tasRayParams.FilterDescendantsInstances = { TasAnimator.character }
    local direction = Vector3.new(0, -(depth + 1), 0)
    for index, offset in ipairs(TAS_FOOT_OFFSETS) do
        if index == 1 or not centerOnly then
            if workspace:Raycast(cframe * offset, direction, tasRayParams) then
                return true
            end
        end
    end
    return false
end

local function tasNearTruss(position)
    tasOverlapParams.FilterDescendantsInstances = { TasAnimator.character }
    local ok, parts = pcall(function()
        return workspace:GetPartBoundsInRadius(position, 2, tasOverlapParams)
    end)
    if ok then
        for _, part in ipairs(parts) do
            if part:IsA("TrussPart") then
                return true
            end
        end
    end
    return false
end

local function updateTasAnimator(frame, jumped, elapsed)
    local character = getCharacter()
    local humanoid = getHumanoid()
    if not character or not humanoid then
        return
    end
    if TasAnimator.character ~= character and not startTasAnimator() then
        return
    end
    local velocity = frame.VVelocity or { 0, 0, 0 }
    local vy = velocity[2] or 0
    local horizontal = Vector3.new(velocity[1] or 0, 0, velocity[3] or 0).Magnitude
    if jumped then
        TasAnimator.jumpUntil = elapsed + TAS_JUMP_DURATION
    end
    local jumping = elapsed < TasAnimator.jumpUntil
    local state = frame.SState
    local pose
    if state then
        if TAS_GROUND_STATES[state] then
            pose = "ground"
        elseif TAS_AIR_STATES[state] then
            pose = "air"
        elseif state == "Climbing" then
            pose = "climb"
        elseif state == "Seated" then
            pose = "sit"
        end
    elseif jumping and vy > 0 then
        pose = "air"
    elseif frame.CCFrame then
        local cframe = CFrame.new(table.unpack(frame.CCFrame, 1, 12))
        if not tasGrounded(cframe, humanoid, true) and tasNearTruss(cframe.Position) then
            pose = "climb"
        elseif humanoid.FloorMaterial ~= Enum.Material.Air or tasGrounded(cframe, humanoid, false) then
            pose = "ground"
        else
            pose = "air"
        end
        if pose == "air" and not jumping then
            if TasAnimator.airSince < 0 then
                TasAnimator.airSince = elapsed
            end
            if elapsed - TasAnimator.airSince < TAS_AIR_DELAY and TasAnimator.pose ~= "none" then
                pose = TasAnimator.pose
            end
        else
            TasAnimator.airSince = -1
        end
    end
    TasAnimator.pose = pose or "none"

    if pose == "ground" then
        if horizontal <= 0.5 then
            tasPlay("idle", 1)
        elseif humanoid.RigType == Enum.HumanoidRigType.R6 then
            tasPlay("walk", horizontal / 14.5)
        else
            tasPlay("run", horizontal / 16)
        end
    elseif pose == "air" then
        tasPlay(jumping and "jump" or "fall", 1)
    elseif pose == "climb" then
        tasPlay("climb", vy / 12)
    elseif pose == "sit" then
        tasPlay("sit", 1)
    else
        tasPlay(nil, 1)
    end

    local tool = character:FindFirstChildOfClass("Tool")
    local holding = tool ~= nil and tool:FindFirstChild("Handle") ~= nil
    local toolTrack = holding and tasTrack("toolnone") or TasAnimator.tracks.toolnone
    if toolTrack then
        if holding and not toolTrack.IsPlaying then
            toolTrack:Play(0.1)
        elseif not holding and toolTrack.IsPlaying then
            toolTrack:Stop(0.1)
        end
    end
end

local tasFreezeAnimations, buildAnimPlayback, applyAnimPlayback

do
    local TAS_UNLOOPED = { toolslash = true, toollunge = true }

    local function tasPriority(name, fallback)
        local ok, priority = pcall(function()
            return Enum.AnimationPriority[name]
        end)
        return ok and priority or fallback
    end

    local function tasTrackById(id, priority, looped)
        local track = TasAnimator.byId[id]
        if not track and TasAnimator.loader then
            local ok, loaded = pcall(function()
                local animation = Instance.new("Animation")
                animation.AnimationId = id
                return TasAnimator.loader:LoadAnimation(animation)
            end)
            if ok and loaded then
                track = loaded
                TasAnimator.byId[id] = track
            end
        end
        if track then
            track.Priority = priority
            track.Looped = looped
        end
        return track
    end

    local function tasSpeed(speed)
        return TasAnimator.frozen and 0 or speed
    end

    local function tasSeekTrack(track, speed, offset)
        local length = track.Length
        if offset > 0 and length <= 0 then
            TasAnimator.pendingSeeks[track] = { speed = speed, offset = offset, since = os.clock() }
        end
        if offset > 0 and length > 0 then
            local position = offset * speed
            if track.Looped then
                position = position % length
            else
                position = math.min(position, length)
            end
            track.TimePosition = position
        end
    end

    local function tasStartTrack(track, fade, speed, offset)
        track:Play(fade)
        track:AdjustSpeed(tasSpeed(speed))
        tasSeekTrack(track, speed, offset)
    end

    local function tasSetSlot(slotName, id, fade, priority, looped, speed, offset)
        local current = TasAnimator.slots[slotName]
        if current and current.id == id then
            if current.track and math.abs(current.speed - speed) > 0.001 then
                current.speed = speed
                current.track:AdjustSpeed(tasSpeed(speed))
            end
            return
        end
        if current and current.track then
            current.track:Stop(fade)
        end
        TasAnimator.slots[slotName] = nil
        if type(id) ~= "string" or id == "" then
            return
        end
        local track = tasTrackById(id, priority, looped)
        if track then
            tasStartTrack(track, fade, speed, offset)
        end
        TasAnimator.slots[slotName] = { id = id, track = track, speed = speed }
    end

    local function tasApplyRecorded(state, offset)
        tasSetSlot("core", state.C, tonumber(state.CF) or 0.1, Enum.AnimationPriority.Core, not TAS_UNLOOPED[state.CN], tonumber(state.CS) or 1, offset)
        local toolPriority = state.TN == "toolnone" and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Action
        tasSetSlot("tool", state.T, tonumber(state.TF) or 0.1, toolPriority, not TAS_UNLOOPED[state.TN], 1, offset)
        local coreNumber = type(state.C) == "string" and state.C:match("%d+") or nil
        local toolNumber = type(state.T) == "string" and state.T:match("%d+") or nil
        local wanted = {}
        if type(state.X) == "table" then
            for id, info in pairs(state.X) do
                local number = type(id) == "string" and id:match("%d+") or nil
                local isDefault = number == "180435792" or number == "129967390" or number == "129967478"
                for _, default in pairs(TAS_DEFAULT_ANIMATIONS) do
                    if default == number then
                        isDefault = true
                    end
                end
                if number == nil or (number ~= coreNumber and number ~= toolNumber and not isDefault) then
                    wanted[id] = info
                end
            end
        end
        local coreSlot, toolSlot = TasAnimator.slots.core, TasAnimator.slots.tool
        for id, entry in pairs(TasAnimator.extras) do
            if type(wanted[id]) ~= "table" then
                local shared = entry.track and ((coreSlot and coreSlot.track == entry.track) or (toolSlot and toolSlot.track == entry.track))
                if entry.track and not shared then
                    entry.track:Stop(0.1)
                end
                TasAnimator.extras[id] = nil
            end
        end
        for id, info in pairs(wanted) do
            if type(id) == "string" and type(info) == "table" then
                local speed = tonumber(info.S) or 1
                local entry = TasAnimator.extras[id]
                if not entry then
                    local track = tasTrackById(id, tasPriority(info.P, Enum.AnimationPriority.Action), info.L == true)
                    if track then
                        tasStartTrack(track, 0.1, speed, offset)
                    end
                    TasAnimator.extras[id] = { track = track, speed = speed }
                elseif entry.track and math.abs(entry.speed - speed) > 0.001 then
                    entry.speed = speed
                    entry.track:AdjustSpeed(tasSpeed(speed))
                end
            end
        end
    end

    tasFreezeAnimations = function(state)
        TasAnimator.frozen = state
        for _, entry in pairs(TasAnimator.slots) do
            if entry.track then
                entry.track:AdjustSpeed(tasSpeed(entry.speed))
            end
        end
        for _, entry in pairs(TasAnimator.extras) do
            if entry.track then
                entry.track:AdjustSpeed(tasSpeed(entry.speed))
            end
        end
        for _, track in pairs(TasAnimator.tracks) do
            pcall(function()
                track:AdjustSpeed(state and 0 or 1)
            end)
        end
    end

    buildAnimPlayback = function(frames)
        local points = {}
        for index, frame in ipairs(frames) do
            if type(frame.AAnim) == "table" then
                table.insert(points, { index = index, time = tonumber(frame.time) or 0, state = frame.AAnim })
            end
        end
        if #points == 0 then
            return nil
        end
        return { points = points, pointer = 0, session = -1 }
    end

    applyAnimPlayback = function(playback, index, elapsed)
        if TasAnimator.character ~= getCharacter() and not startTasAnimator() then
            return
        end
        for track, seek in pairs(TasAnimator.pendingSeeks) do
            local waited = os.clock() - seek.since
            local done = waited > 2
            pcall(function()
                if track.Length > 0 then
                    local position = (seek.offset + waited) * seek.speed
                    if track.Looped then
                        position = position % track.Length
                    else
                        position = math.min(position, track.Length)
                    end
                    track.TimePosition = position
                    done = true
                end
            end)
            if done then
                TasAnimator.pendingSeeks[track] = nil
            end
        end
        local force = false
        if playback.session ~= TasAnimator.session then
            playback.session = TasAnimator.session
            force = true
        end
        local points = playback.points
        local pointer = playback.pointer
        if pointer > 0 and points[pointer].index > index then
            pointer = 0
            force = true
        end
        local before = pointer
        while points[pointer + 1] and points[pointer + 1].index <= index do
            pointer = pointer + 1
        end
        playback.pointer = pointer
        local point = points[pointer]
        if point and (pointer ~= before or force) then
            tasApplyRecorded(point.state, force and math.max(0, elapsed - point.time) or 0)
        end
    end

    local LIVE_FALLBACK = {
        idle = { { "180435571", 9 }, { "180435792", 1 } },
        walk = { { "180426354", 10 } },
        run = { { "180426354", 10 } },
        jump = { { "125750702", 10 } },
        fall = { { "180436148", 10 } },
        climb = { { "180436334", 10 } },
        sit = { { "178130996", 10 } },
        toolnone = { { "182393478", 10 } },
        toolslash = { { "129967390", 10 } },
        toollunge = { { "129967478", 10 } },
        wave = { { "128777973", 10 } },
        point = { { "128853357", 10 } },
        dance1 = { { "182435998", 10 }, { "182491037", 10 }, { "182491065", 10 } },
        dance2 = { { "182436842", 10 }, { "182491248", 10 }, { "182491277", 10 } },
        dance3 = { { "182436935", 10 }, { "182491368", 10 }, { "182491423", 10 } },
        laugh = { { "129423131", 10 } },
        cheer = { { "129423030", 10 } },
    }
    local LIVE_STOP_POSES = { Dead = true, GettingUp = true, FallingDown = true, PlatformStanding = true }
    local LIVE_TOOL_ANIMS = { None = "toolnone", Slash = "toolslash", Lunge = "toollunge" }
    local LIVE_STATE_POSES = { Freefall = "FreeFall", Jumping = "Jumping", Climbing = "Climbing", Seated = "Seated", Dead = "Dead", PlatformStanding = "PlatformStanding" }
    local LIVE_JUMP_TIME = 0.3
    local LIVE_SPEED_STEP = 0.02
    local LIVE_DEFAULT_WALK = "180426354"
    local CORE_PRIORITY = Enum.AnimationPriority.Core

    local Live = {
        active = false,
        frozen = false,
        resync = false,
        scale = 1,
        clock = 0,
        character = nil,
        humanoid = nil,
        loader = nil,
        animate = nil,
        animateWasDisabled = false,
        connections = {},
        cache = {},
        owned = {},
        loopHooked = {},
        core = { name = nil, id = nil, track = nil, speed = 1, fade = 0.1 },
        tool = { name = nil, id = nil, track = nil, speed = 1, fade = 0.1 },
        extras = {},
        pose = "Standing",
        jumpTime = 0,
        toolAnim = "None",
        toolTime = 0,
        forceSync = true,
        lastKey = nil,
        lastSpeed = nil,
        lastState = nil,
        lastStateTime = 0,
        playEmote = nil,
        emoteLoops = { wave = false, point = false, dance1 = true, dance2 = true, dance3 = true, laugh = false, cheer = false },
        loopedFor = nil,
        hookEmoteEnd = nil,
        emoteEnds = {},
    }

    local function liveVariants(name)
        local list = {}
        local folder = Live.animate and Live.animate:FindFirstChild(name)
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("Animation") and child.AnimationId ~= "" then
                    local weightValue = child:FindFirstChild("Weight")
                    table.insert(list, { child.AnimationId, weightValue and tonumber(weightValue.Value) or 1 })
                end
            end
        end
        if #list == 0 and LIVE_FALLBACK[name] then
            for _, entry in ipairs(LIVE_FALLBACK[name]) do
                table.insert(list, { "rbxassetid://" .. entry[1], entry[2] })
            end
        end
        return list
    end

    local function liveRoll(name)
        local list = liveVariants(name)
        local total = 0
        for _, entry in ipairs(list) do
            total = total + math.max(entry[2], 0)
        end
        if total <= 0 then
            return list[1] and list[1][1] or nil
        end
        local roll = math.random() * total
        for _, entry in ipairs(list) do
            roll = roll - math.max(entry[2], 0)
            if roll <= 0 then
                return entry[1]
            end
        end
        return list[#list][1]
    end

    local function liveSpeedOf(slot)
        return Live.frozen and 0 or slot.speed * Live.scale
    end

    local function liveTrack(id, priority, looped)
        local track = Live.cache[id]
        if not track and Live.loader then
            local ok, loaded = pcall(function()
                local animation = Instance.new("Animation")
                animation.AnimationId = id
                return Live.loader:LoadAnimation(animation)
            end)
            if ok and loaded then
                track = loaded
                Live.cache[id] = track
                Live.owned[track] = true
            end
        end
        if track then
            track.Priority = priority
            if looped ~= nil then
                track.Looped = looped
            end
        end
        return track
    end

    local livePlay

    local function liveHookLoop(track)
        if Live.loopHooked[track] then
            return
        end
        Live.loopHooked[track] = true
        table.insert(Live.connections, track.DidLoop:Connect(function()
            if Live.active and not Live.frozen and Live.core.track == track and #liveVariants(Live.core.name) > 1 then
                livePlay("core", Live.core.name, 0, CORE_PRIORITY, true)
            end
        end))
    end

    function Live.loopedFor(name)
        if Live.emoteLoops[name] ~= nil then
            return Live.emoteLoops[name]
        elseif name == "emote" then
            return nil
        end
        return not TAS_UNLOOPED[name]
    end

    function Live.hookEmoteEnd(name, track)
        if (Live.emoteLoops[name] == false or (name == "emote" and not track.Looped)) and not Live.emoteEnds[track] then
            Live.emoteEnds[track] = true
            table.insert(Live.connections, track.Stopped:Connect(function()
                if Live.active and not Live.frozen and Live.core.track == track then
                    livePlay("core", "idle", 0.1, CORE_PRIORITY)
                end
            end))
        end
    end

    livePlay = function(slotName, name, fade, priority, reroll, forcedId)
        local slot = Live[slotName]
        if slot.name == name and not reroll and not forcedId then
            return
        end
        local id = forcedId or (name and liveRoll(name))
        if slot.name == name and slot.id == id then
            return
        end
        if slot.track then
            slot.track:Stop(fade)
        end
        slot.name = name
        slot.id = id
        slot.fade = fade
        slot.track = nil
        if not reroll then
            slot.speed = 1
        end
        if id then
            local track = liveTrack(id, priority, Live.loopedFor(name))
            if track then
                Live.hookEmoteEnd(name, track)
                track:Play(fade)
                track:AdjustSpeed(liveSpeedOf(slot))
                slot.track = track
                if slotName == "core" then
                    liveHookLoop(track)
                end
            end
        end
    end

    local function liveSetSpeed(slotName, speed)
        local slot = Live[slotName]
        slot.speed = speed
        if slot.track then
            slot.track:AdjustSpeed(liveSpeedOf(slot))
        end
    end

    local function liveApplySpeeds()
        for _, slotName in ipairs({ "core", "tool" }) do
            local slot = Live[slotName]
            if slot.track then
                slot.track:AdjustSpeed(liveSpeedOf(slot))
            end
        end
        for track, info in pairs(Live.extras) do
            pcall(function()
                track:AdjustSpeed(Live.frozen and 0 or info.S)
            end)
        end
    end

    local function liveIsR6()
        return Live.humanoid ~= nil and Live.humanoid.RigType == Enum.HumanoidRigType.R6
    end

    local function liveOnRunning(speed)
        local real = speed / Live.scale
        if real > 0.01 then
            local r6 = liveIsR6()
            livePlay("core", r6 and "walk" or "run", 0.1, CORE_PRIORITY)
            local id = Live.core.id or ""
            if not r6 then
                liveSetSpeed("core", real / 16)
            elseif id:find(LIVE_DEFAULT_WALK, 1, true) then
                liveSetSpeed("core", real / 14.5)
            end
            Live.pose = "Running"
        else
            if Live.emoteLoops[Live.core.name] == nil and Live.core.name ~= "emote" then
                livePlay("core", "idle", 0.1, CORE_PRIORITY)
            end
            Live.pose = "Standing"
        end
    end

    function Live.emote(emote)
        if not Live.active or Live.frozen or Live.pose ~= "Standing" then
            return false
        end
        if typeof(emote) == "Instance" and emote:IsA("Animation") and emote.AnimationId ~= "" then
            livePlay("core", "emote", 0.1, CORE_PRIORITY, false, emote.AnimationId)
            return true
        end
        if emote == "dance" then
            local dances = { "dance1", "dance2", "dance3" }
            emote = dances[math.random(1, #dances)]
        end
        if type(emote) == "string" and (Live.emoteLoops[emote] ~= nil or (Live.animate and Live.animate:FindFirstChild(emote))) then
            livePlay("core", emote, 0.1, CORE_PRIORITY, true)
            return Live.core.track ~= nil
        end
        return false
    end

    local function liveOnJumping()
        livePlay("core", "jump", 0.1, CORE_PRIORITY)
        Live.jumpTime = LIVE_JUMP_TIME
        Live.pose = "Jumping"
    end

    local function liveOnClimbing(speed)
        livePlay("core", "climb", 0.1, CORE_PRIORITY)
        liveSetSpeed("core", speed / Live.scale / 12)
        Live.pose = "Climbing"
    end

    local function liveOnFreeFall()
        if Live.jumpTime <= 0 then
            livePlay("core", "fall", 0.3, CORE_PRIORITY)
        end
        Live.pose = "FreeFall"
    end

    local function liveOnSeated()
        livePlay("core", "sit", 0.5, CORE_PRIORITY)
        Live.pose = "Seated"
    end

    local function liveSyncPose()
        local humanoid = Live.humanoid
        if not humanoid then
            return
        end
        local root = getRootPart()
        local velocity = root and root.AssemblyLinearVelocity or Vector3.new()
        local state = humanoid:GetState()
        local states = Enum.HumanoidStateType
        if state == states.Jumping then
            if Live.core.name == "jump" then
                Live.pose = "Jumping"
            else
                liveOnJumping()
            end
        elseif state == states.Freefall then
            liveOnFreeFall()
        elseif state == states.Climbing then
            liveOnClimbing(velocity.Y)
        elseif state == states.Seated then
            liveOnSeated()
        elseif state == states.PlatformStanding or state == states.Physics then
            Live.pose = "PlatformStanding"
        elseif state == states.Dead then
            Live.pose = "Dead"
        else
            liveOnRunning(Vector3.new(velocity.X, 0, velocity.Z).Magnitude)
        end
    end

    local function liveAddExtra(track)
        if Live.extras[track] or Live.owned[track] then
            return
        end
        local ok, id = pcall(function()
            return track.Animation.AnimationId
        end)
        if not ok or type(id) ~= "string" or id == "" then
            return
        end
        local number = id:match("%d+")
        local coreNumber = Live.core.id and tostring(Live.core.id):match("%d+") or nil
        local toolNumber = Live.tool.id and tostring(Live.tool.id):match("%d+") or nil
        if number and (number == coreNumber or number == toolNumber) then
            return
        end
        Live.extras[track] = { id = id, P = track.Priority.Name, L = track.Looped, S = track.Speed }
        if Live.frozen then
            pcall(function()
                track:AdjustSpeed(0)
            end)
        end
        table.insert(Live.connections, track.Stopped:Connect(function()
            Live.extras[track] = nil
        end))
    end

    local function liveIsAnimateTrack(track)
        local fromAnimate = false
        pcall(function()
            local animation = track.Animation
            if Live.animate and animation:IsDescendantOf(Live.animate) then
                fromAnimate = true
                return
            end
            local number = tostring(animation.AnimationId):match("%d+")
            if not number then
                return
            end
            for _, variants in pairs(LIVE_FALLBACK) do
                for _, variant in ipairs(variants) do
                    if variant[1] == number then
                        fromAnimate = true
                        return
                    end
                end
            end
            if Live.animate then
                for _, item in ipairs(Live.animate:GetDescendants()) do
                    if item:IsA("Animation") and tostring(item.AnimationId):match("%d+") == number then
                        fromAnimate = true
                        return
                    end
                end
            end
        end)
        return fromAnimate
    end

    local function liveResetSlots()
        Live.core = { name = nil, id = nil, track = nil, speed = 1, fade = 0.1 }
        Live.tool = { name = nil, id = nil, track = nil, speed = 1, fade = 0.1 }
    end

    liveStop = function()
        for _, connection in ipairs(Live.connections) do
            connection:Disconnect()
        end
        Live.connections = {}
        if Live.frozen then
            for track, info in pairs(Live.extras) do
                pcall(function()
                    track:AdjustSpeed(info.S)
                end)
            end
        end
        for _, track in pairs(Live.cache) do
            pcall(function()
                track:Stop(0.1)
                track:Destroy()
            end)
        end
        local animate = Live.animate
        if Live.playEmote then
            pcall(function()
                Live.playEmote.OnInvoke = nil
            end)
            Live.playEmote = nil
        end
        if Live.active and animate and animate.Parent then
            animate.Disabled = Live.animateWasDisabled
        end
        Live.active = false
        Live.frozen = false
        Live.cache = {}
        Live.owned = {}
        Live.loopHooked = {}
        Live.emoteEnds = {}
        Live.extras = {}
        Live.animate = nil
        Live.character = nil
        Live.humanoid = nil
        Live.loader = nil
        liveResetSlots()
    end

    liveStart = function()
        if Live.active then
            return
        end
        local character = getCharacter()
        local humanoid = getHumanoid()
        if not character or not humanoid then
            return
        end
        liveResetSlots()
        Live.active = true
        Live.frozen = false
        Live.resync = false
        Live.character = character
        Live.humanoid = humanoid
        Live.loader = humanoid:FindFirstChildOfClass("Animator") or humanoid
        Live.scale = Physics.appliedScale
        Live.clock = 0
        Live.jumpTime = 0
        Live.toolAnim = "None"
        Live.toolTime = 0
        Live.pose = "Standing"
        Live.forceSync = true
        Live.lastKey = nil
        Live.lastSpeed = nil
        local animate = character:FindFirstChild("Animate")
        if animate and animate:IsA("BaseScript") then
            Live.animate = animate
            Live.animateWasDisabled = animate.Disabled
            animate.Disabled = true
        end
        for _, track in ipairs(Live.loader:GetPlayingAnimationTracks()) do
            if liveIsAnimateTrack(track) then
                track:Stop(0.1)
            else
                liveAddExtra(track)
            end
        end
        local function on(signal, handler)
            table.insert(Live.connections, signal:Connect(function(...)
                if Live.active and not Live.frozen then
                    handler(...)
                end
            end))
        end
        on(humanoid.Running, liveOnRunning)
        on(humanoid.Jumping, liveOnJumping)
        on(humanoid.Climbing, liveOnClimbing)
        on(humanoid.FreeFalling, liveOnFreeFall)
        on(humanoid.Seated, liveOnSeated)
        on(humanoid.Died, function()
            Live.pose = "Dead"
        end)
        on(humanoid.GettingUp, function()
            Live.pose = "GettingUp"
        end)
        on(humanoid.FallingDown, function()
            Live.pose = "FallingDown"
        end)
        local playEmote = Live.animate and Live.animate:FindFirstChild("PlayEmote")
        if playEmote and playEmote:IsA("BindableFunction") then
            Live.playEmote = playEmote
            playEmote.OnInvoke = function(emote)
                return Live.emote(emote)
            end
        else
            on(LocalPlayer.Chatted, function(message)
                local emote = message:match("^/e (.+)$") or message:match("^/emote (.+)$")
                if emote then
                    Live.emote(emote)
                end
            end)
        end
        on(humanoid.PlatformStanding, function()
            Live.pose = "PlatformStanding"
        end)
        on(humanoid.Swimming, function(speed)
            Live.pose = speed > 0 and "Running" or "Standing"
        end)
        table.insert(Live.connections, Live.loader.AnimationPlayed:Connect(function(track)
            if not Live.active or liveIsAnimateTrack(track) then
                return
            end
            liveAddExtra(track)
        end))
        liveSyncPose()
    end

    liveFreeze = function(state)
        if not Live.active or Live.frozen == state then
            return
        end
        Live.frozen = state
        if not state then
            Live.forceSync = true
            Live.resync = true
        end
        liveApplySpeeds()
    end

    local function liveSetExact(slotName, name, id, fade, speed, priority, offset)
        local slot = Live[slotName]
        if slot.id ~= id then
            if slot.track then
                slot.track:Stop(fade)
            end
            slot.track = nil
            if type(id) == "string" and id ~= "" then
                local track = liveTrack(id, priority, Live.loopedFor(name))
                if track then
                    if slotName == "core" then
                        Live.hookEmoteEnd(name, track)
                    end
                    track:Play(fade)
                    slot.track = track
                    if slotName == "core" then
                        liveHookLoop(track)
                    end
                end
            end
        end
        slot.name = name
        slot.id = id
        slot.speed = speed
        if slot.track then
            slot.track:AdjustSpeed(liveSpeedOf(slot))
            tasSeekTrack(slot.track, speed, offset)
        end
    end

    liveShowState = function(frame)
        if not Live.active or not frame or type(frame.AnimRef) ~= "table" then
            return
        end
        local state = frame.AnimRef
        local offset = math.max(0, (frame.Time or 0) - (frame.AnimRefTime or 0))
        liveSetExact("core", state.CN, state.C, 0, tonumber(state.CS) or 1, CORE_PRIORITY, offset)
        Live.core.fade = tonumber(state.CF) or 0.1
        local toolPriority = state.TN == "toolnone" and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Action
        liveSetExact("tool", state.TN, state.T, 0, 1, toolPriority, offset)
        Live.tool.fade = tonumber(state.TF) or 0.1
        Live.pose = LIVE_STATE_POSES[frame.State] or (state.CN == "idle" and "Standing" or "Running")
        Live.jumpTime = state.CN == "jump" and math.max(0, LIVE_JUMP_TIME - offset) or 0
        Live.forceSync = true
    end

    liveSnapshot = function(frame, force)
        if not Live.active then
            return
        end
        local extras, keys = {}, {}
        for track, info in pairs(Live.extras) do
            if not Live.frozen then
                local ok, speed = pcall(function()
                    return track.Speed
                end)
                if ok and type(speed) == "number" then
                    info.S = math.floor(speed * 100 + 0.5) / 100
                end
            end
            extras[info.id] = { P = info.P, L = info.L, S = info.S }
            table.insert(keys, info.id .. ":" .. tostring(info.S))
        end
        table.sort(keys)
        local core, tool = Live.core, Live.tool
        local key = tostring(core.id) .. "|" .. tostring(tool.id) .. "|" .. table.concat(keys, ",")
        local speed = math.floor(core.speed * 100 + 0.5) / 100
        if force or Live.forceSync or key ~= Live.lastKey or not Live.lastSpeed or math.abs(speed - Live.lastSpeed) >= LIVE_SPEED_STEP then
            Live.forceSync = false
            Live.lastKey = key
            Live.lastSpeed = speed
            Live.lastState = { C = core.id, CN = core.name, CF = core.fade, CS = speed, T = tool.id, TN = tool.name, TF = tool.fade, X = extras }
            Live.lastStateTime = frame.Time
            frame.Anim = Live.lastState
        end
        frame.AnimRef = Live.lastState
        frame.AnimRefTime = Live.lastStateTime
    end

    liveStep = function(deltaTime)
        if not started or viewingTas then
            return
        end
        local character = getCharacter()
        if not Live.active or Live.character ~= character then
            local humanoid = getHumanoid()
            if character and humanoid and humanoid.Health > 0 and getRootPart() then
                liveStop()
                liveStart()
                liveFreeze(paused)
            end
            return
        end
        local animate = character:FindFirstChild("Animate")
        if animate and animate:IsA("BaseScript") then
            if Live.animate ~= animate then
                Live.animate = animate
                Live.animateWasDisabled = false
            end
            if not animate.Disabled then
                animate.Disabled = true
            end
        end
        if Live.loader then
            local okPlaying, playing = pcall(function()
                return Live.loader:GetPlayingAnimationTracks()
            end)
            if okPlaying then
                for _, track in ipairs(playing) do
                    if track ~= Live.core.track and track ~= Live.tool.track and not Live.extras[track] then
                        pcall(function()
                            if not Live.owned[track] or track.WeightTarget > 0 then
                                track:Stop(0)
                            end
                        end)
                    end
                end
            end
        end
        local scale = Physics.appliedScale
        if math.abs(scale - Live.scale) > 0.000001 then
            Live.scale = scale
            liveApplySpeeds()
        end
        if Live.frozen then
            return
        end
        if Live.resync then
            Live.resync = false
            liveSyncPose()
        end
        local gameDelta = deltaTime * scale
        Live.clock = Live.clock + gameDelta
        Live.jumpTime = Live.jumpTime - gameDelta
        if Live.pose == "FreeFall" and Live.jumpTime <= 0 then
            livePlay("core", "fall", 0.3, CORE_PRIORITY)
        elseif LIVE_STOP_POSES[Live.pose] then
            livePlay("core", nil, 0.1, CORE_PRIORITY)
        end
        local tool = character:FindFirstChildOfClass("Tool")
        if tool and tool:FindFirstChild("Handle") then
            local value = tool:FindFirstChild("toolanim")
            if value and value:IsA("StringValue") then
                Live.toolAnim = value.Value
                value.Parent = nil
                Live.toolTime = Live.clock + 0.3
            end
            if Live.clock > Live.toolTime then
                Live.toolTime = 0
                Live.toolAnim = "None"
            end
            local name = LIVE_TOOL_ANIMS[Live.toolAnim] or "toolnone"
            local isIdle = name == "toolnone"
            livePlay("tool", name, isIdle and 0.1 or 0, isIdle and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Action)
        elseif Live.tool.name then
            livePlay("tool", nil, 0.1, Enum.AnimationPriority.Idle)
            Live.toolAnim = "None"
            Live.toolTime = 0
        end
    end
end

local function stopViewing(handOffFrame)
    TasInput.releaseAll()
    if viewConnection then
        viewConnection = nil
        pcall(function()
            RunService:UnbindFromRenderStep("AeryTASView")
        end)
    end
    if not viewingTas then
        return
    end
    TasMotion.release()
    Scroll.clear()
    viewingTas = false
    viewPaused = false
    stopTasAnimator()
    stopObjectPlayback(viewObjects)
    viewObjects = nil
    viewAnims = nil
    cursor = nil
    if started then
        liveStart()
        local frame = lastRecordedFrame()
        setPaused(true)
        if frame then
            recordTime = frame.Time
            applyFrame(frame)
            ObjectHold.seek(totalFrames())
        end
    else
        local rootPart = getRootPart()
        if rootPart then
            rootPart.Anchored = false
        end
        if type(handOffFrame) == "table" then
            TasMotion.handOff(handOffFrame)
        end
        updateStatus()
    end
    updateTimeLabel()
    updateCounters()
end

local function viewTas()
    if viewingTas then
        stopViewing()
        return
    end
    local frames = serializeRun()
    local rootPart = getRootPart()
    if #frames < 2 or not rootPart then
        notify("AeryTAS", "Nothing to view yet.", 3)
        return
    end
    setPaused(true)
    liveStop()
    viewingTas = true
    viewPaused = false
    ObjectHold.sync()
    CameraHold.sync()
    rootPart.Anchored = false
    startTasAnimator()
    viewObjects = buildObjectPlayback(frames)
    viewAnims = buildAnimPlayback(frames)
    updateStatus()
    if (not Toggles.ReplayScroll or Toggles.ReplayScroll.Value) and not Scroll.available() then
        for _, frame in ipairs(frames) do
            if frame.WWheel then
                notify("AeryTAS", "This run has mouse-wheel scrolls, but AHKConnection isn't set up, so the zoom won't be replayed.", 5)
                break
            end
        end
    end

    Scroll.clear()
    TasMotion.prepare(frames)
    TasMotion.hold()
    local elapsed = frames[1].time or 0
    local nextFrame = 1
    viewConnection = true
    RunService:BindToRenderStep("AeryTASView", Enum.RenderPriority.Camera.Value - 1, function(deltaTime)
        local root = getRootPart()
        if not root then
            stopViewing()
            return
        end
        View.index = math.max(nextFrame - 1, 1)
        if viewPaused and not (View.step and frames[nextFrame]) then
            View.step = false
            TasMotion.apply(frames, View.index, elapsed)
            return
        end
        local stepping = viewPaused
        if stepping then
            View.step = false
            elapsed = frames[nextFrame].time
        else
            elapsed = elapsed + deltaTime
        end
        local jumped = false
        local wheel = {}
        local keys = {}
        local mouse
        if TasInput.resumePending then
            TasInput.resumePending = false
            TasInput.restore(frames, nextFrame, Toggles.ReplayInput and Toggles.ReplayInput.Value)
        end
        while nextFrame <= #frames and frames[nextFrame].time <= elapsed do
            local passed = frames[nextFrame]
            jumped = jumped or tasJumped(frames[nextFrame - 1], passed)
            if type(passed.WWheel) == "string" then
                table.insert(wheel, passed.WWheel)
            end
            if type(passed.KKeys) == "string" then
                table.insert(keys, passed.KKeys)
            end
            if type(passed.MMouse) == "table" then
                mouse = passed.MMouse
            end
            nextFrame = nextFrame + (1)
        end
        if #wheel > 0 and (not Toggles.ReplayScroll or Toggles.ReplayScroll.Value) then
            Scroll.send(table.concat(wheel, ","))
        end
        TasInput.play(Toggles.ReplayInput and Toggles.ReplayInput.Value, keys, mouse)
        local index = math.max(nextFrame - 1, 1)
        if TasMotion.humanoid ~= getHumanoid() then
            TasMotion.hold()
        end
        TasMotion.apply(frames, index, elapsed)
        local playingCharacter = getCharacter()
        local playingAnimate = playingCharacter and playingCharacter:FindFirstChild("Animate")
        if playingAnimate and playingAnimate:IsA("BaseScript") then
            if TasAnimator.animate ~= playingAnimate then
                TasAnimator.animate = playingAnimate
                TasAnimator.animateWasDisabled = false
            end
            if not playingAnimate.Disabled then
                playingAnimate.Disabled = true
            end
        end
        TasAnimator.stopForeign()
        if viewAnims then
            applyAnimPlayback(viewAnims, nextFrame - 1, elapsed)
        else
            updateTasAnimator(frames[index], jumped, elapsed)
        end
        if viewObjects then
            applyObjectPlayback(viewObjects, elapsed)
        end
        View.index = math.max(nextFrame - 1, 1)
        if stepping then
            TasInput.releaseAll()
        end
        if nextFrame > #frames then
            stopViewing(frames[#frames])
        end
    end)
end

local function toggleViewPause()
    if not viewingTas then
        return
    end
    viewPaused = not viewPaused
    View.step = false
    if viewPaused then
        TasInput.releaseAll()
    else
        TasInput.resumePending = true
    end
    local rootPart = getRootPart()
    if rootPart then
        rootPart.Anchored = viewPaused
    end
    tasFreezeAnimations(viewPaused)
end

local function takeOver()
    if not viewingTas then
        return
    end
    if not started then
        notify("AeryTAS", "Take Over needs a run that's still going. This one is stopped, so press Start to record a new run.", 4)
        return
    end
    local index = View.index
    stopViewing()
    seekTo(math.min(index, totalFrames()))
end

local function stopRecording()
    if not started then
        return
    end
    stopViewing()
    liveStop()
    started = false
    cursor = nil
    paused = true
    resumeMotion = nil
    sampleAccumulator = 0
    ObjectHold.sync()
    CameraHold.sync()
    local frame = lastRecordedFrame()
    if frame then
        recordTime = frame.Time
    end
    local rootPart = getRootPart()
    if rootPart then
        rootPart.Anchored = false
    end
    updateStatus()
    updateTimeLabel()
    updateCounters()
    notify("AeryTAS", ("Recording stopped (%s). You can view or save it, or start a new one."):format(plural(totalFrames(), "frame")), 4)
end

local function cleanFileName(text)
    local name = tostring(text or "")
    name = name:gsub("%.json$", "")
    name = name:gsub('[\\/:%*%?"<>|]', "")
    name = name:gsub("^%s+", "")
    name = name:gsub("%s+$", "")
    return name
end

local function defaultFileName()
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    local name = ok and type(info) == "table" and info.Name or tostring(game.PlaceId)
    name = name:gsub("[^%w%s]", "")
    name = name:gsub("%s+", "_")
    return name .. "_TAS"
end

local function autoFileName()
    return runTower or currentKitTower() or placeFileName or defaultFileName()
end

local function refreshFileName()
    if started and not runTower then
        runTower = currentKitTower()
    end
    local auto = autoFileName()
    local option = Options.FileName
    if option and auto ~= lastAutoName and (option.Value == lastAutoName or option.Value == "") then
        option:SetValue(auto)
    end
    lastAutoName = auto
end

local overwriteConfirm = { path = nil, expires = 0 }

local function saveRun()
    if not writefile then
        notify("AeryTAS", "Your executor can't write files.", 4)
        return
    end
    local frames = serializeRun()
    if #frames < 2 then
        notify("AeryTAS", "Nothing recorded yet.", 3)
        return
    end
    local name = cleanFileName(Options.FileName and Options.FileName.Value)
    if name == "" then
        name = autoFileName()
    end
    local path = TAS_FOLDER .. "/" .. name .. ".json"
    local existed = isfile and isfile(path)
    if existed and not (overwriteConfirm.path == path and os.clock() <= overwriteConfirm.expires) then
        overwriteConfirm.path = path
        overwriteConfirm.expires = os.clock() + 4
        notify("AeryTAS", name .. ".json already exists. Save again within 4 seconds to overwrite it.", 4)
        return
    end
    overwriteConfirm.path = nil
    local ok, problem = pcall(function()
        if not isfolder("Aery Hub") then
            makefolder("Aery Hub")
        end
        if not isfolder(TAS_FOLDER) then
            makefolder(TAS_FOLDER)
        end
        local function addCFrame(row, components)
            local cframe = CFrame.new(table.unpack(components, 1, 12))
            local axis, angle = cframe:ToAxisAngle()
            local rotation = axis * angle
            if rotation.X ~= rotation.X then
                rotation = Vector3.new()
            end
            table.insert(row, roundTo(components[1], 1000))
            table.insert(row, roundTo(components[2], 1000))
            table.insert(row, roundTo(components[3], 1000))
            table.insert(row, roundTo(rotation.X, 100000))
            table.insert(row, roundTo(rotation.Y, 100000))
            table.insert(row, roundTo(rotation.Z, 100000))
        end
        local packed = {}
        local lastState
        for _, frame in ipairs(frames) do
            local row = { frame.time }
            addCFrame(row, frame.CCFrame)
            addCFrame(row, frame.CCameraCFrame)
            table.insert(row, frame.VVelocity[1])
            table.insert(row, frame.VVelocity[2])
            table.insert(row, frame.VVelocity[3])
            local extra = {}
            local hasExtra = false
            if frame.SState ~= nil and frame.SState ~= lastState then
                extra.s = frame.SState
                lastState = frame.SState
                hasExtra = true
            end
            for key, field in pairs({ z = "ZZoom", l = "LLock", a = "AAnim", o = "OObjects", k = "KKeys", m = "MMouse", w = "WWheel" }) do
                if frame[field] ~= nil then
                    extra[key] = frame[field]
                    hasExtra = true
                end
            end
            if hasExtra then
                table.insert(row, extra)
            end
            table.insert(packed, row)
        end
        writefile(path, HttpService:JSONEncode({ v = 2, k = frames[1].OKeys, f = packed }))
    end)
    if ok then
        runSaved = true
        local verb = existed and "Overwrote" or "Saved"
        local details = plural(#frames, "frame")
        if ObjectRecorder.count > 0 then
            details = details .. ", " .. plural(ObjectRecorder.count, "object")
        end
        notify("AeryTAS", ("%s %s.json (%s, %s)."):format(verb, name, details, formatTime(frames[#frames].time or 0)), 5)
    else
        notify("AeryTAS", "Couldn't save the run: " .. tostring(problem), 5)
    end
end

local function restartRecording()
    stopViewing()
    liveStop()
    started = false
    runTower = nil
    cursor = nil
    paused = true
    resumeMotion = nil
    sampleAccumulator = 0
    ObjectHold.sync()
    CameraHold.sync()
    recordTime = 0
    currentSegment = {}
    savestates = {}
    runSaved = true
    confirmNewRunUntil = 0
    resetObjectRecorder()
    local rootPart = getRootPart()
    if rootPart then
        rootPart.Anchored = false
    end
    updateStatus()
    updateTimeLabel()
    updateCounters()
end


local KEYBINDS = {
    { id = "PauseKey", group = "Recording", text = "Start / Pause", default = "E", run = togglePause, release = false },
    { id = "StopKey", group = "Recording", text = "Stop", default = "N", run = stopRecording, release = false },
    { id = "SaveKey", group = "Recording", text = "Save", default = "M", run = saveRun, release = false },
    { id = "StepForwardKey", group = "Frames", text = "Frame Advance", default = "G", run = function()
        task.spawn(holdFrameAdvance)
    end, release = function()
        steppingForward = false
    end },
    { id = "StepBackKey", group = "Frames", text = "Frame Back", default = "F", run = function()
        task.spawn(holdFrameBack)
    end, release = function()
        steppingBack = false
    end },
    { id = "SeekForwardKey", group = "Frames", text = "Go Forward", default = "T", run = function()
        task.spawn(holdSeek, 1)
    end, release = function()
        seekDirection = 0
    end },
    { id = "SeekBackKey", group = "Frames", text = "Go Backward", default = "Q", run = function()
        task.spawn(holdSeek, -1)
    end, release = function()
        seekDirection = 0
    end },
    { id = "AddSavestateKey", group = "Savestates", text = "Add", default = "X", run = addSavestate, release = false },
    { id = "RemoveSavestateKey", group = "Savestates", text = "Remove", default = "B", run = removeSavestate, release = false },
    { id = "LastSavestateKey", group = "Savestates", text = "Go to Last", default = "V", run = goToLastSavestate, release = false },
    { id = "ViewKey", group = "Viewing", text = "View", default = "Z", run = viewTas, release = false },
    { id = "ViewPauseKey", group = "Viewing", text = "Pause", default = "R", run = toggleViewPause, release = false },
    { id = "StopViewKey", group = "Viewing", text = "Stop", default = "L", run = stopViewing, release = false },
    { id = "TakeOverKey", group = "Viewing", text = "Take Over", default = "H", run = takeOver, release = false },
    { id = "CollisionKey", group = "Other", text = "Collision", default = "C", run = toggleCollisionUnderMouse, release = false },
    { id = "CloseKey", group = "Other", text = "Close", default = "None", run = function()
        Library:Unload()
    end, release = false },
}

do
    local shared = getgenv and getgenv() or _G
    local previous = shared.AeryTASRecorder
    if previous and previous ~= Library and previous.Unloaded ~= true and type(previous.Unload) == "function" then
        pcall(previous.Unload, previous)
    end
    shared.AeryTASRecorder = Library
end

local UI = {
    visible = true,
    setVisible = nil,
    listening = nil,
    dirty = false,
    settingsPath = "Aery Hub/TAS Recorder/settings.json",
    keybindIds = {},
    repaintTheme = nil,
    setFont = nil,
}

function UI.option(store, id, kind, default, callback)
    local option = { Type = kind, Value = default, Default = default, Callback = callback, widget = nil }
    function option:SetValue(value)
        if value == self.Value then
            return
        end
        self.Value = value
        UI.dirty = true
        if self.widget then
            self.widget(value)
        end
        if self.Callback then
            self.Callback(value)
        end
    end
    store[id] = option
    return option
end

function UI.text(initial)
    local holder = { text = initial, visible = true, label = nil, frame = nil, labels = {} }
    function holder:SetText(text)
        self.text = text
        if self.label then
            self.label.Text = text
        end
        for _, extra in ipairs(self.labels) do
            extra.Text = text
        end
    end
    function holder:SetVisible(visible)
        self.visible = visible
        if self.frame then
            self.frame.Visible = visible
        end
    end
    return holder
end

statusLabel = UI.text("Status: Idle")
timeLabel = UI.text("Time: 0:00.000")
framesLabel = UI.text("Frame: 0 / 0")
savestatesLabel = UI.text("Savestates: 0")
objectsLabel = UI.text("Objects: 0")
fpsLabel = UI.text("Game FPS: -")
pauseButton = UI.text("Start Recording")
viewButton = UI.text("View TAS")
hud = UI.text("0:00.000  |  Idle")

UI.themes = {
    { "Monochrome", "ebebeb", "141414", "ffffff", "0e0e0e", "464646" },
    { "Lavender", "f1e8ff", "211a2c", "b57edc", "16111f", "3e3054" },
    { "Pumpkin", "ffe3c4", "24140a", "ff7518", "160c05", "4a2a12" },
    { "Midnight", "e6ecff", "131a2b", "4f7cff", "0b0f1a", "25304d" },
    { "Mint", "e6fff4", "13201d", "3ddc97", "0b1412", "22392f" },
    { "Crimson", "ffe6e7", "211214", "e5484d", "140a0b", "3d2023" },
}
UI.fonts = {
    { "ProggyClean", "https://raw.githubusercontent.com/bluescan/proggyfonts/139ec08a38096161291792313ef5803fc4f0e37b/ProggyOriginal/ProggyClean.ttf" },
    { "DejaVu Sans", "https://raw.githubusercontent.com/matplotlib/matplotlib/5a84a6f84361b9c94458a85b20c40e8a1ffe55d7/lib/matplotlib/mpl-data/fonts/ttf/DejaVuSans.ttf" },
    { "Code", Enum.Font.Code },
}
UI.fontNames = {}
for _, entry in ipairs(UI.fonts) do
    table.insert(UI.fontNames, entry[1])
end
UI.themeNames = {}
for _, theme in ipairs(UI.themes) do
    table.insert(UI.themeNames, theme[1])
end
table.insert(UI.themeNames, "Custom")

UI.themeKeys = {
    { "FontColor", "Text Color" },
    { "MainColor", "Main Color" },
    { "AccentColor", "Accent Color" },
    { "BackgroundColor", "Background Color" },
    { "OutlineColor", "Outline Color" },
}

function UI.themeColor(name, index)
    local custom = Options[UI.themeKeys[index][1]]
    if name == "Custom" and custom and custom.Value ~= "" then
        local ok, color = pcall(Color3.fromHex, custom.Value)
        if ok then
            return color
        end
    end
    local theme = UI.themes[1]
    for _, entry in ipairs(UI.themes) do
        if entry[1] == name then
            theme = entry
        end
    end
    return Color3.fromHex(theme[index + 1])
end

function UI.applyTheme(name)
    for index, key in ipairs(UI.themeKeys) do
        Linoria[key[1]] = UI.themeColor(name, index)
    end
    Linoria.AccentColorDark = Linoria:GetDarkerColor(Linoria.AccentColor)
    Linoria:UpdateColorsUsingRegistry()
end

UI.applyTheme("Monochrome")

UI.option(Options, "RecordRate", "Dropdown", tostring(DEFAULT_FPS), applyFpsCap)
UI.option(Toggles, "LockFps", "Toggle", true, function(value)
    if value and not setfpscap then
        notify("AeryTAS", "Your executor can't change the frame rate.", 4)
    end
    applyFpsCap()
end)
UI.option(Toggles, "MoveCameraWhilePaused", "Toggle", false, function()
    CameraHold.sync()
end)
UI.option(Toggles, "RecordObjects", "Toggle", true, function()
    ObjectHold.sync()
end)
UI.option(Options, "ObjectRadius", "Slider", 150)
UI.option(Toggles, "ReplayScroll", "Toggle", true)
UI.option(Toggles, "ReplayInput", "Toggle", false, function(value)
    if not value then
        TasInput.releaseAll()
    end
end)
UI.option(Toggles, "ShowHud", "Toggle", true, function(value)
    hud:SetVisible(value)
end)

placeFileName = defaultFileName()
lastAutoName = currentKitTower() or placeFileName
UI.option(Options, "FileName", "Input", lastAutoName)

for _, bind in ipairs(KEYBINDS) do
    UI.option(Options, bind.id, "KeyPicker", bind.default)
    table.insert(UI.keybindIds, { id = bind.id, group = bind.group, text = bind.text })
end
UI.option(Options, "MenuKeybind", "KeyPicker", "U")
table.insert(UI.keybindIds, { id = "MenuKeybind", group = "Other", text = "Show / Hide" })

UI.option(Toggles, "SlowMotion", "Toggle", false)
UI.option(Options, "SlowMotionSpeed", "Slider", 50)
UI.option(Options, "Theme", "Dropdown", "Monochrome", UI.applyTheme)
UI.option(Options, "Font", "Dropdown", "ProggyClean", function(name)
    if UI.setFont then
        UI.setFont(name)
    end
end)
for _, key in ipairs(UI.themeKeys) do
    UI.option(Options, key[1], "Input", "", function()
        if Options.Theme.Value == "Custom" then
            UI.applyTheme("Custom")
        end
    end)
end

do
    local DAMAGE_BRICK_TYPES = { kills = true, double = true, ouch = true, instakills = true, custom = true }

    local LEGACY_DAMAGE_MARKERS = { "instakills", "ouch", "double", "kills" }

    local function isDamageBrick(part)
        if not part:IsA("BasePart") then
            return false
        end
        if IS_TOR then
            local folder = part:FindFirstAncestor("Instakills")
            return (folder ~= nil and folder.Parent ~= nil and folder.Parent.Name == "COParts") or part:FindFirstAncestor("ResetParts") ~= nil
        end
        if part.Name == "InstakillBrick" or part.Name == "KillBrick" then
            return true
        end
        if IS_ASTN then
            for _, name in ipairs({ "KillBrick", "DoubleBrick", "OuchBrick", "InstakillBrick" }) do
                if part.Name == name or part:FindFirstChild(name) then
                    return true
                end
            end
            local teleporter = part.Parent
            return part.Name == "Teleporter" and teleporter ~= nil and teleporter:FindFirstChild("Destination") ~= nil and part:FindFirstAncestor("ClientObjects") ~= nil and part.Size.X >= 10 and part.Size.Z >= 10
        end
        local configuration = part:FindFirstChild("DamageBrickConfiguration")
        if configuration then
            local brickType = configuration:GetAttribute("Type")
            if brickType == "custom" then
                return (tonumber(configuration:GetAttribute("Damage")) or 0) > 0
            end
            if DAMAGE_BRICK_TYPES[brickType] then
                return true
            end
        end
        for _, marker in ipairs(LEGACY_DAMAGE_MARKERS) do
            if part:FindFirstChild(marker) then
                return true
            end
        end
        return part.Parent ~= nil and part.Parent.Name == "KillBricks"
    end

    local function sharedGodmode()
        local env = getgenv and getgenv() or _G
        local state = env.AeryHubGodmode
        if type(state) ~= "table" then
            state = { users = {}, damageHooked = false, remoteHooked = false }
            env.AeryHubGodmode = state
        end
        return state
    end

    local function getCharacterManager()
        local storage = cloneref and cloneref(ReplicatedStorage) or ReplicatedStorage
        return require(storage:WaitForChild("Framework"):WaitForChild("Kit"):WaitForChild("Managers"):WaitForChild("CharacterManager"))
    end

    local function isHarmful(manager, source)
        if typeof(source) == "number" then
            return source > 0
        end
        if typeof(source) == "Instance" and source:IsA("BasePart") then
            local ok, amount = pcall(manager.ValidateDamageBrick, manager, source)
            if not ok then
                return isDamageBrick(source)
            end
            return typeof(amount) == "number" and amount > 0
        end
        return false
    end

    local function carriesDamage(...)
        for i = 1, select("#", ...) do
            local value = select(i, ...)
            if type(value) == "number" and value > 0 then
                return true
            end
        end
        return false
    end

    local function hookDamageRemote(state)
        if state.remoteHooked or not hookmetamethod or not getnamecallmethod then
            return
        end
        local events = IS_TOR and ReplicatedStorage:FindFirstChild("Events")
        local damageEvent = IS_TOR and events and events:FindFirstChild("Instakill") or ReplicatedStorage:FindFirstChild("DamageEvent")
        if not damageEvent then
            local framework = ReplicatedStorage:FindFirstChild("Framework")
            local remotes = framework and framework:FindFirstChild("Remotes")
            local towerRemotes = remotes and remotes:FindFirstChild("Towers")
            local objects = towerRemotes and towerRemotes:FindFirstChild("Objects")
            damageEvent = objects and objects:FindFirstChild("DamageEvent")
        end
        if not damageEvent then
            return
        end
        state.remoteHooked = pcall(function()
            local originalNamecall
            originalNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                if self == damageEvent and next(state.users) ~= nil and getnamecallmethod() == "FireServer" and (IS_TOR or IS_ASTN or carriesDamage(...)) then
                    return
                end
                return originalNamecall(self, ...)
            end))
        end)
    end

    local function enableGodmode()
        local state = sharedGodmode()
        state.users.recorder = true
        hookDamageRemote(state)
        if IS_TOR or IS_ASTN then
            return state.remoteHooked
        end
        if state.damageHooked then
            return true
        end
        return pcall(function()
            local manager = getCharacterManager()
            local originalDamage
            originalDamage = hookfunction(manager.Damage, newcclosure(function(self, source, ...)
                if next(state.users) ~= nil and isHarmful(manager, source) then
                    return
                end
                return originalDamage(self, source, ...)
            end))
            state.damageHooked = true
        end)
    end

    local function disableGodmode()
        sharedGodmode().users.recorder = nil
    end

    local untouchable = {}
    local brickConnection
    local scan = 0

    local function makeUntouchable(part)
        if untouchable[part] == nil and part.Parent and isDamageBrick(part) then
            untouchable[part] = part.CanTouch
            part.CanTouch = false
        end
    end

    local function enableTouchGodmode()
        local towers = workspace:FindFirstChild(IS_TOR and "Obbies" or "Towers")
        if not towers then
            return false
        end
        scan = scan + 1
        local myScan = scan
        brickConnection = towers.DescendantAdded:Connect(function(part)
            task.defer(function()
                if part.Parent then
                    makeUntouchable(part)
                end
            end)
        end)
        task.spawn(function()
            for index, part in ipairs(towers:GetDescendants()) do
                if scan ~= myScan then
                    return
                end
                makeUntouchable(part)
                if index % 150 == 0 then
                    task.wait()
                end
            end
        end)
        return true
    end

    local function disableTouchGodmode()
        scan = scan + 1
        if brickConnection then
            brickConnection:Disconnect()
            brickConnection = nil
        end
        for part, canTouch in pairs(untouchable) do
            if part.Parent then
                part.CanTouch = canTouch
            end
        end
        table.clear(untouchable)
    end

    Library:OnUnload(function()
        disableGodmode()
        disableTouchGodmode()
    end)

    UI.option(Toggles, "Godmode", "Toggle", false, function(enabled)
        local turnOff = function()
            notify("Godmode", "Godmode isn't supported in this game.")
            task.defer(function()
                Toggles.Godmode:SetValue(false)
            end)
        end
        if game.GameId == TEA_GAME_ID then
            if enabled then
                if not enableTouchGodmode() then
                    turnOff()
                end
            else
                disableTouchGodmode()
            end
            return
        end
        if enabled then
            if not enableGodmode() then
                turnOff()
            elseif IS_TOR or IS_ASTN then
                enableTouchGodmode()
            end
        else
            disableGodmode()
            disableTouchGodmode()
        end
    end)
end

local PHYSICS_INPUTS = {
    { id = "PhysicsWalkSpeed", key = "WalkSpeed", text = "Walk Speed", tip = "Your walk speed. Roblox's default is 16." },
    { id = "PhysicsJumpPower", key = "JumpPower", text = "Jump Power", tip = "How high you jump. Roblox's default is 50." },
    { id = "PhysicsGravity", key = "Gravity", text = "Gravity", tip = "The game's gravity. Roblox's default is 196.2." },
    { id = "PhysicsFriction", key = "Friction", text = "Friction", tip = "How much your character grips the ground, from 0 to 2." },
    { id = "PhysicsDensity", key = "Density", text = "Density", tip = "How heavy your character is, from 0.01 to 100." },
}

local function readPhysicsInputs()
    for _, input in ipairs(PHYSICS_INPUTS) do
        local option = Options[input.id]
        local value = option and tonumber(option.Value)
        if value and input.key == "Friction" then
            value = math.clamp(value, 0, 2)
        elseif value and input.key == "Density" then
            value = math.clamp(value, 0.01, 100)
        elseif value and value < 0 then
            value = nil
        end
        Physics.custom[input.key] = value
    end
end

for _, input in ipairs(PHYSICS_INPUTS) do
    UI.option(Options, input.id, "Input", "", readPhysicsInputs)
end

function UI.resetPhysics()
    for _, input in ipairs(PHYSICS_INPUTS) do
        Options[input.id]:SetValue("")
    end
    readPhysicsInputs()
    restorePhysics()
end

function UI.saveSettings()
    UI.dirty = false
    local values = {}
    for _, store in ipairs({ Options, Toggles }) do
        for id, option in pairs(store) do
            if id ~= "FileName" and option.Value ~= option.Default then
                values[id] = option.Value
            end
        end
    end
    pcall(function()
        if not isfolder("Aery Hub") then
            makefolder("Aery Hub")
        end
        if not isfolder("Aery Hub/TAS Recorder") then
            makefolder("Aery Hub/TAS Recorder")
        end
        writefile(UI.settingsPath, HttpService:JSONEncode(values))
    end)
end

function UI.loadSettings()
    local ok, values = pcall(function()
        return HttpService:JSONDecode(readfile(UI.settingsPath))
    end)
    if not ok or type(values) ~= "table" then
        return
    end
    for _, store in ipairs({ Options, Toggles }) do
        for id, option in pairs(store) do
            local value = values[id]
            if value ~= nil and id ~= "FileName" and type(value) == type(option.Value) then
                option:SetValue(value)
            end
        end
    end
end

updateHud()

task.spawn(function()
    while not Library.Unloaded do
        refreshFileName()
        if UI.dirty then
            UI.saveSettings()
        end
        task.wait(1)
    end
end)

local fpsFrames, fpsClock, fpsSlowFor = 0, 0, 0
table.insert(connections, RunService.Heartbeat:Connect(function(deltaTime)
    fpsFrames = fpsFrames + (1)
    fpsClock = fpsClock + deltaTime
    if fpsClock >= 0.5 then
        gameFps = math.floor(fpsFrames / fpsClock + 0.5)
        if fpsLabel then
            fpsLabel:SetText("Game FPS: " .. gameFps)
        end
        local locked = setfpscap and Toggles.LockFps and Toggles.LockFps.Value
        if locked and started and not paused and not viewingTas and gameFps < recordFps() * 0.9 then
            fpsSlowFor = fpsSlowFor + fpsClock
            if fpsSlowFor >= 2 and not runFpsWarned then
                runFpsWarned = true
                notify("AeryTAS", ("Your game runs at %d FPS, below the %d FPS you record at, so this run may replay unevenly. Pick a lower Recording FPS."):format(gameFps, recordFps()), 6)
            end
        else
            fpsSlowFor = 0
        end
        updateHud()
        fpsFrames, fpsClock = 0, 0
    end

    updatePhysics()
    liveStep(deltaTime)
    if CameraHold.active then
        CameraHold.zoom = CameraHold.zoom or getCameraZoom()
        if CameraHold.zoom then
            TasMotion.setZoom(CameraHold.zoom)
        end
    end
    if TasMotion.releaseAt and os.clock() >= TasMotion.releaseAt then
        TasMotion.unlockZoom()
    end

end))

RunService:BindToRenderStep("AeryTASCapture", Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
    if not started or paused or viewingTas or Library.Unloaded or not getRootPart() then
        return
    end
    local gameDelta = deltaTime * Physics.appliedScale
    local interval = recordFps() ^ -1
    local takeFrame
    recordTime = recordTime + gameDelta
    if setfpscap and Toggles.LockFps and Toggles.LockFps.Value then
        takeFrame = true
    else
        sampleAccumulator = sampleAccumulator + gameDelta
        takeFrame = sampleAccumulator >= interval - gameDelta / 2
        if takeFrame then
            sampleAccumulator = math.min(sampleAccumulator - interval, interval)
        end
    end
    if takeFrame then
        runSaved = false
        local frame = captureFrame()
        liveSnapshot(frame, false)
        if #Scroll.pending > 0 then
            frame.Wheel = table.concat(Scroll.pending, ",")
            Scroll.pending = {}
        end
        if #TasInput.pending > 0 then
            frame.Keys = table.concat(TasInput.pending, ",")
            TasInput.pending = {}
        end
        local recordObjects = not Toggles.RecordObjects or Toggles.RecordObjects.Value
        if recordObjects and (ObjectRecorder.forceFull or recordTime < ObjectRecorder.lastSample or recordTime - ObjectRecorder.lastSample >= OBJECT_INTERVAL) then
            frame.Objects = sampleObjects()
            ObjectRecorder.lastSample = recordTime
        end
        table.insert(currentSegment, frame)
        updateCounters()
    end
    updateTimeLabel()
end)

table.insert(connections, UserInputService.InputChanged:Connect(function(input, gameProcessed)
    if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
        return
    end
    if started and not viewingTas and input.Position.Z ~= 0 then
        table.insert(Scroll.pending, input.Position.Z > 0 and "u" or "d")
    end
end))

function TasInput.record(input, gameProcessed, sign)
    if not started or paused or viewingTas or Library.Unloaded then
        return
    end
    local name
    local inputType = input.UserInputType
    if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.MouseButton2 then
        if gameProcessed then
            return
        end
        name = inputType == Enum.UserInputType.MouseButton1 and "b1" or "b2"
    elseif inputType == Enum.UserInputType.Keyboard then
        name = input.KeyCode.Name
        if UserInputService:GetFocusedTextBox() or not TasInput.VK[name] or TasInput.blocked()[name] then
            return
        end
    else
        return
    end
    table.insert(TasInput.pending, sign .. name)
end

table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
    TasInput.record(input, gameProcessed, "+")
end))

table.insert(connections, UserInputService.InputEnded:Connect(function(input, gameProcessed)
    TasInput.record(input, gameProcessed, "-")
end))

table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if UI.listening and input.UserInputType == Enum.UserInputType.Keyboard then
        UI.listening = nil
        return
    end
    if gameProcessed or Library.Unloaded or UI.listening or input.KeyCode == Enum.KeyCode.Unknown then
        return
    end
    local key = input.KeyCode.Name
    if key == Options.MenuKeybind.Value then
        UI.setVisible(not UI.visible)
    end
    for _, bind in ipairs(KEYBINDS) do
        local option = Options[bind.id]
        if option and option.Value == key then
            bind.run()
        end
    end
end))

table.insert(connections, UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Unknown then
        return
    end
    local key = input.KeyCode.Name
    for _, bind in ipairs(KEYBINDS) do
        local option = Options[bind.id]
        if bind.release and option and option.Value == key then
            bind.release()
        end
    end
end))

local diedConnection

local function watchCharacter(character)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if humanoid then
        if diedConnection then
            diedConnection:Disconnect()
        end
        diedConnection = humanoid.Died:Connect(function()
            stopViewing()
            liveStop()
            paused = true
            sampleAccumulator = 0
            ObjectHold.sync()
            CameraHold.release()
            updateStatus()
        end)
    end
end

table.insert(connections, LocalPlayer.CharacterAdded:Connect(function(character)
    task.spawn(watchCharacter, character)
    character:WaitForChild("HumanoidRootPart", 10)
    task.wait(1)
    if started and not Library.Unloaded then
        goToLastSavestate()
    end
end))

if LocalPlayer.Character then
    task.spawn(watchCharacter, LocalPlayer.Character)
end

Library:OnUnload(function()
    pcall(function()
        RunService:UnbindFromRenderStep("AeryTASCapture")
    end)
    stopViewing()
    liveStop()
    TasMotion.release()
    stopTasAnimator()
    steppingForward = false
    steppingBack = false
    seekDirection = 0
    started = false
    if diedConnection then
        diedConnection:Disconnect()
        diedConnection = nil
    end
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)
    paused = true
    ObjectHold.release()
    CameraHold.release()
    for part, original in pairs(collisionEdits) do
        if part.Parent then
            part.CanCollide = original.canCollide
            part.Transparency = original.transparency
        end
    end
    table.clear(collisionEdits)
    restorePhysics()
    local rootPart = getRootPart()
    if rootPart then
        rootPart.Anchored = false
    end
    if originalFpsCap ~= nil and setfpscap then
        pcall(setfpscap, originalFpsCap)
        originalFpsCap = nil
    end
end)

local function buildUi()
    local gui = Instance.new("ScreenGui")
    gui.Name = "AeryTAS"
    gui.DisplayOrder = 100
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = game:GetService("CoreGui")

    local function panel(parent)
        local frame = Instance.new("Frame")
        frame.BackgroundColor3 = Linoria.MainColor
        frame.BorderColor3 = Linoria.OutlineColor
        frame.AutomaticSize = Enum.AutomaticSize.XY
        local padding = Instance.new("UIPadding")
        padding.PaddingTop = UDim.new(0, 5)
        padding.PaddingBottom = UDim.new(0, 5)
        padding.PaddingLeft = UDim.new(0, 7)
        padding.PaddingRight = UDim.new(0, 7)
        padding.Parent = frame
        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromOffset(0, 0)
        label.Font = Linoria.Font
        label.TextSize = 14
        label.TextColor3 = Linoria.FontColor
        label.TextStrokeTransparency = 0
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Top
        label.Parent = frame
        frame.Parent = parent
        Linoria:AddToRegistry(frame, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" })
        Linoria:AddToRegistry(label, { TextColor3 = "FontColor" })
        return frame, label
    end

    local hudFrame, hudLabel = panel(gui)
    hudFrame.Active = true
    hudFrame.Position = UDim2.fromOffset(24, 260)
    hudFrame.Size = UDim2.fromOffset(0, 0)
    hudLabel.AutomaticSize = Enum.AutomaticSize.XY
    hudLabel.Text = hud.text
    hudFrame.Visible = hud.visible
    hud.frame = hudFrame
    hud.label = hudLabel

    local tipFrame, tipLabel = panel(gui)
    tipFrame.Visible = false
    tipFrame.AutomaticSize = Enum.AutomaticSize.Y
    tipFrame.Size = UDim2.fromOffset(280, 0)
    tipLabel.Size = UDim2.new(1, 0, 0, 0)
    tipLabel.AutomaticSize = Enum.AutomaticSize.Y
    tipLabel.TextWrapped = true
    local tipOwner
    local dragStart, dragOrigin

    hudFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragStart, dragOrigin = input.Position, hudFrame.Position
        end
    end)
    table.insert(connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragStart = nil
        end
    end))
    table.insert(connections, UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end
        if dragStart then
            local delta = input.Position - dragStart
            hudFrame.Position = UDim2.fromOffset(dragOrigin.X.Offset + delta.X, dragOrigin.Y.Offset + delta.Y)
        end
        if tipFrame.Visible then
            local mouse = UserInputService:GetMouseLocation()
            tipFrame.Position = UDim2.fromOffset(mouse.X + 16, mouse.Y + 18)
        end
    end))

    local function tip(instance, text)
        if not text then
            return
        end
        instance.MouseEnter:Connect(function()
            tipOwner = instance
            tipLabel.Text = text
            local mouse = UserInputService:GetMouseLocation()
            tipFrame.Position = UDim2.fromOffset(mouse.X + 16, mouse.Y + 18)
            tipFrame.Visible = UI.visible
        end)
        instance.MouseLeave:Connect(function()
            if tipOwner == instance then
                tipOwner = nil
                tipFrame.Visible = false
            end
        end)
    end

    Linoria.AddToolTip = function(_, text, instance)
        tip(instance, text)
    end
    Linoria.ToggleKeybind = { Type = "KeyPicker", Value = "" }
    local window = Linoria:CreateWindow({ Title = "AeryTAS", Center = true, AutoShow = true, TabPadding = 8, Size = UDim2.fromOffset(550, 475) })

    local idCount = 0
    local function newId(id)
        idCount = idCount + 1
        return "AeryTAS" .. id .. idCount
    end

    local function push(option)
        return function(value)
            if not Library.Unloaded then
                option:SetValue(value)
            end
        end
    end

    local function bind(option, set)
        local previous = option.widget
        option.widget = previous and function(value)
            previous(value)
            set(value)
        end or set
    end

    local function page(name, parts)
        local tab = window:AddTab(name)
        for _, part in ipairs(parts) do
            part[3](part[2] == 1 and tab:AddLeftGroupbox(part[1]) or tab:AddRightGroupbox(part[1]))
        end
    end

    local function label(box, holder)
        local element = box:AddLabel(holder.text)
        element.TextLabel.RichText = true
        table.insert(holder.labels, element.TextLabel)
    end

    local function button(box, text, tooltip, callback, double)
        local holder = type(text) == "table" and text or nil
        local element = box:AddButton({ Text = holder and holder.text or text, Func = callback, DoubleClick = double, Tooltip = tooltip })
        if holder then
            table.insert(holder.labels, element.Label)
        end
    end

    local function toggle(box, id, text, tooltip)
        local option = Toggles[id]
        local element = box:AddToggle(newId(id), { Text = text, Default = option.Value, Tooltip = tooltip, Callback = push(option) })
        bind(option, function(value)
            element:SetValue(value)
        end)
    end

    local function slider(box, id, text, min, max, suffix, tooltip)
        local option = Options[id]
        local element = box:AddSlider(newId(id), { Text = text, Default = option.Value, Min = min, Max = max, Rounding = 0, Suffix = suffix, Tooltip = tooltip, Callback = push(option) })
        bind(option, function(value)
            element:SetValue(value)
        end)
    end

    local function dropdown(box, id, text, list, tooltip)
        local option = Options[id]
        local element = box:AddDropdown(newId(id), { Text = text, Values = list, Default = option.Value, Tooltip = tooltip, Callback = function(value)
            if type(value) == "string" then
                push(option)(value)
            end
        end })
        bind(option, function(value)
            element:SetValue(value)
        end)
    end

    local function textbox(box, id, text, placeholder, tooltip, finished)
        local option = Options[id]
        local element = box:AddInput(newId(id), { Text = text, Default = option.Value, Placeholder = placeholder, Finished = finished, Tooltip = tooltip, Callback = push(option) })
        bind(option, function(value)
            element:SetValue(value)
        end)
    end

    local function keybind(box, entry)
        local option = Options[entry.id]
        local id = newId(entry.id)
        local picker
        local holder = box:AddLabel(entry.text)
        holder:AddKeyPicker(id, { Default = option.Value, Text = entry.text, NoUI = true, Mode = "Toggle", Modes = { "Toggle" }, ChangedCallback = function()
            if Library.Unloaded or not picker then
                return
            end
            local key = picker.Value
            if key == "Escape" then
                key = "None"
            end
            if key and key ~= "MB1" and key ~= "MB2" and key ~= option.Value then
                if key ~= "None" then
                    for _, other in ipairs(UI.keybindIds) do
                        if other.id ~= entry.id and Options[other.id].Value == key then
                            Options[other.id]:SetValue("None")
                            notify("AeryTAS", key .. " was used by " .. other.group .. ": " .. other.text .. ", that one is now None.", 4)
                        end
                    end
                end
                option:SetValue(key)
            end
            picker:SetValue({ option.Value, "Toggle" })
        end })
        picker = LinoriaOptions[id]
        bind(option, function(value)
            picker:SetValue({ value, "Toggle" })
        end)
        local pickFrame = holder.TextLabel:FindFirstChildWhichIsA("Frame")
        if pickFrame then
            pickFrame.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    UI.listening = entry.id
                end
            end)
        end
    end

    page("Recorder", {
        { "Run", 1, function(s)
            for _, holder in ipairs({ statusLabel, timeLabel, framesLabel, savestatesLabel, objectsLabel, fpsLabel }) do
                label(s, holder)
            end
            button(s, pauseButton, "Starts a run from where you stand, then pauses and resumes it. Your character is frozen while paused.", togglePause)
            button(s, "Stop Recording", "Ends the run and unfreezes you. The run is kept so you can view or save it.", stopRecording)
            button(s, "Frame Back", "Moves one frame back without deleting anything. Resuming from there drops every frame after it.", frameBack)
            button(s, "Frame Advance", "Moves one frame forward. At the end of the run, plays and records exactly one new frame.", function()
                task.spawn(frameAdvance)
            end)
            button(s, "Add Savestate", "Marks the current frame as a point you can go back to.", addSavestate)
            button(s, "Remove Savestate", "Deletes the newest savestate and everything after it, then moves you to the one before.", removeSavestate)
            button(s, "Go To Last Savestate", "Deletes everything after the newest savestate and moves you back to it.", goToLastSavestate)
            button(s, viewButton, "Plays back everything recorded so far. Nothing is recorded while viewing.", viewTas)
            button(s, "Restart Recording", "Click twice to throw away the whole run.", restartRecording, true)
        end },
        { "Save", 2, function(s)
            textbox(s, "FileName", "File Name", "File name", "Saved as Aery Hub/TAS/<name>.json. Named after your tower unless you type a name.", false)
            button(s, "Save Run", "Writes the whole run to the file. If the name is taken, press again within 4 seconds to replace it.", saveRun)
        end },
        { "Settings", 2, function(s)
            dropdown(s, "RecordRate", "Recording FPS", FRAME_RATES, "How many frames are saved per second.")
            toggle(s, "LockFps", "Lock FPS", "Caps your frame rate to Recording FPS while AeryTAS is open.")
            toggle(s, "MoveCameraWhilePaused", "Move Camera While Paused", "Lets you turn the camera while the run is paused.")
            toggle(s, "RecordObjects", "Record Client Objects", "Records moving parts near you so they move the same way in every replay.")
            slider(s, "ObjectRadius", "Object Radius", 50, 500, nil, "How far from you, in studs, client objects are recorded.")
            toggle(s, "ReplayScroll", "Replay Scroll (AHK)", "Replays your scroll zoom. Needs AHKConnection running.")
            toggle(s, "ReplayInput", "Replay Mouse & Keys", "View TAS moves your cursor and presses the keys and mouse buttons recorded in the run. Sends real input to the Roblox window.")
        end },
    })

    local function keybindGroup(group, help)
        return function(s)
            if help then
                s:AddLabel(help, true)
            end
            for _, entry in ipairs(UI.keybindIds) do
                if entry.group == group then
                    keybind(s, entry)
                end
            end
        end
    end
    page("Keybinds", {
        { "Recording", 1, keybindGroup("Recording", "Click a key, then press the new one. Esc clears it.") },
        { "Frames", 1, keybindGroup("Frames", "Hold a key to repeat it.") },
        { "Savestates", 2, keybindGroup("Savestates") },
        { "Viewing", 2, keybindGroup("Viewing") },
        { "Other", 2, keybindGroup("Other") },
    })

    page("Tweaks", {
        { "Slow Motion", 1, function(s)
            toggle(s, "SlowMotion", "Slow Motion", "Runs your movement and gravity slower so precise jumps are easier. The run is still saved at normal speed.")
            slider(s, "SlowMotionSpeed", "Speed", 10, 100, "%", "How fast you move while Slow Motion is on. 50 is half speed.")
        end },
        { "Bypass", 1, function(s)
            toggle(s, "Godmode", "Godmode", "Killbricks and turrets can't hurt you.")
        end },
        { "Physics", 2, function(s)
            for _, input in ipairs(PHYSICS_INPUTS) do
                textbox(s, input.id, input.text, "Game default", input.tip .. " Press Enter to apply. Leave empty to keep the game's value.", true)
            end
            button(s, "Reset Physics", "Clears every value above and puts the game's own physics back.", UI.resetPhysics)
        end },
    })

    page("Settings", {
        { "Theme", 1, function(s)
            dropdown(s, "Theme", "Theme", UI.themeNames, "The window's colors. Change any color below to make your own Custom theme.")
            local quiet = true
            local pickers = {}
            for index, key in ipairs(UI.themeKeys) do
                local pickerId = newId(key[1])
                local holder = s:AddLabel(key[2])
                holder:AddColorPicker(pickerId, { Default = UI.themeColor(Options.Theme.Value, index), Title = key[2], Callback = function(color)
                    if quiet or Library.Unloaded then
                        return
                    end
                    local theme = Options.Theme.Value
                    if theme ~= "Custom" then
                        for other, otherKey in ipairs(UI.themeKeys) do
                            Options[otherKey[1]]:SetValue(UI.themeColor(theme, other):ToHex())
                        end
                    end
                    Options[key[1]]:SetValue(color:ToHex())
                    Options.Theme:SetValue("Custom")
                end })
                pickers[index] = LinoriaOptions[pickerId]
                tip(holder.TextLabel, "The window's " .. string.lower(key[2]) .. ". Changing it saves your colors as the Custom theme.")
            end
            UI.repaintTheme = function()
                quiet = true
                for index, picker in ipairs(pickers) do
                    picker:SetValueRGB(UI.themeColor(Options.Theme.Value, index))
                end
                quiet = false
            end
            bind(Options.Theme, UI.repaintTheme)
            quiet = false
            button(s, "Reset Theme", "Goes back to the default Monochrome theme.", function()
                Options.Theme:SetValue("Monochrome")
            end)
        end },
        { "Window", 2, function(s)
            dropdown(s, "Font", "Font", UI.fontNames, "The window's font. ProggyClean is the Dear ImGui font most CS:GO cheats use, DejaVu Sans looks like the Verdana of skeet and onetap, and Code is Linoria's default.")
            toggle(s, "ShowHud", "Show Run Info", "Shows the run's time, status, frames, savestates, objects and FPS in a small window you can drag anywhere.")
            keybind(s, { id = "MenuKeybind", group = "Other", text = "Show / Hide" })
            button(s, "Close AeryTAS", "Stops recording, unfreezes your character and closes AeryTAS. Unsaved runs are lost.", function()
                Library:Unload()
            end)
        end },
    })

    UI.applyTheme(Options.Theme.Value)

    local fonts = {}
    local currentFont = Font.fromEnum(Enum.Font.Code)
    local function loadFont(name)
        for _, entry in ipairs(UI.fonts) do
            if entry[1] == name and not fonts[name] then
                if typeof(entry[2]) == "EnumItem" then
                    fonts[name] = Font.fromEnum(entry[2])
                else
                    pcall(function()
                        local folder = "Aery Hub/TAS Recorder"
                        for _, path in ipairs({ "Aery Hub", folder }) do
                            if not isfolder(path) then
                                makefolder(path)
                            end
                        end
                        local file = folder .. "/" .. string.gsub(name, " ", "")
                        if not isfile(file .. ".ttf") then
                            writefile(file .. ".ttf", game:HttpGet(entry[2]))
                        end
                        writefile(file .. ".json", HttpService:JSONEncode({ name = name, faces = { { name = "Regular", weight = 400, style = "normal", assetId = getcustomasset(file .. ".ttf") } } }))
                        fonts[name] = Font.new(getcustomasset(file .. ".json"))
                    end)
                end
            end
        end
        return fonts[name]
    end
    local function applyFont(object)
        if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
            object.FontFace = currentFont
        end
    end
    function UI.setFont(name)
        currentFont = loadFont(name) or Font.fromEnum(Enum.Font.Code)
        for _, holder in ipairs({ Linoria.ScreenGui, gui }) do
            for _, object in ipairs(holder:GetDescendants()) do
                applyFont(object)
            end
        end
    end
    for _, holder in ipairs({ Linoria.ScreenGui, gui }) do
        table.insert(connections, holder.DescendantAdded:Connect(function(object)
            task.defer(applyFont, object)
        end))
    end
    UI.setFont(Options.Font.Value)

    function UI.setVisible(visible)
        UI.visible = visible
        Library.Toggled = visible
        tipFrame.Visible = false
        if window.Holder.Visible ~= visible then
            task.spawn(Linoria.Toggle)
        end
    end

    Library:OnUnload(function()
        pcall(Linoria.Unload, Linoria)
        gui:Destroy()
    end)

    Library:OnUnload(function()
        if UI.dirty then
            UI.saveSettings()
        end
    end)
end

buildUi()

restartRecording()
UI.loadSettings()
applyFpsCap()
readPhysicsInputs()
