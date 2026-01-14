local StuffsModule = {}

-- // SERVICES //
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

-- // LOCAL PLAYER & CONSTANTS //
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- // INTERNAL STATE //
local State = {
    FpsBoost = false,
    InfEnergy = false,
    FastAttack = false,
    WalkWater = false,
    PingsFps = false,
    FogRemoved = false,
    LavaRemoved = false
}

-- Connection Manager to prevent memory leaks
local Connections = {}
local function ClearConnection(name)
    if Connections[name] then
        Connections[name]:Disconnect()
        Connections[name] = nil
    end
end

-- // UTILITIES & NOTIFICATIONS //
local Utils = {}

function Utils.Notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title;
            Text = text;
            Duration = duration or 3;
        })
    end)
end

function Utils.GetCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

function Utils.IsAlive(char)
    local hum = char and char:FindFirstChild("Humanoid")
    return hum and hum.Health > 0
end

-- // --- SECTION 1: UI TOOLS (FPS & PING) --- //
local GuiComponents = {}

function GuiComponents.ToggleFPS(state)
    ClearConnection("FpsLoop")
    
    local guiName = "FpsPingGui"
    local existingGui = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild(guiName)
    
    if not state then
        if existingGui then existingGui.Enabled = false end
        return
    end

    if not existingGui then
        local ScreenGui = Instance.new("ScreenGui")
        ScreenGui.Name = guiName
        ScreenGui.ResetOnSpawn = false
        ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

        local Label = Instance.new("TextLabel")
        Label.Name = "Label"
        Label.Size = UDim2.new(0, 150, 0, 25)
        Label.Position = UDim2.new(1, -20, 0, 10)
        Label.AnchorPoint = Vector2.new(1, 0)
        Label.BackgroundTransparency = 1
        Label.TextColor3 = Color3.new(1, 1, 1)
        Label.Font = Enum.Font.GothamBold
        Label.TextSize = 18
        Label.TextXAlignment = Enum.TextXAlignment.Right
        Label.RichText = true
        Label.TextStrokeTransparency = 0.5
        Label.Parent = ScreenGui
        existingGui = ScreenGui
    end

    existingGui.Enabled = true
    local label = existingGui:FindFirstChild("Label")
    
    local lastTime = tick()
    local frameCount = 0

    Connections["FpsLoop"] = RunService.RenderStepped:Connect(function()
        frameCount = frameCount + 1
        if tick() - lastTime >= 1 then
            local fps = frameCount
            frameCount = 0
            lastTime = tick()

            local ping = math.floor(LocalPlayer:GetNetworkPing() * 2000) -- Convert to ms approximation

            local fpsColor = fps >= 50 and "00FF00" or (fps >= 30 and "FFA500" or "FF0000")
            local pingColor = ping <= 80 and "00FF00" or (ping <= 150 and "FFFF00" or "FF0000")

            if label then
                label.Text = string.format(
                    '<font color="#%s">FPS: %d</font>  |  <font color="#%s">Ping: %dms</font>',
                    fpsColor, fps, pingColor, ping
                )
            end
        end
    end)
end

-- // --- SECTION 2: ENVIRONMENT MODS --- //
local Environment = {}

function Environment.BoostFPS(state)
    if not state then 
        -- Note: FPS Boost is usually destructive and cannot be fully undone without rejoining
        ClearConnection("FpsBoostListener")
        return 
    end

    local function OptimizeObject(v)
        if v:IsA("PostEffect") or v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Explosion") then
            v.Enabled = false
        elseif v:IsA("Decal") or v:IsA("Texture") then
            v:Destroy()
        elseif v:IsA("BasePart") and not v:IsA("MeshPart") then
            v.Material = Enum.Material.SmoothPlastic
            v.Reflectance = 0
            v.CastShadow = false
        elseif v:IsA("MeshPart") then
            v.CastShadow = false
            v.Reflectance = 0
            v.Material = Enum.Material.SmoothPlastic
        end
    end

    -- Initial cleanup
    Lighting.GlobalShadows = false
    Lighting.FogEnd = 9e9
    if Workspace:FindFirstChild("Terrain") then
        Workspace.Terrain.WaterWaveSize = 0
        Workspace.Terrain.WaterReflectance = 0
    end

    for _, v in pairs(Workspace:GetDescendants()) do
        OptimizeObject(v)
    end

    -- Keep cleaning new objects
    Connections["FpsBoostListener"] = Workspace.DescendantAdded:Connect(function(v)
        task.wait() -- Yield briefly to let properties load
        OptimizeObject(v)
    end)
    
    Utils.Notify("System", "FPS Boost Enabled (Destructive)", 3)
end

function Environment.RemoveFog(state)
    if state then
        Lighting.FogEnd = 100000
        for _, v in pairs(Lighting:GetDescendants()) do
            if v:IsA("Atmosphere") then v:Destroy() end
        end
    end
end

function Environment.RemoveLava(state)
    if state then
        for _, v in pairs(Workspace:GetDescendants()) do
            if v.Name == "Lava" then v:Destroy() end
        end
        for _, v in pairs(ReplicatedStorage:GetDescendants()) do
            if v.Name == "Lava" then v:Destroy() end
        end
    end
end

function Environment.WalkOnWater(state)
    local map = Workspace:FindFirstChild("Map")
    local water = map and map:FindFirstChild("WaterBase-Plane")
    if water then
        water.Size = state and Vector3.new(1000, 110, 1000) or Vector3.new(1000, 80, 1000)
        water.CanCollide = state
    end
end

