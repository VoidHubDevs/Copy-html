local SilentAimModule = {}
SilentAimModule.__index = SilentAimModule

-- =========================
-- Services & Dependencies
-- =========================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- =========================
-- Configuration (Default)
-- =========================
SilentAimModule.Config = {
    Enabled = false,
    
    -- Input Settings
    Mode = "KeyHold", -- "Always", "Toggle", "KeyHold"
    Keybind = Enum.UserInputType.MouseButton2,
    
    -- Targeting
    TeamCheck = true,
    VisibleCheck = true, -- Raycast wall check
    FOVRadius = 250, -- Circle size
    MaxDistance = 2000,
    TargetNPCs = false,
    TargetPlayers = true,
    
    -- Hitbox & Humanization
    HitboxPriority = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso"},
    Multipoint = true, -- If Head is hidden, try Torso
    HitChance = 100, -- 0 to 100
    
    -- Prediction
    Prediction = {
        Enabled = true,
        Mode = "Velocity", -- "Velocity" or "Static"
        StaticAmount = 0.135,
        AutoPing = true -- Scales prediction based on ping
    },
    
    -- Visuals
    ShowFOV = true,
    FOVColor = Color3.fromRGB(255, 255, 255),
    SnapLines = false
}

-- =========================
-- Internal State
-- =========================
local State = {
    CurrentTarget = nil,
    CurrentHitbox = nil,
    PredictedPosition = nil,
    IsAiming = false,
    ActiveConnections = {},
    FOVInstance = nil -- Circle Drawing
}

-- =========================
-- Helper Functions
-- =========================
local function isAlly(player)
    if not player or not LocalPlayer then return false end
    -- Generic Team Check
    if player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then
        return true
    end
    -- Blox Fruits Specific Ally Check (Preserved)
    local success, result = pcall(function()
        local myGui = LocalPlayer:FindFirstChild("PlayerGui")
        local scroll = myGui.Main.Allies.Container.Allies.ScrollingFrame
        if scroll and scroll:FindFirstChild(player.Name) then return true end
        return false
    end)
    return success and result
end

local function isVisible(origin, targetPart)
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true

    local direction = (targetPart.Position - origin).Unit * (targetPart.Position - origin).Magnitude
    local result = Workspace:Raycast(origin, direction, params)

    if not result then return true end -- No obstacle
    if result.Instance:IsDescendantOf(targetPart.Parent) then return true end -- Hit the target
    return false
end

local function getPrediction(targetPart)
    if not SilentAimModule.Config.Prediction.Enabled then
        return targetPart.Position
    end

    local velocity = targetPart.AssemblyLinearVelocity
    local ping = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
    local scale = SilentAimModule.Config.Prediction.AutoPing and ping or SilentAimModule.Config.Prediction.StaticAmount
    
    return targetPart.Position + (velocity * scale)
end

-- =========================
-- Visuals (FOV Circle)
-- =========================
local function updateFOV()
    if not SilentAimModule.Config.ShowFOV then
        if State.FOVInstance then State.FOVInstance.Visible = false end
        return
    end

    if not State.FOVInstance then
        local circle = Drawing.new("Circle") -- Requires Executor with Drawing API
        circle.Thickness = 1
        circle.NumSides = 64
        circle.Filled = false
        circle.Transparency = 1
        State.FOVInstance = circle
    end

    State.FOVInstance.Visible = true
    State.FOVInstance.Radius = SilentAimModule.Config.FOVRadius
    State.FOVInstance.Position = UserInputService:GetMouseLocation()
    State.FOVInstance.Color = SilentAimModule.Config.FOVColor
end

-- =========================
-- Target Selector
-- =========================
function SilentAimModule:GetBestTarget()
    local bestTarget = nil
    local bestDistance = math.huge
    local mousePos = UserInputService:GetMouseLocation()
    
    local potentialTargets = {}

    -- 1. Gather Players
    if SilentAimModule.Config.TargetPlayers then
        for _, pl in pairs(Players:GetPlayers()) do
            if pl ~= LocalPlayer then table.insert(potentialTargets, pl) end
        end
    end
    
    -- 2. Gather NPCs (Specific to Blox Fruits structure)
    if SilentAimModule.Config.TargetNPCs then
        local enemies = Workspace:FindFirstChild("Enemies")
        if enemies then
            for _, npc in pairs(enemies:GetChildren()) do
                if npc:FindFirstChild("Humanoid") then table.insert(potentialTargets, npc) end
            end
        end
    end

    for _, target in pairs(potentialTargets) do
        local char, hum, root
        
        if target:IsA("Player") then
            char = target.Character
        else
            char = target -- It's an NPC Model
        end

        if char then
            hum = char:FindFirstChild("Humanoid")
            root = char:FindFirstChild("HumanoidRootPart")
        end

        if char and root and hum and hum.Health > 0 then
            -- A. Team Check
            if target:IsA("Player") and SilentAimModule.Config.TeamCheck and isAlly(target) then
                continue
            end

            -- B. Distance Check
            local dist3D = (root.Position - Camera.CFrame.Position).Magnitude
            if dist3D > SilentAimModule.Config.MaxDistance then continue end

            -- C. FOV Check
            local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position)
            local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
            
            if dist2D <= SilentAimModule.Config.FOVRadius then
                -- D. Hitbox Priority & Visibility
                local selectedHitbox = nil
                
                -- Check hitboxes in order
                for _, partName in ipairs(SilentAimModule.Config.HitboxPriority) do
                    local part = char:FindFirstChild(partName)
                    if part then
                        if SilentAimModule.Config.VisibleCheck then
                            if isVisible(Camera.CFrame.Position, part) then
                                selectedHitbox = part
                                break -- Found best visible part
                            end
                        else
                            selectedHitbox = part
                            break -- Found best part (no vis check)
                        end
                    end
                end

                if selectedHitbox then
                    -- Selection Logic: Prioritize closest to Mouse cursor
                    if dist2D < bestDistance then
                        bestDistance = dist2D
                        bestTarget = target
                        State.CurrentHitbox = selectedHitbox
                    end
                end
            end
        end
    end

    State.CurrentTarget = bestTarget
    return bestTarget
