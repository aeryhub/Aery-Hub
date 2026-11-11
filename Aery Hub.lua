local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

local ETOH_GAME_ID = 3264581003
local TEA_GAME_ID = 5488708927
local CSCD_GAME_ID = 3762953501
local TOR_GAME_ID = 10768640243
local ASTN_GAME_ID = 5865880597
local IS_CSCD = game.GameId == CSCD_GAME_ID
local IS_TOR = game.GameId == TOR_GAME_ID
local IS_ASTN = game.GameId == ASTN_GAME_ID

if game.GameId ~= ETOH_GAME_ID and game.GameId ~= TEA_GAME_ID and not IS_CSCD and not IS_TOR and not IS_ASTN then
    LocalPlayer:Kick("This experience isn't supported. Aery Hub currently only supports EToH, TEA, CSCD, The Obby Realm and Amazing's Tower Supernerfs.")
    return
end

do
    local previousUnload = (getgenv and getgenv() or _G).AeryHubUnload
    if type(previousUnload) == "function" then
        pcall(previousUnload)
    end
end

local REPO = "https://raw.githubusercontent.com/deividcomsono/Obsidian/d62041eda54085a03259c789d4af2be76077379f/"
local Library = loadstring(game:HttpGet(REPO .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(REPO .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(REPO .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

local function notify(title, description, time)
    Library:Notify({ Title = title, Description = description, Time = time or 3 })
end

local kitController
local cscdTower

local function cscdAcronym(name)
    return name:match("^(.-) | ") or name
end

local CSCD_LOBBY_OBJECTS = { LobbyClientSidedObjects = true, ClearLobbyClientSidedObjects = true, TowerKit = true }

local function cscdLoadedTower()
    local clientParts = workspace:FindFirstChild("ClientParts")
    if not clientParts then
        return nil, false
    end
    local towers = workspace:FindFirstChild("Towers")
    local teleporters = workspace:FindFirstChild("Teleporters")
    for _, folder in ipairs(clientParts:GetChildren()) do
        local name = folder.Name
        if not CSCD_LOBBY_OBJECTS[name] then
            if towers and towers:FindFirstChild(name) then
                return name, true
            end
            if teleporters then
                local prefix = name .. " | "
                for _, part in ipairs(teleporters:GetDescendants()) do
                    if part.Name:sub(1, #prefix) == prefix then
                        return name, true
                    end
                end
            end
        end
    end
    return nil, true
end

local function currentKitTower()
    if IS_CSCD then
        local tower, tracked = cscdLoadedTower()
        if tracked then
            return LocalPlayer:GetAttribute("TrackingTools") and tower or nil
        end
        if cscdTower and LocalPlayer:GetAttribute("TrackingTools") then
            return cscdTower
        end
        return nil
    end
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

if IS_CSCD then
    local touchConnections = {}

    local function watchTeleporter(part)
        if not part:IsA("BasePart") then
            return
        end
        table.insert(touchConnections, part.Touched:Connect(function(hit)
            local character = LocalPlayer.Character
            if character and hit:IsDescendantOf(character) then
                cscdTower = cscdAcronym(part.Name)
            end
        end))
    end

    local teleporters = workspace:FindFirstChild("Teleporters")
    if teleporters then
        for _, descendant in ipairs(teleporters:GetDescendants()) do
            watchTeleporter(descendant)
        end
        table.insert(touchConnections, teleporters.DescendantAdded:Connect(watchTeleporter))
    end

    Library:OnUnload(function()
        for _, connection in ipairs(touchConnections) do
            connection:Disconnect()
        end
        table.clear(touchConnections)
    end)
end

local towerLibrary

local function getTowerLibrary()
    if not towerLibrary then
        local ok, module = pcall(function()
            return require(ReplicatedStorage.Framework.Scripts.Shared.Library.TowerLibrary)
        end)
        if ok and type(module) == "table" then
            towerLibrary = module
        end
    end
    return towerLibrary
end

local DIFFICULTY_COLORS = {
    Gingerbread = "#6C584B",
    Effortless = "#3A7622",
    Easy = "#75F347",
    Medium = "#FFFE00",
    Hard = "#FD7C00",
    Difficult = "#FF3232",
    Challenging = "#A00000",
    Intense = "#19232D",
    Remorseless = "#C800C8",
    Insane = "#0000FF",
    Extreme = "#0389FF",
    Terrifying = "#00FFFF",
    Catastrophic = "#FFFFFF",
    Horrific = "#9695FF",
    Unreal = "#5100CB",
    Nil = "#65666D",
    Error = "#E50000",
}

local OUTLINED_DIFFICULTIES = { Nil = true, Unreal = true, Horrific = true, Error = true }

local function torTier(name)
    local ok, rating, color = pcall(function()
        local modules = ReplicatedStorage.SharedModules
        local rating = require(modules.ObbyIndex)[workspace:GetAttribute("AreaName")][name].TierRating
        return rating, require(modules.TierIndex)[rating].TierColor
    end)
    if not ok or type(rating) ~= "string" then
        return nil
    end
    return "Tier " .. (rating:match("%d+") or rating), color
end

local function towerDifficultyName(name)
    if IS_TOR then
        return (torTier(name))
    end
    if IS_CSCD then
        local teleporters = workspace:FindFirstChild("Teleporters")
        if not teleporters or type(name) ~= "string" then
            return nil
        end
        local prefix = name .. " | "
        for _, child in ipairs(teleporters:GetChildren()) do
            if child.Name:sub(1, #prefix) == prefix then
                local difficulty = child.Name:sub(#prefix + 1):match("^%s*(.-)%s*$")
                local lower = difficulty:lower()
                for known in pairs(DIFFICULTY_COLORS) do
                    if known:lower() == lower then
                        return known
                    end
                end
                return difficulty
            end
        end
        return nil
    end
    if game.GameId == TEA_GAME_ID then
        local ok, difficulty = pcall(function()
            local library = require(ReplicatedStorage.Modules.LibraryModule)
            local place = library.PlaceInfo[game.PlaceId] or library.PlaceInfo[tostring(game.PlaceId)]
            return place.Towers[name].Difficulty.Name
        end)
        return ok and type(difficulty) == "string" and difficulty or nil
    end
    if IS_ASTN then
        local tower = type(name) == "string" and workspace:FindFirstChild("Towers") and workspace.Towers:FindFirstChild(name)
        local value = tower and tower:FindFirstChild("Difficulty")
        return value and value:IsA("StringValue") and value.Value ~= "" and value.Value or nil
    end
    local lib = getTowerLibrary()
    local data = lib and type(lib.Data) == "table" and type(lib.Data.Towers) == "table" and lib.Data.Towers[name]
    local difficulty = data and data.Difficulty
    return type(difficulty) == "string" and difficulty or nil
end

local function towerDifficulty(name)
    if IS_TOR then
        local text, color = torTier(name)
        if text and typeof(color) == "Color3" then
            return ('<font color="#%s">\226\150\160 %s</font>'):format(color:ToHex(), text)
        end
        return text
    end
    local text = towerDifficultyName(name)
    if not text then
        return nil
    end
    local color = DIFFICULTY_COLORS[text]
    if not color then
        return text
    end
    local icon = OUTLINED_DIFFICULTIES[text] and "\226\150\161" or "\226\150\160"
    local styled = ('<font color="%s">%s %s</font>'):format(color, icon, text)
    if text == "Intense" then
        styled = ('<stroke color="#8A9BB0" thickness="1">%s</stroke>'):format(styled)
    end
    return styled
end

local panicHandlers = {}

local PANIC_TOGGLES = { "AllJumpMode", "FarmAttempts", "Fly", "Noclip", "InfJump", "Godmode", "DisableVoid" }
local PANIC_SLIDERS = { WalkSpeedSlider = 16, JumpPowerSlider = 50 }

local function runPanic()
    for _, id in ipairs(PANIC_TOGGLES) do
        local toggle = Toggles[id]
        if toggle and toggle.Value then
            pcall(toggle.SetValue, toggle, false)
        end
    end
    for id, value in pairs(PANIC_SLIDERS) do
        local option = Options[id]
        if option and option.Value ~= value then
            pcall(option.SetValue, option, value)
        end
    end
    for _, handler in ipairs(panicHandlers) do
        pcall(handler)
    end
end

local function plural(count, word)
    return ("%d %s%s"):format(count, word, count == 1 and "" or "s")
end

local function getCharacter()
    return LocalPlayer.Character
end

local function getRoot()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local character = LocalPlayer.Character
    return character and character:FindFirstChildWhichIsA("Humanoid")
end

local function disconnectAll(list)
    for _, connection in pairs(list) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(list)
end

local function forEachSlowly(list, callback, keepGoing)
    for index, item in ipairs(list) do
        if not keepGoing() then
            return false
        end
        callback(item)
        if index % 150 == 0 then
            task.wait()
        end
    end
    return true
end

local function isWinpadPart(part)
    if IS_TOR then
        return part.Name == "Winpad" and part.Parent ~= nil and part.Parent.Parent == workspace:FindFirstChild("Obbies")
    end
    if not IS_CSCD then
        return part.Name == "WinPad"
    end
    local winpads = workspace:FindFirstChild("Winpads")
    local parent = part.Parent
    if not winpads or not parent then
        return false
    end
    return parent == winpads or (parent.Parent == winpads and (part.Name == "WinPad" or part.Name == "Winpad"))
end

local function towerNameOf(part, fallback)
    if IS_CSCD then
        local node = part
        while node and node.Parent and node.Parent ~= workspace do
            local parent = node.Parent
            if parent.Parent == workspace and (parent.Name == "Towers" or parent.Name == "Teleporters" or parent.Name == "Winpads") then
                return cscdAcronym(node.Name)
            end
            node = parent
        end
        return fallback
    end
    if IS_ASTN and part.Parent == workspace:FindFirstChild("Portals") then
        local value = part:FindFirstChild("TowerPortal") or part:FindFirstChild("TowerRush")
        return value and value:IsA("StringValue") and value.Value or fallback
    end
    local towers = workspace:FindFirstChild(IS_TOR and "Obbies" or "Towers")
    local name = fallback
    local node = part.Parent
    while node and node ~= towers and node ~= workspace do
        name = node.Name
        node = node.Parent
    end
    return name
end

local Window = Library:CreateWindow({
    Title = "Aery Hub",
    Icon = 140587030575792,
    Footer = "Game: " .. (IS_CSCD and "Caleb's Soul Crushing Domain" or IS_TOR and "The Obby Realm" or IS_ASTN and "Amazing's Tower Supernerfs" or game.GameId == TEA_GAME_ID and "The Eternal Abyss" or "Eternal Towers of Hell"),
    NotifySide = "Right",
    ShowCustomCursor = true,
    AutoShow = false,
})

do
    local shared = getgenv and getgenv() or _G
    shared.AeryHubLibraries = shared.AeryHubLibraries or {}
    local libraries = shared.AeryHubLibraries
    table.insert(libraries, Library)
    local function inheritMouseIcon()
        if not Library.Toggled then
            return
        end
        for _, other in ipairs(libraries) do
            if other ~= Library and other.Unloaded ~= true and other.Toggled and other.OriginalMouseIconEnabled ~= nil then
                Library.OriginalMouseIconEnabled = other.OriginalMouseIconEnabled
                return
            end
        end
    end
    local originalToggle = Window.Toggle
    Window.Toggle = function(self, ...)
        local result = originalToggle(self, ...)
        inheritMouseIcon()
        return result
    end
    inheritMouseIcon()
    Library:OnUnload(function()
        for index = #libraries, 1, -1 do
            if libraries[index] == Library or libraries[index].Unloaded == true then
                table.remove(libraries, index)
            end
        end
    end)
end

local IS_TEA = game.GameId == TEA_GAME_ID
local NullBox
NullBox = setmetatable({}, {
    __index = function()
        return function()
            return NullBox
        end
    end,
})

local Tabs = {
    Main = Window:AddTab("Main", "house"),
    TowerRush = not IS_TEA and not IS_TOR and Window:AddTab("Tower Rush", "swords") or nil,
    Exploits = Window:AddTab("Exploits", "bug"),
    Visuals = Window:AddTab("Visuals", "scan-eye"),
    TAS = Window:AddTab("TAS", "clock"),
    Credits = Window:AddTab("Credits", "award"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

local PlayerBox = (IS_TOR or workspace:FindFirstChild("Towers")) and Tabs.Main:AddRightGroupbox("Player") or Tabs.Main:AddLeftGroupbox("Player")

PlayerBox:AddSlider("WalkSpeedSlider", {
    Text = "Walk Speed",
    Tooltip = "Sets your walk speed. Default is 16.",
    Default = 16,
    Min = 0,
    Max = 100,
    Rounding = 1,
    Compact = false,
    Callback = function(value)
        local humanoid = getHumanoid()
        if humanoid then
            humanoid.WalkSpeed = value
        end
    end,
})

PlayerBox:AddSlider("JumpPowerSlider", {
    Text = "Jump Power",
    Tooltip = "Sets your jump power. Default is 50.",
    Default = 50,
    Min = 0,
    Max = 200,
    Rounding = 1,
    Compact = false,
    Callback = function(value)
        local humanoid = getHumanoid()
        if humanoid then
            humanoid.JumpPower = value
        end
    end,
})

do
    local respawnConnection = LocalPlayer.CharacterAdded:Connect(function(character)
        local humanoid = character:WaitForChild("Humanoid", 10)
        if not humanoid or Library.Unloaded then
            return
        end
        local speed = Options.WalkSpeedSlider.Value
        if speed ~= PANIC_SLIDERS.WalkSpeedSlider then
            humanoid.WalkSpeed = speed
        end
        local power = Options.JumpPowerSlider.Value
        if power ~= PANIC_SLIDERS.JumpPowerSlider then
            humanoid.JumpPower = power
        end
    end)
    Library:OnUnload(function()
        respawnConnection:Disconnect()
    end)
end

PlayerBox:AddDivider()

do
    local jumpConnection
    local debounce = false

    local function onJumpRequest()
        if debounce then
            return
        end
        local humanoid = getHumanoid()
        if not humanoid or humanoid.Health <= 0 then
            return
        end
        if humanoid.FloorMaterial ~= Enum.Material.Air then
            return
        end
        debounce = true
        local jumping = Enum.HumanoidStateType.Jumping
        if not humanoid:GetStateEnabled(jumping) then
            humanoid:SetStateEnabled(jumping, true)
        end
        humanoid:ChangeState(jumping)
        task.delay(0.1, function()
            debounce = false
        end)
    end

    PlayerBox:AddToggle("InfJump", {
        Text = "Inf Jump",
        Default = false,
        Tooltip = "Jump as many times as you want, even midair.",
        Callback = function(enabled)
            if jumpConnection then
                jumpConnection:Disconnect()
                jumpConnection = nil
            end
            debounce = false
            if enabled then
                jumpConnection = UserInputService.JumpRequest:Connect(onJumpRequest)
            end
        end,
    })
end

local PhysicsFixer = { paused = {}, users = {} }

function PhysicsFixer.pause(character, user)
    PhysicsFixer.users[user] = true
    local fixer = character:FindFirstChild("PhysicsFixer")
    if fixer and fixer:IsA("LocalScript") and fixer.Enabled then
        fixer.Enabled = false
        PhysicsFixer.paused[fixer] = true
    end
end

function PhysicsFixer.resume(user)
    PhysicsFixer.users[user] = nil
    if next(PhysicsFixer.users) then
        return
    end
    for fixer in pairs(PhysicsFixer.paused) do
        if fixer.Parent then
            fixer.Enabled = true
        end
    end
    table.clear(PhysicsFixer.paused)
end

do
    local enabled = false
    local steppedConnection
    local watchConnections = {}
    local originalCollide = {}

    local applyNoclip = function()
        local character = getCharacter()
        if not enabled or not character then
            return
        end
        PhysicsFixer.pause(character, "noclip")
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                if originalCollide[part] == nil then
                    originalCollide[part] = part.CanCollide
                    table.insert(watchConnections, part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                        if enabled and part.Parent then
                            part.CanCollide = false
                        end
                    end))
                end
                part.CanCollide = false
            end
        end
    end

    PlayerBox:AddToggle("Noclip", {
        Text = "Noclip",
        Default = false,
        Tooltip = "Walk through walls and objects.",
        Callback = function(state)
            enabled = state
            if steppedConnection then
                steppedConnection:Disconnect()
                steppedConnection = nil
            end
            disconnectAll(watchConnections)
            if state then
                table.clear(originalCollide)
                steppedConnection = RunService.Stepped:Connect(applyNoclip)
            else
                for part, canCollide in pairs(originalCollide) do
                    if part.Parent then
                        part.CanCollide = canCollide
                    end
                end
                table.clear(originalCollide)
                PhysicsFixer.resume("noclip")
            end
        end,
    })
end

do
    local flyConnection
    local controlModule
    local movers = {}

    local function keyDown(key)
        return UserInputService:IsKeyDown(key) and not UserInputService:GetFocusedTextBox()
    end

    local function moveVector()
        if controlModule then
            local ok, vector = pcall(controlModule.GetMoveVector, controlModule)
            if ok and typeof(vector) == "Vector3" then
                return vector
            end
        end
        local x = (keyDown(Enum.KeyCode.D) and 1 or 0) - (keyDown(Enum.KeyCode.A) and 1 or 0)
        local z = (keyDown(Enum.KeyCode.S) and 1 or 0) - (keyDown(Enum.KeyCode.W) and 1 or 0)
        return Vector3.new(x, 0, z)
    end

    local function removeMovers()
        for _, mover in pairs(movers) do
            pcall(function()
                mover:Destroy()
            end)
        end
        table.clear(movers)
    end

    local function buildMovers(root)
        removeMovers()
        local attachment = Instance.new("Attachment")
        attachment.Parent = root
        local velocity = Instance.new("LinearVelocity")
        velocity.Attachment0 = attachment
        velocity.RelativeTo = Enum.ActuatorRelativeTo.World
        velocity.MaxForce = math.huge
        velocity.VectorVelocity = Vector3.zero
        velocity.Parent = root
        local orientation = Instance.new("AlignOrientation")
        orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
        orientation.Attachment0 = attachment
        orientation.MaxTorque = math.huge
        orientation.Responsiveness = 200
        orientation.CFrame = root.CFrame.Rotation
        orientation.Parent = root
        movers.attachment = attachment
        movers.velocity = velocity
        movers.orientation = orientation
    end

    local function stopFlying()
        if flyConnection then
            flyConnection:Disconnect()
            flyConnection = nil
        end
        removeMovers()
        local humanoid = getHumanoid()
        if humanoid then
            humanoid.PlatformStand = false
        end
    end

    PlayerBox:AddToggle("Fly", {
        Text = "Fly",
        Default = false,
        Tooltip = "WASD moves where the camera faces, Space goes up, Left Ctrl goes down.",
        Callback = function(enabled)
            stopFlying()
            if not enabled then
                return
            end
            if not controlModule then
                pcall(function()
                    local playerModule = LocalPlayer.PlayerScripts:WaitForChild("PlayerModule", 5)
                    controlModule = require(playerModule:WaitForChild("ControlModule", 5))
                end)
            end
            flyConnection = RunService.RenderStepped:Connect(function()
                local root = getRoot()
                local humanoid = getHumanoid()
                local camera = workspace.CurrentCamera
                if not root or not humanoid or not camera then
                    return
                end
                if not movers.attachment or movers.attachment.Parent ~= root then
                    buildMovers(root)
                end
                humanoid.PlatformStand = true
                local input = moveVector()
                local look = camera.CFrame.LookVector
                local direction = camera.CFrame.RightVector * input.X - look * input.Z
                if keyDown(Enum.KeyCode.Space) then
                    direction = direction + (Vector3.yAxis)
                end
                if keyDown(Enum.KeyCode.LeftControl) then
                    direction = direction - (Vector3.yAxis)
                end
                if direction.Magnitude > 1 then
                    direction = direction.Unit
                end
                local speed = Options.FlySpeed and Options.FlySpeed.Value or 50
                movers.velocity.VectorVelocity = direction * speed
                movers.orientation.CFrame = camera.CFrame.Rotation
            end)
        end,
    })

    PlayerBox:AddSlider("FlySpeed", {
        Text = "Fly Speed",
        Tooltip = "Sets how fast Fly moves you.",
        Default = 50,
        Min = 10,
        Max = 200,
        Rounding = 0,
        Compact = false,
    })
end

PlayerBox:AddDivider()

do
    local originalDestroyHeight = workspace.FallenPartsDestroyHeight

    PlayerBox:AddToggle("DisableVoid", {
        Text = "Disable Void",
        Default = false,
        Tooltip = "Prevents the void from killing you.",
        Callback = function(enabled)
            workspace.FallenPartsDestroyHeight = enabled and (math.huge - math.huge) or originalDestroyHeight
        end,
    })
end

local TowerRings = {
    Ring0 = { "CoV", "PTR", "TNF", "ToB", "ToBM", "ToCD", "ToDAN", "ToG", "ToKP", "ToKTS", "ToME", "ToNSA", "ToVP" },
    Ring1 = { "CoLS", "CoLS_SE", "NEAT", "R1TR", "ToA", "ToAST", "ToH", "ToIE", "ToIG", "ToK", "ToKY", "ToM", "ToNI", "ToR", "ToS", "ToSP", "ToSP_SE", "ToTS" },
    Ring2 = { "CoWS", "MAT", "R2TR", "ToBH", "ToCH", "ToDC", "ToDD", "ToES", "ToFaF", "ToOH", "ToPS", "ToSD", "ToT", "ToTF" },
    Ring3 = { "CoHaD", "R3TR", "TAT", "ToAT", "ToC", "ToD", "ToDS", "ToF", "ToFT", "ToIC", "ToLD", "ToSI", "ToWER", "ToWH" },
    Ring4 = { "CoU", "R4TR", "ToCN", "ToDaD", "ToE", "ToGG", "ToHF", "ToI", "ToL", "ToLL", "ToNP", "ToO", "ToSH", "ToTM", "ToVS", "WBAT" },
    Ring5 = { "CoCR", "LAT", "R14MTR", "R5TR", "ToDM", "ToEA", "ToFF", "ToFN", "ToFO", "ToGaH", "ToIB", "ToNV", "ToOC", "ToRS", "ToTH", "ToTR" },
    Ring6 = { "CoSR", "ToEP", "ToFJ", "ToIM", "ToISC", "ToN", "ToRR", "ToSM", "ToTI" },
    Ring7 = { "CoTE", "FFAST", "ToEH", "ToER", "ToTB" },
    Ring8 = { "ToGF" },
    Ring9 = { "CoL", "R9TR", "ToAM", "ToBBB", "ToBK", "ToBT", "ToCA", "ToCP", "ToCR", "ToFaCT", "ToGO", "ToHA", "ToJE", "ToNS", "ToPP", "ToQT" },
    Zone1 = { "CoP", "SAT", "ToAD", "ToAV", "ToCO", "ToED", "ToHS", "ToMH", "ToP", "ToPHaT", "ToRNI", "ToTL", "ToUT", "ToWEL", "ToYS", "ToZ", "ToZD", "Z1TR" },
    Zone2 = { "ToDT", "ToSA", "ToVR" },
    Zone3 = { "CoTS", "ToBB", "ToCOF", "ToHH", "ToOD" },
    Zone4 = { "CoQ", "ToAAA", "ToAC", "ToDDD", "ToET", "ToFG", "ToFSC", "ToFaST", "ToIF", "ToMIM", "ToPC", "ToSS", "ToTV", "ToUID", "ToWW", "Z4TR" },
    Zone5 = { "ToAR", "ToPZ" },
    Zone6 = { "ToMM" },
    Zone7 = { "CoACT", "ToBR", "ToCE", "ToCMC", "ToDF", "ToFM", "ToGM", "ToJ", "ToRW", "ToSV", "ToSaPS", "ToUA", "ToUI", "ToWS", "ToY", "Z7TR" },
    Zone8 = { "CoPE", "ToAE", "ToDIE" },
    Zone9 = { "CoIC", "ToABCD", "ToBBBB", "ToBL", "ToDTD", "ToEC", "ToEMP", "ToFCB", "ToFU", "ToHR", "ToMF", "ToNN", "ToPB", "ToSRD", "ToVITE", "ToWWW", "Z9TR" },
    Zone10 = { "ToBP", "ToCZ", "ToIT", "ToRL", "ToRT", "ToRoMW", "ToTHT", "ToVV" },
    SilentAbyss = { "ToSA" },
    ArcaneArea = { "AATR", "SoAP", "SoAS", "SoBT", "SoCA", "SoMC", "SoME", "SoRO", "SoTC", "SoWC", "ToIA" },
    AshenTowerworks = { "ATwTR", "ToCB", "ToCWC", "ToFSF", "ToFZ", "ToLLL", "ToMD", "ToRH", "ToSR", "ToVT", "ToWF", "ToWIA", "ToWMT", "ToWoW" },
    LostRiver = { "CoIS", "LRTR", "ToCS", "ToDL", "ToEW", "ToLOZ", "ToOO", "ToTEM", "ToTJ", "ToTST", "ToUH", "ToWaW" },
    ForgottenRidge = { "CoWN", "SoC", "SoHP", "SoLW", "SoMD", "SoP", "SoTP", "SoUR", "SoWP", "TIPAT", "ToDE", "ToII", "ToIS", "ToJGF", "ToMB", "ToTC", "ToV" },
    GardenOfEeshol = { "GoETR", "NEAF", "SoBA", "SoBJ", "SoDS", "SoFF", "SoFW", "SoGP", "SoIF", "SoLIQ", "SoN", "SoO", "SoOA", "SoVV", "ToPA" },
    DarkSideoftheMoon = { "ToFC", "ToMG", "ToMP", "ToPW", "ToQ" },
    ParadiseAtoll = { "SoUV" },
    SteelspireHorizon = { "ToSH" },
    ElysianFields = { "SoGE" },
    HeccfireDepths = { "SoRP" },
    LegacyFortress = { "LFTR", "ToC(L)", "ToG(L)", "ToGI(L)", "ToMD(L)", "ToPS(L)", "ToST(L)", "ToT(L)", "ToTE(L)", "ToTU(L)", "ToUB(L)", "ToUP(L)", "ToWS(L)" },
    SummitOfMemories = { "ToSM" },
    TimelessManor = { "ToTM" },
    TheDoghouse = { "ToDH" },
    ["Pit-of-Misery"] = { "PoMTR", "ToBF", "ToEV", "ToG", "ToGF", "ToMDC", "ToOLC", "ToP", "ToSE", "ToSF", "ToTH", "ToTRP", "ToVH", "ToWM", "WAT" },
    TheEternalAbyss = { "ToEA" },
    BIOUMS = { "MS" },
    ["100M-Event-Replay"] = { "100MC", "100MF", "100MR", "100MT" },
    Scope1 = { "ToScope1" },
    HalloweenEvent2026 = { "SoH" },
}

local ROUTE_GAME = IS_CSCD and "CSCD" or IS_TOR and "TOR" or IS_ASTN and "ASTN" or "EToH"
local ROUTE_BASE = "https://raw.githubusercontent.com/aeryhub/Aery-Routes/refs/heads/main/Games/" .. ROUTE_GAME .. "/"

local PLACE_RING = {
    [15873244701] = { "TheEternalAbyss", "Pit-of-Misery" },
    [9070958509] = "Ring0", [9070657865] = "Ring1", [9070979698] = "Ring2", [9070980083] = "Ring3",
    [9070980555] = "Ring4", [9070980846] = "Ring5", [9070981164] = "Ring6", [9070981409] = "Ring7",
    [9070981722] = "Ring8", [9070982474] = "Ring9",
    [9071001075] = "Zone1", [9071001366] = "Zone2", [9071001563] = "Zone3", [9071001883] = "Zone4",
    [9071002104] = "Zone5", [9071002463] = "Zone6", [9071002677] = "Zone7", [9071002915] = "Zone8",
    [9071004505] = "Zone9", [9071004898] = "Zone10",
    [9070954594] = "ForgottenRidge", [9070960075] = "GardenOfEeshol", [76003383649350] = "DarkSideoftheMoon",
    [15639952229] = "Pit-of-Misery", [121814103864070] = "Pit-of-Misery",
    [131042387601353] = "TimelessManor", [115856553162061] = "100M-Event-Replay", [111393548264972] = "BIOUMS",
    [9070944007] = "ArcaneArea", [14399266686] = "AshenTowerworks", [95241871632790] = "ElysianFields",
    [9070963935] = "HeccfireDepths", [116826560849733] = "LegacyFortress", [9945448769] = "LostRiver",
    [9070975342] = "ParadiseAtoll", [11916533264] = "SilentAbyss", [18538513621] = "SteelspireHorizon",
    [90713610472463] = "SummitOfMemories", [16976865869] = "TheDoghouse",
    [11516779046] = "Scope1",
    [18892014130] = "HalloweenEvent2026",
}

local ROUTE_AREAS = IS_CSCD and {
    [10284097192] = "Scope1", [11336299336] = "TheNilZone", [10284095469] = "Scope2",
    [110118540850785] = "LushColosseum", [108802919009038] = "BreakingPoint",
    [98973761521173] = "TimekeeperArchive", [11139578249] = "HauntedValley", [18986339218] = "FoolsNilZone",
    [11534310219] = "BlackrockRavine", [18907688613] = "TropicalIsles", [133967265657551] = "OneOverAMillion",
    [81058558877489] = "TheJuntMegaEdition", [111832585205629] = "Scope0", [125648358719301] = "ToVLClassic",
    [11504336574] = "Scope3", [75067728300321] = "Scope3", [119901287296729] = "FloatyIsland",
} or IS_TOR and { [140664680860222] = "AshenHollow" } or IS_ASTN and {
    [17120699596] = "RingSelect", [17120707813] = "Ring1", [17120753412] = "Ring2",
    [109105112902803] = "Ring3", [87827917737017] = "Ring4",
    [112049880480276] = "AprilFools", [128163013785935] = "Archipelago",
} or PLACE_RING

local AREA_DISPLAY_NAMES = {
    DarkSideoftheMoon = "Dark Side of the Moon",
    ["TEA-Pit of Misery"] = "TEA-Pit of Misery",
}

local function areaName(area)
    if AREA_DISPLAY_NAMES[area] then
        return AREA_DISPLAY_NAMES[area]
    end
    local name = area:gsub("%-", " "):gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2"):gsub(" Of ", " of ")
    return name
end

local function areaNames(areas)
    local names = {}
    for _, area in ipairs(areas) do
        table.insert(names, areaName(area))
    end
    return table.concat(names, ", ")
end

local ROUTE_MAX_GAP = 50
local ROUTE_MAX_SHIFT = 300
local ROUTE_SHIFT_CANDIDATES = 16
local ROUTE_SHIFT_PENALTY = 3

local ChatCommands = { enter = nil, complete = nil, stop = nil, portal = nil }
local TOUCH = HttpService:JSONDecode("[0, 1]")

if workspace:FindFirstChild(IS_TOR and "Obbies" or "Towers") then
    local CurrentTowerBox = Tabs.Main:AddLeftGroupbox(IS_TOR and "Current Obby" or "Current Tower")
    local CurrentTowerLabel = CurrentTowerBox:AddLabel("", true)

    local TowerBox = Tabs.Main:AddLeftGroupbox(IS_TOR and "Obbies" or "Towers")

    local function showCurrentTower(name)
        if name then
            local difficulty = towerDifficulty(name)
            CurrentTowerLabel:SetText(difficulty and (name .. " - " .. difficulty) or name)
        else
            CurrentTowerLabel:SetText("Lobby")
        end
    end

    showCurrentTower(currentKitTower())
    if game.GameId == TEA_GAME_ID or IS_TOR or IS_ASTN then
        local towerConnection = LocalPlayer:GetAttributeChangedSignal(IS_TOR and "CurrentObby" or "Tower"):Connect(function()
            showCurrentTower(currentKitTower())
        end)
        Library:OnUnload(function()
            towerConnection:Disconnect()
        end)
    else
        task.spawn(function()
            local lastTower = currentKitTower()
            while not Library.Unloaded do
                task.wait(1)
                local name = currentKitTower()
                if name ~= lastTower then
                    lastTower = name
                    showCurrentTower(name)
                end
            end
        end)
    end

    local towerNames = {}
    local listedTowers = {}
    for _, tower in pairs(workspace:WaitForChild(IS_TOR and "Obbies" or "Towers"):GetChildren()) do
        table.insert(towerNames, tower.Name)
        listedTowers[tower.Name] = true
    end
    if IS_TOR or IS_ASTN then
        table.sort(towerNames)
    end
    local rushFolder = IS_CSCD and workspace:FindFirstChild("Teleporters") and workspace.Teleporters:FindFirstChild("TowerRushes")
    if rushFolder then
        for _, rush in ipairs(rushFolder:GetChildren()) do
            local name = cscdAcronym(rush.Name)
            if rush:IsA("BasePart") and not listedTowers[name] then
                table.insert(towerNames, name)
                listedTowers[name] = true
            end
        end
    end

    local routeNames = {}
    local routeListLoaded = false
    local refreshRushStatus
    local updateRushInfo
    local refreshSecretEnding

    local rushLabels = {}
    pcall(function()
        if IS_ASTN then
            for areaName in pairs(require(ReplicatedStorage.MenuData.Areas)) do
                local ring, title = areaName:match("^Ring (%d+): (.+)$")
                if ring then
                    rushLabels["Ring" .. ring .. "TowerRush"] = title .. " Rush"
                end
            end
        elseif IS_CSCD then
            for rushName, info in pairs(require(ReplicatedStorage.All_Areas.TOWER_RUSH_INFO)) do
                if type(info) == "table" and type(info.Name) == "string" then
                    rushLabels[rushName] = info.Name
                end
            end
        end
    end)

    local function formatTowerName(name)
        local status = routeNames[name]
        local label = rushLabels[name] or tostring(name)
        if status == nil and not routeListLoaded then
            return label
        end
        return (status and "\240\159\159\162 " or "\240\159\148\180 ") .. label
    end

    TowerBox:AddDropdown("TowerDropdown", {
        Values = towerNames,
        Default = 1,
        Multi = false,
        Searchable = true,
        Tooltip = "\240\159\159\162 has Auto Play, \240\159\148\180 doesn't.",
        FormatListValue = formatTowerName,
        FormatDisplayValue = formatTowerName,
    })

    task.spawn(function()
        local found = {}
        local treeUrl = "https://api.github.com/repos/aeryhub/Aery-Routes/git/trees/main?recursive=1"
        local ok, tree = false, nil
        if not IS_CSCD or ROUTE_AREAS[game.PlaceId] then
            ok, tree = pcall(function()
                return HttpService:JSONDecode(game:HttpGet(treeUrl))
            end)
            if not (ok and type(tree) == "table" and type(tree.tree) == "table") then
                ok, tree = pcall(function()
                    local httpRequest = request or http_request or (syn and syn.request)
                    local response = httpRequest({ Url = treeUrl, Method = "GET", Headers = { ["User-Agent"] = "Aery Hub" } })
                    return HttpService:JSONDecode(response.Body)
                end)
            end
        end
        local placeAreas = ROUTE_AREAS[game.PlaceId]
        if type(placeAreas) == "string" then
            placeAreas = { placeAreas }
        end
        local allowedFolders
        if placeAreas then
            allowedFolders = {}
            for _, area in ipairs(placeAreas) do
                allowedFolders[area] = true
            end
        end
        if ok and type(tree) == "table" and type(tree.tree) == "table" then
            for _, entry in ipairs(tree.tree) do
                local folder, name
                if type(entry.path) == "string" then
                    folder, name = entry.path:match("^Games/" .. ROUTE_GAME .. "/([^/]+)/(.+)%.lua$")
                end
                if name and (not allowedFolders or allowedFolders[folder]) then
                    found[name] = true
                end
            end
        end
        pcall(function()
            if isfolder("Aery Hub/Routes/" .. ROUTE_GAME) then
                for _, path in ipairs(listfiles("Aery Hub/Routes/" .. ROUTE_GAME)) do
                    local name = path:match("([^/\\]+)%.lua$")
                    if name then
                        found[name] = true
                    end
                end
            end
        end)
        for name in pairs(found) do
            routeNames[name] = true
        end
        if not (ok and type(tree) == "table" and type(tree.tree) == "table") and next(found) == nil then
            return
        end
        routeListLoaded = true
        if Options.TowerDropdown then
            Options.TowerDropdown:SetValues(towerNames)
        end
        if refreshRushStatus then
            refreshRushStatus()
        end
        if updateRushInfo then
            updateRushInfo()
        end
        if refreshSecretEnding then
            refreshSecretEnding()
        end
    end)

    local function findTowerPortal(towerName)
        if IS_TOR then
            local obby = workspace.Obbies:FindFirstChild(towerName)
            local portal = obby and (obby:FindFirstChild("Portal") or obby:FindFirstChild("HardcorePortal"))
            local fallback
            if portal then
                for _, part in ipairs((portal:FindFirstChild("TeleportPartFolder") or portal):GetDescendants()) do
                    if part:IsA("BasePart") then
                        if part:FindFirstChildOfClass("TouchTransmitter") then
                            return part
                        end
                        fallback = fallback or part
                    end
                end
            end
            if fallback then
                return fallback
            end
            return nil, obby and ("Failed to enter: " .. towerName) or ("Obby not found: " .. towerName)
        end
        if IS_CSCD then
            local teleporters = workspace:FindFirstChild("Teleporters")
            if teleporters then
                local prefix = towerName .. " | "
                for _, child in ipairs(teleporters:GetDescendants()) do
                    if child:IsA("BasePart") and (child.Name == towerName or child.Name:sub(1, #prefix) == prefix) then
                        return child
                    end
                end
            end
            if not workspace.Towers:FindFirstChild(towerName) then
                return nil, "Tower not found: " .. towerName
            end
            return nil, "Failed to enter: " .. towerName
        end
        local tower = workspace.Towers:FindFirstChild(towerName)
        if IS_ASTN then
            local portals = workspace:FindFirstChild("Portals")
            for _, portal in ipairs(portals and portals:GetChildren() or {}) do
                local value = portal:FindFirstChild("TowerPortal") or portal:FindFirstChild("TowerRush")
                if portal:IsA("BasePart") and value and value.Value == towerName then
                    return portal
                end
            end
            return nil, tower and ("Failed to enter: " .. towerName) or ("Tower not found: " .. towerName)
        end
        if not tower then
            return nil, "Tower not found: " .. towerName
        end
        local teleporter
        if game.GameId == TEA_GAME_ID then
            teleporter = tower:FindFirstChild("Portal") and tower.Portal:FindFirstChild("Teleporter")
        else
            local outer = tower:FindFirstChild("Teleporter")
            local inner = outer and (outer:FindFirstChild("Teleporter") or outer:FindFirstChild("TowerRushPortal"))
            teleporter = inner and (inner:FindFirstChild("TPFRAME") or inner:FindFirstChild("Teleport"))
            if inner and not (teleporter and teleporter:IsA("BasePart")) then
                teleporter = nil
                for _, part in ipairs(inner:GetDescendants()) do
                    if part:IsA("BasePart") and part:FindFirstChildOfClass("TouchTransmitter") then
                        teleporter = part
                        break
                    end
                end
            end
        end
        if not teleporter then
            return nil, "Failed to enter: " .. towerName
        end
        return teleporter
    end

    local function enterTower(towerName)
        local root = getRoot()
        if not root or not towerName or towerName == "" then
            return false
        end
        local teleporter, problem = findTowerPortal(towerName)
        if not teleporter then
            return false, problem
        end
        if IS_CSCD then
            root.AssemblyLinearVelocity = Vector3.zero
            root.CFrame = teleporter.CFrame
            pcall(firetouchinterest, root, teleporter, TOUCH[1])
            task.wait(0.1)
            pcall(firetouchinterest, root, teleporter, TOUCH[2])
            cscdTower = towerName
            return true
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = teleporter.CFrame
        pcall(firetouchinterest, root, teleporter, TOUCH[1])
        task.wait(0.1)
        pcall(firetouchinterest, root, teleporter, TOUCH[2])
        return true
    end

    local function findTowerName(query)
        local wanted = query:lower()
        local found
        for rushName, label in pairs(rushLabels) do
            local initials = label:gsub("(%w)%w*%s*", "%1")
            if wanted == label:lower() or wanted == initials:lower() then
                found = rushName
            end
        end
        for _, name in ipairs(found and {} or towerNames) do
            if name:lower() == wanted then
                found = name
                break
            end
        end
        if not found and IS_TOR then
            local ok, index = pcall(function()
                return require(ReplicatedStorage.SharedModules.ObbyIndex)[workspace:GetAttribute("AreaName")]
            end)
            if ok and type(index) == "table" then
                for _, name in ipairs(towerNames) do
                    local data = index[name]
                    local acronym = type(data) == "table" and data.ObbyAcronym
                    if type(acronym) == "string" and acronym:lower() == wanted then
                        found = name
                        break
                    end
                end
            end
        end
        if not found then
            for rushName in pairs(rushLabels) do
                if wanted == rushName:lower() then
                    found = rushName
                end
            end
        end
        if not found then
            for _, name in ipairs(towerNames) do
                if name:lower():sub(1, #wanted) == wanted then
                    found = name
                    break
                end
            end
        end
        return found
    end

    ChatCommands.enter = function(query)
        local name, option = query:match("^(.-)%s+(%S+)$")
        local toPortal = option and option:lower() == "portal"
        if toPortal then
            query = name
        end
        local found = findTowerName(query)
        if not found then
            notify("/enter", "No " .. (IS_TOR and "obby" or "tower") .. " called " .. query .. ".")
            return
        end
        if toPortal then
            local portal, problem = findTowerPortal(found)
            if not portal or not ChatCommands.portal then
                notify("/enter", problem or "/enter portal doesn't work in this game.")
                return
            end
            ChatCommands.portal(found)
            return
        end
        local ok, problem = enterTower(found)
        if not ok and problem then
            notify("/enter", problem)
        end
    end

    TowerBox:AddButton({
        Text = IS_TOR and "Enter Obby" or "Enter Tower",
        DoubleClick = false,
        Tooltip = IS_TOR and "Teleports you into the selected obby." or "Teleports you into the selected tower.",
        Func = function()
            local ok, problem = enterTower(Options.TowerDropdown.Value)
            if not ok and problem then
                notify(IS_TOR and "Enter Obby" or "Enter Tower", problem)
            end
        end,
    })

    if not IS_TEA and not IS_CSCD and not IS_TOR and not IS_ASTN then
        local SC_DIFFICULTIES = { Insane = true, Extreme = true, Terrifying = true, Catastrophic = true, Horrific = true, Unreal = true }
        local winroomDetectors = {}
        local misc = workspace:FindFirstChild("Misc")
        local randomStuff = misc and misc:FindFirstChild("RandomStuff")

        for _, tower in ipairs(workspace.Towers:GetChildren()) do
            local portal = tower:FindFirstChild("Teleporter")
            local room = workspace:FindFirstChild(tower.Name .. "WinnersRoom") or (randomStuff and randomStuff:FindFirstChild(tower.Name .. "WinnersRoom"))
            local spot = room and room:FindFirstChild("WinTp")
            if portal and spot and spot:IsA("BasePart") and SC_DIFFICULTIES[towerDifficultyName(tower.Name) or ""] then
                local parts = portal:GetDescendants()
                table.insert(parts, portal)
                for _, part in ipairs(parts) do
                    if part:IsA("BasePart") and part.Name ~= "TeleportTo" then
                        local detector = Instance.new("ClickDetector")
                        detector.MaxActivationDistance = 2000
                        detector.MouseClick:Connect(function()
                            local root = getRoot()
                            if root and spot.Parent then
                                root.AssemblyLinearVelocity = Vector3.zero
                                root.CFrame = CFrame.new(spot.Position + Vector3.new(0, 4, 0))
                            end
                        end)
                        detector.Parent = part
                        table.insert(winroomDetectors, detector)
                    end
                end
            end
        end

        Library:OnUnload(function()
            for _, detector in ipairs(winroomDetectors) do
                detector:Destroy()
            end
            table.clear(winroomDetectors)
        end)
    end

    if not IS_TOR then
        local function chartKey(text)
            return (tostring(text):gsub("[^%w]", "")):lower()
        end

        local function knownTowers()
            local names = {}
            local towers = workspace:FindFirstChild("Towers")
            if towers then
                for _, tower in ipairs(towers:GetChildren()) do
                    names[chartKey(tower.Name)] = tower.Name
                end
            end
            local teleporters = IS_CSCD and workspace:FindFirstChild("Teleporters")
            if teleporters then
                for _, part in ipairs(teleporters:GetDescendants()) do
                    if part:IsA("BasePart") then
                        local acronym = cscdAcronym(part.Name)
                        names[chartKey(acronym)] = acronym
                    end
                end
            end
            for rushName, label in pairs(rushLabels) do
                names[chartKey(label)] = rushName
            end
            return names
        end

        local function chartTowerAt(part, names)
            names = names or knownTowers()
            local towers = workspace:FindFirstChild("Towers")
            local teleporters = workspace:FindFirstChild("Teleporters")
            local persistent = workspace:FindFirstChild("PClientParts")
            local node = part
            while node and node ~= workspace do
                if (towers and node:IsDescendantOf(towers)) or (teleporters and node:IsDescendantOf(teleporters)) then
                    return nil
                end
                local found = names[chartKey(node.Name)]
                local gui = node:IsA("BasePart") and node:FindFirstChildWhichIsA("SurfaceGui")
                local label = gui and gui:FindFirstChildWhichIsA("TextLabel")
                if not found and label then
                    found = names[chartKey(label.Text)]
                end
                if found and label and persistent and node:IsDescendantOf(persistent) and chartKey(label.Text) == chartKey(node.Name) then
                    return found, node
                end
                if found then
                    local up = node.Parent
                    while up and up ~= workspace do
                        if up.Name:lower():find("chart") then
                            return found, node
                        end
                        up = up.Parent
                    end
                end
                node = node.Parent
            end
            return nil
        end

        local function portalLanding(portal)
            local root = getRoot()
            local character = getCharacter()
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { character }
            local overlap = OverlapParams.new()
            overlap.FilterType = Enum.RaycastFilterType.Exclude
            overlap.FilterDescendantsInstances = { character }
            local portalHeight = portal.Position.Y

            local function candidate(spot)
                local hit = workspace:Raycast(Vector3.new(spot.X, portalHeight, spot.Z), Vector3.new(0, -20, 0), params)
                if not hit or hit.Instance == portal then
                    return nil
                end
                local standing = hit.Position + Vector3.new(0, 3, 0)
                local clear = true
                local nearby = workspace:GetPartBoundsInBox(CFrame.new(standing), Vector3.new(2, 4.5, 1.5), overlap)
                table.insert(nearby, hit.Instance)
                for _, part in ipairs(nearby) do
                    if part:FindFirstChild("DamageBrickConfiguration") or part.Name == "KillBrick" or part.Name == "InstakillBrick" then
                        return nil
                    end
                    if part.CanCollide and part ~= hit.Instance then
                        clear = false
                    end
                end
                if clear then
                    local sight = workspace:Raycast(standing, portal.Position - standing, params)
                    clear = not sight or sight.Instance:IsDescendantOf(portal.Parent)
                end
                local distance = root and (standing - root.Position).Magnitude or 0
                return { standing = standing, clear = clear, distance = distance }
            end

            local function pick(spots)
                local best
                for _, spot in ipairs(spots) do
                    local option = candidate(spot)
                    if option then
                        local better = not best
                            or (option.clear and not best.clear)
                            or (option.clear == best.clear and option.distance < best.distance)
                        if better then
                            best = option
                        end
                    end
                end
                return best
            end

            local size = portal.Size
            local thin = math.min(size.X, size.Z)
            local best
            if thin < math.max(size.X, size.Z) * 0.6 then
                local normal = size.X < size.Z and portal.CFrame.RightVector or portal.CFrame.LookVector
                normal = Vector3.new(normal.X, 0, normal.Z).Unit
                local offset = thin / 2 + 4
                local holder = portal.Parent and portal.Parent:IsA("Model") and portal.Parent or portal
                local vote = 0
                for _, item in ipairs(holder:GetDescendants()) do
                    if (item:IsA("SurfaceGui") or item:IsA("Decal")) and item.Parent:IsA("BasePart") then
                        vote = vote + item.Parent.CFrame:VectorToWorldSpace(Vector3.FromNormalId(item.Face)):Dot(normal)
                    end
                end
                if vote < 0 then
                    normal = -normal
                end
                local front = vote ~= 0 and candidate(portal.Position + normal * offset)
                best = front and front.clear and front or pick({ portal.Position + normal * offset, portal.Position - normal * offset })
            end
            if not best or not best.clear then
                local reach = math.max(size.X, size.Z) / 2 + 5
                local spots = {}
                for step = 0, 7 do
                    local angle = step * math.pi / 4
                    table.insert(spots, portal.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * reach)
                end
                local around = pick(spots)
                if around and (not best or (around.clear and not best.clear)) then
                    best = around
                end
            end
            local standing = best and best.standing or (portal.Position + Vector3.new(thin / 2 + 4, 0, 0))
            return CFrame.lookAt(standing, Vector3.new(portal.Position.X, standing.Y, portal.Position.Z))
        end

        local function teleportToChartTower(towerName)
            local root = getRoot()
            local portal = root and findTowerPortal(towerName)
            if not portal then
                return
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.CFrame = portalLanding(portal)
        end
        ChatCommands.portal = teleportToChartTower

        local chartDetectors = {}
        local chartDone = {}
        local chartOwned = setmetatable({}, { __mode = "k" })
        local chartHooks = {}
        local chartMuted = {}

        local function addChartDetectors(chart)
            local names = knownTowers()
            for _, part in ipairs(chart:GetDescendants()) do
                if part:IsA("BasePart") then
                    local towerName, node = chartTowerAt(part, names)
                    if towerName and not chartDone[node] then
                        chartDone[node] = true
                        local holders = { node }
                        if not (node:IsA("BasePart") or node:IsA("Model")) then
                            holders = {}
                            for _, inner in ipairs(node:GetDescendants()) do
                                if inner:IsA("BasePart") then
                                    table.insert(holders, inner)
                                end
                            end
                        end
                        local existing = {}
                        local searched = { node }
                        for _, inner in ipairs(node:GetDescendants()) do
                            table.insert(searched, inner)
                        end
                        for _, item in ipairs(searched) do
                            if item:IsA("ClickDetector") and not chartOwned[item] then
                                table.insert(existing, item)
                            end
                        end
                        if IS_ASTN then
                            for _, detector in ipairs(existing) do
                                local parent = detector.Parent
                                detector.Parent = nil
                                table.insert(chartMuted, { Enable = function()
                                    detector.Parent = parent
                                end })
                            end
                            table.clear(existing)
                        end
                        if #existing > 0 then
                            for _, detector in ipairs(existing) do
                                if getconnections then
                                    pcall(function()
                                        for _, connection in ipairs(getconnections(detector.MouseClick)) do
                                            connection:Disable()
                                            table.insert(chartMuted, connection)
                                        end
                                    end)
                                end
                                table.insert(chartHooks, detector.MouseClick:Connect(function()
                                    teleportToChartTower(towerName)
                                end))
                            end
                        else
                            for _, holder in ipairs(holders) do
                                local detector = Instance.new("ClickDetector")
                                detector.MaxActivationDistance = 2000
                                detector.MouseClick:Connect(function()
                                    teleportToChartTower(towerName)
                                end)
                                chartOwned[detector] = true
                                detector.Parent = holder
                                table.insert(chartDetectors, detector)
                            end
                        end
                    end
                end
            end
        end

        local function scanCharts()
            if IS_CSCD then
                local lobby = workspace:FindFirstChild("Lobby")
                local charts = lobby and lobby:FindFirstChild("Difficulty Charts")
                local normal = charts and charts:FindFirstChild("Normal DC")
                if normal then
                    addChartDetectors(normal)
                end
                local connected = workspace:FindFirstChild("ScriptConnectedFolders")
                local labels = connected and connected:FindFirstChild("DifficultyChartLabels")
                if labels then
                    addChartDetectors(labels)
                end
                return
            end
            for _, child in ipairs(workspace:GetChildren()) do
                if child.Name:lower():find("chart") then
                    addChartDetectors(child)
                elseif child.Name ~= "Towers" then
                    for _, inner in ipairs(child:GetChildren()) do
                        if inner.Name:lower():find("chart") then
                            addChartDetectors(inner)
                        end
                    end
                end
            end
            local persistent = workspace:FindFirstChild("PClientParts")
            if persistent then
                addChartDetectors(persistent)
            end
        end

        local chartExtras = { models = {}, rainbow = {}, completed = {}, connection = nil, watching = false, pending = false, chartWatch = nil, watchedChart = nil, persistentWatch = nil, watchedPersistent = nil, refresh = nil }

        function chartExtras.isExtra(instance)
            for _, extra in ipairs(chartExtras.models) do
                if instance == extra.model or instance:IsDescendantOf(extra.model) then
                    return true
                end
            end
            return false
        end

        local function addMissingChartEntries()
            local chart = workspace:FindFirstChild("DifficultyChart")
            local levels = chart and chart:IsA("Model") and chart:FindFirstChild("ChartLevels")
            local towers = workspace:FindFirstChild("Towers")
            local lib = getTowerLibrary()
            local data = lib and type(lib.Data) == "table" and type(lib.Data.Towers) == "table" and lib.Data.Towers
            if not levels or not towers or not data then
                return
            end
            local listed = {}
            for _, item in ipairs(chart:GetDescendants()) do
                if not chartExtras.isExtra(item) then
                    if item:IsA("TextLabel") then
                        listed[chartKey(item.Text)] = true
                    elseif item:IsA("Model") then
                        listed[chartKey(item.Name)] = true
                    end
                end
            end
            local persistent = workspace:FindFirstChild("PClientParts")
            if persistent then
                for _, item in ipairs(persistent:GetDescendants()) do
                    local holder = item:IsA("TextLabel") and item:FindFirstAncestorWhichIsA("BasePart")
                    if holder and chartKey(holder.Name) == chartKey(item.Text) then
                        listed[chartKey(item.Text)] = true
                    end
                end
            end
            for index = #chartExtras.models, 1, -1 do
                local extra = chartExtras.models[index]
                if listed[chartKey(extra.name)] or not extra.model.Parent then
                    extra.model:Destroy()
                    table.remove(chartExtras.models, index)
                end
            end
            for index = #chartExtras.rainbow, 1, -1 do
                if not chartExtras.rainbow[index].Parent then
                    table.remove(chartExtras.rainbow, index)
                end
            end
            local function labelAdded(item)
                if item:IsA("TextLabel") and not chartExtras.pending and not chartExtras.isExtra(item) then
                    chartExtras.pending = true
                    task.delay(1, function()
                        chartExtras.pending = false
                        if chartExtras.refresh then
                            chartExtras.refresh()
                        end
                    end)
                end
            end
            if chartExtras.watchedChart ~= chart then
                if chartExtras.chartWatch then
                    chartExtras.chartWatch:Disconnect()
                end
                chartExtras.watchedChart = chart
                chartExtras.chartWatch = chart.DescendantAdded:Connect(labelAdded)
            end
            if persistent and chartExtras.watchedPersistent ~= persistent then
                if chartExtras.persistentWatch then
                    chartExtras.persistentWatch:Disconnect()
                end
                chartExtras.watchedPersistent = persistent
                chartExtras.persistentWatch = persistent.DescendantAdded:Connect(labelAdded)
            end
            local entries = {}
            local template
            for _, entry in ipairs(chart:GetChildren()) do
                if entry:IsA("Model") and entry ~= levels and towers:FindFirstChild(entry.Name) then
                    local label, bar
                    for _, part in ipairs(entry:GetDescendants()) do
                        if part:IsA("BasePart") then
                            if part:FindFirstChildWhichIsA("SurfaceGui") then
                                label = part
                            elseif part:FindFirstChildWhichIsA("BlockMesh") then
                                bar = part
                            end
                        end
                    end
                    if label and bar then
                        entries[entry.Name] = { label = label, bar = bar }
                        template = template or { model = entry, label = label, bar = bar }
                    end
                end
            end
            local anyLevel = levels:FindFirstChildWhichIsA("BasePart")
            if not template or not anyLevel then
                return
            end
            local center = anyLevel.Position
            local axis = template.label.Position - center
            axis = Vector3.new(axis.X, 0, axis.Z).Unit
            local spineHalf = anyLevel.Size.X / 2
            local labelHalf = template.label.Size.X / 2
            local labelHalfY = template.label.Size.Y / 2
            local occupied = {}
            local function occupy(dist, halfDist, y, halfY)
                table.insert(occupied, { dist = dist, halfDist = halfDist, y = y, halfY = halfY })
            end
            local function isFree(dist, halfDist, y, halfY)
                for _, area in ipairs(occupied) do
                    if math.abs(area.dist - dist) < area.halfDist + halfDist + 0.4 and math.abs(area.y - y) < area.halfY + halfY + 0.3 then
                        return false
                    end
                end
                return true
            end
            for _, parts in pairs(entries) do
                occupy((parts.label.Position - center):Dot(axis), parts.label.Size.X / 2, parts.label.Position.Y, parts.label.Size.Y / 2)
                occupy((parts.bar.Position - center):Dot(axis), parts.bar.Size.X / 2, parts.bar.Position.Y, 0.25)
            end
            local official = {}
            local okNil, nils = pcall(getnilinstances)
            if okNil and type(nils) == "table" then
                for _, item in ipairs(nils) do
                    if item.Name == "Activate" and item:IsA("Model") then
                        for _, part in ipairs(item:GetChildren()) do
                            if part:IsA("BasePart") then
                                if part:FindFirstChildWhichIsA("SurfaceGui") then
                                    official[chartKey(part.Name)] = item
                                end
                                occupy((part.Position - center):Dot(axis), part.Size.X / 2, part.Position.Y, part:FindFirstChildWhichIsA("BlockMesh") and 0.25 or part.Size.Y / 2)
                            end
                        end
                    end
                end
            end

            for _, tower in ipairs(towers:GetChildren()) do
                local info = data[tower.Name]
                local level = type(info) == "table" and type(info.Difficulty) == "string" and levels:FindFirstChild(info.Difficulty)
                local placement = type(info) == "table" and tonumber(info.DifficultyPlacement)
                local source = official[chartKey(tower.Name)]
                if not entries[tower.Name] and not listed[chartKey(tower.Name)] and not chartExtras.completed[tower.Name] and (source or (level and placement)) then
                    local chosenSide, chosenBar, hiddenSide, hiddenBar, base
                    if not source then
                        local fraction = placement - math.floor(placement)
                        local y = level.Position.Y - level.Size.Y / 2 + fraction * level.Size.Y
                        base = Vector3.new(center.X, y, center.Z)
                        local labelRotation = template.label.CFrame - template.label.Position
                        local look = template.label.CFrame.LookVector
                        local viewParams = RaycastParams.new()
                        viewParams.FilterType = Enum.RaycastFilterType.Exclude
                        viewParams.FilterDescendantsInstances = { chart, getCharacter() }
                        local spaceParams = OverlapParams.new()
                        spaceParams.FilterType = Enum.RaycastFilterType.Exclude
                        spaceParams.FilterDescendantsInstances = { chart, getCharacter() }
                        local function isVisible(labelDist)
                            local spot = labelRotation + base + axis * labelDist
                            for _, part in ipairs(workspace:GetPartBoundsInBox(spot, template.label.Size, spaceParams)) do
                                if part.Transparency < 0.9 then
                                    return false
                                end
                            end
                            local hit = workspace:Raycast(spot.Position + look * template.label.Size.Z, look * 12, viewParams)
                            return not (hit and hit.Instance.Transparency < 0.9)
                        end
                        for step = 0, 45 do
                            local barLength = step * 0.5 + 1.5
                            for _, side in ipairs({ 1, -1 }) do
                                if not chosenSide then
                                    local labelDist = side * (spineHalf + barLength + labelHalf)
                                    if isFree(labelDist, labelHalf, y, labelHalfY) then
                                        if isVisible(labelDist) then
                                            chosenSide, chosenBar = side, barLength
                                        elseif not hiddenSide then
                                            hiddenSide, hiddenBar = side, barLength
                                        end
                                    end
                                end
                            end
                        end
                        if not chosenSide then
                            chosenSide, chosenBar = hiddenSide or 1, hiddenBar or 24
                        end
                    end
                    local model = (source or template.model):Clone()
                    model.Name = tower.Name
                    for _, item in ipairs(model:GetDescendants()) do
                        if item:IsA("ClickDetector") then
                            item:Destroy()
                        end
                    end
                    local label, bar
                    for _, part in ipairs(model:GetDescendants()) do
                        if part:IsA("BasePart") then
                            if part:FindFirstChildWhichIsA("SurfaceGui") then
                                label = part
                            elseif part:FindFirstChildWhichIsA("BlockMesh") then
                                bar = part
                            end
                        end
                    end
                    if not source then
                        label.CFrame = template.label.CFrame - template.label.Position + base + axis * (chosenSide * (spineHalf + chosenBar + labelHalf))
                        bar.Size = Vector3.new(chosenBar, bar.Size.Y, bar.Size.Z)
                        bar.CFrame = template.bar.CFrame - template.bar.Position + base + axis * (chosenSide * (spineHalf + chosenBar / 2))
                        local text = label:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChildWhichIsA("TextLabel")
                        if text then
                            text.Text = tower.Name
                        end
                    end
                    bar.Color = BrickColor.new("Really red").Color
                    table.insert(chartExtras.models, { model = model, name = tower.Name, bar = bar, rush = tower:FindFirstChild("TowerRushList") ~= nil })
                    model.Parent = chart
                    occupy((label.Position - center):Dot(axis), labelHalf, label.Position.Y, labelHalfY)
                    occupy((bar.Position - center):Dot(axis), bar.Size.X / 2, bar.Position.Y, 0.25)
                    if tower:FindFirstChild("TowerRushList") then
                        table.insert(chartExtras.rainbow, label)
                    end
                end
            end

            if #chartExtras.rainbow > 0 and not chartExtras.connection then
                chartExtras.connection = RunService.Heartbeat:Connect(function()
                    local color = Color3.fromHSV(os.clock() * 0.2 % 1, 0.8, 1)
                    for _, part in ipairs(chartExtras.rainbow) do
                        part.Color = color
                    end
                end)
            end

            if chartExtras.watching or #chartExtras.models == 0 then
                return
            end
            chartExtras.watching = true
            task.spawn(function()
                local playerData
                pcall(function()
                    playerData = require(ReplicatedStorage.Framework).Controller.DataController:Wait().Data
                end)
                local completedColor = BrickColor.new("Lime green").Color
                local notCompletedColor = BrickColor.new("Really red").Color
                while playerData and #chartExtras.models > 0 and not Library.Unloaded do
                    for _, extra in ipairs(chartExtras.models) do
                        local ok, completed = pcall(lib.IsTowerCompleted, lib, playerData, extra.name)
                        if extra.bar.Parent then
                            extra.bar.Color = (ok and completed) and completedColor or notCompletedColor
                        end
                    end
                    task.wait(3)
                end
                chartExtras.watching = false
            end)
        end

        local function refreshChart()
            if Library.Unloaded then
                return
            end
            if game.GameId == ETOH_GAME_ID then
                local ok, problem = pcall(addMissingChartEntries)
                if not ok then
                    warn("[Aery Hub] chart entries: " .. tostring(problem))
                end
            end
            scanCharts()
        end

        chartExtras.refresh = refreshChart
        if game.GameId == ETOH_GAME_ID then
            task.spawn(pcall, function()
                local framework = require(ReplicatedStorage.Framework)
                framework.Network:Connect(framework.Library.Remotes.TowerEvent):ListenClient(function(event)
                    local name = event == "complete" and not Library.Unloaded and currentKitTower()
                    if not name then
                        return
                    end
                    for index = #chartExtras.models, 1, -1 do
                        local extra = chartExtras.models[index]
                        if extra.name == name and not extra.rush then
                            chartExtras.completed[name] = true
                            extra.model:Destroy()
                            table.remove(chartExtras.models, index)
                        end
                    end
                end)
            end)
        end
        refreshChart()
        task.delay(5, refreshChart)
        local chartAdded = workspace.ChildAdded:Connect(function(child)
            if child.Name == "DifficultyChart" or child.Name == "Misc" then
                task.delay(2, refreshChart)
            end
        end)
        Library:OnUnload(function()
            chartAdded:Disconnect()
        end)

        Library:OnUnload(function()
            for _, detector in ipairs(chartDetectors) do
                detector:Destroy()
            end
            table.clear(chartDetectors)
            for _, hook in ipairs(chartHooks) do
                hook:Disconnect()
            end
            table.clear(chartHooks)
            for _, connection in ipairs(chartMuted) do
                pcall(function()
                    connection:Enable()
                end)
            end
            table.clear(chartMuted)
            if chartExtras.connection then
                chartExtras.connection:Disconnect()
            end
            if chartExtras.chartWatch then
                chartExtras.chartWatch:Disconnect()
            end
            if chartExtras.persistentWatch then
                chartExtras.persistentWatch:Disconnect()
            end
            for _, extra in ipairs(chartExtras.models) do
                extra.model:Destroy()
            end
            table.clear(chartExtras.models)
        end)
    end

    local AutoPlayBox = Tabs.Main:AddLeftGroupbox("Auto Play")

    local pauseButton
    local rushPauseButton

    local AutoPlay = {
        running = false,
        waypoints = {},
        routeNodes = {},
        speed = 20,
        originalGravity = workspace.Gravity,
        noclip = false,
        noclipConnection = nil,
        collideWatch = {},
        originalCollide = {},
        routeFolder = nil,
        loopThread = nil,
        showRoute = false,
        paused = false,
        pauseRequested = false,
        timeOverride = false,
        sources = {},
        sliceStarted = 0,
        loadWatch = {},
        deathWatch = nil,
        rushWatch = nil,
        rushInfo = nil,
        recorderLoading = false,
    }

    local function detectRing()
        local towers
        for _ = 1, 40 do
            towers = workspace:FindFirstChild("Towers")
            if towers then
                break
            end
            task.wait(0.25)
        end
        if not towers then
            return "Ring0"
        end
        for _, tower in ipairs(towers:GetChildren()) do
            for ring, names in pairs(TowerRings) do
                if table.find(names, tower.Name) then
                    return ring
                end
            end
        end
        return "Ring0"
    end

    local function routeFoldersFor(towerName)
        local placeRings = ROUTE_AREAS[game.PlaceId]
        if type(placeRings) == "string" then
            placeRings = { placeRings }
        end
        local folders = {}
        if placeRings then
            for _, ring in ipairs(placeRings) do
                if TowerRings[ring] and table.find(TowerRings[ring], towerName) then
                    table.insert(folders, ring)
                end
            end
            if #folders == 0 then
                table.insert(folders, placeRings[1])
            end
            return folders
        end
        for ring, names in pairs(TowerRings) do
            if table.find(names, towerName) then
                table.insert(folders, ring)
            end
        end
        if #folders == 0 then
            table.insert(folders, detectRing())
        end
        return folders
    end

    local function fetchRoute(towerName)
        local localPath = "Aery Hub/Routes/" .. ROUTE_GAME .. "/" .. towerName .. ".lua"
        local okLocal, localSource = pcall(function()
            return isfile(localPath) and readfile(localPath) or nil
        end)
        if okLocal and type(localSource) == "string" and localSource ~= "" then
            return localSource, nil, true
        end
        if AutoPlay.sources[towerName] then
            return AutoPlay.sources[towerName]
        end
        if IS_CSCD and not ROUTE_AREAS[game.PlaceId] then
            return nil, "No route for " .. towerName .. ". Make one with Aery Recorder and save it to Aery Hub/Routes/" .. ROUTE_GAME .. "."
        end
        local folders = routeFoldersFor((towerName:gsub("_SE$", "")))
        if #folders > 1 and not ROUTE_AREAS[game.PlaceId] then
            return nil, towerName .. " is a different tower in " .. areaNames(folders) .. ". Join that area to auto play it."
        end
        for _, folder in ipairs(folders) do
            local ok, source = pcall(function()
                return game:HttpGet(ROUTE_BASE .. folder .. "/" .. HttpService:UrlEncode(towerName) .. ".lua")
            end)
            if ok and type(source) == "string" and source ~= "" and not source:match("^%s*404") then
                AutoPlay.sources[towerName] = source
                return source
            end
        end
        return nil, "No route found for " .. towerName
    end

    local checkingRoutes = {}

    local function hasSecretEnding(towerName)
        if type(towerName) ~= "string" or towerName == "" then
            return false
        end
        if routeNames[towerName .. "_SE"] == true then
            return true
        end
        local ok, exists = pcall(function()
            return isfile("Aery Hub/Routes/" .. ROUTE_GAME .. "/" .. towerName .. "_SE.lua")
        end)
        return ok and exists == true
    end

    local function checkTowerRoute(towerName)
        if refreshSecretEnding then
            refreshSecretEnding()
        end
        if type(towerName) ~= "string" or towerName == "" then
            return
        end
        if routeNames[towerName] ~= true then
            local ok, exists = pcall(function()
                return isfile("Aery Hub/Routes/" .. ROUTE_GAME .. "/" .. towerName .. ".lua")
            end)
            if ok and exists then
                routeNames[towerName] = true
                if Options.TowerDropdown then
                    Options.TowerDropdown:Display()
                end
                return
            end
        end
        if routeNames[towerName] ~= nil or routeListLoaded or checkingRoutes[towerName] then
            return
        end
        checkingRoutes[towerName] = true
        task.spawn(function()
            local ok, source = pcall(fetchRoute, towerName)
            routeNames[towerName] = ok and source ~= nil
            checkingRoutes[towerName] = nil
            if Options.TowerDropdown then
                Options.TowerDropdown:Display()
            end
        end)
    end

    Options.TowerDropdown:OnChanged(checkTowerRoute)
    checkTowerRoute(Options.TowerDropdown.Value)

    local function parsePath(expr)
        local base, rest = expr:match("^(workspace[^:]*)(.*)$")
        if not base then
            return nil
        end
        local names = {}
        local position = #"workspace" + 1
        while position <= #base do
            local name, nextPosition = base:match("^%.([%a_][%w_]*)()", position)
            if not name then
                name, nextPosition = base:match('^%["(.-)"%]()', position)
            end
            if not name then
                return nil
            end
            table.insert(names, name)
            position = nextPosition
        end
        local indices = {}
        local at = 1
        while at <= string.len(rest) do
            local index, nextAt = rest:match("^:GetChildren%(%)%[(%d+)%]()", at)
            if index then
                table.insert(indices, tonumber(index))
            else
                local name
                name, nextAt = rest:match("^%.([%a_][%w_]*)()", at)
                if not name then
                    name, nextAt = rest:match('^%["(.-)"%]()', at)
                end
                if not name then
                    return nil
                end
                table.insert(indices, name)
            end
            at = nextAt
        end
        return { names = names, indices = indices }
    end

    local function parseStep(expr)
        if expr == '"jump"' then
            return { kind = "jump" }
        end
        local x, y, z = expr:match("^makeWaypoint%(%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*%)$")
        if x then
            return { kind = "point", position = Vector3.new(tonumber(x), tonumber(y), tonumber(z)) }
        end
        local seconds = expr:match('^{%s*type%s*=%s*"wait"%s*,%s*seconds%s*=%s*([%d%.e%-]+)%s*}$')
        if seconds then
            return { kind = "wait", seconds = tonumber(seconds) or 1 }
        end
        local target = expr:match('^{%s*type%s*=%s*"teleport"%s*,%s*target%s*=%s*(.-)%s*}$')
        if target then
            local step = parseStep(target)
            if step and (step.kind == "part" or step.kind == "point") then
                step.teleport = true
                return step
            end
            return nil
        end
        local path = parsePath(expr)
        if path then
            return { kind = "part", path = path }
        end
        return nil
    end

    local ROUTE_SLICE = 0.004

    local function routeBreather()
        if os.clock() - AutoPlay.sliceStarted > ROUTE_SLICE then
            task.wait()
            AutoPlay.sliceStarted = os.clock()
        end
    end

    local function parseRoute(source)
        local steps = {}
        local moves = 0
        for line in source:gmatch("[^\r\n]+") do
            routeBreather()
            local expr = (line:gsub("%-%-.*$", "")):match("^%s*(.-)%s*$")
            expr = expr:gsub("^route%[#route %+ 1%]%s*=%s*", "")
            expr = expr:gsub(",$", "")
            local step = parseStep(expr)
            if step then
                table.insert(steps, step)
                if step.kind ~= "jump" and step.kind ~= "wait" then
                    moves = moves + (1)
                end
            end
        end
        return moves > 0 and steps or nil
    end

    local function partPool()
        local ok, pool = pcall(function()
            return require(ReplicatedStorage.Modules.PartPoolModule).Pool
        end)
        if ok and type(pool) == "table" and #pool > 0 then
            return pool
        end
        return nil
    end

    local function childrenOf(cache, instance)
        local children = cache[instance]
        if not children then
            if IS_TEA and instance.Name == "Parts" and instance.Parent == workspace then
                children = partPool()
            end
            children = children or instance:GetChildren()
            cache[instance] = children
        end
        return children
    end

    local function resolveNamed(names)
        local node = workspace
        for _, name in ipairs(names) do
            node = node:FindFirstChild(name)
            if not node then
                return nil
            end
        end
        return node
    end

    local function partAt(cache, step, shift)
        if not step.container then
            return nil
        end
        local indices = step.path.indices
        local node = childrenOf(cache, step.container)[indices[1] + shift]
        for k = 2, #indices do
            if not node then
                return nil
            end
            local segment = indices[k]
            if type(segment) == "string" then
                node = node:FindFirstChild(segment)
            else
                node = childrenOf(cache, node)[segment]
            end
        end
        if node and node:IsA("BasePart") then
            return node
        end
        return nil
    end

    local function positionOf(context, step, shift)
        local indices = step.path.indices
        if #indices == 1 then
            return context.positions[indices[1] + shift] or nil
        end
        local part = partAt(context.cache, step, shift)
        return part and part.Position or nil
    end

    local function solveShifts(cache, container, list)
        local kids = childrenOf(cache, container)
        local positions = {}
        for i, child in ipairs(kids) do
            routeBreather()
            positions[i] = child:IsA("BasePart") and child.Position or false
        end
        local context = { cache = cache, positions = positions }
        local limit = ROUTE_MAX_GAP * ROUTE_MAX_GAP
        local memo = {}

        local function near(a, b)
            local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
            return dx * dx + dy * dy + dz * dz <= limit
        end

        local function stepPosition(step, shift)
            if #step.path.indices == 1 then
                return positionOf(context, step, shift)
            end
            local known = memo[step]
            if not known then
                known = {}
                memo[step] = known
            end
            local value = known[shift]
            if value == nil then
                routeBreather()
                value = positionOf(context, step, shift) or false
                known[shift] = value
            end
            return value or nil
        end

        local stepVotes, totals = {}, {}
        for k, step in ipairs(list) do
            routeBreather()
            if list[k - 2] then
                memo[list[k - 2]] = nil
            end
            local votes, count = {}, 0
            local first = step.path.indices[1]
            local before, after = list[k - 1], list[k + 1]
            if before and before.path.indices[1] == first then
                before = nil
            end
            if after and after.path.indices[1] == first then
                after = nil
            end
            if before or after then
                for shift = math.max(-ROUTE_MAX_SHIFT, -first + 1), math.min(ROUTE_MAX_SHIFT, #kids - first) do
                    local here = stepPosition(step, shift)
                    if here then
                        local weight = 0
                        local other = before and stepPosition(before, shift)
                        if other and near(here, other) then
                            weight = weight + (1)
                        end
                        other = after and stepPosition(after, shift)
                        if other and near(here, other) then
                            weight = weight + (1)
                        end
                        if weight > 0 then
                            votes[shift] = weight
                            count = count + (1)
                        end
                    end
                end
            end
            for shift, weight in pairs(votes) do
                votes[shift] = weight / count
                totals[shift] = (totals[shift] or 0) + weight / count
            end
            stepVotes[k] = votes
        end

        local candidates = {}
        for shift in pairs(totals) do
            table.insert(candidates, shift)
        end
        table.sort(candidates, function(a, b)
            return totals[a] > totals[b]
        end)
        for i = #candidates, ROUTE_SHIFT_CANDIDATES + 1, -1 do
            candidates[i] = nil
        end
        if not table.find(candidates, 0) then
            table.insert(candidates, 0)
        end

        local byIndex, order = {}, {}
        for k, step in ipairs(list) do
            local first = step.path.indices[1]
            if not byIndex[first] then
                byIndex[first] = {}
                table.insert(order, first)
            end
            table.insert(byIndex[first], k)
        end
        table.sort(order)

        local score, back = {}, {}
        for c = 1, #candidates do
            score[c] = candidates[c] == 0 and 0 or -ROUTE_SHIFT_PENALTY
        end
        for j, index in ipairs(order) do
            local bestC, bestScore = 1, -math.huge
            for c = 1, #candidates do
                if score[c] > bestScore then
                    bestC, bestScore = c, score[c]
                end
            end
            local nextScore, from = {}, {}
            for c, shift in ipairs(candidates) do
                local gain = 0
                for _, k in ipairs(byIndex[index]) do
                    gain = gain + (stepVotes[k][shift] or 0)
                end
                if score[c] >= bestScore - ROUTE_SHIFT_PENALTY then
                    nextScore[c], from[c] = score[c] + gain, c
                else
                    nextScore[c], from[c] = bestScore - ROUTE_SHIFT_PENALTY + gain, bestC
                end
            end
            score, back[j] = nextScore, from
        end

        local c = 1
        for i = 2, #candidates do
            if score[i] > score[c] then
                c = i
            end
        end
        local shiftOf, changes, previousShift = {}, {}, 0
        for j = #order, 1, -1 do
            shiftOf[order[j]] = candidates[c]
            c = back[j][c]
        end
        for _, index in ipairs(order) do
            if shiftOf[index] ~= previousShift then
                table.insert(changes, { index = index, shift = shiftOf[index] })
                previousShift = shiftOf[index]
            end
        end
        return { order = order, shiftOf = shiftOf }, changes
    end

    local function shiftAt(solution, index)
        local order = solution.order
        local low, high, found = 1, #order, order[1]
        while low <= high do
            local middle = math.floor((low + high) / 2)
            if order[middle] <= index then
                found, low = order[middle], middle + 1
            else
                high = middle - 1
            end
        end
        return found and solution.shiftOf[found] or 0
    end

    local routeTowerName

    local function anchorToRouteTower(path)
        if not IS_TEA or not routeTowerName or #path.names ~= 1 or path.names[1] ~= "Towers" or #path.indices < 2 then
            return
        end
        local towers = workspace:FindFirstChild("Towers")
        if not (towers and towers:FindFirstChild(routeTowerName)) then
            return
        end
        path.names = { "Towers", routeTowerName }
        table.remove(path.indices, 1)
        while type(path.indices[1]) == "string" do
            table.insert(path.names, table.remove(path.indices, 1))
        end
    end

    local function isShuffled(step)
        return #step.path.indices > 0 and #step.path.names == 1 and step.path.names[1] == "ClientParts"
    end

    local function matchShuffled(cache, steps, resolved)
        local before, after, last = {}, {}, nil
        for k = 1, #steps do
            before[k] = last
            last = resolved[k] and resolved[k].Position or (steps[k].kind == "point" and steps[k].position) or last
        end
        last = nil
        for k = #steps, 1, -1 do
            after[k] = last
            last = resolved[k] and resolved[k].Position or (steps[k].kind == "point" and steps[k].position) or last
        end
        local groups, order = {}, {}
        for k, step in ipairs(steps) do
            if step.kind == "part" and step.container and isShuffled(step) then
                local byFirst = groups[step.container]
                if not byFirst then
                    byFirst = {}
                    groups[step.container] = byFirst
                end
                local first = step.path.indices[1]
                if not byFirst[first] then
                    byFirst[first] = {}
                    table.insert(order, { container = step.container, first = first })
                end
                table.insert(byFirst[first], k)
            end
        end
        local far = ROUTE_MAX_GAP * 20
        local changed = 0
        for _, group in ipairs(order) do
            local list = groups[group.container][group.first]
            local kids = childrenOf(cache, group.container)
            local bestShift, bestScore = nil, math.huge
            for c = 1, #kids do
                routeBreather()
                local shift = c - group.first
                local score, found = 0, false
                for _, k in ipairs(list) do
                    local part = partAt(cache, steps[k], shift)
                    local distance = far
                    if part then
                        found = true
                        if before[k] then
                            distance = math.min(distance, (part.Position - before[k]).Magnitude)
                        end
                        if after[k] then
                            distance = math.min(distance, (part.Position - after[k]).Magnitude)
                        end
                    end
                    score = score + (distance)
                end
                if found and score < bestScore then
                    bestShift, bestScore = shift, score
                end
            end
            if bestShift then
                for _, k in ipairs(list) do
                    resolved[k] = partAt(cache, steps[k], bestShift)
                end
                if bestShift ~= 0 then
                    changed = changed + (1)
                end
            end
        end
        return changed
    end

    local function resolveRoute(steps)
        local cache, groups, containers = {}, {}, {}
        for _, step in ipairs(steps) do
            if step.kind == "part" then
                anchorToRouteTower(step.path)
                step.container = resolveNamed(step.path.names)
                if step.container and #step.path.indices > 0 and not step.teleport and not isShuffled(step) then
                    if not groups[step.container] then
                        groups[step.container] = {}
                        table.insert(containers, step.container)
                    end
                    table.insert(groups[step.container], step)
                end
            end
        end

        local shifts, corrections = {}, 0
        AutoPlay.sliceStarted = os.clock()
        for _, container in ipairs(containers) do
            local solution, changes = solveShifts(cache, container, groups[container])
            shifts[container] = solution
            corrections = corrections + (#changes)
            for _, change in ipairs(changes) do
                warn(("[Aery Hub] Auto Play: %s indices from %d shifted by %d"):format(container:GetFullName(), change.index, change.shift))
            end
        end

        local resolved = {}
        for k, step in ipairs(steps) do
            routeBreather()
            local container = step.container
            if step.kind == "part" and container and not isShuffled(step) then
                if #step.path.indices == 0 then
                    resolved[k] = container:IsA("BasePart") and container or nil
                else
                    local solution = shifts[container]
                    resolved[k] = partAt(cache, step, solution and shiftAt(solution, step.path.indices[1]) or 0)
                end
            end
        end
        local matched = matchShuffled(cache, steps, resolved)
        if matched > 0 then
            corrections = corrections + (matched)
            warn(("[Aery Hub] Auto Play: matched %s in workspace.ClientParts by position"):format(plural(matched, "client object")))
        end

        local waypoints, missing = {}, 0
        for k, step in ipairs(steps) do
            routeBreather()
            if step.kind == "jump" then
                table.insert(waypoints, { kind = "jump" })
            elseif step.kind == "wait" then
                table.insert(waypoints, { kind = "wait", seconds = step.seconds })
            elseif step.kind == "point" then
                table.insert(waypoints, { kind = step.teleport and "teleport" or "move", position = step.position })
            else
                local part = resolved[k]
                if part then
                    table.insert(waypoints, { kind = step.teleport and "teleport" or "move", part = part, indexed = #step.path.indices > 0 })
                else
                    missing = missing + (1)
                end
            end
        end

        local function positionNear(i, direction)
            local j = i + direction
            while waypoints[j] do
                local waypoint = waypoints[j]
                if waypoint.kind == "move" or waypoint.kind == "teleport" then
                    return waypoint.part and waypoint.part.Position or waypoint.position
                end
                j = j + (direction)
            end
            return nil
        end

        local skipBad = not Toggles.SkipBadWaypoints or Toggles.SkipBadWaypoints.Value
        local kept = {}
        for i, waypoint in ipairs(waypoints) do
            local keep = true
            if skipBad and waypoint.kind == "move" and waypoint.indexed then
                local here = waypoint.part.Position
                local before, after = positionNear(i, -1), positionNear(i, 1)
                local fromBefore = before and (here - before).Magnitude or 0
                local toAfter = after and (here - after).Magnitude or 0
                if before and after
                    and fromBefore > ROUTE_MAX_GAP
                    and toAfter > ROUTE_MAX_GAP
                    and (after - before).Magnitude <= math.max(ROUTE_MAX_GAP, math.min(fromBefore, toAfter) * 0.25) then
                    keep = false
                    missing = missing + (1)
                end
            end
            if keep then
                table.insert(kept, waypoint)
            end
        end
        return kept, corrections, missing
    end

    local function loadRoute(towerName)
        local source, problem, isLocal = fetchRoute(towerName)
        if not source then
            return false, problem
        end
        routeTowerName = (towerName:gsub("_SE$", ""))
        local steps = parseRoute(source)
        if not steps then
            if isLocal then
                return false, false
            end
            return false, "Couldn't read the route for " .. towerName
        end
        local waypoints, corrections, missing = resolveRoute(steps)
        local nodes = {}
        for _, waypoint in ipairs(waypoints) do
            if waypoint.kind == "move" or waypoint.kind == "teleport" then
                table.insert(nodes, waypoint)
            end
        end
        if #nodes == 0 then
            return false, "No route found for " .. towerName
        end
        if IS_TEA then
            local first
            for _, node in ipairs(nodes) do
                if node.position then
                    first = node.position
                    break
                end
            end
            local tower = workspace:FindFirstChild("Towers") and workspace.Towers:FindFirstChild(towerName)
            local spawnPad = tower and tower:FindFirstChild("SpawnPad")
            if first and spawnPad and spawnPad:IsA("BasePart") then
                local standing = spawnPad.Position + Vector3.new(0, spawnPad.Size.Y / 2 + 3, 0)
                local difference = standing - first
                if difference.Magnitude > 300 then
                    local offset = Vector3.new(
                        math.abs(difference.X) > 100 and difference.X or 0,
                        difference.Y,
                        math.abs(difference.Z) > 100 and difference.Z or 0
                    )
                    for _, node in ipairs(nodes) do
                        if node.position then
                            node.position = node.position + (offset)
                        end
                    end
                end
            end
        end
        AutoPlay.waypoints = waypoints
        AutoPlay.routeNodes = nodes
        if corrections > 0 or missing > 0 then
            notify("Auto Play", ("Fixed %d index shift(s), skipped %d bad waypoint(s)."):format(corrections, missing), 5)
        end
        return true
    end

    local ROUTE_HOP_DISTANCE = 500

    local function isLongHop(distance)
        local toggle = Toggles.TeleportFarWaypoints
        return distance > ROUTE_HOP_DISTANCE and (not toggle or toggle.Value)
    end

    local function nodePosition(node)
        if node.part then
            return node.part.Parent and node.part.Position or nil
        end
        return node.position
    end

    local ROUTE_ORDER_JUMP = 60
    local ROUTE_ORDER_MIN_JUMPS = 5
    local ROUTE_ORDER_MAX_SHARE = 0.32

    local function routeOrderProblem()
        local jumps, steps = 0, 0
        for i = 2, #AutoPlay.routeNodes do
            local node = AutoPlay.routeNodes[i]
            if node.kind ~= "teleport" then
                local from, to = nodePosition(AutoPlay.routeNodes[i - 1]), nodePosition(node)
                if from and to then
                    steps = steps + (1)
                    local gap = (to - from).Magnitude
                    if gap > ROUTE_ORDER_JUMP and gap <= ROUTE_HOP_DISTANCE then
                        jumps = jumps + (1)
                    end
                end
            end
        end
        if jumps >= ROUTE_ORDER_MIN_JUMPS and jumps > steps * ROUTE_ORDER_MAX_SHARE then
            return "This route may get you kicked."
        end
        return nil
    end

    local function updateTiming()
        if #AutoPlay.routeNodes < 2 then
            return
        end
        local minutes = tonumber(Options.EstMinutes and Options.EstMinutes.Value) or 3
        local seconds = tonumber(Options.EstSeconds and Options.EstSeconds.Value) or 0
        local total = AutoPlay.timeOverride or (minutes * 60 + seconds)
        if total <= 0 then
            return
        end
        local length = 0
        for i = 2, #AutoPlay.routeNodes do
            local node = AutoPlay.routeNodes[i]
            if node.kind ~= "teleport" then
                local from, to = nodePosition(AutoPlay.routeNodes[i - 1]), nodePosition(node)
                local segment = from and to and (to - from).Magnitude
                if segment and not isLongHop(segment) then
                    length = length + segment
                end
            end
        end
        if length > 0 then
            AutoPlay.speed = length / total
        end
    end

    local function clearRoute()
        if AutoPlay.routeFolder then
            AutoPlay.routeFolder:Destroy()
            AutoPlay.routeFolder = nil
        end
    end

    local function drawRoute()
        clearRoute()
        if not AutoPlay.showRoute or #AutoPlay.routeNodes < 2 then
            return
        end
        local color = Options.RouteColor and Options.RouteColor.Value or Color3.new(0, 1, 0)
        local folder = Instance.new("Folder")
        folder.Name = "AutoPlayRoute"
        folder.Parent = workspace
        AutoPlay.routeFolder = folder

        local anchor = Instance.new("Part")
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanQuery = false
        anchor.CanTouch = false
        anchor.Transparency = 1
        anchor.Size = Vector3.new(0.1, 0.1, 0.1)
        anchor.Parent = folder

        for i = 1, #AutoPlay.routeNodes - 1 do
            local from, to = nodePosition(AutoPlay.routeNodes[i]), nodePosition(AutoPlay.routeNodes[i + 1])
            if from and to and AutoPlay.routeNodes[i + 1].kind ~= "teleport" and not isLongHop((to - from).Magnitude) then
                local a0 = Instance.new("Attachment")
                a0.Parent = anchor
                a0.WorldPosition = from + Vector3.new(0, 2, 0)
                local a1 = Instance.new("Attachment")
                a1.Parent = anchor
                a1.WorldPosition = to + Vector3.new(0, 2, 0)
                local beam = Instance.new("Beam")
                beam.Attachment0 = a0
                beam.Attachment1 = a1
                beam.Color = ColorSequence.new(color)
                beam.Width0 = 0.15
                beam.Width1 = 0.15
                beam.FaceCamera = true
                beam.LightEmission = 1
                beam.Parent = anchor
            end
        end
    end

    local function setAutoNoclip(state)
        AutoPlay.noclip = state
        if AutoPlay.noclipConnection then
            AutoPlay.noclipConnection:Disconnect()
            AutoPlay.noclipConnection = nil
        end
        disconnectAll(AutoPlay.collideWatch)
        if state then
            table.clear(AutoPlay.originalCollide)
            AutoPlay.noclipConnection = RunService.Stepped:Connect(function()
                local character = getCharacter()
                if not AutoPlay.noclip or not character then
                    return
                end
                PhysicsFixer.pause(character, "autoplay")
                local root = character:FindFirstChild("HumanoidRootPart")
                if root then
                    for _, joint in ipairs(root:GetJoints()) do
                        if joint:IsA("WeldConstraint") or joint:IsA("JointInstance") then
                            local other = joint.Part0 == root and joint.Part1 or joint.Part0
                            if other and not other:IsDescendantOf(character) then
                                joint:Destroy()
                            end
                        end
                    end
                end
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if AutoPlay.originalCollide[part] == nil then
                            AutoPlay.originalCollide[part] = part.CanCollide
                            table.insert(AutoPlay.collideWatch, part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                                if AutoPlay.noclip and part.Parent then
                                    part.CanCollide = false
                                end
                            end))
                        end
                        part.CanCollide = false
                    end
                end
            end)
        else
            for part, canCollide in pairs(AutoPlay.originalCollide) do
                if part.Parent then
                    part.CanCollide = canCollide
                end
            end
            table.clear(AutoPlay.originalCollide)
            PhysicsFixer.resume("autoplay")
        end
    end

    local function returnToLobby()
        local team = LocalPlayer.Team
        if not team or team.Name ~= "Winner!" then
            return
        end
        local misc = workspace:FindFirstChild("Misc")
        local restart = misc and misc:FindFirstChild("RestartBrick")
        if not restart then
            for _, descendant in ipairs(workspace:GetDescendants()) do
                if descendant.Name == "RestartBrick" and descendant:IsA("BasePart") then
                    restart = descendant
                    break
                end
            end
        end
        local root = getRoot()
        if restart and root then
            root.CFrame = restart.CFrame
        end
    end

    local function updatePauseButton()
        local text = "Pause"
        if AutoPlay.paused then
            text = "Resume"
        elseif AutoPlay.pauseRequested then
            text = "Pausing..."
        end
        for _, button in pairs({ pauseButton or false, rushPauseButton or false }) do
            if button then
                button:SetText(text)
            end
        end
    end

    local function setAutoPlayPaused(paused)
        AutoPlay.paused = paused
        AutoPlay.pauseRequested = false
        updatePauseButton()
    end

    local function waitWhilePaused()
        local pausedAt = tick()
        local root = getRoot()
        if root then
            root.AssemblyLinearVelocity = Vector3.zero
            root.Anchored = true
        end
        while AutoPlay.running and AutoPlay.paused do
            RunService.Heartbeat:Wait()
        end
        if root and root.Parent then
            root.Anchored = false
        end
        return tick() - pausedAt
    end

    local function stopAutoPlay()
        setAutoPlayPaused(false)
        local thread = AutoPlay.loopThread
        if thread and thread ~= coroutine.running() then
            AutoPlay.loopThread = nil
            pcall(task.cancel, thread)
        end
        disconnectAll(AutoPlay.loadWatch)
        if AutoPlay.deathWatch then
            AutoPlay.deathWatch:Disconnect()
            AutoPlay.deathWatch = nil
        end
        if AutoPlay.rushWatch then
            AutoPlay.rushWatch:Disconnect()
            AutoPlay.rushWatch = nil
        end
        if not AutoPlay.running then
            return
        end
        AutoPlay.running = false
        setAutoNoclip(false)
        workspace.Gravity = AutoPlay.originalGravity
        local humanoid = getHumanoid()
        if humanoid then
            humanoid.PlatformStand = false
            pcall(function()
                humanoid:ChangeState(Enum.HumanoidStateType.Running)
            end)
        end
        local root = getRoot()
        if root then
            root.Anchored = false
        end
        if Toggles.ReturnToLobby and Toggles.ReturnToLobby.Value then
            task.spawn(function()
                task.wait(1)
                returnToLobby()
            end)
        end
    end

    local moveTo = function(node)
        local root = getRoot()
        local humanoid = getHumanoid()
        local position = nodePosition(node)
        if not root or not humanoid then
            return false
        end
        if not position then
            return true
        end
        local target = position + Vector3.new(0, 3, 0)
        if node.kind == "teleport" or isLongHop((root.Position - target).Magnitude) then
            root.AssemblyLinearVelocity = Vector3.zero
            root.CFrame = CFrame.new(target) * (root.CFrame - root.CFrame.Position)
            return true
        end
        humanoid.PlatformStand = true
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.PlatformStanding)
        end)
        local start = root.Position
        local duration = (target - start).Magnitude / math.max(AutoPlay.speed, 0.01)
        local began = tick()
        while AutoPlay.running do
            if AutoPlay.paused then
                began = began + (waitWhilePaused())
                root = getRoot() or root
            end
            local alpha = duration > 0 and math.clamp((tick() - began) / duration, 0, 1) or 1
            local point = start:Lerp(target, alpha)
            root.AssemblyLinearVelocity = Vector3.zero
            root.CFrame = CFrame.new(point) * (root.CFrame - root.CFrame.Position)
            if alpha >= 1 then
                break
            end
            RunService.Heartbeat:Wait()
        end
        return true
    end

    local RUSH_WAIT = 30

    local function rushTowerList(source)
        local chunk = loadstring(source)
        if not chunk then
            return nil
        end
        setfenv(chunk, {})
        local ok, result = pcall(chunk)
        if ok and type(result) == "function" then
            ok, result = pcall(result)
        end
        if not ok or type(result) ~= "table" or #result == 0 then
            return nil
        end
        for _, entry in ipairs(result) do
            if type(entry) ~= "string" or entry == "jump" then
                return nil
            end
        end
        return result
    end

    local SOUL_CRUSHING = { Insane = true, Extreme = true, Terrifying = true, Catastrophic = true, Horrific = true, Unreal = true }

    refreshRushStatus = function()
        local towers = workspace:FindFirstChild("Towers")
        if not towers then
            return
        end
        for _, tower in ipairs(towers:GetChildren()) do
            local rushName = tower.Name
            if tower:FindFirstChild("TowerRushList") and routeNames[rushName] then
                task.spawn(function()
                    local ok, source, _, isLocal = pcall(fetchRoute, rushName)
                    local list = ok and type(source) == "string" and not isLocal and rushTowerList(source)
                    local complete = list and true or false
                    if list then
                        for _, name in ipairs(list) do
                            local difficulty = towerDifficultyName(name)
                            if not (difficulty and SOUL_CRUSHING[difficulty]) and not routeNames[name] then
                                complete = false
                                break
                            end
                        end
                    end
                    routeNames[rushName] = complete
                    if Options.TowerDropdown then
                        Options.TowerDropdown:Display()
                    end
                    if Options.RushDropdown then
                        Options.RushDropdown:Display()
                    end
                end)
            end
        end
    end

    local function runWaypoints()
        for _, step in ipairs(AutoPlay.waypoints) do
            if AutoPlay.pauseRequested then
                setAutoPlayPaused(true)
            end
            if AutoPlay.paused then
                waitWhilePaused()
            end
            if not AutoPlay.running then
                return false
            end
            if step.kind == "jump" then
                local humanoid = getHumanoid()
                if humanoid then
                    humanoid.PlatformStand = false
                    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            elseif step.kind == "wait" then
                local remaining = step.seconds or 0
                while remaining > 0 and AutoPlay.running do
                    if AutoPlay.paused then
                        waitWhilePaused()
                    else
                        remaining = remaining - (RunService.Heartbeat:Wait())
                    end
                end
            elseif not moveTo(step) then
                return false
            end
        end
        return AutoPlay.running
    end

    local function beginAutoPlay()
        stopAutoPlay()
        AutoPlay.originalGravity = workspace.Gravity
        AutoPlay.running = true
        setAutoNoclip(true)
        workspace.Gravity = 0
        local humanoid = getHumanoid()
        if humanoid then
            AutoPlay.deathWatch = humanoid.Died:Connect(stopAutoPlay)
        end
    end

    local RUSH_TELEPORT_DISTANCE = 50
    local RUSH_LEFT_GRACE = 10

    local function handControlToPlayer()
        setAutoPlayPaused(false)
        setAutoNoclip(false)
        workspace.Gravity = AutoPlay.originalGravity
        local humanoid = getHumanoid()
        if humanoid then
            humanoid.PlatformStand = false
            pcall(function()
                humanoid:ChangeState(Enum.HumanoidStateType.Running)
            end)
        end
        local root = getRoot()
        if root then
            root.Anchored = false
        end
    end

    local function takeControlBack()
        setAutoNoclip(true)
        workspace.Gravity = 0
    end

    local function waitForRushTower(previousName, timeout)
        local deadline = timeout and tick() + timeout
        local root = getRoot()
        local lastPosition = root and root.Position
        local teleported = false
        local leftSince
        while AutoPlay.running do
            if deadline and tick() >= deadline then
                return nil, "timeout"
            end
            if AutoPlay.paused and deadline then
                deadline = deadline + waitWhilePaused()
            end
            root = getRoot()
            if root then
                if lastPosition and (root.Position - lastPosition).Magnitude > RUSH_TELEPORT_DISTANCE then
                    teleported = true
                end
                lastPosition = root.Position
            end
            local current = currentKitTower()
            if current == nil then
                leftSince = leftSince or tick()
                if tick() - leftSince >= RUSH_LEFT_GRACE then
                    return nil, "left"
                end
            else
                leftSince = nil
                if root and (current ~= previousName or teleported) then
                    return current
                end
            end
            RunService.Heartbeat:Wait()
        end
        return nil, "stopped"
    end

    local function parseRushTime(text)
        if type(text) ~= "string" then
            return nil
        end
        local minutes, seconds = text:match("^%s*(%d+):(%d+%.?%d*)%s*$")
        if minutes then
            return (tonumber(minutes) or 0) * 60 + (tonumber(seconds) or 0)
        end
        local value = tonumber(text)
        if value and value > 0 then
            return value * 60
        end
        return nil
    end

    local function rushTimeId(rushName, towerName)
        return "RushTime_" .. rushName .. "_" .. towerName
    end

    local function rushTowerTime(rushName, towerName)
        local option = Options[rushTimeId(rushName, towerName)]
        local total = option and parseRushTime(option.Value)
        if total and total > 0 then
            return total
        end
        return 180
    end

    local RUSH_SETTLE_TIME = 1
    local RUSH_SETTLE_LIMIT = 8

    local function waitForTowerLoad()
        local lastChange = tick()
        local function changed()
            lastChange = tick()
        end
        table.insert(AutoPlay.loadWatch, workspace.DescendantAdded:Connect(changed))
        table.insert(AutoPlay.loadWatch, workspace.DescendantRemoving:Connect(changed))
        local deadline = tick() + RUSH_SETTLE_LIMIT
        while AutoPlay.running and tick() < deadline and tick() - lastChange < RUSH_SETTLE_TIME do
            task.wait(0.1)
        end
        disconnectAll(AutoPlay.loadWatch)
    end

    local function startRush(rushName, towers)
        beginAutoPlay()
        AutoPlay.loopThread = task.spawn(function()
            local manualList = Options["RushManual_" .. rushName]
            local fetched = {}
            for _, towerName in ipairs(towers) do
                local skip = fetched[towerName] or manualList and type(manualList.Value) == "table" and manualList.Value[towerName] == true
                fetched[towerName] = true
                if not skip and AutoPlay.running then
                    pcall(fetchRoute, towerName)
                end
            end
            if not AutoPlay.running then
                return
            end
            local function rushLength()
                if IS_CSCD then
                    return AutoPlay.rushInfo and tonumber(AutoPlay.rushInfo.TotalTowers)
                end
                local progress = IS_ASTN and LocalPlayer:GetAttribute("TowerRush")
                return tonumber(type(progress) == "string" and progress:match("/(%d+)") or nil)
            end
            local enteredRush = false
            if currentKitTower() == nil then
                AutoPlay.rushInfo = nil
                local events = IS_CSCD and ReplicatedStorage:FindFirstChild("All_Areas") and ReplicatedStorage.All_Areas:FindFirstChild("GlobalEvents")
                local loadEvent = events and events:FindFirstChild("LoadCO")
                if loadEvent then
                    AutoPlay.rushWatch = loadEvent.OnClientEvent:Connect(function(...)
                        local info = select(10, ...)
                        if type(info) == "table" then
                            AutoPlay.rushInfo = info
                        end
                    end)
                end
                local entered, problem = enterTower(rushName)
                if not entered then
                    notify("Auto Play", problem or ("Couldn't enter " .. rushName), 5)
                    stopAutoPlay()
                    return
                end
                enteredRush = true
            end
            local total = #towers
            if enteredRush and (IS_ASTN or IS_CSCD) then
                local deadline = tick() + RUSH_WAIT
                while AutoPlay.running and not rushLength() and tick() < deadline do
                    task.wait(0.1)
                end
                total = rushLength() or total
            end
            local previousName
            local manual = false
            for index = 1, total do
                local name, reason = waitForRushTower(previousName, not manual and RUSH_WAIT or nil)
                if not name then
                    if reason == "timeout" then
                        notify("Auto Play", ("Rush stopped: no tower came after %s."):format(previousName or rushName), 5)
                    elseif reason == "left" then
                        notify("Auto Play", "Rush ended.", 4)
                    end
                    break
                end
                previousName = name
                waitForTowerLoad()
                if not AutoPlay.running then
                    break
                end
                local manualOption = Options["RushManual_" .. rushName]
                local playMyself = manualOption and type(manualOption.Value) == "table" and manualOption.Value[name] == true
                local loaded = false
                if not playMyself then
                    loaded = loadRoute(name)
                end
                if loaded then
                    if manual then
                        takeControlBack()
                        manual = false
                    end
                    AutoPlay.timeOverride = rushTowerTime(rushName, name)
                    updateTiming()
                    drawRoute()
                    notify("Auto Play", ("Rush: %s (%d/%d)"):format(name, index, total), 3)
                    local orderProblem = routeOrderProblem()
                    if orderProblem then
                        notify("Auto Play", orderProblem, 6)
                    end
                    if not runWaypoints() then
                        break
                    end
                else
                    if not manual then
                        handControlToPlayer()
                        manual = true
                    end
                    clearRoute()
                    if playMyself then
                        notify("Auto Play", ("Your turn: %s (%d/%d)."):format(name, index, total), 6)
                    else
                        notify("Auto Play", ("No route for %s (%d/%d)."):format(name, index, total), 6)
                    end
                    if index == total then
                        break
                    end
                end
            end
            AutoPlay.timeOverride = false
            stopAutoPlay()
        end)
    end

    local function startAutoPlay(seconds)
        stopAutoPlay()
        AutoPlay.timeOverride = seconds or false
        local baseName = Options.TowerDropdown.Value
        if not baseName then
            return
        end
        local towerName = baseName
        if Toggles.SecretEnding and Toggles.SecretEnding.Value and hasSecretEnding(baseName) then
            towerName = baseName .. "_SE"
        end
        local source, fetchProblem, isLocal = fetchRoute(towerName)
        local towers = source and not isLocal and rushTowerList(source)
        if towers then
            startRush(towerName, towers)
            return
        end
        if currentKitTower() ~= baseName then
            if not source then
                notify("Auto Play", fetchProblem or ("No route found for " .. towerName))
                return
            end
            local entered, problem = enterTower(baseName)
            if not entered then
                notify("Auto Play", problem or ("Couldn't enter " .. baseName))
                return
            end
            AutoPlay.originalGravity = workspace.Gravity
            AutoPlay.running = true
            AutoPlay.loopThread = task.spawn(function()
                local deadline = tick() + RUSH_WAIT
                while currentKitTower() ~= baseName and tick() < deadline do
                    task.wait(0.1)
                end
                if currentKitTower() ~= baseName then
                    notify("Auto Play", "Couldn't enter " .. baseName)
                    stopAutoPlay()
                    return
                end
                waitForTowerLoad()
                if AutoPlay.running then
                    AutoPlay.running = false
                    startAutoPlay(seconds)
                end
            end)
            return
        end
        local loaded, problem = loadRoute(towerName)
        if not loaded then
            if problem ~= false then
                notify("Auto Play", problem or ("No route found for " .. towerName))
            end
            return
        end
        local orderProblem = routeOrderProblem()
        if orderProblem then
            notify("Auto Play", orderProblem, 6)
        end
        updateTiming()
        drawRoute()
        beginAutoPlay()
        local character = getCharacter()
        if character then
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") then
                    table.insert(AutoPlay.loadWatch, part.Touched:Connect(function(hit)
                        if isWinpadPart(hit) then
                            stopAutoPlay()
                        end
                    end))
                end
            end
        end
        AutoPlay.loopThread = task.spawn(function()
            runWaypoints()
            stopAutoPlay()
        end)
    end

    AutoPlayBox:AddButton({
        Text = "Auto Play",
        DoubleClick = false,
        Tooltip = "Plays the selected tower for you.",
        Func = function()
            startAutoPlay()
        end,
    })

    ChatCommands.stop = stopAutoPlay

    ChatCommands.complete = function(argument)
        local function parseSeconds(text)
            local minutes, rest = text:match("^(%d+):(%d+%.?%d*)$")
            local value = minutes and (tonumber(minutes) or 0) * 60 + (tonumber(rest) or 0) or tonumber(text)
            return value and value > 0 and value or nil
        end
        local name, seconds
        if argument ~= "" then
            seconds = parseSeconds(argument)
            if not seconds then
                name = findTowerName(argument)
                if not name then
                    local rest, last = argument:match("^(.-)%s+(%S+)$")
                    seconds = last and parseSeconds(last)
                    name = seconds and findTowerName(rest)
                end
                if not name then
                    notify("/complete", "No " .. (IS_TOR and "obby" or "tower") .. " called " .. argument .. ".")
                    return
                end
            end
        end
        name = name or currentKitTower()
        if not name then
            notify("/complete", "You must be in " .. (IS_TOR and "an obby" or "a tower") .. " or name one: /complete <name> [time]")
            return
        end
        Options.TowerDropdown:SetValue(name)
        if Options.TowerDropdown.Value ~= name then
            notify("/complete", name .. " isn't in the " .. (IS_TOR and "Obbies" or "Towers") .. " list.")
            return
        end
        startAutoPlay(seconds)
    end

    AutoPlayBox:AddToggle("SecretEnding", {
        Text = "Secret Ending",
        Default = false,
        Tooltip = "Plays the tower's secret ending route instead.",
    })

    refreshSecretEnding = function()
        Toggles.SecretEnding:SetVisible(hasSecretEnding(Options.TowerDropdown.Value))
    end
    refreshSecretEnding()

    local function pressPause()
        if not AutoPlay.running then
            return
        end
        if AutoPlay.paused then
            setAutoPlayPaused(false)
        elseif AutoPlay.pauseRequested or (Toggles.InstantPause and Toggles.InstantPause.Value) then
            setAutoPlayPaused(true)
        else
            AutoPlay.pauseRequested = true
            updatePauseButton()
        end
    end

    local PauseButton = AutoPlayBox:AddButton({
        Text = "Pause",
        DoubleClick = false,
        Tooltip = "Pauses or resumes Auto Play.",
        Func = pressPause,
    })
    PauseButton:AddButton({
        Text = "Stop",
        DoubleClick = false,
        Tooltip = "Stops Auto Play.",
        Func = stopAutoPlay,
    })
    pauseButton = PauseButton

    local AutoPlaySettingsBox = Tabs.Main:AddLeftGroupbox("Auto Play Settings")

    AutoPlaySettingsBox:AddToggle("InstantPause", {
        Text = "Instant Pause",
        Default = false,
        Tooltip = "Pause stops on the spot instead of finishing the current move first.",
    })

    table.insert(panicHandlers, stopAutoPlay)

    Library:OnUnload(function()
        stopAutoPlay()
        AutoPlay.showRoute = false
        clearRoute()
    end)

    AutoPlaySettingsBox:AddDivider()

    AutoPlaySettingsBox:AddInput("EstMinutes", {
        Text = "Run Minutes",
        Tooltip = "Sets the minutes Auto Play takes to finish the route.",
        Default = "3",
        Numeric = true,
        Finished = false,
        Placeholder = "3",
        Callback = updateTiming,
    })

    AutoPlaySettingsBox:AddInput("EstSeconds", {
        Text = "Run Seconds",
        Tooltip = "Sets the seconds Auto Play takes to finish the route.",
        Default = "0",
        Numeric = true,
        Finished = false,
        Placeholder = "0",
        Callback = updateTiming,
    })

    AutoPlaySettingsBox:AddDivider()

    AutoPlaySettingsBox:AddToggle("SkipBadWaypoints", {
        Text = "Skip Bad Waypoints",
        Default = true,
        Tooltip = "Skips a waypoint that sticks far out from the ones around it.",
    })

    AutoPlaySettingsBox:AddToggle("TeleportFarWaypoints", {
        Text = "Teleport Far Waypoints",
        Default = true,
        Tooltip = "Teleports straight to a waypoint more than 500 studs away instead of flying there.",
        Callback = function()
            updateTiming()
            drawRoute()
        end,
    })

    AutoPlaySettingsBox:AddToggle("ShowRoute", {
        Text = "Show Route",
        Tooltip = "Draws the loaded route's path on screen.",
        Default = false,
        Callback = function(enabled)
            AutoPlay.showRoute = enabled
            if enabled then
                drawRoute()
            else
                clearRoute()
            end
        end,
    }):AddColorPicker("RouteColor", {
        Title = "Route Color",
        Default = Color3.new(0, 1, 0),
        Transparency = 0,
        Callback = function()
            if AutoPlay.showRoute then
                drawRoute()
            end
        end,
    })

    AutoPlaySettingsBox:AddToggle("ReturnToLobby", {
        Text = "Return to Lobby After Win",
        Default = false,
        Tooltip = "Teleports you back to the lobby after you complete the tower.",
    })

    local AutomationBox = IS_TOR and NullBox or AutoPlaySettingsBox
    AutomationBox:AddDivider()
    local farmRun = 0

    local function attemptLimit()
        local value = Options.FarmAttemptCount and Options.FarmAttemptCount.Value
        local limit = tonumber(value)
        if not limit or limit < 1 then
            return math.huge
        end
        return math.floor(limit)
    end

    AutomationBox:AddToggle("FarmAttempts", {
        Text = "Farm Attempts",
        Tooltip = "Restarts the selected tower over and over to raise your attempt count.",
        Default = false,
        Callback = function(enabled)
            farmRun = farmRun + (1)
            if not enabled then
                return
            end
            local run = farmRun
            local towerName = Options.TowerDropdown and Options.TowerDropdown.Value
            if (game.GameId == ETOH_GAME_ID or IS_CSCD or IS_ASTN) and (type(towerName) ~= "string" or towerName == "") then
                notify("Farm Attempts", "Select a tower in the Main dropdown first.")
                Toggles.FarmAttempts:SetValue(false)
                return
            end

            local function waitForRespawn(oldCharacter)
                local deadline = tick() + 15
                while farmRun == run and tick() < deadline do
                    local character = getCharacter()
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    if character and character ~= oldCharacter and humanoid and humanoid.Health > 0 and getRoot() then
                        return true
                    end
                    task.wait(0.1)
                end
                return false
            end

            task.spawn(function()
                local done = 0
                while farmRun == run and done < attemptLimit() do
                    local counted = false
                    if game.GameId == TEA_GAME_ID then
                        local tower = LocalPlayer:GetAttribute("Tower")
                        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                        local runClientObjects = remotes and remotes:FindFirstChild("RunClientObjects")
                        if tower and tower ~= "" and runClientObjects then
                            counted = pcall(function()
                                runClientObjects:FireServer(tower)
                            end)
                        end
                        task.wait(0.5)
                    elseif game.GameId == ETOH_GAME_ID or IS_CSCD or IS_ASTN then
                        local entered, problem = enterTower(towerName)
                        if not entered then
                            if farmRun == run then
                                notify("Farm Attempts", problem or ("Couldn't enter " .. towerName), 5)
                                Toggles.FarmAttempts:SetValue(false)
                            end
                            return
                        end
                        currentKitTower()
                        local kit = not IS_CSCD and kitController or nil
                        if kit then
                            local loadDeadline = tick() + 15
                            while farmRun == run and not (kit.Tower == towerName and kit.CanReset) and tick() < loadDeadline do
                                RunService.Heartbeat:Wait()
                            end
                        else
                            task.wait(1.5)
                        end
                        if farmRun ~= run then
                            return
                        end
                        local character = getCharacter()
                        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                        if humanoid and humanoid.Health > 0 then
                            counted = pcall(function()
                                if kit then
                                    kit.DiedFromReset = true
                                end
                                humanoid.Health = -1
                            end)
                        end
                        if counted and farmRun == run then
                            done = done + (1)
                            counted = false
                        end
                        if done >= attemptLimit() then
                            break
                        end
                        if not waitForRespawn(character) then
                            if farmRun == run then
                                notify("Farm Attempts", "Timed out waiting to respawn.", 5)
                                Toggles.FarmAttempts:SetValue(false)
                            end
                            return
                        end
                        task.wait(0.5)
                    else
                        task.wait(1)
                    end
                    if counted and farmRun == run then
                        done = done + (1)
                    end
                end
                if farmRun == run then
                    notify("Farm Attempts", "Finished " .. plural(done, "attempt") .. ".", 5)
                    Toggles.FarmAttempts:SetValue(false)
                end
            end)
        end,
    })

    AutomationBox:AddInput("FarmAttemptCount", {
        Text = "Attempt Limit",
        Tooltip = "How many resets before Farm Attempts stops.",
        Default = "",
        Numeric = true,
        Finished = false,
        Placeholder = "Unlimited",
    })

    AutoPlayBox:AddDivider()
    AutoPlayBox:AddButton({
        Text = "Open Aery Recorder",
        DoubleClick = false,
        Tooltip = "Loads Aery Recorder in its own window to make Auto Play routes.",
        Func = function()
            if AutoPlay.recorderLoading then
                return
            end
            AutoPlay.recorderLoading = true
            task.delay(5, function()
                AutoPlay.recorderLoading = false
            end)
            task.spawn(function()
                local ok, problem = pcall(function()
                    loadstring(game:HttpGet("https://api.luarmor.net/files/v3/loaders/8720fab2c05912e3fef8cc8558323fcf.lua"))()
                end)
                AutoPlay.recorderLoading = false
                if not ok then
                    notify("Aery Recorder", "Couldn't load Aery Recorder: " .. tostring(problem), 6)
                end
            end)
        end,
    })

    if Tabs.TowerRush then
        local RushBox = Tabs.TowerRush:AddLeftGroupbox("Tower Rush")
        local rushNames = {}
        for _, tower in ipairs(IS_ASTN and (workspace:FindFirstChild("Portals") or workspace):GetChildren() or workspace.Towers:GetChildren()) do
            local rushValue = IS_ASTN and tower:FindFirstChild("TowerRush")
            if rushValue and rushValue:IsA("StringValue") and not table.find(rushNames, rushValue.Value) then
                table.insert(rushNames, rushValue.Value)
            elseif not IS_ASTN and tower:FindFirstChild("TowerRushList") then
                table.insert(rushNames, tower.Name)
            end
        end
        local cscdRushes = IS_CSCD and workspace:FindFirstChild("Teleporters") and workspace.Teleporters:FindFirstChild("TowerRushes")
        for _, part in ipairs(cscdRushes and cscdRushes:GetChildren() or {}) do
            local acronym = cscdAcronym(part.Name)
            if part:IsA("BasePart") and not table.find(rushNames, acronym) then
                table.insert(rushNames, acronym)
            end
        end
        local cscdRushInfo = {}
        if IS_CSCD then
            pcall(function()
                cscdRushInfo = require(ReplicatedStorage.All_Areas.TOWER_RUSH_INFO)
            end)
        end
        table.sort(rushNames)
        if #rushNames == 0 then
            RushBox:AddLabel("There is no tower rush in this area.", true)
        else
            local rushLists = {}
            local rushInputs = {}
            local rushBoxes = {}

            local function inlineInput(input)
                local holder = input and input.Holder
                local label = holder and holder:FindFirstChildOfClass("TextLabel")
                local box = holder and holder:FindFirstChildOfClass("TextBox")
                if not (label and box) then
                    return
                end
                holder.Size = UDim2.new(1, 0, 0, 21)
                label.Position = UDim2.fromScale(0, 0)
                label.Size = UDim2.new(0.5, -4, 1, 0)
                box.AnchorPoint = Vector2.new(1, 0)
                box.Position = UDim2.fromScale(1, 0)
                box.Size = UDim2.new(0.5, -4, 1, 0)
            end
            RushBox:AddDropdown("RushDropdown", {
                Text = "Rush",
                Tooltip = "Selects the tower rush that Start Rush plays.",
                Values = rushNames,
                Default = 1,
                Multi = false,
                FormatListValue = formatTowerName,
                FormatDisplayValue = formatTowerName,
            })
            local rushInfo = RushBox:AddLabel("", true)

            for _, rushName in ipairs(rushNames) do
                local towers = IS_ASTN and towerNames
                local info = IS_CSCD and type(cscdRushInfo) == "table" and cscdRushInfo[rushName]
                if type(info) == "table" and type(info.Towers) == "table" then
                    towers = {}
                    for _, entry in ipairs(info.Towers) do
                        if type(entry) == "table" and type(entry.Name) == "string" then
                            for _ = 1, math.max(tonumber(entry.Count) or 1, 1) do
                                table.insert(towers, entry.Name)
                            end
                        end
                    end
                    if #towers == 0 then
                        towers = nil
                    end
                elseif not (IS_ASTN or IS_CSCD) then
                    local ok, source, _, isLocal = pcall(fetchRoute, rushName)
                    towers = ok and type(source) == "string" and not isLocal and rushTowerList(source)
                end
                if towers then
                    rushLists[rushName] = towers
                    rushInputs[rushName] = {}
                    local TimesBox = Tabs.TowerRush:AddRightGroupbox(#rushNames > 1 and (rushLabels[rushName] or rushName) .. " Times" or "Tower Times")
                    rushBoxes[rushName] = TimesBox
                    local distinct, listed = {}, {}
                    for _, towerName in ipairs(towers) do
                        if not listed[towerName] then
                            listed[towerName] = true
                            table.insert(distinct, towerName)
                        end
                    end
                    RushBox:AddDropdown("RushManual_" .. rushName, {
                        Text = "Play Myself",
                        Values = distinct,
                        Multi = true,
                        AllowNull = true,
                        Tooltip = "Towers you play yourself in this rush.",
                        Callback = function()
                            if updateRushInfo then
                                updateRushInfo()
                            end
                        end,
                    })
                    TimesBox:AddLabel("Minutes per tower (3, 1.5 or 1:30).", true)
                    for _, towerName in ipairs(distinct) do
                        local input = TimesBox:AddInput(rushTimeId(rushName, towerName), {
                            Text = towerName,
                            Default = "3",
                            Numeric = false,
                            Finished = false,
                            ClearTextOnFocus = false,
                            Placeholder = "3",
                        })
                        rushInputs[rushName][towerName] = input
                        inlineInput(input)
                    end
                    pcall(function()
                        TimesBox:Resize()
                    end)
                end
            end

            RushBox:AddDivider()
            RushBox:AddButton({
                Text = "Start Rush",
                DoubleClick = false,
                Tooltip = "Plays the selected rush. Towers without a route are left to you.",
                Func = function()
                    local rushName = Options.RushDropdown.Value
                    local towers = rushName and rushLists[rushName]
                    if not towers then
                        notify("Tower Rush", "Couldn't load the tower list for " .. tostring(rushName) .. ".")
                        return
                    end
                    stopAutoPlay()
                    startRush(rushName, towers)
                end,
            })
            rushPauseButton = RushBox:AddButton({
                Text = "Pause",
                DoubleClick = false,
                Tooltip = "Pauses or resumes the rush.",
                Func = pressPause,
            })
            rushPauseButton:AddButton({
                Text = "Stop",
                DoubleClick = false,
                Tooltip = "Stops the rush.",
                Func = stopAutoPlay,
            })

            updateRushInfo = function()
                local rushName = Options.RushDropdown.Value
                local towers = rushName and rushLists[rushName]
                if not towers then
                    rushInfo:SetText("Couldn't load this rush's tower list.")
                    return
                end
                local missing, seen = {}, {}
                for _, towerName in ipairs(towers) do
                    if not seen[towerName] then
                        seen[towerName] = true
                        if routeListLoaded and not routeNames[towerName] then
                            table.insert(missing, towerName)
                        end
                    end
                end
                local text = IS_ASTN and "The game picks the towers from this ring" or plural(#towers, "tower")
                if not routeListLoaded then
                    text = text .. ". Checking routes..."
                elseif #missing == 0 then
                    text = text .. ". Every tower has a route."
                else
                    text = text .. ". No route: " .. table.concat(missing, ", ")
                end
                local manualOption = Options["RushManual_" .. rushName]
                local mine = {}
                if manualOption and type(manualOption.Value) == "table" then
                    for _, towerName in ipairs(towers) do
                        if manualOption.Value[towerName] == true and not table.find(mine, towerName) then
                            table.insert(mine, towerName)
                        end
                    end
                end
                if #mine > 0 then
                    text = text .. "\nYou play: " .. table.concat(mine, ", ")
                end
                rushInfo:SetText(text)
                for inputRush, inputs in pairs(rushInputs) do
                    local manualValue = Options["RushManual_" .. inputRush] and Options["RushManual_" .. inputRush].Value
                    Options["RushManual_" .. inputRush]:SetVisible(inputRush == rushName)
                    rushBoxes[inputRush]:SetVisible(inputRush == rushName)
                    for towerName, input in pairs(inputs) do
                        input:SetText(formatTowerName(towerName))
                        input:SetVisible(not (type(manualValue) == "table" and manualValue[towerName] == true) and not (routeListLoaded and not routeNames[towerName]))
                    end
                end
            end
            Options.RushDropdown:OnChanged(updateRushInfo)
            updateRushInfo()
        end
    end
end

local JumpBox = Tabs.Main:AddRightGroupbox("All Jump Mode")

do
    local checkpoints = {}
    local folder

    local function saveCheckpoint()
        local character = getCharacter()
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
        if not root or not humanoid then
            return
        end
        local marker = Instance.new("Part")
        marker.Anchored = true
        marker.CanCollide = false
        marker.Color = Color3.new(1, 1, 1)
        marker.Transparency = -(Options.CheckpointOpacity and Options.CheckpointOpacity.Value or 20) / 100 + 1
        marker.Material = Enum.Material.Neon
        marker.Size = Vector3.new(2, 2, 1)
        marker.CFrame = root.CFrame
        marker.Parent = folder
        table.insert(checkpoints, {
            part = marker,
            cameraCFrame = workspace.CurrentCamera.CFrame,
            state = humanoid:GetState(),
            rootCFrame = root.CFrame,
        })
    end

    local function deleteCheckpoint()
        local last = table.remove(checkpoints)
        if last and last.part then
            last.part:Destroy()
        end
    end

    local function teleportToCheckpoint()
        local last = checkpoints[#checkpoints]
        local character = getCharacter()
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
        if not last or not root or not humanoid then
            return
        end
        root.Anchored = true
        humanoid.AutoRotate = false
        root.CFrame = last.rootCFrame
        workspace.CurrentCamera.CFrame = last.cameraCFrame
        if last.state == Enum.HumanoidStateType.Freefall then
            root.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
        else
            root.AssemblyLinearVelocity = Vector3.zero
        end
        task.wait(0.1)
        humanoid:ChangeState(last.state)
        root.Anchored = false
        humanoid.AutoRotate = true
    end

    local function keyMatches(input, optionName)
        local picker = Options[optionName]
        return picker and picker.Value and input.KeyCode.Name == picker.Value
    end

    JumpBox:AddToggle("AllJumpMode", {
        Text = "All Jump Mode",
        Tooltip = "Saves checkpoints anywhere and teleports you back with the keys below.",
        Default = false,
        Callback = function(enabled)
            local toggle = Toggles.AllJumpMode
            if enabled then
                if toggle.Connection then
                    return
                end
                folder = Instance.new("Folder")
                folder.Name = "CPs"
                folder.Parent = workspace
                toggle.Connection = UserInputService.InputBegan:Connect(function(input)
                    if UserInputService:GetFocusedTextBox() then
                        return
                    end
                    if keyMatches(input, "SaveKey") then
                        saveCheckpoint()
                    elseif keyMatches(input, "DeleteKey") then
                        deleteCheckpoint()
                    elseif keyMatches(input, "TeleportKey") then
                        task.spawn(teleportToCheckpoint)
                    end
                end)
            else
                if toggle.Connection then
                    toggle.Connection:Disconnect()
                    toggle.Connection = nil
                end
                for _, checkpoint in ipairs(checkpoints) do
                    if checkpoint.part then
                        pcall(checkpoint.part.Destroy, checkpoint.part)
                    end
                end
                checkpoints = {}
                if folder then
                    pcall(folder.Destroy, folder)
                    folder = nil
                end
            end
        end,
    })

    JumpBox:AddSlider("CheckpointOpacity", {
        Text = "Checkpoint Opacity",
        Default = 20,
        Min = 0,
        Max = 100,
        Rounding = 0,
        Compact = false,
        Tooltip = "How visible the checkpoint markers are. 0 makes them invisible.",
        Callback = function(value)
            for _, checkpoint in ipairs(checkpoints) do
                if checkpoint.part then
                    checkpoint.part.Transparency = -value / 100 + 1
                end
            end
        end,
    })

    JumpBox:AddDivider()

    JumpBox:AddLabel("Save Key"):AddKeyPicker("SaveKey", {
        Default = "E",
        Text = "Save Checkpoint",
        Mode = "Press",
        SyncToggleState = false,
        NoUI = false,
    })
    JumpBox:AddLabel("Delete Key"):AddKeyPicker("DeleteKey", {
        Default = "V",
        Text = "Delete Checkpoint",
        Mode = "Press",
        SyncToggleState = false,
        NoUI = false,
    })
    JumpBox:AddLabel("Teleport Key"):AddKeyPicker("TeleportKey", {
        Default = "R",
        Text = "Teleport to Checkpoint",
        Mode = "Press",
        SyncToggleState = false,
        NoUI = false,
    })
end

Library:OnUnload(function()
    Library.Unloaded = true
end)

local MiscBox = Tabs.Main:AddRightGroupbox("Miscellaneous")
local EToHMiscBox = (IS_TEA or IS_CSCD or IS_TOR or IS_ASTN) and NullBox or MiscBox

MiscBox:AddButton({
    Text = "Panic",
    DoubleClick = false,
    Tooltip = "Turns off everything others could notice. Visuals like ESP stay on.",
    Func = function()
        runPanic()
        notify("Panic", "Everything others could notice is off.", 3)
    end,
})

MiscBox:AddLabel("Panic Key"):AddKeyPicker("PanicKey", {
    Text = "Panic",
    Mode = "Press",
    SyncToggleState = false,
    NoUI = false,
})

do
    local panicConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed or Library.Unloaded then
            return
        end
        local key = Options.PanicKey and Options.PanicKey.Value
        if key and key ~= "None" and input.KeyCode.Name == key then
            runPanic()
            notify("Panic", "Everything others could notice is off.", 3)
        end
    end)
    Library:OnUnload(function()
        panicConnection:Disconnect()
    end)
end

EToHMiscBox:AddDivider()

do
    local STAFF_GROUP = 4777338
    local STAFF_MIN_RANK = 108

    local function checkStaff(player)
        if player == LocalPlayer then
            return
        end
        local ok, rank = pcall(function()
            return player:GetRankInGroup(STAFF_GROUP)
        end)
        if not ok or not rank or rank <= STAFF_MIN_RANK then
            return
        end
        local selected = Options.StaffAction.Value
        if type(selected) ~= "table" then
            selected = { [selected or "Warn"] = true }
        end
        if selected.Panic then
            runPanic()
        end
        if selected.Warn then
            local suffix = selected.Panic and " joined, panic activated." or " has joined the server!"
            notify("\226\154\160\239\184\143 Staff Detector", player.Name .. suffix, 5)
        end
        if selected.Kick or selected["Leave Game"] then
            LocalPlayer:Kick("\226\154\160\239\184\143 Staff Detector: " .. player.Name .. " is a staff member, you have been kicked")
        end
    end

    EToHMiscBox:AddToggle("StaffDetector", {
        Text = "Staff Detector",
        Default = false,
        Tooltip = "Warns you when a staff member joins.",
        Callback = function(enabled)
            local toggle = Toggles.StaffDetector
            if toggle.Connection then
                toggle.Connection:Disconnect()
                toggle.Connection = nil
            end
            if enabled and game.GameId ~= TEA_GAME_ID then
                for _, player in pairs(Players:GetPlayers()) do
                    task.spawn(checkStaff, player)
                end
                toggle.Connection = Players.PlayerAdded:Connect(checkStaff)
            end
        end,
    })
end

EToHMiscBox:AddDropdown("StaffAction", {
    Text = "Staff Action",
    Values = { "Warn", "Kick", "Panic" },
    Default = { "Warn" },
    Multi = true,
    Tooltip = "Warn shows a popup, Kick leaves the game, Panic turns off everything others could notice.",
})

MiscBox:AddDivider()

MiscBox:AddToggle("JoinNotification", {
    Text = "Join Notification",
    Default = false,
    Tooltip = "Tells you when someone joins the server.",
    Callback = function(enabled)
        local toggle = Toggles.JoinNotification
        if toggle.Connection then
            toggle.Connection:Disconnect()
            toggle.Connection = nil
        end
        if enabled then
            toggle.Connection = Players.PlayerAdded:Connect(function(player)
                if player ~= LocalPlayer then
                    notify("Join Notification", player.Name .. " has joined the server!")
                end
            end)
        end
    end,
})

do
    local idledConnection
    local disabledConnections = {}

    MiscBox:AddToggle("AntiAFK", {
        Text = "Anti AFK",
        Default = false,
        Tooltip = "Stops Roblox from kicking you for being idle.",
        Callback = function(enabled)
            if not enabled then
                if idledConnection then
                    idledConnection:Disconnect()
                    idledConnection = nil
                end
                for _, connection in ipairs(disabledConnections) do
                    pcall(function()
                        connection:Enable()
                    end)
                end
                table.clear(disabledConnections)
                return
            end

            local getConnections = getconnections or get_signal_cons
            if getConnections then
                for _, connection in pairs(getConnections(LocalPlayer.Idled)) do
                    if connection.Disable and connection.Enable then
                        connection:Disable()
                        table.insert(disabledConnections, connection)
                    elseif connection.Disconnect then
                        connection:Disconnect()
                    end
                end
            elseif not idledConnection then
                local VirtualUser = cloneref and cloneref(game:GetService("VirtualUser")) or game:GetService("VirtualUser")
                idledConnection = LocalPlayer.Idled:Connect(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new())
                end)
            end
        end,
    })
end

MiscBox:AddDivider()

local function rejoinServer()
    local events = (IS_TOR or IS_TEA) and ReplicatedStorage:FindFirstChild(IS_TOR and "Events" or "Remotes")
    local remote = events and events:FindFirstChild(IS_TOR and "RejoinServer" or "Teleport")
    if remote then
        remote:FireServer()
    elseif #Players:GetPlayers() <= 1 then
        task.wait()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    else
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end
end

MiscBox:AddButton({
    Text = "Rejoin",
    DoubleClick = false,
    Tooltip = "Rejoins this server.",
    Func = rejoinServer,
}):AddButton({
    Text = "Server Hop",
    DoubleClick = false,
    Tooltip = "Joins a different server of this area.",
    Func = function()
        local httpRequest = (syn and syn.request) or (http and http.request) or http_request
            or (fluxus and fluxus.request) or request
        if not httpRequest then
            notify("Server Hop", "Your executor doesn't support server hop.")
            return
        end
        local response = httpRequest({
            Url = string.format(
                "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true",
                game.PlaceId
            ),
        })
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(response.Body)
        end)
        local servers = {}
        if ok and decoded and decoded.data then
            for _, server in pairs(decoded.data) do
                if server.id ~= game.JobId and (server.playing or 0) < (server.maxPlayers or 0) then
                    table.insert(servers, server.id)
                end
            end
        end
        if #servers > 0 then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[math.random(1, #servers)], LocalPlayer)
        else
            notify("Server Hop", "Couldn't find a server. Try again.")
        end
    end,
})

do
    local TextChatService = game:GetService("TextChatService")
    local commands = {}
    local connections = {}
    local textures = { parts = {}, off = false, scan = 0, watch = nil }

    local function stripTexture(part)
        local character = LocalPlayer.Character
        if part:IsA("BasePart") and textures.parts[part] == nil and not (character and part:IsDescendantOf(character)) then
            textures.parts[part] = part.Material
            part.Material = Enum.Material.SmoothPlastic
        end
    end

    local function enableTextures()
        textures.off = false
        textures.scan = textures.scan + (1)
        if textures.watch then
            textures.watch:Disconnect()
            textures.watch = nil
        end
        for part, material in pairs(textures.parts) do
            if part.Parent then
                part.Material = material
            end
        end
        table.clear(textures.parts)
    end

    local function disableTextures()
        if textures.off then
            return
        end
        textures.off = true
        textures.scan = textures.scan + (1)
        local myScan = textures.scan
        textures.watch = workspace.DescendantAdded:Connect(function(part)
            task.defer(function()
                if textures.off and part.Parent then
                    stripTexture(part)
                end
            end)
        end)
        task.spawn(forEachSlowly, workspace:GetDescendants(), stripTexture, function()
            return textures.off and textures.scan == myScan
        end)
    end

    local function cscdStats()
        local stats = LocalPlayer:FindFirstChild("Stats")
        local inTower = stats and stats:FindFirstChild("InTower")
        if not inTower or inTower.Value == "" then
            notify("Aery Hub", "You must be in a tower to use this.")
            return nil
        end
        return stats, ReplicatedStorage.All_Areas.GlobalEvents
    end

    local function torMode(mode)
        if not LocalPlayer:GetAttribute("CurrentObby") then
            notify("Aery Hub", "You must be in an obby to use this.")
            return
        end
        ReplicatedStorage.Events.UpdateObbyMode:FireServer(LocalPlayer:GetAttribute("PlayingMode") == mode and "Legit" or mode)
    end

    local handlers = {}

    local function addCommand(alias, run)
        handlers[alias] = run
    end

    addCommand("/rejoin", function()
        rejoinServer()
    end)

    addCommand("/disable", function(argument)
        if argument:lower() == "textures" then
            disableTextures()
        end
    end)

    addCommand("/enable", function(argument)
        if argument:lower() == "textures" then
            enableTextures()
        end
    end)

    addCommand("/enter", function(argument)
        if argument == "" then
            notify("/enter", "Usage: /enter <" .. (IS_TOR and "obby" or "tower") .. " name> [portal]")
        elseif ChatCommands.enter then
            ChatCommands.enter(argument)
        end
    end)

    addCommand("/complete", function(argument)
        if ChatCommands.complete then
            ChatCommands.complete(argument)
        end
    end)

    addCommand("/stop", function()
        if ChatCommands.stop then
            ChatCommands.stop()
        end
    end)

    do
        addCommand("/exit", function()
            if ChatCommands.stop then
                ChatCommands.stop()
            end
            if IS_TOR then
                if LocalPlayer:GetAttribute("CurrentObby") then
                    ReplicatedStorage.Events.RequestUnloadObby:FireServer()
                end
            elseif IS_TEA then
                local character = LocalPlayer.Character
                if currentKitTower() or (LocalPlayer.Team and LocalPlayer.Team.Name == "Winner") then
                    ReplicatedStorage.Remotes.ExitTower:FireServer()
                elseif character and workspace:FindFirstChild("StartSpawn") then
                    character:PivotTo(workspace.StartSpawn.CFrame + Vector3.new(0, 5, 0))
                end
            elseif IS_CSCD then
                local stats, events = cscdStats()
                if stats then
                    events.ExitTower:FireServer(stats.InAllJump.Value)
                end
            elseif IS_ASTN then
                if currentKitTower() then
                    ReplicatedStorage.TowerGame.MenuExitTower:FireServer()
                end
            else
                local humanoid = getHumanoid()
                if not currentKitTower() or not humanoid or humanoid.Health <= 0 then
                    notify("/exit", "You must be in a tower to use this.")
                    return
                end
                kitController.DiedFromReset = true
                humanoid.Health = -1
            end
        end)
    end

    if IS_TOR or IS_CSCD or IS_TEA or IS_ASTN then
        addCommand("/practice", function()
            if IS_TOR then
                torMode("Practice")
                return
            end
            if IS_ASTN then
                ReplicatedStorage.TowerGame.PracticeHandler:FireServer("Practice")
                return
            end
            if IS_TEA then
                ReplicatedStorage.Remotes.PracticeEvent:FireServer(false)
                return
            end
            local stats, events = cscdStats()
            if not stats then
                return
            end
            if stats.InPractice.Value then
                events.Restart:FireServer(stats.InAllJump.Value)
                return
            end
            local tower = stats.InTower.Value
            local difficulty = towerDifficultyName(tower)
            if not difficulty then
                notify("/practice", "Couldn't find the difficulty of " .. tower .. ".")
                return
            end
            events.EnterPractice:FireServer(tower, difficulty)
        end)

        addCommand("/aj", function()
            if IS_TOR then
                torMode("AllJump")
                return
            end
            if IS_ASTN then
                notify("/aj", "/aj doesn't work in ASTN.")
                return
            end
            if IS_TEA then
                ReplicatedStorage.Remotes.PracticeEvent:FireServer(true)
                return
            end
            local stats = LocalPlayer:WaitForChild("Stats")
            local events = ReplicatedStorage.All_Areas.GlobalEvents
            local enabled = stats.InAllJump.Value
            if enabled and stats.InPractice.Value then
                notify("/aj", "Leave practice mode first.")
                return
            end
            local _, result = events.ChangeSettings:InvokeServer("Alljumps", { not enabled })
            if type(result) == "table" and not result[1] then
                pcall(function()
                    events.RequestTimeClient:Invoke(true)
                end)
                task.wait(0.25)
                events.Restart:FireServer()
            end
        end)
    else
        for _, alias in ipairs({ "/practice", "/aj" }) do
            addCommand(alias, function()
                notify(alias, alias .. " doesn't work in EToH.")
            end)
        end
    end

    local runner = Instance.new("BindableEvent")
    table.insert(connections, runner.Event:Connect(function(alias, argument)
        local ok, problem = pcall(handlers[alias], argument)
        if not ok then
            notify(alias, tostring(problem), 5)
        end
    end))

    local function runChatCommand(text)
        local alias, argument = text:match("^%s*(%S+)%s*(.-)%s*$")
        alias = alias and alias:lower()
        if alias and handlers[alias] then
            runner:Fire(alias, argument)
            return true
        end
        return false
    end

    local chatHook = getgenv().AeryHubChatHook
    if type(chatHook) ~= "table" then
        chatHook = { run = nil, hooked = false }
        getgenv().AeryHubChatHook = chatHook
    end
    if not chatHook.hooked and hookmetamethod and getnamecallmethod and checkcaller then
        chatHook.hooked = pcall(function()
            local originalNamecall
            originalNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                if chatHook.run and not checkcaller() and getnamecallmethod() == "SendAsync" and typeof(self) == "Instance" and self.ClassName == "TextChannel" then
                    local text = ...
                    if type(text) == "string" and chatHook.run(text) then
                        return nil
                    end
                end
                return originalNamecall(self, ...)
            end))
        end)
    end
    chatHook.run = runChatCommand

    for alias in pairs(handlers) do
        local command = Instance.new("TextChatCommand")
        command.Name = "Aery" .. alias:sub(2)
        command.PrimaryAlias = alias
        command.AutocompleteVisible = false
        command.Parent = TextChatService
        table.insert(commands, command)
        table.insert(connections, command.Triggered:Connect(function(source, text)
            if source.UserId == LocalPlayer.UserId then
                runChatCommand(text)
            end
        end))
    end

    local hookedBoxes = {}
    local function hookChatBox(box)
        if not box:IsA("TextBox") or hookedBoxes[box] then
            return
        end
        hookedBoxes[box] = true
        table.insert(connections, box.FocusLost:Connect(function(enterPressed)
            if enterPressed and runChatCommand(box.Text) then
                box.Text = ""
            end
        end))
    end
    pcall(function()
        local chat = game:GetService("CoreGui"):FindFirstChild("ExperienceChat")
        if chat then
            for _, child in ipairs(chat:GetDescendants()) do
                hookChatBox(child)
            end
            table.insert(connections, chat.DescendantAdded:Connect(hookChatBox))
        end
    end)

    Library:OnUnload(function()
        if chatHook.run == runChatCommand then
            chatHook.run = nil
        end
        disconnectAll(connections)
        runner:Destroy()
        for _, command in ipairs(commands) do
            command:Destroy()
        end
        table.clear(commands)
        enableTextures()
    end)
end

local ToolsBox = (IS_TEA or IS_TOR) and NullBox or Tabs.Exploits:AddLeftGroupbox("Tools")

local createdTools = {}

Library:OnUnload(function()
    local humanoid = getHumanoid()
    if humanoid then
        pcall(function()
            humanoid:UnequipTools()
        end)
    end
    for _, tool in ipairs(createdTools) do
        pcall(function()
            tool:Destroy()
        end)
    end
    table.clear(createdTools)
end)

local fakeItems = {}

local function rebuildHotbar()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local hotbar = playerGui and playerGui:FindFirstChild("Backpack")
    if hotbar then
        hotbar.Parent = nil
        task.wait(0.1)
        hotbar.Parent = playerGui
    end
end

local function getItemData()
    local Framework = ReplicatedStorage.Framework
    local data = require(Framework.Scripts.Client.Controller.DataController):Wait().Data
    local itemMap = require(Framework.Scripts.Shared.SharedVariables):GetVariable("ItemMap", true)
    return data, itemMap
end

local function addFakeItem(name)
    if game.GameId ~= ETOH_GAME_ID then
        return false
    end
    local ok, added = pcall(function()
        local data, itemMap = getItemData()
        local items = data.items
        if fakeItems[name] then
            return true
        end
        local owned = items[name]
        if type(owned) ~= "table" and (type(itemMap) ~= "table" or not itemMap[name]) then
            return false
        end
        local used, maxOrder, sample = {}, 0, nil
        for itemName, entry in pairs(items) do
            if type(entry) == "table" and itemName ~= name then
                if type(entry.order) == "number" then
                    used[entry.order] = true
                    maxOrder = math.max(maxOrder, entry.order)
                end
                if not sample and not entry.upgrade then
                    sample = entry
                end
            end
        end
        local slot
        for i = 1, 10 do
            if not used[i] then
                slot = i
                break
            end
        end
        if type(owned) == "table" then
            local onHotbar = type(owned.order) == "number" and owned.order >= 1 and owned.order <= 10
            if not onHotbar or owned.enabled == false then
                fakeItems[name] = { order = owned.order, enabled = owned.enabled }
                if not onHotbar and slot then
                    owned.order = slot
                end
                owned.enabled = true
            end
            return true
        end
        local entry = {}
        for key, value in pairs(sample or {}) do
            entry[key] = value
        end
        entry.order = slot or (maxOrder + 1)
        entry.enabled = true
        entry.upgrade = nil
        items[name] = entry
        fakeItems[name] = true
        return true
    end)
    return ok and added
end

Library:OnUnload(function()
    if next(fakeItems) == nil then
        return
    end
    pcall(function()
        local data = getItemData()
        for name, original in pairs(fakeItems) do
            local entry = data.items[name]
            if type(original) == "table" then
                if type(entry) == "table" then
                    entry.order = original.order
                    entry.enabled = original.enabled
                end
            else
                data.items[name] = nil
            end
        end
    end)
    table.clear(fakeItems)
    task.spawn(rebuildHotbar)
end)

local toolGivers = {}
local givenTools = {}

local function addToolButton(info)
    local forCSCD = info.CSCD == true
    info.CSCD = nil
    if forCSCD ~= IS_CSCD then
        return
    end
    local give = info.Func
    toolGivers[info.Text] = give
    info.Func = function()
        givenTools[info.Text] = true
        give()
    end
    return ToolsBox:AddButton(info)
end

do
    local respawnConnection = LocalPlayer.CharacterAdded:Connect(function()
        if next(givenTools) == nil then
            return
        end
        local backpack = LocalPlayer:WaitForChild("Backpack", 10)
        if not backpack then
            return
        end
        task.wait(0.5)
        for name in pairs(givenTools) do
            local character = LocalPlayer.Character
            if not backpack:FindFirstChild(name) and not (character and character:FindFirstChild(name)) and toolGivers[name] then
                task.spawn(toolGivers[name])
            end
        end
    end)
    Library:OnUnload(function()
        respawnConnection:Disconnect()
        table.clear(givenTools)
    end)
end

local function newTool(name, tooltip, textureId)
    local tool = Instance.new("Tool")
    table.insert(createdTools, tool)
    tool.Name = name
    tool.ToolTip = tooltip or ""
    if textureId then
        tool.TextureId = textureId
    end
    tool.CanBeDropped = false
    tool.RequiresHandle = false
    tool.ManualActivationOnly = true
    local inHotbar = addFakeItem(name)
    if inHotbar then
        pcall(function()
            game:GetService("CollectionService"):AddTag(tool, "GameItem")
        end)
    end
    tool.Parent = LocalPlayer:FindFirstChildOfClass("Backpack")
    if inHotbar then
        task.spawn(rebuildHotbar)
    end
    return tool
end

local function toolConnect(tool, signal, callback)
    if not tool.Parent then
        return
    end
    local connection = signal:Connect(callback)
    tool.Destroying:Connect(function()
        connection:Disconnect()
    end)
end

local function waitForHumanoid()
    local humanoid
    repeat
        humanoid = getHumanoid()
        if not humanoid then
            task.wait()
        end
    until humanoid
    return humanoid
end

addToolButton({
    Text = "T-Pose",
    DoubleClick = false,
    Tooltip = "Gives you a T-Pose tool. Hold click to T-pose.",
    Func = function()
        local tool = newTool("T-Pose", IS_ASTN and "ascert ur dominance lol" or "Assert dominance", "http://www.roblox.com/asset/?id=6869582429")
        task.spawn(function()
            local mouse = LocalPlayer:GetMouse()
            local animation = Instance.new("Animation")
            animation.AnimationId = IS_ASTN and "rbxassetid://17152993440" or "rbxassetid://9105892431"
            local track = waitForHumanoid():LoadAnimation(animation)
            local holding = false
            toolConnect(tool, mouse.Button1Down, function()
                if tool.Parent ~= getCharacter() then
                    return
                end
                holding = true
                while holding and tool.Parent == getCharacter() do
                    if not track.IsPlaying then
                        track:Play()
                    end
                    task.wait()
                end
                track:Stop()
            end)
            toolConnect(tool, mouse.Button1Up, function()
                holding = false
            end)
        end)
    end,
})
local function giveHelicopter(name, tooltip, textureId, animationId, arms)
    local tool = newTool(name, tooltip, textureId)
    task.spawn(function()
        local mouse = LocalPlayer:GetMouse()
        local humanoid = waitForHumanoid()
        local animation = Instance.new("Animation")
        animation.AnimationId = animationId
        local track = humanoid:LoadAnimation(animation)
        local holding = false
        local function setSpinning(state)
            local character = getCharacter()
            if not character then
                return
            end
            if state then
                if not track.IsPlaying then
                    track:Play()
                end
                if not arms and not character:FindFirstChild("InvisibleLegs") then
                    Instance.new("BoolValue", character).Name = "InvisibleLegs"
                end
            else
                track:Stop()
                if character:FindFirstChild("InvisibleLegs") then
                    character.InvisibleLegs:Destroy()
                end
            end
            for _, legName in ipairs(arms and { "Left Arm", "Right Arm" } or { "Left Leg", "Right Leg" }) do
                local leg = character:FindFirstChild(legName)
                if leg then
                    leg.Transparency = state and 1 or 0
                end
            end
        end
        local function isUpright(root)
            local o = root.Orientation
            local xOk = (o.X > -5 and o.X < 5) or o.X > 355
            local zOk = (o.Z > -5 and o.Z < 5) or o.Z > 355
            return xOk and zOk
        end
        toolConnect(tool, mouse.Button1Down, function()
            if tool.Parent ~= getCharacter() then
                return
            end
            holding = true
            while holding and tool.Parent == getCharacter() do
                local root = getRoot()
                local upright = root ~= nil and isUpright(root)
                if upright ~= track.IsPlaying then
                    setSpinning(upright)
                end
                task.wait()
            end
            setSpinning(false)
        end)
        toolConnect(tool, mouse.Button1Up, function()
            holding = false
        end)
    end)
end

addToolButton({
    Text = "Helicopter Powers",
    DoubleClick = false,
    Tooltip = "Gives you a Helicopter Powers tool. Hold click to spin.",
    Func = function()
        giveHelicopter("Helicopter Powers", "I can see my house from here!", "rbxassetid://6235245591", IS_ASTN and "rbxassetid://17153013013" or "rbxassetid://9105897084")
    end,
})

addToolButton({
    Text = "Plane Powers",
    CSCD = true,
    DoubleClick = false,
    Tooltip = "Gives you a Plane Powers tool. Hold click to spin.",
    Func = function()
        giveHelicopter("Plane Powers", "Fly above the danger!", "rbxassetid://10671808511", "rbxassetid://10688933895")
    end,
})

addToolButton({
    Text = "Vertical Mobility",
    DoubleClick = false,
    Tooltip = "Gives you a Vertical Mobility tool. Hold click to thrust vertically.",
    Func = function()
        if IS_ASTN then
            notify("Vertical Mobility", "Vertical Mobility can't be used in ASTN yet.")
            givenTools["Vertical Mobility"] = nil
            return
        end
        local tool = newTool("Vertical Mobility", "Cheater...", "rbxassetid://6300212134")
        tool.Grip = CFrame.new(1.5, 0, -2.29999995, 1, 0, 0, 0, 1, 0, 0, 0, 1)

        local gui = Instance.new("ScreenGui")
        gui.Name = "Button"
        gui.IgnoreGuiInset = false
        local flyButton = Instance.new("TextButton")
        flyButton.Name = "FlyButton"
        flyButton.AnchorPoint = Vector2.new(0.5, 0.5)
        flyButton.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
        flyButton.BorderColor3 = Color3.fromRGB(27, 42, 53)
        flyButton.BorderSizePixel = 0
        flyButton.Position = UDim2.new(0.1, 0, 0.85, 0)
        flyButton.Size = UDim2.new(0.1, 0, 0.1, 0)
        flyButton.Font = Enum.Font.GothamBlack
        flyButton.Text = "Fly"
        flyButton.TextColor3 = Color3.fromRGB(0, 0, 0)
        flyButton.TextScaled = true
        flyButton.TextSize = 14
        flyButton.TextWrapped = true
        flyButton.Parent = gui

        local sound = Instance.new("Sound")
        sound.Name = "Thrusting"
        sound.SoundId = "rbxassetid://391784935"
        sound.Looped = true
        sound.Volume = 0.3
        sound.RollOffMaxDistance = 10000
        sound.RollOffMinDistance = 10
        sound.RollOffMode = Enum.RollOffMode.Inverse

        local THRUST_SPEED = 100
        local force = Instance.new("BodyVelocity")
        force.Velocity = Vector3.zero
        local gyro = Instance.new("BodyGyro")
        gyro.P = 20000
        gyro.D = 8000
        gyro.MaxTorque = Vector3.new(20000, 20000, 20000)

        local standStill = Instance.new("Animation")
        standStill.AnimationId = "rbxassetid://9105888138"
        local standTrack
        local trackHumanoid
        local thrustConnection

        local function loadStandTrack()
            local humanoid = getHumanoid()
            if humanoid and trackHumanoid ~= humanoid then
                trackHumanoid = humanoid
                local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid
                local ok, track = pcall(animator.LoadAnimation, animator, standStill)
                standTrack = ok and track or nil
            end
        end

        local mobileGui
        local function cutEngine()
            if thrustConnection then
                thrustConnection:Disconnect()
                thrustConnection = nil
            end
            force.Velocity = Vector3.zero
            force.Parent = nil
            gyro.Parent = nil
            sound:Stop()
            if standTrack and standTrack.IsPlaying then
                standTrack:Stop()
            end
        end
        local function thrust()
            local character = getCharacter()
            local torso = character and (character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso"))
            local root = getRoot()
            if tool.Parent ~= character or not torso or not root then
                return
            end
            cutEngine()
            force.MaxForce = Vector3.new(0, root.AssemblyMass * workspace.Gravity * 10, 0)
            force.Parent = torso
            gyro.Parent = torso
            sound.Parent = torso
            sound:Play()
            loadStandTrack()
            if standTrack then
                standTrack:Play()
                standTrack:AdjustSpeed(2.5)
            end
            thrustConnection = RunService.Heartbeat:Connect(function()
                local camera = workspace.CurrentCamera
                if not camera or tool.Parent ~= getCharacter() then
                    cutEngine()
                    return
                end
                gyro.CFrame = camera.CFrame
                force.Velocity = Vector3.new(0, camera.CFrame.LookVector.Y * THRUST_SPEED, 0)
            end)
        end

        local mouse = LocalPlayer:GetMouse()
        toolConnect(tool, mouse.Button1Down, thrust)
        toolConnect(tool, mouse.Button1Up, cutEngine)

        tool.Equipped:Connect(function()
            if UserInputService.TouchEnabled then
                mobileGui = gui:Clone()
                mobileGui.Parent = LocalPlayer:FindFirstChild("PlayerGui")
                mobileGui.FlyButton.MouseButton1Down:Connect(thrust)
                mobileGui.FlyButton.MouseButton1Up:Connect(cutEngine)
            end
        end)
        tool.Unequipped:Connect(function()
            if mobileGui then
                mobileGui:Destroy()
                mobileGui = nil
            end
            cutEngine()
        end)
    end,
})


addToolButton({
    Text = "Noclip",
    DoubleClick = false,
    Tooltip = "Gives you a Noclip tool. Equip it to fly through walls.",
    Func = function()
        local tool = Instance.new("Tool")
        table.insert(createdTools, tool)
        tool.Name = "Noclip"
        tool.CanBeDropped = false
        tool.RequiresHandle = false
        tool.Parent = LocalPlayer:FindFirstChildOfClass("Backpack")

        local SPEED = 60
        local flying = false

        local function getNextMovement(deltaTime)
            local move = Vector3.new()
            if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
                move = move + (Vector3.new(-1, 0, 0))
            elseif UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
                move = move + (Vector3.new(1, 0, 0))
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
                move = move + (Vector3.new(0, 0, -1))
            elseif UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
                move = move + (Vector3.new(0, 0, 1))
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                move = move + (Vector3.new(0, 1, 0))
            elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                move = move + (Vector3.new(0, -1, 0))
            end
            return CFrame.new(move * (SPEED * deltaTime))
        end

        tool.Equipped:Connect(function()
            local character = getCharacter()
            if not character then
                return
            end
            local humanoid = character:WaitForChild("Humanoid")
            local root = character:WaitForChild("HumanoidRootPart")
            flying = true
            root.Anchored = true
            humanoid.PlatformStand = true
            local last = tick()
            while flying and tool.Parent == character do
                local now = tick()
                local camera = workspace.CurrentCamera
                local look = (camera.Focus.Position - camera.CFrame.Position).Unit
                local position = root.Position
                root.CFrame = CFrame.new(position, position + look) * getNextMovement(now - last)
                last = now
                RunService.RenderStepped:Wait()
            end
        end)

        tool.Unequipped:Connect(function()
            flying = false
            local character = getCharacter()
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
            if root then
                root.Anchored = false
            end
            if humanoid then
                humanoid.PlatformStand = false
            end
        end)
    end,
})

addToolButton({
    Text = "IPose",
    CSCD = true,
    DoubleClick = false,
    Tooltip = "Gives you an IPose tool. Hold click to I-pose.",
    Func = function()
        giveHelicopter("IPose", "I Pose? What's that? Me:", "rbxassetid://10671753537", "rbxassetid://10714741678", true)
    end,
})

local BypassBox = (IS_TEA or IS_CSCD or IS_TOR or IS_ASTN) and Tabs.Exploits:AddLeftGroupbox("Bypass") or Tabs.Exploits:AddRightGroupbox("Bypass")
local EToHBypassBox = (IS_TEA or IS_CSCD or IS_TOR or IS_ASTN) and NullBox or BypassBox

local DAMAGE_BRICK_TYPES = { kills = true, double = true, ouch = true, instakills = true, custom = true }

local LEGACY_DAMAGE_MARKERS = { "instakills", "ouch", "double", "kills" }
local NAMED_DAMAGE_BRICKS = { InstakillBrick = "instakills", KillBrick = "kills", DoubleBrick = "double", OuchBrick = "ouch" }

local function damageBrickType(part)
    if not part:IsA("BasePart") then
        return nil
    end
    if IS_TOR then
        local folder = part:FindFirstAncestor("Instakills")
        if folder and folder.Parent and folder.Parent.Name == "COParts" then
            return "instakills"
        end
        return part:FindFirstAncestor("ResetParts") and "instakills" or nil
    end
    if part.Name == "InstakillBrick" then
        return "instakills"
    end
    if part.Name == "KillBrick" then
        return "kills"
    end
    if IS_ASTN then
        if NAMED_DAMAGE_BRICKS[part.Name] then
            return NAMED_DAMAGE_BRICKS[part.Name]
        end
        local teleporter = part.Parent
        if part.Name == "Teleporter" and teleporter and teleporter:FindFirstChild("Destination") and part:FindFirstAncestor("ClientObjects") and part.Size.X >= 10 and part.Size.Z >= 10 then
            return "instakills"
        end
        for name, brickType in pairs(NAMED_DAMAGE_BRICKS) do
            if part:FindFirstChild(name) then
                return brickType
            end
        end
        return nil
    end
    local configuration = part:FindFirstChild("DamageBrickConfiguration")
    if configuration then
        local brickType = configuration:GetAttribute("Type")
        if brickType == "custom" then
            return (tonumber(configuration:GetAttribute("Damage")) or 0) > 0 and "custom" or nil
        end
        if DAMAGE_BRICK_TYPES[brickType] then
            return brickType
        end
    end
    for _, marker in ipairs(LEGACY_DAMAGE_MARKERS) do
        if part:FindFirstChild(marker) then
            return marker
        end
    end
    if part.Parent and part.Parent.Name == "KillBricks" then
        return "kills"
    end
    return nil
end

local function isDamageBrick(part)
    return damageBrickType(part) ~= nil
end

local function findDamageEvent()
    local damageEvent = ReplicatedStorage:FindFirstChild("DamageEvent")
    if not damageEvent then
        local framework = ReplicatedStorage:FindFirstChild("Framework")
        local remotes = framework and framework:FindFirstChild("Remotes")
        local towerRemotes = remotes and remotes:FindFirstChild("Towers")
        local objects = towerRemotes and towerRemotes:FindFirstChild("Objects")
        damageEvent = objects and objects:FindFirstChild("DamageEvent")
    end
    return damageEvent
end

do
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
        local damageEvent = IS_TOR and events and events:FindFirstChild("Instakill") or findDamageEvent()
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
        state.users.hub = true
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
        sharedGodmode().users.hub = nil
    end

    Library:OnUnload(disableGodmode)

    local untouchable = {}
    local brickConnection

    local function makeUntouchable(part)
        if untouchable[part] == nil and isDamageBrick(part) then
            untouchable[part] = part.CanTouch
            part.CanTouch = false
        end
    end

    local function enableTouchGodmode()
        local towers = workspace:FindFirstChild(IS_TOR and "Obbies" or "Towers")
        if not towers then
            return false
        end
        for _, part in ipairs(towers:GetDescendants()) do
            makeUntouchable(part)
        end
        brickConnection = towers.DescendantAdded:Connect(function(part)
            task.defer(function()
                if part.Parent then
                    makeUntouchable(part)
                end
            end)
        end)
        return true
    end

    local function disableTouchGodmode()
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

    Library:OnUnload(disableTouchGodmode)

    BypassBox:AddToggle("Godmode", {
        Text = "Godmode",
        Default = false,
        Tooltip = "Killbricks and turrets can't hurt you.",
        Callback = function(enabled)
            if game.GameId == TEA_GAME_ID then
                if enabled then
                    if not enableTouchGodmode() then
                        notify("Godmode", "Godmode isn't supported in this game.")
                        Toggles.Godmode:SetValue(false)
                    end
                else
                    disableTouchGodmode()
                end
                return
            end
            if enabled then
                if not enableGodmode() then
                    notify("Godmode", "Godmode isn't supported in this game.")
                    Toggles.Godmode:SetValue(false)
                elseif IS_TOR or IS_ASTN then
                    enableTouchGodmode()
                end
            else
                disableGodmode()
                disableTouchGodmode()
            end
        end,
    })
end


local function removeBarrier(keywords)
    local removed = 0
    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local name = descendant.Name:lower()
            if name:find("barrier") then
                for _, keyword in ipairs(keywords) do
                    if name:find(keyword) then
                        descendant:Destroy()
                        removed = removed + (1)
                        break
                    end
                end
            end
        end
    end
    return removed
end

EToHBypassBox:AddButton({
    Text = "Remove Bootleg Coil Barrier",
    DoubleClick = false,
    Tooltip = "Deletes the barriers that block the bootleg coil.",
    Func = function()
        notify("Bypass", "Removed " .. plural(removeBarrier({ "coil" }), "part") .. ".")
    end,
})

EToHBypassBox:AddButton({
    Text = "Remove VM Barrier",
    DoubleClick = false,
    Tooltip = "Deletes the barriers that block Vertical Mobility.",
    Func = function()
        notify("Bypass", "Removed " .. plural(removeBarrier({ "vm", "vertical", "mobility" }), "part") .. ".")
    end,
})

BypassBox:AddButton({
    Text = "Remove Killbricks",
    DoubleClick = false,
    Tooltip = "Deletes every killbrick that's loaded right now.",
    Func = function()
        local removed = 0
        for _, descendant in ipairs(workspace:GetDescendants()) do
            if descendant.Parent and isDamageBrick(descendant) then
                descendant:Destroy()
                removed = removed + (1)
            end
        end
        notify("Bypass", "Removed " .. plural(removed, "killbrick") .. ".")
    end,
})

local AvatarBox

if game.GameId == ETOH_GAME_ID or IS_ASTN or IS_CSCD or IS_TEA or IS_TOR then
    local AreaBox = Tabs.Exploits:AddRightGroupbox("Area Teleporter")

    local areas = IS_TOR and {
        ["Ashen Hollow"] = 140664680860222,
    } or IS_TEA and {
        ["The Eternal Abyss"] = 15873244701,
        ["Pit of Misery"] = 121814103864070,
        ["Timeless Manor"] = 131042387601353,
        ["Starry Night"] = 137721171983074,
    } or IS_CSCD and {
        ["Scope 1"] = 10284097192,
        ["The Nil Zone"] = 11336299336,
        ["Scope 2"] = 10284095469,
        ["Lush Colosseum"] = 110118540850785,
        ["Breaking Point"] = 108802919009038,
        ["Timekeeper Archive"] = 98973761521173,
        ["Haunted Valley (HE2022)"] = 11139578249,
        ["Fool's Nil Zone (AF2023)"] = 18986339218,
        ["Blackrock Ravine (CE2023)"] = 11534310219,
        ["Tropical Isles (SE2024)"] = 18907688613,
        ["One Over a Million (1M Visits)"] = 133967265657551,
        ["The Junt: Mega Edition (AF2025)"] = 81058558877489,
        ["Scope 0 (AF2026)"] = 111832585205629,
        ["Tower of Vague Luminescence: Classic"] = 125648358719301,
        ["Scope 3"] = 11504336574,
        ["Scope 3 (Lag Free)"] = 75067728300321,
    } or IS_ASTN and {
        ["Ring Select"] = 17120699596,
        ["Ring 1: Misery"] = 17120707813,
        ["Ring 2: Dread"] = 17120753412,
        ["Ring 3: Anguish"] = 109105112902803,
        ["Ring 4: Torment"] = 87827917737017,
        ["April Fools"] = 112049880480276,
        ["Archipelago"] = 128163013785935,
    } or {
        ["Ring 0: Purgatorio"] = 9070958509,
        ["Ring 1: Limbo"] = 9070657865,
        ["Ring 2: Desire"] = 9070979698,
        ["Ring 3: Gluttony"] = 9070980083,
        ["Ring 4: Greed"] = 9070980555,
        ["Ring 5: Wrath"] = 9070980846,
        ["Ring 6: Heresy"] = 9070981164,
        ["Ring 7: Violence"] = 9070981409,
        ["Ring 8: Fraud"] = 9070981722,
        ["Ring 9: Treachery"] = 9070982474,
        ["Zone 1: Sea"] = 9071001075,
        ["Zone 2: Surface"] = 9071001366,
        ["Zone 3: Sky"] = 9071001563,
        ["Zone 4: Exosphere"] = 9071001883,
        ["Zone 5: The Moon"] = 9071002104,
        ["Zone 6: Mars"] = 9071002463,
        ["Zone 7: Asteroid Belt"] = 9071002677,
        ["Zone 8: Pluto"] = 9071002915,
        ["Zone 9: Singularity"] = 9071004505,
        ["Zone 10: Interstellar Shore"] = 9071004898,
        ["Arcane Area"] = 9070944007,
        ["Ashen Towerworks"] = 14399266686,
        ["Dark Side of the Moon"] = 76003383649350,
        ["Forgotten Ridge"] = 9070954594,
        ["Garden of Eesh\195\182l"] = 9070960075,
        ["Lost River"] = 9945448769,
        ["Paradise Atoll"] = 9070975342,
        ["Silent Abyss"] = 11916533264,
        ["Steelspire Horizon"] = 18538513621,
        ["The Starlit Archives"] = 137445538655679,
        ["100M Replay"] = 115856553162061,
        ["Abyssal Badlands"] = 9070940724,
        ["BIOUMS"] = 111393548264972,
        ["Beggmuda Triangle"] = 9070946020,
        ["Borealis Reach"] = 93695130452528,
        ["Eclipsed Headquarters"] = 11402141810,
        ["Elysian Fields"] = 95241871632790,
        ["Event Realm"] = 82312199603536,
        ["Festive Cliffside"] = 9070951600,
        ["Fool's Ring 9"] = 9070952780,
        ["Forsaken Manor"] = 9070957584,
        ["Glacial Outpost"] = 95630397821208,
        ["Halloween Event 2026"] = 18892014130,
        ["Harvest Carnival"] = 14399267725,
        ["Heccfire Depths"] = 9070963935,
        ["Legacy Fortress"] = 116826560849733,
        ["Old Frosted Kingdom"] = 9070972538,
        ["Pit of Misery"] = 15639952229,
        ["Saint Venoma"] = 80158334909597,
        ["Snowmetropolis"] = 14399270175,
        ["Snowy Cabin"] = 9070982934,
        ["Something Otherworldly..."] = 12966817992,
        ["Summit of Memories"] = 90713610472463,
        ["T H I R S T Z O N E"] = 9070983600,
        ["Terrain World"] = 9247591798,
        ["The Doghouse"] = 16976865869,
        ["The Eternal Potluck"] = 9070971186,
        ["Time-Lost Clockwork"] = 13671413767,
        ["Time-Lost Nexus"] = 88764361702760,
        ["Time-Lost Plain"] = 9070997222,
        ["Time-Lost Sands"] = 102253882954075,
        ["Time-Lost Tempest"] = 127134690806439,
        ["Windswept Peak"] = 112597732892199,
        ["test place"] = 14631353950,
    }

    local areaList = {}
    for name in pairs(areas) do
        table.insert(areaList, name)
    end
    table.sort(areaList)

    AreaBox:AddDropdown("SelectArea", {
        Text = "Select Area",
        Tooltip = "Selects the area the buttons below take you to.",
        Values = areaList,
        Multi = false,
        Searchable = true,
        Disabled = false,
        Visible = true,
    })

    AreaBox:AddButton({
        Text = "Join Area",
        DoubleClick = false,
        Tooltip = "Joins a public server of the selected area.",
        Func = function()
            local placeId = areas[Options.SelectArea.Value]
            if not placeId then
                notify("Area Teleporter", "Select an area first.")
                return
            end
            pcall(function()
                if IS_TEA then
                    ReplicatedStorage.Remotes.Teleport:FireServer(placeId)
                else
                    TeleportService:Teleport(placeId, LocalPlayer)
                end
            end)
        end,
    })

    local personalRequest

    local function requestPersonal(...)
        if not personalRequest then
            local framework = require(ReplicatedStorage.Framework)
            personalRequest = framework.Network:Connect(framework.Library.Remotes.PersonalServerRequest)
        end
        return personalRequest:RequestServer(...)
    end

    AreaBox:AddButton({
        Text = "Join Personal Server",
        DoubleClick = false,
        Tooltip = IS_TOR and "Makes your own personal server in the area you're in and joins it. Needs the Private Server gamepass." or IS_CSCD and "Makes your own private server in the area you're in and joins it. Needs 1500 Legit Points, 10,000 All Jump Points or the Private Servers gamepass." or IS_ASTN and "Makes your own personal server in the area you're in and joins it. Needs the Personal Server gamepass." or "Makes your own personal server in the selected area and joins it. Needs the Personal Server gamepass.",
        Func = function()
            if IS_TOR then
                if workspace:GetAttribute("PersonalServer") == true then
                    notify("Personal Server", "You're already in a personal server.", 5)
                    return
                end
                task.spawn(function()
                    local okPass, owns = pcall(function()
                        return ReplicatedStorage.Events.GamepassEvents.HasGamepass:InvokeServer(2006943864)
                    end)
                    if okPass and owns ~= true then
                        notify("Personal Server", "You need the Private Server gamepass.", 5)
                        return
                    end
                    notify("Personal Server", "Joining your personal server...", 3)
                    pcall(function()
                        ReplicatedStorage.Events.PersonalRemote:FireServer("Create", "All")
                    end)
                end)
                return
            end
            if IS_TEA then
                local placeId = areas[Options.SelectArea.Value]
                if not placeId then
                    notify("Personal Server", "Select an area first.")
                    return
                end
                if not LocalPlayer:GetAttribute("HasPersonal") then
                    notify("Personal Server", "You need the Personal Server gamepass.", 5)
                    return
                end
                if workspace:GetAttribute("PersonalServer") == LocalPlayer.UserId and game.PlaceId == placeId then
                    notify("Personal Server", "You're already in your personal server here.", 5)
                    return
                end
                notify("Personal Server", "Joining your personal server...", 3)
                pcall(function()
                    ReplicatedStorage.Remotes.PersonalRemote:FireServer("JoinOwn", placeId, "")
                end)
                return
            end
            if IS_CSCD then
                if game.PrivateServerId ~= "" then
                    notify("Personal Server", "You're already in a private server.", 5)
                    return
                end
                task.spawn(function()
                    local stats = LocalPlayer:FindFirstChild("leaderstats")
                    local legit = stats and stats:FindFirstChild("Legit Points")
                    local allJump = stats and stats:FindFirstChild("All Jump Points")
                    local legitPoints = legit and tonumber(tostring(legit.Value))
                    local allJumpPoints = allJump and tonumber(tostring(allJump.Value))
                    local okMarket, owns = pcall(function()
                        return game:GetService("MarketplaceService"):UserOwnsGamePassAsync(LocalPlayer.UserId, 838350747)
                    end)
                    local eligible = (okMarket and owns == true) or (legitPoints and legitPoints >= 1500) or (allJumpPoints and allJumpPoints >= 10000)
                    if not eligible and okMarket and legitPoints and allJumpPoints then
                        notify("Personal Server", ("You need 1500 Legit Points (%d), 10,000 All Jump Points (%d) or the Private Servers gamepass."):format(legitPoints, allJumpPoints), 8)
                        return
                    end
                    local okCreate, result = pcall(function()
                        return ReplicatedStorage.All_Areas.GlobalEvents.CreateReservedServer:InvokeServer()
                    end)
                    if not okCreate then
                        notify("Personal Server", "Couldn't make a server: " .. tostring(result), 8)
                    elseif type(result) == "table" and not result.success then
                        notify("Personal Server", tostring(result.message or "The server refused."), 8)
                    else
                        notify("Personal Server", "Joining your personal server...", 5)
                    end
                end)
                return
            end
            if IS_ASTN then
                task.spawn(function()
                    local okMarket, owns = pcall(function()
                        return game:GetService("MarketplaceService"):UserOwnsGamePassAsync(LocalPlayer.UserId, 821488023)
                    end)
                    if okMarket and owns ~= true then
                        notify("Personal Server", "You need the Personal Server gamepass.", 5)
                        return
                    end
                    if workspace:GetAttribute("PersonalServer") ~= nil then
                        notify("Personal Server", "You're already in a personal server.", 5)
                        return
                    end
                    local server = ReplicatedStorage:FindFirstChild("ServerFunction")
                    local okCreate, code = pcall(function()
                        return server:InvokeServer("Create")
                    end)
                    notify("Personal Server", okCreate and tostring(code) or ("Couldn't make a server: " .. tostring(code)), 8)
                end)
                return
            end
            local placeId = areas[Options.SelectArea.Value]
            if not placeId then
                notify("Personal Server", "Select an area first.")
                return
            end
            task.spawn(function()
                local okMarket, ownsMarket = pcall(function()
                    return game:GetService("MarketplaceService"):UserOwnsGamePassAsync(LocalPlayer.UserId, 264906765)
                end)
                local okServer, ownsServer = pcall(requestPersonal, "owns-gamepass")
                local owns = (okMarket and ownsMarket == true) or (okServer and ownsServer == true)
                if not owns then
                    notify("Personal Server", ("You need the Personal Server gamepass. (Roblox: %s, EToH: %s)"):format(
                        okMarket and tostring(ownsMarket) or "error",
                        okServer and tostring(ownsServer) or "error"
                    ), 8)
                    return
                end
                notify("Personal Server", "Joining your personal server...", 3)
                local okJoin, joined = pcall(requestPersonal, "join-personal", placeId)
                if not okJoin then
                    notify("Personal Server", "Couldn't join: " .. tostring(joined), 8)
                elseif not joined then
                    notify("Personal Server", "The server refused. Try again.", 5)
                end
            end)
        end,
    })
end

local function userFromId(text)
    if type(text) ~= "string" or not text:match("^%d+$") then
        return nil
    end
    local ok, infos = pcall(function()
        return game:GetService("UserService"):GetUserInfosByUserIdsAsync({ tonumber(text) or 0 })
    end)
    return ok and type(infos) == "table" and infos[1] or nil
end

AvatarBox = Tabs.Exploits:AddRightGroupbox("Avatar")

AvatarBox:AddInput("AvatarInput", {
    Text = "Username or ID",
    Tooltip = "Sets the player whose avatar Change Avatar puts on you.",
    Default = "",
    Numeric = false,
    Finished = false,
    ClearTextOnFocus = false,
    Placeholder = "Roblox",
})

do
    local CLOTHING_CLASSES = { "Accessory", "Shirt", "Pants", "ShirtGraphic", "BodyColors", "CharacterMesh", "Decal" }
    local R6_LIMBS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

    local function isClothing(instance)
        for _, className in ipairs(CLOTHING_CLASSES) do
            if instance:IsA(className) then
                return true
            end
        end
        return false
    end

    local function moveLimbContents(old, new)
        for _, child in ipairs(old:GetChildren()) do
            if not child:IsA("Motor6D") and not child:IsA("TouchTransmitter") then
                local existing = new:FindFirstChild(child.Name)
                if not (existing and existing.ClassName == child.ClassName) then
                    pcall(function()
                        child.Parent = new
                    end)
                end
            end
        end
    end

    local function retargetJoints(character, replaced)
        for _, joint in ipairs(character:GetDescendants()) do
            local isJoint = joint:IsA("WeldConstraint") or (joint:IsA("JointInstance") and not joint:IsA("Motor6D"))
            if isJoint then
                pcall(function()
                    if joint.Part0 and replaced[joint.Part0] then
                        joint.Part0 = replaced[joint.Part0]
                    end
                    if joint.Part1 and replaced[joint.Part1] then
                        joint.Part1 = replaced[joint.Part1]
                    end
                end)
            end
        end
    end

    local function redisplayCosmetics()
        if game.GameId ~= ETOH_GAME_ID then
            return
        end
        local ok, controller, equipped = pcall(function()
            local Framework = ReplicatedStorage.Framework
            local display = require(Framework.Scripts.Client.Controller.Game.CosmeticDisplayController)
            local data = require(Framework.Scripts.Client.Controller.DataController):Wait().Data
            return display, data.cosmetics.equipped
        end)
        if not ok or type(controller.Display) ~= "function" or type(controller.MakeDisplayData) ~= "function" then
            return
        end
        pcall(function()
            controller:MakeDisplayData(LocalPlayer)
        end)
        for slot, name in pairs(equipped) do
            if slot ~= "Emote" and type(name) == "string" and name ~= "" then
                pcall(function()
                    controller:Display(LocalPlayer, slot, name)
                end)
            end
        end
    end

    local Avatar = { model = nil, connection = nil, session = 0 }

    local function buildAvatar(description)
        local okModel, model = pcall(function()
            return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R6)
        end)
        if okModel then
            return model
        end
        return nil
    end

    local function applyAvatar(template)
        local model = template:Clone()
        local character = getCharacter()
        if not character then
            model:Destroy()
            return false, "character"
        end
        local root = character:FindFirstChild("HumanoidRootPart")
        local pivot = character:GetPivot()
        local primary = character.PrimaryPart

        for _, child in ipairs(character:GetChildren()) do
            if isClothing(child) then
                child:Destroy()
            end
        end
        local replaced = {}
        for _, limbName in ipairs(R6_LIMBS) do
            local old = character:FindFirstChild(limbName)
            local new = model:FindFirstChild(limbName)
            if old and new then
                moveLimbContents(old, new)
                replaced[old] = new
                new:SetAttribute("AeryAvatar", true)
                new.Parent = character
                if old:GetAttribute("AeryAvatar") then
                    old:Destroy()
                else
                    old.Name = "Aery " .. limbName
                    old.Transparency = 1
                    old.Massless = true
                end
            end
        end
        for _, child in ipairs(model:GetChildren()) do
            if isClothing(child) then
                child.Parent = character
            end
        end
        for _, joint in ipairs(model:GetDescendants()) do
            if joint:IsA("Motor6D") and joint.Part0 and joint.Part1 then
                local part0 = character:FindFirstChild(joint.Part0.Name)
                local part1 = character:FindFirstChild(joint.Part1.Name)
                if part0 and part1 then
                    local clone = joint:Clone()
                    clone.Part0 = part0
                    clone.Part1 = part1
                    clone.Parent = part0
                end
            end
        end
        if root then
            root.Parent = character
        end
        retargetJoints(character, replaced)
        local newPrimary = replaced[primary] or primary
        if not (newPrimary and newPrimary.Parent == character) then
            newPrimary = root
        end
        if newPrimary then
            character.PrimaryPart = newPrimary
        end
        character:PivotTo(pivot)
        model:Destroy()
        redisplayCosmetics()
        return true
    end

    Avatar.connection = LocalPlayer.CharacterAdded:Connect(function(character)
        if not Avatar.model then
            return
        end
        Avatar.session = Avatar.session + 1
        local session = Avatar.session
        for _, limbName in ipairs(R6_LIMBS) do
            character:WaitForChild(limbName, 10)
        end
        character:WaitForChild("HumanoidRootPart", 10)
        task.wait()
        if Avatar.model and session == Avatar.session and character.Parent and not Library.Unloaded then
            applyAvatar(Avatar.model)
        end
    end)
    local function setAvatarModel(model)
        if Avatar.model then
            Avatar.model:Destroy()
        end
        Avatar.model = model
    end
    local function resetAvatar()
        setAvatarModel(nil)
        Avatar.session = Avatar.session + 1
        local okDesc, description = pcall(function()
            return Players:GetHumanoidDescriptionFromUserId(LocalPlayer.UserId)
        end)
        local own = okDesc and buildAvatar(description)
        if own then
            applyAvatar(own)
            own:Destroy()
        end
    end

    Library:OnUnload(function()
        if Avatar.connection then
            Avatar.connection:Disconnect()
        end
        if Avatar.model then
            task.spawn(resetAvatar)
        end
    end)

    AvatarBox:AddButton({
        Text = "Change Avatar",
        DoubleClick = false,
        Tooltip = "Wear that player's avatar.",
        Func = function()
            local username = (Options.AvatarInput.Value or ""):match("^%s*(.-)%s*$")
            if username == "" then
                return
            end
            local info = userFromId(username)
            local ok, userId = info ~= nil, info and info.Id
            if not ok then
                ok, userId = pcall(function()
                    return Players:GetUserIdFromNameAsync(username)
                end)
            end
            if not ok then
                notify("Avatar Changer", "User not found: " .. username)
                return
            end
            local okDesc, description = pcall(function()
                return Players:GetHumanoidDescriptionFromUserId(userId)
            end)
            if not okDesc then
                notify("Avatar Changer", "Couldn't load " .. username .. "'s avatar.")
                return
            end
            local model = buildAvatar(description)
            if not model then
                notify("Avatar Changer", "Couldn't build " .. username .. "'s avatar.")
                return
            end
            if not applyAvatar(model) then
                model:Destroy()
                notify("Avatar Changer", "You have no character right now.")
                return
            end
            setAvatarModel(model)
        end,
    }):AddButton({
        Text = "Reset Avatar",
        DoubleClick = false,
        Tooltip = "Puts your own avatar back.",
        Func = resetAvatar,
    })
end

local SpooferBox = Tabs.Exploits:AddRightGroupbox("Name Spoofer")

do
    local Spoofer = {
        username = nil,
        displayName = nil,
        originals = setmetatable({}, { __mode = "k" }),
        lastWritten = setmetatable({}, { __mode = "k" }),
        hooked = setmetatable({}, { __mode = "k" }),
        connections = {},
        humanoid = nil,
        humanoidName = "",
        watching = false,
        scan = 0,
    }

    local function replacePlain(text, find, replacement)
        if find == "" then
            return text
        end
        local parts = {}
        local start = 1
        while true do
            local first, last = string.find(text, find, start, true)
            if not first then
                break
            end
            table.insert(parts, text:sub(start, first - 1))
            table.insert(parts, replacement)
            start = last + 1
        end
        table.insert(parts, text:sub(start))
        return table.concat(parts)
    end

    local function spoofText(text)
        local swaps = {}
        if Spoofer.username then
            table.insert(swaps, { LocalPlayer.Name, Spoofer.username })
        end
        if Spoofer.displayName then
            table.insert(swaps, { LocalPlayer.DisplayName, Spoofer.displayName })
        end
        if #swaps == 0 then
            return text
        end
        table.sort(swaps, function(a, b)
            return #a[1] > #b[1]
        end)
        for index, swap in ipairs(swaps) do
            text = replacePlain(text, swap[1], "\1" .. index .. "\1")
        end
        for index, swap in ipairs(swaps) do
            text = replacePlain(text, "\1" .. index .. "\1", swap[2])
        end
        return text
    end

    local function isTextObject(instance)
        return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
    end

    local function refresh(instance)
        local base = Spoofer.originals[instance] or instance.Text
        if type(base) ~= "string" then
            return
        end
        local spoofed = spoofText(base)
        if spoofed ~= base then
            Spoofer.originals[instance] = base
        else
            Spoofer.originals[instance] = nil
        end
        if instance.Text ~= spoofed then
            Spoofer.lastWritten[instance] = spoofed
            instance.Text = spoofed
        end
    end

    local function watch(instance)
        if not isTextObject(instance) then
            return
        end
        if not Spoofer.hooked[instance] then
            Spoofer.hooked[instance] = instance:GetPropertyChangedSignal("Text"):Connect(function()
                if instance.Text == Spoofer.lastWritten[instance] then
                    return
                end
                Spoofer.originals[instance] = nil
                pcall(refresh, instance)
            end)
        end
        refresh(instance)
    end

    local function applyHumanoid()
        local humanoid = getHumanoid()
        if Spoofer.displayName and humanoid then
            if Spoofer.humanoid ~= humanoid then
                Spoofer.humanoid = humanoid
                Spoofer.humanoidName = humanoid.DisplayName
            end
            humanoid.DisplayName = Spoofer.displayName
        elseif not Spoofer.displayName and Spoofer.humanoid then
            if Spoofer.humanoid.Parent then
                Spoofer.humanoid.DisplayName = Spoofer.humanoidName
            end
            Spoofer.humanoid = nil
            Spoofer.humanoidName = ""
        end
    end

    local function update()
        if Spoofer.username or Spoofer.displayName then
            if Spoofer.watching then
                for instance in pairs(Spoofer.hooked) do
                    pcall(refresh, instance)
                end
            else
                Spoofer.watching = true
                Spoofer.scan = Spoofer.scan + 1
                local scan = Spoofer.scan
                local roots = { LocalPlayer:FindFirstChildOfClass("PlayerGui") }
                pcall(function()
                    table.insert(roots, game:GetService("CoreGui"))
                end)
                table.insert(roots, workspace)
                for _, root in ipairs(roots) do
                    table.insert(Spoofer.connections, root.DescendantAdded:Connect(function(instance)
                        pcall(watch, instance)
                    end))
                end
                task.spawn(function()
                    local count = 0
                    for _, root in ipairs(roots) do
                        local ok, list = pcall(root.GetDescendants, root)
                        for _, instance in ipairs(ok and list or {}) do
                            if Spoofer.scan ~= scan then
                                return
                            end
                            pcall(watch, instance)
                            count = count + 1
                            if count % 150 == 0 then
                                task.wait()
                            end
                        end
                    end
                end)
                table.insert(Spoofer.connections, LocalPlayer.CharacterAdded:Connect(function(character)
                    character:WaitForChild("Humanoid", 10)
                    applyHumanoid()
                end))
            end
            applyHumanoid()
            return
        end
        applyHumanoid()
        disconnectAll(Spoofer.connections)
        Spoofer.scan = Spoofer.scan + 1
        for _, connection in pairs(Spoofer.hooked) do
            connection:Disconnect()
        end
        for instance, original in pairs(Spoofer.originals) do
            pcall(function()
                instance.Text = original
            end)
        end
        Spoofer.originals = setmetatable({}, { __mode = "k" })
        Spoofer.lastWritten = setmetatable({}, { __mode = "k" })
        Spoofer.hooked = setmetatable({}, { __mode = "k" })
        Spoofer.watching = false
    end

    local function spoofValue(inputId, field)
        local option = Options[inputId]
        local value = option and option.Value or ""
        local info = userFromId(value)
        if info then
            return field == "username" and info.Username or info.DisplayName
        end
        return value
    end

    local function spooferToggle(id, text, tooltip, inputId, field, emptyMessage)
        SpooferBox:AddToggle(id, {
            Text = text,
            Default = false,
            Tooltip = tooltip,
            Callback = function(enabled)
                if enabled then
                    local option = Options[inputId]
                    local value = option and option.Value or ""
                    if value == "" then
                        notify("Name Spoofer", emptyMessage)
                        Toggles[id]:SetValue(false)
                        return
                    end
                    if Toggles.ProtectIdentity and Toggles.ProtectIdentity.Value then
                        return
                    end
                    Spoofer[field] = spoofValue(inputId, field)
                elseif Toggles.ProtectIdentity and Toggles.ProtectIdentity.Value then
                    return
                else
                    Spoofer[field] = nil
                end
                update()
            end,
        })
    end

    SpooferBox:AddInput("SpooferInput", {
        Text = "Username or ID",
        Tooltip = "Sets the username Name Spoofer shows instead of yours.",
        Default = "",
        Numeric = false,
        Finished = false,
        ClearTextOnFocus = false,
        Placeholder = "Roblox",
    })

    spooferToggle("NameSpoofer", "Name Spoofer", "Spoofs your username.", "SpooferInput", "username", "Enter a username first.")

    SpooferBox:AddInput("DisplaySpooferInput", {
        Text = "Display Name or ID",
        Tooltip = "Sets the display name Display Name Spoofer shows instead of yours.",
        Default = "",
        Numeric = false,
        Finished = false,
        ClearTextOnFocus = false,
        Placeholder = "Roblox",
    })

    spooferToggle("DisplayNameSpoofer", "Display Name Spoofer", "Spoofs your display name, including the name above your character.", "DisplaySpooferInput", "displayName", "Enter a display name first.")

    local function randomName(syllables)
        local consonants = "bcdfghjklmnprstvz"
        local vowels = "aeiou"
        local parts = {}
        for _ = 1, syllables do
            local c = math.random(#consonants)
            local v = math.random(#vowels)
            table.insert(parts, consonants:sub(c, c) .. vowels:sub(v, v))
        end
        local name = table.concat(parts)
        return name:sub(1, 1):upper() .. name:sub(2)
    end

    SpooferBox:AddToggle("ProtectIdentity", {
        Text = "Protect Identity",
        Default = false,
        Tooltip = "Hides your names behind random ones.",
        Callback = function(enabled)
            if enabled then
                local username, displayName
                repeat
                    username = randomName(math.random(3, 4)) .. math.random(10, 9999)
                until username:lower() ~= LocalPlayer.Name:lower()
                repeat
                    displayName = randomName(math.random(2, 3))
                until displayName:lower() ~= LocalPlayer.DisplayName:lower()
                Spoofer.username = username
                Spoofer.displayName = displayName
            else
                Spoofer.username = Toggles.NameSpoofer.Value and spoofValue("SpooferInput", "username") or nil
                Spoofer.displayName = Toggles.DisplayNameSpoofer.Value and spoofValue("DisplaySpooferInput", "displayName") or nil
            end
            update()
        end,
    })

    Library:OnUnload(function()
        Spoofer.username = nil
        Spoofer.displayName = nil
        update()
    end)
end

do
    local hideTimes = {
        on = false,
        connections = {},
        hooked = HttpService:JSONDecode("{}"),
        originals = HttpService:JSONDecode("{}"),
    }

    local function maskTimes(text)
        return (text:gsub("%d[%d:]*:%d%d%.%d+", function(time)
            return (time:gsub("%d", "X"))
        end))
    end

    local function hideLabel(label)
        if not hideTimes.on then
            return
        end
        local text = label.Text
        local masked = maskTimes(text)
        if masked ~= text then
            hideTimes.originals[label] = text
            label.Text = masked
        end
    end

    local function watchLabel(label)
        if hideTimes.hooked[label] or not (label:IsA("TextLabel") or label:IsA("TextButton")) then
            return
        end
        hideTimes.hooked[label] = true
        hideLabel(label)
        table.insert(hideTimes.connections, label:GetPropertyChangedSignal("Text"):Connect(function()
            hideLabel(label)
        end))
    end

    local function setHideTimes(enabled)
        hideTimes.on = enabled
        disconnectAll(hideTimes.connections)
        table.clear(hideTimes.hooked)
        if not enabled then
            for label, text in pairs(hideTimes.originals) do
                if label.Parent and label.Text == maskTimes(text) then
                    label.Text = text
                end
            end
            table.clear(hideTimes.originals)
            return
        end
        local roots = { LocalPlayer:FindFirstChildOfClass("PlayerGui") }
        pcall(function()
            table.insert(roots, game:GetService("CoreGui"):FindFirstChild("ExperienceChat"))
        end)
        for _, root in ipairs(roots) do
            table.insert(hideTimes.connections, root.DescendantAdded:Connect(watchLabel))
            task.spawn(forEachSlowly, root:GetDescendants(), watchLabel, function()
                return hideTimes.on
            end)
        end
    end

    SpooferBox:AddToggle("HideCompletionTimes", {
        Text = "Hide Completion Times",
        Default = false,
        Tooltip = "Replaces completion times on your screen with X:XX.XX.",
        Callback = setHideTimes,
    })

    Library:OnUnload(function()
        setHideTimes(false)
    end)
end

local SubrealmBox = (IS_TEA or IS_CSCD or IS_TOR or IS_ASTN) and NullBox or Tabs.Exploits:AddLeftGroupbox("Unlock Subrealms")

local function rootOrWait()
    return LocalPlayer.Character:WaitForChild("HumanoidRootPart")
end

local function subrealmButton(text, placeId, area, action)
    SubrealmBox:AddButton({
        Text = text,
        DoubleClick = false,
        Tooltip = "Takes you into this subrealm. You must be in " .. area .. ".",
        Func = function()
            if game.PlaceId ~= placeId then
                notify("Unlock Subrealms", "You must be in " .. area .. ".")
                return
            end
            action(workspace:FindFirstChild("PClientParts"))
        end,
    })
end

subrealmButton("Forgotten Ridge (Ring 1)", 9070657865, "Ring 1", function(parts)
    local button = parts.FRTramEntry.Tram:WaitForChild("Button")
    rootOrWait().CFrame = button.CFrame
    task.wait(0.2)
    if fireclickdetector then
        fireclickdetector(button.ClickDetector)
    end
end)

subrealmButton("Garden of Eesh\195\182l (Ring 2)", 9070979698, "Ring 2", function()
    rootOrWait().CFrame = CFrame.new(-5103.41455, 1830.57654, 1997.2865, 0, 0, -1, 0, 1, 0, 1, 0, 0)
end)

subrealmButton("Silent Abyss (Ring 4)", 9070980555, "Ring 4", function(parts)
    local entrance = parts.SAEntrance.Pod:FindFirstChild("Entrance")
    if entrance then
        rootOrWait().CFrame = entrance.CFrame
    end
end)

subrealmButton("Lost River (Ring 5)", 9070980846, "Ring 5", function(parts)
    local platform = parts.LREntrance.Raft:FindFirstChild("Platform")
    if platform then
        local root = rootOrWait()
        root.CFrame = platform.CFrame
        root.Anchored = true
        task.wait(0.4)
        root.Anchored = false
    end
end)

subrealmButton("Ashen Towerworks (Ring 6)", 9070981164, "Ring 6", function(parts)
    local placeId = 14399266686
    pcall(function()
        local value = parts.IMPEntrance.Teleporter.PlaceID.Value
        if type(value) == "number" and value > 0 then
            placeId = value
        end
    end)
    TeleportService:Teleport(placeId, LocalPlayer)
end)

subrealmButton("The Starlit Archives (Ring 8)", 9070981722, "Ring 8", function(parts)
    local teleporter = parts:FindFirstChild("TSA teleporter")
    if teleporter then
        rootOrWait().CFrame = teleporter.CFrame
    end
end)

SubrealmBox:AddDivider()

subrealmButton("Steelspire Horizon (Zone 1)", 9071001075, "Zone 1", function(parts)
    rootOrWait().CFrame = parts.SHelicopter.Helicopter:WaitForChild("Trigger").CFrame
end)

subrealmButton("Arcane Area (Zone 2)", 9071001366, "Zone 2", function()
    rootOrWait().CFrame = CFrame.new(-39.5, 14, -309, 0, 0, 1, 0, 1, 0, -1, 0, 0)
end)

subrealmButton("Paradise Atoll (Zone 3)", 9071001563, "Zone 3", function(parts)
    local root = rootOrWait()
    root.CFrame = parts.JetFuel.CFrame
    task.wait(0.2)
    root.CFrame = parts.PA_Teleport.Touch.CFrame
end)

subrealmButton("Dark Side (Zone 5)", 9071002104, "Zone 5", function()
    rootOrWait().CFrame = CFrame.new(4491.32861, 1201.6322, -1979.57922, 0.795978189, 0, -0.605325401, 0, 1, 0, 0.605325401, 0, 0.795978189)
end)

local function removeDrawing(drawing)
    pcall(function()
        drawing:Remove()
    end)
end

local TowerEspBox = Tabs.Visuals:AddLeftGroupbox("Tower ESP")

local function isPortalPart(part)
    local parent = part.Parent
    if IS_CSCD then
        local teleporters = workspace:FindFirstChild("Teleporters")
        return teleporters ~= nil and parent ~= nil and (parent == teleporters or parent.Parent == teleporters)
    end
    if IS_TOR then
        return part.Name == "Name" and parent ~= nil and (parent.Name == "Portal" or parent.Name == "HardcorePortal")
    end
    if IS_ASTN then
        return parent ~= nil and parent == workspace:FindFirstChild("Portals")
    end
    if part.Name == "TPFRAME" then
        return true
    end
    if part.Name == "Teleport" and parent ~= nil and (parent.Name == "Teleporter" or parent.Name == "TowerRushPortal") and parent.Parent ~= nil and parent.Parent.Name == "Teleporter" then
        return true
    end
    return part.Name == "Teleporter" and parent ~= nil and parent.Name == "Portal"
end

local TOWER_PART_CONTAINERS = IS_CSCD and { "Towers", "Teleporters", "Winpads" } or IS_TOR and { "Obbies" } or IS_ASTN and { "Towers", "Portals" } or { "Towers" }

local function towerPartEsp(id, text, partName, create, update)
    local data = {}
    local connections = {}

    local function add(part)
        local matches = type(partName) == "function" and partName(part) or part.Name == partName
        if part:IsA("BasePart") and matches and not data[part] then
            data[part] = create(part)
        end
    end

    local function remove(part)
        local drawings = data[part]
        if drawings then
            for _, drawing in pairs(drawings) do
                if typeof(drawing) == "Instance" then
                    drawing:Destroy()
                else
                    removeDrawing(drawing)
                end
            end
            data[part] = nil
        end
    end

    TowerEspBox:AddToggle(id, {
        Text = text,
        Tooltip = "Shows " .. text:lower() .. " through walls.",
        Default = false,
        Callback = function(enabled)
            disconnectAll(connections)
            for part in pairs(data) do
                remove(part)
            end
            if not enabled then
                return
            end
            for _, containerName in ipairs(TOWER_PART_CONTAINERS) do
                local container = workspace:FindFirstChild(containerName)
                if container then
                    for _, descendant in ipairs(container:GetDescendants()) do
                        add(descendant)
                    end
                    table.insert(connections, container.DescendantAdded:Connect(function(part)
                        task.defer(function()
                            if part.Parent then
                                add(part)
                            end
                        end)
                    end))
                    table.insert(connections, container.DescendantRemoving:Connect(remove))
                end
            end
            if update then
                table.insert(connections, RunService.RenderStepped:Connect(function()
                    local camera = workspace.CurrentCamera
                    for part, drawings in pairs(data) do
                        if not part.Parent then
                            remove(part)
                        else
                            update(part, drawings, camera)
                        end
                    end
                end))
            end
        end,
    })
end

local function labelDrawing(textValue, color)
    local text = Drawing.new("Text")
    text.Text = textValue
    text.Size = 16
    text.Font = 3
    text.Center = true
    text.Outline = true
    text.OutlineColor = Color3.fromRGB(0, 0, 0)
    text.Color = color
    text.Visible = false
    text.Position = Vector2.new(0, 0)
    return text
end

local function tracerDrawings(color)
    local outline = Drawing.new("Line")
    outline.Thickness = 3
    outline.Color = Color3.fromRGB(0, 0, 0)
    outline.Visible = false
    outline.Transparency = 1
    local main = Drawing.new("Line")
    main.Thickness = 1
    main.Color = color
    main.Visible = false
    main.Transparency = 1
    return { outline = outline, main = main }
end

local function updateLabel(part, drawings, camera)
    local screen, onScreen = camera:WorldToViewportPoint(part.Position)
    drawings.text.Visible = onScreen
    if onScreen then
        drawings.text.Position = Vector2.new(screen.X, screen.Y)
    end
end

local function updateTracer(part, drawings, camera)
    local screen, onScreen = camera:WorldToViewportPoint(part.Position)
    if not onScreen then
        drawings.outline.Visible = false
        drawings.main.Visible = false
        return
    end
    local viewport = camera.ViewportSize
    local from = Vector2.new(viewport.X * 0.5, viewport.Y)
    local to = Vector2.new(screen.X, screen.Y + 18)
    for _, line in ipairs({ drawings.outline, drawings.main }) do
        line.From = from
        line.To = to
        line.Visible = true
    end
end

local INTENSE_OUTLINE = Color3.fromHex("#8A9BB0")

local function portalColor(part)
    local difficulty = towerDifficultyName(towerNameOf(part, ""))
    local hex = difficulty and DIFFICULTY_COLORS[difficulty]
    return hex and Color3.fromHex(hex) or Color3.new(1, 1, 1), difficulty
end

towerPartEsp("PortalNameESP", "Portal Names", isPortalPart, function(part)
    local color, difficulty = portalColor(part)
    local text = labelDrawing(towerNameOf(part, "Portal"), color)
    if difficulty == "Intense" then
        text.OutlineColor = INTENSE_OUTLINE
    end
    return { text = text }
end, updateLabel)

towerPartEsp("PortalTracers", "Portal Tracers", isPortalPart, function(part)
    local color, difficulty = portalColor(part)
    local drawings = tracerDrawings(color)
    if difficulty == "Intense" then
        drawings.outline.Color = INTENSE_OUTLINE
    end
    return drawings
end, updateTracer)

local chamsContainer = Instance.new("Folder")
chamsContainer.Name = "PortalChams"
pcall(function()
    chamsContainer.Parent = (gethui and gethui()) or game:GetService("CoreGui")
end)
Library:OnUnload(function()
    chamsContainer:Destroy()
end)

towerPartEsp("PortalChams", "Portal Chams", isPortalPart, function(part)
    local box = Instance.new("BoxHandleAdornment")
    box.Adornee = part
    box.Size = part.Size
    box.Color3 = portalColor(part)
    box.Transparency = 0.3
    box.AlwaysOnTop = true
    box.ZIndex = 1
    box.Parent = chamsContainer
    return { box = box }
end)

towerPartEsp("WinpadBoxESP", "Winpad Boxes", isWinpadPart, function()
    local box = Drawing.new("Square")
    box.Thickness = 1
    box.Filled = false
    box.Color = Color3.fromRGB(0, 255, 0)
    box.Visible = false
    box.ZIndex = 2
    local outline = Drawing.new("Square")
    outline.Thickness = 2
    outline.Filled = false
    outline.Color = Color3.fromRGB(0, 0, 0)
    outline.Visible = false
    outline.ZIndex = 1
    return { box = box, outline = outline }
end, function(part, drawings, camera)
    local half = part.Size / 2
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local anyOnScreen = false
    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            for _, sz in ipairs({ -1, 1 }) do
                local corner = part.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
                local screen, onScreen = camera:WorldToViewportPoint(corner)
                if screen.Z > 0 then
                    anyOnScreen = anyOnScreen or onScreen
                    minX, minY = math.min(minX, screen.X), math.min(minY, screen.Y)
                    maxX, maxY = math.max(maxX, screen.X), math.max(maxY, screen.Y)
                end
            end
        end
    end
    for _, square in ipairs({ drawings.box, drawings.outline }) do
        square.Visible = anyOnScreen
        if anyOnScreen then
            square.Position = Vector2.new(minX, minY)
            square.Size = Vector2.new(math.abs(maxX - minX), math.abs(maxY - minY))
        end
    end
end)

towerPartEsp("WinpadNameESP", "Winpad Names", isWinpadPart, function(part)
    return { text = labelDrawing(towerNameOf(part, "Unknown") .. " Winpad", Color3.fromRGB(0, 255, 0)) }
end, updateLabel)

towerPartEsp("WinpadTracers", "Winpad Tracers", isWinpadPart, function()
    return tracerDrawings(Color3.fromRGB(0, 255, 0))
end, updateTracer)

do
    local KillbrickBox = Tabs.Visuals:AddLeftGroupbox("Killbrick ESP")
    local brickTypes
    if IS_TOR then
        brickTypes = {
            { id = "instakills", label = "Instakills", color = Color3.fromRGB(130, 0, 0) },
        }
    elseif game.GameId == TEA_GAME_ID then
        brickTypes = {
            { id = "kills", label = "Killbricks", color = Color3.fromRGB(255, 60, 60) },
            { id = "instakills", label = "Instakills", color = Color3.fromRGB(130, 0, 0) },
        }
    else
        brickTypes = {
            { id = "kills", label = "Normal", color = Color3.fromRGB(255, 60, 60) },
            { id = "double", label = "Double", color = Color3.fromRGB(255, 140, 26) },
            { id = "ouch", label = "Ouch", color = Color3.fromRGB(255, 60, 200) },
            { id = "instakills", label = "Instakill", color = Color3.fromRGB(130, 0, 0) },
            { id = "custom", label = "Custom", color = Color3.fromRGB(255, 210, 30) },
        }
        if IS_ASTN then
            table.remove(brickTypes)
        end
    end

    local active = false
    local known = {}
    local boxes = {}
    local drawings = {}
    local connections = {}
    local scan = 0

    local function toggleOn(id)
        return Toggles[id] ~= nil and Toggles[id].Value == true
    end

    local function labelFor(brickType)
        for _, info in ipairs(brickTypes) do
            if info.id == brickType then
                return info.label
            end
        end
        return brickType
    end

    local function colorFor(brickType)
        for _, info in ipairs(brickTypes) do
            if info.id == brickType then
                return info.color
            end
        end
        return Color3.new(1, 0, 0)
    end

    local function removeDrawings(part)
        local set = drawings[part]
        if set then
            removeDrawing(set.text)
            removeDrawing(set.outline)
            removeDrawing(set.main)
            drawings[part] = nil
        end
    end

    local function hideDrawings(set)
        set.text.Visible = false
        set.outline.Visible = false
        set.main.Visible = false
    end
    local container = Instance.new("Folder")
    container.Name = "KillbrickOutlines"
    pcall(function()
        container.Parent = (gethui and gethui()) or game:GetService("CoreGui")
    end)

    local function typeShown(brickType)
        local selected = Options.KillbrickTypes and Options.KillbrickTypes.Value
        if type(selected) ~= "table" then
            return true
        end
        for _, info in ipairs(brickTypes) do
            if info.id == brickType then
                return selected[info.label] == true
            end
        end
        return false
    end

    local function removeBox(part)
        if boxes[part] then
            boxes[part]:Destroy()
            boxes[part] = nil
        end
    end

    local function refreshPart(part)
        removeBox(part)
        local brickType = known[part]
        if not active or not brickType or not typeShown(brickType) or not part.Parent or not toggleOn("KillbrickESP") then
            return
        end
        local color = colorFor(brickType)
        local box = Instance.new("SelectionBox")
        box.Adornee = part
        box.Color3 = color
        box.SurfaceColor3 = color
        box.SurfaceTransparency = 0.75
        box.LineThickness = 0.03
        box.Parent = container
        boxes[part] = box
    end

    local function consider(part)
        if not part.Parent then
            return
        end
        local brickType = damageBrickType(part)
        if brickType then
            known[part] = brickType
            refreshPart(part)
        end
    end

    local function refreshAll()
        for part in pairs(known) do
            refreshPart(part)
            local set = drawings[part]
            if set then
                local color = colorFor(known[part])
                set.text.Color = color
                set.main.Color = color
            end
        end
    end

    local function stop()
        scan = scan + 1
        disconnectAll(connections)
        for part in pairs(boxes) do
            removeBox(part)
        end
        for part in pairs(drawings) do
            removeDrawings(part)
        end
        table.clear(known)
    end

    local function watch(root, keepGoing)
        if not keepGoing() then
            return
        end
        table.insert(connections, root.DescendantAdded:Connect(function(part)
            task.defer(function()
                if active and part.Parent then
                    consider(part)
                end
            end)
        end))
        table.insert(connections, root.DescendantRemoving:Connect(function(part)
            if known[part] then
                removeBox(part)
                removeDrawings(part)
                known[part] = nil
            end
        end))
        forEachSlowly(root:GetDescendants(), consider, keepGoing)
    end

    local function start()
        stop()
        if not active then
            return
        end
        local myScan = scan
        local function keepGoing()
            return active and scan == myScan
        end
        task.spawn(function()
            for _, child in ipairs(workspace:GetChildren()) do
                if not keepGoing() then
                    return
                end
                if child.Parent == workspace and child ~= workspace.CurrentCamera and not child:IsA("Terrain") and not Players:GetPlayerFromCharacter(child) then
                    if child:IsA("BasePart") then
                        consider(child)
                    else
                        watch(child, keepGoing)
                    end
                end
            end
        end)
        table.insert(connections, RunService.RenderStepped:Connect(function()
            local names, tracers = toggleOn("KillbrickNames"), toggleOn("KillbrickTracers")
            local camera = workspace.CurrentCamera
            local root = getRoot()
            local range = Options.KillbrickDistance and Options.KillbrickDistance.Value or 150
            for part, brickType in pairs(known) do
                local set = drawings[part]
                local show = (names or tracers) and camera ~= nil and root ~= nil and part.Parent ~= nil
                    and typeShown(brickType) and (part.Position - root.Position).Magnitude <= range
                if show then
                    if not set then
                        local color = colorFor(brickType)
                        local lines = tracerDrawings(color)
                        set = { text = labelDrawing(labelFor(brickType), color), outline = lines.outline, main = lines.main }
                        drawings[part] = set
                    end
                    if names then
                        updateLabel(part, set, camera)
                    else
                        set.text.Visible = false
                    end
                    if tracers then
                        updateTracer(part, set, camera)
                    else
                        set.outline.Visible = false
                        set.main.Visible = false
                    end
                elseif set then
                    hideDrawings(set)
                end
            end
        end))
        table.insert(connections, workspace.ChildAdded:Connect(function(child)
            task.defer(function()
                if active and child.Parent == workspace and not Players:GetPlayerFromCharacter(child) then
                    if child:IsA("BasePart") then
                        consider(child)
                    else
                        watch(child, keepGoing)
                    end
                end
            end)
        end))
    end

    local function updateActive()
        local want = toggleOn("KillbrickESP") or toggleOn("KillbrickNames") or toggleOn("KillbrickTracers")
        if want ~= active then
            active = want
            start()
        else
            refreshAll()
        end
    end

    KillbrickBox:AddToggle("KillbrickESP", {
        Text = "Killbrick ESP",
        Default = false,
        Tooltip = "Outlines killbricks in the color of their type.",
        Callback = updateActive,
    })

    local typeLabels = {}
    for _, info in ipairs(brickTypes) do
        table.insert(typeLabels, info.label)
    end

    KillbrickBox:AddToggle("KillbrickNames", {
        Text = "Killbrick Names",
        Default = false,
        Tooltip = "Shows each nearby killbrick's type above it.",
        Callback = updateActive,
    })

    KillbrickBox:AddToggle("KillbrickTracers", {
        Text = "Killbrick Tracers",
        Default = false,
        Tooltip = "Draws a line to each nearby killbrick.",
        Callback = updateActive,
    })

    KillbrickBox:AddDropdown("KillbrickTypes", {
        Text = "Killbrick Types",
        Tooltip = "Selects which killbrick types Killbrick ESP shows.",
        Values = typeLabels,
        Default = typeLabels,
        Multi = true,
        Callback = refreshAll,
    })

    KillbrickBox:AddSlider("KillbrickDistance", {
        Text = "Killbrick Distance",
        Default = 150,
        Min = 25,
        Max = 500,
        Rounding = 0,
        Compact = false,
        Tooltip = "How far away killbrick names and tracers are shown, in studs.",
    })

    Library:OnUnload(function()
        active = false
        stop()
        container:Destroy()
    end)
end

local CameraBox = Tabs.Visuals:AddRightGroupbox("Lighting and Camera")

do
    local connection
    local original

    local apply = function()
        Lighting.Brightness = 2
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
        Lighting.ClockTime = 14
    end

    CameraBox:AddToggle("Fullbright", {
        Text = "Fullbright",
        Tooltip = "Removes darkness and shadows for full map visibility.",
        Default = false,
        Callback = function(enabled)
            if connection then
                connection:Disconnect()
                connection = nil
            end
            if enabled then
                original = original or {
                    Brightness = Lighting.Brightness,
                    Ambient = Lighting.Ambient,
                    OutdoorAmbient = Lighting.OutdoorAmbient,
                    ClockTime = Lighting.ClockTime,
                }
                apply()
                connection = RunService.RenderStepped:Connect(apply)
            elseif original then
                for property, value in pairs(original) do
                    Lighting[property] = value
                end
                original = nil
            end
        end,
    })
end

do
    local connection
    local original

    local apply = function()
        Lighting.FogStart = 999999
        Lighting.FogEnd = 999999
    end

    CameraBox:AddToggle("NoFog", {
        Text = "No Fog",
        Tooltip = "Removes fog to extend view distance.",
        Default = false,
        Callback = function(enabled)
            if connection then
                connection:Disconnect()
                connection = nil
            end
            if enabled then
                original = original or { FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd }
                apply()
                connection = RunService.RenderStepped:Connect(apply)
            elseif original then
                Lighting.FogStart = original.FogStart
                Lighting.FogEnd = original.FogEnd
                original = nil
            end
        end,
    })
end

CameraBox:AddDivider()

CameraBox:AddSlider("FOVSlider", {
    Text = "Field of View",
    Tooltip = "Sets the camera's field of view. Default is 70.",
    Default = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70,
    Min = 50,
    Max = 120,
    Rounding = 1,
    Compact = false,
    Callback = function(value)
        if workspace.CurrentCamera then
            workspace.CurrentCamera.FieldOfView = value
        end
    end,
})

do
    local blurAmount = 60
    local blur
    local lastLook
    local heartbeatConnection
    local cameraConnection

    local function ensureBlur(camera)
        if not blur or not blur.Parent then
            blur = Instance.new("BlurEffect")
        end
        blur.Parent = camera
    end

    CameraBox:AddToggle("MotionBlur", {
        Text = "Motion Blur",
        Tooltip = "Blurs the screen while you turn the camera.",
        Default = false,
        Callback = function(enabled)
            if heartbeatConnection then
                heartbeatConnection:Disconnect()
                heartbeatConnection = nil
            end
            if cameraConnection then
                cameraConnection:Disconnect()
                cameraConnection = nil
            end
            if not enabled then
                if blur then
                    blur:Destroy()
                    blur = nil
                end
                return
            end
            local camera = workspace.CurrentCamera
            ensureBlur(camera)
            lastLook = camera.CFrame.LookVector
            cameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
                ensureBlur(workspace.CurrentCamera)
                lastLook = workspace.CurrentCamera.CFrame.LookVector
            end)
            heartbeatConnection = RunService.Heartbeat:Connect(function()
                local current = workspace.CurrentCamera
                ensureBlur(current)
                local look = current.CFrame.LookVector
                blur.Size = math.abs((look - lastLook).Magnitude) * blurAmount / 2
                lastLook = look
            end)
        end,
    })

    CameraBox:AddSlider("BlurAmount", {
        Text = "Blur Amount",
        Tooltip = "Sets the strength of Motion Blur.",
        Default = 60,
        Min = 0,
        Max = 200,
        Rounding = 0,
        Callback = function(value)
            blurAmount = tonumber(value) or 60
        end,
    })
end

local LayoutBox = Tabs.Visuals:AddRightGroupbox("Layout Mode")

do
    local active = false
    local boxes = {}
    local faded = {}
    local opaque = {}
    local partConnections = {}
    local rootConnections = {}
    local scopeTower
    local scan = 0
    local watchRun = 0
    local container = Instance.new("Folder")
    container.Name = "LayoutMode"
    pcall(function()
        container.Parent = (gethui and gethui()) or game:GetService("CoreGui")
    end)

    local function optionOn(name)
        return Toggles[name] and Toggles[name].Value
    end

    local function clearPart(part)
        local box = boxes[part]
        if box then
            box:Destroy()
            boxes[part] = nil
        end
        if faded[part] then
            pcall(function()
                part.LocalTransparencyModifier = 0
            end)
            faded[part] = nil
        end
    end

    local function addBox(part, color)
        local box = Instance.new("SelectionBox")
        box.Adornee = part
        box.Color3 = color
        box.SurfaceColor3 = color
        box.SurfaceTransparency = 0.75
        box.LineThickness = 0.03
        box.Parent = container
        boxes[part] = box
    end

    local function restoreOpaque(part)
        local original = opaque[part]
        if original then
            opaque[part] = nil
            pcall(function()
                part.Transparency = original
            end)
        end
    end

    local function classify(part)
        clearPart(part)
        if not active or not part.Parent then
            return
        end
        local baseTransparency = opaque[part] or part.Transparency
        if optionOn("LayoutReveal") and baseTransparency >= 1 and part.CanCollide and not isDamageBrick(part) then
            addBox(part, Options.LayoutRevealColor.Value)
        end
        if optionOn("LayoutOpaque") then
            if part.Transparency > 0 then
                opaque[part] = part.Transparency
                part.Transparency = 0
            end
        elseif opaque[part] then
            restoreOpaque(part)
        end
        if optionOn("LayoutFade") and not part.CanCollide and part.Transparency < 1 then
            part.LocalTransparencyModifier = (Options.LayoutFadeAmount and Options.LayoutFadeAmount.Value or 100) / 100
            faded[part] = true
        end
    end

    local function track(part)
        if partConnections[part] then
            return
        end
        if optionOn("LayoutLive") then
            partConnections[part] = {
                part:GetPropertyChangedSignal("Transparency"):Connect(function()
                    if opaque[part] and part.Transparency == 0 then
                        return
                    end
                    opaque[part] = nil
                    classify(part)
                end),
                part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                    classify(part)
                end),
            }
        else
            partConnections[part] = {}
        end
        classify(part)
    end

    local function untrack(part)
        local connections = partConnections[part]
        if connections then
            disconnectAll(connections)
            partConnections[part] = nil
        end
        clearPart(part)
        restoreOpaque(part)
    end

    local function currentTower(towers)
        local kitTower = currentKitTower()
        if kitTower and towers:FindFirstChild(kitTower) then
            return towers[kitTower]
        end
        local attribute = LocalPlayer:GetAttribute("Tower")
        if type(attribute) == "string" and towers:FindFirstChild(attribute) then
            return towers[attribute]
        end
        local root = getRoot()
        if not root then
            return nil
        end
        for _, tower in ipairs(towers:GetChildren()) do
            local ok, cframe, size = pcall(function()
                return tower:GetBoundingBox()
            end)
            if ok and cframe then
                local offset = cframe:PointToObjectSpace(root.Position)
                if math.abs(offset.X) <= size.X / 2 and math.abs(offset.Y) <= size.Y / 2 and math.abs(offset.Z) <= size.Z / 2 then
                    return tower
                end
            end
        end
        return nil
    end

    local function stop()
        scan = scan + 1
        disconnectAll(rootConnections)
        for part in pairs(partConnections) do
            untrack(part)
        end
        for part in pairs(boxes) do
            clearPart(part)
        end
        for part in pairs(faded) do
            clearPart(part)
        end
        for part in pairs(opaque) do
            restoreOpaque(part)
        end
    end

    local function trackPart(part)
        if part.Parent and part:IsA("BasePart") then
            track(part)
        end
    end

    local function watchRoot(root, keepGoing)
        if not keepGoing() then
            return
        end
        if optionOn("LayoutLive") then
            table.insert(rootConnections, root.DescendantAdded:Connect(function(part)
                if part:IsA("BasePart") then
                    track(part)
                end
            end))
            table.insert(rootConnections, root.DescendantRemoving:Connect(function(part)
                if partConnections[part] then
                    untrack(part)
                end
            end))
        end
        forEachSlowly(root:GetDescendants(), trackPart, keepGoing)
    end

    local function rebuild()
        stop()
        if not active then
            return
        end
        local myScan = scan
        local function keepGoing()
            return active and scan == myScan
        end
        local towers = workspace:FindFirstChild("Towers")
        local function watchOther(child)
            if child == towers or child == workspace.CurrentCamera or child:IsA("Terrain") or Players:GetPlayerFromCharacter(child) then
                return
            end
            if child:IsA("BasePart") then
                trackPart(child)
            else
                watchRoot(child, keepGoing)
            end
        end
        if towers and optionOn("LayoutCurrentTower") then
            scopeTower = currentTower(towers)
        end
        task.spawn(function()
            if towers then
                if optionOn("LayoutCurrentTower") then
                    if scopeTower then
                        watchRoot(scopeTower, keepGoing)
                    end
                else
                    watchRoot(towers, keepGoing)
                end
            end
            for _, child in ipairs(workspace:GetChildren()) do
                if not keepGoing() then
                    return
                end
                if child.Parent == workspace then
                    watchOther(child)
                end
            end
        end)
        if optionOn("LayoutLive") then
            table.insert(rootConnections, workspace.ChildAdded:Connect(function(child)
                task.defer(function()
                    if active and child.Parent == workspace then
                        watchOther(child)
                    end
                end)
            end))
            table.insert(rootConnections, workspace.ChildRemoved:Connect(function(child)
                if partConnections[child] then
                    untrack(child)
                end
            end))
        end
    end

    LayoutBox:AddToggle("LayoutMode", {
        Text = "Layout Mode",
        Default = false,
        Tooltip = "Shows what's actually solid in towers, using the options below.",
        Callback = function(enabled)
            active = enabled
            watchRun = watchRun + 1
            local run = watchRun
            rebuild()
            if not enabled then
                return
            end
            task.spawn(function()
                while active and watchRun == run do
                    task.wait(2)
                    local towers = workspace:FindFirstChild("Towers")
                    if active and watchRun == run and towers and optionOn("LayoutCurrentTower") and currentTower(towers) ~= scopeTower then
                        rebuild()
                    end
                end
            end)
        end,
    })

    LayoutBox:AddDivider()

    LayoutBox:AddToggle("LayoutReveal", {
        Text = "Outline Hidden Parts",
        Default = true,
        Tooltip = "Outlines invisible parts that are solid, like hidden platforms and walls.",
        Callback = rebuild,
    }):AddColorPicker("LayoutRevealColor", {
        Title = "Hidden Part Color",
        Default = Color3.fromRGB(0, 255, 120),
        Callback = rebuild,
    })

    LayoutBox:AddToggle("LayoutOpaque", {
        Text = "Remove Transparency",
        Default = false,
        Tooltip = "Makes see-through and invisible tower parts fully visible.",
        Callback = rebuild,
    })

    LayoutBox:AddToggle("LayoutFade", {
        Text = "Fade Non-Solid Parts",
        Default = true,
        Tooltip = "Fades out parts you can pass through, like fake walls and floors.",
        Callback = rebuild,
    })

    LayoutBox:AddSlider("LayoutFadeAmount", {
        Text = "Fade Amount",
        Tooltip = "How faded walk-through parts are. 100 hides them completely.",
        Default = 100,
        Min = 0,
        Max = 100,
        Rounding = 0,
        Compact = false,
        Callback = function(value)
            for part in pairs(faded) do
                pcall(function()
                    part.LocalTransparencyModifier = value / 100
                end)
            end
        end,
    })

    LayoutBox:AddToggle("LayoutLive", {
        Text = "Update Automatically",
        Default = true,
        Tooltip = "Keeps up with parts that appear or change, like platforms from buttons.",
        Callback = rebuild,
    })

    LayoutBox:AddToggle("LayoutCurrentTower", {
        Text = "Current Tower Only",
        Default = false,
        Tooltip = "Only affects the tower you're in.",
        Callback = rebuild,
    })

    Library:OnUnload(function()
        active = false
        stop()
        container:Destroy()
    end)
end

do
    local TAS_FOLDER = "Aery Hub/TAS"
    local TasBox = Tabs.TAS:AddLeftGroupbox("TAS")

    pcall(function()
        if not isfolder("Aery Hub") then
            makefolder("Aery Hub")
        end
        if not isfolder(TAS_FOLDER) then
            makefolder(TAS_FOLDER)
        end
    end)

    local TAS_API = ""
    local TAS_CACHE = TAS_FOLDER .. "/Online"

    pcall(function()
        if not isfolder(TAS_CACHE) then
            makefolder(TAS_CACHE)
        end
    end)

    local function httpGet(url)
        local ok, body = pcall(function()
            return game:HttpGet(url)
        end)
        if ok and type(body) == "string" and body ~= "" then
            return body
        end
        local httpRequest = request or http_request or (syn and syn.request)
        if not httpRequest then
            return nil
        end
        local okRequest, response = pcall(httpRequest, { Url = url, Method = "GET", Headers = { ["User-Agent"] = "Aery Hub" } })
        if okRequest and type(response) == "table" and (response.StatusCode or 200) == 200 and type(response.Body) == "string" then
            return response.Body
        end
        return nil
    end

    local TasAreas = {
        [15873244701] = "TheEternalAbyss",
        [121814103864070] = "TEA-Pit of Misery",
        [137721171983074] = "StarryNight",
    }

    local function currentRings()
        local rings = TasAreas[game.PlaceId] or PLACE_RING[game.PlaceId]
        if type(rings) == "string" then
            return { rings }
        end
        return rings or {}
    end

    local function fetchOnlineTas()
        if TAS_API == "" then
            return {}
        end
        local found = {}
        for _, ring in ipairs(currentRings()) do
            local body = httpGet(TAS_API .. ring:gsub(" ", "%%20"))
            if not body then
                return nil
            end
            local ok, list = pcall(function()
                return HttpService:JSONDecode(body)
            end)
            if not ok or type(list) ~= "table" then
                return nil
            end
            if type(list.message) == "string" and not list.message:find("Not Found", 1, true) then
                return nil
            end
            if list.message == nil then
                for _, item in ipairs(list) do
                    if type(item) == "table" and item.type == "file" and type(item.name) == "string" and item.name:sub(-5) == ".json" then
                        table.insert(found, {
                            name = item.name:sub(1, -6),
                            ring = ring,
                            url = item.download_url,
                            sha = type(item.sha) == "string" and item.sha:sub(1, 8) or "latest",
                            size = tonumber(item.size),
                        })
                    end
                end
            end
        end
        return found
    end

    local function listTasFiles()
        local files = {}
        if isfolder and listfiles and isfolder(TAS_FOLDER) then
            for _, path in ipairs(listfiles(TAS_FOLDER)) do
                if path:sub(-5) == ".json" and not path:match("[/\\]Keybinds%.json$") then
                    table.insert(files, path)
                end
            end
        end
        return files
    end

    local function readTasSource(entry)
        if entry.path then
            local ok, content = pcall(readfile, entry.path)
            return ok and content or nil
        end
        local prefix = ("%s_%s_"):format(entry.ring, entry.name)
        local cachePath = ("%s/%s%s.json"):format(TAS_CACHE, prefix, entry.sha)
        entry.cachePath = cachePath
        local okCached, cached = pcall(function()
            return isfile(cachePath) and readfile(cachePath) or nil
        end)
        if okCached and type(cached) == "string" and cached ~= "" and (not entry.size or #cached == entry.size) then
            return cached
        end
        notify("TAS", "Downloading " .. entry.name .. "...", 3)
        local content = entry.url and httpGet(entry.url)
        if not content then
            return nil
        end
        if entry.size and #content ~= entry.size then
            notify("TAS", "The download of " .. entry.name .. " was incomplete or outdated. Try again in a few minutes.", 6)
            return nil
        end
        pcall(writefile, cachePath, content)
        pcall(function()
            for _, path in ipairs(listfiles(TAS_CACHE)) do
                local fileName = path:match("([^/\\]+)$") or ""
                if fileName:sub(1, #prefix) == prefix and fileName ~= prefix .. entry.sha .. ".json" then
                    delfile(path)
                end
            end
        end)
        return content
    end

    local function loadTas(entry)
        local content = readTasSource(entry)
        if type(content) ~= "string" or content == "" then
            return nil
        end
        local okDecode, frames = pcall(function()
            return HttpService:JSONDecode(content)
        end)
        if not okDecode or type(frames) ~= "table" then
            if not entry.path and entry.cachePath then
                pcall(delfile, entry.cachePath)
            end
            return nil
        end
        if frames.v ~= 2 or type(frames.f) ~= "table" then
            return nil, "This TAS uses the old format, which Aery Hub no longer plays. Record it again with AeryTAS."
        end
        do
            local function unpackCFrame(row, start)
                local rotation = Vector3.new(row[start + 3], row[start + 4], row[start + 5])
                local cframe = CFrame.new(row[start], row[start + 1], row[start + 2])
                local angle = rotation.Magnitude
                if angle > 0.000001 then
                    cframe = cframe * CFrame.fromAxisAngle(rotation / angle, angle)
                end
                return { cframe:GetComponents() }
            end
            local fields = { z = "ZZoom", l = "LLock", a = "AAnim", o = "OObjects", k = "KKeys", m = "MMouse", w = "WWheel" }
            local unpacked = {}
            local state
            local okUnpack = pcall(function()
                for _, row in ipairs(frames.f) do
                    local frame = {
                        time = row[1],
                        CCFrame = unpackCFrame(row, 2),
                        CCameraCFrame = unpackCFrame(row, 8),
                        VVelocity = { row[14], row[15], row[16] },
                    }
                    local extra = row[17]
                    if type(extra) == "table" then
                        if extra.s ~= nil then
                            state = extra.s
                        end
                        for key, field in pairs(fields) do
                            if extra[key] ~= nil then
                                frame[field] = extra[key]
                            end
                        end
                    end
                    frame.SState = state
                    table.insert(unpacked, frame)
                end
            end)
            if not okUnpack or not unpacked[1] then
                return nil
            end
            if type(frames.k) == "table" then
                unpacked[1].OKeys = frames.k
            end
            frames = unpacked
        end
        local function validCFrame(list)
            if type(list) ~= "table" or #list < 12 then
                return false
            end
            for index = 1, 12 do
                if type(list[index]) ~= "number" then
                    return false
                end
            end
            return true
        end
        local normalized = {}
        for index, frame in ipairs(frames) do
            if type(frame) == "table" and validCFrame(frame.CCFrame) and validCFrame(frame.CCameraCFrame) then
                if type(frame.VVelocity) ~= "table" then
                    frame.VVelocity = { 0, 0, 0 }
                end
                frame.time = tonumber(frame.time) or index / 60
                table.insert(normalized, frame)
            end
        end
        if #normalized == 0 then
            return nil
        end
        if type(frames[1]) == "table" and type(frames[1].OKeys) == "table" then
            normalized[1].OKeys = frames[1].OKeys
        end
        return normalized
    end

    local playing = false
    local paused = false
    local pausedAt = 0
    local tasPauseButton
    local tasStatusLabel
    local TAS_STATUS_COLORS = { Idle = "#8C8C8C", Playing = "#5BE37D", Paused = "#FFD24A", Stopped = "#FF5A5A" }

    local function setTasStatus(status)
        if tasStatusLabel then
            tasStatusLabel:SetText(('Status: <font color="%s">%s</font>'):format(TAS_STATUS_COLORS[status], status))
        end
    end
    local frames, frameIndex, startTime
    local playConnection, healConnection
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
        local root = getRoot()
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

    local function updateTasPauseButton()
        if tasPauseButton then
            tasPauseButton:SetText(paused and "Resume" or "Pause")
        end
        if playing then
            setTasStatus(paused and "Paused" or "Playing")
        end
    end

    local buildAnimPlayback, applyAnimPlayback

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
    end

    local TasMotion = { zoomActive = false, minZoom = nil, maxZoom = nil, releaseAt = nil, humanoid = nil, platformStand = nil, lockController = nil, lockBefore = nil, intro = nil }

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
        if not frame or not getRoot() then
            return
        end
        local velocity = TasMotion.decode(frame).velocity
        local function push()
            local root = getRoot()
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
        local camera = workspace.CurrentCamera
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
        local root = getRoot()
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
        local camera = workspace.CurrentCamera
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

    local TasInput = { held = {}, warned = false, resumePending = false, cameraKeys = { LeftShift = true, RightShift = true, b2 = true, Left = true, Right = true }, VK = {
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
        local camera = workspace.CurrentCamera
        if not camera or type(point) ~= "table" then
            return
        end
        local size = camera.ViewportSize
        pcall(mousemoveabs, math.floor(size.X * (point[1] or 0.5) + 0.5), math.floor(size.Y * (point[2] or 0.5) + 0.5))
    end

    function TasInput.play(enabled, keys, mouse)
        if not enabled or (#keys == 0 and not mouse) then
            return
        end
        if not TasInput.available() then
            if not TasInput.warned then
                TasInput.warned = true
                notify("TAS", "Your executor can't send mouse or key input, so it won't be replayed.", 5)
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

    local function setTasPaused(state)
        if not playing or state == paused then
            return
        end
        if state then
            paused = true
            pausedAt = tick()
            stopTasAnimator()
            TasInput.releaseAll()
            TasMotion.release()
            TasMotion.handOff(frames[math.max(frameIndex - 1, 1)])
        else
            startTime = startTime + (tick() - pausedAt)
            paused = false
            TasInput.resumePending = true
            startTasAnimator()
            TasMotion.hold()
        end
        updateTasPauseButton()
    end

    local tasKillbricks = { originals = setmetatable({}, { __mode = "k" }), watches = {}, scan = 0 }

    local function setKillbricksTouchable(state)
        tasKillbricks.scan = tasKillbricks.scan + 1
        local myScan = tasKillbricks.scan
        for _, watch in ipairs(tasKillbricks.watches) do
            watch:Disconnect()
        end
        tasKillbricks.watches = {}
        if state then
            for part, original in pairs(tasKillbricks.originals) do
                pcall(function()
                    if part.Parent then
                        part.CanTouch = original
                    end
                end)
            end
            tasKillbricks.originals = setmetatable({}, { __mode = "k" })
            return
        end
        local function disable(part)
            if part:IsA("BasePart") and tasKillbricks.originals[part] == nil and isDamageBrick(part) then
                tasKillbricks.originals[part] = part.CanTouch
                part.CanTouch = false
            end
        end
        local function keepGoing()
            return tasKillbricks.scan == myScan
        end
        for _, folderName in ipairs({ "Towers", "ClientParts", "Obbies" }) do
            local folder = workspace:FindFirstChild(folderName)
            if folder then
                task.spawn(function()
                    pcall(forEachSlowly, folder:GetDescendants(), disable, keepGoing)
                end)
                table.insert(tasKillbricks.watches, folder.DescendantAdded:Connect(function(part)
                    task.defer(function()
                        pcall(disable, part)
                    end)
                end))
            end
        end
    end

    local tasObjects, tasAnims

    local tasScroll = { folder = "Aery Hub/TAS/AHK", request = "Aery Hub/TAS/AHK/Request", recorderLoading = false }

    function tasScroll.available()
        local ok, exists = pcall(function()
            return isfolder(tasScroll.folder)
        end)
        return ok and exists == true
    end

    function tasScroll.send(text)
        if text == "" or not tasScroll.available() then
            return false
        end
        pcall(function()
            local existing = isfile(tasScroll.request) and readfile(tasScroll.request) or ""
            writefile(tasScroll.request, existing ~= "" and existing .. "," .. text or text)
        end)
        return true
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
        local playback = { tracks = {}, claimed = {}, count = 0, released = false }
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

    local function stopTas()
        if playConnection then
            playConnection = nil
            pcall(function()
                RunService:UnbindFromRenderStep("AeryHubTasPlayback")
            end)
        end
        TasInput.releaseAll()
        TasMotion.release()
        if playing and tasScroll.available() then
            pcall(writefile, tasScroll.request, "")
        end
        if healConnection then
            healConnection:Disconnect()
            healConnection = nil
        end
        stopTasAnimator()
        stopObjectPlayback(tasObjects)
        tasObjects = nil
        tasAnims = nil
        if playing then
            local root = getRoot()
            if root then
                root.Anchored = false
            end
        end
        setKillbricksTouchable(true)
        local wasPlaying = playing
        playing = false
        paused = false
        updateTasPauseButton()
        if wasPlaying then
            setTasStatus("Stopped")
        end
    end

    local function playTas(tasFrames)
        if playing then
            stopTas()
            task.wait(0.1)
        end
        local startHumanoid = getHumanoid()
        if not getRoot() or not startHumanoid or startHumanoid.Health <= 0 then
            notify("TAS", "You need a living character to play a TAS.")
            return
        end
        frames = tasFrames
        frameIndex = 1
        startTime = tick()
        paused = false
        playing = true
        updateTasPauseButton()
        setKillbricksTouchable(false)

        local damageEvent = findDamageEvent()
        if healConnection then
            healConnection:Disconnect()
            healConnection = nil
        end
        if damageEvent then
            local lastHeal = 0
            healConnection = RunService.Heartbeat:Connect(function()
                local humanoid = playing and (not Toggles.TasHeal or Toggles.TasHeal.Value) and getHumanoid()
                if not humanoid or humanoid.Health <= 0 or humanoid.Health >= humanoid.MaxHealth or os.clock() - lastHeal < 0.1 then
                    return
                end
                lastHeal = os.clock()
                pcall(function()
                    damageEvent:FireServer(-99999)
                end)
            end)
        end

        startTasAnimator()
        tasAnims = buildAnimPlayback(frames)
        if (not Toggles.TasReplayScroll or Toggles.TasReplayScroll.Value) and not tasScroll.available() then
            for _, frame in ipairs(frames) do
                if frame.WWheel then
                    notify("TAS", "This TAS has mouse-wheel scrolls, but AHKConnection isn't set up, so the zoom won't be replayed.", 5)
                    break
                end
            end
        end
        if not Toggles.TasSyncObjects or Toggles.TasSyncObjects.Value then
            tasObjects = buildObjectPlayback(frames)
        end

        if tasScroll.available() then
            pcall(writefile, tasScroll.request, "")
        end
        TasMotion.prepare(frames)
        TasMotion.hold()
        playConnection = true
        startTime = tick() - (tonumber(frames[1].time) or 0)
        RunService:BindToRenderStep("AeryHubTasPlayback", Enum.RenderPriority.Camera.Value - 1, function(deltaTime)
            if not playing then
                return
            end
            if paused then
                if tasObjects and not tasObjects.released then
                    stopObjectPlayback(tasObjects)
                    tasObjects.released = true
                end
                return
            end
            if tasObjects then
                tasObjects.released = false
            end
            local liveHumanoid = getHumanoid()
            if not getRoot() or not liveHumanoid or liveHumanoid.Health <= 0 then
                startTime = startTime + deltaTime
                return
            end
            local elapsed = tick() - startTime
            local jumped = false
            local wheel = {}
            local keys = {}
            local mouse
            if TasInput.resumePending then
                TasInput.resumePending = false
                TasInput.restore(frames, frameIndex, Toggles.TasReplayInput and Toggles.TasReplayInput.Value)
            end
            while frameIndex <= #frames and (frames[frameIndex].time or 0) <= elapsed do
                local passed = frames[frameIndex]
                if tasJumped(frames[frameIndex - 1], passed) then
                    jumped = true
                end
                if type(passed.WWheel) == "string" then
                    table.insert(wheel, passed.WWheel)
                end
                if type(passed.KKeys) == "string" then
                    table.insert(keys, passed.KKeys)
                end
                if type(passed.MMouse) == "table" then
                    mouse = passed.MMouse
                end
                frameIndex = frameIndex + (1)
            end
            if #wheel > 0 and (not Toggles.TasReplayScroll or Toggles.TasReplayScroll.Value) then
                tasScroll.send(table.concat(wheel, ","))
            end
            TasInput.play(Toggles.TasReplayInput and Toggles.TasReplayInput.Value, keys, mouse)
            local current = frames[math.max(frameIndex - 1, 1)]
            if current then
                if TasMotion.humanoid ~= getHumanoid() then
                    TasMotion.hold()
                end
                TasMotion.apply(frames, math.max(frameIndex - 1, 1), elapsed)
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
                if tasAnims then
                    applyAnimPlayback(tasAnims, frameIndex - 1, elapsed)
                else
                    updateTasAnimator(current, jumped, elapsed)
                end
            end
            if tasObjects then
                applyObjectPlayback(tasObjects, elapsed)
            end
            if frameIndex > #frames then
                local last = frames[#frames]
                stopTas()
                TasMotion.handOff(last)
            end
        end)
    end

    local onlineTas = {}
    local entryByName = {}

    local function tasNames()
        local names = {}
        entryByName = {}
        local multiRing = #currentRings() > 1
        for _, entry in ipairs(onlineTas) do
            local label = multiRing and ("%s (%s)"):format(entry.name, areaName(entry.ring)) or entry.name
            table.insert(names, label)
            entryByName[label] = entry
        end
        for _, path in ipairs(listTasFiles()) do
            local label = "[Local] " .. (path:match("([^/\\]+)%.json$") or "Unknown")
            table.insert(names, label)
            entryByName[label] = { path = path, name = label }
        end
        return names
    end

    local rings = currentRings()
    local RingLabel = TasBox:AddLabel(#rings > 0 and ("Area: %s (loading...)"):format(areaNames(rings)) or "Area: Unknown")
    tasStatusLabel = TasBox:AddLabel("")
    setTasStatus("Idle")

    local TasDropdown = TasBox:AddDropdown("TASDropdown", {
        Tooltip = "Selects the TAS that Play TAS plays.",
        Values = tasNames(),
        Default = 1,
        Multi = false,
        Searchable = true,
    })

    TasDropdown:OnChanged(function()
        if TasDropdown.Menu then
            TasDropdown.Menu:Close()
        end
    end)

    local refreshing = false
    local function refreshTas()
        if refreshing then
            return
        end
        refreshing = true
        task.spawn(function()
            if #rings > 0 then
                local fetched = fetchOnlineTas()
                if fetched then
                    onlineTas = fetched
                    RingLabel:SetText(("Area: %s (%d TAS)"):format(areaNames(rings), #onlineTas))
                else
                    RingLabel:SetText(("Area: %s (couldn't reach GitHub)"):format(areaNames(rings)))
                end
            end
            TasDropdown:SetValues(tasNames())
            refreshing = false
        end)
    end

    local loading = false
    local function playSelected()
        local entry = entryByName[TasDropdown.Value]
        if not entry then
            notify("TAS", "No TAS selected.")
            return
        end
        if loading then
            return
        end
        loading = true
        task.spawn(function()
            local tasFrames, loadProblem = loadTas(entry)
            if not tasFrames or #tasFrames == 0 then
                loading = false
                notify("TAS", loadProblem or ("Couldn't load " .. tostring(TasDropdown.Value)), loadProblem and 6 or 3)
                return
            end
            local ok, problem = pcall(playTas, tasFrames)
            loading = false
            if not ok then
                stopTas()
                notify("TAS", "Couldn't play this TAS: " .. tostring(problem), 6)
            end
        end)
    end

    TasBox:AddDivider()
    TasBox:AddButton({ Text = "Play TAS", Tooltip = "Plays the selected TAS.", Func = playSelected, DoubleClick = false })
    tasPauseButton = TasBox:AddButton({
        Text = "Pause",
        DoubleClick = false,
        Tooltip = "Pauses or resumes the TAS.",
        Func = function()
            setTasPaused(not paused)
        end,
    })
    tasPauseButton:AddButton({ Text = "Stop", Tooltip = "Stops the TAS.", Func = stopTas, DoubleClick = false })
    local PlaybackBox = Tabs.TAS:AddRightGroupbox("Playback")
    PlaybackBox:AddToggle("TasSyncObjects", {
        Text = "Sync Client Objects",
        Default = true,
        Tooltip = "Moves platforms and spinners the way they moved in the recording.",
    })
    PlaybackBox:AddToggle("TasReplayScroll", {
        Text = "Replay Scroll (AHK)",
        Default = true,
        Tooltip = "Replays the TAS's scroll zoom. Needs AHKConnection running.",
    })
    local ahkStatusLabel = PlaybackBox:AddLabel("")
    task.spawn(function()
        local lastBeat
        while not Library.Unloaded do
            local ok, beat = pcall(readfile, tasScroll.folder .. "/Alive")
            local connected = ok and beat ~= nil and lastBeat ~= nil and beat ~= lastBeat
            lastBeat = ok and beat or nil
            ahkStatusLabel:SetText(('AHKConnection: <font color="%s">%s</font>'):format(connected and TAS_STATUS_COLORS.Playing or TAS_STATUS_COLORS.Stopped, connected and "Connected" or "Not connected"))
            task.wait(2)
        end
    end)
    PlaybackBox:AddToggle("TasReplayInput", {
        Text = "Replay Mouse &amp; Keys",
        Default = false,
        Tooltip = "Moves your cursor and presses the keys and mouse buttons recorded in the TAS. Sends real input to the Roblox window.",
        Callback = function(value)
            if not value then
                TasInput.releaseAll()
            end
        end,
    })
    PlaybackBox:AddToggle("TasHeal", {
        Text = "Heal During TAS",
        Default = true,
        Tooltip = "Heals you back to full health when you take damage while a TAS plays.",
    })
    table.insert(panicHandlers, stopTas)
    TasBox:AddDivider()
    TasBox:AddButton({
        Text = "Refresh TAS",
        DoubleClick = false,
        Tooltip = "Reloads the TAS list.",
        Func = refreshTas,
    }):AddButton({
        Text = "Open AeryTAS",
        DoubleClick = false,
        Tooltip = "Loads AeryTAS in its own window to record runs.",
        Func = function()
            if tasScroll.recorderLoading then
                return
            end
            tasScroll.recorderLoading = true
            task.delay(5, function()
                tasScroll.recorderLoading = false
            end)
            task.spawn(function()
                local ok, problem = pcall(function()
                    loadstring(game:HttpGet("https://api.luarmor.net/files/v3/loaders/e6126f89dac35d2b395034dfcfeee8cf.lua"))()
                end)
                tasScroll.recorderLoading = false
                if not ok then
                    notify("AeryTAS", "Couldn't load AeryTAS: " .. tostring(problem), 6)
                end
            end)
        end,
    })

    refreshTas()

    local KeybindBox = Tabs.TAS:AddRightGroupbox("Keybinds")
    KeybindBox:AddLabel("Play Key"):AddKeyPicker("TASPlayKey", {
        Default = "P",
        Mode = "Press",
        Text = "Play TAS",
        SyncToggleState = false,
        NoUI = false,
    })
    KeybindBox:AddLabel("Pause Key"):AddKeyPicker("TASPauseKey", {
        Default = "K",
        Mode = "Press",
        Text = "Pause / Resume TAS",
        SyncToggleState = false,
        NoUI = false,
    })
    KeybindBox:AddLabel("Stop Key"):AddKeyPicker("TASStopKey", {
        Default = "O",
        Mode = "Press",
        Text = "Stop TAS",
        SyncToggleState = false,
        NoUI = false,
    })

    local inputConnection = UserInputService.InputBegan:Connect(function(input)
        if Library.Unloaded or input.KeyCode == Enum.KeyCode.Unknown or UserInputService:GetFocusedTextBox() then
            return
        end
        local key = input.KeyCode.Name
        if key == Options.TASPlayKey.Value then
            playSelected()
        elseif key == Options.TASStopKey.Value then
            stopTas()
        elseif key == Options.TASPauseKey.Value then
            setTasPaused(not paused)
        end
    end)

    Library:OnUnload(function()
        inputConnection:Disconnect()
        stopTas()
    end)
end

if game.GameId == ETOH_GAME_ID then
    task.spawn(function()
        local EXTENDED_DIFFICULTIES = { Horrific = true, Unreal = true }
        local ok, TowerLibrary, AreaLibrary = pcall(function()
            local framework = require(ReplicatedStorage:WaitForChild("Framework"))
            return framework.Library.TowerLibrary, framework.Library.AreaLibrary
        end)
        if not ok or type(TowerLibrary) ~= "table" or type(TowerLibrary.ShouldDisplayTower) ~= "function" or Library.Unloaded then
            return
        end
        local original = TowerLibrary.ShouldDisplayTower
        local function extended(self, name, showEverything)
            if original(self, name, showEverything) then
                return true
            end
            if not showEverything or type(name) ~= "string" or name:find(":") then
                return false
            end
            local data = self.Data.Towers[name]
            if type(data) ~= "table" or not EXTENDED_DIFFICULTIES[data.Difficulty] then
                return false
            end
            local tags = type(data.Tags) == "table" and data.Tags or {}
            if tags.CurrentMonthly or tags.Private then
                return false
            end
            local area = tags.Area
            if area and type(AreaLibrary) == "table" then
                local areas = AreaLibrary.Data
                local info = areas.Areas[area] or (areas.Subrealms and areas.Subrealms[area]) or (areas.MiscAreas and areas.MiscAreas[area])
                if not info or info.Unreleased then
                    return false
                end
            end
            return true
        end
        TowerLibrary.ShouldDisplayTower = extended
        Library:OnUnload(function()
            if TowerLibrary.ShouldDisplayTower == extended then
                TowerLibrary.ShouldDisplayTower = original
            end
        end)
    end)
end

local DevelopersBox = Tabs.Credits:AddLeftGroupbox("Developers", "hammer")
local CommunityBox = Tabs.Credits:AddRightGroupbox("Community", "messages-square")

DevelopersBox:AddLabel('[<font color="rgb(230,172,211)">aeryliaaa</font>] Owner')

CommunityBox:AddButton({
    Text = "Copy Discord Server",
    DoubleClick = false,
    Tooltip = "Copies our Discord invite link.",
    Func = function()
        if setclipboard then
            setclipboard("https://discord.gg/gagjSutR8M")
            notify("Discord", "Copied to your clipboard!")
        else
            notify("Discord", "Your executor doesn't support setclipboard.")
            notify("Discord", "Our Discord Server: https://discord.gg/gagjSutR8M", 5)
        end
    end,
})

local MenuBox = Tabs["UI Settings"]:AddLeftGroupbox("Menu", "wrench")

MenuBox:AddToggle("ShowCustomCursor", {
    Text = "Custom Cursor",
    Tooltip = "Shows the menu's own cursor while the menu is open.",
    Default = true,
    Callback = function(value)
        Library.ShowCustomCursor = value
    end,
})

MenuBox:AddToggle("AlwaysOnTop", {
    Text = "Always On Top",
    Tooltip = "Keeps the menu above other windows.",
    Default = false,
    Callback = function(value)
        if Window.SetAlwaysOnTop then
            Window:SetAlwaysOnTop(value)
        end
    end,
})

MenuBox:AddDropdown("NotificationSide", {
    Values = { "Left", "Right" },
    Default = "Right",
    Text = "Notification Side",
    Tooltip = "Sets which side of the screen notifications appear on.",
    Callback = function(value)
        Library:SetNotifySide(value)
    end,
})

MenuBox:AddDropdown("DPIDropdown", {
    Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
    Default = "100%",
    Text = "DPI Scale",
    Tooltip = "Sets the menu's size.",
    Callback = function(value)
        Library:SetDPIScale(tonumber((value:gsub("%%", ""))))
    end,
})

MenuBox:AddSlider("UICornerSlider", {
    Text = "Corner Radius",
    Tooltip = "Sets how round the menu's corners are.",
    Default = 4,
    Min = 0,
    Max = 20,
    Rounding = 0,
    Callback = function(value)
        if Window.SetCornerRadius then
            Window:SetCornerRadius(value)
        end
    end,
})

MenuBox:AddToggle("AutoExecute", {
    Text = "Auto Execute",
    Default = false,
    Tooltip = "Runs Aery Hub again after you teleport to another area or server.",
    Callback = function(value)
        local queue = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
        if value and type(queue) ~= "function" then
            notify("Auto Execute", "Your executor doesn't support queue_on_teleport.", 4)
        end
    end,
})
do
    local AUTO_EXECUTE_SOURCE = 'local g = getgenv and getgenv() or _G\n'
        .. 'if g.AeryHubAutoRan then return end\n'
        .. 'g.AeryHubAutoRan = true\n'
        .. 'g.AeryHubAutoExecute = true\n'
        .. 'if not game:IsLoaded() then game.Loaded:Wait() end\n'
        .. 'loadstring(game:HttpGet("https://api.luarmor.net/files/v3/loaders/d41c92d6b584febfaa3c379a64fd2bac.lua"))()\n'
    local autoExecuteConnection = LocalPlayer.OnTeleport:Connect(function(state)
        if state ~= Enum.TeleportState.Started and state ~= Enum.TeleportState.InProgress then
            return
        end
        if not (Toggles.AutoExecute and Toggles.AutoExecute.Value) then
            return
        end
        local queue = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
        if type(queue) == "function" then
            local key = getgenv and getgenv().script_key
            pcall(queue, (type(key) == "string" and "script_key = " .. string.format("%q", key) .. "\n" or "") .. AUTO_EXECUTE_SOURCE)
        end
    end)
    Library:OnUnload(function()
        autoExecuteConnection:Disconnect()
    end)
end

MenuBox:AddDivider()
MenuBox:AddLabel("Menu Key"):AddKeyPicker("MenuKeybind", { Default = "Delete", NoUI = true, Text = "Menu Key" })
local sliderDefaults = {}
for id, option in pairs(Options) do
    if option.Type == "Slider" then
        sliderDefaults[id] = option.Value
    end
end

do
    local env = getgenv and getgenv() or _G
    local function unloadHub()
        if Library.Unloaded then
            return
        end
        for _, toggle in pairs(Toggles) do
            if toggle.Value then
                pcall(toggle.SetValue, toggle, false)
            end
        end
        for id, value in pairs(sliderDefaults) do
            local option = Options[id]
            if option and option.Value ~= value then
                pcall(option.SetValue, option, value)
            end
        end
        Library:Unload()
    end

    MenuBox:AddButton({
        Text = "Unload",
        DoubleClick = false,
        Tooltip = "Turns every feature off, puts everything back, and removes Aery Hub.",
        Func = unloadHub,
    })

    env.AeryHubUnload = unloadHub
    Library:OnUnload(function()
        if env.AeryHubUnload == unloadHub then
            env.AeryHubUnload = nil
        end
    end)
end

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
local AERY_THEMES = {
    { "Monochrome", { FontColor = "ffffff", MainColor = "141414", AccentColor = "ffffff", BackgroundColor = "000000", OutlineColor = "2a2a2a" } },
    { "Lavender", { FontColor = "f1e8ff", MainColor = "211a2c", AccentColor = "b57edc", BackgroundColor = "16111f", OutlineColor = "3e3054" } },
    { "Pumpkin", { FontColor = "ffe3c4", MainColor = "24140a", AccentColor = "ff7518", BackgroundColor = "160c05", OutlineColor = "4a2a12" } },
    { "Midnight", { FontColor = "e6ecff", MainColor = "131a2b", AccentColor = "4f7cff", BackgroundColor = "0b0f1a", OutlineColor = "25304d" } },
    { "Mint", { FontColor = "e6fff4", MainColor = "13201d", AccentColor = "3ddc97", BackgroundColor = "0b1412", OutlineColor = "22392f" } },
    { "Crimson", { FontColor = "ffe6e7", MainColor = "211214", AccentColor = "e5484d", BackgroundColor = "140a0b", OutlineColor = "3d2023" } },
}

for name in pairs(ThemeManager.BuiltInThemes) do
    if name ~= "Default" then
        ThemeManager.BuiltInThemes[name] = nil
    end
end

for index, theme in ipairs(AERY_THEMES) do
    local colors = {}
    for key, value in pairs(theme[2]) do
        colors[key] = value
    end
    colors.BackgroundImage = ""
    ThemeManager.BuiltInThemes[theme[1]] = { index / 10 + 1, colors }
end

ThemeManager:SetDefaultTheme(AERY_THEMES[1][2])
ThemeManager:SetFolder("Aery Hub")
SaveManager:SetFolder(IS_CSCD and "Aery Hub/CSCD" or IS_TOR and "Aery Hub/TOR" or IS_ASTN and "Aery Hub/ASTN" or "Aery Hub/EToH")
SaveManager:SetSubFolder(IS_CSCD and "CSCD" or IS_TOR and "TOR" or IS_ASTN and "ASTN" or "EToH")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()
if getgenv and getgenv().AeryHubAutoExecute and Toggles.AutoExecute and not Toggles.AutoExecute.Value then
    Toggles.AutoExecute:SetValue(true)
end
Library:Toggle(true)
