--[[
    Murder Mystery 2 (GameId 66654135)

    Role source: ReplicatedStorage.Remotes.Extras.GetPlayerData (RemoteFunction)
      returns { [playerName] = { Role = "Murderer"|"Sheriff"|"Hero"|"Innocent", Dead = bool, ... } }
      Empty between rounds.
    Fallback: tools in Backpack/Character ("Knife" -> murderer, "Gun" -> sheriff),
      which also catches an innocent picking up the dropped gun mid-round.
    Dropped gun: BasePart named "GunDrop" somewhere in Workspace.
    Coins: Workspace.<Map>.CoinContainer.Coin_Server (touch pickup, child MeshPart "CoinVisual").
]]

return function(Window, ctx)
    local Players      = game:GetService("Players")
    local RS           = game:GetService("ReplicatedStorage")
    local TweenService = game:GetService("TweenService")
    local LP           = Players.LocalPlayer

    local GetPlayerData = RS:WaitForChild("Remotes"):WaitForChild("Extras"):WaitForChild("GetPlayerData")

    local COLORS = {
        Murderer = Color3.fromRGB(255, 40, 40),
        Sheriff  = Color3.fromRGB(40, 120, 255),
        Innocent = Color3.fromRGB(60, 255, 90),
        Gun      = Color3.fromRGB(190, 80, 255),
        Coin     = Color3.fromRGB(255, 210, 40),
    }

    local opts = {
        roleEsp     = false,
        everyoneEsp = false,
        distance    = false,
        gunEsp      = false,
        roleNotify  = false,
        alert       = false,
        alertRange  = 30,
        autoGun     = false,
        coinEsp     = false,
        coinFarm    = false,
        farmSpeed   = 25,
    }

    local container = Instance.new("Folder")
    container.Name = "megab_hl"
    local okHui, hui = pcall(function() return gethui and gethui() end)
    container.Parent = (okHui and hui) or game:GetService("CoreGui")

    local highlights = {} -- [Player] = Highlight
    local billboards = {} -- [Player] = BillboardGui
    local gunHl, coinHl   -- single Highlights (gun part, whole CoinContainer)
    local roles = {}      -- [playerName] = role string from server

    ------------------------------------------------------------------ roles

    local function hasTool(plr, name)
        for _, c in ipairs({ plr:FindFirstChild("Backpack"), plr.Character }) do
            if c and c:FindFirstChild(name) then return true end
        end
        return false
    end

    -- "Murderer" | "Sheriff" | "Innocent" | nil (no round / dead)
    local function roleOf(plr)
        if hasTool(plr, "Knife") then return "Murderer" end
        if hasTool(plr, "Gun") then return "Sheriff" end
        local r = roles[plr.Name]
        if r == "Murderer" then return "Murderer" end
        if r == "Sheriff" or r == "Hero" then return "Sheriff" end
        if r == "Innocent" then return "Innocent" end
        return nil
    end

    local function findRole(role)
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and roleOf(plr) == role then return plr end
        end
        return nil
    end

    local function refreshRoles()
        local ok, data = pcall(GetPlayerData.InvokeServer, GetPlayerData)
        if not ok or type(data) ~= "table" then return end
        local new = {}
        for name, info in pairs(data) do
            if type(info) == "table" and not info.Dead then
                new[name] = info.Role
            end
        end
        roles = new
    end

    ------------------------------------------------------------------ helpers

    local function rootOf(char)
        return char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    end

    local function aliveChar(plr)
        local char = plr.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        return hum and hum.Health > 0 and rootOf(char) and char or nil
    end

    local function teleportTo(cf)
        if not aliveChar(LP) then return false end
        LP.Character:PivotTo(cf)
        return true
    end

    local function teleportToPlayer(plr)
        local target = plr and rootOf(plr.Character)
        if not target then return false end
        return teleportTo(target.CFrame * CFrame.new(0, 0, 3)) -- 3 studs behind
    end

    local function findGunDrop()
        return workspace:FindFirstChild("GunDrop", true)
    end

    local function findCoinContainer()
        return workspace:FindFirstChild("CoinContainer", true)
    end

    local function isLiveCoin(coin)
        if coin.Name ~= "Coin_Server" or not coin:IsA("BasePart") then return false end
        local vis = coin:FindFirstChild("CoinVisual")
        return vis ~= nil and vis.Transparency < 1
    end

    local function nearestCoin(from)
        local cc = findCoinContainer()
        if not cc then return nil end
        local best, bestDist
        for _, coin in ipairs(cc:GetChildren()) do
            if isLiveCoin(coin) then
                local d = (coin.Position - from).Magnitude
                if not bestDist or d < bestDist then best, bestDist = coin, d end
            end
        end
        return best
    end

    local function touch(part)
        local root = rootOf(LP.Character)
        if root and typeof(firetouchinterest) == "function" then
            pcall(firetouchinterest, root, part, 0)
            pcall(firetouchinterest, root, part, 1)
        end
    end

    local function notify(title, content)
        Window:Notify({ title = title, content = content, duration = 4 })
    end

    ------------------------------------------------------------------ visuals

    local function clear(plr)
        if highlights[plr] then highlights[plr]:Destroy() highlights[plr] = nil end
        if billboards[plr] then billboards[plr]:Destroy() billboards[plr] = nil end
    end

    local function makeBillboard()
        local bb = Instance.new("BillboardGui")
        bb.AlwaysOnTop = true
        bb.Size = UDim2.fromOffset(180, 40)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.LightInfluence = 0
        local label = Instance.new("TextLabel")
        label.Name = "Text"
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 14
        label.TextStrokeTransparency = 0.3
        label.Parent = bb
        bb.Parent = container
        return bb
    end

    local function wantHighlight(role)
        if role == "Murderer" or role == "Sheriff" then return opts.roleEsp end
        return opts.everyoneEsp
    end

    local function update(plr)
        if plr == LP then return end
        local char = plr.Character
        local role = roleOf(plr)
        if not char then return clear(plr) end
        local color = COLORS[role] or Color3.new(1, 1, 1) -- no role: lobby / dead / between rounds
        local special = role == "Murderer" or role == "Sheriff"

        -- highlight (players without a role only ever get a name label)
        if role and wantHighlight(role) then
            local h = highlights[plr]
            if not h then
                h = Instance.new("Highlight")
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.FillTransparency = 0.5
                h.OutlineTransparency = 0
                h.Parent = container
                highlights[plr] = h
            end
            h.Adornee = char
            h.FillColor = color
            h.OutlineColor = color
        elseif highlights[plr] then
            highlights[plr]:Destroy()
            highlights[plr] = nil
        end

        -- label: name (Everyone ESP) + role and distance (Display Distance, murderer/sheriff only)
        local lines = {}
        if opts.everyoneEsp then table.insert(lines, plr.DisplayName) end
        local head = char:FindFirstChild("Head")
        local myRoot, theirRoot = rootOf(LP.Character), rootOf(char)
        if opts.distance and special and myRoot and theirRoot then
            local dist = (myRoot.Position - theirRoot.Position).Magnitude
            table.insert(lines, ("%s · %d studs"):format(role, math.floor(dist + 0.5)))
        end
        if #lines > 0 and head then
            local bb = billboards[plr] or makeBillboard()
            billboards[plr] = bb
            bb.Adornee = head
            bb.Text.Text = table.concat(lines, "\n")
            bb.Text.TextColor3 = color
        elseif billboards[plr] then
            billboards[plr]:Destroy()
            billboards[plr] = nil
        end
    end

    local function singleHighlight(current, want, adornee, color, fill)
        if not (want and adornee) then
            if current then current:Destroy() end
            return nil
        end
        if not current then
            current = Instance.new("Highlight")
            current.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            current.FillColor = color
            current.OutlineColor = color
            current.FillTransparency = fill
            current.Parent = container
        end
        current.Adornee = adornee
        return current
    end

    ------------------------------------------------------------------ murderer alert

    local alertInRange = false
    local lastAlert = 0
    local function checkAlert()
        if not opts.alert or roleOf(LP) == "Murderer" then alertInRange = false return end
        local murd = findRole("Murderer")
        local a = murd and rootOf(murd.Character)
        local b = rootOf(LP.Character)
        if not (a and b) then alertInRange = false return end
        local dist = (a.Position - b.Position).Magnitude
        local inRange = dist <= opts.alertRange
        -- fire on entering range, and again every 5s while they stay close
        if inRange and (not alertInRange or os.clock() - lastAlert > 5) then
            lastAlert = os.clock()
            notify("⚠ Murderer nearby", ("%s is %d studs away"):format(murd.DisplayName, math.floor(dist + 0.5)))
        end
        alertInRange = inRange
    end

    ------------------------------------------------------------------ role notify

    local announced = {} -- [role] = playerName already announced this round
    local function checkAnnounce()
        if next(roles) == nil then table.clear(announced) return end -- round over
        if not opts.roleNotify then return end
        for _, role in ipairs({ "Murderer", "Sheriff" }) do
            local plr = findRole(role)
            if plr and announced[role] ~= plr.Name then
                announced[role] = plr.Name
                notify(role, plr.DisplayName .. " (@" .. plr.Name .. ")")
            end
        end
    end

    ------------------------------------------------------------------ auto grab gun

    local grabbing = false
    local function tryGrabGun()
        if grabbing or not opts.autoGun then return end
        local gun = findGunDrop()
        if not gun or not aliveChar(LP) then return end
        local myRole = roleOf(LP)
        if myRole == "Murderer" or myRole == "Sheriff" then return end -- murderer can't, sheriff already has one
        grabbing = true
        task.spawn(function()
            local back = LP.Character:GetPivot()
            teleportTo(gun.CFrame + Vector3.new(0, 1, 0))
            touch(gun)
            local t = os.clock()
            while gun.Parent and os.clock() - t < 1 do task.wait(0.05) end
            local got = not gun.Parent or hasTool(LP, "Gun")
            teleportTo(back)
            if got then notify("Auto Grab Gun", "Gun picked up.") end
            task.wait(got and 1 or 2) -- cooldown before retrying
            grabbing = false
        end)
    end

    ------------------------------------------------------------------ coin farm

    local farmTween
    local function stopFarmTween()
        if farmTween then farmTween:Cancel() farmTween = nil end
    end

    local function farmStep()
        local char = aliveChar(LP)
        if not char then return task.wait(1) end
        local root = rootOf(char)
        local coin = nearestCoin(root.Position)
        if not coin then return task.wait(1) end

        local dist = (coin.Position - root.Position).Magnitude
        farmTween = TweenService:Create(root, TweenInfo.new(dist / opts.farmSpeed, Enum.EasingStyle.Linear),
            { CFrame = CFrame.new(coin.Position) })
        farmTween:Play()
        -- stop early if the coin is taken by someone else or the farm is switched off
        while farmTween and farmTween.PlaybackState == Enum.PlaybackState.Playing do
            if not opts.coinFarm or not isLiveCoin(coin) or not coin.Parent then break end
            task.wait(0.05)
        end
        stopFarmTween()
        if coin.Parent then touch(coin) end
        task.wait(0.15)
    end

    ------------------------------------------------------------------ loops

    local alive = true
    local conns = {}
    local function teardown()
        alive = false
        stopFarmTween()
        for _, c in ipairs(conns) do c:Disconnect() end
        table.clear(conns)
        container:Destroy()
    end

    task.spawn(function() -- server role poll every 2s
        while alive do
            refreshRoles()
            checkAnnounce()
            task.wait(2)
        end
    end)
    task.spawn(function() -- visuals + alerts every 0.2s
        while alive do
            if Window.unloaded then teardown() break end -- unloaded via Rayfield's own UI
            for _, plr in ipairs(Players:GetPlayers()) do update(plr) end
            gunHl  = singleHighlight(gunHl, opts.gunEsp, findGunDrop(), COLORS.Gun, 0.3)
            coinHl = singleHighlight(coinHl, opts.coinEsp, findCoinContainer(), COLORS.Coin, 0.4)
            checkAlert()
            tryGrabGun()
            task.wait(0.2)
        end
    end)
    task.spawn(function() -- coin farm
        while alive do
            if opts.coinFarm then farmStep() else task.wait(0.3) end
        end
    end)

    ------------------------------------------------------------------ UI: Basic

    local Tab = Window:CreateTab({ name = "Basic" })

    Tab:CreateSection({ name = "ESP" })
    Tab:CreateToggle({
        name = "Sheriff and Murderer ESP",
        description = "Murderer red, sheriff blue.",
        flag = "mm2_esp_roles",
        callback = function(v) opts.roleEsp = v end,
    })
    Tab:CreateToggle({
        name = "Everyone ESP",
        description = "Innocents green, plus everyone's name above their head.",
        flag = "mm2_esp_everyone",
        callback = function(v) opts.everyoneEsp = v end,
    })
    Tab:CreateToggle({
        name = "Display Distance",
        description = "Role and distance in studs above murderer and sheriff.",
        flag = "mm2_esp_distance",
        callback = function(v) opts.distance = v end,
    })
    Tab:CreateToggle({
        name = "Dropped Gun ESP",
        description = "Purple highlight on the gun after the sheriff dies.",
        flag = "mm2_esp_gun",
        callback = function(v) opts.gunEsp = v end,
    })

    Tab:CreateSection({ name = "Alerts" })
    Tab:CreateToggle({
        name = "Role Notify",
        description = "Notification naming murderer and sheriff each round.",
        flag = "mm2_role_notify",
        callback = function(v)
            opts.roleNotify = v
            if v then table.clear(announced) end
        end,
    })
    Tab:CreateToggle({
        name = "Murderer Alert",
        description = "Warns you when the murderer gets close.",
        flag = "mm2_alert",
        callback = function(v) opts.alert = v alertInRange = false end,
    })
    Tab:CreateSlider({
        name = "Alert Distance",
        range = { 10, 100 },
        increment = 5,
        value = 30,
        suffix = " studs",
        flag = "mm2_alert_range",
        callback = function(v) opts.alertRange = v end,
    })

    Tab:CreateSection({ name = "Teleport" })
    local function tpRole(role)
        refreshRoles()
        local plr = findRole(role)
        if not plr then return notify("Teleport", "No " .. role:lower() .. " found.") end
        if not teleportToPlayer(plr) then notify("Teleport", "Could not reach " .. plr.Name .. ".") end
    end
    Tab:CreateButton({ name = "TP to Murderer", callback = function() tpRole("Murderer") end })
    Tab:CreateButton({ name = "TP to Sheriff",  callback = function() tpRole("Sheriff") end })
    Tab:CreateButton({
        name = "TP to Dropped Gun",
        callback = function()
            local gun = findGunDrop()
            if not gun then return notify("Teleport", "No dropped gun on the map.") end
            teleportTo(gun.CFrame + Vector3.new(0, 3, 0))
        end,
    })
    Tab:CreateToggle({
        name = "Auto Grab Gun",
        description = "When the gun drops: teleport to it, pick it up, come back.",
        flag = "mm2_auto_gun",
        callback = function(v) opts.autoGun = v end,
    })

    local function playerNames()
        local names = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then table.insert(names, plr.Name) end
        end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        return names
    end

    local selected
    local dropdown = Tab:CreateDropdown({
        name = "Player",
        options = playerNames(),
        placeholder = "Select a player",
        forgetState = true,
        callback = function(name) selected = name end,
    })
    Tab:CreateButton({
        name = "TP to Selected Player",
        callback = function()
            local plr = selected and Players:FindFirstChild(selected)
            if not plr then return notify("Teleport", "Select a player first.") end
            if not teleportToPlayer(plr) then notify("Teleport", plr.Name .. " has no character.") end
        end,
    })

    ------------------------------------------------------------------ UI: Farm

    local Farm = Window:CreateTab({ name = "Farm" })
    Farm:CreateSection({ name = "Coins" })
    Farm:CreateToggle({
        name = "Coin ESP",
        description = "Yellow highlight on every coin on the map.",
        flag = "mm2_coin_esp",
        callback = function(v) opts.coinEsp = v end,
    })
    Farm:CreateToggle({
        name = "Coin Farm",
        description = "Flies you to the nearest coin, one after another.",
        flag = "mm2_coin_farm",
        forgetState = true, -- never auto-start farming on load
        callback = function(v)
            opts.coinFarm = v
            if not v then stopFarmTween() end
        end,
    })
    Farm:CreateSlider({
        name = "Farm Speed",
        description = "Higher is faster but easier to get flagged.",
        range = { 16, 60 },
        increment = 1,
        value = 25,
        suffix = " studs/s",
        flag = "mm2_farm_speed",
        callback = function(v) opts.farmSpeed = v end,
    })

    table.insert(conns, Players.PlayerAdded:Connect(function() dropdown:Refresh(playerNames()) end))
    table.insert(conns, Players.PlayerRemoving:Connect(function(plr)
        clear(plr)
        task.defer(function() dropdown:Refresh(playerNames()) end)
    end))

    ctx.onUnload(teardown)
end
