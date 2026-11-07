--[[
    megab UI v2: hand-made UI library (no Rayfield)

    Module-facing API (unchanged):
      local UI = loadstring(src)()
      local Window = UI:CreateWindow({ name, subtitle, configuration = { fileName, customFolder } })
      Window:CreateTab({ name, icon? })     -> Tab   (icon = Lucide name; sensible default per tab name)
      Window:Notify({ title, content, duration, icon? })
      Window:Unload()  Window.unloaded  Window.Flags[flag]  Window:Get(flag)  Window:Set(flag, v)
      Window:SetTheme(name)  Window:SetKeybind("RightShift")  Window:Open()  Window:Close()
      UI:CreateSplash({ title, credit, folder }) -> { Step(text, 0..1), Finish(), Fail(text) }  loading screen
      CreateWindow({ startHidden = true }) keeps the window closed until Window:Open()
      Tab:CreateSection({ name })
      Tab:CreateToggle({ name, description, flag, forgetState, value, callback })     -> { value, Set }
      Tab:CreateSlider({ name, description, range, increment, value, suffix, flag, forgetState, callback })
      Tab:CreateDropdown({ name, description, options, value, placeholder, flag, forgetState, callback })
                                                                                      -> { value, Set, Refresh }
      Tab:CreateButton({ name, description, callback })
      Tab:CreateText({ name, text })                                                  -> { Set, SetTitle }

    Per-game element values save to <customFolder>/configs/<fileName>.json.
    UI settings (theme, toggle key) save to <customFolder>/settings.json and apply to every game.
    Icons: Lucide, from Rayfield's generated sprite sheets (48px, rbxassetid + rect offset).
]]

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")

------------------------------------------------------------------ icons (Lucide, 48px sheets)

local ICONS = {
    ["home"] = { 16898613509, 820, 147 },        ["sprout"] = { 16898613777, 918, 306 },
    ["crosshair"] = { 16898613044, 453, 869 },   ["info"] = { 16898613509, 612, 869 },
    ["eye"] = { 16898613353, 771, 563 },         ["settings"] = { 16898613777, 771, 257 },
    ["x"] = { 16898613869, 869, 906 },           ["minus"] = { 16898613613, 771, 196 },
    ["chevron-right"] = { 16898612819, 869, 759 }, ["chevron-down"] = { 16898612819, 196, 918 },
    ["palette"] = { 16898613613, 453, 918 },     ["keyboard"] = { 16898613509, 453, 820 },
    ["bell"] = { 16898612819, 820, 257 },        ["check"] = { 16898612819, 710, 869 },
    ["sparkles"] = { 16898613777, 918, 49 },     ["coins"] = { 16898613044, 869, 612 },
    ["map-pin"] = { 16898613613, 820, 257 },     ["swords"] = { 16898613777, 967, 759 },
    ["shield"] = { 16898613777, 869, 0 },        ["zap"] = { 16898613869, 918, 906 },
    ["bot"] = { 16898612819, 869, 98 },          ["terminal"] = { 16898613869, 820, 257 },
    ["layout-grid"] = { 16898613509, 918, 404 }, ["star"] = { 16898613777, 967, 147 },
    ["heart"] = { 16898613509, 661, 771 },       ["gamepad-2"] = { 16898613353, 710, 967 },
    ["paw-print"] = { 16898613699, 771, 257 },   ["move"] = { 16898613613, 453, 820 },
    ["circle-check"] = { 16898612819, 869, 955 }, ["circle-alert"] = { 16898612819, 918, 808 },
    ["power"] = { 16898613699, 820, 147 },       ["sun"] = { 16898613777, 967, 453 },
    ["moon"] = { 16898613613, 306, 918 },        ["ghost"] = { 16898613353, 869, 906 },
    ["code"] = { 16898613044, 355, 869 },        ["gem"] = { 16898613353, 918, 857 },
    ["flame"] = { 16898613353, 967, 306 },       ["leaf"] = { 16898613509, 918, 661 },
    ["waves"] = { 16898613869, 820, 808 },       ["cherry"] = { 16898612819, 612, 967 },
    ["bird"] = { 16898612819, 869, 0 },          ["skull"] = { 16898613777, 49, 869 },
    ["target"] = { 16898613869, 514, 771 },      ["crown"] = { 16898613044, 404, 918 },
}

-- default tab icons by tab name
local TAB_ICONS = {
    basic = "home", main = "home", home = "home", farm = "sprout", guns = "crosshair", combat = "swords",
    esp = "eye", visuals = "eye", teleport = "map-pin", movement = "move", misc = "layout-grid",
    info = "info", settings = "settings", pets = "paw-print", player = "gamepad-2",
}

