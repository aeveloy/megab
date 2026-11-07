--[[
    Adopt Me! (GameId 383310974)

    Game API: require(ReplicatedStorage.Fsys).load(name)
      RouterClient.get("<API>/<Name>") -> RemoteEvent/RemoteFunction (plain names in ReplicatedStorage.API)
      ClientData.get_data()[LocalPlayer.Name] -> player state (money, inventory, equip_manager, ailments_manager)
      InteriorsM.enter(destination_id, door_id, settings) -> teleport between interiors
        e.g. enter("School", "MainDoor", {}), enter("MainMap", "School/MainDoor", {}),
             enter("housing", "MainDoor", { house_owner = LocalPlayer })
    Pet needs ("ailments"): ailments_manager.ailments[pet_unique][kind] = { progress, rate, ... }
      Definitions: ReplicatedStorage.new.modules.Ailments.AilmentsDB.<kind>
      Location kinds complete by staying ~50s in the right interior / map area (server RateArea).
    Playtime payouts: PayAPI/Collect (FireServer).
]]

return function(Window, ctx)
    local Players     = game:GetService("Players")
    local RS          = game:GetService("ReplicatedStorage")
    local VirtualUser = game:GetService("VirtualUser")
    local LP          = Players.LocalPlayer

    local load       = require(RS:WaitForChild("Fsys")).load
    local Router     = load("RouterClient")
    local ClientData = load("ClientData")
    local InteriorsM = load("InteriorsM")

    local opts = {
        antiAfk   = false,
        speedOn   = false,
        speed     = 32,
        jumpOn    = false,
        jump      = 75,
        autoMoney = false,
        autoPet   = false,
    }

    local alive = true
    local conns = {}
    local function teardown()
        alive = false
        for _, c in ipairs(conns) do c:Disconnect() end
        table.clear(conns)
    end

    local function notify(title, content)
        Window:Notify({ title = title, content = content, duration = 4 })
    end

    local function myData()
        local all = ClientData.get_data()
        return all and all[LP.Name]
    end

    local function humanoid()
        local char = LP.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    ------------------------------------------------------------------ teleport

    local function currentLocation()
        local loc = InteriorsM.get_current_location()
        return loc and loc.destination_id
    end

    -- leaving an interior uses "<Interior>/MainDoor" as the door on the main map
    local function enter(dest, settings)
        local here = currentLocation()
        local door = "MainDoor"
        if dest == "MainMap" and here and here ~= "MainMap" then door = here .. "/MainDoor" end
        local ok, err = pcall(InteriorsM.enter, dest, door, settings or {})
        if not ok then notify("Teleport", tostring(err)) return false end
        local t = os.clock()
        while currentLocation() ~= dest and os.clock() - t < 8 do task.wait(0.2) end
        task.wait(0.5)
        return currentLocation() == dest
    end

    local function goHome()
        return enter("housing", { house_owner = LP })
    end

    local function goMapPoint(part)
        if currentLocation() ~= "MainMap" then enter("MainMap") end
        local char = LP.Character
        if char and part then char:PivotTo(CFrame.new(part.Position + Vector3.new(0, 4, 0))) end
    end

    local PLACES = { -- label -> destination_id
        ["Home"] = "housing", ["Main Map"] = "MainMap", ["Nursery"] = "Nursery", ["School"] = "School",
        ["Hospital"] = "Hospital", ["Salon"] = "Salon", ["Pizza Shop"] = "PizzaShop",
        ["Supermarket"] = "Supermarket", ["Pet Shop"] = "PetShop", ["Toy Shop"] = "ToyShop",
        ["Hat Shop"] = "HatShop", ["Coffee Shop"] = "CoffeeShop", ["Ice Cream"] = "IceCream",
        ["Cat Cafe"] = "CatCafe", ["Vehicle Dealer"] = "AutoShop", ["Safety Hub"] = "SafetyHub",
        ["Sky Castle"] = "SkyCastle", ["VIP Room"] = "VIP", ["Wing Room"] = "WingRoom",
        ["Cave"] = "Cave", ["Trade Hub"] = "TradeHub", ["Detective"] = "DetectiveBuilding",
        ["AFK Zone"] = "AFKZone",
    }
    local placeNames = {}
    for label in pairs(PLACES) do table.insert(placeNames, label) end
    table.sort(placeNames)

    ------------------------------------------------------------------ anti-afk

    table.insert(conns, LP.Idled:Connect(function()
        if not opts.antiAfk then return end
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end))

    ------------------------------------------------------------------ movement

    local function applyMovement()
        local hum = humanoid()
        if not hum then return end
        if opts.speedOn then hum.WalkSpeed = opts.speed end
        if opts.jumpOn then
            hum.UseJumpPower = true
            hum.JumpPower = opts.jump
        end
    end

    local function resetMovement()
        local hum = humanoid()
        if not hum then return end
        if not opts.speedOn then hum.WalkSpeed = 16 end
        if not opts.jumpOn then hum.UseJumpPower = true hum.JumpPower = 50 end
    end

    ------------------------------------------------------------------ money

    local function collectPay()
        pcall(function() Router.get("PayAPI/Collect"):FireServer() end)
        pcall(function() load("UIManager").set_app_visibility("PlaytimePayoutsApp", false) end)
    end

    ------------------------------------------------------------------ pet needs

    local function staticPart(...)
        local node = workspace:FindFirstChild("StaticMap")
        for _, name in ipairs({ ... }) do node = node and node:FindFirstChild(name) end
        return node
    end

    -- house furniture: Workspace.HouseInteriors.furniture["<owner>/.../<unique>"] > Model (kind name)
    -- used via HousingAPI/ActivateFurniture(owner, unique, useBlockName, { cframe }, petChar)
    local function findFurniture(pattern)
        local hi = workspace:FindFirstChild("HouseInteriors")
        local furn = hi and hi:FindFirstChild("furniture")
        if not furn then return nil end
        for _, f in ipairs(furn:GetChildren()) do
            local model = f:FindFirstChildWhichIsA("Model")
            local blocks = f:FindFirstChild("UseBlocks", true)
            if model and blocks and model.Name:find(pattern) and #blocks:GetChildren() > 0 then
                return f.Name:match("([^/]+)$"), blocks:GetChildren()[1]
            end
        end
        return nil
    end

    local function useFurniture(patterns, pet)
        if currentLocation() ~= "housing" then goHome() end
        for _, pattern in ipairs(patterns) do
            local unique, block = findFurniture(pattern)
            if unique then
                local ok = pcall(function()
                    Router.get("HousingAPI/ActivateFurniture"):InvokeServer(LP, unique, block.Name, { cframe = block.CFrame }, pet.char)
                end)
                if ok then return true end
            end
        end
        notify("Pet Needs", "No furniture for this in your house: " .. table.concat(patterns, "/"))
        return false
    end

    -- kind -> { run = function(pet), repeat_every = seconds or nil }
    -- run moves you / uses something; the loop then waits for the need to disappear
    -- pets don't follow InteriorsM.enter; re-equip each one at your side after a teleport
    local function summonPet(pet)
        local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        pcall(function() Router.get("ToolAPI/Unequip"):InvokeServer(pet.uid, {}) end)
        task.wait(0.5)
        pcall(function()
            Router.get("ToolAPI/Equip"):InvokeServer(pet.uid, { spawn_cframe = root.CFrame * CFrame.new(0, 0, -4) })
        end)
        task.wait(1)
    end

    local function place(dest) return { run = function(pet) enter(dest) summonPet(pet) end } end
    local function mapPoint(...)
        local path = { ... }
        return { run = function(pet) goMapPoint(staticPart(table.unpack(path))) summonPet(pet) end }
    end
    local function furniture(...) local p = { ... } return { run = function(pet) useFurniture(p, pet) end, repeat_every = 15 } end

    local HANDLERS = {
        school      = place("School"),
        salon       = place("Salon"),
        pizza_party = place("PizzaShop"),
        cat_cafe    = place("CatCafe"),
        sick        = place("Hospital"),
        camping     = mapPoint("Campsite", "CampsiteOrigin"),
        beach_party = mapPoint("Beach", "BeachPartyNavTarget"),
        bored       = mapPoint("Park", "BoredAilmentTarget"),
        dirty       = furniture("Bathtub", "Shower"),
        sleepy      = furniture("Bed"),
        toilet      = furniture("Toilet"),
        hungry      = furniture("FoodBowl"),
        thirsty     = furniture("WaterBowl"),
        -- pet_me: NOT supported. FocusPet -> PetPetted -> ProgressPetMeAilment (the game's order)
        -- does not clear it from a script; the server seems to need the real petting screen.
        -- play: equip a toy and throw it (the game's own ThrowToyHelper); ~3 throws
        play        = {
            run = function()
                local d = myData()
                local toys = d and d.inventory and d.inventory.toys
                if not toys then return end
                local toyUid, toy
                for u, it in pairs(toys) do
                    if tostring(it.id):find("bone") or tostring(it.id):find("ball") then toyUid, toy = u, it break end
                end
                if not toyUid then toyUid, toy = next(toys) end
                if not toyUid then return notify("Pet Needs", "You need a toy for play.") end
                pcall(function() Router.get("ToolAPI/Equip"):InvokeServer(toyUid, {}) end)
                task.wait(0.8)
                local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    pcall(load("ThrowToyHelper").generic_throw_toy_use, toy,
                        (root.CFrame * CFrame.new(0, 0, -15)).Position, { reaction_name = "ThrowToyReaction" })
                end
            end,
            repeat_every = 6,
        },
        -- walk: hold the pet and keep moving (~30s of movement)
        walk        = {
            walk = true,
            run = function(pet)
                pcall(function() Router.get("AdoptAPI/HoldBaby"):InvokeServer(pet.char) end)
            end,
            finish = function(pet)
                pcall(function() Router.get("AdoptAPI/EjectBaby"):FireServer(pet.char) end)
            end,
        },
        -- ride: equip a stroller, sit the pet in it, keep moving (~30s of movement)
        ride        = {
            walk = true,
            run = function(pet)
                local d = myData()
                local strollerUid = d and d.inventory and d.inventory.strollers and next(d.inventory.strollers)
                if not strollerUid then return notify("Pet Needs", "You need a stroller for ride.") end
                pcall(function() Router.get("ToolAPI/Equip"):InvokeServer(strollerUid, {}) end)
                task.wait(1)
                local tool = LP.Character and LP.Character:FindFirstChild("StrollerTool")
                local seat = tool and tool:FindFirstChild("TouchToSit", true)
                if seat then
                    pcall(function() Router.get("AdoptAPI/UseStroller"):InvokeServer(LP, pet.char, seat) end)
                end
            end,
            finish = function()
                local d = myData()
                local strollerUid = d and d.inventory and d.inventory.strollers and next(d.inventory.strollers)
                if strollerUid then pcall(function() Router.get("ToolAPI/Unequip"):InvokeServer(strollerUid, {}) end) end
            end,
        },
    }

    -- keeps the character walking in a small circle (movement needs count time spent moving)
    local function walkStep(state)
        local hum, root = humanoid(), LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not (hum and root) then return end
        state.center = state.center or root.Position
        state.angle = (state.angle or 0) + 0.4
        hum:MoveTo(state.center + Vector3.new(math.cos(state.angle) * 10, 0, math.sin(state.angle) * 10))
    end

    -- { uid = pet unique, char = pet model } for each pet you have out
    local function equippedPets()
        local list = {}
        local ok, entities = pcall(function() return load("PetEntityManager").get_local_owned_pet_entities() end)
        if not ok or type(entities) ~= "table" then return list end
        for _, e in pairs(entities) do
            local uid = type(e.unique_id) == "string" and e.unique_id:match("^(.-)%-%d+$")
            local char = e.base and e.base.char
            if uid and char then table.insert(list, { uid = uid, char = char }) end
        end
        return list
    end

    local function petAilments(uid)
        local d = myData()
        local am = d and d.ailments_manager and d.ailments_manager.ailments
        return (am and am[uid]) or {}
    end

    local status -- Text element handle, set in UI section
    local function pretty(text) return (text:gsub("_", " ")) end -- "pizza_party" -> "pizza party"
    local function setStatus(text) if status then status:Set(pretty(text)) end end

    local failed = {} -- [uid .. kind] = os.clock() of a timed-out attempt; skipped for 2 min

    local function petStep()
        local pets = equippedPets()
        if #pets == 0 then setStatus("No pet out. Equip a pet from your backpack.") return task.wait(3) end

        local pet, todo, unsupported = nil, nil, {}
        for _, p in ipairs(pets) do
            for kind in pairs(petAilments(p.uid)) do
                local recentlyFailed = failed[p.uid .. kind] and os.clock() - failed[p.uid .. kind] < 120
                if HANDLERS[kind] and not recentlyFailed then
                    if not todo then pet, todo = p, kind end
                else
                    table.insert(unsupported, kind)
                end
            end
        end
        if not todo then
            setStatus(#unsupported > 0 and ("Waiting. Can't do yet: " .. table.concat(unsupported, ", ")) or "All needs done.")
            return task.wait(3)
        end

        local h = HANDLERS[todo]
        local t, lastRun, walkState = os.clock(), os.clock(), {}
        setStatus("Doing: " .. todo)
        h.run(pet)
        while opts.autoPet and petAilments(pet.uid)[todo] and os.clock() - t < 75 do
            if h.repeat_every and os.clock() - lastRun >= h.repeat_every then
                lastRun = os.clock()
                h.run(pet)
            end
            if h.walk then walkStep(walkState) end
            setStatus(("Doing: %s (%ds)"):format(todo, math.floor(os.clock() - t)))
            task.wait(0.25)
        end
        if h.walk then
            local hum, root = humanoid(), LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if hum and root then hum:MoveTo(root.Position) end
        end
        if h.finish then h.finish(pet) end
        if not petAilments(pet.uid)[todo] then
            notify("Pet Needs", pretty(todo) .. " done")
        elseif opts.autoPet then
            failed[pet.uid .. todo] = os.clock()
            notify("Pet Needs", pretty(todo) .. " didn't finish, skipping it for 2 min")
        end
    end

    ------------------------------------------------------------------ loops

    task.spawn(function() -- movement + money + unload watch
        local lastPay = 0
        while alive do
            if Window.unloaded then teardown() break end
            applyMovement()
            if opts.autoMoney and os.clock() - lastPay > 30 then
                lastPay = os.clock()
                collectPay()
            end
            task.wait(0.5)
        end
    end)
    task.spawn(function() -- pet needs
        while alive do
            if opts.autoPet then
                local ok, err = pcall(petStep)
                if not ok then setStatus("Error: " .. tostring(err)) task.wait(3) end
            else
                task.wait(0.5)
            end
        end
    end)

    ------------------------------------------------------------------ UI: Basic

    local Tab = Window:CreateTab({ name = "Basic" })

    Tab:CreateSection({ name = "Teleport" })
    local selectedPlace
    Tab:CreateDropdown({
        name = "Place",
        options = placeNames,
        placeholder = "Select a place",
        forgetState = true,
        callback = function(label) selectedPlace = label end,
    })
    Tab:CreateButton({
        name = "Teleport to Place",
        callback = function()
            if not selectedPlace then return notify("Teleport", "Select a place first.") end
            local dest = PLACES[selectedPlace]
            task.spawn(function()
                local ok = dest == "housing" and goHome() or enter(dest)
                if not ok then notify("Teleport", "Could not reach " .. selectedPlace .. ".") end
            end)
        end,
    })

    Tab:CreateSection({ name = "Movement" })
    Tab:CreateToggle({
        name = "Speed",
        flag = "am_speed_on",
        callback = function(v) opts.speedOn = v if not v then resetMovement() end end,
    })
    Tab:CreateSlider({
        name = "Walk Speed",
        range = { 16, 100 },
        increment = 1,
        value = 32,
        flag = "am_speed",
        callback = function(v) opts.speed = v end,
    })
    Tab:CreateToggle({
        name = "Jump",
        flag = "am_jump_on",
        callback = function(v) opts.jumpOn = v if not v then resetMovement() end end,
    })
    Tab:CreateSlider({
        name = "Jump Power",
        range = { 50, 200 },
        increment = 5,
        value = 75,
        flag = "am_jump",
        callback = function(v) opts.jump = v end,
    })

    Tab:CreateSection({ name = "Misc" })
    Tab:CreateToggle({
        name = "Anti-AFK",
        description = "Stops Roblox kicking you after 20 minutes idle.",
        flag = "am_anti_afk",
        callback = function(v) opts.antiAfk = v end,
    })

    ------------------------------------------------------------------ UI: Farm

    local Farm = Window:CreateTab({ name = "Farm" })

    Farm:CreateSection({ name = "Money" })
    Farm:CreateToggle({
        name = "Auto Collect Paycheck",
        description = "Collects your playtime bucks every 30s, no popup.",
        flag = "am_auto_money",
        callback = function(v) opts.autoMoney = v if v then collectPay() end end,
    })

    Farm:CreateSection({ name = "Pet Needs" })
    Window.megabHandles = Window.megabHandles or {} -- lets MCP tests drive forgetState toggles
    Window.megabHandles.autoPet = Farm:CreateToggle({
        name = "Auto Pet Needs",
        description = "Takes your equipped pet wherever its needs are fixed.",
        flag = "am_auto_pet",
        forgetState = true, -- teleports you around; never auto-start on load
        callback = function(v)
            opts.autoPet = v
            if not v then setStatus("Off.") end
        end,
    })
    status = Farm:CreateText({ name = "Status", text = "Off." })
    local supported = {}
    for kind in pairs(HANDLERS) do table.insert(supported, kind) end
    table.sort(supported)
    Farm:CreateText({ name = "Supported needs", text = pretty(table.concat(supported, ", ")) })

    ctx.onUnload(function()
        opts.speedOn, opts.jumpOn = false, false
        resetMovement()
        teardown()
    end)
end
