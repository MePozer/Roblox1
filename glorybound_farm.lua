--[[
    GloryBound Farm
    - AutoFarm: телепорт к ближайшему мобу (на голову / чуть выше) + автоатака
    - KillAura: атака всех мобов в радиусе
    - Перетаскиваемое окно, слайдеры высоты, отступа и радиуса
    - F — AutoFarm, G — KillAura

    Вставлять в executor, находясь в игре.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    AutoFarm = false,
    KillAura = false,

    Height = 2.5,          -- высота над головой моба
    Standoff = 2.5,        -- горизонтальный отступ от головы
    AuraRadius = 20,       -- радиус KillAura

    TeleportCooldown = 0.35,
    AttackDelay = 0.12,
    MaxTargetDistance = 400,

    UseWhitelist = false,
    MobWhitelist = {
        "Undead", "Skeleton", "Zombie", "Brute", "War Lion",
        "Cerberus", "Enemy", "Mob", "Monster", "Barbarian", "Raider",
    },
    MobBlacklist = {
        "Dummy", "Train", "Shop", "Merchant", "Blacksmith",
        "Quest", "Friendly", "Ally", "Bench", "Barbell", "Dumbbell",
    },

    AutoEquip = true,
    WeaponPatterns = {
        "Sword", "Blade", "Spear", "Bow", "Axe", "Mace",
        "Dagger", "Weapon", "Gladius",
    },
}

local state = {
    target = nil,
    auraCount = 0,
}

local ui = {}
local screenGui = nil
local lastTeleport = 0
local lastScan = 0
local cachedMobs = {}

local guiParent
if gethui then
    pcall(function()
        guiParent = gethui()
    end)
end
if not guiParent then
    pcall(function()
        guiParent = game:GetService("CoreGui")
    end)
end
if not guiParent then
    guiParent = LocalPlayer:WaitForChild("PlayerGui")
end

if getgenv then
    local old = guiParent:FindFirstChild("GloryBoundFarm")
    if old then old:Destroy() end
    getgenv().GloryBoundFarmLoaded = true
end

local function getAlive()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if hum and root and hum.Health > 0 then
        return char, hum, root
    end
    return nil
end

local function containsAny(name, list)
    local lower = string.lower(name)
    for _, pattern in ipairs(list) do
        if string.find(lower, string.lower(pattern), 1, true) then
            return true
        end
    end
    return false
end

local function isMob(model)
    if containsAny(model.Name, CONFIG.MobBlacklist) then return false end
    if CONFIG.UseWhitelist then
        return containsAny(model.Name, CONFIG.MobWhitelist)
    end
    return true
end

local function getHead(model)
    return model:FindFirstChild("Head")
        or model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
end

local function collectMobs()
    local result = {}
    local char, _, myRoot = getAlive()
    if not myRoot then return result end

    local seen = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj ~= char and not Players:GetPlayerFromCharacter(obj) then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            if hum and not seen[hum] and hum.Health > 0 and isMob(obj) then
                local head = getHead(obj)
                local root = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart or head
                if head and root then
                    local dist = (root.Position - myRoot.Position).Magnitude
                    if dist <= CONFIG.MaxTargetDistance then
                        seen[hum] = true
                        table.insert(result, {
                            model = obj,
                            humanoid = hum,
                            head = head,
                            root = root,
                            distance = dist,
                        })
                    end
                end
            end
        end
    end

    table.sort(result, function(a, b) return a.distance < b.distance end)
    return result
end

local function scanMobs()
    if os.clock() - lastScan < 0.4 then
        return cachedMobs
    end
    cachedMobs = collectMobs()
    lastScan = os.clock()
    return cachedMobs
end

local function isValid(mob)
    if not mob or not mob.model or not mob.model.Parent then return false end
    local hum = mob.model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    return true
end

local function getWeapon()
    local char = LocalPlayer.Character
    if not char then return nil end

    local equipped = char:FindFirstChildOfClass("Tool")
    if equipped then return equipped end

    if CONFIG.AutoEquip then
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if backpack and hum then
            for _, item in ipairs(backpack:GetChildren()) do
                if item:IsA("Tool") and containsAny(item.Name, CONFIG.WeaponPatterns) then
                    pcall(function() hum:EquipTool(item) end)
                    if item.Parent ~= char then
                        pcall(function() item.Parent = char end)
                    end
                    task.wait(0.05)
                    return item
                end
            end
        end
    end
    return nil
end

local function attackMob(mob)
    if not isValid(mob) then return end
    local _, _, myRoot = getAlive()
    if not myRoot then return end

    local head = mob.model:FindFirstChild("Head") or mob.head
    if head then
        local look = Vector3.new(head.Position.X, myRoot.Position.Y, head.Position.Z)
        if (look - myRoot.Position).Magnitude > 0.1 then
            myRoot.CFrame = CFrame.lookAt(myRoot.Position, look)
        end
    end

    local tool = getWeapon()
    if tool then
        pcall(function() tool:Activate() end)
        return
    end

    if type(mouse1click) == "function" then
        pcall(mouse1click)
    elseif type(mouse1press) == "function" then
        pcall(mouse1press)
        task.wait(0.03)
        if type(mouse1release) == "function" then
            pcall(mouse1release)
        end
    end
end

local function teleportToMob(mob)
    if not isValid(mob) then return false end
    local _, _, myRoot = getAlive()
    if not myRoot then return false end

    local head = mob.model:FindFirstChild("Head") or mob.head
    if not head then return false end

    local headPos = head.Position
    local flat = Vector3.new(myRoot.Position.X - headPos.X, 0, myRoot.Position.Z - headPos.Z)
    if flat.Magnitude < 0.05 then
        flat = Vector3.new(0, 0, 1)
    end

    local targetPos = headPos + Vector3.new(0, CONFIG.Height, 0) + flat.Unit * CONFIG.Standoff
    local lookTarget = Vector3.new(headPos.X, targetPos.Y, headPos.Z)
    if (lookTarget - targetPos).Magnitude < 0.05 then
        lookTarget = targetPos + Vector3.new(0, 0, -1)
    end

    myRoot.CFrame = CFrame.lookAt(targetPos, lookTarget)
    lastScan = 0
    return true
end

local function createUI()
    local screen = Instance.new("ScreenGui")
    screen.Name = "GloryBoundFarm"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local ok = pcall(function()
        screen.Parent = guiParent
    end)
    if not ok then
        screen.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, 300, 0, 352)
    main.Position = UDim2.new(0.5, -150, 0.16, 0)
    main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    main.BorderSizePixel = 0
    main.Parent = screen

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 10)
    mainCorner.Parent = main

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(62, 62, 74)
    mainStroke.Thickness = 1
    mainStroke.Parent = main

    local header = Instance.new("TextButton")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = Color3.fromRGB(31, 31, 39)
    header.BorderSizePixel = 0
    header.Text = ""
    header.AutoButtonColor = false
    header.Parent = main

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 10)
    headerCorner.Parent = header

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -90, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "GloryBound Farm"
    title.TextColor3 = Color3.fromRGB(235, 180, 80)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.Parent = header

    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 26, 0, 26)
    closeButton.Position = UDim2.new(1, -34, 0, 5)
    closeButton.BackgroundColor3 = Color3.fromRGB(45, 45, 56)
    closeButton.Text = "x"
    closeButton.TextColor3 = Color3.fromRGB(220, 220, 225)
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextSize = 16
    closeButton.AutoButtonColor = false
    closeButton.Parent = header

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 6)
    closeCorner.Parent = closeButton

    closeButton.MouseButton1Click:Connect(function()
        screen:Destroy()
        if getgenv then getgenv().GloryBoundFarmLoaded = false end
    end)

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -32, 1, -48)
    content.Position = UDim2.new(0, 16, 0, 44)
    content.BackgroundTransparency = 1
    content.Parent = main

    local autoLabel = Instance.new("TextLabel")
    autoLabel.Size = UDim2.new(1, -90, 0, 28)
    autoLabel.Position = UDim2.new(0, 0, 0, 0)
    autoLabel.BackgroundTransparency = 1
    autoLabel.Text = "AutoFarm (телепорт к мобу)"
    autoLabel.TextColor3 = Color3.fromRGB(225, 225, 232)
    autoLabel.TextXAlignment = Enum.TextXAlignment.Left
    autoLabel.Font = Enum.Font.Gotham
    autoLabel.TextSize = 13
    autoLabel.Parent = content

    local autoButton = Instance.new("TextButton")
    autoButton.Size = UDim2.new(0, 70, 0, 28)
    autoButton.Position = UDim2.new(1, -70, 0, 0)
    autoButton.BackgroundColor3 = Color3.fromRGB(55, 55, 66)
    autoButton.Text = "OFF"
    autoButton.TextColor3 = Color3.fromRGB(220, 220, 226)
    autoButton.Font = Enum.Font.GothamBold
    autoButton.TextSize = 12
    autoButton.AutoButtonColor = false
    autoButton.Parent = content

    local autoCorner = Instance.new("UICorner")
    autoCorner.CornerRadius = UDim.new(0, 6)
    autoCorner.Parent = autoButton

    local auraLabel = Instance.new("TextLabel")
    auraLabel.Size = UDim2.new(1, -90, 0, 28)
    auraLabel.Position = UDim2.new(0, 0, 0, 38)
    auraLabel.BackgroundTransparency = 1
    auraLabel.Text = "KillAura (все в радиусе)"
    auraLabel.TextColor3 = Color3.fromRGB(225, 225, 232)
    auraLabel.TextXAlignment = Enum.TextXAlignment.Left
    auraLabel.Font = Enum.Font.Gotham
    auraLabel.TextSize = 13
    auraLabel.Parent = content

    local auraButton = Instance.new("TextButton")
    auraButton.Size = UDim2.new(0, 70, 0, 28)
    auraButton.Position = UDim2.new(1, -70, 0, 38)
    auraButton.BackgroundColor3 = Color3.fromRGB(55, 55, 66)
    auraButton.Text = "OFF"
    auraButton.TextColor3 = Color3.fromRGB(220, 220, 226)
    auraButton.Font = Enum.Font.GothamBold
    auraButton.TextSize = 12
    auraButton.AutoButtonColor = false
    auraButton.Parent = content

    local auraCorner = Instance.new("UICorner")
    auraCorner.CornerRadius = UDim.new(0, 6)
    auraCorner.Parent = auraButton

    local function makeSlider(y, labelText, minValue, maxValue, stepValue, key, formatString)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 46)
        row.Position = UDim2.new(0, 0, 0, y)
        row.BackgroundTransparency = 1
        row.Parent = content

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -60, 0, 18)
        label.BackgroundTransparency = 1
        label.Text = labelText
        label.TextColor3 = Color3.fromRGB(200, 200, 210)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.Gotham
        label.TextSize = 12
        label.Parent = row

        local valueLabel = Instance.new("TextLabel")
        valueLabel.Size = UDim2.new(0, 50, 0, 18)
        valueLabel.Position = UDim2.new(1, -50, 0, 0)
        valueLabel.BackgroundTransparency = 1
        valueLabel.Text = string.format(formatString, CONFIG[key])
        valueLabel.TextColor3 = Color3.fromRGB(235, 180, 80)
        valueLabel.TextXAlignment = Enum.TextXAlignment.Right
        valueLabel.Font = Enum.Font.GothamBold
        valueLabel.TextSize = 12
        valueLabel.Parent = row

        local track = Instance.new("TextButton")
        track.Size = UDim2.new(1, 0, 0, 8)
        track.Position = UDim2.new(0, 0, 0, 24)
        track.BackgroundColor3 = Color3.fromRGB(52, 52, 62)
        track.BorderSizePixel = 0
        track.Text = ""
        track.AutoButtonColor = false
        track.Parent = row

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(1, 0)
        trackCorner.Parent = track

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(235, 180, 80)
        fill.BorderSizePixel = 0
        fill.Parent = track

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(1, 0)
        fillCorner.Parent = fill

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 14, 0, 14)
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.Position = UDim2.new(0, 0, 0.5, 0)
        knob.BackgroundColor3 = Color3.fromRGB(245, 245, 248)
        knob.BorderSizePixel = 0
        knob.ZIndex = 2
        knob.Parent = track

        local knobCorner = Instance.new("UICorner")
        knobCorner.CornerRadius = UDim.new(1, 0)
        knobCorner.Parent = knob

        local dragging = false

        local function setFromX(x)
            local width = math.max(track.AbsoluteSize.X, 1)
            local rel = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
            local raw = minValue + (maxValue - minValue) * rel
            local value = math.floor(raw / stepValue + 0.5) * stepValue
            value = math.clamp(value, minValue, maxValue)
            CONFIG[key] = value
            valueLabel.Text = string.format(formatString, value)
            local pos = (value - minValue) / (maxValue - minValue)
            fill.Size = UDim2.new(pos, 0, 1, 0)
            knob.Position = UDim2.new(pos, 0, 0.5, 0)
        end

        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                setFromX(input.Position.X)
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                setFromX(input.Position.X)
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)

        local initialPos = (CONFIG[key] - minValue) / (maxValue - minValue)
        fill.Size = UDim2.new(initialPos, 0, 1, 0)
        knob.Position = UDim2.new(initialPos, 0, 0.5, 0)

        return row
    end

    makeSlider(80, "Высота над головой", 0, 15, 0.5, "Height", "%.1f")
    makeSlider(132, "Отступ от головы", 0, 15, 0.5, "Standoff", "%.1f")
    makeSlider(184, "Радиус KillAura", 5, 60, 1, "AuraRadius", "%.0f")

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, 0, 0, 44)
    status.Position = UDim2.new(0, 0, 0, 236)
    status.BackgroundTransparency = 1
    status.Text = "Цель: -\nМобов в радиусе: 0"
    status.TextColor3 = Color3.fromRGB(160, 160, 172)
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.TextWrapped = true
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.Parent = content

    local hint = Instance.new("TextLabel")
    hint.Size = UDim2.new(1, 0, 0, 18)
    hint.Position = UDim2.new(0, 0, 0, 284)
    hint.BackgroundTransparency = 1
    hint.Text = "F — AutoFarm | G — KillAura"
    hint.TextColor3 = Color3.fromRGB(120, 120, 132)
    hint.TextXAlignment = Enum.TextXAlignment.Left
    hint.Font = Enum.Font.Gotham
    hint.TextSize = 11
    hint.Parent = content

    local OFF_COLOR = Color3.fromRGB(55, 55, 66)
    local ON_COLOR = Color3.fromRGB(46, 160, 90)

    local function paint(button, enabled)
        button.Text = enabled and "ON" or "OFF"
        button.BackgroundColor3 = enabled and ON_COLOR or OFF_COLOR
    end

    ui.setAutoFarm = function(value)
        CONFIG.AutoFarm = value
        paint(autoButton, value)
    end

    ui.setKillAura = function(value)
        CONFIG.KillAura = value
        paint(auraButton, value)
    end

    autoButton.MouseButton1Click:Connect(function()
        ui.setAutoFarm(not CONFIG.AutoFarm)
    end)

    auraButton.MouseButton1Click:Connect(function()
        ui.setKillAura(not CONFIG.KillAura)
    end)

    local dragging = false
    local dragStart = nil
    local startPos = nil

    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    task.spawn(function()
        while screen.Parent do
            local targetName = "-"
            if state.target and state.target.model and state.target.model.Parent then
                targetName = state.target.model.Name
            end
            status.Text = string.format("Цель: %s\nМобов в радиусе: %d", targetName, state.auraCount)
            task.wait(0.25)
        end
    end)

    ui.status = status
    return screen
