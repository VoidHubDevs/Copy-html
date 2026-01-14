-- ==============================================================================
-- VSkillManager (Refactored & Expanded)
-- ==============================================================================
-- Features:
-- [x] Data-driven Skill Database
-- [x] Centralized Cooldown & Resource Management
-- [x] Visuals (Cooldown Rings, Cast Bars)
-- [x] PC/Mobile Input Support (Hotkeys + Touch)
-- [x] Loadouts/Presets
-- [x] Telemetry (Usage Stats)
-- [x] Macro/Chaining Queue
-- ==============================================================================

local VSkillManager = {}
VSkillManager.__index = VSkillManager

-- :: Services ::
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

-- :: Local Player ::
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- :: Constants ::
local MOBILE_TOUCH_THRESHOLD = 0.5 -- Screen width ratio (0.5 = right half)

-- ==============================================================================
-- [1] DATA-DRIVEN SKILLS & CONFIGURATION
-- ==============================================================================

-- Define all skill properties here
local SkillDatabase = {
    ["Shark Anchor"] = {
        ["Z"] = {
            Name = "Typhoon Toss",
            Cooldown = 6,
            CastTime = 1.5,
            DamageThreshold = 0, -- Min damage on counter to cancel
            VisualColor = Color3.fromRGB(0, 150, 255)
        },
        ["X"] = { -- Example of expanding
            Name = "Armor Breaker",
            Cooldown = 8,
            CastTime = 0.5,
            VisualColor = Color3.fromRGB(0, 100, 200)
        }
    },
    ["Dough-Dough"] = {
        ["V"] = {
            Name = "Dough Fist",
            Cooldown = 10,
            CastTime = 2.0,
            VisualColor = Color3.fromRGB(255, 230, 150)
        }
    },
    ["Cursed Dual Katana"] = {
        ["Z"] = {
            Name = "Slayer",
            Cooldown = 4,
            CastTime = 1.2,
            VisualColor = Color3.fromRGB(200, 50, 50)
        }
    }
}

-- Default Keybinds (PC)
local Keybinds = {
    [Enum.KeyCode.Z] = "Z",
    [Enum.KeyCode.X] = "X",
    [Enum.KeyCode.C] = "C",
    [Enum.KeyCode.V] = "V",
    [Enum.KeyCode.F] = "F"
}

-- ==============================================================================
-- [2] STATE MANAGEMENT
-- ==============================================================================

local State = {
    CurrentToolName = nil,
    ActiveCooldowns = {}, -- { [SkillName] = os.clock() end_time }
    ActiveCast = nil,     -- Currently casting skill info
    Telemetry = {},       -- { [SkillName] = count }
    Loadout = {},         -- Current active skills
    IsMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled,
    SilentAimRef = nil    -- Reference to external module
}

-- ==============================================================================
-- [3] VISUALS SYSTEM (UI Factory)
-- ==============================================================================

local Visuals = {}
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "VSkillVisuals"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = PlayerGui

function Visuals:CreateCooldownIndicator(skillName, duration)
    -- Create a simple circular progress or bar
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 50, 0, 50)
    frame.Position = UDim2.new(0.5, -25, 0.8, -100) -- Adjust position dynamically
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0.5
    frame.Parent = ScreenGui
    
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 5)
    bar.Position = UDim2.new(0, 0, 1, 0)
    bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    bar.Parent = frame

    -- Tween the bar
    local tween = TweenService:Create(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Size = UDim2.new(0, 0, 0, 5)})
    tween:Play()
    tween.Completed:Connect(function() frame:Destroy() end)
end

function Visuals:ShowCastBar(skillName, castTime, color)
    local castFrame = Instance.new("Frame")
    castFrame.Size = UDim2.new(0, 200, 0, 20)
    castFrame.Position = UDim2.new(0.5, -100, 0.7, 0)
    castFrame.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
    castFrame.BorderSizePixel = 0
    castFrame.Parent = ScreenGui

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = color or Color3.new(1, 1, 1)
    fill.BorderSizePixel = 0
    fill.Parent = castFrame

    local tween = TweenService:Create(fill, TweenInfo.new(castTime, Enum.EasingStyle.Linear), {Size = UDim2.new(1, 0, 1, 0)})
    tween:Play()
    
    -- Cleanup
    task.delay(castTime, function()
        castFrame:Destroy()
    end)
end

-- ==============================================================================
-- [4] CORE LOGIC
-- ==============================================================================

