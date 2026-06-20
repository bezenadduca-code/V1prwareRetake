------------------------------------------------------------------------
-- ELLIOT AIMBOT - Fixed hook for BOTH RemoteEvent & RemoteFunction
------------------------------------------------------------------------
print("Elliot Aimbot Fixed loaded")

local lp = game.Players.LocalPlayer
local svc = {
    RS = game:GetService("ReplicatedStorage"),
    WS = game:GetService("Workspace"),
    Run = game:GetService("RunService"),
    Input = game:GetService("UserInputService"),
    Players = game:GetService("Players")
}

local elliotEnabled = false
local elliotConnection = nil
local elliotAutoRotBak = nil
local elliotPredDist = 5
local elliotAimType = "Camera + Character"
local elliotThrowDur = 1.0
local elliotIsThrowing = false
local elliotThrowTS = 0
local elliotHum, elliotHRP = nil, nil
local elliotTargetMode = "Low HP"
local elliotLastAimTime = 0

-- Setup character
local function setupChar(char)
    elliotHum = char:WaitForChild("Humanoid")
    elliotHRP = char:WaitForChild("HumanoidRootPart")
end

if lp.Character then setupChar(lp.Character) end
lp.CharacterAdded:Connect(setupChar)

------------------------------------------------------------------------
-- PART 1: HOOK REMOTES SAFELY (BOTH TYPES)
------------------------------------------------------------------------
local function hookRemotes()
    -- Get the network module
    local network = svc.RS:FindFirstChild("Modules")
    if network then
        network = network:FindFirstChild("Network")
        if network then
            network = network:FindFirstChild("Network")
        end
    end
    
    if not network then 
        print("[Elliot] ❌ Network module not found!")
        return 
    end
    
    -- Find ALL remotes in network
    for _, child in ipairs(network:GetChildren()) do
        if child:IsA("RemoteEvent") then
            print("[Elliot] 📡 Found RemoteEvent:", child.Name)
            
            -- Hook FireServer (Client -> Server)
            if child.FireServer then
                local oldFire = child.FireServer
                child.FireServer = function(self, ...)
                    local args = {...}
                    local argsStr = tostring(args)
                    
                    if argsStr and (argsStr:find("Throw") or argsStr:find("Pizza") or argsStr:find("pizza")) then
                        print("[Elliot] 🎯 RemoteEvent.FireServer caught!")
                        elliotIsThrowing = true
                        elliotThrowTS = tick()
                        task.delay(elliotThrowDur, function()
                            elliotIsThrowing = false
                        end)
                    end
                    
                    return oldFire(self, ...)
                end
                print("[Elliot] ✅ Hooked RemoteEvent.FireServer")
            end
            
        elseif child:IsA("RemoteFunction") then
            print("[Elliot] 📡 Found RemoteFunction:", child.Name)
            
            -- Hook InvokeServer (Client -> Server)
            if child.InvokeServer then
                local oldInvoke = child.InvokeServer
                child.InvokeServer = function(self, ...)
                    local args = {...}
                    local argsStr = tostring(args)
                    
                    if argsStr and (argsStr:find("Throw") or argsStr:find("Pizza") or argsStr:find("pizza")) then
                        print("[Elliot] 🎯 RemoteFunction.InvokeServer caught!")
                        elliotIsThrowing = true
                        elliotThrowTS = tick()
                        task.delay(elliotThrowDur, function()
                            elliotIsThrowing = false
                        end)
                    end
                    
                    return oldInvoke(self, ...)
                end
                print("[Elliot] ✅ Hooked RemoteFunction.InvokeServer")
            end
        end
    end
end

------------------------------------------------------------------------
-- PART 2: HOOK MODULE FUNCTIONS
------------------------------------------------------------------------
local function hookModules()
    local modules = svc.RS:FindFirstChild("Modules")
    if not modules then 
        print("[Elliot] ❌ Modules folder not found!")
        return 
    end
    
    -- Hook PredictProjectile module
    for _, child in ipairs(modules:GetChildren()) do
        if child.Name == "PredictProjectile" or string.find(child.Name, "Projectile") then
            local success, module = pcall(function()
                return require(child)
            end)
            
            if success and type(module) == "table" then
                -- Hook FindAngleToShootAt
                if module.FindAngleToShootAt then
                    local oldFunc = module.FindAngleToShootAt
                    module.FindAngleToShootAt = function(...)
                        print("[Elliot] 🎯 FindAngleToShootAt called!")
                        elliotIsThrowing = true
                        elliotThrowTS = tick()
                        task.delay(elliotThrowDur, function()
                            elliotIsThrowing = false
                        end)
                        return oldFunc(...)
                    end
                    print("[Elliot] ✅ Hooked FindAngleToShootAt")
                end
            end
        end
        
        -- Hook Behavior module
        if child.Name == "Behavior" then
            local success, module = pcall(function()
                return require(child)
            end)
            
            if success and type(module) == "table" then
                -- Hook HookThrowVisual
                if module.HookThrowVisual then
                    local oldFunc = module.HookThrowVisual
                    module.HookThrowVisual = function(...)
                        print("[Elliot] 🎯 HookThrowVisual called!")
                        elliotIsThrowing = true
                        elliotThrowTS = tick()
                        task.delay(elliotThrowDur, function()
                            elliotIsThrowing = false
                        end)
                        return oldFunc(...)
                    end
                    print("[Elliot] ✅ Hooked HookThrowVisual")
                end
            end
        end
    end
end

-- Install all hooks
task.wait(2)
hookRemotes()
hookModules()
print("[Elliot] ✅ All hooks installed!")

