local SharedLib = {}

-- // SERVICES //
local Services = {
    UserInputService = game:GetService("UserInputService"),
    RunService = game:GetService("RunService"),
    HttpService = game:GetService("HttpService"),
    Workspace = game:GetService("Workspace"),
    CoreGui = game:GetService("CoreGui")
}

-- // 1. LOGGER & PROFILER //
-- Responsibilities: Debugging, Performance Monitoring, Levels
SharedLib.Logger = {
    LogLevels = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 },
    CurrentLevel = 1, -- Default to INFO
    Prefix = "[SYSTEM]",
    Timings = {}
}

function SharedLib.Logger:Log(level, msg)
    if level >= self.CurrentLevel then
        local tag = (level == 0 and "[DBG]") or (level == 2 and "[WRN]") or (level == 3 and "[ERR]") or "[INF]"
        print(string.format("%s %s %s", self.Prefix, tag, tostring(msg)))
    end
end

function SharedLib.Logger:Profile(label, func)
    local start = os.clock()
    local result = func()
    local duration = (os.clock() - start) * 1000 -- ms
    
    -- Moving average for smoother profiling
    local prev = self.Timings[label] or duration
    self.Timings[label] = (prev * 0.9) + (duration * 0.1)
    
    return result
end

function SharedLib.Logger:GetMetrics()
    return self.Timings
end

-- // 2. UTILS (Math, Prediction, LOS) //
-- Responsibilities: Pure functions, Vector math, Physics helpers
SharedLib.Utils = {}

function SharedLib.Utils.Lerp(a, b, t)
    return a + (b - a) * t
end

function SharedLib.Utils.Clamp(val, min, max)
    return math.min(math.max(val, min), max)
end

function SharedLib.Utils.PredictPosition(originPart, targetPart, projectileSpeed)
    local distance = (targetPart.Position - originPart.Position).Magnitude
    local timeToTravel = distance / projectileSpeed
    return targetPart.Position + (targetPart.Velocity * timeToTravel)
end

function SharedLib.Utils.IsVisible(origin, target, ignoreList)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignoreList or {}
    params.IgnoreWater = true

    local dir = target.Position - origin.Position
    local result = Services.Workspace:Raycast(origin.Position, dir, params)

    -- If we hit nothing, or we hit the target (or a child of the target), it is visible
    if not result then return true end
    if result.Instance:IsDescendantOf(target.Parent) then return true end
    return false
end

-- // 3. POOLING (Memory Optimization) //
-- Responsibilities: Reuse tables/UI to prevent GC spikes in loops
SharedLib.Pools = {
    Tables = {},
    UI = {}
}

function SharedLib.Pools:GetTable()
    if #self.Tables > 0 then
        return table.remove(self.Tables)
    end
    return {}
end

function SharedLib.Pools:ReleaseTable(t)
    table.clear(t)
    table.insert(self.Tables, t)
end

function SharedLib.Pools:GetUI(template, parent)
    -- Simple example: In reality, you'd key this by template name
    local item = template:Clone()
    item.Parent = parent
    return item
end

-- // 4. EVENT BUS (Decoupled Comms) //
-- Responsibilities: Pub/Sub pattern
SharedLib.EventBus = {
    _subs = {}
}

function SharedLib.EventBus:Subscribe(event, callback)
    if not self._subs[event] then self._subs[event] = {} end
    table.insert(self._subs[event], callback)
    
    -- Return Disconnect handle
    return {
        Disconnect = function()
            for i, v in ipairs(self._subs[event]) do
                if v == callback then
                    table.remove(self._subs[event], i)
                    break
                end
            end
        end
    }
end

function SharedLib.EventBus:Publish(event, ...)
    if self._subs[event] then
        for _, cb in ipairs(self._subs[event]) do
            task.spawn(cb, ...)
        end
    end
end

-- // 5. INPUT MANAGER (Abstraction) //
-- Responsibilities: Remapping, Logical Actions, PC Support
SharedLib.Input = {
    Keybinds = {
        -- Defaults
        ToggleMenu = Enum.KeyCode.RightControl,
        ToggleESP = Enum.KeyCode.F4,
        AimLock = Enum.UserInputType.MouseButton2,
        Dash = Enum.KeyCode.Q
    },
    ActiveStates = {}
}

