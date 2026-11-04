--[[
    NIGHTS HUB  v1.0
    99 Nights in the Forest  |  Delta / mobile
    Todas as funcoes sao toggles. Nada liga sozinho.
    Config: NightsHub/config.json
]]

local CONFIG = {
    versao     = "1.0",
    savePath   = "NightsHub/config.json",
    accent     = Color3.fromRGB(0, 229, 255),
    accentDim  = Color3.fromRGB(0, 120, 140),
    bg         = Color3.fromRGB(14, 15, 20),
    bgPanel    = Color3.fromRGB(20, 22, 29),
    text       = Color3.fromRGB(232, 240, 245),
    textDim    = Color3.fromRGB(130, 145, 158),
    danger     = Color3.fromRGB(255, 82, 82),
    maxEsp     = 150,
    jitter     = 0.18,
}

local PALETTE = {
    Color3.fromRGB(255, 72, 72),  Color3.fromRGB(255, 140, 0),
    Color3.fromRGB(255, 215, 0),  Color3.fromRGB(80, 255, 120),
    Color3.fromRGB(0, 229, 255),  Color3.fromRGB(160, 110, 255),
    Color3.fromRGB(255, 110, 200),Color3.fromRGB(255, 255, 255),
}

if getgenv().NightsHub then
    pcall(function() getgenv().NightsHub.destroy() end)
    task.wait(0.15)
end

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local Lighting     = game:GetService("Lighting")
local RS           = game:GetService("ReplicatedStorage")
local Workspace    = game:GetService("Workspace")
local VIM          = game:GetService("VirtualInputManager")

local plr  = Players.LocalPlayer
local cam  = Workspace.CurrentCamera
local plrGui = plr:WaitForChild("PlayerGui")

local NH = { conns = {}, tasks = {}, drawings = {}, alive = true }
getgenv().NightsHub = NH

---------------------------------------------------------------------
-- LOGGER
---------------------------------------------------------------------
local LOG = { buf = {}, last = {}, n = 0 }

local function log(level, msg)
    local key = level .. msg
    LOG.last[key] = (LOG.last[key] or 0) + 1
    if LOG.last[key] > 3 then return end
    LOG.n += 1
    table.insert(LOG.buf, ("[%s] %s"):format(level, msg))
    if #LOG.buf > 200 then table.remove(LOG.buf, 1) end
    if level == "erro" then pcall(function() warn("[NightsHub] " .. msg) end) end
end

local function conn(sig, fn)
    local c = sig:Connect(fn)
    table.insert(NH.conns, c)
    return c
end

---------------------------------------------------------------------
-- NOTIFICACOES
---------------------------------------------------------------------
local notifHolder

