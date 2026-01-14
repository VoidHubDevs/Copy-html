local AimbotModule = {}
AimbotModule.__index = AimbotModule

-- ==============================================================================
-- SERVICES & CONSTANTS
-- ==============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- ==============================================================================
-- DEFAULT CONFIGURATION & STATE
-- ==============================================================================
local State = {
    Initialized = false,
    Enabled = false,
    IsAiming = false,
    CurrentTarget = nil,
    CurrentToolName = "None",
    LastTargetUpdate = 0,
    LastShotTime = 0,
    JitterOffset = Vector3.new(0, 0, 0),
    Connections = {},
    DebugUI = nil
}

local Config = {
    -- General
    Enabled = true,
    TeamCheck = true,
    AliveCheck = true,
    WallCheck = true,
    
    -- Selection
    FOV = 150, -- Field of View radius
    MaxDistance = 1000,
    RefreshRate = 0.05, -- 20Hz Target Selection Throttling
    PriorityMode = "Closest", -- Options: "Closest", "LowestHP", "HighestThreat"
    
    -- Aiming Physics
    AimBone = "HumanoidRootPart", -- or "Head"
    Smoothing = 0.5, -- 0 = instant, 1 = no movement
    Prediction = 0.15, -- Time in seconds to predict
    
    -- Humanization
    Humanize = {
        Enabled = true,
        JitterIntensity = 0.5, -- Shake amount
        MissChance = 0, -- 0-100% chance to intentionally offset
        OffsetRange = 1.5, -- Random offset magnitude
    },
    
    -- Input
    Keybind = Enum.UserInputType.MouseButton2,
    ToggleMode = false, -- False = Hold to aim, True = Toggle
    
    -- Visuals
    ShowFOV = false,
    ShowTarget = true,
    TargetColor = Color3.fromRGB(255, 50, 50),
}

-- Per-Weapon Profiles
-- Automatically switches settings based on equipped tool name
local WeaponProfiles = {
    ["Dough-Dough"] = { Smoothing = 0.2, Prediction = 0.13, FOV = 300 },
    ["Soul Guitar"] = { Smoothing = 0.1, Prediction = 0.18, FOV = 400 },
    ["Cursed Dual Katana"] = { Smoothing = 0.05, Prediction = 0.1, FOV = 120 },
    ["Shark Anchor"] = { Smoothing = 0.3, Prediction = 0.15, FOV = 200 },
}

-- ==============================================================================
-- HELPER FUNCTIONS
-- ==============================================================================

local function IsVisible(targetPart, origin)
    if not Config.WallCheck then return true end
    origin = origin or Camera.CFrame.Position
    
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true

    local direction = (targetPart.Position - origin)
    local result = Workspace:Raycast(origin, direction, params)

    return (result and result.Instance:IsDescendantOf(targetPart.Parent)) or (not result)
end

local function GetCharacter(player)
    return player.Character or player.CharacterAdded:Wait()
end

-- Preserved Logic: Team Check from original file
local function IsAlly(targetPlayer)
    if targetPlayer == LocalPlayer then return true end
    
    -- 1. Game Specific Team Color/Name Check
    if LocalPlayer.Team and targetPlayer.Team then
        if LocalPlayer.Team.Name == targetPlayer.Team.Name then
            -- Note: In some games, same team can still be enemy (Free for all), 
            -- but adhering to original logic:
            local myGui = LocalPlayer:FindFirstChild("PlayerGui")
            -- Checking ally list UI (from original script)
            if myGui and myGui:FindFirstChild("Main") and myGui.Main:FindFirstChild("Allies") then
                local scrolling = myGui.Main.Allies.Container.Allies.ScrollingFrame
                for _, frame in pairs(scrolling:GetDescendants()) do
                    if frame:IsA("ImageButton") and frame.Name == targetPlayer.Name then
                        return true
                    end
                end
            end
            -- If not in ally list but same team (Pirates/Marines logic)
            if LocalPlayer.Team.Name == "Marines" then return true end
        end
    end
    return false
end

-- ==============================================================================
-- TARGET SCORING SYSTEM
-- ==============================================================================