end

local function autoFarmLoop()
    while true do
        if not screenGui or not screenGui.Parent then break end

        if CONFIG.AutoFarm then
            local mobs = scanMobs()
            local target = nil
            for _, mob in ipairs(mobs) do
                if isValid(mob) then
                    target = mob
                    break
                end
            end
            state.target = target

            if target then
                local now = os.clock()
                if now - lastTeleport >= CONFIG.TeleportCooldown then
                    if teleportToMob(target) then
                        lastTeleport = now
                    end
                end
                task.wait(0.05)
                attackMob(target)
                task.wait(CONFIG.AttackDelay)
            else
                task.wait(0.3)
            end
        else
            state.target = nil
            task.wait(0.2)
        end

        task.wait()
    end
end

local function killAuraLoop()
    while true do
        if not screenGui or not screenGui.Parent then break end

        if CONFIG.KillAura then
            local mobs = scanMobs()
            local inRange = {}
            for _, mob in ipairs(mobs) do
                if isValid(mob) and mob.distance <= CONFIG.AuraRadius then
                    table.insert(inRange, mob)
                end
            end
            state.auraCount = #inRange

            if #inRange > 0 then
                local limit = math.min(#inRange, 8)
                for i = 1, limit do
                    if not CONFIG.KillAura then break end
                    attackMob(inRange[i])
                    task.wait(0.04)
                end
                task.wait(CONFIG.AttackDelay)
            else
                task.wait(0.25)
            end
        else
            state.auraCount = 0
            task.wait(0.2)
        end

        task.wait()
    end
end

screenGui = createUI()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if UserInputService:GetFocusedTextBox() then return end

    if input.KeyCode == Enum.KeyCode.F then
        if ui.setAutoFarm then
            ui.setAutoFarm(not CONFIG.AutoFarm)
        end
    elseif input.KeyCode == Enum.KeyCode.G then
        if ui.setKillAura then
            ui.setKillAura(not CONFIG.KillAura)
        end
    end
end)

task.spawn(autoFarmLoop)
task.spawn(killAuraLoop)
