--[[
    Brookhaven RP (GameId 1686885941)

    Places: Workspace.JobGivers.<Job> models sit inside each job building (Police, Fire House, Day Care,
      Club Brooks, ...), so the place menu is built from them at runtime, plus a few big buildings
      (Bank, Mall, Hospital) placed at their bounding box floor.
    Houses: Workspace["001_Lots"].<Lot> has OwnerObj (ObjectValue -> Player) and a Spawn part.
    Avatar copy: the game's own ChangePlayerToAvatar request errors when called outside its editor UI,
      so we read the target's in-game look (Humanoid:GetAppliedDescription()) and wear each piece through
      the game's avatar editor: WearingController.WearAsset / WearShirt / WearPants and
      CharacterBodyController.ChangeBodyColor. WearAsset toggles, so RemoveAllAssets runs first.
      Some items get refused by the server (conflicts), so the copy reports how many pieces it wore.
    Remotes in ReplicatedStorage.RE have a "1" inserted between letters (1Avata1rOrigina1l = AvatarOriginal).
]]

return function(Window, ctx)
    local Players    = game:GetService("Players")
    local RS         = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local UIS        = game:GetService("UserInputService")
    local Http       = game:GetService("HttpService")
    local LP         = Players.LocalPlayer
    local Camera     = workspace.CurrentCamera

    local opts = {
        speedOn = false, speed = 32,
        jumpOn = false, jump = 80,
        infJump = false, noclip = false,
        fly = false, flySpeed = 60,
        esp = false, labels = false,
    }

    local alive = true
    local conns = {}
    local container = Instance.new("Folder")
    container.Name = "megab_hl"
    local okHui, hui = pcall(function() return gethui and gethui() end)
    container.Parent = (okHui and hui) or game:GetService("CoreGui")

    local function notify(title, content, icon)
        Window:Notify({ title = title, content = content, duration = 4, icon = icon })
    end
    local function rootOf(char) return char and char:FindFirstChild("HumanoidRootPart") end
    local function humanoid() return LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") end
    -- Buildings load only when you're near them (lazy models), so a fresh teleport can have no floor yet.
    -- Freeze the character on arrival, wait up to 4s for a floor to appear under `pos`, then land on it.
    local function teleport(pos)
        local char = LP.Character
        local root = rootOf(char)
        if not root then return false end
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = { char }
        params.RespectCanCollide = true -- ignore trigger parts you'd fall through
        root.Anchored = true
        char:PivotTo(CFrame.new(pos + Vector3.new(0, 3, 0)))
        pcall(function() LP:RequestStreamAroundAsync(pos, 3) end)
        local hit, t = nil, os.clock()
        repeat
            hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), params)
            if not hit then task.wait(0.1) end
        until hit or os.clock() - t > 4
        if root.Parent then
            char:PivotTo(CFrame.new((hit and hit.Position or pos) + Vector3.new(0, 3, 0)))
            root.Anchored = false
        end
        return true
    end

    ------------------------------------------------------------------ players list (shared by dropdowns)

    local function label(p) return p.DisplayName == p.Name and p.Name or (p.DisplayName .. " (@" .. p.Name .. ")") end
    local function otherPlayers()
        local names, map = {}, {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP then local l = label(p) table.insert(names, l) map[l] = p end
        end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        return names, map
    end
    local playerMap = select(2, otherPlayers())
    local playerDropdowns = {}
    local function refreshPlayers()
        local names, map = otherPlayers()
        playerMap = map
        for _, d in ipairs(playerDropdowns) do d:Refresh(names) end
    end
    table.insert(conns, Players.PlayerAdded:Connect(refreshPlayers))
    table.insert(conns, Players.PlayerRemoving:Connect(function() task.defer(refreshPlayers) end))

    ------------------------------------------------------------------ places

    -- spots checked in game (inside each building, floor under them)
    local FIXED = {
        ["Bank"]          = Vector3.new(20, 3, 247),
        ["Mall"]          = Vector3.new(216, 3, -153),
        ["Movie Theater"] = Vector3.new(183, 3, -148),
        ["Hospital"]      = Vector3.new(-309, 2, 5),
        ["Pet Hospital"]  = Vector3.new(-165, 5, 290),
        ["Spawn"]         = Vector3.new(-56, 3, -1),
    }
    local function places()
        local list = table.clone(FIXED)
        local givers = workspace:FindFirstChild("JobGivers")
        if givers then
            for _, g in ipairs(givers:GetChildren()) do
                local ok, cf = pcall(g.GetPivot, g)
                if ok and cf.Position.Y > -50 and not list[g.Name] then list[g.Name] = cf.Position end
            end
        end
        return list
    end
    local function nearestPlace(pos)
        local best, bestD = nil, math.huge
        for name, p in pairs(places()) do
            local d = (p - pos).Magnitude
            if d < bestD then best, bestD = name, d end
        end
        return best
    end

    ------------------------------------------------------------------ house

    local function myHouseSpawn()
        local lots = workspace:FindFirstChild("001_Lots")
        if not lots then return nil end
        for _, lot in ipairs(lots:GetChildren()) do
            local owner = lot:FindFirstChild("OwnerObj")
            if owner and owner.Value == LP then
                local s = lot:FindFirstChild("Spawn") or lot:FindFirstChild("HouseSpawnPosition")
                if s then return s.Position end
            end
        end
        return nil
    end

    ------------------------------------------------------------------ waypoints (saved to megab/brookhaven_waypoints.json)

    local WP_PATH = "megab/brookhaven_waypoints.json"
    local waypoints = {} -- name -> {x, y, z}
    pcall(function()
        if typeof(isfile) == "function" and isfile(WP_PATH) then waypoints = Http:JSONDecode(readfile(WP_PATH)) end
    end)
    local function saveWaypoints()
        if typeof(writefile) == "function" then pcall(writefile, WP_PATH, Http:JSONEncode(waypoints)) end
    end
    local function waypointNames()
        local t = {}
        for name in pairs(waypoints) do table.insert(t, name) end
        table.sort(t)
        return t
    end

    ------------------------------------------------------------------ ESP

    local highlights, billboards = {}, {}
    local function clear(plr)
        if highlights[plr] then highlights[plr]:Destroy() highlights[plr] = nil end
        if billboards[plr] then billboards[plr]:Destroy() billboards[plr] = nil end
    end
    local function colorFor(plr) -- stable pastel color per player
        return Color3.fromHSV((plr.UserId % 360) / 360, 0.55, 1)
    end
    local function makeBillboard()
        local bb = Instance.new("BillboardGui")
        bb.AlwaysOnTop = true
        bb.Size = UDim2.fromOffset(200, 36)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.LightInfluence = 0
        local l = Instance.new("TextLabel")
        l.Name = "Text"
        l.BackgroundTransparency = 1
        l.Size = UDim2.fromScale(1, 1)
        l.Font = Enum.Font.GothamBold
        l.TextSize = 14
        l.TextStrokeTransparency = 0.3
        l.Parent = bb
        bb.Parent = container
        return bb
    end
    local function updateEsp(plr)
        if plr == LP then return end
        local char = plr.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not char or not hum or hum.Health <= 0 then return clear(plr) end
        local color = colorFor(plr)
        if opts.esp then
            local h = highlights[plr]
            if not h then
                h = Instance.new("Highlight")
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.FillTransparency = 0.6
                h.Parent = container
                highlights[plr] = h
            end
            h.Adornee, h.FillColor, h.OutlineColor = char, color, color
        elseif highlights[plr] then
            highlights[plr]:Destroy() highlights[plr] = nil
        end
        local head, mine, theirs = char:FindFirstChild("Head"), rootOf(LP.Character), rootOf(char)
        if opts.labels and head and mine and theirs then
            local bb = billboards[plr] or makeBillboard()
            billboards[plr] = bb
            bb.Adornee = head
            bb.Text.Text = ("%s\n%d studs"):format(plr.DisplayName, math.floor((mine.Position - theirs.Position).Magnitude + 0.5))
            bb.Text.TextColor3 = color
        elseif billboards[plr] then
            billboards[plr]:Destroy() billboards[plr] = nil
        end
    end
    table.insert(conns, Players.PlayerRemoving:Connect(clear))

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
        if not (opts.noclip or opts.fly) or not LP.Character then return end
        for _, p in ipairs(LP.Character:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
        end
    end))

    table.insert(conns, UIS.JumpRequest:Connect(function()
        if not opts.infJump then return end
        local hum = humanoid()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end))

    -- fly: velocity + gyro on the root, steered by the camera and WASD / Space / Shift
    local flyVel, flyGyro
    local function stopFly()
        if flyVel then flyVel:Destroy() flyVel = nil end
        if flyGyro then flyGyro:Destroy() flyGyro = nil end
        local hum = humanoid()
        if hum then hum.PlatformStand = false end
    end
    table.insert(conns, RunService.Heartbeat:Connect(function()
        if not opts.fly then if flyVel then stopFly() end return end
        local root, hum = rootOf(LP.Character), humanoid()
        if not root or not hum then return end
        if not flyVel or flyVel.Parent ~= root then
            stopFly()
            flyVel = Instance.new("BodyVelocity")
            flyVel.MaxForce = Vector3.new(1e9, 1e9, 1e9)
            flyVel.Velocity = Vector3.zero
            flyVel.Parent = root
            flyGyro = Instance.new("BodyGyro")
            flyGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
            flyGyro.P = 9e4
            flyGyro.Parent = root
        end
        hum.PlatformStand = true
        local cf = Camera.CFrame
        local dir = Vector3.zero
        if UIS:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
        if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end
        flyVel.Velocity = dir.Magnitude > 0 and dir.Unit * opts.flySpeed or Vector3.zero
        flyGyro.CFrame = cf
    end))

    ------------------------------------------------------------------ spectate

    local spectating
    local function stopSpectate()
        spectating = nil
        local hum = humanoid()
        if hum then Camera.CameraSubject = hum end
    end

    ------------------------------------------------------------------ avatar copy

    local okWC, WC = pcall(function() return require(RS.Modules.Client.AvatarEditor.WearingController) end)
    local okBC, BC = pcall(function() return require(RS.Modules.Client.AvatarEditor.CharacterBodyController) end)
    -- your own look, saved before the first copy; kept in getgenv so a hub reload doesn't lose it
    local genv = (typeof(getgenv) == "function" and getgenv()) or _G
    local copying = false

    -- the avatar editor's server requests, called directly so we get the server's reply message
    local okRem, Remotes = pcall(function() return require(RS.Packages.Remotes) end)
    local function myLook()
        local hum = humanoid()
        local ok, d = pcall(function() return hum:GetAppliedDescription() end)
        return ok and d or nil
    end
    -- the server answers "Too fast!" when requests come in quickly: wait and try again
    local function request(name, ...)
        for _ = 1, 6 do
            local ok, success, msg = pcall(Remotes.invokeServer, name, ...)
            if ok and success then return true end
            if not (ok and tostring(msg):find("Too fast")) then return false, msg end
            task.wait(0.6)
        end
        return false, "Too fast"
    end

    local function wearDescription(d)
        -- 1. strip everything (this also resets the body) and wait until it's done
        WC.RemoveAllAssets()
        local t = os.clock()
        repeat task.wait(0.2) local m = myLook() until (m and #m:GetAccessories(true) == 0) or os.clock() - t > 4
        task.wait(0.4)
        -- 2. body and head (dynamic heads carry the face). The server's order is Torso, RightArm, LeftArm, RightLeg, LeftLeg, Head
        if d.Torso ~= 0 or d.Head ~= 0 then
            request("ChangeCharacterBody", { d.Torso, d.RightArm, d.LeftArm, d.RightLeg, d.LeftLeg, d.Head })
            task.wait(0.8)
        end
        -- 3. accessories, one at a time (Wear toggles, so skip anything already on)
        local worn, total = 0, 0
        for _, a in ipairs(d:GetAccessories(true)) do
            total += 1
            if WC.IsWearing(a.AssetId) or request("Wear", a.AssetId) then worn += 1 end
            task.wait(0.35)
        end
        -- 4. clothes and a classic face, only if they differ (they toggle too)
        local now = myLook()
        if d.Shirt ~= 0 then total += 1 if (now and now.Shirt == d.Shirt) or request("WearShirt", d.Shirt) then worn += 1 end task.wait(0.35) end
        if d.Pants ~= 0 then total += 1 if (now and now.Pants == d.Pants) or request("WearPants", d.Pants) then worn += 1 end task.wait(0.35) end
        if d.Face ~= 0 and not (now and now.Face == d.Face) then request("Wear", d.Face) task.wait(0.35) end
        -- 5. skin color
        if okBC then pcall(BC.ChangeBodyColor, d.HeadColor) end
        return worn, total
    end

    local function copyAvatar(plr)
        if not (okWC and okRem) then return notify("Copy Avatar", "Couldn't reach Brookhaven's avatar editor.", "circle-alert") end
        if copying then return notify("Copy Avatar", "Still copying, one second.") end
        local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
        if not hum then return notify("Copy Avatar", plr.DisplayName .. " has no character right now.", "circle-alert") end
        local okD, d = pcall(hum.GetAppliedDescription, hum)
        if not okD or not d then return notify("Copy Avatar", "Couldn't read " .. plr.DisplayName .. "'s look.", "circle-alert") end
        copying = true
        if not genv.megab_bh_original then
            local mine = humanoid()
            local okMine, m = pcall(function() return mine:GetAppliedDescription() end)
            if okMine then genv.megab_bh_original = m end
        end
        local worn, total = wearDescription(d)
        copying = false
        notify("Copy Avatar", ("You're wearing %s's look (%d of %d pieces)."):format(plr.DisplayName, worn, total), "user")
    end

    local function restoreAvatar()
        if not (okWC and okRem) then return end
        if copying then return end
        local d = genv.megab_bh_original
        if not d then -- nothing saved this session: use your Roblox website avatar
            local ok, web = pcall(Players.GetHumanoidDescriptionFromUserId, Players, LP.UserId)
            if not ok then return notify("Copy Avatar", "Couldn't load your look.", "circle-alert") end
            d = web
        end
        copying = true
        wearDescription(d)
        copying = false
        notify("Copy Avatar", "Your own look is back.", "user")
    end

    ------------------------------------------------------------------ loop / teardown

    task.spawn(function()
        while alive do
            if Window.unloaded then break end
            for _, plr in ipairs(Players:GetPlayers()) do updateEsp(plr) end
            applyMovement()
            if spectating and not spectating.Parent then stopSpectate() end
            task.wait(0.2)
        end
    end)

    ctx.onUnload(function()
        alive = false
        for _, c in ipairs(conns) do c:Disconnect() end
        table.clear(conns)
        stopFly()
        if spectating then stopSpectate() end
        opts.speedOn, opts.jumpOn = false, false
        resetMovement()
        container:Destroy()
    end)

    ------------------------------------------------------------------ UI: Basic

    local Tab = Window:CreateTab({ name = "Basic" })

    Tab:CreateSection({ name = "Movement" })
    Tab:CreateToggle({ name = "Speed", description = "Walk faster.", flag = "bh_speed_on",
        callback = function(v) opts.speedOn = v if not v then resetMovement() end end })
    Tab:CreateSlider({ name = "Walk Speed", range = { 16, 150 }, increment = 1, value = 32, flag = "bh_speed",
        callback = function(v) opts.speed = v end })
    Tab:CreateToggle({ name = "Jump", description = "Jump higher.", flag = "bh_jump_on",
        callback = function(v) opts.jumpOn = v if not v then resetMovement() end end })
    Tab:CreateSlider({ name = "Jump Power", range = { 50, 250 }, increment = 5, value = 80, flag = "bh_jump",
        callback = function(v) opts.jump = v end })
    Tab:CreateToggle({ name = "Infinite Jump", description = "Jump again in the air.", flag = "bh_infjump",
        callback = function(v) opts.infJump = v end })
    Tab:CreateToggle({ name = "Noclip", description = "Walk through walls.", flag = "bh_noclip",
        callback = function(v) opts.noclip = v end })

    Tab:CreateSection({ name = "Fly" })
    Tab:CreateToggle({ name = "Fly", description = "WASD to move, Space up, Shift down.", flag = "bh_fly", forgetState = true,
        callback = function(v) opts.fly = v end })
    Tab:CreateSlider({ name = "Fly Speed", range = { 20, 300 }, increment = 5, value = 60, flag = "bh_fly_speed",
        callback = function(v) opts.flySpeed = v end })

    ------------------------------------------------------------------ UI: Teleport

    local Tp = Window:CreateTab({ name = "Teleport", icon = "map-pin" })

    Tp:CreateSection({ name = "Places" })
    local placeList = places()
    local placeNames = {}
    for name in pairs(placeList) do table.insert(placeNames, name) end
    table.sort(placeNames)
    local selectedPlace
    Tp:CreateDropdown({ name = "Place", options = placeNames, placeholder = "Select a place", forgetState = true,
        callback = function(v) selectedPlace = v end })
    Tp:CreateButton({ name = "Teleport to Place", callback = function()
        if not selectedPlace then return notify("Teleport", "Pick a place first.") end
        local pos = places()[selectedPlace]
        if pos and teleport(pos) then notify("Teleport", "You're at " .. selectedPlace .. ".", "map-pin") end
    end })
    Tp:CreateButton({ name = "Teleport to My House", callback = function()
        local pos = myHouseSpawn()
        if not pos then return notify("Teleport", "You don't have a house yet. Claim one first.", "circle-alert") end
        teleport(pos)
        notify("Teleport", "Welcome home.", "home")
    end })

    Tp:CreateSection({ name = "Players" })
    local selectedTp
    local tpDrop = Tp:CreateDropdown({ name = "Player", options = (otherPlayers()), placeholder = "Select a player", forgetState = true,
        callback = function(v) selectedTp = v end })
    table.insert(playerDropdowns, tpDrop)
    Tp:CreateButton({ name = "Teleport to Player", callback = function()
        local plr = selectedTp and playerMap[selectedTp]
        local r = plr and rootOf(plr.Character)
        if not r then return notify("Teleport", "Pick a player who is in the game.") end
        teleport(r.Position + r.CFrame.LookVector * -3)
        notify("Teleport", "You're next to " .. plr.DisplayName .. ".", "map-pin")
    end })

    Tp:CreateSection({ name = "Waypoints" })
    local selectedWp
    local wpDrop = Tp:CreateDropdown({ name = "Waypoint", options = waypointNames(), placeholder = "No waypoint", forgetState = true,
        callback = function(v) selectedWp = v end })
    Tp:CreateButton({ name = "Save Waypoint Here", description = "Saves where you stand. It stays after you leave.", callback = function()
        local r = rootOf(LP.Character)
        if not r then return end
        local near = nearestPlace(r.Position) or "Brookhaven"
        local n, name = 1, nil
        repeat name = ("%s %d"):format(near, n) n += 1 until not waypoints[name]
        waypoints[name] = { r.Position.X, r.Position.Y, r.Position.Z }
        saveWaypoints()
        wpDrop:Refresh(waypointNames())
        wpDrop:Set(name, true)
        selectedWp = name
        notify("Waypoints", "Saved " .. name .. ".", "map-pin")
    end })
    Tp:CreateButton({ name = "Teleport to Waypoint", callback = function()
        local p = selectedWp and waypoints[selectedWp]
        if not p then return notify("Waypoints", "Pick a waypoint first.") end
        teleport(Vector3.new(p[1], p[2], p[3]))
    end })
    Tp:CreateButton({ name = "Delete Waypoint", callback = function()
        if not selectedWp or not waypoints[selectedWp] then return notify("Waypoints", "Pick a waypoint first.") end
        waypoints[selectedWp] = nil
        saveWaypoints()
        notify("Waypoints", "Deleted " .. selectedWp .. ".")
        selectedWp = nil
        wpDrop:Refresh(waypointNames())
    end })

    ------------------------------------------------------------------ UI: Players

    local Pl = Window:CreateTab({ name = "Players", icon = "users" })

    Pl:CreateSection({ name = "ESP" })
    Pl:CreateToggle({ name = "Player ESP", description = "Everyone glows in their own color.", flag = "bh_esp",
        callback = function(v) opts.esp = v end })
    Pl:CreateToggle({ name = "Names and Distance", description = "Name and distance in studs above everyone.", flag = "bh_labels",
        callback = function(v) opts.labels = v end })

    Pl:CreateSection({ name = "Spectate" })
    local selectedSpec
    local specDrop = Pl:CreateDropdown({ name = "Player", options = (otherPlayers()), placeholder = "Select a player", forgetState = true,
        callback = function(v) selectedSpec = v end })
    table.insert(playerDropdowns, specDrop)
    Pl:CreateButton({ name = "Spectate Player", callback = function()
        local plr = selectedSpec and playerMap[selectedSpec]
        local hum = plr and plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
        if not hum then return notify("Spectate", "Pick a player who is in the game.") end
        spectating = plr
        Camera.CameraSubject = hum
        notify("Spectate", "Watching " .. plr.DisplayName .. ".", "eye")
    end })
    Pl:CreateButton({ name = "Stop Spectating", callback = function()
        stopSpectate()
        notify("Spectate", "Camera is back on you.", "eye")
    end })

    Pl:CreateSection({ name = "Copy Avatar" })
    local selectedCopy
    local copyDrop = Pl:CreateDropdown({ name = "Player", options = (otherPlayers()), placeholder = "Select a player", forgetState = true,
        callback = function(v) selectedCopy = v end })
    table.insert(playerDropdowns, copyDrop)
    Pl:CreateButton({ name = "Copy Their Look", description = "Wears their outfit through Brookhaven's avatar editor.", callback = function()
        local plr = selectedCopy and playerMap[selectedCopy]
        if not plr then return notify("Copy Avatar", "Pick a player first.") end
        notify("Copy Avatar", "Copying " .. plr.DisplayName .. "...", "user")
        copyAvatar(plr)
    end })
    Pl:CreateButton({ name = "Restore My Look", callback = function()
        notify("Copy Avatar", "Putting your look back...", "user")
        restoreAvatar()
    end })

    -- respawn: camera back on you if you were spectating someone who left
    table.insert(conns, LP.CharacterAdded:Connect(function()
        task.wait(0.5)
        if not spectating then stopSpectate() end
    end))
end
