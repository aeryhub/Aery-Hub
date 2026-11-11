local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

do
    local hasUnsaved = getgenv().AeryHubRouteRecorderUnsaved
    if getgenv().AeryHubRouteRecorder and type(hasUnsaved) == "function" and hasUnsaved() then
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", { Title = "Aery Recorder", Text = "Aery Recorder is already open and its route isn't saved. Save it or unload the recorder first.", Duration = 6 })
        end)
        return
    end
end

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/download/1.6.66/main.lua"))()

local ROUTE_GAME = game.GameId == 3762953501 and "CSCD" or game.GameId == 10768640243 and "TOR" or game.GameId == 5865880597 and "ASTN" or "EToH"
local ROUTE_BASE = "https://raw.githubusercontent.com/aeryhub/Aery-Routes/refs/heads/main/Games/" .. ROUTE_GAME .. "/"
local TREE_URL = "https://api.github.com/repos/aeryhub/Aery-Routes/git/trees/main?recursive=1"
local LITE_LIMIT = 200

local COLOR_ACCENT = Color3.fromRGB(90, 130, 230)
local COLOR_ORANGE = Color3.fromRGB(210, 160, 60)
local COLOR_PURPLE = Color3.fromRGB(170, 90, 210)

local steps = {}
local savedRoute = ""
local recording = false
local topPoints = false
local previewEnabled = true
local numbersEnabled = true
local liteMode = false

local routeList = nil
local routeByLabel = {}
local selectedRoute = nil

local previewObjects = {}
local markerToIndex = setmetatable({}, { __mode = "k" })
local markerByIndex = {}
local lineByIndex = {}
local axisParts = {}
local axisPartInfo = setmetatable({}, { __mode = "k" })

local selectedIndex = nil
local selectionBall = nil
local selectionBox = nil
local moveHandles = nil
local handleStartPos = nil
local dragAxis = nil
local dragStartHit = nil
local dragStartPos = nil
local hoverBox = nil
local connections = {}
local syncing = false

local Window
local statusParagraphs = {}
local routeDropdown, saveNameInput, stepInfo, stepNumberInput, xInput, yInput, zInput, secondsInput, teleportToggle

local redrawPreview
local rebuildList
local refreshPoint
local showSelection

local function routeLabel(entry)
    return ("%s  [%s]"):format(entry.name, entry.category)
end

local function normalToVector(normal)
    if normal == Enum.NormalId.Right then
        return Vector3.new(1, 0, 0)
    elseif normal == Enum.NormalId.Left then
        return Vector3.new(-1, 0, 0)
    elseif normal == Enum.NormalId.Top then
        return Vector3.new(0, 1, 0)
    elseif normal == Enum.NormalId.Bottom then
        return Vector3.new(0, -1, 0)
    elseif normal == Enum.NormalId.Back then
        return Vector3.new(0, 0, 1)
    end
    return Vector3.new(0, 0, -1)
end

local function axisVector(axis)
    if axis == "X" then
        return Vector3.new(1, 0, 0)
    elseif axis == "Y" then
        return Vector3.new(0, 1, 0)
    end
    return Vector3.new(0, 0, 1)
end

local function round2(n)
    return math.floor(n * 100 + 0.5) / 100
end

local function setStatus(text)
    for _, paragraph in ipairs(statusParagraphs) do
        paragraph:SetDesc(text)
    end
end

local function pointOf(step)
    return step.kind == "checkpoint" and step.pos or nil
end