local function notif(msg, kind)
    if not notifHolder then return end
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -24, 0, 34)
    f.Position = UDim2.new(0, 12, 0, -40)
    f.BackgroundColor3 = CONFIG.bgPanel
    f.BackgroundTransparency = 0.1
    f.BorderSizePixel = 0
    f.Parent = notifHolder
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 8) c.Parent = f
    local s = Instance.new("UIStroke")
    s.Color = (kind == "erro" and CONFIG.danger) or CONFIG.accent
    s.Thickness = 1 s.Transparency = 0.35 s.Parent = f
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -16, 1, 0) l.Position = UDim2.new(0, 10, 0, 0)
    l.BackgroundTransparency = 1 l.Font = Enum.Font.Code
    l.TextSize = 12 l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextColor3 = CONFIG.text l.Text = msg l.Parent = f
    TweenService:Create(f, TweenInfo.new(0.22), { Position = UDim2.new(0, 12, 0, 10) }):Play()
    task.delay(2.2, function()
        if f.Parent then
            TweenService:Create(f, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
            task.delay(0.2, function() f:Destroy() end)
        end
    end)
end

---------------------------------------------------------------------
-- CONFIG STORE
---------------------------------------------------------------------
local CFG = {}

local function save()
    local ok, data = pcall(function()
        local t = {}
        for k, v in pairs(CFG) do t[k] = v end
        return game:GetService("HttpService"):JSONEncode({ schema = 1, ui = UI.saveState(), cfg = t })
    end)
    if not ok or not writefile then return end
    pcall(function()
        if makefolder then makefolder("NightsHub") end
        writefile(CONFIG.savePath, data)
    end)
end

local function load()
    if not (isfile and readfile) then return end
    local ok, raw = pcall(function() return isfile(CONFIG.savePath) and readfile(CONFIG.savePath) end)
    if not ok or not raw then return end
    local ok2, data = pcall(function() return game:GetService("HttpService"):JSONDecode(raw) end)
    if not ok2 or type(data) ~= "table" then return end
    if type(data.cfg) == "table" then
        for k, v in pairs(data.cfg) do CFG[k] = v end
    end
    if type(data.ui) == "table" then UI.loadState(data.ui) end
end

local saveDebounce
local function queueSave()
    if saveDebounce then task.cancel(saveDebounce) end
    saveDebounce = task.delay(1.5, save)
end

local function setCfg(id, v)
    CFG[id] = v
    queueSave()
end

---------------------------------------------------------------------
-- SCHEDULER
---------------------------------------------------------------------
local SCHED = { list = {} }

function SCHED.add(id, interval, fn, jitter)
    SCHED.list[id] = { interval = interval, fn = fn, jitter = jitter or CONFIG.jitter, last = 0, busy = false, fails = 0 }
end

conn(RunService.Heartbeat, function()
    local now = os.clock()
    for id, t in pairs(SCHED.list) do
        if t.busy then continue end
        local w = t.interval * (1 + t.jitter * (math.random() * 2 - 1))
        if now - t.last < w then continue end
        t.last = now
        t.busy = true
        task.spawn(function()
            local ok, err = pcall(t.fn)
            t.busy = false
            if not ok then
                t.fails += 1
                if t.fails <= 3 then log("erro", ("%s: %s"):format(id, tostring(err))) end
                if t.fails == 4 then notif("Modulo " .. id .. " suspenso", "erro") end
            else
                t.fails = 0
            end
        end)
    end
end)

---------------------------------------------------------------------
-- BRIDGE
---------------------------------------------------------------------
local Bridge = { remotes = {}, lastScan = 0 }
local SCAN_WORDS = { "damage", "hit", "attack", "swing", "combat", "mob", "chop", "harvest", "pickup", "collect", "interact", "fuel", "upgrade", "open" }

function Bridge.rescan()
    Bridge.remotes = {}
    for _, d in ipairs(RS:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
            local n = d.Name:lower()
            local score = 0
            for _, w in ipairs(SCAN_WORDS) do
                if n:find(w, 1, true) then score += 1 end
            end
            if score > 0 then table.insert(Bridge.remotes, { obj = d, score = score }) end
        end
    end
    table.sort(Bridge.remotes, function(a, b) return a.score > b.score end)
    Bridge.lastScan = os.clock()
    log("info", "scan: " .. #Bridge.remotes .. " remotes")
end

function Bridge.fire(obj, ...)
    if not obj then return false end
    local args = { ... }
    if obj:IsA("RemoteEvent") then
        return pcall(obj.FireServer, obj, table.unpack(args))
    else
        return pcall(obj.InvokeServer, obj, table.unpack(args))
    end
end

function Bridge.broadcast(maxN, ...)
    local n = 0
    for _, r in ipairs(Bridge.remotes) do
        if n >= maxN then break end
        Bridge.fire(r.obj, ...)
        n += 1
    end
    return n
end

---------------------------------------------------------------------
-- CHARACTER HELPERS
---------------------------------------------------------------------
local function char() return plr.Character end
local function hrp()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function hum()
    local c = char()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function tpSilent(pos)
    local p = hrp()
    if not p then return false end
    local cur = p.CFrame
    p.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    return cur
end

local function approach(target, offset)
    local p = hrp()
    if not p or not target then return end
    local ok, tpos = pcall(function() return target:GetPivot().Position end)
    if not ok then return end
    local dir = (p.Position - tpos).Unit
    p.CFrame = CFrame.new(tpos + dir * (offset or 6) + Vector3.new(0, 2, 0))
end

local function distTo(pos)
    local p = hrp()
    if not p then return 1e9 end
    return (p.Position - pos).Magnitude
end

local function equipTool(word)
    local c = char()
    if not c then return nil end
    for _, t in ipairs(c:GetChildren()) do
        if t:IsA("Tool") and t.Name:lower():find(word, 1, true) then
            hum():EquipTool(t)
            return t
        end
    end
    return nil
end

local function activatedTool()
    local c = char()
    if not c then return end
    for _, t in ipairs(c:GetChildren()) do
        if t:IsA("Tool") then pcall(function() t:Activate() end) return end
    end
end

---------------------------------------------------------------------
-- ENTITY FINDER
---------------------------------------------------------------------
local CATS = {
    wolf   = { words = { "wolf" }, notWords = { "alpha" } },
    alpha  = { words = { "alpha" } },
    bear   = { words = { "bear" } },
    cultist= { words = { "cultist", "zealot" } },
    deer   = { words = { "deer" } },
    kid    = { words = { "kid", "child" } },
    chest  = { words = { "chest", "crate" } },
    diamond= { words = { "diamond", "gem" } },
    trader = { words = { "trader", "pelt" } },
    item   = { words = { "pickup", "drop", "loot" } },
    tree   = { words = { "tree", "oak", "pine" } },
    cave   = { words = { "cave" } },
    poi    = { words = { "stronghold", "shrine", "campfire", "fire" } },
}

local function matchCat(name, cat)
    local n = name:lower()
    local d = CATS[cat]
    if not d then return false end
    for _, w in ipairs(d.notWords or {}) do
        if n:find(w, 1, true) then return false end
    end
    for _, w in ipairs(d.words) do
        if n:find(w, 1, true) then return true end
    end
    return false
end

local function findCat(cat, radius)
    local out = {}
    local p = hrp()
    if not p then return out end
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("Model") and matchCat(d.Name, cat) then
            local ok, pivot = pcall(function() return d:GetPivot().Position end)
            if ok then
                local dd = (pivot - p.Position).Magnitude
                if dd <= radius then table.insert(out, { obj = d, pos = pivot, dist = dd }) end
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

---------------------------------------------------------------------
-- DEFINICOES DA UI
---------------------------------------------------------------------
local DEFS = {
    { id = "farm", code = "FRM", name = "FARM", items = {
        { t = "sec", name = "COLETA" },
        { t = "toggle", id = "farm.tp", name = "Farm por teleporte", def = true },
        { t = "toggle", id = "farm.wood", name = "Auto Madeira", def = false },
        { t = "slider", id = "farm.woodDist", name = "Distancia madeira", min = 10, max = 120, def = 45 },
        { t = "toggle", id = "farm.fruit", name = "Auto Fruta" },
        { t = "slider", id = "farm.fruitDist", name = "Distancia fruta", min = 10, max = 100, def = 40 },
        { t = "toggle", id = "farm.scrap", name = "Auto Scrap" },
        { t = "slider", id = "farm.scrapDist", name = "Distancia scrap", min = 10, max = 100, def = 40 },
        { t = "toggle", id = "farm.stone", name = "Auto Pedra" },
        { t = "toggle", id = "farm.loot", name = "Auto Loot" },
        { t = "slider", id = "farm.lootDist", name = "Distancia loot", min = 5, max = 80, def = 30 },
        { t = "sec", name = "DIAMANTE" },
        { t = "toggle", id = "farm.chest", name = "Auto Bau" },
        { t = "slider", id = "farm.chestDist", name = "Distancia bau", min = 10, max = 150, def = 60 },
        { t = "toggle", id = "farm.badge", name = "Auto Badge" },
        { t = "toggle", id = "farm.stronghold", name = "Auto Fortaleza" },
        { t = "sec", name = "ACAMPAMENTO" },
        { t = "toggle", id = "camp.fuel", name = "Auto Combustivel" },
        { t = "toggle", id = "camp.upgrade", name = "Auto Upgrade" },
        { t = "slider", id = "camp.interval", name = "Intervalo (s)", min = 0.4, max = 3, def = 1, step = 0.1 },
    }},
    { id = "combat", code = "CMB", name = "COMBATE", items = {
        { t = "sec", name = "KILL AURA" },
        { t = "toggle", id = "combat.aura", name = "Kill Aura" },
        { t = "slider", id = "combat.auraDist", name = "Alcance", min = 8, max = 120, def = 45 },
        { t = "slider", id = "combat.auraDelay", name = "Delay (s)", min = 0.05, max = 0.5, def = 0.15, step = 0.05 },
        { t = "slider", id = "combat.auraTargets", name = "Alvos por ciclo", min = 1, max = 6, def = 3, step = 1 },
        { t = "toggle", id = "combat.approach", name = "Aproximar do alvo", def = true },
        { t = "toggle", id = "combat.onlyCamp", name = "So perto da fogueira" },
        { t = "sec", name = "ALVOS DO AURA" },
        { t = "toggle", id = "combat.mob.wolf", name = "Lobo", def = true },
        { t = "toggle", id = "combat.mob.alpha", name = "Lobo Alfa", def = true },
        { t = "toggle", id = "combat.mob.bear", name = "Urso", def = true },
        { t = "toggle", id = "combat.mob.cultist", name = "Cultista", def = true },
        { t = "toggle", id = "combat.mob.deer", name = "Deer", def = false },
        { t = "sec", name = "KILL AURA ARVORE" },
        { t = "toggle", id = "combat.tree", name = "Kill Aura Arvore" },
        { t = "slider", id = "combat.treeDist", name = "Alcance", min = 5, max = 80, def = 30 },
        { t = "toggle", id = "combat.treeApproach", name = "Chegar perto", def = true },
        { t = "toggle", id = "combat.treeDrop", name = "So arvores com drop", def = true },
        { t = "sec", name = "ARMA" },
        { t = "toggle", id = "combat.autoEquip", name = "Auto equipar arma", def = true },
        { t = "toggle", id = "combat.silentAim", name = "Silent Aim" },
    }},
    { id = "esp", code = "ESP", name = "VISUAL", items = {
        { t = "sec", name = "GERAL" },
        { t = "toggle", id = "esp.on", name = "ESP Master" },
        { t = "toggle", id = "esp.box", name = "Caixa", def = true },
        { t = "toggle", id = "esp.name", name = "Nome", def = true },
        { t = "toggle", id = "esp.dist", name = "Distancia", def = true },
        { t = "toggle", id = "esp.tracer", name = "Tracer" },
        { t = "sec", name = "CATEGORIAS" },
        { t = "esprow", cat = "wolf", name = "Lobo" },
        { t = "esprow", cat = "alpha", name = "Lobo Alfa" },
        { t = "esprow", cat = "bear", name = "Urso" },
        { t = "esprow", cat = "cultist", name = "Cultista" },
        { t = "esprow", cat = "deer", name = "Deer" },
        { t = "esprow", cat = "kid", name = "Crianca" },
        { t = "esprow", cat = "chest", name = "Bau" },
        { t = "esprow", cat = "diamond", name = "Diamante" },
        { t = "esprow", cat = "trader", name = "Pelt Trader" },
        { t = "esprow", cat = "item", name = "Item" },
        { t = "esprow", cat = "tree", name = "Arvore" },
        { t = "esprow", cat = "cave", name = "Caverna" },
        { t = "esprow", cat = "poi", name = "Ponto de interesse" },
    }},
    { id = "mov", code = "MOV", name = "MOVIMENTO", items = {
        { t = "sec", name = "VELOCIDADE" },
        { t = "toggle", id = "mov.speedOn", name = "Speed" },
        { t = "slider", id = "mov.speed", name = "Valor", min = 16, max = 200, def = 32 },
        { t = "sec", name = "PULO" },
        { t = "toggle", id = "mov.jumpOn", name = "Jump" },
        { t = "slider", id = "mov.jump", name = "Valor", min = 50, max = 200, def = 80 },
        { t = "sec", name = "VOADOR" },
        { t = "toggle", id = "mov.fly", name = "Fly" },
        { t = "slider", id = "mov.flySpeed", name = "Velocidade do voo", min = 20, max = 200, def = 60 },
        { t = "sec", name = "OUTROS" },
        { t = "toggle", id = "mov.noclip", name = "Noclip" },
        { t = "toggle", id = "mov.stamina", name = "Stamina Infinita" },
        { t = "toggle", id = "mov.antifall", name = "Anti-Fall", def = true },
        { t = "toggle", id = "mov.antiafk", name = "Anti-AFK", def = true },
    }},
    { id = "world", code = "WRLD", name = "MUNDO", items = {
        { t = "sec", name = "MAPA" },
        { t = "toggle", id = "world.reveal", name = "Revelar Mapa" },
        { t = "toggle", id = "world.wallpass", name = "Atravessar Parede" },
        { t = "sec", name = "TELEPORTE" },
        { t = "toggle", id = "world.silent", name = "Modo Silent", def = true },
        { t = "button", id = "tp.save", name = "Salvar ponto" },
        { t = "button", id = "tp.back", name = "Voltar ao ponto" },
        { t = "sec", name = "DESTINOS" },
        { t = "button", id = "tp.camp", name = "Acampamento" },
        { t = "button", id = "tp.fire", name = "Fogueira" },
        { t = "button", id = "tp.kid", name = "Criancas" },
        { t = "button", id = "tp.trader", name = "Pelt Trader" },
        { t = "button", id = "tp.strong", name = "Fortaleza Cultista" },
        { t = "button", id = "tp.cave", name = "Caverna" },
        { t = "button", id = "tp.chest", name = "Bau mais proximo" },
        { t = "button", id = "tp.poi", name = "Ponto de interesse" },
    }},
    { id = "items", code = "ITM", name = "ITENS", items = {
        { t = "sec", name = "TRAZER" },
        { t = "toggle", id = "item.bring", name = "Bring Item" },
        { t = "slider", id = "item.bringDist", name = "Alcance", min = 10, max = 150, def = 60 },
        { t = "button", id = "item.bringAll", name = "Trazer tudo no raio" },
        { t = "sec", name = "SOBREVIVENCIA" },
        { t = "toggle", id = "item.autoEat", name = "Auto Comer" },
        { t = "slider", id = "item.eatAt", name = "Comer abaixo de (%)", min = 10, max = 80, def = 45 },
        { t = "toggle", id = "item.autoHeal", name = "Auto Curar" },
        { t = "toggle", id = "item.autoRepair", name = "Auto Reparar" },
    }},
    { id = "cfg", code = "CFG", name = "SISTEMA", items = {
        { t = "sec", name = "PERFIL" },
        { t = "toggle", id = "sys.discrete", name = "Modo Discreto" },
        { t = "button", id = "sys.save", name = "Salvar config" },
        { t = "button", id = "sys.load", name = "Carregar config" },
        { t = "button", id = "sys.reset", name = "Resetar tudo" },
        { t = "sec", name = "DIAGNOSTICO" },
        { t = "button", id = "sys.remotes", name = "Listar remotes" },
        { t = "button", id = "sys.dump", name = "Dump no clipboard" },
        { t = "sec", name = "SESSAO" },
        { t = "label", id = "sys.stats", name = "stats" },
        { t = "button", id = "sys.panic", name = "PANICO" },
        { t = "button", id = "sys.unload", name = "Descarregar hub" },
    }},
}

for _, tab in ipairs(DEFS) do
    for _, it in ipairs(tab.items) do
        if it.id and CFG[it.id] == nil then
            if it.t == "toggle" then CFG[it.id] = it.def == true
            elseif it.t == "slider" then CFG[it.id] = it.def
            elseif it.t == "esprow" then
                CFG["esp.cat." .. it.cat] = false
                CFG["esp.cold." .. it.cat] = math.random(1, #PALETTE)
                CFG["esp.dist." .. it.cat] = 150
            end
        end
    end
end

---------------------------------------------------------------------
-- UI ENGINE
---------------------------------------------------------------------
local UI = { root = nil, panel = nil, body = nil, bubble = nil, current = nil, tabBtns = {} }

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    o.Parent = parent
    return o
end

local function corner(o, r)
    mk("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

local function stroke(o, color, th, tr)
    mk("UIStroke", { Color = color, Thickness = th or 1, Transparency = tr or 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end

function UI.saveState()
    if not UI.panel then return {} end
    return { pos = { UI.panel.Position.X.Offset, UI.panel.Position.Y.Offset }, bubble = UI.bubble.Position.X.Offset, collapsed = UI.bubble.Visible }
end

function UI.loadState(s)
    if not s or not UI.panel then return end
    if s.pos then UI.panel.Position = UDim2.fromOffset(s.pos[1], s.pos[2]) end
end

local function divider(parent)
    local d = mk("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = CONFIG.accent, BackgroundTransparency = 0.8, BorderSizePixel = 0 }, parent)
    return d
end

local function section(parent, text)
    local wrap = mk("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, parent)
    mk("TextLabel", {
        Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(0, 6),
        BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11,
        TextColor3 = CONFIG.accent, TextXAlignment = Enum.TextXAlignment.Left,
        Text = "// " .. text, Parent = wrap,
    })
    return wrap
end

local function row(parent, h)
    return mk("Frame", { Size = UDim2.new(1, 0, 0, h or 40), BackgroundTransparency = 1 }, parent)
end

local function toggle(parent, id, name)
    local r = row(parent, 40)
    mk("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = CONFIG.text,
        TextXAlignment = Enum.TextXAlignment.Left, Text = name, Parent = r,
    })
    local track = mk("Frame", { Size = UDim2.fromOffset(46, 26), Position = UDim2.new(1, -46, 0.5, -13), BackgroundColor3 = Color3.fromRGB(48, 52, 62), BorderSizePixel = 0 }, r)
    corner(track, 13)
    local knob = mk("Frame", { Size = UDim2.fromOffset(20, 20), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = CONFIG.text, BorderSizePixel = 0 }, track)
    corner(knob, 10)

    local function paint(on)
        track.BackgroundColor3 = on and CONFIG.accent or Color3.fromRGB(48, 52, 62)
        TweenService:Create(knob, TweenInfo.new(0.12), { Position = on and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3) }):Play()
        knob.BackgroundColor3 = on and Color3.new(1, 1, 1) or CONFIG.text
    end

    local btn = mk("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" }, track)
    paint(CFG[id] == true)
    btn.MouseButton1Click:Connect(function()
        setCfg(id, not CFG[id])
        paint(CFG[id])
    end)
    return r
end

local function slider(parent, id, name, min, max, step)
    local wrap = mk("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 }, parent)
    mk("TextLabel", {
        Size = UDim2.new(0.6, 0, 0, 16), BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = CONFIG.textDim,
        TextXAlignment = Enum.TextXAlignment.Left, Text = name, Parent = wrap,
    })
    local valLbl = mk("TextLabel", {
        Size = UDim2.new(0.4, 0, 0, 16), Position = UDim2.new(0.6, 0, 0, 0), BackgroundTransparency = 1,
        Font = Enum.Font.Code, TextSize = 12, TextColor3 = CONFIG.accent,
        TextXAlignment = Enum.TextXAlignment.Right, Text = tostring(CFG[id]), Parent = wrap,
    })
    local track = mk("Frame", { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(44, 48, 58), BorderSizePixel = 0 }, wrap)
    corner(track, 3)
    local fill = mk("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = CONFIG.accent, BorderSizePixel = 0 }, track)
    corner(fill, 3)
    local knob = mk("Frame", { Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 3 }, track)
    corner(knob, 9)

    local function paint()
        local a = (CFG[id] - min) / (max - min)
        fill.Size = UDim2.new(a, 0, 1, 0)
        knob.Position = UDim2.new(a, -9, 0.5, -9)
        valLbl.Text = (step and step < 1) and string.format("%.2f", CFG[id]) or tostring(math.floor(CFG[id]))
    end

    local drag = mk("TextButton", { Size = UDim2.new(1, 0, 1, 12), Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1, Text = "" }, track)

    local function apply(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local v = min + (max - min) * rel
        if step then v = math.floor(v / step + 0.5) * step end
        setCfg(id, math.clamp(v, min, max))
        paint()
    end

    drag.MouseButton1Down:Connect(function(x) apply(x) end)
    drag.MouseMoved:Connect(function(x) if drag:GetAttribute("h") then apply(x) end end)
    drag.MouseEnter:Connect(function() drag:SetAttribute("h", true) end)
    drag.MouseLeave:Connect(function() drag:SetAttribute("h", false) end)
    conn(UIS.InputChanged, function(i)
        if i.UserInputType == Enum.UserInputType.Touch and drag:GetAttribute("h") then apply(i.Position.X) end
    end)
    conn(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.Touch then drag:SetAttribute("h", false) end
    end)

    paint()
    return wrap
end

local function button(parent, id, name, cb)
    local b = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = CONFIG.accent,
        BackgroundTransparency = 0.88, BorderSizePixel = 0, AutoButtonColor = true,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = CONFIG.text, Text = name,
    }, parent)
    corner(b, 8)
    stroke(b, CONFIG.accent, 1, 0.6)
    b.MouseButton1Click:Connect(function()
        local ok, err = pcall(cb)
        if not ok then notif(tostring(err), "erro") end
    end)
    return b
end

local function esprow(parent, cat, name)
    local wrap = mk("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1 }, parent)
    local top = mk("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, wrap)
    local sw = mk("TextButton", {
        Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(0, 5),
        BackgroundColor3 = PALETTE[CFG["esp.cold." .. cat] or 1], BorderSizePixel = 0, Text = "",
    }, top)
    corner(sw, 4)
    mk("TextLabel", {
        Size = UDim2.new(1, -80, 1, 0), Position = UDim2.fromOffset(24, 0), BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = CONFIG.text,
        TextXAlignment = Enum.TextXAlignment.Left, Text = name, Parent = top,
    })
    sw.MouseButton1Click:Connect(function()
        local i = (CFG["esp.cold." .. cat] or 1) % #PALETTE + 1
        setCfg("esp.cold." .. cat, i)
        sw.BackgroundColor3 = PALETTE[i]
    end)

    local tr = mk("Frame", { Size = UDim2.fromOffset(38, 22), Position = UDim2.new(1, -38, 0, 2), BackgroundColor3 = Color3.fromRGB(48, 52, 62), BorderSizePixel = 0 }, top)
    corner(tr, 11)
    local kn = mk("Frame", { Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = CONFIG.text, BorderSizePixel = 0 }, tr)
    corner(kn, 8)
    local tb = mk("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" }, tr)
    local function paint()
        local on = CFG["esp.cat." .. cat] == true
        tr.BackgroundColor3 = on and CONFIG.accent or Color3.fromRGB(48, 52, 62)
        TweenService:Create(kn, TweenInfo.new(0.12), { Position = on and UDim2.fromOffset(19, 3) or UDim2.fromOffset(3, 3) }):Play()
    end
    paint()
    tb.MouseButton1Click:Connect(function()
        setCfg("esp.cat." .. cat, not CFG["esp.cat." .. cat])
        paint()
    end)
    slider(wrap, "esp.dist." .. cat, "Alcance", 20, 500, 5)
    return wrap
end

local function buildTab(tabId)
    if UI.body then UI.body:Destroy() end
    local sc = mk("ScrollingFrame", {
        Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = CONFIG.accentDim,
        CanvasSize = UDim2.new(0, 0, 0, 0), ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = UI.panel,
    }, nil)
    sc.Parent = UI.panelBodyHolder
    UI.body = sc

    local layout = mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, sc)
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        sc.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
    end)

    for _, tab in ipairs(DEFS) do
        if tab.id == tabId then
            for _, it in ipairs(tab.items) do
                if it.t == "sec" then section(sc, it.name)
                elseif it.t == "toggle" then toggle(sc, it.id, it.name)
                elseif it.t == "slider" then slider(sc, it.id, it.name, it.min, it.max, it.step)
                elseif it.t == "esprow" then esprow(sc, it.cat, it.name)
                elseif it.t == "button" then button(sc, it.id, it.name, function() ACTIONS[it.id]() end)
                elseif it.t == "label" then
                    local l = mk("TextLabel", {
                        Size = UDim2.new(1, 0, 0, 60), BackgroundColor3 = Color3.fromRGB(26, 29, 37),
                        BackgroundTransparency = 0.2, BorderSizePixel = 0, Font = Enum.Font.Code,
                        TextSize = 11, TextColor3 = CONFIG.textDim, TextWrapped = true,
                        TextXAlignment = Enum.TextXAlignment.Left, Text = "—", Parent = sc,
                    })
                    corner(l, 6)
                    STATS_LABEL = l
                end
            end
        end
    end
end

function UI.mount()
    UI.root = mk("ScreenGui", {
        Name = "NightsHub", ResetOnSpawn = false, IgnoreGuiInset = true,
        DisplayOrder = 99999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = plrGui,
    })
    notifHolder = mk("Frame", { Size = UDim2.new(0.9, 0, 0, 130), Position = UDim2.new(0.05, 0, 0.06, 0), BackgroundTransparency = 1 }, UI.root)

    local vp = cam.ViewportSize
    local w = math.min(vp.X * 0.92, 420)
    local h = math.min(vp.Y * 0.68, 620)

    UI.panel = mk("Frame", {
        Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset((vp.X - w) / 2, 90),
        BackgroundColor3 = CONFIG.bg, BackgroundTransparency = 0.06, BorderSizePixel = 0,
        ClipsDescendants = true, Parent = UI.root,
    })
    corner(UI.panel, 14)
    stroke(UI.panel, CONFIG.accent, 1, 0.55)

    local glow = mk("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, CONFIG.accent), ColorSequenceKeypoint.new(1, CONFIG.accentDim),
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1),
        }),
        Rotation = 90,
    }, UI.panel)

    -- HEADER
    local header = mk("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = CONFIG.bgPanel, BackgroundTransparency = 0.15, BorderSizePixel = 0, Parent = UI.panel })
    local hg = mk("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 26, 34)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 16, 22)),
        }), Rotation = 0,
    }, header)
    divider(header)

    mk("TextLabel", {
        Size = UDim2.new(1, -110, 0, 16), Position = UDim2.fromOffset(12, 8), BackgroundTransparency = 1,
        Font = Enum.Font.Code, TextSize = 15, TextColor3 = CONFIG.accent,
        TextXAlignment = Enum.TextXAlignment.Left, Text = "NIGHTS_HUB", Parent = header,
    })
    local pill = mk("Frame", { Size = UDim2.fromOffset(42, 15), Position = UDim2.new(1, -100, 0, 9), BackgroundColor3 = CONFIG.accent, BackgroundTransparency = 0.8, BorderSizePixel = 0 }, header)
    corner(pill, 7)
    mk("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 9, TextColor3 = CONFIG.accent, Text = "v" .. CONFIG.versao, Parent = pill })
    mk("TextLabel", {
        Size = UDim2.new(1, -110, 0, 14), Position = UDim2.fromOffset(12, 26), BackgroundTransparency = 1,
        Font = Enum.Font.Code, TextSize = 10, TextColor3 = CONFIG.textDim,
        TextXAlignment = Enum.TextXAlignment.Left, Text = "99 NIGHTS // DELTA", Parent = header,
    })

    local closeBtn = mk("TextButton", { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -34, 0, 13), BackgroundColor3 = Color3.fromRGB(40, 44, 54), BorderSizePixel = 0, Font = Enum.Font.Code, TextSize = 14, TextColor3 = CONFIG.text, Text = "X" }, header)
    corner(closeBtn, 6)
    closeBtn.MouseButton1Click:Connect(function()
        UI.panel.Visible = false
        UI.bubble.Visible = true
        save()
    end)

    local minBtn = mk("TextButton", { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -64, 0, 13), BackgroundColor3 = Color3.fromRGB(40, 44, 54), BorderSizePixel = 0, Font = Enum.Font.Code, TextSize = 14, TextColor3 = CONFIG.text, Text = "-" }, header)
    corner(minBtn, 6)
    minBtn.MouseButton1Click:Connect(function()
        UI.panel.Visible = false
        UI.bubble.Visible = true
    end)

    -- TABS
    local tabs = mk("ScrollingFrame", { Size = UDim2.new(1, 0, 0, 42), Position = UDim2.fromOffset(0, 52), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0, ScrollingDirection = Enum.ScrollingDirection.X, CanvasSize = UDim2.new(0, 0, 0, 0), Parent = UI.panel })
    local tl = mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
    tl:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        tabs.CanvasSize = UDim2.new(0, tl.AbsoluteContentSize.X + 16, 0, 0)
    end)

    for _, tab in ipairs(DEFS) do
        local b = mk("TextButton", {
            Size = UDim2.fromOffset(58, 34), BackgroundColor3 = Color3.fromRGB(26, 29, 37),
            BackgroundTransparency = 0.35, BorderSizePixel = 0, Font = Enum.Font.Code,
            TextSize = 10, TextColor3 = CONFIG.textDim, Text = tab.code,
        }, tabs)
        corner(b, 7)
        local ul = mk("Frame", { Size = UDim2.new(1, -12, 0, 2), Position = UDim2.new(0, 6, 1, -4), BackgroundColor3 = CONFIG.accent, BackgroundTransparency = 1, BorderSizePixel = 0 }, b)
        UI.tabBtns[tab.id] = { btn = b, ul = ul }
        b.MouseButton1Click:Connect(function()
            for _, e in pairs(UI.tabBtns) do
                e.btn.TextColor3 = CONFIG.textDim
                e.btn.BackgroundColor3 = Color3.fromRGB(26, 29, 37)
                e.ul.BackgroundTransparency = 1
            end
            b.TextColor3 = CONFIG.accent
            b.BackgroundColor3 = Color3.fromRGB(22, 34, 40)
            ul.BackgroundTransparency = 0
            UI.current = tab.id
            buildTab(tab.id)
        end)
    end

    UI.panelBodyHolder = mk("Frame", { Size = UDim2.new(1, 0, 1, -144), Position = UDim2.fromOffset(0, 96), BackgroundTransparency = 1, ClipsDescendants = true }, UI.panel)

    -- FOOTER
    local footer = mk("Frame", { Size = UDim2.new(1, 0, 0, 48), Position = UDim2.new(0, 0, 1, -48), BackgroundColor3 = CONFIG.bgPanel, BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = UI.panel })
    local dot = mk("Frame", { Size = UDim2.fromOffset(7, 7), Position = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.fromRGB(80, 255, 120), BorderSizePixel = 0 }, footer)
    corner(dot, 4)
    mk("TextLabel", { Size = UDim2.new(0.5, 0, 0, 14), Position = UDim2.fromOffset(24, 8), BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 10, TextColor3 = CONFIG.textDim, TextXAlignment = Enum.TextXAlignment.Left, Text = "ONLINE", Parent = footer })

    local panic = mk("TextButton", { Size = UDim2.new(1, -24, 0, 26), Position = UDim2.fromOffset(12, 24), BackgroundColor3 = CONFIG.danger, BackgroundTransparency = 0.82, BorderSizePixel = 0, Font = Enum.Font.Code, TextSize = 11, TextColor3 = Color3.fromRGB(255, 190, 190), Text = "PANICO" }, footer)
    corner(panic, 6)
    panic.MouseButton1Click:Connect(function() ACTIONS["sys.panic"]() end)

    -- BUBBLE
    UI.bubble = mk("Frame", { Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(vp.X - 72, vp.Y - 150), BackgroundColor3 = CONFIG.bgPanel, BorderSizePixel = 0, Visible = false, Parent = UI.root })
    corner(UI.bubble, 26)
    stroke(UI.bubble, CONFIG.accent, 1, 0.3)
    mk("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 16, TextColor3 = CONFIG.accent, Text = "NH", Parent = UI.bubble })

    local bubbleBtn = mk("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" }, UI.bubble)
    bubbleBtn.MouseButton1Click:Connect(function()
        UI.bubble.Visible = false
        UI.panel.Visible = true
    end)

    -- DRAG
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = i.Position
            startPos = UI.panel.Position
        end
    end)
    conn(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            UI.panel.Position = UDim2.fromOffset(startPos.X.Offset + d.X, startPos.Y.Offset + d.Y)
        end
    end)
    conn(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                save()
            end
        end
    end)

    local bdrag, bstart, bpos
    UI.bubble.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch then
            bdrag = true bstart = i.Position bpos = UI.bubble.Position
        end
    end)
    conn(UIS.InputChanged, function(i)
        if bdrag and i.UserInputType == Enum.UserInputType.Touch then
            local d = i.Position - bstart
            UI.bubble.Position = UDim2.fromOffset(bpos.X.Offset + d.X, bpos.Y.Offset + d.Y)
        end
    end)
    conn(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.Touch then bdrag = false end
    end)

    buildTab("farm")
    UI.current = "farm"
    local first = UI.tabBtns["farm"]
    if first then first.btn.TextColor3 = CONFIG.accent first.ul.BackgroundTransparency = 0 end