local function CalculateScore(target, mode)
    local char = target.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local human = char and char:FindFirstChildOfClass("Humanoid")
    
    if not (root and human and human.Health > 0) then return -math.huge end
    
    local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position)
    local mousePos = UserInputService:GetMouseLocation()
    local distToMouse = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
    local dist3D = (root.Position - Camera.CFrame.Position).Magnitude
    
    -- Check Constraints
    if not onScreen then return -math.huge end
    if distToMouse > Config.FOV then return -math.huge end
    if dist3D > Config.MaxDistance then return -math.huge end
    if Config.WallCheck and not IsVisible(root) then return -math.huge end
    
    -- Calculate Score based on Priority Mode
    local score = 0
    
    if mode == "Closest" then
        -- Higher score = closer to mouse cursor
        score = (Config.FOV - distToMouse)
        
    elseif mode == "LowestHP" then
        -- Higher score = lower health
        score = (human.MaxHealth - human.Health)
        
    elseif mode == "HighestThreat" then
        -- Combine distance and health (example heuristic)
        score = (1000 - dist3D) + (human.MaxHealth - human.Health)
        
    elseif mode == "NearestToCrosshair" then
         -- Pure 2D distance
        score = (10000 - distToMouse)
    end
    
    return score
end

-- ==============================================================================
-- CORE LOGIC
-- ==============================================================================

function AimbotModule:UpdateProfile()
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    local toolName = tool and tool.Name or "None"
    
    if toolName ~= State.CurrentToolName then
        State.CurrentToolName = toolName
        local profile = WeaponProfiles[toolName]
        if profile then
            -- Apply profile overrides
            for k, v in pairs(profile) do
                if Config[k] ~= nil then Config[k] = v end
            end
            -- print("[Aimbot] Loaded profile for: " .. toolName)
        end
    end
end

function AimbotModule:GetBestTarget()
    -- Throttling
    if (tick() - State.LastTargetUpdate) < Config.RefreshRate and State.CurrentTarget then
        -- Validate current target is still valid
        if State.CurrentTarget.Parent and 
           State.CurrentTarget.Character and 
           State.CurrentTarget.Character:FindFirstChild("Humanoid") and
           State.CurrentTarget.Character.Humanoid.Health > 0 then
            return State.CurrentTarget
        end
    end
    
    State.LastTargetUpdate = tick()
    
    local bestTarget = nil
    local bestScore = -math.huge
    
    -- Iterate Players
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and (not Config.TeamCheck or not IsAlly(plr)) then
            local score = CalculateScore(plr, Config.PriorityMode)
            if score > bestScore then
                bestScore = score
                bestTarget = plr
            end
        end
    end
    
    -- Iterate NPCs (if enabled via extended logic, kept simple here for Players)
    -- To add NPCs, you would loop workspace.Enemies here similarly.
    
    return bestTarget
end

function AimbotModule:UpdateHumanization()
    if not Config.Humanize.Enabled then 
        State.JitterOffset = Vector3.new(0,0,0)
        return 
    end
    
    -- Generate random jitter noise
    local intensity = Config.Humanize.JitterIntensity
    State.JitterOffset = Vector3.new(
        (math.random() - 0.5) * intensity,
        (math.random() - 0.5) * intensity,
        (math.random() - 0.5) * intensity
    )
end

function AimbotModule:CalculateAimCFrame(target)
    local char = target.Character
    local part = char and char:FindFirstChild(Config.AimBone)
    if not part then return Camera.CFrame end
    
    -- 1. Base Position
    local targetPos = part.Position
    
    -- 2. Prediction
    if Config.Prediction > 0 and part.AssemblyLinearVelocity then
        targetPos = targetPos + (part.AssemblyLinearVelocity * Config.Prediction)
    end
    
    -- 3. Humanization (Jitter)
    if Config.Humanize.Enabled then
        targetPos = targetPos + State.JitterOffset
    end
    
    -- 4. Calculate Look Vector
    local lookVector = (targetPos - Camera.CFrame.Position).Unit
    local newCFrame = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + lookVector)
    
    -- 5. Smoothing
    if Config.Smoothing > 0 then
        -- Lerp between current and target
        -- Dynamic smoothing based on distance can be added here
        return Camera.CFrame:Lerp(newCFrame, 1 - Config.Smoothing) 
    else
        return newCFrame
    end
