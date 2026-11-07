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
Window:Notify({ title = title, content = content, duration = ok and 4 or 10, icon = ok and "circle-check" or "circle-alert" })