end

---------------------------------------------------------------------
-- ESP
---------------------------------------------------------------------
local Esp = { pool = {}, active = {}, nextScan = 0 }

local function grab(kind)
    for _, d in ipairs(Esp.pool) do
        if d.kind == kind and not d.used then d.used = true return d end
    end
    local obj
    if kind == "box" then
        obj = Drawing.new("Square") obj.Thickness = 1 obj.Filled = false
    elseif kind == "text" then
        obj = Drawing.new("Text") obj.Size = 13 obj.Center = true obj.Outline = true
    elseif kind == "line" then
        obj = Drawing.new("Line") obj.Thickness = 1
    end
    if obj then
        local rec = { kind = kind, obj = obj, used = true }
        table.insert(Esp.pool, rec)
        return rec
    end
end

local function releaseAll()
    for _, d in ipairs(Esp.pool) do
        d.used = false
        if d.obj then pcall(function() d.obj.Visible = false end) end
    end
end

local function espScan()
    Esp.active = {}
    local p = hrp()
    if not p then return end
    local total = 0
    for cat in pairs(CATS) do
        if CFG["esp.cat." .. cat] then
            local radius = math.min(CFG["esp.dist." .. cat] or 150, 600)
            for _, e in ipairs(findCat(cat, radius)) do
                if total >= CONFIG.maxEsp then break end
                e.cat = cat
                table.insert(Esp.active, e)
                total += 1
            end
        end
    end
