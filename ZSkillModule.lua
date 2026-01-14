-- ==============================================================================
-- ZSkillManager (Refactored: Mirroring VSkill Arch + Advanced Features)
-- ==============================================================================
-- Features:
-- [x] Data-Driven Skill Database
-- [x] Cooldown Groups (Shared Cooldowns) & Resource Pools
-- [x] Debug Overlay (Exact Timings)
-- [x] PC Macros/Modifiers (e.g., Shift+Z)
-- [x] Legacy Aimlock Logic Integration
-- ==============================================================================

local ZSkillManager = {}
ZSkillManager.__index = ZSkillManager

-- :: Services ::
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- :: Local Player ::
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- ==============================================================================
-- [1] DATA-DRIVEN CONFIGURATION
-- ==============================================================================

-- Resources (Mocked or Read from Game)
local ResourcePool = {
    Energy = 1000,
    MaxEnergy = 1000,
    RegenRate = 5 -- per tick
}

-- Cooldown Groups (Skills sharing a key prevent others in the group)
local CooldownGroups = {
    ["Melee_Dash"] = 0,   -- Timestamp when this group is free
    ["Heavy_Attack"] = 0
}

-- Skill Database
local SkillDatabase = {
    ["Godhuman"] = {
        ["Z"] = {
            Name = "Soaring Beast",
            Cooldown = 8.0,
            CastTime = 0.5,
            ResourceCost = 50, -- Energy
            Group = "Melee_Dash",
            TriggerOnRelease = true, -- Mobile specific logic
            AimlockEnabled = true    -- Logic Flag
        },
        ["C"] = {
            Name = "Sixth Realm Gun",
            Cooldown = 12.0,
            CastTime = 1.0,
            ResourceCost = 100,
            Group = "Heavy_Attack",
            AimlockEnabled = false
        }
    }
}

-- PC Keybinds & Macros
local KeyMap = {
    [Enum.KeyCode.Z] = { Key = "Z", Modifier = nil },
    [Enum.KeyCode.X] = { Key = "X", Modifier = nil },
    -- Macro Example: Shift+Z triggers a different logic path or skill variation
    [Enum.KeyCode.Z] = { Key = "Z_Alt", Modifier = Enum.KeyCode.LeftShift } 
}

-- ==============================================================================
-- [2] STATE & VISUALS
-- ==============================================================================

local State = {
    CurrentTool = nil,
    ActiveCooldowns = {}, -- [UniqueKey] = ExpiryTime
    ActiveSkill = nil,    -- Currently executing skill
    IsAiming = false,
    DebugMode = true,
    TargetInfoEnabled = false
}

-- :: UI Container ::
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ZSkillOverlay"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = PlayerGui

-- :: Debug Overlay ::
local DebugLabel = Instance.new("TextLabel")
DebugLabel.Size = UDim2.new(0, 200, 0, 100)
DebugLabel.Position = UDim2.new(0.85, 0, 0.1, 0)
DebugLabel.BackgroundTransparency = 0.5
DebugLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
DebugLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
DebugLabel.TextXAlignment = Enum.TextXAlignment.Left
DebugLabel.TextYAlignment = Enum.TextYAlignment.Top
DebugLabel.Font = Enum.Font.Code
DebugLabel.TextSize = 14
DebugLabel.Visible = false
DebugLabel.Parent = ScreenGui

-- :: Target UI (Legacy Refined) ::
local TargetFrame = Instance.new("Frame")
TargetFrame.Size = UDim2.new(0.2, 0, 0.05, 0)
TargetFrame.Position = UDim2.new(0.5, -100, 0.05, 0)
TargetFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
TargetFrame.Visible = false
TargetFrame.Parent = ScreenGui

local TargetName = Instance.new("TextLabel")
TargetName.Size = UDim2.new(1, 0, 0.6, 0)
TargetName.BackgroundTransparency = 1
TargetName.TextColor3 = Color3.white
TargetName.Parent = TargetFrame

local TargetHPBar = Instance.new("Frame")
TargetHPBar.Size = UDim2.new(1, 0, 0.4, 0)
TargetHPBar.Position = UDim2.new(0, 0, 0.6, 0)
TargetHPBar.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
TargetHPBar.BorderSizePixel = 0
TargetHPBar.Parent = TargetFrame