end

-- =========================
-- Hooks & Core Logic
-- =========================
local function OnBeforeFire(ctx)
    -- Placeholder: Can be used to check weapon cooldowns or specific conditions
    return true
end

local function OnAfterFire(ctx)
    -- Placeholder: Analytics or chaining
end

function SilentAimModule:InitHooks()
    local mt = getrawmetatable(game)
    setreadonly(mt, false)
    
    local oldNamecall = mt.__namecall
    
    mt.__namecall = newcclosure(function(self, ...)
        local args = {...}
        local method = getnamecallmethod()
        
        -- Intercept FireServer / InvokeServer
        if (method == "FireServer" or method == "InvokeServer") and SilentAimModule.Config.Enabled and State.IsAiming then
            if State.CurrentTarget and State.CurrentHitbox then
                
                -- Calculate Position
                local predictedPos = getPrediction(State.CurrentHitbox)
                
                -- Chance Check
                if math.random(1, 100) > SilentAimModule.Config.HitChance then
                     return oldNamecall(self, ...)
                end

                -- Hook: Before Fire
                if not OnBeforeFire({Target = State.CurrentTarget, Pos = predictedPos}) then
                    return oldNamecall(self, ...)
                end
                
                -- 1. Modify Vector3 Arguments (Standard FPS / Blox Fruits Skills)
                for i, arg in ipairs(args) do
                    if typeof(arg) == "Vector3" then
                        -- Replace Mouse Position with Target Position
                        args[i] = predictedPos
                    end
                end
                
                -- 2. Modify String Arguments (Specific Skill triggers)
                -- (Blox fruits specific logic preservation)
                if tostring(self) == "RemoteEvent" and typeof(args[1]) == "string" then
                    -- If needed, inject logic here
                end

                -- Hook: After Fire
                OnAfterFire({Target = State.CurrentTarget})

                return oldNamecall(self, unpack(args))
            end
        end
        
        return oldNamecall(self, ...)
    end)
    
    setreadonly(mt, true)
end

-- =========================
-- Input & Render Management
-- =========================
function SilentAimModule:Start()
    -- Render Loop
    RunService.RenderStepped:Connect(function()
        if SilentAimModule.Config.ShowFOV then
             -- Use pcall in case Drawing is not supported
             pcall(updateFOV)
        end
        
        if not SilentAimModule.Config.Enabled then 
            State.IsAiming = false
            return 
        end

        -- Update Aiming State based on Mode
        if SilentAimModule.Config.Mode == "Always" then
            State.IsAiming = true
        elseif SilentAimModule.Config.Mode == "KeyHold" then
            State.IsAiming = UserInputService:IsMouseButtonPressed(SilentAimModule.Config.Keybind) or UserInputService:IsKeyDown(SilentAimModule.Config.Keybind)
        end
        -- Note: Toggle mode handling is in InputBegan

        if State.IsAiming then
            SilentAimModule:GetBestTarget()
        else
            State.CurrentTarget = nil
            State.CurrentHitbox = nil
        end
    end)
    
    -- Input Listeners
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        
        if SilentAimModule.Config.Mode == "Toggle" then
            if input.UserInputType == SilentAimModule.Config.Keybind or input.KeyCode == SilentAimModule.Config.Keybind then
                State.IsAiming = not State.IsAiming
            end
        end
    end)

    -- Initialize the Hook
    SilentAimModule:InitHooks()
end

-- =========================
-- External API (For GUI Integration)
-- =========================
function SilentAimModule:Toggle(bool)
    SilentAimModule.Config.Enabled = bool
end

function SilentAimModule:SetTargetMode(mode) -- "Player" or "NPC" or "Both"
    if mode == "Player" then
        SilentAimModule.Config.TargetPlayers = true; SilentAimModule.Config.TargetNPCs = false
    elseif mode == "NPC" then
        SilentAimModule.Config.TargetPlayers = false; SilentAimModule.Config.TargetNPCs = true
    elseif mode == "Both" then
        SilentAimModule.Config.TargetPlayers = true; SilentAimModule.Config.TargetNPCs = true
    end
end

function SilentAimModule:SetFOV(radius)
    SilentAimModule.Config.FOVRadius = radius
end

function SilentAimModule:SetHitboxPriority(tableOfBodyParts)
    SilentAimModule.Config.HitboxPriority = tableOfBodyParts
end

return SilentAimModule