end

-- ==============================================================================
-- PUBLIC API
-- ==============================================================================

function AimbotModule.Init()
    if State.Initialized then return end
    State.Initialized = true
    
    -- Render Loop
    RunService:BindToRenderStep("AimbotUpdate", Enum.RenderPriority.Camera.Value + 1, function(dt)
        if not State.Enabled then 
            State.IsAiming = false
            return 
        end
        
        -- Check Input
        local aiming = State.IsAiming
        if not Config.ToggleMode then
            aiming = UserInputService:IsMouseButtonPressed(Config.Keybind) or 
                     UserInputService:IsKeyDown(Enum.KeyCode.ButtonL2) -- Controller support
        end
        
        if aiming then
            AimbotModule:UpdateProfile() -- Check weapon change
            
            local target = AimbotModule:GetBestTarget()
            State.CurrentTarget = target
            
            if target then
                AimbotModule:UpdateHumanization()
                local goalCF = AimbotModule:CalculateAimCFrame(target)
                Camera.CFrame = goalCF
                
                -- Highlight Visualization
                if Config.ShowTarget then AimbotModule.UpdateHighlight(target) end
            else
                AimbotModule.RemoveHighlight()
            end
        else
            State.CurrentTarget = nil
            AimbotModule.RemoveHighlight()
        end
    end)
    
    -- Input Handling
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        
        if Config.ToggleMode and input.UserInputType == Config.Keybind then
            State.IsAiming = not State.IsAiming
        end
    end)
    
    print("AimbotModule Initialized")
end

function AimbotModule.Enable()
    State.Enabled = true
end

function AimbotModule.Disable()
    State.Enabled = false
    State.IsAiming = false
    AimbotModule.RemoveHighlight()
end

function AimbotModule.Destroy()
    RunService:UnbindFromRenderStep("AimbotUpdate")
    AimbotModule.RemoveHighlight()
    for _, conn in pairs(State.Connections) do conn:Disconnect() end
    State = nil
end

-- ==============================================================================
-- VISUALIZATIONS & DEBUG
-- ==============================================================================

function AimbotModule.UpdateHighlight(target)
    if not State.DebugUI then
        State.DebugUI = Instance.new("Highlight")
        State.DebugUI.Name = "AimbotHighlight"
        State.DebugUI.FillTransparency = 1
        State.DebugUI.OutlineTransparency = 0
        State.DebugUI.OutlineColor = Config.TargetColor
        State.DebugUI.Parent = game.CoreGui
    end
    
    if target and target.Character then
        State.DebugUI.Adornee = target.Character
        State.DebugUI.Enabled = true
    end
end

function AimbotModule.RemoveHighlight()
    if State.DebugUI then
        State.DebugUI.Enabled = false
        State.DebugUI.Adornee = nil
    end
end

-- ==============================================================================
-- CONFIGURATION SETTERS
-- ==============================================================================

function AimbotModule.SetConfig(key, value)
    if Config[key] ~= nil then
        Config[key] = value
    end
end

function AimbotModule.GetConfig()
    return Config
end

-- PC Extras: Native mouse simulation helper (optional usage)
function AimbotModule.MousemoveRel(x, y)
    -- This requires an executor that supports mousemoverel
    if mousemoverel then
        mousemoverel(x, y)
    end
end

-- ==============================================================================
-- LEGACY COMPATIBILITY (Hooks for Skills)
-- ==============================================================================
-- This preserves the V/Z skill detection from the original script
if not _G.AimlockHooked then
    _G.AimlockHooked = true
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if (method == "InvokeServer" or method == "FireServer") then
            local arg1 = args[1]
            if typeof(arg1) == "string" then
                -- Integrate Skill Triggers here if needed
                -- For now, we ensure we don't break existing game logic
                -- print("Skill Used: ", arg1) 
            end
        end
        return oldNamecall(self, ...)
    end)
end

return AimbotModule