-- ==============================================================================
-- [3] CORE SYSTEMS (Cooldowns, Resources, Groups)
-- ==============================================================================

function ZSkillManager:UpdateDebug()
    if not State.DebugMode then DebugLabel.Visible = false return end
    DebugLabel.Visible = true
    
    local text = "** DEBUG OVERLAY **\n"
    text = text .. string.format("Energy: %d/%d\n", ResourcePool.Energy, ResourcePool.MaxEnergy)
    
    text = text .. "\n[Cooldowns]:\n"
    for k, v in pairs(State.ActiveCooldowns) do
        local remaining = v - os.clock()
        if remaining > 0 then
            text = text .. string.format("%s: %.1fs\n", k, remaining)
        end
    end

    text = text .. "\n[Groups]:\n"
    for k, v in pairs(CooldownGroups) do
        local remaining = v - os.clock()
        if remaining > 0 then
            text = text .. string.format("%s: %.1fs\n", k, remaining)
        end
    end
    
    DebugLabel.Text = text
end

function ZSkillManager:CheckResource(cost)
    if ResourcePool.Energy >= cost then
        ResourcePool.Energy -= cost
        return true
    end
    return false
end

function ZSkillManager:CanUseSkill(toolName, key, skillData)
    local uniqueKey = toolName .. "_" .. key
    local now = os.clock()

    -- 1. Individual Cooldown
    if State.ActiveCooldowns[uniqueKey] and now < State.ActiveCooldowns[uniqueKey] then
        return false
    end

    -- 2. Group Cooldown
    if skillData.Group and CooldownGroups[skillData.Group] and now < CooldownGroups[skillData.Group] then
        return false
    end

    -- 3. Resource Check
    if not self:CheckResource(skillData.ResourceCost) then
        return false
    end

    return true
end

function ZSkillManager:ApplyCooldowns(toolName, key, skillData)
    local uniqueKey = toolName .. "_" .. key
    local now = os.clock()
    
    State.ActiveCooldowns[uniqueKey] = now + skillData.Cooldown
    if skillData.Group then
        CooldownGroups[skillData.Group] = now + skillData.Cooldown
    end
end

-- ==============================================================================
-- [4] AIMLOCK & TARGETING LOGIC
-- ==============================================================================

local AimContext = {
    Target = nil,
    Connection = nil,
    Timeout = nil
}

local function GetNearestEnemy()
    local myRoot = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end
    
    local closest, minDist = nil, 1000 -- Max Range
    
    for _, v in ipairs(Players:GetPlayers()) do
        if v ~= Player and v.Character and v.Character:FindFirstChild("HumanoidRootPart") then
            -- Note: Insert Team Check / Ally Check Logic here (Simplified for brevity)
            local dist = (v.Character.HumanoidRootPart.Position - myRoot.Position).Magnitude
            if dist < minDist then
                minDist = dist
                closest = v.Character
            end
        end
    end
    return closest
end

function ZSkillManager:StartAimlock()
    if State.IsAiming then return end
    
    local target = GetNearestEnemy()
    if not target then return end

    State.IsAiming = true
    AimContext.Target = target

    -- Render Loop
    AimContext.Connection = RunService.RenderStepped:Connect(function()
        if not State.IsAiming or not AimContext.Target then 
            self:StopAimlock() 
            return 
        end
        local cam = workspace.CurrentCamera
        local targetRoot = AimContext.Target:FindFirstChild("HumanoidRootPart")
        if cam and targetRoot then
            cam.CFrame = CFrame.lookAt(cam.CFrame.Position, targetRoot.Position)
        end
    end)

    -- Safety Timeout
    AimContext.Timeout = task.delay(1.0, function() self:StopAimlock() end)
end

function ZSkillManager:StopAimlock()
    State.IsAiming = false
    if AimContext.Connection then AimContext.Connection:Disconnect() AimContext.Connection = nil end
    if AimContext.Timeout then task.cancel(AimContext.Timeout) AimContext.Timeout = nil end
end

-- ==============================================================================
-- [5] SKILL EXECUTION
-- ==============================================================================