------------------------------------------------------------------ themes

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local THEMES = {
    Basic    = { icon = "sparkles", bg = rgb(17,18,23),  panel = rgb(24,26,33),  card = rgb(31,33,42),  cardHover = rgb(38,41,52),  stroke = rgb(48,51,64),  text = rgb(236,238,245), muted = rgb(140,145,162), accent = rgb(124,92,255), accent2 = rgb(64,196,255),  off = rgb(58,61,76),   onText = rgb(255,255,255) },
    Claude   = { mascot = "claude", icon = "star",     bg = rgb(31,30,29),  panel = rgb(38,37,35),  card = rgb(48,46,43),  cardHover = rgb(58,55,51),  stroke = rgb(66,62,57),  text = rgb(240,236,228), muted = rgb(168,160,148), accent = rgb(217,119,87), accent2 = rgb(235,170,120), off = rgb(78,73,67),   onText = rgb(255,255,255) },
    ChatGPT  = { mascot = "chatgpt", icon = "bot",      bg = rgb(13,13,13),  panel = rgb(23,23,23),  card = rgb(33,33,33),  cardHover = rgb(44,44,44),  stroke = rgb(52,52,52),  text = rgb(236,236,236), muted = rgb(155,155,155), accent = rgb(16,163,127), accent2 = rgb(25,195,125),  off = rgb(64,64,64),   onText = rgb(255,255,255) },
    Gemini   = { mascot = "gemini", icon = "gem",      bg = rgb(14,16,24),  panel = rgb(20,23,34),  card = rgb(28,32,46),  cardHover = rgb(36,41,58),  stroke = rgb(46,52,72),  text = rgb(232,236,248), muted = rgb(140,150,175), accent = rgb(71,150,227),  accent2 = rgb(202,102,115), off = rgb(56,62,84),   onText = rgb(255,255,255) },
    Black    = { icon = "moon",     bg = rgb(0,0,0),     panel = rgb(8,8,8),     card = rgb(16,16,16),  cardHover = rgb(26,26,26),  stroke = rgb(38,38,38),  text = rgb(255,255,255), muted = rgb(130,130,130), accent = rgb(255,255,255), accent2 = rgb(170,170,170), off = rgb(50,50,50),   onText = rgb(0,0,0) },
    Code     = { icon = "code",     bg = rgb(30,30,30),  panel = rgb(37,37,38),  card = rgb(45,45,48),  cardHover = rgb(55,55,58),  stroke = rgb(62,62,66),  text = rgb(212,212,212), muted = rgb(140,140,140), accent = rgb(0,122,204),   accent2 = rgb(78,201,176),  off = rgb(70,70,74),   onText = rgb(255,255,255) },
    Ocean    = { icon = "waves",    bg = rgb(10,22,33),  panel = rgb(14,30,44),  card = rgb(19,40,58),  cardHover = rgb(25,50,72),  stroke = rgb(32,60,84),  text = rgb(225,240,250), muted = rgb(130,160,185), accent = rgb(0,170,200),   accent2 = rgb(80,220,200),  off = rgb(38,66,90),   onText = rgb(255,255,255) },
    Sakura   = { icon = "cherry",   bg = rgb(28,18,24),  panel = rgb(38,24,32),  card = rgb(50,32,42),  cardHover = rgb(62,40,52),  stroke = rgb(74,48,62),  text = rgb(250,232,240), muted = rgb(190,150,170), accent = rgb(255,120,170), accent2 = rgb(255,180,210), off = rgb(84,56,70),   onText = rgb(255,255,255) },
    Forest   = { icon = "leaf",     bg = rgb(16,22,17),  panel = rgb(22,30,23),  card = rgb(30,40,31),  cardHover = rgb(38,50,39),  stroke = rgb(46,60,47),  text = rgb(228,240,228), muted = rgb(145,165,145), accent = rgb(90,180,100),  accent2 = rgb(170,220,110), off = rgb(54,68,55),   onText = rgb(255,255,255) },
    Sunset   = { icon = "flame",    bg = rgb(26,16,20),  panel = rgb(36,22,26),  card = rgb(48,29,33),  cardHover = rgb(60,36,40),  stroke = rgb(72,44,48),  text = rgb(250,235,228), muted = rgb(190,155,145), accent = rgb(255,110,80),  accent2 = rgb(255,190,90),  off = rgb(80,52,54),   onText = rgb(255,255,255) },
    Midnight = { icon = "ghost",    bg = rgb(8,10,22),   panel = rgb(13,16,32),  card = rgb(19,23,44),  cardHover = rgb(26,31,56),  stroke = rgb(34,40,70),  text = rgb(225,228,255), muted = rgb(130,135,180), accent = rgb(110,90,255),  accent2 = rgb(240,90,200),  off = rgb(40,46,78),   onText = rgb(255,255,255) },
    Light    = { icon = "sun",      bg = rgb(245,246,250), panel = rgb(235,237,243), card = rgb(255,255,255), cardHover = rgb(240,242,248), stroke = rgb(220,223,232), text = rgb(25,27,35), muted = rgb(110,115,130), accent = rgb(124,92,255), accent2 = rgb(64,160,255), off = rgb(205,208,218), onText = rgb(255,255,255) },
}
local THEME_ORDER = { "Basic", "Claude", "ChatGPT", "Gemini", "Black", "Code", "Ocean", "Sakura", "Forest", "Sunset", "Midnight", "Light" }

local FONT      = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold
local FAST      = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SMOOTH    = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local BOUNCE    = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local THEME_TW  = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local WIDTH, HEIGHT, TOP_H, SIDE_W = 640, 420, 56, 180

------------------------------------------------------------------ small helpers