------------------------------------------------------------------------
-- PART 3: AIMBOT LOGIC
------------------------------------------------------------------------
local function findTarget()
    local sf = svc.WS:FindFirstChild("Players")
    if sf then sf = sf:FindFirstChild("Survivors") end
    if not sf then sf = svc.WS:FindFirstChild("Survivors") end
    if not sf or not elliotHRP then return nil end
    
    local best, bestVal = nil, math.huge
    for _, s in ipairs(sf:GetChildren()) do
        if s ~= lp.Character then
            local h = s:FindFirstChildOfClass("Humanoid")
            local r = s:FindFirstChild("HumanoidRootPart")
            if h and r and h.Health > 0 then
                local dist = (r.Position - elliotHRP.Position).Magnitude
                local val = elliotTargetMode == "Closest" and dist or h.Health
                if val < bestVal then
                    best = r
                    bestVal = val
                end
            end
        end
    end
    return best
end

local function aimAt(tgt)
    if not tgt or not tgt.Parent then return end
    
    local now = tick()
    if now - elliotLastAimTime < 0.05 then return end
    elliotLastAimTime = now
    
    local vel = tgt.AssemblyLinearVelocity
    local pos = tgt.Position
    local predPos = pos
    if vel.Magnitude > 10 then
        predPos = pos + (vel.Unit * elliotPredDist)
    end
    
    if elliotAimType == "HRP Aimbot" or elliotAimType == "Camera + Character" then
        if elliotHRP then
            if elliotAutoRotBak == nil then
                elliotAutoRotBak = elliotHum.AutoRotate
                elliotHum.AutoRotate = false
            end
            local dir = (predPos - elliotHRP.Position)
            local flat = Vector3.new(dir.X, 0, dir.Z).Unit
            elliotHRP.CFrame = CFrame.new(elliotHRP.Position) * 
                               CFrame.Angles(0, math.atan2(flat.X, flat.Z), 0)
        end
    end
    
    if elliotAimType == "Camera Aimbot" or elliotAimType == "Camera + Character" then
        local cam = svc.WS.CurrentCamera
        if cam then
            cam.CFrame = CFrame.lookAt(cam.CFrame.Position, predPos)
        end
    end
end

local function startAimbot()
    if elliotConnection then elliotConnection:Disconnect() end
    
    elliotConnection = svc.Run.RenderStepped:Connect(function()
        if not elliotEnabled or not elliotHum or not elliotHRP then
            if elliotAutoRotBak ~= nil then
                elliotHum.AutoRotate = elliotAutoRotBak
                elliotAutoRotBak = nil
            end
            return
        end
        
        local isThrowing = elliotIsThrowing and (tick() - elliotThrowTS) <= elliotThrowDur
        
        if not isThrowing then
            if elliotAutoRotBak ~= nil then
                elliotHum.AutoRotate = elliotAutoRotBak
                elliotAutoRotBak = nil
            end
            return
        end
        
        local tgt = findTarget()
        if tgt then
            aimAt(tgt)
        end
    end)
end

------------------------------------------------------------------------
-- PART 4: UI
------------------------------------------------------------------------
local function createUI()
    local ui = loadstring(game:HttpGet(
        "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
    ))()
    
    ui:AddTheme({
        Name = "ElliotTheme",
        Accent = Color3.fromHex("#FFD700"),
        Background = Color3.fromHex("#1A1410"),
        Outline = Color3.fromHex("#FFD700"),
        Text = Color3.fromHex("#FFF8DC"),
        Toggle = Color3.fromHex("#FFD700"),
        ToggleBar = Color3.fromHex("#8B6914"),
        WindowBackground = Color3.fromHex("#0F0D0A"),
    })
    ui:SetTheme("ElliotTheme")
    
    local win = ui:CreateWindow({
        Title = "Elliot Aimbot",
        Icon = "pizza",
        Author = "Elliot",
        Folder = "elliot-aimbot",
        Size = UDim2.fromOffset(480, 420),
        Transparent = true,
        Theme = "ElliotTheme",
        Resizable = true,
        SideBarWidth = 150,
    })
    
    local tab = win:Tab({ Title = "Elliot", Icon = "pizza" })
    local sec = tab:Section({ Title = "Pizza Throw Aimbot", Opened = true })
    
    sec:Toggle({
        Title = "Enable Aimbot",
        Type = "Checkbox",
        Default = false,
        Callback = function(v)
            elliotEnabled = v
            if v then
                startAimbot()
            else
                if elliotConnection then
                    elliotConnection:Disconnect()
                    elliotConnection = nil
                end
                if elliotAutoRotBak ~= nil and elliotHum then
                    elliotHum.AutoRotate = elliotAutoRotBak
                    elliotAutoRotBak = nil
                end
            end
        end
    })
    
    sec:Dropdown({
        Title = "Aimbot Type",
        Values = {"HRP Aimbot", "Camera Aimbot", "Camera + Character"},
        Default = "Camera + Character",
        Callback = function(v) elliotAimType = v end
    })
    
    sec:Dropdown({
        Title = "Target Mode",
        Values = {"Low HP", "Closest"},
        Default = "Low HP",
        Callback = function(v) elliotTargetMode = v end
    })
    
    sec:Slider({
        Title = "Prediction (studs)",
        Value = {Min = 0, Max = 50, Default = 5},
        Step = 1,
        Callback = function(v) elliotPredDist = v end
    })
    
    sec:Slider({
        Title = "Throw Duration (s)",
        Value = {Min = 0.1, Max = 3, Default = 1.0},
        Step = 0.1,
        Callback = function(v) elliotThrowDur = v end
    })
    
    print("[Elliot] UI Created!")
end

createUI()
print("[Elliot] ✅ Aimbot ready! Press L to toggle UI")