-- // --- SECTION 3: PLAYER MODS (Infinite Energy) --- //
function StuffsModule:SetINFEnergy(state)
    State.InfEnergy = state
    ClearConnection("InfEnergy")

    local function HookEnergy(char)
        if not State.InfEnergy then return end
        local energy = char:WaitForChild("Energy", 3)
        if energy then
            Connections["InfEnergy"] = energy.Changed:Connect(function()
                if State.InfEnergy then energy.Value = energy.MaxValue end
            end)
            energy.Value = energy.MaxValue
        end
    end

    if state then
        if LocalPlayer.Character then HookEnergy(LocalPlayer.Character) end
        Connections["CharAdded_Energy"] = LocalPlayer.CharacterAdded:Connect(HookEnergy)
    else
        ClearConnection("CharAdded_Energy")
    end
end

-- // --- SECTION 4: COMBAT (Fast Attack) --- //
local FastAttackLogic = {}
FastAttackLogic.__index = FastAttackLogic

-- Configuration
local CombatConfig = {
    Distance = 60,
    Cooldown = 0, -- Instant
    MaxCombo = 4, -- Safe combo max
    Limbs = {"RightLowerArm", "LeftLowerArm", "UpperTorso", "Head"}
}

function FastAttackLogic.new()
    local self = setmetatable({
        Debounce = 0,
        ComboCount = 0,
        LastComboTime = 0,
        Net = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"),
        Remotes = ReplicatedStorage:WaitForChild("Remotes")
    }, FastAttackLogic)

    -- Attempt to grab game specific remotes safely
    pcall(function()
        self.RegisterAttack = self.Net:WaitForChild("RE/RegisterAttack")
        self.RegisterHit = self.Net:WaitForChild("RE/RegisterHit")
        self.CombatFlags = require(ReplicatedStorage.Modules.Flags).COMBAT_REMOTE_THREAD
        
        -- Safe dependency loading
        local combatCtrl = ReplicatedStorage.Controllers:FindFirstChild("CombatController")
        if combatCtrl then
            self.ShootFunction = debug.getupvalue(require(combatCtrl).Attack, 9)
        end
        
        local localScript = LocalPlayer:WaitForChild("PlayerScripts"):FindFirstChildOfClass("LocalScript")
        if localScript and getscriptclosure then
             -- Logic dependent on specific executor capabilities
             -- self.HitFunction = ... (Simplified for general stability)
        end
    end)
    return self
end

function FastAttackLogic:GetTargets()
    local targets = {}
    local char = LocalPlayer.Character
    if not char then return targets end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return targets end

    local function scan(folder)
        for _, v in pairs(folder:GetChildren()) do
            if v ~= char and Utils.IsAlive(v) and v:FindFirstChild("HumanoidRootPart") then
                local enemyRoot = v.HumanoidRootPart
                if (enemyRoot.Position - root.Position).Magnitude <= CombatConfig.Distance then
                    table.insert(targets, {v, enemyRoot})
                end
            end
        end
    end

    if Workspace:FindFirstChild("Enemies") then scan(Workspace.Enemies) end
    if Workspace:FindFirstChild("Characters") then scan(Workspace.Characters) end
    return targets
end

function FastAttackLogic:Attack()
    if tick() - self.Debounce < CombatConfig.Cooldown then return end
    
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    
    -- Only attack if holding a valid weapon
    if not tool or (tool.ToolTip ~= "Melee" and tool.ToolTip ~= "Sword" and tool.ToolTip ~= "Blox Fruit") then 
        return 
    end

    local targets = self:GetTargets()
    if #targets > 0 then
        -- Logic for Combo Counter
        if tick() - self.LastComboTime > 0.5 then self.ComboCount = 0 end
        self.ComboCount = (self.ComboCount % CombatConfig.MaxCombo) + 1
        self.LastComboTime = tick()
        self.Debounce = tick()

        -- Send Attack
        self.RegisterAttack:FireServer(CombatConfig.Cooldown)
        
        -- Send Hits
        for _, targetData in ipairs(targets) do
            local enemyRoot = targetData[2]
            -- Construct the hit structure required by the game
            self.RegisterHit:FireServer(enemyRoot, { {targetData[1], enemyRoot} })
        end
    end
end

local AttackInstance = FastAttackLogic.new()

function StuffsModule:SetFastAttack(state)
    State.FastAttack = state
    ClearConnection("FastAttack")
    
    if state then
        Utils.Notify("Combat", "Fast Attack Enabled", 2)
        Connections["FastAttack"] = RunService.Stepped:Connect(function()
            if State.FastAttack then
                pcall(function() AttackInstance:Attack() end)
            end
        end)
    else
        Utils.Notify("Combat", "Fast Attack Disabled", 2)
    end
end

-- // --- MODULE API --- //

function StuffsModule:SetFpsBoost(state)
    State.FpsBoost = state
    Environment.BoostFPS(state)
end

function StuffsModule:SetFog(state)
    State.FogRemoved = state
    Environment.RemoveFog(state)
end

function StuffsModule:SetLava(state)
    State.LavaRemoved = state
    Environment.RemoveLava(state)
end

function StuffsModule:SetWalkWater(state)
    State.WalkWater = state
    Environment.WalkOnWater(state)
end

function StuffsModule:SetPingsOrFps(state)
    State.PingsFps = state
    GuiComponents.ToggleFPS(state)
end

function StuffsModule:SetRejoinServer()
    if #Players:GetPlayers() <= 1 then
        LocalPlayer:Kick("\nRejoining...")
        task.wait()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    else
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end
end

-- Initialize Listeners for Character Reset (Keeps settings active on respawn)
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if State.WalkWater then Environment.WalkOnWater(true) end
    if State.InfEnergy then StuffsModule:SetINFEnergy(true) end
end)

return StuffsModule
