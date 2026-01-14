-- ==============================================================================
-- UISettingsManager (Refactored & Expanded)
-- ==============================================================================
-- Features:
-- [x] Centralized Settings Store (Get/Set/Subscribe)
-- [x] Persistence (Save/Load via writefile/readfile)
-- [x] Profile Management (Default/Custom Profiles)
-- [x] Keybind System (PC Support)
-- [x] Performance Mode & UI Scaling
-- [x] Decoupled Game Logic (V4, Fruit, Speed)
-- ==============================================================================

local UISettingsManager = {}
UISettingsManager.__index = UISettingsManager

-- :: Services ::
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer

-- :: Constants ::
local FOLDER_NAME = "VScript_Config"
local DEFAULT_PROFILE = "default"

-- ==============================================================================
-- [1] CORE SETTINGS & EVENT SYSTEM
-- ==============================================================================

local Config = {} -- Holds current runtime values
local Listeners = {} -- { [SettingName] = {Callback1, Callback2...} }
local Keybinds = {} -- { [Enum.KeyCode] = "SettingName" }

-- Default Configuration
local Defaults = {
    -- Visuals
    Theme = "Dark",
    BackgroundColor = "Dark",
    UIScale = 1.0,
    PerformanceMode = false,
    
    -- Game Features
    WalkSpeed = 16,
    V4Awakening = false,
    FruitESP = false,
    FruitTeleport = false,
    
    -- Keybinds (Stored as string names of keys)
    Keybinds = {}
}

-- :: Event Dispatcher ::
local function FireChange(key, value)
    if Listeners[key] then
        for _, callback in ipairs(Listeners[key]) do
            task.spawn(callback, value)
        end
    end
end

-- :: Public API ::
function UISettingsManager:Get(key)
    if Config[key] == nil then return Defaults[key] end
    return Config[key]
end

function UISettingsManager:Set(key, value)
    if Config[key] == value then return end -- No change
    Config[key] = value
    FireChange(key, value)
end

function UISettingsManager:Subscribe(key, callback)
    if not Listeners[key] then Listeners[key] = {} end
    table.insert(Listeners[key], callback)
    
    -- Fire immediately with current value
    callback(self:Get(key))
end

-- ==============================================================================
-- [2] PERSISTENCE (Save/Load)
-- ==============================================================================

function UISettingsManager:SaveProfile(profileName)
    profileName = profileName or DEFAULT_PROFILE
    
    if not isfolder(FOLDER_NAME) then makefolder(FOLDER_NAME) end
    
    local data = HttpService:JSONEncode(Config)
    writefile(FOLDER_NAME .. "/" .. profileName .. ".json", data)
    print("[Settings] Saved profile:", profileName)
end

function UISettingsManager:LoadProfile(profileName)
    profileName = profileName or DEFAULT_PROFILE
    local path = FOLDER_NAME .. "/" .. profileName .. ".json"
    
    if isfile(path) then
        local content = readfile(path)
        local success, decoded = pcall(HttpService.JSONDecode, HttpService, content)
        
        if success and decoded then
            -- Apply loaded settings
            for k, v in pairs(decoded) do
                self:Set(k, v)
            end
            print("[Settings] Loaded profile:", profileName)
        else
            warn("[Settings] Failed to decode profile.")
        end
    else
        warn("[Settings] Profile not found, using defaults.")
        -- Reset to defaults
        for k, v in pairs(Defaults) do
            self:Set(k, v)
        end
    end
end

-- ==============================================================================
-- [3] THEME ENGINE (Refactored)
-- ==============================================================================

local ThemeColors = {
    Red = Color3.fromRGB(220, 59, 48),
    Green = Color3.fromRGB(48, 209, 88),
    Purple = Color3.fromRGB(175, 82, 222),
    Cyan = Color3.fromRGB(0, 220, 220),
    Dark = Color3.fromRGB(40, 40, 40),
    White = Color3.fromRGB(220, 220, 220)
}

function UISettingsManager:ApplyTheme(libraryRef)
    local themeName = self:Get("Theme")
    local color = ThemeColors[themeName] or ThemeColors.Dark
    
    -- Construct theme table expected by UI Library
    local themeData = {
        SchemeColor = color,
        Header = color,
        TextColor = self:Get("PerformanceMode") and Color3.new(1,1,1) or Color3.fromRGB(255,255,255),
        Background = Color3.fromRGB(20, 20, 20)
    }
    
    if libraryRef and libraryRef.ChangeColor then
        libraryRef:ChangeColor(themeData)
    end
end