local function make(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then inst[k] = v end
    end
    for _, child in ipairs(children or {}) do child.Parent = inst end
    if props and props.Parent then inst.Parent = props.Parent end
    return inst
end
local function corner(r) return make("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function pad(t, r, b, l)
    return make("UIPadding", {
        PaddingTop = UDim.new(0, t), PaddingRight = UDim.new(0, r or t),
        PaddingBottom = UDim.new(0, b or t), PaddingLeft = UDim.new(0, l or r or t),
    })
end
local function tween(inst, info, props) local tw = TweenService:Create(inst, info, props) tw:Play() return tw end

local function guiParent()
    local ok, hui = pcall(function() return gethui and gethui() end)
    if ok and hui then return hui end
    local okCore, core = pcall(function() return game:GetService("CoreGui") end)
    if okCore and core then return core end
    return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function readJson(path)
    local ok, data = pcall(function()
        if typeof(isfile) == "function" and isfile(path) then return HttpService:JSONDecode(readfile(path)) end
    end)
    return ok and type(data) == "table" and data or {}
end
local function ensureFolder(path)
    pcall(function() if typeof(isfolder) == "function" and not isfolder(path) then makefolder(path) end end)
end
-- mascot PNGs: cached in <folder>/assets, downloaded from <assetBase>assets/ once, shown via getcustomasset
local assetCache = {}
local function customAsset(folder, assetBase, name)
    if assetCache[name] then return assetCache[name] end
    local getAsset = (typeof(getcustomasset) == "function" and getcustomasset) or (typeof(getsynasset) == "function" and getsynasset)
    if not getAsset or typeof(isfile) ~= "function" then return nil end
    local path = folder .. "/assets/" .. name .. ".png"
    local okFile, exists = pcall(isfile, path)
    if not (okFile and exists) then
        if not assetBase or typeof(writefile) ~= "function" then return nil end
        local ok, body = pcall(game.HttpGet, game, assetBase .. "assets/" .. name .. ".png")
        if not ok or type(body) ~= "string" or body:sub(2, 4) ~= "PNG" then return nil end
        ensureFolder(folder .. "/assets")
        if not pcall(writefile, path, body) then return nil end
    end
    local ok, id = pcall(getAsset, path)
    if ok and id then assetCache[name] = id return id end
    return nil
end
local function writeJsonLater(path, getData)
    local pending = false
    return function()
        if pending or typeof(writefile) ~= "function" then return end
        pending = true
        task.delay(0.4, function()
            pending = false
            pcall(writefile, path, HttpService:JSONEncode(getData()))
        end)
    end
end

------------------------------------------------------------------ library

local UI = {}

------------------------------------------------------------------ loading screen

-- UI:CreateSplash({ title, credit, folder }) -> splash
--   splash:Step(text, progress 0..1)   splash:Finish()  (yields until faded out)
-- Uses the saved theme from <folder>/settings.json so it matches the window.
function UI:CreateSplash(o)
    o = o or {}
    local saved = readJson((o.folder or "megab") .. "/settings.json")
    local T = THEMES[saved.theme or ""] or THEMES.Basic

    local gui = make("ScreenGui", { Name = "megab_splash", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    gui.Parent = guiParent()

    local blur = make("BlurEffect", { Size = 0, Parent = game:GetService("Lighting") })
    local shade = make("Frame", { Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0 })

    local card = make("CanvasGroup", {
        Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(380, 230), BackgroundColor3 = T.bg, GroupTransparency = 1,
    }, { corner(18), make("UIStroke", { Name = "Edge", Color = T.stroke, Thickness = 1, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
    local cardScale = make("UIScale", { Parent = card, Scale = 0.85 })
    local function accentGrad(parent, rot)
        return make("UIGradient", { Parent = parent, Rotation = rot or 0, Color = ColorSequence.new(T.accent, T.accent2) })
    end

    -- soft glow behind the logo
    local glow = make("Frame", { Parent = card, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(120, 120), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.85 }, { corner(60) })
    accentGrad(glow, 45)

    local logo = make("Frame", { Parent = card, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(64, 64), BackgroundColor3 = Color3.new(1, 1, 1) }, { corner(18) })
    local logoGrad = accentGrad(logo, 45)
    make("TextLabel", { Parent = logo, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "m", Font = FONT_BOLD, TextSize = 34, TextColor3 = T.onText })
    local logoScale = make("UIScale", { Parent = logo })

    make("TextLabel", { Parent = card, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 112), Size = UDim2.new(1, -40, 0, 26),
        Text = o.title or "megab", Font = FONT_BOLD, TextSize = 22, TextColor3 = T.text })
    local status = make("TextLabel", { Parent = card, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 140), Size = UDim2.new(1, -40, 0, 18),
        Text = "Starting up...", Font = FONT, TextSize = 13, TextColor3 = T.muted })

    local track = make("Frame", { Parent = card, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 168), Size = UDim2.new(1, -60, 0, 6), BackgroundColor3 = T.off }, { corner(3) })
    local fill = make("Frame", { Parent = track, Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, { corner(3) })
    accentGrad(fill)
    local shine = make("Frame", { Parent = fill, Size = UDim2.fromScale(0.35, 1), Position = UDim2.fromScale(-0.4, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.6, BorderSizePixel = 0 }, { corner(3) })
    local percent = make("TextLabel", { Parent = card, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -30, 0, 176), Size = UDim2.fromOffset(60, 16),
        Text = "0%", Font = FONT_BOLD, TextSize = 11, TextColor3 = T.accent2, TextXAlignment = Enum.TextXAlignment.Right })

    local credit = make("TextLabel", { Parent = card, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -40, 0, 16),
        Text = o.credit or "", Font = FONT_BOLD, TextSize = 12, TextColor3 = Color3.new(1, 1, 1) })
    accentGrad(credit)

    -- idle animations: logo breathes, gradient spins, shine sweeps the bar
    local alive = true
    task.spawn(function()
        local up = true
        while alive do
            tween(logoScale, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Scale = up and 1.08 or 1 })
            tween(glow, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Size = up and UDim2.fromOffset(140, 140) or UDim2.fromOffset(110, 110), BackgroundTransparency = up and 0.8 or 0.9 })
            up = not up
            task.wait(0.9)
        end
    end)
    task.spawn(function()
        while alive do
            logoGrad.Rotation = (logoGrad.Rotation + 2) % 360
            task.wait(1 / 60)
        end
    end)
    task.spawn(function()
        while alive do
            shine.Position = UDim2.fromScale(-0.4, 0)
            tween(shine, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Position = UDim2.fromScale(1.1, 0) })
            task.wait(1.4)
        end
    end)

    -- intro
    tween(blur, SMOOTH, { Size = 14 })
    tween(shade, SMOOTH, { BackgroundTransparency = 0.55 })
    tween(cardScale, BOUNCE, { Scale = 1 })
    tween(card, SMOOTH, { GroupTransparency = 0 })
    tween(card.Edge, SMOOTH, { Transparency = 0 })

    local splash = {}
    local shown = 0
    function splash:Step(msg, progress)
        if msg then status.Text = msg end
        if progress then
            progress = math.clamp(progress, 0, 1)
            tween(fill, SMOOTH, { Size = UDim2.fromScale(progress, 1) })
            local from, to = shown, math.floor(progress * 100 + 0.5)
            shown = to
            task.spawn(function() -- count the percentage up
                for p = from, to do percent.Text = p .. "%" task.wait(0.006) end
            end)
        end
        task.wait(0.25) -- keep each step readable
    end
    function splash:Finish()
        splash:Step("Ready!", 1)
        task.wait(0.35)
        tween(cardScale, SMOOTH, { Scale = 1.06 })
        tween(blur, SMOOTH, { Size = 0 })
        tween(shade, SMOOTH, { BackgroundTransparency = 1 })
        tween(card.Edge, SMOOTH, { Transparency = 1 })
        tween(card, SMOOTH, { GroupTransparency = 1 }).Completed:Wait()
        alive = false
        blur:Destroy()
        gui:Destroy()
    end
    function splash:Fail(msg)
        status.Text = msg or "Failed to load."
        status.TextColor3 = rgb(255, 110, 110)
        task.wait(2.5)
        splash:Finish()
    end
    return splash
end

function UI:CreateWindow(opts)
    opts = opts or {}
    local cfg = type(opts.configuration) == "table" and opts.configuration or {}
    local folder = cfg.customFolder or "megab"
    ensureFolder(folder)
    ensureFolder(folder .. "/configs")

    local Window = { unloaded = false }
    local conns, elements = {}, {}

    -- per-game element values
    local configPath = folder .. "/configs/" .. tostring(cfg.fileName or "default") .. ".json"
    local configData = readJson(configPath)
    local saveConfig = writeJsonLater(configPath, function() return configData end)

    -- global UI settings
    local settingsPath = folder .. "/settings.json"
    local settings = readJson(settingsPath)
    settings.theme = THEMES[settings.theme or ""] and settings.theme or "Basic"
    settings.key = settings.key or "RightShift"
    local saveSettings = writeJsonLater(settingsPath, function() return settings end)

    ------------------------------------------------------ theming

    local T = THEMES[settings.theme]
    local bound, gradients, refreshers = {}, {}, {}

    local function bind(inst, prop, key)
        table.insert(bound, { inst, prop, key })
        inst[prop] = T[key]
        return inst
    end
    local function onTheme(fn) table.insert(refreshers, fn) fn(false) end
    local function grad(parent, rotation)
        local g = make("UIGradient", { Parent = parent, Rotation = rotation or 0, Color = ColorSequence.new(T.accent, T.accent2) })
        table.insert(gradients, g)
        return g
    end
    local function stroke(parent, key, thickness)
        return bind(make("UIStroke", { Parent = parent, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }), "Color", key or "stroke")
    end
    local function icon(name, size, parent, colorKey)
        local d = ICONS[name] or ICONS["layout-grid"]
        local img = make("ImageLabel", {
            Parent = parent, BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size),
            Image = "rbxassetid://" .. d[1], ImageRectSize = Vector2.new(48, 48), ImageRectOffset = Vector2.new(d[2], d[3]),
        })
        if colorKey then bind(img, "ImageColor3", colorKey) end
        return img
    end
    local function text(props, colorKey)
        local l = make("TextLabel", {
            Parent = props.Parent, BackgroundTransparency = 1, Font = props.Font or FONT, Text = props.Text or "",
            TextSize = props.TextSize or 14, TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
            TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center, TextWrapped = props.TextWrapped or false,
            AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None, Size = props.Size or UDim2.new(1, 0, 0, 18),
            Position = props.Position or UDim2.new(), AnchorPoint = props.AnchorPoint or Vector2.new(),
            LayoutOrder = props.LayoutOrder or 0, ZIndex = props.ZIndex or 1, Name = props.Name or "Label",
            TextTruncate = props.TextTruncate or Enum.TextTruncate.None,
        })
        bind(l, "TextColor3", colorKey or "text")
        return l
    end

    local function applyTheme(name, animate)
        if not THEMES[name] then return end
        T = THEMES[name]
        local info = animate and THEME_TW or TweenInfo.new(0)
        local alive = {}
        for _, b in ipairs(bound) do
            local inst, prop, key = b[1], b[2], b[3]
            if inst.Parent then
                table.insert(alive, b)
                if animate then tween(inst, info, { [prop] = T[key] }) else inst[prop] = T[key] end
            end
        end
        bound = alive
        for _, g in ipairs(gradients) do
            if g.Parent then g.Color = ColorSequence.new(T.accent, T.accent2) end
        end
        for _, fn in ipairs(refreshers) do pcall(fn, animate) end
    end

    ------------------------------------------------------ flags

    Window.Flags = setmetatable({}, {
        __index = function(_, flag) local e = elements[flag] return e and e.value end,
        __newindex = function(_, flag, v) local e = elements[flag] if e then e:Set(v) end end,
        __iter = function()
            local snapshot = {}
            for flag, e in pairs(elements) do snapshot[flag] = e.value end
            return next, snapshot
        end,
    })
    function Window:Get(flag) local e = elements[flag] return e and e.value end
    function Window:Set(flag, v) local e = elements[flag] if not e then return false end e:Set(v) return true end

    local function register(handle, o) if o.flag and not o.forgetState then elements[o.flag] = handle end end
    local function savedValue(o, default)
        if o.flag and not o.forgetState and configData[o.flag] ~= nil then return configData[o.flag] end
        return default
    end
    local function persist(o, v) if o.flag and not o.forgetState then configData[o.flag] = v saveConfig() end end

    ------------------------------------------------------ shell

    local gui = make("ScreenGui", {
        Name = "megab_ui", ResetOnSpawn = false, IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
    })
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    gui.Parent = guiParent()

    -- CanvasGroup so the whole window can fade as one
    local main = make("CanvasGroup", {
        Name = "Main", Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(WIDTH, HEIGHT), GroupTransparency = 1,
    }, { corner(16) })
    bind(main, "BackgroundColor3", "bg")
    -- a UIStroke on a CanvasGroup ignores GroupTransparency, so open/close fade it too
    local mainStroke = stroke(main, "stroke", 1)
    mainStroke.Transparency = 1
    local scale = make("UIScale", { Parent = main, Scale = 0.9 })

    -- top bar
    local top = make("Frame", { Name = "Top", Parent = main, Size = UDim2.new(1, 0, 0, TOP_H), BorderSizePixel = 0 })
    bind(top, "BackgroundColor3", "panel")
    local line = make("Frame", { Parent = top, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1) })
    grad(line)

    local logo = make("Frame", { Parent = top, Position = UDim2.fromOffset(14, 12), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = Color3.new(1, 1, 1) }, { corner(10) })
    grad(logo, 45)
    local logoText = make("TextLabel", { Parent = logo, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "m", Font = FONT_BOLD, TextSize = 18 })
    bind(logoText, "TextColor3", "onText")

    text({ Parent = top, Text = opts.name or "megab", Font = FONT_BOLD, TextSize = 16, Position = UDim2.fromOffset(56, 10), Size = UDim2.new(1, -190, 0, 18) })
    text({ Parent = top, Text = opts.subtitle or "", TextSize = 12, Position = UDim2.fromOffset(56, 29), Size = UDim2.new(1, -190, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd }, "muted")

    local function topButton(iconName, x)
        local b = make("TextButton", {
            Parent = top, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, -1),
            Size = UDim2.fromOffset(30, 30), AutoButtonColor = false, Text = "",
        }, { corner(9) })
        bind(b, "BackgroundColor3", "card")
        local ic = icon(iconName, 16, b, "muted")
        ic.AnchorPoint = Vector2.new(0.5, 0.5)
        ic.Position = UDim2.fromScale(0.5, 0.5)
        b.MouseEnter:Connect(function() tween(b, FAST, { BackgroundColor3 = T.cardHover }) tween(ic, FAST, { ImageColor3 = T.text }) end)
        b.MouseLeave:Connect(function() tween(b, FAST, { BackgroundColor3 = T.card }) tween(ic, FAST, { ImageColor3 = T.muted }) end)
        return b, ic
    end
    local closeBtn = topButton("x", -13)
    local miniBtn = topButton("minus", -49)
    local gearBtn, gearIcon = topButton("settings", -85)

    -- body
    local body = make("Frame", { Parent = main, Position = UDim2.fromOffset(0, TOP_H), Size = UDim2.new(1, 0, 1, -TOP_H), BackgroundTransparency = 1, ClipsDescendants = true })
    local sidebar = make("Frame", { Parent = body, Size = UDim2.new(0, SIDE_W, 1, 0), BorderSizePixel = 0 }, {
        pad(12, 10),
        make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
    })
    bind(sidebar, "BackgroundColor3", "panel")
    local pages = make("Frame", { Parent = body, Position = UDim2.fromOffset(SIDE_W, 0), Size = UDim2.new(1, -SIDE_W, 1, 0), BackgroundTransparency = 1 })

    -- AI themes (Claude, ChatGPT, Gemini) show their mascot as a faint watermark over the pages (under settings)
    local MASCOT_FADE = 0.8
    local mascot = make("ImageLabel", {
        Name = "Mascot", Parent = body, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 30, 1, 34),
        Size = UDim2.fromOffset(250, 250), Rotation = -12, BackgroundTransparency = 1, ImageTransparency = 1, ZIndex = 2, Active = false, Interactable = false,
    })
    local mascotToken = 0
    onTheme(function(animate)
        mascotToken += 1
        local token, name = mascotToken, T.mascot
        local function show()
            local id = name and customAsset(folder, opts.assetBase, name)
            if token ~= mascotToken or not mascot.Parent then return end
            if not id then mascot.ImageTransparency = 1 return end
            mascot.Image = id
            if animate then
                mascot.Rotation = -24
                tween(mascot, THEME_TW, { ImageTransparency = MASCOT_FADE, Rotation = -12 })
            else
                mascot.ImageTransparency = MASCOT_FADE
            end
        end
        if animate and mascot.ImageTransparency < 1 then
            tween(mascot, FAST, { ImageTransparency = 1 }).Completed:Connect(function() task.spawn(show) end)
        else
            task.spawn(show)
        end
    end)

    ------------------------------------------------------ notifications

    local toasts = make("Frame", {
        Parent = gui, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -56),
        Size = UDim2.fromOffset(300, 500), BackgroundTransparency = 1,
    }, {
        make("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder }),
    })
    local toastCount = 0

    function Window:Notify(n)
        if Window.unloaded then return end
        n = n or {}
        toastCount += 1
        local holder = make("Frame", { Parent = toasts, LayoutOrder = toastCount, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 })
        local card = make("CanvasGroup", {
            Parent = holder, Position = UDim2.fromOffset(320, 0), Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, GroupTransparency = 1,
        }, { corner(12), pad(12, 14, 12, 50) })
        bind(card, "BackgroundColor3", "panel")
        local edge = make("UIStroke", { Parent = card, Thickness = 1.5, Color = Color3.new(1, 1, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
        grad(edge)
        local badge = make("Frame", { Parent = card, Position = UDim2.new(0, -38, 0, 0), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = Color3.new(1, 1, 1) }, { corner(9) })
        grad(badge, 45)
        local bi = icon(n.icon or "bell", 16, badge, "onText")
        bi.AnchorPoint, bi.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
        local col = make("Frame", { Parent = card, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, {
            make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
        })
        text({ Parent = col, Text = tostring(n.title or ""), Font = FONT_BOLD, TextSize = 14, LayoutOrder = 1 })
        text({ Parent = col, Text = tostring(n.content or ""), TextSize = 13, TextWrapped = true,
            AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2 }, "muted")
        tween(card, SMOOTH, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 })

        local duration = n.duration or math.clamp(#tostring(n.content or "") / 12, 3, 9)
        task.delay(duration, function()
            if not holder.Parent then return end
            tween(card, SMOOTH, { Position = UDim2.fromOffset(320, 0), GroupTransparency = 1 }).Completed:Wait()
            holder:Destroy()
        end)
    end
    Window.Toast = Window.Notify

    ------------------------------------------------------ open / close / reopen pill

    local pill = make("TextButton", {
        Parent = gui, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -60),
        Size = UDim2.fromOffset(46, 46), AutoButtonColor = false, Text = "", Visible = false,
    }, { corner(23) })
    bind(pill, "BackgroundColor3", "panel")
    local pillStroke = make("UIStroke", { Parent = pill, Thickness = 2, Color = Color3.new(1, 1, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    grad(pillStroke, 45)
    local pillLogo = make("Frame", { Parent = pill, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = Color3.new(1, 1, 1) }, { corner(15) })
    grad(pillLogo, 45)
    local pillText = make("TextLabel", { Parent = pillLogo, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "m", Font = FONT_BOLD, TextSize = 16 })
    bind(pillText, "TextColor3", "onText")
    local pillScale = make("UIScale", { Parent = pill, Scale = 1 })
    pill.MouseEnter:Connect(function() tween(pillScale, BOUNCE, { Scale = 1.12 }) end)
    pill.MouseLeave:Connect(function() tween(pillScale, BOUNCE, { Scale = 1 }) end)

    local isOpen, minimized, animating = false, false, false
    local function heightNow() return minimized and TOP_H or HEIGHT end

    local function openUI()
        if isOpen then return end
        isOpen = true
        tween(pill, SMOOTH, { Position = UDim2.new(0.5, 0, 0, -60) }).Completed:Connect(function()
            if isOpen then pill.Visible = false end
        end)
        main.Visible = true
        main.Size = UDim2.fromOffset(WIDTH, heightNow())
        scale.Scale = 0.9
        tween(scale, BOUNCE, { Scale = 1 })
        tween(main, SMOOTH, { GroupTransparency = 0 })
        tween(mainStroke, SMOOTH, { Transparency = 0 })
    end
    local function closeUI()
        if not isOpen then return end
        isOpen = false
        tween(scale, SMOOTH, { Scale = 0.9 })
        tween(mainStroke, SMOOTH, { Transparency = 1 })
        tween(main, SMOOTH, { GroupTransparency = 1 }).Completed:Connect(function()
            if not isOpen then main.Visible = false end
        end)
        pill.Visible = true
        pill.Position = UDim2.new(0.5, 0, 0, -60)
        tween(pill, BOUNCE, { Position = UDim2.new(0.5, 0, 0, 14) })
    end
    local function toggleUI() if isOpen then closeUI() else openUI() end end

    closeBtn.MouseButton1Click:Connect(function()
        closeUI()
        Window:Notify({ title = "megab hidden", content = ("Click the icon at the top or press %s to open it."):format(settings.key), duration = 4, icon = "eye" })
    end)
    pill.MouseButton1Click:Connect(openUI)
    miniBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        tween(main, SMOOTH, { Size = UDim2.fromOffset(WIDTH, heightNow()) })
    end)

    -- keybind (with "press a key" capture used by the settings panel)
    local capturing = nil -- function(keyCodeName) while waiting for a key
    table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if capturing then
            local cb = capturing
            capturing = nil
            cb(input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode.Name or nil)
            return
        end
        if not processed and input.KeyCode.Name == settings.key then toggleUI() end
    end))

    do -- drag by the top bar
        local dragging, dragStart, startPos
        top.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging, dragStart, startPos = true, input.Position, main.Position
            end
        end)
        table.insert(conns, UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local d = input.Position - dragStart
                tween(main, TweenInfo.new(0.08), { Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y) })
            end
        end))
        table.insert(conns, UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end))
    end

    ------------------------------------------------------ element builders (shared by tabs + settings page)

    local function makeList(parent)
        return make("ScrollingFrame", {
            Parent = parent, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
        }, {
            pad(14, 16, 16, 14),
            make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
        })
    end

    local function builders(page)
        local B = {}
        local order = 0
        local function nextOrder() order += 1 return order end
        B.nextOrder = nextOrder -- for custom rows placed between built elements
        local function hasDesc(o) return o.description and o.description ~= "" end

        local function card(o, height)
            local c = make("Frame", {
                Parent = page, LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, height or 0),
                AutomaticSize = height and Enum.AutomaticSize.None or Enum.AutomaticSize.Y,
            }, { corner(10) })
            bind(c, "BackgroundColor3", "card")
            stroke(c)
            local left = make("Frame", { Parent = c, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -96, 1, 0), BackgroundTransparency = 1 }, {
                make("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }),
            })
            text({ Parent = left, Text = o.name or "", Font = FONT_BOLD, TextSize = 14, LayoutOrder = 1 })
            if hasDesc(o) then
                text({ Parent = left, Text = o.description, TextSize = 12, TextWrapped = true,
                    AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2 }, "muted")
            end
            return c, left
        end
        local function hoverable(c, target)
            target.MouseEnter:Connect(function() tween(c, FAST, { BackgroundColor3 = T.cardHover }) end)
            target.MouseLeave:Connect(function() tween(c, FAST, { BackgroundColor3 = T.card }) end)
        end
        local function hitbox(c) return make("TextButton", { Parent = c, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 3 }) end

        function B.section(s)
            local row = make("Frame", { Parent = page, LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 })
            local dot = make("Frame", { Parent = row, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 2, 1, -5), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = Color3.new(1, 1, 1) }, { corner(3) })
            grad(dot, 45)
            text({ Parent = row, Text = string.upper((s and s.name) or ""), Font = FONT_BOLD, TextSize = 11, Position = UDim2.fromOffset(14, 0),
                Size = UDim2.new(1, -14, 1, 0), TextYAlignment = Enum.TextYAlignment.Bottom }, "accent")
        end

        function B.toggle(o)
            local c = card(o, hasDesc(o) and 58 or 44)
            local hit = hitbox(c)
            local track = make("Frame", { Parent = c, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(44, 24) }, { corner(12) })
            local knob = make("Frame", { Parent = track, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(18, 18) }, { corner(9) })
            hoverable(c, hit)
            local handle = { value = false }
            local function render(animate)
                local info = animate == false and TweenInfo.new(0) or BOUNCE
                tween(track, FAST, { BackgroundColor3 = handle.value and T.accent or T.off })
                tween(knob, info, { Position = handle.value and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
                    BackgroundColor3 = handle.value and T.onText or T.text })
            end
            onTheme(function() render(true) end)
            function handle:Set(v, skipCallback)
                handle.value = v and true or false
                render(true)
                persist(o, handle.value)
                if not skipCallback and o.callback then task.spawn(o.callback, handle.value) end
            end
            hit.MouseButton1Click:Connect(function() handle:Set(not handle.value) end)
            register(handle, o)
            local initial = savedValue(o, o.value or false)
            handle:Set(initial, not initial)
            return handle
        end

        function B.button(o)
            local c = card(o, hasDesc(o) and 58 or 44)
            local hit = hitbox(c)
            local ic = icon("chevron-right", 18, c, "muted")
            ic.AnchorPoint, ic.Position = Vector2.new(1, 0.5), UDim2.new(1, -14, 0.5, 0)
            hoverable(c, hit)
            hit.MouseEnter:Connect(function() tween(ic, FAST, { Position = UDim2.new(1, -10, 0.5, 0), ImageColor3 = T.accent }) end)
            hit.MouseLeave:Connect(function() tween(ic, FAST, { Position = UDim2.new(1, -14, 0.5, 0), ImageColor3 = T.muted }) end)
            hit.MouseButton1Click:Connect(function()
                tween(c, TweenInfo.new(0.08), { BackgroundColor3 = T.accent })
                task.delay(0.12, function() tween(c, SMOOTH, { BackgroundColor3 = T.cardHover }) end)
                if o.callback then task.spawn(o.callback) end
            end)
            return {}
        end

        function B.text(o)
            local c = make("Frame", { Parent = page, LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, {
                corner(10), pad(11, 14), make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
            })
            bind(c, "BackgroundColor3", "card")
            stroke(c)
            local title = text({ Parent = c, Text = o.name or "", Font = FONT_BOLD, TextSize = 14, LayoutOrder = 1 })
            local bodyText = text({ Parent = c, Text = o.text or "", TextSize = 13, TextWrapped = true,
                AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2 }, "muted")
            title.Visible = (o.name or "") ~= ""
            local handle = { name = o.name, text = o.text }
            function handle:Set(t) handle.text = t bodyText.Text = t or "" bodyText.Visible = (t or "") ~= "" end
            function handle:SetTitle(t) handle.name = t title.Text = t or "" title.Visible = (t or "") ~= "" end
            return handle
        end

        function B.slider(o)
            local min, max = (o.range and o.range[1]) or 0, (o.range and o.range[2]) or 100
            local inc = o.increment or 1
            local c, left = card(o, hasDesc(o) and 76 or 62)
            left.Size = UDim2.new(1, -96, 0, hasDesc(o) and 46 or 36)
            local valueText = text({ Parent = c, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 9), Size = UDim2.fromOffset(100, 18),
                Font = FONT_BOLD, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right }, "accent2")
            local track = make("Frame", { Parent = c, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -13), Size = UDim2.new(1, -28, 0, 6) }, { corner(3) })
            bind(track, "BackgroundColor3", "off")
            local fill = make("Frame", { Parent = track, Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, { corner(3) })
            grad(fill)
            local dot = make("Frame", { Parent = track, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(16, 16), ZIndex = 2 }, { corner(8) })
            bind(dot, "BackgroundColor3", "text")
            local dotScale = make("UIScale", { Parent = dot })
            local hit = make("TextButton", { Parent = track, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0.5, -13), BackgroundTransparency = 1, Text = "", ZIndex = 3 })

            local handle = { value = min }
            local function snap(v)
                v = math.clamp(v, min, max)
                return math.clamp(min + math.floor((v - min) / inc + 0.5) * inc, min, max)
            end
            local function render(animate)
                local a = (max > min) and (handle.value - min) / (max - min) or 0
                local info = animate and SMOOTH or TweenInfo.new(0.05)
                tween(fill, info, { Size = UDim2.fromScale(a, 1) })
                tween(dot, info, { Position = UDim2.fromScale(a, 0.5) })
                local shown = (inc % 1 == 0) and tostring(math.floor(handle.value + 0.5)) or string.format("%.2f", handle.value)
                valueText.Text = shown .. (o.suffix or "")
            end
            function handle:Set(v, skipCallback)
                handle.value = snap(tonumber(v) or min)
                render(true)
                persist(o, handle.value)
                if not skipCallback and o.callback then task.spawn(o.callback, handle.value, false) end
            end
            local dragging = false
            local function fromX(x)
                local a = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
                local v = snap(min + a * (max - min))
                if v ~= handle.value then
                    handle.value = v
                    render(false)
                    if o.callback then task.spawn(o.callback, v, true) end
                end
            end
            hit.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true
                    tween(dotScale, BOUNCE, { Scale = 1.3 })
                    fromX(input.Position.X)
                end
            end)
            table.insert(conns, UserInputService.InputChanged:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    fromX(input.Position.X)
                end
            end))
            table.insert(conns, UserInputService.InputEnded:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
                    dragging = false
                    tween(dotScale, BOUNCE, { Scale = 1 })
                    handle:Set(handle.value)
                end
            end))
            register(handle, o)
            handle:Set(savedValue(o, o.value or min))
            return handle
        end

        function B.dropdown(o)
            local headerH = hasDesc(o) and 58 or 44
            local c = make("Frame", { Parent = page, LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, headerH), ClipsDescendants = true }, { corner(10) })
            bind(c, "BackgroundColor3", "card")
            stroke(c)
            local header = make("TextButton", { Parent = c, Size = UDim2.new(1, 0, 0, headerH), BackgroundTransparency = 1, Text = "", ZIndex = 3 })
            local left = make("Frame", { Parent = c, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.45, -14, 0, headerH), BackgroundTransparency = 1 }, {
                make("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }),
            })
            text({ Parent = left, Text = o.name or "", Font = FONT_BOLD, TextSize = 14, LayoutOrder = 1 })
            if hasDesc(o) then text({ Parent = left, Text = o.description, TextSize = 12, LayoutOrder = 2, TextTruncate = Enum.TextTruncate.AtEnd }, "muted") end

            local box = make("Frame", { Parent = c, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, (headerH - 30) / 2), Size = UDim2.new(0.55, -14, 0, 30) }, { corner(8) })
            bind(box, "BackgroundColor3", "panel")
            stroke(box)
            local chosen = text({ Parent = box, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -36, 1, 0), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd })
            local arrow = icon("chevron-down", 16, box, "muted")
            arrow.AnchorPoint, arrow.Position = Vector2.new(1, 0.5), UDim2.new(1, -8, 0.5, 0)

            local list = make("Frame", { Parent = c, Position = UDim2.fromOffset(10, headerH), Size = UDim2.new(1, -20, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, {
                make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
                pad(0, 0, 10, 0),
            })
            hoverable(c, header)

            local handle = { value = {} }
            local options, open, optionButtons = {}, false, {}
            local function renderChosen(animate)
                local v = handle.value[1]
                chosen.Text = v or (o.placeholder or "None")
                chosen.TextColor3 = v and T.text or T.muted
                local info = animate and FAST or TweenInfo.new(0)
                for name, b in pairs(optionButtons) do
                    local on = name == v
                    tween(b, info, { BackgroundColor3 = on and T.accent or T.panel, TextColor3 = on and T.onText or T.muted })
                end
            end
            onTheme(function(animate) renderChosen(animate) end)
            local function setOpen(v)
                open = v
                tween(c, SMOOTH, { Size = UDim2.new(1, 0, 0, headerH + (open and (#options * 34 + 10) or 0)) })
                tween(arrow, SMOOTH, { Rotation = open and 180 or 0 })
            end
            function handle:Set(v, skipCallback)
                if type(v) == "table" then v = v[1] end
                handle.value = v and { v } or {}
                renderChosen(true)
                persist(o, v)
                if not skipCallback and o.callback then task.spawn(o.callback, v) end
            end
            function handle:Refresh(newOptions)
                for _, b in pairs(optionButtons) do b:Destroy() end
                table.clear(optionButtons)
                options = newOptions or {}
                for i, name in ipairs(options) do
                    local b = make("TextButton", {
                        Parent = list, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 30), AutoButtonColor = false,
                        Text = "   " .. tostring(name), Font = FONT, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
                        BackgroundColor3 = T.panel, TextColor3 = T.muted,
                    }, { corner(8) })
                    b.MouseEnter:Connect(function() if handle.value[1] ~= name then tween(b, FAST, { BackgroundColor3 = T.cardHover, TextColor3 = T.text }) end end)
                    b.MouseLeave:Connect(function() if handle.value[1] ~= name then tween(b, FAST, { BackgroundColor3 = T.panel, TextColor3 = T.muted }) end end)
                    b.MouseButton1Click:Connect(function() handle:Set(name) setOpen(false) end)
                    optionButtons[name] = b
                end
                local v = handle.value[1]
                if v and not table.find(options, v) then handle:Set(nil) end
                renderChosen(false)
                if open then setOpen(true) end
            end
            function handle:Add(name) local copy = table.clone(options) table.insert(copy, name) handle:Refresh(copy) end
            function handle:Remove(name)
                local copy = table.clone(options)
                local i = table.find(copy, name)
                if i then table.remove(copy, i) handle:Refresh(copy) end
            end
            header.MouseButton1Click:Connect(function() setOpen(not open) end)
            handle:Refresh(o.options or {})
            register(handle, o)
            local initial = savedValue(o, o.value)
            if type(initial) == "table" then initial = initial[1] end
            if initial and table.find(options, initial) then handle:Set(initial) else renderChosen(false) end
            return handle
        end

        return B
    end

    ------------------------------------------------------ tabs

    local tabs, current = {}, nil
    local function paintTab(t, animate)
        local on = t == current
        local info = animate and FAST or TweenInfo.new(0)
        tween(t.button, info, { BackgroundColor3 = on and T.card or T.panel })
        tween(t.label, info, { TextColor3 = on and T.text or T.muted })
        tween(t.icon, info, { ImageColor3 = on and T.accent or T.muted })
        tween(t.marker, info, { BackgroundTransparency = on and 0 or 1, Size = on and UDim2.fromOffset(3, 18) or UDim2.fromOffset(3, 4) })
    end
    local function selectTab(tab)
        if current == tab then return end
        local prev = current
        current = tab
        for _, t in ipairs(tabs) do paintTab(t, true) end
        if prev then prev.page.Visible = false end
        tab.page.Visible = true
        tab.page.Position = UDim2.fromOffset(0, 14)
        tween(tab.page, SMOOTH, { Position = UDim2.fromOffset(0, 0) })
    end
    onTheme(function(animate) for _, t in ipairs(tabs) do paintTab(t, animate) end end)

    function Window:CreateTab(t)
        t = t or {}
        local name = t.name or "Tab"
        local iconName = (type(t.icon) == "string" and ICONS[t.icon] and t.icon) or TAB_ICONS[string.lower(name)] or "layout-grid"

        local button = make("TextButton", { Parent = sidebar, LayoutOrder = #tabs + 1, Size = UDim2.new(1, 0, 0, 36), AutoButtonColor = false, Text = "" }, { corner(10) })
        button.BackgroundColor3 = T.panel
        local ic = icon(iconName, 18, button)
        ic.AnchorPoint, ic.Position = Vector2.new(0, 0.5), UDim2.new(0, 14, 0.5, 0)
        local lbl = make("TextLabel", { Parent = button, BackgroundTransparency = 1, Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -42, 1, 0),
            Text = name, Font = FONT_BOLD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
        local marker = make("Frame", { Parent = button, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0), Size = UDim2.fromOffset(3, 4), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0 }, { corner(2) })
        grad(marker, 90)

        local page = makeList(pages)
        page.Visible = false
        bind(page, "ScrollBarImageColor3", "accent")

        local rec = { button = button, page = page, marker = marker, label = lbl, icon = ic }
        table.insert(tabs, rec)
        paintTab(rec, false)
        button.MouseButton1Click:Connect(function() selectTab(rec) end)
        button.MouseEnter:Connect(function() if current ~= rec then tween(button, FAST, { BackgroundColor3 = T.card }) end end)
        button.MouseLeave:Connect(function() if current ~= rec then tween(button, FAST, { BackgroundColor3 = T.panel }) end end)
        if not current then selectTab(rec) end

        local B = builders(page)
        local Tab = {}
        function Tab:CreateSection(o) return B.section(o) end
        function Tab:CreateToggle(o) return B.toggle(o) end
        function Tab:CreateButton(o) return B.button(o) end
        function Tab:CreateText(o) return B.text(o) end
        function Tab:CreateSlider(o) return B.slider(o) end
        function Tab:CreateDropdown(o) return B.dropdown(o) end
        return Tab
    end

    ------------------------------------------------------ settings panel (gear button)

    local settingsPage = make("Frame", { Parent = body, Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(1, 1), ZIndex = 5, Visible = false })
    bind(settingsPage, "BackgroundColor3", "bg")
    local settingsList = makeList(settingsPage)
    bind(settingsList, "ScrollBarImageColor3", "accent")
    local S = builders(settingsList)

    S.section({ name = "Theme" })
    local grid = make("Frame", { Parent = settingsList, LayoutOrder = S.nextOrder(), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, {
        make("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 0, 64), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
    })
    local themeCells = {}
    for i, themeName in ipairs(THEME_ORDER) do
        local th = THEMES[themeName]
        local cell = make("TextButton", { Parent = grid, LayoutOrder = i, AutoButtonColor = false, Text = "", BackgroundColor3 = th.card }, { corner(10) })
        local cs = make("UIStroke", { Parent = cell, Thickness = 1, Color = th.stroke, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
        local cScale = make("UIScale", { Parent = cell })
        local ci = icon(th.icon, 18, cell)
        ci.ImageColor3 = th.accent
        ci.Position = UDim2.fromOffset(10, 10)
        make("TextLabel", { Parent = cell, BackgroundTransparency = 1, Position = UDim2.fromOffset(34, 9), Size = UDim2.new(1, -40, 0, 20),
            Text = themeName, Font = FONT_BOLD, TextSize = 13, TextColor3 = th.text, TextXAlignment = Enum.TextXAlignment.Left })
        local swatches = make("Frame", { Parent = cell, Position = UDim2.new(0, 10, 1, -22), Size = UDim2.new(1, -20, 0, 12), BackgroundTransparency = 1 }, {
            make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }),
        })
        for _, key in ipairs({ "accent", "accent2", "bg", "text" }) do
            make("Frame", { Parent = swatches, Size = UDim2.fromOffset(12, 12), BackgroundColor3 = th[key] }, { corner(6), make("UIStroke", { Color = th.stroke, Thickness = 1 }) })
        end
        cell.MouseEnter:Connect(function() tween(cScale, BOUNCE, { Scale = 1.04 }) end)
        cell.MouseLeave:Connect(function() tween(cScale, BOUNCE, { Scale = 1 }) end)
        cell.MouseButton1Click:Connect(function() Window:SetTheme(themeName) end)
        themeCells[themeName] = { stroke = cs, theme = th }
    end
    onTheme(function(animate)
        for themeName, c in pairs(themeCells) do
            local on = themeName == settings.theme
            tween(c.stroke, animate and FAST or TweenInfo.new(0), { Color = on and T.accent or c.theme.stroke, Thickness = on and 2 or 1 })
        end
    end)

    S.section({ name = "Keybind" })
    local keyCard = make("Frame", { Parent = settingsList, LayoutOrder = S.nextOrder(), Size = UDim2.new(1, 0, 0, 58) }, { corner(10) })
    bind(keyCard, "BackgroundColor3", "card")
    stroke(keyCard)
    local kic = icon("keyboard", 18, keyCard, "accent")
    kic.AnchorPoint, kic.Position = Vector2.new(0, 0.5), UDim2.new(0, 14, 0.5, 0)
    local keyLeft = make("Frame", { Parent = keyCard, Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -170, 1, 0), BackgroundTransparency = 1 }, {
        make("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }),
    })
    text({ Parent = keyLeft, Text = "Open / close key", Font = FONT_BOLD, TextSize = 14, LayoutOrder = 1 })
    text({ Parent = keyLeft, Text = "Click, then press any key. Esc cancels.", TextSize = 12, LayoutOrder = 2 }, "muted")
    local keyBtn = make("TextButton", { Parent = keyCard, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(116, 32),
        AutoButtonColor = false, Font = FONT_BOLD, TextSize = 13, Text = settings.key }, { corner(8) })
    bind(keyBtn, "BackgroundColor3", "panel")
    bind(keyBtn, "TextColor3", "accent2")
    stroke(keyBtn)
    keyBtn.MouseButton1Click:Connect(function()
        keyBtn.Text = "Press a key..."
        tween(keyBtn, FAST, { BackgroundColor3 = T.cardHover })
        capturing = function(keyName)
            if keyName then Window:SetKeybind(keyName) end
            keyBtn.Text = settings.key
            tween(keyBtn, FAST, { BackgroundColor3 = T.panel })
        end
    end)

    S.section({ name = "About" })
    S.text({ name = "megab UI", text = "Hand-made UI. Lucide icons, " .. #THEME_ORDER .. " themes. Theme and key are saved for every game." })

    local settingsOpen = false
    gearBtn.MouseButton1Click:Connect(function()
        settingsOpen = not settingsOpen
        if settingsOpen then
            settingsPage.Visible = true
            settingsPage.Position = UDim2.fromScale(1, 0)
            tween(settingsPage, SMOOTH, { Position = UDim2.fromScale(0, 0) })
        else
            tween(settingsPage, SMOOTH, { Position = UDim2.fromScale(1, 0) }).Completed:Connect(function()
                if not settingsOpen then settingsPage.Visible = false end
            end)
        end
        tween(gearIcon, SMOOTH, { Rotation = settingsOpen and 90 or 0 })
    end)

    function Window:SetTheme(name)
        if not THEMES[name] then return false end
        settings.theme = name
        saveSettings()
        applyTheme(name, true)
        return true
    end
    function Window:SetKeybind(keyName)
        if typeof(keyName) == "EnumItem" then keyName = keyName.Name end
        if type(keyName) ~= "string" then return false end
        settings.key = keyName
        keyBtn.Text = keyName
        saveSettings()
        Window:Notify({ title = "Keybind set", content = keyName .. " now opens and closes megab.", duration = 3, icon = "keyboard" })
        return true
    end
    Window.Themes = THEME_ORDER

    ------------------------------------------------------ unload

    function Window:Unload()
        if Window.unloaded then return end
        Window.unloaded = true
        for _, c in ipairs(conns) do c:Disconnect() end
        table.clear(conns)
        tween(scale, SMOOTH, { Scale = 0.9 })
        tween(pill, SMOOTH, { Position = UDim2.new(0.5, 0, 0, -60) })
        tween(mainStroke, SMOOTH, { Transparency = 1 })
        tween(main, SMOOTH, { GroupTransparency = 1 }).Completed:Wait()
        gui:Destroy()
    end
    Window.Destroy = Window.Unload

    function Window:Open() openUI() end
    function Window:Close() closeUI() end

    -- first open (startHidden: the caller opens it later, e.g. after the loading screen)
    applyTheme(settings.theme, false)
    if not opts.startHidden then openUI() else main.Visible = false end

    return Window
end

return UI