end

local function espDraw()
    releaseAll()
    if not (CFG["esp.on"] and CFG["esp.box"] ~= nil) then return end
    local p = hrp()
    if not p then return end
    local vp = cam.ViewportSize

    for _, e in ipairs(Esp.active) do
        local pos = e.pos
        if pos then
            local sp, on = cam:WorldToViewportPoint(pos)
            if on and sp.Z > 0 then
                local ok, size = pcall(function() return e.obj:GetExtentsSize() end)
                local hh = ok and math.clamp((size.Y * 900) / sp.Z, 14, 400) or 40
                local ww = hh * 0.55
                local col = PALETTE[CFG["esp.cold." .. e.cat] or 1]

                if CFG["esp.box"] then
                    local b = grab("box")
                    if b then
                        b.obj.Color = col
                        b.obj.Size = Vector2.new(ww, hh)
                        b.obj.Position = Vector2.new(sp.X - ww / 2, sp.Y - hh / 2)
                        b.obj.Visible = true
                    end
                end
                if CFG["esp.name"] then
                    local t = grab("text")
                    if t then
                        t.obj.Color = col
                        t.obj.Text = e.obj.Name
                        t.obj.Position = Vector2.new(sp.X, sp.Y - hh / 2 - 14)
                        t.obj.Visible = true
                    end
                end
                if CFG["esp.dist"] then
                    local t = grab("text")
                    if t then
                        t.obj.Color = col
                        t.obj.Text = math.floor(e.dist) .. "m"
                        t.obj.Position = Vector2.new(sp.X, sp.Y + hh / 2 + 4)
                        t.obj.Visible = true
                    end
                end
                if CFG["esp.tracer"] then
                    local l = grab("line")
                    if l then
                        l.obj.Color = col
                        l.obj.From = Vector2.new(vp.X / 2, vp.Y)
                        l.obj.To = Vector2.new(sp.X, sp.Y + hh / 2)
                        l.obj.Visible = true
                    end
                end
            end
        end
    end