function SharedLib.Input:IsActionActive(actionName)
    local bind = self.Keybinds[actionName]
    if not bind then return false end
    
    if typeof(bind) == "EnumItem" then
        if bind.EnumType == Enum.KeyCode then
            return Services.UserInputService:IsKeyDown(bind)
        elseif bind.EnumType == Enum.UserInputType then
            return Services.UserInputService:IsMouseButtonPressed(bind)
        end
    end
    return false
end

function SharedLib.Input:Rebind(action, newKey)
    self.Keybinds[action] = newKey
    SharedLib.Logger:Log(1, "Rebound " .. action .. " to " .. tostring(newKey))
end

-- // 6. CONFIG MANAGER (Persistence) //
-- Responsibilities: JSON Save/Load, Versioning, Safety
SharedLib.Config = {
    FileName = "MyScriptConfig_v1.json",
    CurrentVersion = "1.0.0",
    Data = {}
}

local DEFAULT_CONFIG = {
    Version = "1.0.0",
    Visuals = { Enabled = true, Box = true, Tracers = false },
    Combat = { Enabled = false, FOV = 100 },
    Safety = { AntiBan = true, DelayMs = 50 } -- Safety toggle example
}

function SharedLib.Config:Load()
    -- Check for executor file support (writefile/readfile)
    if not makefolder or not writefile or not readfile then 
        SharedLib.Logger:Log(2, "File System not supported. Using Defaults.")
        self.Data = DEFAULT_CONFIG
        return 
    end

    if isfile(self.FileName) then
        local content = readfile(self.FileName)
        local success, decoded = pcall(Services.HttpService.JSONDecode, Services.HttpService, content)
        if success then
            self.Data = decoded
            self:Migrate()
        else
            self.Data = DEFAULT_CONFIG
        end
    else
        self.Data = DEFAULT_CONFIG
        self:Save()
    end
end

function SharedLib.Config:Save()
    if writefile then
        local success, encoded = pcall(Services.HttpService.JSONEncode, Services.HttpService, self.Data)
        if success then
            writefile(self.FileName, encoded)
        end
    end
end

function SharedLib.Config:Migrate()
    -- Handle version upgrades (Example: 1.0.0 -> 1.0.1)
    if self.Data.Version ~= self.CurrentVersion then
        self.Data.Version = self.CurrentVersion
        -- Add missing keys from defaults
        for k, v in pairs(DEFAULT_CONFIG) do
            if self.Data[k] == nil then self.Data[k] = v end
        end
        self:Save()
    end
end

-- // 7. TASK RUNNER //
-- Responsibilities: Throttling, Canceling, Loops
SharedLib.Tasks = {
    _tasks = {}
}

function SharedLib.Tasks:Loop(name, delay, callback)
    if self._tasks[name] then self._tasks[name]:Disconnect() end
    
    local lastRun = 0
    self._tasks[name] = Services.RunService.Heartbeat:Connect(function()
        if tick() - lastRun >= delay then
            lastRun = tick()
            -- Safety: Wrap in pcall to prevent loop crash
            local success, err = pcall(callback)
            if not success then
                SharedLib.Logger:Log(3, "Task Error ["..name.."]: " .. err)
            end
        end
    end)
end

function SharedLib.Tasks:Cancel(name)
    if self._tasks[name] then
        self._tasks[name]:Disconnect()
        self._tasks[name] = nil
    end
end

-- // INITIALIZATION //
function SharedLib:Init()
    self.Logger:Log(1, "Initializing Shared Libraries...")
    self.Config:Load()
    
    -- Desktop specific: Check Input Service capability
    if Services.UserInputService.KeyboardEnabled and Services.UserInputService.MouseEnabled then
        self.Logger:Log(1, "PC Environment Detected. Enhanced Inputs Active.")
    end
    
    self.Logger:Log(1, "Shared Libs Loaded.")
end

return SharedLib