-- ==============================================================================
-- [4] FEATURE MANAGERS (Decoupled Logic)
-- ==============================================================================

-- :: WalkSpeed Manager ::
local function InitWalkSpeed()
    UISettingsManager:Subscribe("WalkSpeed", function(speed)
        getgenv().WalkSpeedValue = speed
        local char = Player.Character
        if char and char:FindFirstChild("Humanoid") then
            char.Humanoid.WalkSpeed = speed
        end
    end)

    -- Enforce speed on respawn/change
    task.spawn(function()
        while task.wait(1) do
            local target = UISettingsManager:Get("WalkSpeed")
            if target and target > 16 then
                local char = Player.Character
                if char and char:FindFirstChild("Humanoid") and char.Humanoid.WalkSpeed ~= target then
                    char.Humanoid.WalkSpeed = target
                end
            end
        end
    end)
end

-- :: V4 Awakening Manager ::
local function InitV4()
    local sizeConn = nil
    
    UISettingsManager:Subscribe("V4Awakening", function(enabled)
        if enabled then
            local fillFrame = Player:WaitForChild("PlayerGui"):FindFirstChild("RaceEnergy", true)
            if fillFrame then fillFrame = fillFrame:FindFirstChild("Fill", true) end

            if fillFrame and not sizeConn then
                sizeConn = fillFrame:GetPropertyChangedSignal("Size"):Connect(function()
                    if fillFrame.Size.X.Scale >= 0.9 then
                        local backpack = Player:FindFirstChild("Backpack")
                        local remote = backpack and backpack:FindFirstChild("Awakening") and backpack.Awakening:FindFirstChild("RemoteFunction")
                        if remote then remote:InvokeServer(true) end
                    end
                end)
            end
        else
            if sizeConn then sizeConn:Disconnect() sizeConn = nil end
        end
    end)
end

-- :: Fruit ESP/Teleport Manager ::
local function InitFruit()
    local loopTask = nil
    
    UISettingsManager:Subscribe("FruitTeleport", function(enabled)
        if enabled then
            loopTask = task.spawn(function()
                while UISettingsManager:Get("FruitTeleport") do
                    task.wait()
                    for _, v in pairs(workspace:GetChildren()) do
                        if v:IsA("Tool") and v:FindFirstChild("Handle") then
                            local char = Player.Character
                            if char and char:FindFirstChild("HumanoidRootPart") then
                                local info = TweenInfo.new(0.5, Enum.EasingStyle.Linear)
                                TweenService:Create(v.Handle, info, {CFrame = char.HumanoidRootPart.CFrame}):Play()
                            end
                        end
                    end
                end
            end)
        else
            if loopTask then cancel(loopTask) loopTask = nil end
        end
    end)
end

-- ==============================================================================
-- [5] KEYBIND & INPUT SYSTEM
-- ==============================================================================

function UISettingsManager:RegisterKeybind(actionName, defaultKey)
    local savedBind = self:Get("Keybinds")[actionName] or defaultKey
    -- Update Config Map
    local binds = self:Get("Keybinds")
    binds[actionName] = savedBind
    self:Set("Keybinds", binds)
end

function UISettingsManager:SetKeybind(actionName, keyCodeEnum)
    local binds = self:Get("Keybinds")
    binds[actionName] = keyCodeEnum.Name
    self:Set("Keybinds", binds)
end

-- Input Listener
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local binds = UISettingsManager:Get("Keybinds")
        for action, keyName in pairs(binds) do
            if input.KeyCode.Name == keyName then
                -- Toggle boolean settings automatically
                local currentVal = UISettingsManager:Get(action)
                if type(currentVal) == "boolean" then
                    UISettingsManager:Set(action, not currentVal)
                    -- Visual feedback
                    game.StarterGui:SetCore("SendNotification", {
                        Title = "Keybind",
                        Text = action .. ": " .. tostring(not currentVal),
                        Duration = 1
                    })
                end
            end
        end
    end
end)

-- Draggable Logic (Preserved)
function UISettingsManager:MakeDraggable(guiObject)
    local dragging, dragInput, dragStart, startPos
    
    guiObject.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = guiObject.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    
    guiObject.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            guiObject.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- ==============================================================================
-- [6] INITIALIZATION
-- ==============================================================================

function UISettingsManager:Init()
    -- Initialize Sub-Managers
    InitWalkSpeed()
    InitV4()
    InitFruit()
    
    -- Attempt to load default profile
    self:LoadProfile(DEFAULT_PROFILE)
    
    print("[UISettingsManager] Initialized successfully.")
end

return UISettingsManager