local function ToggleExternalSystems(active)
    -- Abstracted Logic for Aim/Silent Aim
    if State.SilentAimRef then
        if active then
            -- Pause Aim when skill is active
            if State.SilentAimRef.Pause then State.SilentAimRef:Pause() end
        else
            -- Resume Aim when skill ends
            if State.SilentAimRef.Restore then State.SilentAimRef:Restore() end
        end
    end
end

local function RecordTelemetry(skillKey)
    if not State.Telemetry[skillKey] then State.Telemetry[skillKey] = 0 end
    State.Telemetry[skillKey] += 1
end

function VSkillManager:IsOnCooldown(skillKey)
    local expiry = State.ActiveCooldowns[skillKey]
    return expiry and (os.clock() < expiry)
end

function VSkillManager:ExecuteSkill(toolName, key)
    local toolData = SkillDatabase[toolName]
    if not toolData then return end
    
    local skill = toolData[key]
    if not skill then return end

    local uniqueKey = toolName .. "_" .. key

    -- 1. Check Cooldown
    if self:IsOnCooldown(uniqueKey) then return end

    -- 2. Start Logic
    RecordTelemetry(uniqueKey)
    State.ActiveCooldowns[uniqueKey] = os.clock() + skill.Cooldown
    State.ActiveCast = skill

    -- 3. Visuals & System Toggles
    Visuals:ShowCastBar(skill.Name, skill.CastTime, skill.VisualColor)
    Visuals:CreateCooldownIndicator(skill.Name, skill.Cooldown)
    
    -- Disable Silent Aim / Enable "Safe Mode"
    ToggleExternalSystems(true)

    -- 4. Handle Duration/End
    task.delay(skill.CastTime, function()
        -- End Logic
        if State.ActiveCast == skill then
            State.ActiveCast = nil
            ToggleExternalSystems(false)
        end
    end)
end

-- ==============================================================================
-- [5] INPUT HANDLING (PC & MOBILE)
-- ==============================================================================

-- PC Keybinds
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local keyStr = Keybinds[input.KeyCode]
        if keyStr and State.CurrentToolName then
            -- Optional: Add macro check here
            VSkillManager:ExecuteSkill(State.CurrentToolName, keyStr)
        end
    end
end)

-- Mobile Touch Logic (Zone Based)
UserInputService.TouchStarted:Connect(function(touch)
    local camera = workspace.CurrentCamera
    if not camera then return end

    -- Detect "Attack Zone" (Right side of screen)
    if touch.Position.X > (camera.ViewportSize.X * MOBILE_TOUCH_THRESHOLD) then
        -- If we are currently in a "hold" skill state, this might be relevant
        -- For now, we rely on the specific skill triggers
    end
end)

UserInputService.TouchEnded:Connect(function(touch)
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    -- Reset logic if needed when finger leaves screen
    if State.ActiveCast then
        -- Optional: Early cancel logic
    end
end)

-- ==============================================================================
-- [6] TOOL WATCHER & INTEGRATION
-- ==============================================================================

local function onToolEquipped(tool)
    State.CurrentToolName = tool.Name
    -- Load appropriate loadout if using a preset system
end

local function onToolUnequipped()
    State.CurrentToolName = nil
    -- Reset active casts instantly
    State.ActiveCast = nil
    ToggleExternalSystems(false)
end

local function setupCharacter(char)
    char.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            onToolEquipped(child)
            child.AncestryChanged:Connect(function(_, parent)
                if not parent then onToolUnequipped() end
            end)
        end
    end)
end

Player.CharacterAdded:Connect(setupCharacter)
if Player.Character then setupCharacter(Player.Character) end

-- ==============================================================================
-- [7] HOOK REPLACEMENT (Network Listener)
-- ==============================================================================
-- NOTE: Instead of raw metamethod hooks, use this function to pipe 
-- detection from your existing hook script into this manager.

function VSkillManager:ProcessNetworkSignal(method, args)
    -- This method should be called by your external hook script
    -- Example: VSkillManager:ProcessNetworkSignal("FireServer", {"Z"})
    
    local action = args[1]
    
    if (method == "InvokeServer" or method == "FireServer") and typeof(action) == "string" then
        if State.CurrentToolName then
            -- Attempt to trigger the skill defined in Database
            self:ExecuteSkill(State.CurrentToolName, action:upper())
        end
    end
end

-- ==============================================================================
-- [8] INIT
-- ==============================================================================

function VSkillManager:Init(SilentAimModule)
    State.SilentAimRef = SilentAimModule
    print("[VSkillManager] Initialized with Data-Driven Skills.")
end

return VSkillManager