function ZSkillManager:ExecuteSkill(toolName, key)
    local toolSkills = SkillDatabase[toolName]
    if not toolSkills then return end

    local skillData = toolSkills[key]
    if not skillData then return end

    -- Validation
    if not self:CanUseSkill(toolName, key, skillData) then 
        warn("Skill on Cooldown or Insufficient Resource")
        return 
    end

    -- Execution
    self:ApplyCooldowns(toolName, key, skillData)
    print("Executing:", skillData.Name)

    -- Specific Logic (e.g., Godhuman Z Aimlock)
    if skillData.AimlockEnabled then
        self:StartAimlock()
    end
end

-- ==============================================================================
-- [6] INPUT & LISTENERS
-- ==============================================================================

-- PC: Keybinds + Modifier Support (Shift/Ctrl)
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if not State.CurrentTool then return end

    if input.UserInputType == Enum.UserInputType.Keyboard then
        -- Check basic bind
        local bindData = KeyMap[input.KeyCode]
        if bindData then
            -- Modifier Check
            local isModifierDown = true
            if bindData.Modifier then
                isModifierDown = UserInputService:IsKeyDown(bindData.Modifier)
            end

            if isModifierDown then
                -- This allows Shift+Z to be treated differently than Z
                local keyToSend = bindData.Modifier and (bindData.Key .. "_Alt") or bindData.Key
                ZSkillManager:ExecuteSkill(State.CurrentTool.Name, keyToSend)
            else
                -- Fallback to standard key if modifier isn't pressed but bind exists without modifier
                -- (Simplified for this example)
                ZSkillManager:ExecuteSkill(State.CurrentTool.Name, bindData.Key)
            end
        end
    end
end)

-- Mobile: Touch Release Logic
UserInputService.TouchEnded:Connect(function(touch)
    local cam = workspace.CurrentCamera
    if not cam then return end

    -- Right side of screen check
    if touch.Position.X > cam.ViewportSize.X / 2 then
        if State.CurrentTool and State.CurrentTool.Name == "Godhuman" then
            -- Mobile specifically triggers Godhuman Z on release
            ZSkillManager:ExecuteSkill("Godhuman", "Z")
        end
    end
end)

-- Tool Watcher
local function SetupCharacter(char)
    char.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            State.CurrentTool = child
        end
    end)
    char.ChildRemoved:Connect(function(child)
        if child == State.CurrentTool then
            State.CurrentTool = nil
            ZSkillManager:StopAimlock()
        end
    end)
end

Player.CharacterAdded:Connect(SetupCharacter)
if Player.Character then SetupCharacter(Player.Character) end

-- Loop for UI Updates
RunService.Heartbeat:Connect(function()
    ZSkillManager:UpdateDebug()
    
    -- Target Info UI Update
    if State.TargetInfoEnabled then
        local target = GetNearestEnemy()
        if target and target:FindFirstChild("Humanoid") then
            TargetFrame.Visible = true
            TargetName.Text = target.Name
            TargetHPBar.Size = UDim2.new(target.Humanoid.Health / target.Humanoid.MaxHealth, 0, 1, 0)
        else
            TargetFrame.Visible = false
        end
    else
        TargetFrame.Visible = false
    end
end)

-- ==============================================================================
-- [7] EXTERNAL HOOK
-- ==============================================================================

function ZSkillManager:ProcessSignal(method, args)
    -- Called by your __namecall hook
    -- args[1] usually contains the key ("Z", "X", etc)
    local key = args[1]
    if typeof(key) == "string" and State.CurrentTool then
        -- We intercept the server firing and run our manager logic
        -- Note: We might allow the signal to pass, but we sync our manager here
        local toolSkills = SkillDatabase[State.CurrentTool.Name]
        if toolSkills and toolSkills[key] then
           self:ExecuteSkill(State.CurrentTool.Name, key)
        end
    end
end

-- Toggle Methods
function ZSkillManager:ToggleDebug(bool) State.DebugMode = bool end
function ZSkillManager:ToggleTargetInfo(bool) State.TargetInfoEnabled = bool end

print("[ZSkillManager] Loaded with Cooldown Groups & Resource Management")
return ZSkillManager
