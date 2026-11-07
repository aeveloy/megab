--[[
    Hub loader (Luau, Roblox executor)
    UI: megab's own library, ui.lua (loaded from <workspace>/megab/ui.lua, or REMOTE_BASE)

    Detects the current game by GameId (universe ID, the same for every place
    in a game, e.g. Lobby/Starter/Ranked) and loads games/<GameId>.lua.

    Lookup order:
      1. Local file:  <executor workspace>/<FOLDER>/games/<GameId>.lua
      2. Remote URL:  REMOTE_BASE .. "games/<GameId>.lua"  (if REMOTE_BASE set)

    Each game module must return a function:
        return function(Window, ctx) ... end
    ctx = { GameId, PlaceId, Name, onUnload = function(fn) }
    The Info tab is created after the module, so it is always the last tab.
]]

local FOLDER      = "megab"     -- folder inside executor workspace
local REMOTE_BASE = "https://raw.githubusercontent.com/aeveloy/megab/main/"

local GameId  = game.GameId
local PlaceId = game.PlaceId

-- every supported game: shown as teleport tabs when the current game has no module
local SUPPORTED = {
    { name = "Murder Mystery 2", gameId = 66654135, placeId = 142823291, icon = "skull",
      about = "Sheriff and murderer ESP, everyone ESP, distance labels, murderer alert, auto grab gun, teleports, coin ESP and coin farm." },
    { name = "Adopt Me!", gameId = 383310974, placeId = 920587237, icon = "paw-print",
      about = "Teleport menu, speed and jump, anti-AFK, auto paycheck, and auto pet needs (16 needs: school, bed, bath, walk, ride, play...)." },
    { name = "Prison Life", gameId = 73885730, placeId = 155615604, icon = "shield",
      about = "Team ESP with names and distance, get guns, teleports, speed, jump, noclip and auto escape." },
}

-- re-executing the loader replaces the previous instance instead of stacking
local env = (typeof(getgenv) == "function" and getgenv()) or _G
if env.megab and env.megab.Unload then pcall(env.megab.Unload) end

local okInfo, info = pcall(function()
    return game:GetService("MarketplaceService"):GetProductInfo(PlaceId)
end)
local GameName = (okInfo and info and info.Name) or ("Place " .. PlaceId)

local function readLocal(path)
    if typeof(isfile) == "function" and typeof(readfile) == "function" then
        local ok, exists = pcall(isfile, path)
        if ok and exists then
            return readfile(path)
        end
    end
    return nil
end

local function readRemote(path)
    if not REMOTE_BASE then return nil end
    local ok, body = pcall(game.HttpGet, game, REMOTE_BASE .. path)
    if ok and body and #body > 0 and not body:find("^404") then
        return body
    end
    return nil
end

-- UI library: our own ui.lua (local first, then remote)
local uiSrc = readLocal(FOLDER .. "/ui.lua") or readRemote("ui.lua")
assert(uiSrc, "megab: ui.lua not found in workspace/" .. FOLDER)
local UI = assert(loadstring(uiSrc, "=megab/ui"))()

-- loading screen: shows each startup step, then hands over to the window
local splash = UI:CreateSplash({
    title = "megab",
    credit = "made by @aeveloy and claudecode <3",
    folder = FOLDER,
})
splash:Step("Loading UI...", 0.2)

local Window = UI:CreateWindow({
    name = "megab",
    subtitle = GameName,
    startHidden = true,
    configuration = {
        fileName = tostring(GameId),
        customFolder = FOLDER,
    },
})
splash:Step("Detecting game: " .. GameName, 0.4)

-- cleanup registry: modules register teardown fns, run on "Unload hub"
local cleanups = {}
local function unloadHub()
    for _, fn in ipairs(cleanups) do pcall(fn) end
    table.clear(cleanups)
    if not Window.unloaded then Window:Unload() end
    if env.megab and env.megab.Window == Window then env.megab = nil end
end
env.megab = { Window = Window, Unload = unloadHub }

local function fetchModule()
    local rel = "games/" .. GameId .. ".lua"
    local src = readLocal(FOLDER .. "/" .. rel) or readLocal(FOLDER .. "/games/" .. GameId .. ".luau")
    if src then return src, "local" end
    src = readRemote(rel)
    if src then return src, "remote" end
    return nil
end