end

SCHED.add("esp.scan", 0.4, function()
    if CFG["esp.on"] and not CFG["sys.discrete"] then espScan() else Esp.active = {} end
end)
SCHED.add("esp.draw", 0.08, function()
    if CFG["esp.on"] then espDraw() else releaseAll() end
end, 0.02)

---------------------------------------------------------------------
-- COMBATE
---------------------------------------------------------------------
local Combat = { cd = {} }

function Combat.hit(mob, dmg)
    local h = mob:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return end
    local t = os.clock()
    if Combat.cd[mob] and t - Combat.cd[mob] < 0.25 then return end
    Combat.cd[mob] = t

    local fired = false
    for i = 1, math.min(3, #Bridge.remotes) do
        local r = Bridge.remotes[i].obj
        if pcall(function() Bridge.fire(r, mob) end) then fired = true end
        if pcall(function() Bridge.fire(r, h) end) then fired = true end
        if pcall(function() Bridge.fire(r, mob, 25) end) then fired = true end
    end
    if CFG["combat.autoEquip"] then
        equipTool("sword") or equipTool("axe") or equipTool("club") or equipTool("knife")
    end
    activatedTool()
    pcall(function() h:TakeDamage(20) end)
end

SCHED.add("combat.aura", 0.12, function()
    if not CFG["combat.aura"] then return end
    if os.clock() - Bridge.lastScan > 30 then Bridge.rescan() end
    local p = hrp()
    if not p then return end
    local radius = CFG["combat.auraDist"]
    local targets = {}
    for _, cat in ipairs({ "wolf", "alpha", "bear", "cultist", "deer" }) do
        if CFG["combat.mob." .. cat] then
            for _, e in ipairs(findCat(cat, radius)) do table.insert(targets, e) end
        end
    end
    table.sort(targets, function(a, b) return a.dist < b.dist end)
    local max = math.floor(CFG["combat.auraTargets"])
    local delay = CFG["combat.auraDelay"]
    for i = 1, math.min(max, #targets) do
        local t = targets[i]
        if CFG["combat.approach"] and t.dist > 12 then approach(t.obj, 6) end
        Combat.hit(t.obj, 25)
        if i < max then task.wait(delay) end
    end
end, 0.1)

SCHED.add("combat.tree", 0.35, function()
    if not CFG["combat.tree"] then return end
    local trees = findCat("tree", CFG["combat.treeDist"])
    local n = 0
    for _, t in ipairs(trees) do
        if n >= 3 then break end
        if CFG["combat.treeDrop"] then
            local ok, size = pcall(function() return t.obj:GetExtentsSize() end)
            if ok and size.Y < 4 then continue end
        end
        equipTool("axe")
        if CFG["combat.treeApproach"] and t.dist > 8 then approach(t.obj, 5) end
        activatedTool()
        n += 1
        task.wait(0.12)
    end
end)

conn(UIS.InputBegan, function(i, gp)
    if not CFG["combat.silentAim"] then return end
    if gp then return end
    if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    local p = hrp()
    if not p then return end
    local best, bd = nil, 1e9
    for _, cat in ipairs({ "wolf", "alpha", "bear", "cultist" }) do
        if CFG["combat.mob." .. cat] then
            for _, e in ipairs(findCat(cat, 200)) do
                if e.dist < bd then best, bd = e, e.dist end
            end
        end
    end
    if best then
        local sp = cam:WorldToViewportPoint(best.pos)
        VIM:SendMouseMove(sp.X, sp.Y)
    end
end)

---------------------------------------------------------------------
-- MOVIMENTO
---------------------------------------------------------------------
SCHED.add("mov.apply", 0.5, function()
    local h = hum()
    if not h then return end
    if CFG["mov.speedOn"] then h.WalkSpeed = CFG["mov.speed"] else h.WalkSpeed = 16 end
    if CFG["mov.jumpOn"] then
        pcall(function() h.JumpPower = CFG["mov.jump"] end)
        pcall(function() h.UseJumpPower = true end)
    end
    if CFG["mov.stamina"] then
        for _, v in ipairs(plr:GetChildren()) do
            if v:IsA("NumberValue") and v.Name:lower():find("stamina") then v.Value = 1e6 end
        end
        local c = char()
        if c then
            for _, v in ipairs(c:GetChildren()) do
                if v:IsA("NumberValue") and v.Name:lower():find("stamina") then v.Value = 1e6 end
            end
        end
    end
end)

local flyBV, flyBG
SCHED.add("mov.fly", 0.05, function()
    local p = hrp()
    if not p then return end
    if CFG["mov.fly"] then
        local h = hum()
        if not flyBV then
            flyBV = Instance.new("BodyVelocity")
            flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            flyBV.Parent = p
        end
        local dir = h and h.MoveDirection or Vector3.zero
        flyBV.Velocity = dir * CFG["mov.flySpeed"] + Vector3.new(0, (dir.Magnitude < 0.1 and 0) or 0, 0)
        pcall(function() p.AssemblyLinearVelocity = dir * CFG["mov.flySpeed"] end)
    else
        if flyBV then flyBV:Destroy() flyBV = nil end
    end
end, 0.02)

SCHED.add("mov.noclip", 0.25, function()
    local c = char()
    if not c then return end
    for _, d in ipairs(c:GetDescendants()) do
        if d:IsA("BasePart") then
            if CFG["mov.noclip"] then d.CanCollide = false
            elseif d.Name ~= "HumanoidRootPart" then d.CanCollide = true end
        end
    end
end)

SCHED.add("mov.antifall", 1, function()
    if not CFG["mov.antifall"] then return end
    local p = hrp()
    if p and p.Position.Y < -60 then
        local camp = Workspace:FindFirstChild("Campfire") or Workspace:FindFirstChild("SpawnLocation")
        if camp then
            pcall(function() p.CFrame = CFrame.new(camp:GetPivot().Position + Vector3.new(0, 5, 0)) end)
        else
            pcall(function() p.CFrame = CFrame.new(0, 100, 0) end)
        end
        notif("Anti-Fall ativado")
    end
end)

SCHED.add("mov.antiafk", 20, function()
    if CFG["mov.antiafk"] then pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game) VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end) end
end)