local function loadRegistry()
    if routeList then
        return true, ("Loaded %d routes."):format(#routeList)
    end

    local HttpService = game:GetService("HttpService")
    local ok, tree = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(TREE_URL))
    end)
    if not (ok and type(tree) == "table" and type(tree.tree) == "table") then
        ok, tree = pcall(function()
            local httpRequest = request or http_request or (syn and syn.request)
            local response = httpRequest({ Url = TREE_URL, Method = "GET", Headers = { ["User-Agent"] = "Aery Hub" } })
            return HttpService:JSONDecode(response.Body)
        end)
    end
    local list = {}
    local files = {}
    pcall(function()
        files = listfiles("Aery Hub/Routes/" .. ROUTE_GAME)
    end)
    for _, file in ipairs(files) do
        local name = file:match("([^/\\]+)%.lua$")
        if name then
            list[#list + 1] = { name = name, category = "Local", file = "Aery Hub/Routes/" .. ROUTE_GAME .. "/" .. name .. ".lua" }
        end
    end
    local onlineFailed = not (ok and type(tree) == "table" and type(tree.tree) == "table")
    if onlineFailed then
        tree = { tree = {} }
    end
    for _, entry in ipairs(tree.tree) do
        local folder, name
        if type(entry.path) == "string" then
            folder, name = entry.path:match("^Games/" .. ROUTE_GAME .. "/([^/]+)/(.+)%.lua$")
        end
        if name then
            list[#list + 1] = {
                name = name,
                category = folder,
                routeUrl = ROUTE_BASE .. folder .. "/" .. game:GetService("HttpService"):UrlEncode(name) .. ".lua",
            }
        end
    end
    table.sort(list, function(a, b)
        if a.category ~= b.category then
            return a.category < b.category
        end
        return a.name < b.name
    end)

    routeList = list
    if onlineFailed then
        return #routeList > 0, ("Online route list failed, loaded %d local routes."):format(#routeList)
    end
    return #routeList > 0, ("Loaded %d routes."):format(#routeList)
end

local function track(object)
    previewObjects[#previewObjects + 1] = object
end

local function clearPreview()
    for _, object in ipairs(previewObjects) do
        object:Destroy()
    end
    previewObjects = {}
    markerToIndex = setmetatable({}, { __mode = "k" })
    markerByIndex = {}
    lineByIndex = {}
end

local function clearAxisParts()
    for _, part in ipairs(axisParts) do
        part:Destroy()
    end
    axisParts = {}
    axisPartInfo = setmetatable({}, { __mode = "k" })
end

local function clearHover()
    if hoverBox then
        hoverBox:Destroy()
        hoverBox = nil
    end
end

local function hideSelection()
    clearAxisParts()
    if selectionBox then
        selectionBox:Destroy()
        selectionBox = nil
    end
    if moveHandles then
        moveHandles:Destroy()
        moveHandles = nil
    end
    if selectionBall then
        selectionBall:Destroy()
        selectionBall = nil
    end
end

local function clearSelection()
    selectedIndex = nil
    dragAxis = nil
    dragStartHit = nil
    dragStartPos = nil
    hideSelection()
end

local function makeAxisPart(axis, sign, size, position, color)
    local part = Instance.new("Part")
    part.Name = ("EToH_Move_%s_%s"):format(axis, sign > 0 and "Pos" or "Neg")
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = true
    part.Material = Enum.Material.Neon
    part.Color = color
    part.Size = size
    part.Position = position
    part.Transparency = 0.15
    part.Parent = workspace
    axisParts[#axisParts + 1] = part
    axisPartInfo[part] = { axis = axis, sign = sign }
    return part
end

local function createMoveHandles()
    moveHandles = Instance.new("Handles")
    moveHandles.Name = "EToH_RoutePointMoveHandles"
    moveHandles.Style = Enum.HandlesStyle.Movement
    moveHandles.Color3 = COLOR_ORANGE
    pcall(function()
        moveHandles.AlwaysOnTop = true
    end)
    moveHandles.Parent = LocalPlayer:WaitForChild("PlayerGui")

    moveHandles.MouseButton1Down:Connect(function()
        local step = selectedIndex and steps[selectedIndex]
        handleStartPos = step and step.pos or nil
    end)

    moveHandles.MouseDrag:Connect(function(face, distance)
        local step = selectedIndex and steps[selectedIndex]
        if not step or step.kind ~= "checkpoint" then
            return
        end
        step.pos = (handleStartPos or step.pos) + normalToVector(face) * distance
        step.edited = true
        selectionBall.Position = step.pos
        local marker = markerByIndex[selectedIndex]
        if marker then
            marker.Position = step.pos
        end
        setStatus(("Moving [%d] %s  X %.1f  Y %.1f  Z %.1f"):format(
            selectedIndex, step.name or "Point", step.pos.X, step.pos.Y, step.pos.Z
        ))
    end)

    moveHandles.MouseButton1Up:Connect(function()
        handleStartPos = nil
        if selectedIndex then
            refreshPoint(selectedIndex)
            showSelection()
        end
        setStatus("Point moved. Copy/export will use the new position.")
    end)
end

showSelection = function()
    local step = selectedIndex and steps[selectedIndex]
    if not step or step.kind ~= "checkpoint" then
        hideSelection()
        return
    end
    local pos = step.pos

    if not selectionBall then
        selectionBall = Instance.new("Part")
        selectionBall.Name = "EToH_SelectedRoutePoint"
        selectionBall.Anchored = true
        selectionBall.CanCollide = false
        selectionBall.CanQuery = false
        selectionBall.Shape = Enum.PartType.Ball
        selectionBall.Material = Enum.Material.Neon
        selectionBall.Color = COLOR_ORANGE
        selectionBall.Size = Vector3.new(1.35, 1.35, 1.35)
        selectionBall.Transparency = 0.5
        selectionBall.Parent = workspace
    end
    selectionBall.Position = pos

    if not selectionBox then
        selectionBox = Instance.new("BoxHandleAdornment")
        selectionBox.Name = "EToH_SelectedRoutePointBox"
        selectionBox.AlwaysOnTop = true
        selectionBox.ZIndex = 10
        selectionBox.Color3 = Color3.new(1, 1, 1)
        selectionBox.Transparency = 0.25
        selectionBox.Size = Vector3.new(1.6, 1.6, 1.6)
        selectionBox.Parent = workspace.CurrentCamera
    end
    selectionBox.Adornee = selectionBall

    if not moveHandles then
        createMoveHandles()
    end
    moveHandles.Adornee = selectionBall

    local offset = 2.75
    if #axisParts > 0 then
        for _, part in ipairs(axisParts) do
            local info = axisPartInfo[part]
            part.Position = pos + axisVector(info.axis) * (info.sign * offset)
        end
        return
    end
    makeAxisPart("X", 1, Vector3.new(4, 0.22, 0.22), pos + Vector3.new(offset, 0, 0), Color3.fromRGB(235, 70, 70))
    makeAxisPart("X", -1, Vector3.new(4, 0.22, 0.22), pos - Vector3.new(offset, 0, 0), Color3.fromRGB(150, 45, 45))
    makeAxisPart("Y", 1, Vector3.new(0.22, 4, 0.22), pos + Vector3.new(0, offset, 0), Color3.fromRGB(70, 220, 90))
    makeAxisPart("Y", -1, Vector3.new(0.22, 4, 0.22), pos - Vector3.new(0, offset, 0), Color3.fromRGB(45, 145, 60))
    makeAxisPart("Z", 1, Vector3.new(0.22, 0.22, 4), pos + Vector3.new(0, 0, offset), Color3.fromRGB(80, 140, 255))
    makeAxisPart("Z", -1, Vector3.new(0.22, 0.22, 4), pos - Vector3.new(0, 0, offset), Color3.fromRGB(45, 80, 165))
end

local function updateAxisDrag()
    local step = selectedIndex and steps[selectedIndex]
    if not step or not dragAxis or not dragStartHit or not dragStartPos then
        return
    end
    local hit = Mouse.Hit and Mouse.Hit.Position
    if not hit then
        return
    end
    local direction = axisVector(dragAxis)
    local distance = (hit - dragStartHit):Dot(direction)
    step.pos = dragStartPos + direction * (math.floor(distance / 0.1 + 0.5) * 0.1)
    step.edited = true
    showSelection()
    setStatus(("Moving [%d] %s  X %.1f  Y %.1f  Z %.1f"):format(
        selectedIndex, step.name or "Point", step.pos.X, step.pos.Y, step.pos.Z
    ))
end

local function drawLine(from, to, color)
    local length = (to - from).Magnitude
    if length < 0.01 then
        return nil
    end
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.Material = Enum.Material.Neon
    part.Color = color
    part.Size = Vector3.new(0.15, 0.15, length)
    part.CFrame = CFrame.new(from, to) * CFrame.new(0, 0, -length / 2)
    part.Transparency = 0.15
    part.Parent = workspace
    track(part)
    return part
end

local function drawMarker(position, index, color)
    local marker = Instance.new("Part")
    marker.Anchored = true
    marker.CanCollide = false
    marker.Shape = Enum.PartType.Ball
    marker.Material = Enum.Material.Neon
    marker.Color = color
    marker.Size = Vector3.new(1, 1, 1)
    marker.Position = position
    marker.Transparency = 0.5
    marker.CanQuery = true
    marker.Parent = workspace
    track(marker)
    markerToIndex[marker] = index
    markerByIndex[index] = marker

    local seeThrough = Instance.new("BoxHandleAdornment")
    seeThrough.Name = "EToH_RoutePointSeeThrough"
    seeThrough.Adornee = marker
    seeThrough.AlwaysOnTop = true
    seeThrough.ZIndex = 5
    seeThrough.Color3 = color
    seeThrough.Size = Vector3.new(1.15, 1.15, 1.15)
    seeThrough.Transparency = 0.5
    seeThrough.Parent = workspace.CurrentCamera
    track(seeThrough)

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "EToH_RouteMarkerNumber"
    billboard.Size = UDim2.fromOffset(40, 20)
    billboard.StudsOffset = Vector3.new(0, 1.4, 0)
    billboard.AlwaysOnTop = true
    billboard.Enabled = numbersEnabled
    billboard.Parent = marker

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Text = tostring(index)
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.Parent = billboard
end

redrawPreview = function()
    clearPreview()
    if not previewEnabled then
        return
    end

    local total = 0
    for _, step in ipairs(steps) do
        if pointOf(step) then
            total = total + 1
        end
    end
    local first = liteMode and math.max(1, total - LITE_LIMIT + 1) or 1

    local count = 0
    local previous = nil
    for index, step in ipairs(steps) do
        local point = pointOf(step)
        if point then
            count = count + 1
            if count >= first then
                local color = step.teleport and COLOR_PURPLE or COLOR_ACCENT
                if previous then
                    lineByIndex[index] = drawLine(previous, point, color)
                end
                drawMarker(point, index, color)
            end
            previous = point
        end
    end
end

local function exportTarget(step)
    return ("makeWaypoint(%.3f, %.3f, %.3f)"):format(step.pos.X, step.pos.Y, step.pos.Z)
end

local function towerDifficulty(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local ok, difficulty = pcall(function()
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        if game.GameId == 10768640243 then
            local rating = require(ReplicatedStorage.SharedModules.ObbyIndex)[workspace:GetAttribute("AreaName")][name].TierRating
            return "Tier " .. (rating:match("%d+") or rating)
        end
        if game.GameId == 3762953501 then
            for _, towers in pairs(require(ReplicatedStorage.All_Areas.ALL_TOWERS)) do
                if type(towers) == "table" and type(towers[name]) == "table" then
                    return towers[name].Difficulty
                end
            end
            return nil
        end
        if game.GameId == 5865880597 then
            return workspace.Towers[name].Difficulty.Value
        end
        if game.GameId == 5488708927 then
            local library = require(ReplicatedStorage.Modules.LibraryModule)
            local place = library.PlaceInfo[game.PlaceId] or library.PlaceInfo[tostring(game.PlaceId)]
            return place.Towers[name].Difficulty.Name
        end
        return require(ReplicatedStorage.Framework.Scripts.Shared.Library.TowerLibrary).Data.Towers[name].Difficulty
    end)
    if ok and type(difficulty) == "string" and difficulty:match("^[%w ]+$") then
        return difficulty
    end
    return nil
end

local function exportRoute(name)
    local difficulty = towerDifficulty(name)
    local lines = {
        "return function()",
        "    local route = {}",
        "    local function makeWaypoint(x, y, z)",
        "        local part = Instance.new(\"Part\")",
        "        part.Anchored, part.CanCollide, part.Transparency = true, false, 1",
        "        part.Size = Vector3.new(1, 1, 1)",
        "        part.Position = Vector3.new(x, y, z)",
        "        part.Parent = workspace",
        "        return part",
        "    end",
        "",
    }
    if difficulty then
        table.insert(lines, 1, "-- Difficulty: " .. difficulty)
    end
    for _, step in ipairs(steps) do
        if step.kind == "checkpoint" then
            local target = exportTarget(step)
            if step.teleport then
                lines[#lines + 1] = ("    route[#route + 1] = { type = \"teleport\", target = %s }"):format(target)
            else
                lines[#lines + 1] = "    route[#route + 1] = " .. target
            end
        elseif step.kind == "wait" then
            lines[#lines + 1] = ("    route[#route + 1] = { type = \"wait\", seconds = %g }"):format(step.seconds)
        elseif step.kind == "jump" then
            lines[#lines + 1] = "    route[#route + 1] = \"jump\""
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "    return route"
    lines[#lines + 1] = "end"
    return table.concat(lines, "\n")
end

local function stepLabel(index, step)
    if step.kind == "checkpoint" then
        return ("%d  %s%s  (%.1f, %.1f, %.1f)"):format(
            index, step.name, step.teleport and " [TP]" or "", step.pos.X, step.pos.Y, step.pos.Z
        )
    elseif step.kind == "wait" then
        return ("%d  Pause %gs"):format(index, step.seconds)
    end
    return ("%d  Jump"):format(index)
end

local function refreshEditor()
    local step = selectedIndex and steps[selectedIndex]
    local isPoint = step ~= nil and step.kind == "checkpoint"
    syncing = true
    stepInfo:SetDesc(step and stepLabel(selectedIndex, step) or ("%d steps. Click a marker or type a step number."):format(#steps))
    stepNumberInput:Set(step and tostring(selectedIndex) or "")
    xInput:Set(isPoint and tostring(round2(step.pos.X)) or "")
    yInput:Set(isPoint and tostring(round2(step.pos.Y)) or "")
    zInput:Set(isPoint and tostring(round2(step.pos.Z)) or "")
    secondsInput:Set(step ~= nil and step.kind == "wait" and tostring(step.seconds) or "")
    teleportToggle:Set(isPoint and step.teleport == true, false)
    syncing = false
end

rebuildList = function()
    refreshEditor()
    redrawPreview()
end

local function appendStep()
    refreshEditor()
    if liteMode then
        redrawPreview()
        return
    end
    local index = #steps
    local point = previewEnabled and pointOf(steps[index])
    if not point then
        return
    end
    local color = steps[index].teleport and COLOR_PURPLE or COLOR_ACCENT
    for i = index - 1, 1, -1 do
        local previous = pointOf(steps[i])
        if previous then
            lineByIndex[index] = drawLine(previous, point, color)
            break
        end
    end
    drawMarker(point, index, color)
end

refreshPoint = function(index)
    local marker = markerByIndex[index]
    if not marker then
        rebuildList()
        return
    end
    local point = steps[index].pos
    marker.Position = point
    local function redrawLine(lineIndex, from, to)
        if lineByIndex[lineIndex] then
            lineByIndex[lineIndex]:Destroy()
        end
        lineByIndex[lineIndex] = drawLine(from, to, steps[lineIndex].teleport and COLOR_PURPLE or COLOR_ACCENT)
    end
    for i = index - 1, 1, -1 do
        local previous = pointOf(steps[i])
        if previous then
            redrawLine(index, previous, point)
            break
        end
    end
    for i = index + 1, #steps do
        local nextPoint = pointOf(steps[i])
        if nextPoint then
            redrawLine(i, point, nextPoint)
            break
        end
    end
    refreshEditor()
end

local function selectStep(index)
    local step = steps[index]
    if not step then
        return
    end
    selectedIndex = index
    showSelection()
    refreshEditor()
    if step.kind == "checkpoint" then
        setStatus(("Selected [%d] %s. Drag red/green/blue handles to move it."):format(index, step.name or "Point"))
    end
end

local function moveStep(index, delta)
    local target = index + delta
    if target < 1 or target > #steps then
        return
    end
    steps[index], steps[target] = steps[target], steps[index]
    if selectedIndex == index then
        selectedIndex = target
    elseif selectedIndex == target then
        selectedIndex = index
    end
    rebuildList()
    if selectedIndex then
        showSelection()
    end
end

local function deleteStep(index)
    table.remove(steps, index)
    if selectedIndex == index then
        clearSelection()
    elseif selectedIndex and selectedIndex > index then
        selectedIndex = selectedIndex - 1
    end
    rebuildList()
    if selectedIndex then
        showSelection()
    end
end

local function teleportTo(position)
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end
    root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0)) * (root.CFrame - root.CFrame.Position)
end

local function stepFromPart(part, teleport)
    if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
        return nil
    end
    return {
        kind = "checkpoint",
        name = part.Name,
        part = part,
        pos = part.Position,
        edited = false,
        teleport = teleport == true,
    }
end

local function addStep(step)
    if selectedIndex and selectedIndex < #steps then
        table.insert(steps, selectedIndex + 1, step)
        selectedIndex = selectedIndex + 1
        rebuildList()
    else
        table.insert(steps, step)
        if selectedIndex then
            selectedIndex = #steps
        end
        appendStep()
    end
    if selectedIndex then
        showSelection()
    end
    return selectedIndex or #steps
end

local function addTopPoint(part)
    local cf, size = part.CFrame, part.Size
    local halfY = math.abs(cf.RightVector.Y) * size.X / 2 + math.abs(cf.UpVector.Y) * size.Y / 2 + math.abs(cf.LookVector.Y) * size.Z / 2
    local index = addStep({
        kind = "checkpoint",
        name = part.Name .. " (top)",
        part = nil,
        pos = part.Position + Vector3.new(0, halfY, 0),
        edited = true,
        teleport = false,
    })
    setStatus(("Added [%d] Point on top of %s"):format(index, part.Name))
end

local function addPart(part)
    if topPoints then
        addTopPoint(part)
        return
    end
    for _, step in ipairs(steps) do
        if step.kind == "checkpoint" and step.part == part then
            setStatus("Already have that part: " .. part.Name)
            return
        end
    end
    local index = addStep({
        kind = "checkpoint",
        name = part.Name,
        part = part,
        pos = part.Position,
        edited = false,
        teleport = false,
    })
    setStatus(("Added [%d] %s"):format(index, part.Name))
end

local function addHere()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        setStatus("No character.")
        return
    end
    local index = addStep({
        kind = "checkpoint",
        name = "Point",
        part = nil,
        pos = root.Position,
        edited = true,
        teleport = false,
    })
    setStatus(("Added [%d] Point at your position"):format(index))
end

local function importRoute(source)
    if type(source) ~= "string" or source:match("^%s*$") then
        return false, "Paste a route first."
    end
    local function pathPart(expr)
        if expr:sub(1, #"workspace") ~= "workspace" then
            return nil
        end
        local node = workspace
        local position = #"workspace" + 1
        while node and position <= string.len(expr) do
            local name, nextPosition = expr:match("^%.([%a_][%w_]*)()", position)
            if not name then
                name, nextPosition = expr:match('^%["(.-)"%]()', position)
            end
            if name then
                node = node:FindFirstChild(name)
            else
                local index
                index, nextPosition = expr:match("^:GetChildren%(%)%[(%d+)%]()", position)
                if not index then
                    return nil
                end
                node = node:GetChildren()[tonumber(index)]
            end
            position = nextPosition
        end
        return node and node:IsA("BasePart") and node or nil
    end

    local function target(expr, teleport)
        local x, y, z = expr:match("^makeWaypoint%(%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*%)$")
        if x then
            return { kind = "checkpoint", name = "Point", part = nil, pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z)), edited = true, teleport = teleport }
        end
        local part = pathPart(expr)
        return part and stepFromPart(part, teleport) or nil
    end

    local imported = {}
    for line in source:gmatch("[^\r\n]+") do
        local expr = (line:gsub("%-%-.*$", ""))
        expr = (expr:gsub("^%s*route%[#route %+ 1%]%s*=%s*", ""))
        expr = expr:match("^%s*(.-)%s*,?%s*$")
        if expr ~= "" then
            local step = nil
            local seconds = expr:match('^{%s*type%s*=%s*"wait"%s*,%s*seconds%s*=%s*([%d%.e%-]+)%s*}$')
            local teleportTarget = expr:match('^{%s*type%s*=%s*"teleport"%s*,%s*target%s*=%s*(.-)%s*}$')
            if expr == '"jump"' then
                step = { kind = "jump" }
            elseif seconds then
                step = { kind = "wait", seconds = tonumber(seconds) or 1 }
            elseif teleportTarget then
                step = target(teleportTarget, true)
            else
                step = target(expr, false)
            end
            if step then
                imported[#imported + 1] = step
            end
        end
    end
    if #imported == 0 then
        return false
    end
    clearSelection()
    steps = imported
    savedRoute = exportRoute("")
    rebuildList()
    return true, ("Imported %d steps."):format(#steps)
end

WindUI:AddTheme({
    Name = "Matcha Wind",
    Accent = Color3.fromHex("#cfdfb4"),
    Dialog = Color3.fromHex("#e9f1da"),
    Outline = Color3.fromHex("#d6e5bc"),
    Text = Color3.fromHex("#2f3b24"),
    Placeholder = Color3.fromHex("#6f7f5c"),
    Background = Color3.fromHex("#e3edcf"),
    Button = Color3.fromHex("#8fae5f"),
    Icon = Color3.fromHex("#5f7346"),
    Toggle = Color3.fromHex("#9cc760"),
    Slider = Color3.fromHex("#9cc760"),
    Checkbox = Color3.fromHex("#9cc760"),
    Primary = Color3.fromHex("#8db85a"),
    SliderIcon = Color3.fromHex("#6f7f5c"),
    DropdownTabBackground = Color3.fromHex("#c9dbab"),
    DropdownBackground = Color3.fromHex("#eaf2dc"),
    TabBackground = Color3.fromHex("#e3edcf"),
    TabBackgroundHover = Color3.fromHex("#d8e6bf"),
    TabBackgroundHoverTransparency = 0,
    TabBackgroundActive = Color3.fromHex("#cddfae"),
    TabBackgroundActiveTransparency = 0,
    PanelBackground = Color3.fromHex("#d6e5bc"),
    PanelBackgroundTransparency = 0,
    LabelBackground = Color3.fromHex("#d6e5bc"),
    LabelBackgroundTransparency = 0,
    ElementBackground = Color3.fromHex("#edf4e0"),
    ElementBackgroundTransparency = 0,
})

local THEME_FILE = "Aery Hub/Aery Recorder/theme.txt"
local savedTheme = "Matcha Wind"
pcall(function()
    local name = readfile(THEME_FILE):match("^%s*(.-)%s*$")
    if WindUI:GetThemes()[name] then
        savedTheme = name
    end
end)

if getgenv().AeryHubRouteRecorder then
    pcall(function()
        getgenv().AeryHubRouteRecorder:Destroy()
    end)
end

Window = WindUI:CreateWindow({
    Title = "Aery Recorder",
    Theme = savedTheme,
    Icon = "route",
    Size = UDim2.fromOffset(580, 460),
})
getgenv().AeryHubRouteRecorder = Window
getgenv().AeryHubRouteRecorderUnsaved = function()
    return #steps > 0 and exportRoute("") ~= savedRoute
end

do
    local function hideGlass(object)
        if object:IsA("ImageLabel") and object.Image == "rbxassetid://131126436897551" then
            object.Visible = false
        end
    end
    for _, gui in ipairs({ WindUI.ScreenGui, WindUI.DropdownGui }) do
        for _, object in ipairs(gui:GetDescendants()) do
            hideGlass(object)
        end
        connections[#connections + 1] = gui.DescendantAdded:Connect(hideGlass)
    end
end

local routeTab = Window:Tab({ Title = "Routes", Icon = "map" })
local recordTab = Window:Tab({ Title = "Record", Icon = "circle-dot" })
local stepsTab = Window:Tab({ Title = "Steps", Icon = "list" })

for _, tab in ipairs({ routeTab, recordTab, stepsTab }) do
    statusParagraphs[#statusParagraphs + 1] = tab:Paragraph({
        Title = "Status",
        Desc = "Pick a route and press Load Route, or record your own.",
    })
end

routeDropdown = routeTab:Dropdown({
    Title = "Route",
    Values = {},
    SearchBarEnabled = true,
    MenuWidth = 260,
    Callback = function(label)
        selectedRoute = routeByLabel[label]
    end,
})

routeTab:Button({
    Title = "Load Route",
    Callback = function()
        if not selectedRoute then
            setStatus("Pick a route first.")
            return
        end
        setStatus("Fetching " .. routeLabel(selectedRoute) .. "...")
        local ok, source = pcall(function()
            if selectedRoute.file then
                return readfile(selectedRoute.file)
            end
            return game:HttpGet(selectedRoute.routeUrl)
        end)
        if not ok or type(source) ~= "string" or #source == 0 then
            setStatus("Route fetch failed: " .. tostring(source))
            return
        end
        local imported, message = importRoute(source)
        if imported then
            setStatus(("Loaded %s: %s"):format(routeLabel(selectedRoute), message))
            saveNameInput:Set(selectedRoute.name)
        elseif message then
            setStatus(("Could not import %s: %s"):format(routeLabel(selectedRoute), message))
        else
            setStatus("")
        end
    end,
})

local pasteInput = routeTab:Input({
    Title = "Paste Route",
    Desc = "Paste a route file's code here, then press Load Pasted Route.",
    Type = "Textarea",
    Placeholder = "return function() ...",
})

routeTab:Button({
    Title = "Load Pasted Route",
    Callback = function()
        local _, message = importRoute(pasteInput.Value)
        if message then
            setStatus(message)
        end
    end,
})

routeTab:Button({
    Title = "Copy .lua",
    Callback = function()
        if #steps == 0 then
            setStatus("Nothing to copy yet.")
            return
        end
        local source = exportRoute((saveNameInput.Value or ""):match("^%s*(.-)%s*$"))
        if pcall(setclipboard, source) then
            savedRoute = exportRoute("")
            setStatus(("Copied %d steps."):format(#steps))
        else
            setStatus("Your executor has no setclipboard. The route is in the console.")
            print(source)
        end
    end,
})

saveNameInput = routeTab:Input({
    Title = "Tower",
    Desc = "File name in Aery Hub/Routes/" .. ROUTE_GAME .. ". The hub's Auto Play uses it for this tower.",
    Placeholder = "ToEV",
})

routeTab:Button({
    Title = "Save Route",
    Callback = function()
        local name = (saveNameInput.Value or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if #steps == 0 then
            setStatus("Nothing to save yet.")
            return
        end
        if name == "" or name:find("[/\\:]") or name:find("%.%.") then
            setStatus("Type a tower name, like ToEV.")
            return
        end
        local path = "Aery Hub/Routes/" .. ROUTE_GAME .. "/" .. name .. ".lua"
        local function save()
            local ok, err = pcall(function()
                if not isfolder("Aery Hub") then
                    makefolder("Aery Hub")
                end
                if not isfolder("Aery Hub/Routes") then
                    makefolder("Aery Hub/Routes")
                end
                if not isfolder("Aery Hub/Routes/" .. ROUTE_GAME) then
                    makefolder("Aery Hub/Routes/" .. ROUTE_GAME)
                end
                writefile(path, exportRoute(name))
            end)
            if ok then
                savedRoute = exportRoute("")
                setStatus(("Saved %d steps to %s"):format(#steps, path))
            else
                setStatus("Could not save: " .. tostring(err))
            end
        end
        local okExists, exists = pcall(isfile, path)
        if not (okExists and exists) then
            save()
            return
        end
        Window:Dialog({
            Title = "Replace route",
            Content = ("%s.lua already exists. Replace it with these %d steps?"):format(name, #steps),
            Buttons = {
                { Title = "Replace", Variant = "Primary", Callback = save },
                { Title = "Cancel", Variant = "Tertiary" },
            },
        })
    end,
})

recordTab:Toggle({
    Title = "Record",
    Desc = "Click parts to add them. Press ] to add your position.",
    Value = false,
    Callback = function(value)
        recording = value
        if recording then
            setStatus("Recording: click a part. Press ] to Add Here.")
        else
            clearHover()
            setStatus(("Paused. %d steps so far. Press ] to Add Here."):format(#steps))
        end
    end,
})

recordTab:Toggle({
    Title = "Top Points",
    Desc = "Clicking a part adds a point on top of it instead of the part.",
    Value = false,
    Callback = function(value)
        topPoints = value
    end,
})

recordTab:Button({ Title = "Add Here", Callback = addHere })

recordTab:Button({
    Title = "Add Pause",
    Callback = function()
        setStatus(("Added [%d] Pause (1s)"):format(addStep({ kind = "wait", seconds = 1 })))
    end,
})

recordTab:Button({
    Title = "Add Jump",
    Callback = function()
        setStatus(("Added [%d] Jump"):format(addStep({ kind = "jump" })))
    end,
})

recordTab:Button({
    Title = "Undo",
    Callback = function()
        if #steps == 0 then
            return
        end
        local index = selectedIndex or #steps
        local removed = steps[index]
        local hadSelection = selectedIndex ~= nil
        deleteStep(index)
        if hadSelection and steps[index - 1] then
            selectStep(index - 1)
        end
        setStatus("Undid " .. (removed.name or removed.kind))
    end,
})

recordTab:Button({
    Title = "Clear",
    Callback = function()
        Window:Dialog({
            Title = "Clear route",
            Content = ("Delete all %d steps?"):format(#steps),
            Buttons = {
                {
                    Title = "Clear",
                    Variant = "Primary",
                    Callback = function()
                        clearSelection()
                        steps = {}
                        rebuildList()
                        setStatus("Cleared.")
                    end,
                },
                { Title = "Cancel", Variant = "Tertiary" },
            },
        })
    end,
})

recordTab:Toggle({
    Title = "Preview",
    Value = true,
    Callback = function(value)
        previewEnabled = value
        redrawPreview()
    end,
})

recordTab:Toggle({
    Title = "Point Numbers",
    Value = true,
    Callback = function(value)
        numbersEnabled = value
        for _, object in ipairs(previewObjects) do
            local billboard = object:FindFirstChild("EToH_RouteMarkerNumber")
            if billboard then
                billboard.Enabled = numbersEnabled
            end
        end
    end,
})

recordTab:Toggle({
    Title = "Lite Preview",
    Desc = ("Only show the last %d points."):format(LITE_LIMIT),
    Value = false,
    Callback = function(value)
        liteMode = value
        redrawPreview()
    end,
})

syncing = true

stepInfo = stepsTab:Paragraph({
    Title = "Selected Step",
    Desc = "No steps yet.",
})

stepNumberInput = stepsTab:Input({
    Title = "Step #",
    Placeholder = "1",
    Callback = function(text)
        if syncing then
            return
        end
        local index = tonumber(text)
        if index and steps[math.floor(index)] then
            selectStep(math.floor(index))
        else
            refreshEditor()
        end
    end,
})

do
    local stepButtons = stepsTab:Group({})
    stepButtons:Button({
        Title = "Previous Step",
        Justify = "Center",
        Icon = "",
        Callback = function()
            selectStep(math.max((selectedIndex or 2) - 1, 1))
        end,
    })
    stepButtons:Space()
    stepButtons:Button({
        Title = "Next Step",
        Justify = "Center",
        Icon = "",
        Callback = function()
            selectStep(math.min((selectedIndex or 0) + 1, #steps))
        end,
    })
end

stepsTab:Button({
    Title = "Deselect Step",
    Callback = function()
        clearSelection()
        refreshEditor()
    end,
})

local function editAxis(axis)
    return function(text)
        if syncing then
            return
        end
        local step = selectedIndex and steps[selectedIndex]
        local value = tonumber(text)
        if not step or step.kind ~= "checkpoint" or not value then
            refreshEditor()
            return
        end
        local pos = step.pos
        step.pos = Vector3.new(
            axis == "X" and value or pos.X,
            axis == "Y" and value or pos.Y,
            axis == "Z" and value or pos.Z
        )
        step.edited = true
        refreshPoint(selectedIndex)
        showSelection()
    end
end

xInput = stepsTab:Input({ Title = "X", Placeholder = "-", Callback = editAxis("X") })
yInput = stepsTab:Input({ Title = "Y", Placeholder = "-", Callback = editAxis("Y") })
zInput = stepsTab:Input({ Title = "Z", Placeholder = "-", Callback = editAxis("Z") })

secondsInput = stepsTab:Input({
    Title = "Pause Seconds",
    Placeholder = "-",
    Callback = function(text)
        if syncing then
            return
        end
        local step = selectedIndex and steps[selectedIndex]
        local seconds = tonumber(text)
        if step and step.kind == "wait" and seconds and seconds >= 0 then
            step.seconds = seconds
            refreshEditor()
        else
            refreshEditor()
        end
    end,
})

teleportToggle = stepsTab:Toggle({
    Title = "Teleport",
    Desc = "Teleport to this point instead of flying there.",
    Value = false,
    Callback = function(value)
        if syncing then
            return
        end
        local step = selectedIndex and steps[selectedIndex]
        if step and step.kind == "checkpoint" then
            step.teleport = value
            rebuildList()
        else
            refreshEditor()
        end
    end,
})

syncing = false

stepsTab:Button({
    Title = "Go To Point",
    Callback = function()
        local step = selectedIndex and steps[selectedIndex]
        if step and step.kind == "checkpoint" then
            teleportTo(step.pos)
        end
    end,
})

stepsTab:Button({
    Title = "Move Up",
    Callback = function()
        if selectedIndex then
            moveStep(selectedIndex, -1)
        end
    end,
})

stepsTab:Button({
    Title = "Move Down",
    Callback = function()
        if selectedIndex then
            moveStep(selectedIndex, 1)
        end
    end,
})

stepsTab:Button({
    Title = "Delete Step",
    Callback = function()
        if selectedIndex then
            deleteStep(selectedIndex)
        end
    end,
})

local settingsTab = Window:Tab({ Title = "Settings", Icon = "settings" })

settingsTab:Keybind({
    Title = "Open/Close UI",
    Desc = "Press this key to show or hide the window.",
    Value = "RightShift",
    Callback = function()
        Window:Toggle()
    end,
})

do
    local themeNames = {}
    for name in pairs(WindUI:GetThemes()) do
        themeNames[#themeNames + 1] = name
    end
    table.sort(themeNames)
    settingsTab:Dropdown({
        Title = "Theme",
        Values = themeNames,
        Value = savedTheme,
        Callback = function(name)
            if not WindUI:SetTheme(name) then
                return
            end
            pcall(function()
                if not isfolder("Aery Hub") then
                    makefolder("Aery Hub")
                end
                if not isfolder("Aery Hub/Aery Recorder") then
                    makefolder("Aery Hub/Aery Recorder")
                end
                writefile(THEME_FILE, name)
            end)
        end,
    })
end

settingsTab:Button({
    Title = "Unload",
    Desc = "Close the recorder and remove everything it added.",
    Callback = function()
        Window:Destroy()
    end,
})

Window:OnDestroy(function()
    recording = false
    if getgenv().AeryHubRouteRecorder == Window then
        getgenv().AeryHubRouteRecorder = nil
        getgenv().AeryHubRouteRecorderUnsaved = nil
    end
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    clearHover()
    clearSelection()
    clearPreview()
end)

local function mouseOverWindow()
    local main = Window.UIElements.Main
    if not main or not main.Visible then
        return false
    end
    local mouse = UserInputService:GetMouseLocation()
    local position = main.AbsolutePosition
    local size = main.AbsoluteSize
    return mouse.X >= position.X
        and mouse.X <= position.X + size.X
        and mouse.Y >= position.Y
        and mouse.Y <= position.Y + size.Y
end

local function isPickablePart(target)
    return target ~= nil and target:IsA("BasePart")
end

local function startAxisDrag(target)
    local info = target and axisPartInfo[target]
    local step = selectedIndex and steps[selectedIndex]
    if not info or not step or step.kind ~= "checkpoint" then
        return false
    end
    dragAxis = info.axis
    dragStartHit = Mouse.Hit and Mouse.Hit.Position or step.pos
    dragStartPos = step.pos
    clearHover()
    setStatus(("Dragging %s axis for [%d] %s."):format(info.axis, selectedIndex, step.name or "Point"))
    return true
end

local function nearestMarker(radius)
    local camera = workspace.CurrentCamera
    if not camera then
        return nil
    end
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    if mousePos.X == 0 and mousePos.Y == 0 then
        mousePos = UserInputService:GetMouseLocation()
    end

    local maxDistance = radius * radius
    local bestDistance = nil
    local bestIndex = nil
    for index, marker in pairs(markerByIndex) do
        local step = steps[index]
        local point = step and pointOf(step)
        if point or marker then
            local screen, onScreen = camera:WorldToViewportPoint(point or marker.Position)
            if onScreen and screen.Z > 0 then
                local dx = screen.X - mousePos.X
                local dy = screen.Y - mousePos.Y
                local distance = dx * dx + dy * dy
                if distance <= maxDistance and (not bestDistance or distance < bestDistance) then
                    bestIndex = index
                    bestDistance = distance
                end
            end
        end
    end
    return bestIndex
end

connections[#connections + 1] = Mouse.Move:Connect(function()
    if dragAxis then
        updateAxisDrag()
        return
    end
    if not recording or mouseOverWindow() then
        clearHover()
        return
    end
    local target = Mouse.Target
    if isPickablePart(target) then
        if not hoverBox then
            hoverBox = Instance.new("SelectionBox")
            hoverBox.Color3 = Color3.new(1, 1, 1)
            hoverBox.LineThickness = 0.04
            hoverBox.SurfaceTransparency = 1
            hoverBox.Parent = workspace.CurrentCamera
        end
        hoverBox.Adornee = target
    else
        clearHover()
    end
end)

connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or UserInputService:GetFocusedTextBox() then
        return
    end
    if input.KeyCode == Enum.KeyCode.RightBracket then
        addHere()
        return
    end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 or mouseOverWindow() then
        return
    end
    local target = Mouse.Target
    if startAxisDrag(target) then
        return
    end
    local markerIndex = target and markerToIndex[target]
    if markerIndex then
        selectStep(markerIndex)
        return
    end
    local nearIndex = nearestMarker(24)
    if nearIndex then
        selectStep(nearIndex)
        return
    end
    if recording and isPickablePart(target) then
        addPart(target)
    end
end)

connections[#connections + 1] = UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if not dragAxis then
        return
    end
    dragAxis = nil
    dragStartHit = nil
    dragStartPos = nil
    if selectedIndex then
        refreshPoint(selectedIndex)
        showSelection()
    end
    setStatus("Point moved. Copy/export will use the new position.")
end)

rebuildList()

task.spawn(function()
    local ok, message = loadRegistry()
    setStatus(message)
    if not ok then
        return
    end
    local labels = {}
    for _, entry in ipairs(routeList) do
        local label = routeLabel(entry)
        labels[#labels + 1] = label
        routeByLabel[label] = entry
    end
    routeDropdown:Refresh(labels)
end)