local function loadModule()
    local src, origin = fetchModule()
    if not src then
        return false, "Unsupported game", "No module for GameId " .. GameId
    end

    local chunk, compileErr = loadstring(src, "=games/" .. GameId)
    if not chunk then
        return false, "Module compile error", tostring(compileErr)
    end

    local okRun, entry = pcall(chunk)
    if not okRun or typeof(entry) ~= "function" then
        return false, "Module error", okRun and "Module must return a function" or tostring(entry)
    end

    local okInit, initErr = pcall(entry, Window, {
        GameId = GameId,
        PlaceId = PlaceId,
        Name = GameName,
        onUnload = function(fn) table.insert(cleanups, fn) end,
    })
    if not okInit then
        return false, "Module init error", tostring(initErr)
    end

    return true, "Loaded", GameName .. " (" .. origin .. ")"
end

splash:Step("Loading " .. GameName .. " features...", 0.65)
local ok, title, content = loadModule()
splash:Step(ok and "Features loaded" or title, 0.85)

-- unsupported game: one tab per supported game, each with a teleport button
local unsupported = not ok and title == "Unsupported game"
if unsupported then
    local TeleportService = game:GetService("TeleportService")
    local LocalPlayer = game:GetService("Players").LocalPlayer

    -- runs in the next game after the teleport, so the hub loads there by itself
    local queueOnTeleport = (syn and syn.queue_on_teleport) or queue_on_teleport or queueonteleport
        or (fluxus and fluxus.queue_on_teleport)
    local AUTOLOAD = ([[
        if not game:IsLoaded() then game.Loaded:Wait() end
        if isfile and isfile("%s/loader.lua") then
            loadstring(readfile("%s/loader.lua"))()
        else
            loadstring(game:HttpGet("%sloader.lua"))()
        end
    ]]):format(FOLDER, FOLDER, REMOTE_BASE or "")

    -- teleport refused (e.g. error 773: this game blocks third-party teleports): give a link instead
    local pending -- the game we are trying to join
    table.insert(cleanups, (function()
        local conn = TeleportService.TeleportInitFailed:Connect(function(player, result, message)
            if player ~= LocalPlayer or not pending then return end
            local link = "https://www.roblox.com/games/" .. pending.placeId
            if typeof(setclipboard) == "function" then pcall(setclipboard, link) end
            Window:Notify({
                title = "Teleport blocked",
                content = ("This game blocks teleports (%s). Link to %s copied, paste it in your browser."):format(tostring(result.Name or result), pending.name),
                duration = 10, icon = "circle-alert",
            })
            pending = nil
        end)
        return function() conn:Disconnect() end
    end)())

    for _, g in ipairs(SUPPORTED) do
        local tab = Window:CreateTab({ name = g.name, icon = g.icon })
        tab:CreateSection({ name = "Supported" })
        tab:CreateText({ name = g.name, text = g.about })
        tab:CreateButton({
            name = "Teleport to " .. g.name,
            description = "Joins a public server of " .. g.name .. ".",
            callback = function()
                pending = g
                if queueOnTeleport then pcall(queueOnTeleport, AUTOLOAD) end
                Window:Notify({
                    title = "Teleporting", duration = 5, icon = "map-pin",
                    content = "Joining " .. g.name .. (queueOnTeleport and "... megab will load there automatically." or "..."),
                })
                local okTp, err = pcall(function() TeleportService:Teleport(g.placeId, LocalPlayer) end)
                if not okTp then
                    Window:Notify({ title = "Teleport failed", content = tostring(err), duration = 8, icon = "circle-alert" })
                end
            end,
        })
    end
    title, content = "Game not supported yet", "Pick a game from the sidebar and teleport there."
end

-- Info tab: always present, always last
local InfoTab = Window:CreateTab({ name = "Info" })
InfoTab:CreateText({
    name = GameName,
    text = ("GameId: %d\nPlaceId: %d\nJobId: %s"):format(GameId, PlaceId, game.JobId),
})
InfoTab:CreateButton({
    name = "Copy GameId",
    callback = function()
        if typeof(setclipboard) == "function" then
            setclipboard(tostring(GameId))
        end
    end,
})
InfoTab:CreateButton({
    name = "Unload hub",
    callback = unloadHub,
})

InfoTab:CreateText({ name = "Credits", text = "made by @aeveloy and claudecode <3" })

splash:Finish()
Window:Open()
Window:Notify({
    title = title, content = content, duration = ok and 4 or 10,
    icon = ok and "circle-check" or (unsupported and "gamepad-2" or "circle-alert"),
})