---------------------------------------------------------------------
-- FARM
---------------------------------------------------------------------
local Farm = { q = {} }

local FARM_MAP = {
    { id = "farm.wood", cat = "tree", dist = "farm.woodDist" },
    { id = "farm.fruit", cat = "item", dist = "farm.fruitDist", word = "fruit" },
    { id = "farm.scrap", cat = "item", dist = "farm.scrapDist", word = "scrap" },
    { id = "farm.stone", cat = "poi", dist = "farm.lootDist", word = "stone" },
    { id = "farm.loot", cat = "item", dist = "farm.lootDist" },
    { id = "farm.chest", cat = "chest", dist = "farm.chestDist" },
    { id = "farm.badge", cat = "item", dist = "farm.lootDist", word = "badge" },
}

SCHED.add("farm.run", 0.3, function()
    for _, m in ipairs(FARM_MAP) do
        if CFG[m.id] then
            local list = findCat(m.cat, CFG[m.dist] or 40)
            for _, e in ipairs(list) do
                if m.word and not e.obj.Name:lower():find(m.word, 1, true) then continue end
                if CFG["farm.tp"] and e.dist > 8 then tpSilent(e.pos) task.wait(0.08) end
                activatedTool()
                Bridge.broadcast(2, e.obj)
                break
            end
        end
    end
end)

