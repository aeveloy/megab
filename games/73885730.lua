--[[
    Prison Life (GameId 73885730)

    Guns: Workspace.Prison_ITEMS.giver.<Gun> models. Remotes.InteractWithItem:InvokeServer(anyPartOfGun)
      returns a message ("You picked up a AK-47." / "Too many primary weapons, ...").
      Server checks you are within ~12 studs, so teleport next to the gun first. Max 2 primaries.
      M4A1 is a gamepass gun: invoking it opens a purchase prompt, so it is excluded.
    Teams: Remotes.RequestTeamChange:InvokeServer(Team, 1). Switching Guards <-> Inmates directly is
      refused; go through Teams.Neutral first (same as the game's menu).
    Escape: an Inmate standing at the criminal base spawn (-975, 105, 2057) becomes a Criminal instantly.
]]

return function(Window, ctx)
    local Players    = game:GetService("Players")
    local RS         = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local Teams      = game:GetService("Teams")
    local LP         = Players.LocalPlayer

    local Remotes          = RS:WaitForChild("Remotes")
    local InteractWithItem = Remotes:WaitForChild("InteractWithItem")
    local RequestTeamChange = Remotes:WaitForChild("RequestTeamChange")

    local CRIMINAL_BASE = Vector3.new(-975, 105, 2057)

    local opts = {
        esp     = false,
        labels  = false,
        speedOn = false,
        speed   = 30,
        jumpOn  = false,
        jump    = 80,
        noclip  = false,
    }

    local alive = true
    local conns = {}

    local container = Instance.new("Folder")
    container.Name = "megab_hl"
    local okHui, hui = pcall(function() return gethui and gethui() end)
    container.Parent = (okHui and hui) or game:GetService("CoreGui")

    local function teardown()
        alive = false
        for _, c in ipairs(conns) do c:Disconnect() end
        table.clear(conns)
        container:Destroy()
    end

    local function notify(title, content)
        Window:Notify({ title = title, content = content, duration = 4 })
    end

    local function rootOf(char)
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function humanoid()
        return LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    end

    local function teleport(pos)
        local char = LP.Character
        if not rootOf(char) then return false end
        char:PivotTo(CFrame.new(pos + Vector3.new(0, 3, 0)))
        return true
    end

    -- InvokeServer that gives up after `timeout` seconds instead of hanging the caller
    local function invokeWithTimeout(remote, timeout, ...)
        local args = table.pack(...)
        local result, done = nil, false
        task.spawn(function()
            local ok, r = pcall(remote.InvokeServer, remote, table.unpack(args, 1, args.n))
            result, done = ok and r or nil, true
        end)
        local t = os.clock()
        while not done and os.clock() - t < timeout do task.wait(0.1) end
        return result, done
    end

    ------------------------------------------------------------------ ESP

    local highlights, billboards = {}, {}

    local function clear(plr)
        if highlights[plr] then highlights[plr]:Destroy() highlights[plr] = nil end
        if billboards[plr] then billboards[plr]:Destroy() billboards[plr] = nil end
    end

    local function makeBillboard()
        local bb = Instance.new("BillboardGui")
        bb.AlwaysOnTop = true
        bb.Size = UDim2.fromOffset(180, 36)
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

    local function update(plr)
        if plr == LP then return end
        local char = plr.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not char or not hum or hum.Health <= 0 then return clear(plr) end
        local color = plr.Team and plr.TeamColor.Color or Color3.new(1, 1, 1)

        if opts.esp then
            local h = highlights[plr]
            if not h then
                h = Instance.new("Highlight")
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.FillTransparency = 0.55
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

        local head = char:FindFirstChild("Head")
        local mine, theirs = rootOf(LP.Character), rootOf(char)
        if opts.labels and head and mine and theirs then
            local bb = billboards[plr] or makeBillboard()
            billboards[plr] = bb
            bb.Adornee = head
            local dist = math.floor((mine.Position - theirs.Position).Magnitude + 0.5)
            bb.Text.Text = ("%s\n%s · %d studs"):format(plr.DisplayName, plr.Team and plr.Team.Name or "?", dist)
            bb.Text.TextColor3 = color
        elseif billboards[plr] then
            billboards[plr]:Destroy()
            billboards[plr] = nil
        end
    end

    ------------------------------------------------------------------ guns

    local EXCLUDED_GUNS = { ["M4A1"] = true } -- gamepass: opens a purchase prompt

    local function gunNames()
        local names, seen = {}, {}
        local giver = workspace:FindFirstChild("Prison_ITEMS") and workspace.Prison_ITEMS:FindFirstChild("giver")
        if not giver then return names end
        for _, m in ipairs(giver:GetChildren()) do
            if m:IsA("Model") and not seen[m.Name] and not EXCLUDED_GUNS[m.Name] then
                seen[m.Name] = true
                table.insert(names, m.Name)
            end
        end
        table.sort(names)
        return names
    end

    local function getGun(name)
        local giver = workspace.Prison_ITEMS.giver
        local model = giver:FindFirstChild(name)
        local part = model and model:FindFirstChildWhichIsA("BasePart", true)
        local root = rootOf(LP.Character)
        if not part or not root then return notify("Guns", "Can't find " .. name .. ".") end

        local back = root.CFrame
        teleport(part.Position)
        task.wait(0.6)
        local msg, done = invokeWithTimeout(InteractWithItem, 5, part)
        task.wait(0.4)
        if rootOf(LP.Character) then LP.Character:PivotTo(back) end
        notify("Guns", done and tostring(msg or ("No reply for " .. name)) or ("Timed out getting " .. name))
    end

    ------------------------------------------------------------------ teams / escape

    local function changeTeam(team)
        if LP.Team == team then return true end
        if LP.Team ~= Teams.Neutral then
            invokeWithTimeout(RequestTeamChange, 8, Teams.Neutral, 1)
            task.wait(3)
        end
        invokeWithTimeout(RequestTeamChange, 8, team, 1)
        local t = os.clock()
        while LP.Team ~= team and os.clock() - t < 6 do task.wait(0.2) end
        return LP.Team == team
    end

    local function escape()
        if LP.Team == Teams.Criminals then return notify("Escape", "You're already a criminal.") end
        if LP.Team ~= Teams.Inmates then
            notify("Escape", "Switching you to Inmates first...")
            if not changeTeam(Teams.Inmates) then return notify("Escape", "Couldn't switch to Inmates.") end
            task.wait(2) -- let the new character spawn
        end
        local char = LP.Character or LP.CharacterAdded:Wait()
        char:WaitForChild("HumanoidRootPart", 5)
        teleport(CRIMINAL_BASE)
        local t = os.clock()
        while LP.Team ~= Teams.Criminals and os.clock() - t < 6 do task.wait(0.2) end
        notify("Escape", LP.Team == Teams.Criminals and "You escaped! You're a criminal now." or "Escape didn't work.")
    end

    ------------------------------------------------------------------ movement

    local function applyMovement()
        local hum = humanoid()
        if not hum then return end
        if opts.speedOn then hum.WalkSpeed = opts.speed end
        if opts.jumpOn then hum.UseJumpPower = true hum.JumpPower = opts.jump end
    end

    local function resetMovement()
        local hum = humanoid()
        if not hum then return end
        if not opts.speedOn then hum.WalkSpeed = 16 end
        if not opts.jumpOn then hum.UseJumpPower = true hum.JumpPower = 50 end
    end

    table.insert(conns, RunService.Stepped:Connect(function()
        if not opts.noclip or not LP.Character then return end
        for _, p in ipairs(LP.Character:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
        end
    end))

    ------------------------------------------------------------------ loop

    task.spawn(function()
        while alive do
            if Window.unloaded then teardown() break end
            for _, plr in ipairs(Players:GetPlayers()) do update(plr) end
            applyMovement()
            task.wait(0.2)
        end
    end)
    table.insert(conns, Players.PlayerRemoving:Connect(clear))

    ------------------------------------------------------------------ UI: Basic

    local Tab = Window:CreateTab({ name = "Basic" })

    Tab:CreateSection({ name = "ESP" })
    Tab:CreateToggle({
        name = "Team ESP",
        description = "Guards blue, inmates orange, criminals red.",
        flag = "pl_esp",
        callback = function(v) opts.esp = v end,
    })
    Tab:CreateToggle({
        name = "Names and Distance",
        description = "Name, team and distance in studs above everyone.",
        flag = "pl_labels",
        callback = function(v) opts.labels = v end,
    })

    Tab:CreateSection({ name = "Teleport" })
    local PLACES = {
        ["Cells"]          = Vector3.new(916, 97, 2435),
        ["Cafeteria"]      = Vector3.new(948, 97, 2325),
        ["Yard"]           = Vector3.new(841, 95, 2478),
        ["Nexus"]          = Vector3.new(915, 97, 2388),
        ["Guard Room"]     = Vector3.new(800, 97, 2299),
        ["Armory"]         = Vector3.new(820, 100, 2227),
        ["Prison Gate"]    = Vector3.new(491, 100, 2229),
        ["Criminal Base"]  = CRIMINAL_BASE,
        ["Town"]           = Vector3.new(420, 20, 1117),
    }
    local placeNames = {}
    for name in pairs(PLACES) do table.insert(placeNames, name) end
    table.sort(placeNames)
    local selectedPlace
    Tab:CreateDropdown({
        name = "Place",
        options = placeNames,
        placeholder = "Select a place",
        forgetState = true,
        callback = function(v) selectedPlace = v end,
    })
    Tab:CreateButton({
        name = "Teleport to Place",
        callback = function()
            if not selectedPlace then return notify("Teleport", "Select a place first.") end
            if selectedPlace == "Criminal Base" and LP.Team == Teams.Inmates then
                notify("Teleport", "Heads up: inmates become criminals at the base.")
            end
            teleport(PLACES[selectedPlace])
        end,
    })

    Tab:CreateSection({ name = "Movement" })
    Tab:CreateToggle({
        name = "Speed",
        flag = "pl_speed_on",
        callback = function(v) opts.speedOn = v if not v then resetMovement() end end,
    })
    Tab:CreateSlider({
        name = "Walk Speed",
        range = { 16, 100 },
        increment = 1,
        value = 30,
        flag = "pl_speed",
        callback = function(v) opts.speed = v end,
    })
    Tab:CreateToggle({
        name = "Jump",
        flag = "pl_jump_on",
        callback = function(v) opts.jumpOn = v if not v then resetMovement() end end,
    })
    Tab:CreateSlider({
        name = "Jump Power",
        range = { 50, 200 },
        increment = 5,
        value = 80,
        flag = "pl_jump",
        callback = function(v) opts.jump = v end,
    })
    Tab:CreateToggle({
        name = "Noclip",
        description = "Walk through walls.",
        flag = "pl_noclip",
        forgetState = true, -- never start inside walls on load
        callback = function(v) opts.noclip = v end,
    })

    ------------------------------------------------------------------ UI: Guns

    local Guns = Window:CreateTab({ name = "Guns" })
    Guns:CreateSection({ name = "Get Guns" })
    local selectedGun
    Guns:CreateDropdown({
        name = "Gun",
        options = gunNames(),
        placeholder = "Select a gun",
        forgetState = true,
        callback = function(v) selectedGun = v end,
    })
    Guns:CreateButton({
        name = "Get Gun",
        description = "Teleports to the gun, picks it up, brings you back. Max 2 big guns.",
        callback = function()
            if not selectedGun then return notify("Guns", "Select a gun first.") end
            task.spawn(getGun, selectedGun)
        end,
    })
    Guns:CreateButton({ name = "Get Remington 870", callback = function() task.spawn(getGun, "Remington 870") end })
    Guns:CreateButton({ name = "Get AK-47",         callback = function() task.spawn(getGun, "AK-47") end })

    Guns:CreateSection({ name = "Escape" })
    Guns:CreateButton({
        name = "Auto Escape",
        description = "Become a criminal. Switches you to Inmates first if needed.",
        callback = function() task.spawn(escape) end,
    })

    ctx.onUnload(function()
        opts.speedOn, opts.jumpOn, opts.noclip = false, false, false
        resetMovement()
        teardown()
    end)
end