local function findCampfire()
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("Model") and d.Name:lower():find("campfire", 1, true) then return d end
    end
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("Model") and d.Name:lower():find("fire", 1, true) then return d end
    end
end

SCHED.add("camp.work", 0.8, function()
    if not (CFG["camp.fuel"] or CFG["camp.upgrade"]) then return end
    local f = findCampfire()
    if not f then return end
    local ok, pos = pcall(function() return f:GetPivot().Position end)
    if not ok then return end
    if distTo(pos) > 10 then approach(f, 6) task.wait(0.1) end
    if CFG["camp.fuel"] then Bridge.broadcast(2, f) activatedTool() end
    if CFG["camp.upgrade"] then Bridge.broadcast(3, f, "upgrade") end
    task.wait(CFG["camp.interval"])
end)

---------------------------------------------------------------------
-- REVELAR MAPA
---------------------------------------------------------------------
local revealStore = {}
SCHED.add("world.reveal", 1.2, function()
    if not CFG["world.reveal"] then return end
    pcall(function()
        Lighting.FogEnd = 1e6
        Lighting.FogStart = 0
        local at = Lighting:FindFirstChildOfClass("Atmosphere")
        if at then at.Density = 0 end
    end)
    for _, d in ipairs(Workspace:GetDescendants()) do
        local n = d.Name:lower()
        if (n:find("fog") or n:find("mist")) and d:IsA("BasePart") then
            revealStore[d] = d.LocalTransparencyModifier
            d.LocalTransparencyModifier = 1
            if CFG["world.wallpass"] then d.CanCollide = false end
        end
    end
end)

---------------------------------------------------------------------
-- TELEPORTE
---------------------------------------------------------------------
local tpPoint

local function doTp(pos)
    if not pos then return notif("Destino nao encontrado", "erro") end
    if CFG["world.silent"] then
        tpSilent(pos)
    else
        local p = hrp()
        if p then
            local t = TweenService:Create(p, TweenInfo.new(0.4), { CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) })
            t:Play()
        end
    end
end

local function firstOf(cat)
    local l = findCat(cat, 5000)
    return l[1] and l[1].pos
end

ACTIONS = {}

ACTIONS["tp.save"] = function() tpPoint = hrp() and hrp().Position notif("Ponto salvo") end
ACTIONS["tp.back"] = function() doTp(tpPoint) end
ACTIONS["tp.camp"] = function() doTp(firstOf("poi")) end
ACTIONS["tp.fire"] = function()
    local f = findCampfire()
    if f then doTp(f:GetPivot().Position) end
end
ACTIONS["tp.kid"] = function() doTp(firstOf("kid")) end
ACTIONS["tp.trader"] = function() doTp(firstOf("trader")) end
ACTIONS["tp.strong"] = function() doTp(firstOf("poi")) end
ACTIONS["tp.cave"] = function() doTp(firstOf("cave")) end
ACTIONS["tp.chest"] = function() doTp(firstOf("chest")) end
ACTIONS["tp.poi"] = function() doTp(firstOf("poi")) end

---------------------------------------------------------------------
-- ITENS
---------------------------------------------------------------------
SCHED.add("item.bring", 0.4, function()
    if not CFG["item.bring"] then return end
    local p = hrp()
    if not p then return end
    for _, e in ipairs(findCat("item", CFG["item.bringDist"])) do
        pcall(function()
            e.obj:PivotTo(CFrame.new(p.Position + p.CFrame.LookVector * 4 + Vector3.new(0, 1, 0)))
        end)
        break
    end
end)

ACTIONS["item.bringAll"] = function()
    local p = hrp()
    if not p then return end
    local n = 0
    for _, e in ipairs(findCat("item", CFG["item.bringDist"])) do
        pcall(function() e.obj:PivotTo(CFrame.new(p.Position + Vector3.new(0, 2, 0) + Vector3.new(math.random(-4, 4), 0, math.random(-4, 4)))) end)
        n += 1
    end
    notif(n .. " itens trazidos")
end

SCHED.add("item.eat", 1, function()
    local h = hum()
    if not h then return end
    if CFG["item.autoEat"] and h.Health / h.MaxHealth * 100 < CFG["item.eatAt"] then
        equipTool("food") or equipTool("berry") or equipTool("meat")
        activatedTool()
    end
    if CFG["item.autoHeal"] and h.Health < h.MaxHealth * 0.5 then
        equipTool("bandage") or equipTool("medkit") or equipTool("herb")
        activatedTool()
    end
    if CFG["item.autoRepair"] then
        equipTool("repair")
        activatedTool()
    end
end)

---------------------------------------------------------------------
-- SISTEMA
---------------------------------------------------------------------
local stats = { kills = 0, t0 = os.clock() }

ACTIONS["sys.panic"] = function()
    for k in pairs(CFG) do
        if type(CFG[k]) == "boolean" then CFG[k] = false end
    end
    releaseAll()
    local h = hum()
    if h then h.WalkSpeed = 16 pcall(function() h.JumpPower = 50 end) end
    pcall(function() if flyBV then flyBV:Destroy() flyBV = nil end end)
    pcall(function()
        Lighting.FogEnd = 1000
        for d, v in pairs(revealStore) do if d.Parent then d.LocalTransparencyModifier = v end end
    end)
    if UI.body then buildTab(UI.current or "farm") end
    notif("Tudo desligado")
end

ACTIONS["sys.save"] = function() save() notif("Config salva") end
ACTIONS["sys.load"] = function() load() if UI.body then buildTab(UI.current or "farm") end notif("Config carregada") end
ACTIONS["sys.reset"] = function()
    if writefile and isfile then pcall(function() delfile(CONFIG.savePath) end) end
    notif("Resetado, rejunte")
end

ACTIONS["sys.remotes"] = function()
    Bridge.rescan()
    local lines = {}
    for i = 1, math.min(12, #Bridge.remotes) do
        table.insert(lines, ("%d. %s"):format(i, Bridge.remotes[i].obj:GetFullName()))
    end
    notif(#Bridge.remotes .. " remotes encontrados")
    if setclipboard then setclipboard(table.concat(lines, "\n")) end
end

ACTIONS["sys.dump"] = function()
    local lines = { "NIGHTS HUB v" .. CONFIG.versao, "exec: " .. tostring(identifyexecutor and identifyexecutor()) }
    for k, v in pairs(CFG) do
        if type(CFG[k]) ~= "table" then table.insert(lines, k .. " = " .. tostring(v)) end
    end
    for _, l in ipairs(LOG.buf) do table.insert(lines, l) end
    if setclipboard then setclipboard(table.concat(lines, "\n")) notif("Dump copiado") end
end

ACTIONS["sys.unload"] = function() NH.destroy() end

SCHED.add("sys.stats", 1, function()
    if not STATS_LABEL then return end
    local t = math.floor(os.clock() - stats.t0)
    STATS_LABEL.Text = ("tempo %02d:%02d\nremotes %d\nesp %d\nstatus %s"):format(
        math.floor(t / 60), t % 60, #Bridge.remotes, #Esp.active,
        (#Bridge.remotes > 0 and "ok") or "sem remote"
    )
end)

SCHED.add("sys.discrete", 1, function()
    local h = hum()
    if not h then return end
    if CFG["sys.discrete"] and CFG["mov.speedOn"] then h.WalkSpeed = math.min(CFG["mov.speed"], 45) end
end)

---------------------------------------------------------------------
-- WATCHDOG
---------------------------------------------------------------------
conn(plr.CharacterAdded, function(c)
    c:WaitForChild("Humanoid")
    task.wait(0.5)
    if CFG["mov.speedOn"] then pcall(function() c.Humanoid.WalkSpeed = CFG["mov.speed"] end) end
    if CFG["mov.jumpOn"] then pcall(function() c.Humanoid.JumpPower = CFG["mov.jump"] end) end
    stats.kills += 0
    notif("Personagem reaplicado")
end)

conn(Workspace, "ChildRemoved", function(o) end)

---------------------------------------------------------------------
-- DESTROY
---------------------------------------------------------------------
function NH.destroy()
    NH.alive = false
    for _, c in ipairs(NH.conns) do pcall(function() c:Disconnect() end) end
    for _, d in ipairs(Esp.pool) do pcall(function() d.obj:Remove() end) end
    pcall(function() if flyBV then flyBV:Destroy() end end)
    pcall(function() if UI.root then UI.root:Destroy() end end)
    getgenv().NightsHub = nil
    pcall(function() warn("[NightsHub] descarregado") end)
end

---------------------------------------------------------------------
-- BOOT
---------------------------------------------------------------------
if not Drawing then notif("Executor sem Drawing, ESP limitado", "erro") end

UI.mount()
load()
Bridge.rescan()
notif("Nights Hub v" .. CONFIG.versao .. " pronto")
log("info", "boot ok")