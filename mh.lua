-- ── SINGLE INSTANCE ──────────────────────────────────────────────────
-- Re-running used to stack a second copy of every loop and ore worker on
-- top of the first. Kill the previous copy before anything loads.
if type(_G.DeepveinKill) == "function" then
    pcall(_G.DeepveinKill)
end
_G.DeepveinKill = nil
_G.DeepveinGen = (_G.DeepveinGen or 0) + 1


local cloneref = (cloneref or clonereference or function(i) return i end)
local Players    = cloneref(game:GetService("Players"))
local RS         = cloneref(game:GetService("ReplicatedStorage"))
local RunService = cloneref(game:GetService("RunService"))

local lp      = Players.LocalPlayer
local MoneyLib = require(RS.Modules.Game.MoneyLib)

-- ── remotes moved into Modules.Networking.Net (Jolt channels) ────────
Net = require(RS.Modules.Networking.Net)
LayoutsRemote = (function()
    local r = RS:WaitForChild("Remotes", 5)
    local p = r and r:FindFirstChild("Placement")
    return p and p:FindFirstChild("Layouts") or nil
end)()
local ChannelCache = {}
function Channel(name)
    local hit = ChannelCache[name]
    if hit then return hit end
    local c = Net[name]
    if not c then
        return {
            InvokeServer = function() return nil end,
            FireServer   = function() end,
            OnClientEvent = { Connect = function() end },
        }
    end
    hit = {
        InvokeServer = function(_, ...) return c:Invoke(...) end,
        FireServer   = function(_, ...) return c:Fire(...) end,
        OnClientEvent = { Connect = function(_, fn) return c:Connect(fn) end },
    }
    ChannelCache[name] = hit
    return hit
end

-- ══════════════════════════════════════════════════════════════════════
--  DEEPVEIN · Miner's Haven automation
--  UI: Halcyon
-- ══════════════════════════════════════════════════════════════════════
local Halcyon = loadstring(game:HttpGet("https://raw.githubusercontent.com/astrawtf/Halcyon/refs/heads/main/halcyon.lua"))()


-- ── REMOTE RESOLVER ───────────────────────────────────────────────────
-- Remotes keep moving between ReplicatedStorage and Net. A missing one used
-- to be a silent no-op (Channel stub) or an infinite WaitForChild yield, which
-- froze the whole auto-rebirth thread. Resolve by exact name, any casing, then
-- fall back to the Instance. Nothing is ever invoked on a fuzzy match.
local ResolveCache = {}
function resolveNet(key, names)
    local hit = ResolveCache[key]
    if hit then return hit.ch, hit.name end
    for _, n in ipairs(names) do
        local ok, c = pcall(function() return Net[n] end)
        if ok and c ~= nil and type(c) ~= "function" then
            ResolveCache[key] = { ch = c, name = n }
            return c, n
        end
    end
    local want = {}
    for _, n in ipairs(names) do want[n:lower()] = true end
    pcall(function()
        for k, v in pairs(Net) do
            if type(k) == "string" and want[k:lower()] and type(v) ~= "function" and v ~= nil then
                ResolveCache[key] = { ch = v, name = k }
                return
            end
        end
    end)
    hit = ResolveCache[key]
    if hit then return hit.ch, hit.name end
    return nil
end

function findRemoteInstance(names)
    for _, n in ipairs(names) do
        local inst = RS:FindFirstChild(n)
        if inst and (inst:IsA("RemoteFunction") or inst:IsA("RemoteEvent")) then return inst end
    end
    local remotes = RS:FindFirstChild("Remotes")
    if remotes then
        for _, n in ipairs(names) do
            local inst = remotes:FindFirstChild(n, true)
            if inst and (inst:IsA("RemoteFunction") or inst:IsA("RemoteEvent")) then return inst end
        end
    end
    return nil
end

function invokeRemote(ch, ...)
    if typeof(ch) == "Instance" then
        if ch:IsA("RemoteFunction") then return ch:InvokeServer(...) end
        return ch:FireServer(...)
    end
    if type(ch.Invoke) == "function" then return ch:Invoke(...) end
    return ch:Fire(...)
end

-- Runs fn off-thread and gives up after `timeout`, so a remote with no server
-- handler can never hang the caller.
function callWithTimeout(timeout, fn, ...)
    local args = table.pack(...)
    local done, ok, res = false, false, nil
    local th = task.spawn(function()
        ok, res = pcall(fn, table.unpack(args, 1, args.n))
        done = true
    end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < timeout do task.wait() end
    if not done then pcall(task.cancel, th); return false, "timeout" end
    return ok, res
end

function netKeysLike(...)
    local pats, out = { ... }, {}
    pcall(function()
        for k in pairs(Net) do
            if type(k) == "string" then
                local lk = k:lower()
                for _, p in ipairs(pats) do
                    if lk:find(p, 1, true) then out[#out + 1] = k; break end
                end
            end
        end
    end)
    table.sort(out)
    return out
end

REBIRTH_NAMES = { "Rebirth", "Reborn", "DoRebirth", "RebirthRequest", "PerformRebirth", "RequestRebirth" }
LAYOUT_NAMES  = { "Layouts", "Layout", "LayoutAction", "LayoutRemote" }
ACTION_NAMES  = { "processAction", "ProcessAction" }

function callRebirth()
    local ch, name = resolveNet("rebirth", REBIRTH_NAMES)
    if ch then
        local ok = callWithTimeout(6, invokeRemote, ch)
        if ok then return true, "Net." .. tostring(name) end
    end
    local inst = findRemoteInstance(REBIRTH_NAMES)
    if inst then
        local ok = callWithTimeout(6, invokeRemote, inst)
        if ok then return true, "RS." .. inst.Name end
    end
    return false
end

function callProcessAction(...)
    local ch = resolveNet("action", ACTION_NAMES)
    if ch and callWithTimeout(4, invokeRemote, ch, ...) then return true end
    local inst = findRemoteInstance(ACTION_NAMES)
    if inst and callWithTimeout(4, invokeRemote, inst, ...) then return true end
    return false
end

function callLayouts(...)
    local ch = resolveNet("layouts", LAYOUT_NAMES)
    if ch and callWithTimeout(6, invokeRemote, ch, ...) then return true end
    if LayoutsRemote and callWithTimeout(6, invokeRemote, LayoutsRemote, ...) then return true end
    return false
end

function layoutRemoteExists()
    return resolveNet("layouts", LAYOUT_NAMES) ~= nil or LayoutsRemote ~= nil
end

-- Themes: named after real materials and pigments, not marketing words.
local THEMES = {
    Basalt    = { Bg="0d0d0e", Card="141416", Raised="1d1d20", Field="101012", Line="242427", Border="33333a", Text="f2f2f3", Sub="a1a1a8", Muted="6e6e76", Accent="e8e6e1", OnAccent="0d0d0e", Track="2c2c31" },
    Graphite  = { Bg="101113", Card="17191c", Raised="22252a", Field="121417", Line="262a2f", Border="363b42", Text="eef0f2", Sub="9aa1a9", Muted="6a7178", Accent="9fb4c7", OnAccent="101113", Track="2f343a" },
    Cobalt    = { Bg="0a0e16", Card="101725", Raised="172033", Field="0c111c", Line="1b2436", Border="27334c", Text="e8eefc", Sub="8b9bb8", Muted="5f6f8c", Accent="5b8def", OnAccent="0a0e16", Track="27334c" },
    Verdigris = { Bg="0b1210", Card="111a17", Raised="18251f", Field="0d1512", Line="1d2b25", Border="2a3d34", Text="e9f4ee", Sub="93ac9f", Muted="657d70", Accent="4fbf9f", OnAccent="0b1210", Track="2a3d34" },
    Sandstone = { Bg="f7f4ee", Card="efeae1", Raised="ffffff", Field="f3efe7", Line="e2dbcf", Border="cfc5b4", Text="1c1a16", Sub="5f5a51", Muted="8d867a", Accent="8a6f45", OnAccent="ffffff", Track="d8d0c2" },
    Parchment = { Bg="fbf9f4", Card="f5f1e8", Raised="ffffff", Field="f8f5ee", Line="e7e0d2", Border="d6cbb8", Text="24211b", Sub="665f53", Muted="948b7c", Accent="2f6f5e", OnAccent="ffffff", Track="ded5c6" },
}
for name, colors in pairs(THEMES) do
    Halcyon:AddTheme(name, colors)
end

local UI = { Name = "Deepvein", Version = "1.0", Hue = Halcyon }
UI._config = "default"
UI._visible = true
UI._init = true

function UI:Notify(o)
    if UI._init then return end
    pcall(function()
        Halcyon:Notify({
            Title = o.Title or "Deepvein",
            Text = o.Content or o.Text or "",
            Type = o.Type or "Info",
            Duration = o.Duration or 4,
        })
    end)
end

-- Window / tab adapter: keeps the hub's call style, renders with Halcyon.
function UI:CreateWindow(cfg)
    local win = Halcyon:Window{ Name = cfg.Title or self.Name, Subtitle = cfg.Subtitle or cfg.Version or "" }
    local api = { _win = win }
    self._win = win

    function api:CreateTab(name, icon)
        return UI:_tab(win, name, icon)
    end
    function api:Notify(o) UI:Notify(o) end
    function api:SetToggleKey(k)
        UI._toggleKey = k
    end

    task.spawn(function()
        local UIS = game:GetService("UserInputService")
        UIS.InputBegan:Connect(function(input, processed)
            if processed then return end
            local key = UI._toggleKey or Enum.KeyCode.RightShift
            if input.KeyCode ~= key then return end
            UI._visible = not UI._visible
            pcall(function() win:Show(UI._visible) end)
        end)
    end)

    return api
end

function UI:_tab(win, name, icon)
    local tab = win:Tab{ Name = name, Icon = icon or "circle" }
    local t = { _tab = tab }

    function t:CreateSection(title)
        tab:Section(tostring(title))
        return t
    end
    function t:AddToggle(o)
        tab:Toggle{ Name = o.Name, Default = o.Default == true, Callback = o.Callback }
    end
    function t:AddButton(o)
        tab:Button{ Name = o.Name, Callback = o.Callback }
    end
    function t:AddDropdown(o)
        local d = tab:Dropdown{ Name = o.Name, Options = o.Options, Default = o.Default, Callback = o.Callback }
        return {
            SetOptions = function(_, list)
                if d and type(d.SetOptions) == "function" then pcall(function() d:SetOptions(list) end) end
            end,
        }
    end
    function t:AddMultiDropdown(o)
        local d = tab:MultiDropdown{ Name = o.Name, Options = o.Options, Default = o.Default or {}, Callback = o.Callback }
        return {
            SetOptions = function(_, list)
                if d and type(d.SetOptions) == "function" then pcall(function() d:SetOptions(list) end) end
            end,
        }
    end
    function t:AddSlider(o)
        tab:Slider{ Name = o.Name, Min = o.Min, Max = o.Max, Default = o.Default, Callback = o.Callback }
    end
    function t:AddTextbox(o)
        tab:Input{ Name = o.Name, Default = o.Default or "", Placeholder = o.Placeholder or "", Callback = o.Callback }
    end
    function t:AddKeybind(o)
        tab:Keybind{ Name = o.Name, Default = o.Default, Callback = function(k) if o.Callback then o.Callback(k) end end }
    end
    return t
end

-- Settings tab is built last so it sits at the end of the window.
function UI:Finalize()
    local win = self._win
    UI._init = false
    if not win then return end
    local tab = win:Tab{ Name = "Settings", Icon = "sliders-horizontal" }

    local names = {}
    for n in pairs(Halcyon.Themes) do names[#names + 1] = n end
    table.sort(names)

    tab:Dropdown{ Name = "Theme", Options = names, Default = Halcyon.ThemeName, Callback = function(v) Halcyon:SetTheme(v) end }
    tab:Input{ Name = "Config Name", Default = self._config, Callback = function(v) self._config = (v ~= "" and v) or "default" end }

    tab:Button{ Name = "Save Config", Callback = function()
        Halcyon:Save(self._config)
        UI:Notify{ Title = "Config", Content = "Saved to " .. self._config, Type = "Success" }
    end }
    tab:Button{ Name = "Load Config", Callback = function()
        local ok = Halcyon:Load(self._config)
        UI:Notify{ Title = "Config", Content = ok and ("Loaded " .. self._config) or "No config named " .. self._config, Type = ok and "Success" or "Error" }
    end }
    tab:Button{ Name = "Delete Config", Callback = function()
        Halcyon:Delete(self._config)
        UI:Notify{ Title = "Config", Content = "Deleted " .. self._config, Type = "Info" }
    end }
    tab:Keybind{ Name = "Toggle UI", Default = Enum.KeyCode.RightShift, Callback = function(k) UI._toggleKey = k end }
end



FURNACE_DB = {
    
    ["Basic Furnace"]                  = { Type="Standard",  CashMult=1,                    RPPerOre=0.01,  SellPart="Lava" },
    ["Basic Research Center"]          = { Type="Research",  CashMult=0.25,                 RPPerOre=0.08,  SellPart="Lava" },
    ["Basic Cell Furnace"]             = { Type="Cell",      CashMult=20,                   RPPerOre=0.005, SellPart="Lava", CellOnly=true },
    ["Advanced Furnace"]               = { Type="Standard",  CashMult=1.5,                  RPPerOre=0.013, SellPart="Lava" },
    ["Ore Incinerator"]                = { Type="Standard",  CashMult=3,                    RPPerOre=0.02,  SellPart="Lava" },
    ["Yuge Furnace"]                   = { Type="Standard",  CashMult=10,                   RPPerOre=0.01,  SellPart="Lava" },
    ["Proficient Research Center"]     = { Type="Research",  CashMult=1,                    RPPerOre=0.133, SellPart="Lava", MinOreValue=20 },
    ["Cell Incinerator"]               = { Type="Cell",      CashMult=300,                  RPPerOre=0.01,  SellPart="Lava", CellOnly=true, UnupgradedOnly=true },
    ["Quantum Processor"]              = { Type="Standard",  CashMult=4,                    RPPerOre=0.03,  SellPart="Lava" },
    ["Quantum Research Center"]        = { Type="Research",  CashMult=2,                    RPPerOre=0.2,   SellPart="Lava", MinOreValue=300 },
    ["Cell Processor"]                 = { Type="Cell",      CashMult=1000,                 RPPerOre=0.018, SellPart="Lava", CellOnly=true },
    ["Elevated Furnace"]               = { Type="Standard",  CashMult=5,                    RPPerOre=0.04,  SellPart="Lava" },
    ["Raised Furnace"]                 = { Type="Standard",  CashMult=6,                    RPPerOre=0.025, SellPart="Lava" },
    ["Reinforced Furnace"]             = { Type="Standard",  CashMult=5,                    RPPerOre=0.067, SellPart="Lava" },
    ["Heavenly Forge"]                 = { Type="Standard",  CashMult=6,                    RPPerOre=0.04,  SellPart="Lava" },
    ["Research Center"]                = { Type="Research",  CashMult=3,                    RPPerOre=0.278, SellPart="Lava", MinOreValue=1000 },
    ["Natural Spring"]                 = { Type="Standard",  CashMult=8,                    RPPerOre=0.075, SellPart="Lava" },
    ["Sacrificial Altar"]              = { Type="Standard",  CashMult=10,                   RPPerOre=0.063, SellPart="Lava" },
    ["Sacrificial Cell"]               = { Type="Cell",      CashMult=50000,                RPPerOre=0.018, SellPart="Lava", CellOnly=true },
    ["Electronic Furnace"]             = { Type="Standard",  CashMult=20,                   RPPerOre=0.063, SellPart="Lava" },
    ["The Dream-Maker"]                = { Type="Standard",  CashMult=15,                   RPPerOre=0.075, SellPart="Lava" },
    ["Shrine of Penitence"]            = { Type="Standard",  CashMult=25,                   RPPerOre=0.093, SellPart="Lava" },
    ["Cell Particalizer"]              = { Type="Cell",      CashMult=5000000000000,         RPPerOre=0.16,  SellPart="Lava", CellOnly=true, UnupgradedOnly=true },
    ["The Black Hole"]                 = { Type="Standard",  CashMult=40,                   RPPerOre=0,     SellPart="Lava" },
    ["Cell Collider"]                  = { Type="Cell",      CashMult=120000000000000,       RPPerOre=0.281, SellPart="Lava", CellOnly=true, UnupgradedOnly=true },
    ["Fusion Reactor"]                 = { Type="Research",  CashMult=5,                    RPPerOre=2.0,   SellPart="Lava", MinUpgradeCounter=20 },
    ["Cell Singularity"]               = { Type="Cell",      CashMult=200000000000000,       RPPerOre=0,     SellPart="Lava", CellOnly=true, UnupgradedOnly=true },
    ["Angelic Grace"]                  = { Type="Standard",  CashMult=100,                  RPPerOre=0.133, SellPart="Lava" },
    ["Heart of Dusk"]                  = { Type="Standard",  CashMult=150,                  RPPerOre=0.133, SellPart="Lava" },
    ["Pirate's Loot Collector"]        = { Type="Cell",      CashMult=1500,                 RPPerOre=0,     SellPart="Lava", CellOnly=true },
    ["Frozen Justice"]                 = { Type="Standard",  CashMult=26,                   RPPerOre=0.056, SellPart="Lava" },
    ["Nature's Grip"]                  = { Type="Cell",      CashMult=200000000,             RPPerOre=0.05,  SellPart="Lava", CellOnly=true },
    ["Invasive Cyberlord"]             = { Type="Standard",  CashMult=250,                  RPPerOre=0.65,  SellPart="Lava" },
    ["Dreamer's Might"]                = { Type="Standard",  CashMult=40,                   RPPerOre=0.1,   SellPart="Lava" },
    ["Dreamer's Fright"]               = { Type="Standard",  CashMult=22.5,                 RPPerOre=0,     SellPart="Lava" },
    ["Dark Magic"]                     = { Type="Standard",  CashMult=45,                   RPPerOre=0.15,  SellPart="Lava" },
    ["The Fracture"]                   = { Type="Cell",      CashMult=300000000,             RPPerOre=0.125, SellPart="Lava", CellOnly=true },
    ["Eternal Journey"]                = { Type="Standard",  CashMult=100,                  RPPerOre=2.0,   SellPart="Lava" },
    ["Solar Flare"]                    = { Type="Standard",  CashMult=25,                   RPPerOre=0.056, SellPart="Lava" },
    ["Sage Redeemer"]                  = { Type="Standard",  CashMult=50,                   RPPerOre=0.056, SellPart="Lava" },
    ["Blind Justice"]                  = { Type="Cell",      CashMult=700000000,             RPPerOre=0.4,   SellPart="Lava", CellOnly=true },
    ["Phase Processor"]                = { Type="Standard",  CashMult=500,                  RPPerOre=0.3,   SellPart="Lava" },
    ["Aether Refinery"]                = { Type="Standard",  CashMult=300,                  RPPerOre=0.333, SellPart="Lava" },
    ["Dreamer's Anguish"]              = { Type="Cell",      CashMult=50000000000000,        RPPerOre=0.175, SellPart="Lava", CellOnly=true },
    ["Sakura Garden"]                  = { Type="Standard",  CashMult=300,                  RPPerOre=0.5,   SellPart="Lava" },
    ["Ambrosia Fountain"]              = { Type="Standard",  CashMult=300,                  RPPerOre=0.01,  SellPart="Lava" },
    ["Guardian of the Gate"]           = { Type="Standard",  CashMult=200,                  RPPerOre=0.1,   SellPart="Lava" },
    ["Timeless Enhancement"]           = { Type="Standard",  CashMult=50,                   RPPerOre=0.24,  SellPart="Lava" },
    ["Nuclear Stronghold"]             = { Type="Standard",  CashMult=290,                  RPPerOre=2.333, SellPart="Lava" },
    ["Industrial Scarab"]              = { Type="Standard",  CashMult=9752,                 RPPerOre=3.1,   SellPart="Lava", IsRPFurnace=true },
    ["Interstellar Conqueror"]         = { Type="Cell",      CashMult=22500000000,           RPPerOre=1.0,   SellPart="Lava", CellOnly=true },
    ["Funky Town"]                     = { Type="Standard",  CashMult=600,                  RPPerOre=0.1,   SellPart="Lava" },
    ["Eternal Limbo"]                  = { Type="Standard",  CashMult=10000,                RPPerOre=25.0,  SellPart="Lava" },
    ["Aethereal Synthesizer"]          = { Type="Standard",  CashMult=5000,                 RPPerOre=0.56,  SellPart="Lava" },
    ["Sakura Falls"]                   = { Type="Standard",  CashMult=9500,                 RPPerOre=0.5,   SellPart="Lava" },
    ["Swift Justice"]                  = { Type="Cell",      CashMult=5000000000,            RPPerOre=0.1,   SellPart="Lava", CellOnly=false },
    ["Ambrosia Forest"]                = { Type="Standard",  CashMult=1500,                 RPPerOre=0.01,  SellPart="Lava" },
    ["Sage King"]                      = { Type="Standard",  CashMult=210,                  RPPerOre=0.6,   SellPart="Lava" },
    ["Guardian of the Portal"]         = { Type="Standard",  CashMult=900,                  RPPerOre=0.571, SellPart="Lava" },
    ["Breached Motherboard"]           = { Type="Standard",  CashMult=4000,                 RPPerOre=0.2,   SellPart="Lava" },
    ["Gaia's Grasp"]                   = { Type="Cell",      CashMult=3000000000000,         RPPerOre=0.8,   SellPart="Lava", CellOnly=true },
    ["The Fissure"]                    = { Type="Cell",      CashMult=1250000000,            RPPerOre=0.667, SellPart="Lava", CellOnly=true },
    ["Forbidden Magic"]                = { Type="Standard",  CashMult=600,                  RPPerOre=0.15,  SellPart="Lava" },
    ["Frozen Peaks"]                   = { Type="Standard",  CashMult=600,                  RPPerOre=0.5,   SellPart="Lava" },
    ["Dreamer's Nightmare"]            = { Type="Cell",      CashMult=1000000000000000000,   RPPerOre=0.833, SellPart="Lava", CellOnly=true },
    ["Dreamer's Terror"]               = { Type="Standard",  CashMult=10000,                RPPerOre=0.7,   SellPart="Lava" },
    ["Dreamer's Valor"]                = { Type="Standard",  CashMult=9500,                 RPPerOre=0.5,   SellPart="Lava" },
    ["Temporal Enchantment"]           = { Type="Standard",  CashMult=2100,                 RPPerOre=2.0,   SellPart="Lava" },
    ["Solar Eruption"]                 = { Type="Standard",  CashMult=190,                  RPPerOre=1.0,   SellPart="Lava" },
    ["Lunar Bombardment"]              = { Type="Standard",  CashMult=475,                  RPPerOre=1.0,   SellPart="Lava" },
    ["Nuclear Castle"]                 = { Type="Standard",  CashMult=3100,                 RPPerOre=2.545, SellPart="Lava" },
    ["Eternal Fracture"]               = { Type="Cell",      CashMult=2000000000,            RPPerOre=1.0,   SellPart="Lava", CellOnly=true },
    ["Anguished Garden"]               = { Type="Standard",  CashMult=1,                    RPPerOre=0.8,   SellPart="Lava" },
    ["Sage Justice"]                   = { Type="Standard",  CashMult=100,                  RPPerOre=0.1,   SellPart="Lava" },
    ["Nature's Temple"]                = { Type="Cell",      CashMult=5000000000000000,      RPPerOre=0.767, SellPart="Lava", CellOnly=true },
    ["Dark Illuminator"]               = { Type="Standard",  CashMult=500,                RPPerOre=0.15,  SellPart="Lava" },
    ["Anguished Guardian of the Gate"] = { Type="Standard",  CashMult=25600,                RPPerOre=0.6,   SellPart="Lava", IsRPFurnace=true },
    ["Ambrosia Garden"]                = { Type="Standard",  CashMult=25000,                RPPerOre=0.6,   SellPart="Lava" },
    ["Northern Lights"]                = { Type="Standard",  CashMult=4000,                 RPPerOre=0.2,   SellPart="Lava" },
    ["Crystal Shrine"]                 = { Type="Standard",  CashMult=3000,                 RPPerOre=0.6,   SellPart="Lava" },
    ["Igneous Forge"]                  = { Type="Standard",  CashMult=2000,                 RPPerOre=0.35,  SellPart="Lava" },
    ["Precursor Furnace"]              = { Type="Standard",  CashMult=500,                  RPPerOre=0.533, SellPart="Lava" },
    ["Dreamer's Blight"]               = { Type="Standard",  CashMult=500,                  RPPerOre=0.5,   SellPart="Lava" },
    ["Aurora Borealis"]                = { Type="Standard",  CashMult=21875,                RPPerOre=0.143, SellPart="Lava" },
    ["Tyrant's Forge"]                 = { Type="Standard",  CashMult=18000,                RPPerOre=0.667, SellPart="Lava" },
    ["Crystal Altar"]                  = { Type="Standard",  CashMult=20000,                RPPerOre=0.5,   SellPart="Lava" },
    ["Dreamer's Devastation"]          = { Type="Standard",  CashMult=14000,                RPPerOre=1.778, SellPart="Lava" },
    ["Phasecursor Furnace"]            = { Type="Standard",  CashMult=10000,                RPPerOre=0.8,   SellPart="Lava" },
    ["The Sunken Past"]                = { Type="Standard",  CashMult=30,                   RPPerOre=0.35,  SellPart="Lava" },
    ["Thingamajig"]                    = { Type="Cell",      CashMult=1000000000,            RPPerOre=1.25,  SellPart="Lava", CellOnly=true },
    ["The Dreamcatcher"]               = { Type="Standard",  CashMult=5,                    RPPerOre=0.02,  SellPart="Lava" },
    ["Canis Processus"]                = { Type="Standard",  CashMult=10,                   RPPerOre=0.01,  SellPart="Lava" },
    ["Diamond Falls"]                  = { Type="Standard",  CashMult=21,                   RPPerOre=0.138, SellPart="Lava" },
    ["THE UNDERTAKER"]                 = { Type="Cell",      CashMult=0.666,                RPPerOre=0.01,  SellPart="Lava", CellOnly=true },
    ["The Great Parasite"]             = { Type="Cell",      CashMult=100,                  RPPerOre=0.16,  SellPart="Lava", CellOnly=true },
    ["Nature's Enchantment"]           = { Type="Standard",  CashMult=55000,                RPPerOre=4.0,   SellPart="Lava" },
    ["Spooky Research Center"]         = { Type="Research",  CashMult=5,                    RPPerOre=1.833, SellPart="Lava", MinOreValue=50000 },
    ["Haunted Carnival"]               = { Type="Cell",      CashMult=80000000,             RPPerOre=0.625, SellPart="Lava", CellOnly=true },
    ["Sweet Tooth"]                    = { Type="Standard",  CashMult=25,                   RPPerOre=0.15,  SellPart="Lava" },
    ["Bag of Stars"]                   = { Type="Cell",      CashMult=9950000,              RPPerOre=0,     SellPart="Lava", CellOnly=true },
    ["New Year's City"]                = { Type="Standard",  CashMult=65,                   RPPerOre=0,     SellPart="Lava" },
    ["Lucky Research Center"]          = { Type="Research",  CashMult=7,                    RPPerOre=0.233, SellPart="Lava" },
    ["Pizza Research Center"]          = { Type="Research",  CashMult=5,                    RPPerOre=0.4,   SellPart="Lava" },
    ["Excalibur"]                      = { Type="Standard",  CashMult=1,                    RPPerOre=0.01,  SellPart="Lava" },
    ["Equinox"]                        = { Type="Standard",  CashMult=70,                   RPPerOre=0.01,  SellPart="Lava" },
    ["Grand Willow"]                   = { Type="Standard",  CashMult=45,                   RPPerOre=0.05,  SellPart="Lava" },
    ["Volcango"]                       = { Type="Standard",  CashMult=500,                  RPPerOre=0,     SellPart="Lava" },
    ["Oasis"]                          = { Type="Standard",  CashMult=2000,                 RPPerOre=0.01,  SellPart="Lava" },
    ["Octopi Council"]                 = { Type="Standard",  CashMult=100,                  RPPerOre=0.333, SellPart="Lava" },
    ["Coconut Drencher"]               = { Type="Cell",      CashMult=4000000,              RPPerOre=0,     SellPart="Lava", CellOnly=true },
    ["The Easter Shrine"]              = { Type="Standard",  CashMult=1000,                 RPPerOre=0.5,   SellPart="Lava" },
    ["Blood Magic"]                    = { Type="Standard",  CashMult=300,                  RPPerOre=0.02,  SellPart="Lava" },
    ["Flying Dutchman"]                = { Type="Standard",  CashMult=70,                   RPPerOre=0,     SellPart="Lava" },
    ["Hungry Spirit"]                  = { Type="Standard",  CashMult=50000000000,          RPPerOre=0.588, SellPart="Lava" },
    ["Dracula's Coffin"]               = { Type="Cell",      CashMult=20000000000,          RPPerOre=0,     SellPart="Lava", CellOnly=true },
    ["Plagued Forest"]                 = { Type="Standard",  CashMult=75,                   RPPerOre=1.0,   SellPart="Lava" },
    ["Conquered Wasteland"]            = { Type="Standard",  CashMult=45,                   RPPerOre=0.647, SellPart="Lava" },
    ["Birthday Cake"]                  = { Type="Standard",  CashMult=100,                  RPPerOre=0.01,  SellPart="Lava" },
    ["Grand Birthday Cake"]            = { Type="Standard",  CashMult=350,                  RPPerOre=0.01,  SellPart="Lava" },
    ["Supreme Birthday Cake"]          = { Type="Standard",  CashMult=700,                  RPPerOre=0,     SellPart="Lava" },
    ["Queen Birthday Cake"]            = { Type="Standard",  CashMult=11000,                RPPerOre=0.833, SellPart="Lava" },
    ["Forsaken Cake"]                  = { Type="Standard",  CashMult=30,                   RPPerOre=0,     SellPart="Lava" },
    ["All Star Behemoth Cake"]         = { Type="Standard",  CashMult=645,                  RPPerOre=0,     SellPart="Lava" },
    ["Belated 4th Birthday Cake"]      = { Type="Standard",  CashMult=100,                  RPPerOre=0,     SellPart="Lava" },
    ["Pot of Gold"]                    = { Type="Standard",  CashMult=5000,                 RPPerOre=0.05,  SellPart="Lava" },
    ["Leprechaun's Hat"]               = { Type="Cell",      CashMult=9500000000,           RPPerOre=0,     SellPart="Lava", CellOnly=true },
    ["Santa's Chimney"]                = { Type="Cell",      CashMult=50000,                RPPerOre=0.05,  SellPart="Lava", CellOnly=true },
    ["Ethereal Sanctuary"]             = { Type="Standard",  CashMult=150,                  RPPerOre=0.333, SellPart="Lava" },
    ["Grand Christmas Tree"]           = { Type="Standard",  CashMult=1125,                 RPPerOre=0.02,  SellPart="Lava" },
    ["Supreme Christmas Tree"]         = { Type="Standard",  CashMult=200,                  RPPerOre=0.1,   SellPart="Lava" },
    ["Ancient Magic"]                  = { Type="Standard",  CashMult=1,                    RPPerOre=0.125, SellPart="Lava" },
    ["Heavenly Wisp"]                  = { Type="Standard",  CashMult=300,                  RPPerOre=1.8,   SellPart="Lava" },
    ["Gladiator's Fury"]               = { Type="Standard",  CashMult=75,                   RPPerOre=0.175, SellPart="Lava" },
    ["Redwood Compass"]                = { Type="Standard",  CashMult=385,                  RPPerOre=1.5,   SellPart="Lava" },
    ["Ore Encapsulator"]               = { Type="Standard",  CashMult=100,                  RPPerOre=0,     SellPart="Lava" },
    ["Sword Master's Spirit"]          = { Type="Standard",  CashMult=75,                   RPPerOre=0.8,   SellPart="Lava" },
    ["Awakened Jack O Lantern"]        = { Type="Standard",  CashMult=600,                  RPPerOre=0.8,   SellPart="Lava" },
    ["Book of Knowledge"]              = { Type="Standard",  CashMult=50000,                RPPerOre=0.1,   SellPart="Lava" },
    ["Devourer of Nightmares"]         = { Type="Standard",  CashMult=100000,               RPPerOre=0,     SellPart="Lava" },
    ["Coliseum Catharsis"]             = { Type="Standard",  CashMult=42500,                RPPerOre=0,     SellPart="Lava" },
    ["Pizza Furnace"]                  = { Type="Standard",  CashMult=1000,                 RPPerOre=1.875, SellPart="Lava" },
    ["Oblivion Emission"]              = { Type="Standard",  CashMult=22000,                RPPerOre=2.885, SellPart="Lava" },
    ["Elysium Solemnity"]              = { Type="Standard",  CashMult=200000,               RPPerOre=0.8,   SellPart="Lava" },
    ["Tyrant's Throne"]                = { Type="Standard",  CashMult=85000,                RPPerOre=0.667, SellPart="Lava" },
    ["Pandora's Box"]                  = { Type="Cell",      CashMult=1e32,                 RPPerOre=10.0,  SellPart="Lava", CellOnly=true, UnupgradedOnly=true },
    ["The Heart of Void"]              = { Type="Standard",  CashMult=66666,                RPPerOre=-2.0,  SellPart="Lava" },
}
UPGRADER_DB = {
    ["Fine-Point Upgrader"]         = { Loopability="Unlimited", IsAdditive=true, Multiplier=1.0 },
    ["Sparking Boba"]         = { Loopability="No", MaxUses=1, Multiplier=22.0 },
    ["Pineapple! Stand"]         = { Loopability="No", MaxUses=1, Multiplier=3},
    ["Basic Ore Purifier"]          = { Loopability="Unlimited", CapValue=1000,   Multiplier=1.1, IsAdditive=true },
    ["Large Ore Upgrader"]          = { Loopability="Unlimited", CapValue=50000,  Multiplier=1.35 },
    ["Ore Scanner"]                 = { Loopability="Unlimited",                  Multiplier=3.5 },
    ["Solar Large Upgrader"]        = { Loopability="Unlimited", CapValue=50000,  Multiplier=1.35 },
    ["Jagged Enhancer"]             = { Loopability="No", MaxUses=1,              Multiplier=3.5,  SpecialFlag="low_counter_only" },
    ["Plasma Iron Polisher"]        = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Ore Cannon"]                  = { Loopability="Multi", MaxUses=5,           Multiplier=1.3 },
    ["Ore Steamer"]                 = { Loopability="Multi", MaxUses=4,  MinInterval=0.25, Multiplier=2.0 },
    ["Spectral Upgrader"]           = { Loopability="No", MaxUses=1,              Multiplier=4.2 },
    ["Portable Ore Advancer"]       = { Loopability="Multi", MaxUses=10,          Multiplier=1.05 },
    ["Overhang Upgrader"]           = { Loopability="No", MaxUses=1,              Multiplier=4.0,  SpecialFlag="launched_only" },
    ["Ore Crane"]                   = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Portable Ore Enhancer"]       = { Loopability="Multi", MaxUses=31,          Multiplier=1.08 },
    ["Radioactive Refiner"]         = { Loopability="Unlimited", AppliesEffect="radioactive", CapValue=500000000000, Multiplier=2.0 },
    ["Raised Wide Upgrader"]        = { Loopability="Unlimited",                  Multiplier=1.6 },
    ["Ore Magnifier"]               = { Loopability="No", MaxUses=1,              Multiplier=5.0,  SpecialFlag="unupgraded_only" },
    ["Industrial Ore Welder"]       = { Loopability="Multi", MaxUses=4,           Multiplier=1.75, SpecialFlag="coal_required" },
    ["Ore Roaster"]                 = { Loopability="Multi", MaxUses=4, AppliesEffect="fire", Multiplier=2.0, SpecialFlag="fire_only" },
    ["Heat Condenser"]              = { Loopability="Multi", MaxUses=4,           Multiplier=3.0,  SpecialFlag="fire_only" },
    ["Ore Tracker"]                 = { Loopability="No", MaxUses=1,              Multiplier=1.0 },
    ["Rush Upgrader"]               = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Ore Hoister"]                 = { Loopability="No", MaxUses=1,              Multiplier=2.5 },
    ["Ore Replicator"]              = { Loopability="No", MaxUses=1,              Multiplier=1.0 },
    ["Portable Ore Stopper"]        = { Loopability="Multi", MaxUses=31,          Multiplier=1.14 },
    ["Freshly Baked Upside-down Pineapple Cake"] = { Loopability="No", MaxUses=1, Multiplier=5.0 },
    ["Pizza Cutter"]                = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Ore Recliner"]                = { Loopability="Multi", MaxUses=5,           Multiplier=1.5 },
    ["Ore Zapper"]                  = { Loopability="Multi", MaxUses=3,           Multiplier=1.25 },
    ["Endpoint Refiner"]            = { Loopability="No", MaxUses=1,              Multiplier=3.0,  SpecialFlag="counter_dependent" },
    ["Satellite Beam"]              = { Loopability="Multi", MaxUses=2,           Multiplier=2.0 },
    ["Precision Refiner"]           = { Loopability="Unlimited", CapValue=100000000, Multiplier=1.4 },
    ["Way-Up-High Upgrader"]        = { Loopability="Unlimited", CapValue=1000000000, Multiplier=1.8 },
    ["Digital Ore Cleaner "]        = { Loopability="Unlimited", CapValue=10000000000, Multiplier=2.0 },
    ["Advanced Ore Scanner"]        = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Freon-Blast Upgrader"]        = { Loopability="Unlimited", ClearsEffect={"fire"}, CapValue=125000000000, Multiplier=1.45 },
    ["Cursed Ore Purifier"]         = { Loopability="Unlimited", IsAdditive=true, Multiplier=1.0 },
    ["Ore Collider"]                = { Loopability="Multi", MaxUses=2,           Multiplier=4.0 },
    ["Schrodinger Evaluator"]       = { Loopability="Multi", MaxUses=3, AppliesEffect="fire", Multiplier=3.2 },
    ["Flaming Ore Scanner"]         = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Ion Field"]                   = { Loopability="Multi", MaxUses=4,           Multiplier=1.8 },
    ["Orbitable Upgrader"]          = { Loopability="Multi", MaxUses=3,           Multiplier=1.4 },
    ["Portable Macrowave"]          = { Loopability="Multi", MaxUses=7,           Multiplier=1.8 },
    ["Serpentine Upgrader"]         = { Loopability="Unlimited", CapValue=10000000000000, Multiplier=1.4 },
    ["Fire-Blast Upgrader"]         = { Loopability="Unlimited", CapValue=64000000000, AppliesEffect="fire", Multiplier=2.0 },
    ["Drone Upgrader"]              = { Loopability="No", MaxUses=1,              Multiplier=2.0, IsAdditive=true },
    ["Ore Winder"]                  = { Loopability="Multi", MaxUses=3,           Multiplier=3.0 },
    ["Suspended Refiner"]           = { Loopability="Unlimited", FloorValue=1e15, Multiplier=1.7 },
    ["Molten Upgrader"]             = { Loopability="Unlimited", FloorValue=1e12, CapValue=5e16, Multiplier=1.8 },
    ["Ore Magmafier"]               = { Loopability="No", MaxUses=1,              Multiplier=2.52, FloorValue=1e15 },
    ["Nuclear Chamber"]             = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Rotary Upgrader"]             = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Advanced Ore Atomizer"]       = { Loopability="Unlimited", CapValue=1e21,   Multiplier=1.4 },
    ["Toxic Schrodinger Evaluator"] = { Loopability="Multi", MaxUses=3, AppliesEffect="poison", Multiplier=4.0 },
    ["Mini Upgrader"]               = { Loopability="Multi", MaxUses=6,           Multiplier=2.5,  EffMultOverride=80.0 },
    ["Freon Suppressor"]            = { Loopability="Unlimited", CapValue=1e23,   Multiplier=1.7, ClearsEffect={"fire"} },
    ["Repulsion Device"]            = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Aerogel Refiner"]             = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Horizon Centrifuge"]          = { Loopability="Unlimited", FloorValue=1e21, CapValue=1e24, Multiplier=1.55 },
    ["Cryogenic Upgrader"]          = { Loopability="Multi", MaxUses=3,           Multiplier=1.45 },
    ["Ore Thermocrusher"]           = { Loopability="Unlimited", CapValue=1e26,   Multiplier=1.3 },
    ["Suspended Lava Refiner"]      = { Loopability="Unlimited", CapValue=1e30,   Multiplier=1.4 },
    ["Ore Transistor"]              = { Loopability="Unlimited", FloorValue=1e27, CapValue=1e33, Multiplier=1.45 },
    ["Loop-de-Loop"]                = { Loopability="Unlimited", CapValue=1e38, MinInterval=3,   Multiplier=2.5 },
    ["Ore Transponder"]             = { Loopability="Unlimited", CapValue=1e41,   Multiplier=2.0 },
    ["Hydraulic Freefall Upgrader"] = { Loopability="Multi", MaxUses=5,           Multiplier=1.3,  SpecialFlag="launched_only" },
    ["Hydraulic Duality Refiner"]   = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Hydraulic Ramp Upgrader"]     = { Loopability="Multi", MaxUses=4,           Multiplier=1.25 },
    ["Portable Tractor Beam"]       = { Loopability="Multi", MaxUses=16,          Multiplier=1.2 },
    ["Anti-Gravity Scanner"]        = { Loopability="No", MaxUses=1,              Multiplier=7.0 },
    ["Schrodinger Chamber"]         = { Loopability="Multi", MaxUses=3,              Multiplier=3.0 },
    ["Portable Flamethrower"]       = { Loopability="Multi", MaxUses=6,           Multiplier=1.0, IsAdditive=true },
    ["Rainbow Upgrader"]            = { Loopability="Unlimited", CapValue=100000000, Multiplier=1.5 },
    ["Pineapple Refiner"]           = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Twitch-Powered Upgrader"]     = { Loopability="No", MaxUses=1,              Multiplier=1.6 },
    ["Professional Upgrader"]       = { Loopability="Multi", MaxUses=4,           Multiplier=1.3 },
    ["Twitch Scanner"]              = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Lunar Refiner"]               = { Loopability="Multi", MaxUses=3,           Multiplier=2.0 },
    ["Chemical Refiner"]            = { Loopability="No", MaxUses=1, AppliesEffect="poison",      Multiplier=7.0 },
    ["Alien Relic"]                 = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Freon Sprayer"]               = { Loopability="Unlimited",                  Multiplier=1.0, ClearsEffect={"fire"}, IsClearer=true },
    ["Ore Negator"]                 = { Loopability="No", MaxUses=1,              Multiplier=1.3 },
    ["Robotic Enhancer"]            = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Premium Tracker"]             = { Loopability="No", MaxUses=1,              Multiplier=1.0 },
    ["Purity Tracker"]              = { Loopability="No", MaxUses=1,              Multiplier=1.0 },
    ["Molten Forge"]                = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Maintenance Supporter"]       = { Loopability="Multi", MaxUses=5,           Multiplier=5.0, ClearsEffect={"poison","smoking"} },
    ["Blazing Annihilator"]         = { Loopability="Unlimited",                  Multiplier=1.0 },
    ["Hydraulic Presser"]           = { Loopability="Unlimited",                  Multiplier=1.0 },
    ["Helium Blaster"]              = { Loopability="Unlimited",                  Multiplier=1.0 },
    ["Berezaa Car Upgrader"]        = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Bouncy House!!!!111!!11!1"]   = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Pistachio Slice"]             = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["BUNZILLA"]                    = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Quantum Ore Cleaner"]         = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Tesla Resetter"]              = { IsTesla=true, Loopability="No",           Multiplier=1.0 },
    ["Ore Illuminator"]             = { Loopability="No", MaxUses=1,              Multiplier=5.0, PostDelay=5.5 },
    ["Flaming Schrodinger"]         = { Loopability="Multi", MaxUses=3,           Multiplier=3.0 },
    ["Big Bad Blaster"]             = { Loopability="Unlimited", AppliesEffect="fire", Multiplier=2.65 },
    ["Lightningbolt Refiner"]       = { Loopability="Multi", MaxUses=2,           Multiplier=4.0 },
    ["Big Bertha"]                  = { Loopability="No", MaxUses=1,              Multiplier=10.0, SpecialFlag="launched_only" },
    ["The Catalyst"]                = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Clockwork"]                   = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Gate of Eclipse"]             = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Ancient Temple"]              = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Wild Spore"]                  = { Loopability="No", MaxUses=1,              Multiplier=5.0, ClearsEffect={"fire","poison","radioactive"}, IsClearer=true },
    ["Azure Refiner"]               = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Morning Star"]                = { Loopability="Unlimited", AppliesEffect="fire", CapValue=1e33, Multiplier=1.4 },
    ["Astral Predictor"]            = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Scorching Heat"]              = { Loopability="No", MaxUses=1,              Multiplier=5.0,  SpecialFlag="fire_only" },
    ["Pizza Blaster"]               = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Red Giant"]                   = { Loopability="Unlimited", CapValue=1e38, AppliesEffect="fire", Multiplier=1.4 },
    ["Crystallized System"]         = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Ore Sawmill"]                 = { Loopability="No", MaxUses=1,              Multiplier=0.5 },
    ["Plasma Scanner"]              = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Shard Park"]                  = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Gravitational Gearwork"]      = { Loopability="No", MaxUses=1,              Multiplier=7.0,  SpecialFlag="launched_only" },
    ["Toxic Waste Disposal"]        = { Loopability="No", MaxUses=1, AppliesEffect="radioactive",   Multiplier=4.5 },
    ["Green Tea Latte"]             = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Fractured Reality"]           = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Mineral Wheel"]               = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Newtonic Corroder"]           = { Loopability="No", MaxUses=1, AppliesEffect="poison",        Multiplier=7.0 },
    ["Atlantic Monolith"]           = { Loopability="No", MaxUses=1,              Multiplier=4.0, ClearsEffect={"fire"} },
    ["Cooling Chamber"]             = { Loopability="No", MaxUses=1,              Multiplier=7.0, ClearsEffect={"fire"} },
    ["Vortex Chamber"]              = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Phase Refiner"]               = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Desert Monument"]             = { Loopability="No", MaxUses=1,              Multiplier=13.0 },
    ["The Sporest"]                 = { Loopability="No", MaxUses=1, AppliesEffect="poison",        Multiplier=8.0 },
    ["Banana Split Upgrader"]       = { Loopability="No", MaxUses=1,              Multiplier=5.5 },
    ["Skyliner Flux"]               = { Loopability="Multi", MaxUses=3,           Multiplier=4.0,  EffMultOverride=64.0 },
    ["Ore Skillet"]                 = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Ooftopian Refiner"]           = { Loopability="No", MaxUses=1,              Multiplier=20.0 },
    ["Ore Memer"]                   = { Loopability="No", MaxUses=1,              Multiplier=4.2 },
    ["Meatball Sandwich"]           = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Turtle Dignifier"]            = { Loopability="No", MaxUses=1,              Multiplier=8.0 },
    ["Utopian Refiner"]             = { Loopability="No", MaxUses=1,              Multiplier=50.0 },
    ["Ore Supernova"]               = { Loopability="No", MaxUses=1,              Multiplier=500.0 },
    ["Dystopian Refiner"]           = { Loopability="No", MaxUses=1,              Multiplier=40.0 },
    ["Burst Refiner"]               = { Loopability="No", MaxUses=1,              Multiplier=15.0 },
    ["Behemoth Blossom"]            = { Loopability="No", MaxUses=1,              Multiplier=80.0 },
    ["Neutropian Refiner"]          = { Loopability="No", MaxUses=1,              Multiplier=90.0 },
    ["Suitopian Refiner"]           = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Orbital Cataclysm"]           = { Loopability="No", MaxUses=1,              Multiplier=8.0 },
    ["Oblivion Weaver"]             = { Loopability="No", MaxUses=1,              Multiplier=9.0 },
    ["The Grand Prism"]             = { Loopability="No", MaxUses=1,              Multiplier=100.0 },
    ["Santa's Workshop"]            = { Loopability="Unlimited",                  Multiplier=1.2 },
    ["Santa's Sleigh"]              = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Ghost of Christmas Past"]     = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Gingerbread House"]           = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Winterheart"]                 = { Loopability="Multi", MaxUses=4,           Multiplier=3.0 },
    ["Festive Spirit"]              = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Santa's Deluxe Sleigh"]       = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Snowglobe Refiner"]           = { Loopability="Multi", MaxUses=4,           Multiplier=2.0 },
    ["Permafrost Refiner"]          = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Phantom of Christmas Future"] = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Wholesome Skull Blaster"]     = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["The Cosmic Tower"]            = { Loopability="No", MaxUses=1,              Multiplier=35.0, SpecialFlag="no_reset_compat" },
    ["Tree of Giving"]              = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Deluxe Santa's Workshop"]     = { Loopability="Multi", MaxUses=5,           Multiplier=1.2 },
    ["Winter Snowflake"]            = { Loopability="No", MaxUses=1,              Multiplier=4.75 },
    ["Gingerbread Mansion"]         = { Loopability="No", MaxUses=1,              Multiplier=8.0 },
    ["Spector of Christmas Present"]= { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Easter Statues"]              = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Santa's Castle"]              = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Hanging Wreath"]              = { Loopability="No", MaxUses=1,              Multiplier=12.0 },
    ["Grand Fruitcake"]             = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Gingerbread Boat"]            = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Santa's Nice List"]           = { Loopability="No", MaxUses=1,              Multiplier=3.0,  SpecialFlag="no_reset_compat" },
    ["The Ice Fortress"]            = { Loopability="No", MaxUses=1,              Multiplier=4.5 },
    ["Abominable Screaming Tree"]   = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Golden Clover Blaster"]       = { Loopability="No", MaxUses=1, AppliesEffect="fire",          Multiplier=4.0 },
    ["Clover Shrine"]               = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Rainbow Refiner"]             = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Pot of Gold-inator"]          = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Golden Horseshoe"]            = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Golden Clover Refiner"]       = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Diamond Egg"]                 = { Loopability="Multi", MaxUses=4, MinInterval=3.5,            Multiplier=2.5 },
    ["Big Bunny"]                   = { Loopability="No", MaxUses=1, AppliesEffect="fire",          Multiplier=4.0 },
    ["Royal Rabbit"]                = { Loopability="No", MaxUses=1,              Multiplier=5.5 },
    ["Amber Fossilizer"]            = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Cosmic Device"]               = { Loopability="No", MaxUses=1,              Multiplier=13.0 },
    ["Methane Sky Fleet"]           = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["CYBEGG9000"]                  = { Loopability="No", MaxUses=1, AppliesEffect="fire",          Multiplier=10.0 },
    ["Deviled Blaster"]             = { Loopability="No", MaxUses=1, AppliesEffect="fire",          Multiplier=13.0 },
    ["The Dust Devil"]              = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Eggscream Refiner"]           = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Energy Core"]                 = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Gator's Cove"]                = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Moai God"]                    = { Loopability="No", MaxUses=1,              Multiplier=8.0 },
    ["Malicious Incubator"]         = { Loopability="No", MaxUses=1, AppliesEffect="poison",        Multiplier=15.0 },
    ["ITeleporter"]                 = { Loopability="No", MaxUses=1,              Multiplier=9.0,  SpecialFlag="teleports" },
    ["Reaper's Fortress"]           = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["UI Infusion Device"]    = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Sandshark"]                   = { Loopability="No", MaxUses=1,              Multiplier=10.0, SpecialFlag="teleports" },
    ["Vaporwave Vibe Visualizer"]   = { Loopability="No", MaxUses=1,              Multiplier=7.0 },
    ["Vitamin C-Coater"]            = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Illusions of Void"]           = { Loopability="No", MaxUses=1,              Multiplier=9.0 },
    ["Portable Pearl Enhancer"]     = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Leggendary Black Hole"]       = { Loopability="No", MaxUses=1,              Multiplier=20.0 },
    ["Ruby Crystallizer"]           = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Glass Butterfly"]             = { Loopability="No", MaxUses=1,              Multiplier=8.0 },
    ["Eggplosive Refiner"]          = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Cactus Mirage"]               = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Chicken Legg Cookout"]        = { Loopability="No", MaxUses=1,              Multiplier=3.5 },
    ["Soaring Chopper"]             = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Lucky Hat"]                   = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Radio Tower"]                 = { Loopability="No", MaxUses=1,              Multiplier=20.0, SpecialFlag="no_reset_compat" },
    ["Soapy Refiner"]               = { Loopability="No", MaxUses=1,              Multiplier=3.0, ClearsEffect={"fire","poison","radioactive"} },
    ["Speggtral Rose"]              = { Loopability="No", MaxUses=1,              Multiplier=7.0 },
    ["Sporegg Hut"]                 = { Loopability="No", MaxUses=1,              Multiplier=4.5 },
    ["Time-Space Scrambler"]        = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Borker's Luxury Villa"]       = { Loopability="No", MaxUses=1,              Multiplier=7.0 },
    ["Final Faberge"]               = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Ore Striker"]                 = { Loopability="No", MaxUses=1,              Multiplier=5.0,  SpecialFlag="no_reset_compat" },
    ["The Beehive"]                 = { Loopability="No", MaxUses=1,              Multiplier=3.5 },
    ["Deluxe Beehive"]              = { Loopability="No", MaxUses=1,              Multiplier=3.5 },
    ["Citrus Enhancer"]             = { Loopability="No", MaxUses=1,              Multiplier=4.75 },
    ["Honeycomb Solace"]            = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Grand Willow"]                = { Loopability="No", MaxUses=1,              Multiplier=35.0, SpecialFlag="no_reset_compat" },
    ["Cupid's Arrow"]               = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["The Heartbreaker"]            = { Loopability="Multi", MaxUses=5,           Multiplier=2.5 },
    ["SpookLord-95000"]             = { Loopability="Unlimited",                  Multiplier=3.0 },
    ["SpookDemon-66666"]            = { Loopability="Unlimited",                  Multiplier=2.0 },
    ["Transylvanian Refiner"]       = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Great Pumpkin"]               = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Goliath Skull"]               = { Loopability="No", MaxUses=1,              Multiplier=20.0, SpecialFlag="teleports" },
    ["The Haunted House"]           = { Loopability="No", MaxUses=1,              Multiplier=8.71 },
    ["Eerie Marsh"]                 = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Pumpkin Hut"]                 = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Industrial Skeletal Salvation"]={ Loopability="No", MaxUses=1,              Multiplier=4.0,  SpecialFlag="coal_required" },
    ["Castle of Apocalypse"]        = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Sugar Corroder"]              = { Loopability="No", MaxUses=1,              Multiplier=1.3 },
    ["Pumpkin Pie Refiner"]         = { Loopability="No", MaxUses=1,              Multiplier=1.8 },
    ["Candy Corn Real Estate"]      = { Loopability="No", MaxUses=1,              Multiplier=1.8 },
    ["Plague Doctor"]               = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Strawberry Cake"]             = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Caramel Birthday Cake"]       = { Loopability="No", MaxUses=1,              Multiplier=15.0 },
    ["All Star Sundae"]             = { Loopability="No", MaxUses=1,              Multiplier=15.0 },
    ["Smore Cake"]                  = { Loopability="Multi", MaxUses=3, AppliesEffect="fire",          Multiplier=7.0 },
    ["Dragon Cake"]                 = { Loopability="Multi", MaxUses=3, AppliesEffect="fire", Multiplier=8.0 },
    ["Honeycomb Cake"]              = { Loopability="Multi", MaxUses=3,           Multiplier=6.0 },
    ["Peanut Butter Cake"]          = { Loopability="Multi", MaxUses=3,           Multiplier=5.0 },
    ["Jelly Cake"]                  = { Loopability="Multi", MaxUses=3,           Multiplier=8.0 },
    ["Citrus Cake"]                 = { Loopability="Multi", MaxUses=3,           Multiplier=5.0 },
    ["Angel's Cake"]                = { Loopability="Multi", MaxUses=3,           Multiplier=6.0 },
    ["Devil's Cake"]                = { Loopability="Multi", MaxUses=3,           Multiplier=7.0 },
    ["The Cherry Pie"]              = { Loopability="Multi", MaxUses=3,           Multiplier=1.8 },
    ["King Birthday Cake"]          = { Loopability="No", MaxUses=1,              Multiplier=15.0 },
    ["Blueberry Pie"]               = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Red Velvet Cake"]             = { Loopability="No", MaxUses=1,              Multiplier=12.0 },
    ["Chocolate Cupcake"]           = { Loopability="No", MaxUses=1,              Multiplier=7.0 },
    ["Acorn Avenue"]                = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Autumn Breeze"]               = { Loopability="Multi", MaxUses=8,           Multiplier=1.5 },
    ["Ghoul Lagoon"]                = { Loopability="No", MaxUses=1,              Multiplier=5.5, ClearsEffect={"fire"} },
    ["Sacred Totem"]                = { Loopability="No", MaxUses=1, AppliesEffect="fire",          Multiplier=7.0 },
    ["Pirate Cove"]                 = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Ore Tixicator"]               = { Loopability="No", MaxUses=1,              Multiplier=1.66 },
    ["The Master"]                  = { Loopability="No", MaxUses=1,              Multiplier=6.6 },
    ["The Boy"]                     = { Loopability="No", MaxUses=1,              Multiplier=1.75 },
    ["The Lord"]                    = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["The Demon"]                   = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["The Baron"]                   = { Loopability="No", MaxUses=1,              Multiplier=6.5 },
    ["The Storm"]                   = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["The Phantasm"]                = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Bubonic Plague"]              = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Ghosdeeri's Antidote"]        = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Famish Wasteland"]            = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Forsaken Battleground"]       = { Loopability="No", MaxUses=1,              Multiplier=3.0,  SpecialFlag="counter_dependent" },
    ["The Guillotine"]              = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Spires of Conquest"]          = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["King Darkseed"]               = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["⭐ Ye Olde Hades' Palace ⭐"] = { Loopability="No", MaxUses=1,              Multiplier=30.0 },
    ["⭐ Galilean Newtonic Corroder ⭐"] = { Loopability="No", MaxUses=1, AppliesEffect="poison",        Multiplier=7.0 },
    ["Birthday Upgrader"]           = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Hopeless Bog"]                = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Pumpkin Hero"]                = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Spooktastic Refiner"]         = { Loopability="Unlimited", CapValue=5000000, Multiplier=1.75 },
    ["Steel Refinery"]              = { Loopability="Unlimited",                  Multiplier=1.5 },
    ["Eggcelent Refiner"]           = { Loopability="Multi", MaxUses=5,           Multiplier=2.5 },
    ["Pumpkin Patch"]               = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Leprechaun's Rune"]           = { Loopability="Unlimited",                  Multiplier=2.0 },
    ["Clover Refiner"]              = { Loopability="No", MaxUses=1,              Multiplier=1.8 },
    ["100M Upgrader"]               = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Spooky Schrodinger"]          = { Loopability="No", MaxUses=2,              Multiplier=3.0 },
    ["Gloom Refiner"]               = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Undead Assistance"]           = { Loopability="Multi", MaxUses=6,           Multiplier=1.5 },
    ["Candy Refiner"]               = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Chocolate Forest"]            = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Ice Crusher"]                 = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Candy Cane Cannon"]           = { Loopability="Unlimited", AppliesEffect="fire",               Multiplier=2.05 },
    ["The Cryolyst"]                = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Fruitcake Blaster"]           = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Digital Peppermint Refiner"]  = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Santa's Workclock"]           = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["North Star"]                  = { Loopability="Multi", MaxUses=4,           Multiplier=1.15 },
    ["Frosted Refiner"]             = { Loopability="No", MaxUses=1,              Multiplier=1.75 },
    ["Igloo Refiner"]               = { Loopability="No", MaxUses=1,              Multiplier=1.15, SpecialFlag="fire_only" },
    ["Snowflake Suppressor"]        = { Loopability="No", MaxUses=1,              Multiplier=1.25 },
    ["Auroral Wings"]               = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Walrus Blaster"]              = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Behemoth Snowflake"]          = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Shiny Red Upgrader"]          = { Loopability="No", MaxUses=1,              Multiplier=1.5 },
    ["Tropical Holidays"]           = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Melancholy Holidays"]         = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Golden Bell Upgrader"]        = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Dual Festive Refiner"]        = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Holiday Street Refiner"]      = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Ornament Blaster"]            = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Hearty Refiner"]              = { Loopability="Multi", MaxUses=4,           Multiplier=1.35 },
    ["Ore Basket"]                  = { Loopability="No", MaxUses=1,              Multiplier=2.5, IsAdditive=true },
    ["Carrot Farm"]                 = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Three Years Upgrader"]        = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Gift Blaster"]                = { Loopability="Multi", MaxUses=2,           Multiplier=3.15 },
    ["Macaroon Upgrader"]           = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Ore Gielder"]                 = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Ore Caramelizer"]             = { Loopability="No", MaxUses=1,              Multiplier=1.3 },
    ["Candycorn Refiner"]           = { Loopability="No", MaxUses=1,              Multiplier=1.4 },
    ["Gummy Refiner"]               = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Frank'n'Cupcake"]             = { Loopability="No", MaxUses=1,              Multiplier=1.5 },
    ["Chocolate Coater"]            = { Loopability="No", MaxUses=1,              Multiplier=1.5 },
    ["Lollipop-inator"]             = { Loopability="No", MaxUses=1,              Multiplier=1.0 },
    ["Pumpkin Spice Refiner"]       = { Loopability="No", MaxUses=1,              Multiplier=2.5 },
    ["Candy Castle"]                = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Silkweaver"]                  = { Loopability="No", MaxUses=1,              Multiplier=1.75 },
    ["Ghastly Graveyard"]           = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Pumpkin Carriage"]            = { Loopability="No", MaxUses=1,              Multiplier=2.25 },
    ["Spider Queen"]                = { Loopability="No", MaxUses=1, AppliesEffect="poison",        Multiplier=2.0 },
    ["The Cookinator"]              = { Loopability="No", MaxUses=1,              Multiplier=1.3 },
    ["Grand Wafer"]                 = { Loopability="No", MaxUses=1,              Multiplier=1.4 },
    ["Ghost Town"]                  = { Loopability="No", MaxUses=1,              Multiplier=3.5 },
    ["The Crazy Hamburger"]         = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Big Candy Cane"]              = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Present Refiner"]             = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Aromatic Holidays"]           = { Loopability="No", MaxUses=1,              Multiplier=1.0 },
    ["L.I.M.E."]                    = { Loopability="Multi", MaxUses=3,           Multiplier=1.2 },
    ["Donut Refiner"]               = { Loopability="No", MaxUses=1,              Multiplier=1.75 },
    ["Orange Rock Candyizer"]       = { Loopability="No", MaxUses=1,              Multiplier=1.5 },
    ["Green Rock Candyizer"]        = { Loopability="No", MaxUses=1,              Multiplier=1.5 },
    ["Purple Rock Candyizer"]       = { Loopability="No", MaxUses=1,              Multiplier=1.5 },
    ["Overlord Device"]             = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["True Overlord Device"]        = { Loopability="No", MaxUses=1,              Multiplier=100.0 },
    ["The Ultimate Sacrifice"]      = { Loopability="No", MaxUses=1,              Multiplier=50.0 },
    -- Wiki: 1st use x50 and resets tags, 2nd x5..x1000 by delay, 3rd+ x1.35,
    -- upgrade loop capped at $100Qn (1e20). A capgrader: ore already above the
    -- cap gains nothing, so on a late-game base it acts as a resetter only.
    ["The Final Upgrader"]          = { IsTesla=true, Loopability="Multi", MaxUses=10, Multiplier=50.0,
                                        FirstMult=50.0, SecondMult=5.0, RepeatMult=1.35,
                                        LoopCap=1e+20, NeedsResetFirst=true, SpecialFlag="reset_then_multiply" },
    ["Tropical Breeze"]             = { Loopability="No", MaxUses=1,              Multiplier=6.0 },
    ["Spooklord Device"]            = { Loopability="No", MaxUses=1,              Multiplier=7.0 },
    ["Catalyzed Star"]              = { Loopability="Unlimited",                  Multiplier=2.0 },
    ["Azure Spore"]                 = { Loopability="Unlimited",                  Multiplier=2.5 },
    ["Quantum Clockwork"]           = { Loopability="No", MaxUses=1,              Multiplier=60.0 },
    ["Aether Schrodinger"]          = { Loopability="No", MaxUses=2,              Multiplier=6.0 },
    ["Lightningbolt Predictor"]     = { Loopability="Unlimited",                  Multiplier=5.0 },
    ["Firecrystallized System"]     = { Loopability="No", MaxUses=1,              Multiplier=12.75, SpecialFlag="coal_required" },
    ["Illuminator Evaluator"]       = { Loopability="Multi", MaxUses=2,                  Multiplier=3.0 },
    ["The Pizzalyst"]               = { Loopability="No", MaxUses=1,              Multiplier=59.7 },
    ["Frozen Eclipse"]              = { Loopability="No", MaxUses=1,              Multiplier=20.0 },
    ["Massive Quantum Diamond Cleaner"] = { Loopability="No", MaxUses=1,          Multiplier=14.0 },
    ["Saturated Catalyst"]          = { Loopability="No", MaxUses=1,              Multiplier=8.0 },
    ["Astral Setter"]               = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Quantum Ore Polisher"]        = { Loopability="No", MaxUses=1,              Multiplier=8.0 },
    ["Neutron Star"]                = { Loopability="Unlimited", CapValue=1e48,   Multiplier=2.0 },
    ["Deadly Spore"] = { Loopability="No", Multiplier=5.0, ClearsEffect = {"fire","radioactive","poison","darkness"}, IsClearer = true, CleanUnlimited = true},
    ["Final Eclipse Gate"]          = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Ore Indoctrinator"]           = { Loopability="No", MaxUses=1,              Multiplier=666.0, PostDelay=67 },
    ["Ancient Coliseum"]            = { Loopability="No", MaxUses=1,              Multiplier=13.0 },
    ["Tesla Refuter"]               = { IsTesla=true, Loopability="No",           Multiplier=1.0,  SpecialFlag="no_reset_compat" },
    ["Super Schrodinger"]           = { Loopability="Multi", MaxUses=2,           Multiplier=4.0 },
    ["Tsar Bomba"]                  = { Loopability="Multi", MaxUses=3,           Multiplier=50.0, EffMultOverride=125000.0 },
    ["Pizza Bombarder"]             = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Crystallized Engine"]         = { Loopability="No", MaxUses=1,              Multiplier=11.0 },
    ["Tempest Refiner"]             = { Loopability="Multi", MaxUses=2,           Multiplier=8.0 },
    ["Grandfather Clockwork"]       = { Loopability="No", MaxUses=1,              Multiplier=15.0 },
    ["Turbine Chamber"]             = { Loopability="No", MaxUses=1,              Multiplier=14.0 },
    ["Azure Purifier"]              = { Loopability="No", MaxUses=1,              Multiplier=9.0 },
    ["Searing Heat"]                = { Loopability="No", MaxUses=1,              Multiplier=15.0, SpecialFlag="fire_only" },
    ["Atmospheric Steamwork"]       = { Loopability="No", MaxUses=1,              Multiplier=14.0 },
    ["Atlantic Monument"]           = { Loopability="No", MaxUses=1,              Multiplier=13.0 },
    ["Phase Bombarder"]             = { Loopability="No", MaxUses=1,              Multiplier=15.0 },
    ["Mad Monstrous Melter"]        = { Loopability="Unlimited", AppliesEffect="fire",               Multiplier=6.1 },
    ["Ore Chainsaw"]                = { Loopability="No", MaxUses=1,              Multiplier=8.0 },
    ["Banana Sundae Refiner"]       = { Loopability="No", MaxUses=1,              Multiplier=9.0 },
    ["Universal Collapse"]          = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Temporal Armageddon"]         = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Shard City"]                  = { Loopability="No", MaxUses=1,              Multiplier=16.0 },
    ["Green Tea Kettle"]            = { Loopability="No", MaxUses=1,              Multiplier=9.0 },
    ["Demon Core"]                  = { Loopability="No", MaxUses=1,              Multiplier=11.0 },
    ["Heavenly Flux"]               = { Loopability="Multi", MaxUses=3,           Multiplier=7.0 },
    ["Vortex Singularity"]          = { Loopability="No", MaxUses=1,              Multiplier=9.0 },
    ["Freon Bombarder"]             = { Loopability="No", MaxUses=1,              Multiplier=1.0, ClearsEffect={"fire"} },
    ["Ore Painter"]                 = { Loopability="Unlimited",                  Multiplier=1.0 },
    ["Dragon Blaster"]              = { Loopability="No", MaxUses=1, AppliesEffect="fire",           Multiplier=4.0 },
    ["Nova Star"]                   = { Loopability="Unlimited",                  Multiplier=1.0 },
    ["Vulcan's Grasp"]              = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Virtual Enhancer"]            = { Loopability="No", MaxUses=1,              Multiplier=15.0 },
    ["Arcane Lightning"]            = { Loopability="No", MaxUses=1,              Multiplier=25.0 },
    ["Blue Supergiant"]             = { Loopability="Unlimited", AppliesEffect="fire", CapValue=1e90, Multiplier=60.0 },
    ["Stardust Pulsar"]             = { Loopability="No", MaxUses=1,              Multiplier=35.0, SpecialFlag="no_reset_compat" },
    ["Frigid Dystopia"]             = { Loopability="No", MaxUses=1,              Multiplier=15.0, SpecialFlag="fire_only" },
    ["Vampire Spore"]               = { Loopability="No", MaxUses=1, AppliesEffect="poison",        Multiplier=11.0 },
    ["Hades' Palace"]               = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Black Dwarf"]                 = { IsTesla=true, Loopability="No",           Multiplier=1.0,  SpecialFlag="no_reset_compat" },
    ["Father of Freon"]             = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Spirit of Fire"]              = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Son of Poison"]               = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Railgun Cannon"]              = { Loopability="No", MaxUses=1,              Multiplier=3.0 },
    ["Big Alberto"]                 = { Loopability="No", MaxUses=1,              Multiplier=25.0 },
    ["Hydra Blaster"]               = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Brimstone Spires"]            = { Loopability="No", MaxUses=1,              Multiplier=15.0 },
    ["Void Star"]                   = {  IsTesla=true, Loopability="No", MaxUses=1,              Multiplier=10.0, SpecialFlag="no_reset_compat" },
    ["Vulcan's Destiny"]            = { Loopability="No", MaxUses=1,              Multiplier=20.0, SpecialFlag="no_reset_compat" },
    ["Mystical Thunder"]            = { Loopability="No", MaxUses=1,              Multiplier=47.0 },
    ["Virtual Enchanter"]           = { Loopability="No", MaxUses=1,              Multiplier=22.0 },
    ["Castle Bravo"]                = { Loopability="No", MaxUses=1,              Multiplier=75.0 },
    ["Devil's Spore"]               = { Loopability="No", MaxUses=1, AppliesEffect="radioactive",   Multiplier=22.0 },
    ["Auroral Metropolis"]          = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Dragonglass Blaster"]         = { Loopability="Multi", MaxUses=1, AppliesEffect="fire",               Multiplier=9.0 },
    ["Igneous Lightning"]           = { Loopability="No", MaxUses=1,              Multiplier=60.0, SpecialFlag="coal_required" },
    ["Ore Nova"]                    = { Loopability="No", MaxUses=1,              Multiplier=1.0 },
    ["Stardust Illuminator"]        = { Loopability="No", MaxUses=1,              Multiplier=66.0, SpecialFlag="no_reset_compat" },
    ["Virtual Gearwork"]            = { Loopability="No", MaxUses=1,              Multiplier=17.0 },
    ["Dragon Cannon"]               = { Loopability="No", MaxUses=1,              Multiplier=30.0 },
    ["Big Fungus"]                  = { Loopability="No", MaxUses=1,              Multiplier=90.0 },
    ["Big Fluxxus"]                  = { Loopability="Multi", MaxUses=2,              Multiplier=90.0 },
    ["Nova Evaluator"]              = { Loopability="Unlimited",                  Multiplier=1.0 },
    ["CONTRALAND"]                  = { Loopability="No", MaxUses=1,              Multiplier=11.0 },
    ["Blazing Agriculture"]         = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Pillars of Creation"]         = { Loopability="No", MaxUses=1,              Multiplier=12.0 },
    ["Solar Apocalypse"]            = { Loopability="No", MaxUses=1, AppliesEffect="fire",           Multiplier=8.0 },
    ["Legendary Peppermint"]        = { Loopability="No", MaxUses=1,              Multiplier=8.0 },
    ["Mighty Sugar Cookie"]         = { Loopability="No", MaxUses=1,              Multiplier=8.5 },
    ["Angel's Blessing"]            = { Loopability="No", MaxUses=1,              Multiplier=150.0 },
    ["Empyrean Monument"]           = { Loopability="No", MaxUses=1,              Multiplier=56.0 },
    ["Dreamer's Life"]              = { Loopability="No", MaxUses=1,              Multiplier=525.0 },
    ["Void Drive"]                  = { Loopability="No", MaxUses=0,              Multiplier=100.0 },
    ["The Trinity"]                 = { Loopability="No", MaxUses=1,              Multiplier=30.0 },
    ["The Cornucopia"]              = { Loopability="No", MaxUses=1,              Multiplier=40.0 },
    ["The Chaosrealm"]              = { Loopability="No", MaxUses=1,              Multiplier=8.0,  SpecialFlag="no_reset_compat" },
    ["Draedon's Gauntlet"]          = { Loopability="No", MaxUses=1,              Multiplier=250.0, PostDelay=11 },
    ["Daestrophe"]                  = { IsTesla=true, Loopability="No", MaxUses=1,              Multiplier=100.0, FireMult=2.0, SpecialFlag="no_reset_compat" },
    ["Delta Phantom"]               = { Loopability="No", MaxUses=1,              Multiplier=100.0 },
    ["Optic Origin"]                = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["The Death Cap"]               = { Loopability="No", MaxUses=1,              Multiplier=130.0 },
    ["Midas Blaster"]               = { Loopability="Unlimited",                  Multiplier=5.0 },
    ["Vulcan's Wrath"]              = { Loopability="No", MaxUses=1,              Multiplier=50.0 },
    ["Garden of Gaia"]              = { Loopability="No", MaxUses=1,              Multiplier=90.0 },
    ["Enchanted Library"]           = { Loopability="No", MaxUses=1,              Multiplier=20.0 },
    ["Ore Hypernova"]               = { Loopability="No", MaxUses=1,              Multiplier=1500.0, SpecialFlag="no_reset_compat" },
    ["The Hourglass"]               = { Loopability="No", MaxUses=1,              Multiplier=70.0 },
    ["Swag City"]                   = { Loopability="No", MaxUses=1,              Multiplier=91.0 },
    ["Methuselah's Mask"]           = { Loopability="No", MaxUses=1,              Multiplier=20.0 },
    ["Meralin's Sorcery"]           = { Loopability="No", MaxUses=1,              Multiplier=127.0 },
    ["Executive Pillars"]           = { Loopability="No", MaxUses=1,              Multiplier=5.5 },
    ["Statue of Knowledge"]         = { Loopability="No", MaxUses=1,              Multiplier=2.5 },
    ["Vesterian Upgrader"]          = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["The Darkest Upgrader"]        = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Test Upgrader"]               = { Loopability="No", MaxUses=1,              Multiplier=1.01 },
    ["The Dreamcatcher"]            = { Loopability="No", MaxUses=1,              Multiplier=5.0 },
    ["Stratospheric Refiner"]       = { Loopability="No", MaxUses=1,              Multiplier=2.5 },
    ["The Holy Cheese"]             = { Loopability="No", MaxUses=1,              Multiplier=4.0 },
    ["Way-Up-High Cake Pop"]        = { Loopability="Multi", MaxUses=3,           Multiplier=3.0 },
    ["Inflatable Party Upgrader"]   = { Loopability="No", MaxUses=1,              Multiplier=3.0,  SpecialFlag="height_based" },
    ["Vanilla Scanner"]             = { Loopability="No", MaxUses=1,              Multiplier=3.0,  SpecialFlag="size_limited_23" },
    ["⭐ New Age Quantum Ore Cleaner ⭐"] = { Loopability="No", MaxUses=1,         Multiplier=4.0 },
    ["Red Velvet Cupcake"]          = { Loopability="No", MaxUses=1,              Multiplier=4.0,  SpecialFlag="cake_boost" },
    ["Lucky Seven's Cake"]          = { Loopability="No", MaxUses=1,              Multiplier=7.0,  SpecialFlag="rng_multiplier" },
    ["Friends Forever"]             = { Loopability="No", MaxUses=1,              Multiplier=10.0,  SpecialFlag="friend_count_multiplier" },
    ["Freshly Baked Upsidedown Pineapple Cake"] = { Loopability="No", MaxUses=1,  Multiplier=10.0,  SpecialFlag="wet" },
    ["Eternal Cake"]                = { Loopability="No", MaxUses=1,              Multiplier=8.0,  SpecialFlag="anti_gravity" },
    ["Funnel Cake"]                 = { Loopability="No", MaxUses=1,              Multiplier=44.0 },
    ["Pancake Stack"]               = { Loopability="No", MaxUses=1,              Multiplier=33.0 },
    ["Blizzard Predictor"]          = { Loopability="No", MaxUses=1,              Multiplier=2.0 },
    ["Frostbite Chamber"]           = { Loopability="No", MaxUses=1,              Multiplier=5.0,  SpecialFlag="no_reset_compat" },
    ["Snowflake Wheel"]             = { Loopability="No", MaxUses=1,              Multiplier=6.0,  SpecialFlag="no_reset_compat" },
    ["Present Schrodinger"]         = { Loopability="No", MaxUses=5,              Multiplier=2.0,  SpecialFlag="no_reset_compat" },
    ["Witch's Cauldron"]            = { Loopability="No", MaxUses=1,              Multiplier=7.5 },
    ["One Million Upgrader"]        = { Loopability="No", MaxUses=1,              Multiplier=10.0 },
    ["Pizza Parlor"]                = { Loopability="No", MaxUses=1,              Multiplier=5.0 }
}


-- ══════════════════════════════════════════════════════════════════════
--  ITEM IDENTITY  ·  ids first, names only as a fallback
-- ══════════════════════════════════════════════════════════════════════
-- The update renames items and ships every shiny as its own id, so a name
-- lookup misses both. A placed machine carries an ItemId attribute that
-- never changes; we key on that, and fold a shiny id back onto its base.
MHItem = {
    byId        = {},
    nameToId    = {},
    baseOfShiny = {},
    upgraderId  = {},
    furnaceId   = {},
    upgraderKey = {},
    furnaceKey  = {},
    orphaned    = {},
}

function stripShiny(name)
    return (tostring(name):gsub("⭐", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Renames live here: [old database key] = "current in-game name"
DB_ALIASES = {
    -- Renames found by matching live Items folder entries to database keys.
    ["Basic Ore Purifier"] = "Ore Purifier",
    ["Basic Research Center"] = "Simple Research Center",
    ["Famish Wasteland"] = "Famished Wasteland",
    ["Final Faberge"] = "Final Fabergé",
    ["Freon Suppressor"] = "Freon Supressor",
    ["Goliath Skull"] = "Goliath Skull (Sender)",
    ["ITeleporter"] = "iTeleporter",
    ["Sandshark"] = "Sandshark (Sender)",
    ["Spector of Christmas Present"] = "Specter of Christmas Present",
    ["Spires of Conquest"] = "Spires Of Conquest",
    ["SpookDemon-66666"] = "SpookDemon-66,666",
    ["SpookLord-95000"] = "SpookLord-95,000",
    ["The Dreamcatcher"] = "Dreamcatcher",
    ["Basic Furnace"] = "Ore Furnace",
    ["Basic Cell Furnace"] = "Ore Cell Furnace",
    ["Fine-Point Upgrader"] = "Fine-point Upgrader",
    ["Freshly Baked Upsidedown Pineapple Cake"] = "Freshly Baked Upside-down Pineapple Cake",
    ["Portable Ore Advancer"] = "Portable Ore Refiner",
}

-- Shiny families from the game data: base name -> its shiny prefixes. A shiny
-- is the same machine as its base, only recoloured, so both have to resolve to
-- one key or the route counts a second, phantom step.
local SHINY_FAMILIES = {
    ["Aether Refinery"] = "Blazing",
    ["Aethereal Synthesizer"] = "Blazing",
    ["Ambrosia Forest"] = "Berry",
    ["Ambrosia Fountain"] = "Berry",
    ["Ancient Coliseum"] = "Dusk",
    ["Ancient Temple"] = "Dusk",
    ["Arcane Lightning"] = "Eclipse",
    ["Astral Predictor"] = "Storm|Contemporary",
    ["Astral Setter"] = "Storm",
    ["Atlantic Monolith"] = "Scorched",
    ["Atlantic Monument"] = "Scorched",
    ["Atmospheric Steamwork"] = "Gamma",
    ["Aurora Borealis"] = "Cosmic",
    ["Auroral Metropolis"] = "Ashen",
    ["Australis Fornacem"] = "Endothermic",
    ["Azure Purifier"] = "Crimson",
    ["Azure Refiner"] = "Crimson",
    ["BUNZILLA"] = "ATOMIC",
    ["Banana Split Upgrader"] = "Mint",
    ["Banana Sundae Refiner"] = "Mint",
    ["Behemoth Blossom/Renegade"] = "Elder",
    ["Big Alberto"] = "Cyber",
    ["Big Bad Blaster"] = "Eternal|Confetti",
    ["Big Bertha"] = "Cyber",
    ["Black Dwarf"] = "Stargazed|Beloved",
    ["Blind Justice"] = "Eldritch|Contemporary",
    ["Blizzard Predictor"] = "Carrot",
    ["Blue Supergiant"] = "Hypergiant",
    ["Breached Motherboard"] = "Binary",
    ["Brimstone Spires"] = "Frozen",
    ["Bubonic Plague"] = "Cured",
    ["Burst Refiner/Renegade"] = "Smoke",
    ["Candy Cane Cannon"] = "Sour",
    ["Carrot Village"] = "Parsnip",
    ["Castle Bravo"] = "Cyber",
    ["Clockwork"] = "Eldritch",
    ["Combustion Engine"] = "Fallen|Leprechaun's|Contemporary",
    ["Cooling Chamber"] = "Bodacious|iSpin",
    ["Crystal Altar"] = "Spectrum",
    ["Crystal Shrine"] = "Spectrum",
    ["Crystallized Engine"] = "Lapis",
    ["Crystallized System"] = "Lapis|Cupid's",
    ["Dark Magic"] = "Blazing",
    ["Deadly Spore"] = "Autumnal",
    ["Demon Core"] = "Blurptonium",
    ["Desert Monument"] = "Elysium|Clover|Ye Olde",
    ["Devil's Spore"] = "Wholesome",
    ["Digital Peppermint Refiner"] = "Frozen",
    ["Draedon's Gauntlet"] = "Inevitable",
    ["Dragon Blaster"] = "Ghastly|Shamrock|Stormcrow",
    ["Dreamer's Anguish"] = "Dusk|New Age",
    ["Dreamer's Blight"] = "Autumnal",
    ["Dreamer's Devastation"] = "Autumnal",
    ["Dreamer's Fright"] = "Mighty|Nightmare|Escape",
    ["Dreamer's Life"] = "Hallow",
    ["Dreamer's Might"] = "Frightful",
    ["Dreamer's Nightmare"] = "Dusk",
    ["Dreamer's Terror"] = "Mighty",
    ["Dreamer's Valor"] = "Frightful",
    ["Dystopian Refiner/Renegade"] = "Grape",
    ["Empyrean Monument"] = "Antithesis",
    ["Enchanted Library"] = "Knowledgeful",
    ["Esoteric Citadel"] = "Master's|Fabergé",
    ["Eternal Journey"] = "Dawn",
    ["Eternal Limbo"] = "Dawn",
    ["Famished Farm"] = "Rejuvenated",
    ["Famished Wasteland"] = "Delusional",
    ["Father of Freon"] = "Blazing",
    ["Final Eclipse Gate"] = "Void",
    ["Flaming Schrodinger"] = "Steamwork",
    ["Forbidden Magic"] = "Blazing",
    ["Forsaken Battleground"] = "Blistering",
    ["Fractured Reality"] = "Oblivion|Lonely",
    ["Frigid Dystopia"] = "Ashen",
    ["Frostbite Chamber"] = "Cranberry",
    ["Frozen Justice"] = "Ashen|New Age",
    ["Frozen Peaks"] = "Ashen",
    ["Fruitcake Blaster"] = "Clown",
    ["Funky Town"] = "Swag|Malicious",
    ["Gaia's Grasp"] = "Dawn",
    ["Gate of Eclipse"] = "Void",
    ["Ghosdeeri's Antidote"] = "Inoculating",
    ["Glass Butterfly"] = "Moth",
    ["Grandfather Clockwork"] = "Eldritch",
    ["Gravitational Gearwork"] = "Gamma",
    ["Gravitational Gyrocopter"] = "Pilot",
    ["Green Tea Kettle"] = "Vintage",
    ["Green Tea Latte"] = "Vintage",
    ["Guardian of the Gate"] = "Eldritch",
    ["Guardian of the Portal"] = "Eldritch",
    ["Hades' Palace"] = "Styx|Transylvanian|Ye Olde",
    ["Heavenly Flux"] = "Poindexter",
    ["Hydra Blaster"] = "Ghastly",
    ["Ice Crusher"] = "Oblivion",
    ["Igneous Forge"] = "Newtonic",
    ["Industrial Scarab"] = "Galilean",
    ["Interstellar Conqueror"] = "Stargazed",
    ["Invasive Cyberlord"] = "Binary",
    ["King Birthday Cake"] = "Caramel",
    ["King Darkseed"] = "Deity",
    ["Lepretron"] = "Golden|Diamond",
    ["Lightningbolt Refiner"] = "Martian",
    ["Lunar Bombardment"] = "Blood",
    ["Lunar Spectacle/Renegade"] = "Scarlet",
    ["Mad Monstrous Melter"] = "Eternal",
    ["Meatball Sandwich"] = "Icecream|Pearl",
    ["Midas Blaster"] = "Sage",
    ["Mineral Wheel"] = "Toxic",
    ["Morning Star"] = "Celestial",
    ["Mycolympus"] = "Vampiric",
    ["Mystical Thunder"] = "Eclipse",
    ["Nature's Enchantment/Renegade"] = "Ancient",
    ["Nature's Grip"] = "Dawn",
    ["Neutron Star"] = "Wholesome",
    ["Neutropian Refiner/Renegade"] = "Kiwi",
    ["Newtonic Corroder"] = "Galilean",
    ["Northern Lights"] = "Cosmic|Dutchman's|Vaporwave",
    ["Nova Star"] = "Celestial|New Age",
    ["Nuclear Castle"] = "Hades",
    ["Nuclear Stronghold"] = "Hades",
    ["Ooftopian Refiner"] = "Cherry|Pomegranate",
    ["Orbital Cataclysm/Renegade"] = "Daybreak",
    ["Ore Chainsaw"] = "Wholesome",
    ["Ore Illuminator"] = "Spicy",
    ["Ore Indoctrinator"] = "Spicy",
    ["Ore Memer"] = "Ghost",
    ["Ore Sawmill"] = "Wholesome",
    ["Ore Skillet"] = "BBQ|Green",
    ["Overlord Device"] = "Overseer",
    ["Phase Bombarder"] = "Neon",
    ["Phase Processor"] = "Neon",
    ["Phase Refiner"] = "Neon",
    ["Pizza Blaster"] = "Void|Birthday",
    ["Pizza Bombarder"] = "Void",
    ["Plasma Scanner"] = "Timekeeper's|Disco",
    ["Precursor Furnace"] = "Neon",
    ["Present Schrodinger"] = "Auroral",
    ["Pumpkin Hut"] = "Darkseed|Dusekkar|Doomsekkar|Ghosdeeri",
    ["Quaint Skymill"] = "Gloomy|Stellar",
    ["Quantum Ore Cleaner"] = "Alpha|.EXE|New Age|Soapy",
    ["Quantum Ore Polisher"] = "Alpha",
    ["Queen Birthday Cake"] = "Velvet",
    ["Red Giant"] = "Wholesome",
    ["Rose Palace"] = "Bitter",
    ["Sage King"] = "Wealthy",
    ["Sage Redeemer"] = "Wealthy|Cephalopod",
    ["Sakura Falls"] = "Abstract",
    ["Sakura Garden"] = "Abstract|Contemporary",
    ["Santa's Workclock"] = "Sour",
    ["Saturated Catalyst"] = "Charged",
    ["Scorching Heat"] = "Frosted",
    ["Searing Heat"] = "Frosted",
    ["Shard City"] = "Solar",
    ["Shard Park"] = "Solar",
    ["Sinister Sepulcher/Renegade"] = "Ornate",
    ["Skydance Serenade/Renegade"] = "Monochrome",
    ["Skyliner Flux"] = "Citrus|Loki's|CYBEGG",
    ["Snowflake Wheel"] = "Oofy",
    ["Solar Eruption"] = "Supergiant",
    ["Solar Flare"] = "Supergiant",
    ["Son of Poison"] = "Frozen|Ye Olde",
    ["Soul Blossom"] = "Corrupt",
    ["Spaghetti & Meatballs"] = "Icecream",
    ["Spires of Conquest"] = "Eerie",
    ["Spirit of Fire"] = "Toxic",
    ["Stardust Pulsar"] = "Nova",
    ["Suitopian Refiner/Renegade"] = "Lemon :)",
    ["Super Schrodinger"] = "Steamwork",
    ["Swift Justice"] = "Eldritch",
    ["Tempest Refiner"] = "Martian",
    ["Temporal Armageddon"] = "Oblivion",
    ["Temporal Enchantment"] = "Dawn",
    ["Tesla Refuter"] = "Advanced",
    ["Tesla Resetter"] = "Advanced|Spooky",
    ["The Catalyst"] = "Charged|Contemporary",
    ["The Cryolyst"] = "Pine",
    ["The Fissure"] = "Purified",
    ["The Fracture"] = "Void",
    ["The Grand Prism/Renegade"] = "Prideful",
    ["The Great Parasite/Renegade"] = "Tomfoolish",
    ["The Guillotine"] = "Gruesome",
    ["The Hourglass"] = "First",
    ["The Sporest"] = "Vampiric|Ye Olde",
    ["Timeless Enhancement"] = "Dawn",
    ["Tortoise Fortifier"] = "Retro",
    ["Toxic Waste Disposal"] = "Blurptonium",
    ["True Overlord Device"] = "Galactic",
    ["Tsar Bomba"] = "Cyber",
    ["Turbine Chamber"] = "Bodacious",
    ["Turtle Dignifier"] = "Retro|Lucky",
    ["Tyrant's Forge"] = "Newtonic",
    ["Universal Collapse"] = "Oblivion",
    ["Utopian Refiner/Renegade"] = "Blueberry",
    ["Vampire Spore"] = "Wholesome",
    ["Virtual Enchanter"] = "Crimson",
    ["Virtual Enhancer"] = "Crimson",
    ["Void Star"] = "Stargazed",
    ["Vortex Chamber"] = "Minted",
    ["Vortex Singularity"] = "Minted",
    ["Vulcan's Destiny"] = "Frozen",
    ["Vulcan's Grasp"] = "Frozen",
    ["Walrus Blaster"] = "Awesome",
    ["Wedding Cake"] = "Void",
    ["Whimsical Turbine"] = "Gloomy",
    ["Wild Spore"] = "Autumnal|Plagued",
}
SHINY_PREFIX = {}
for base, packed in pairs(SHINY_FAMILIES) do
    -- The game drops a leading "The" when it prepends a shiny prefix:
    -- "Contemporary Catalyst", never "Contemporary The Catalyst".
    local bare = base:gsub("^The ", "")
    for prefix in string.gmatch(packed, "[^|]+") do
        SHINY_PREFIX[string.lower(prefix .. " " .. base)] = base
        if bare ~= base then SHINY_PREFIX[string.lower(prefix .. " " .. bare)] = base end
    end
end

function resolveName(name)
    local raw = tostring(name)
    local clean = stripShiny(raw)
    local base = SHINY_PREFIX[string.lower(clean)]
    if base then clean = base end
    local alias = DB_ALIASES[clean]
    if alias then return alias end
    -- A shiny whose prefix is missing from the family data ("Azure
    -- Dragonglass Mine"): drop leading words until the rest is a real item,
    -- so it still lands on its base instead of a phantom second machine.
    if raw:find("⭐") then
        local rest = clean
        while true do
            local cut = rest:find(" ")
            if not cut then break end
            rest = rest:sub(cut + 1)
            local hit = DB_ALIASES[rest]
                or (MHItem.upgraderKey and MHItem.upgraderKey[rest])
                or (MHItem.furnaceKey and MHItem.furnaceKey[rest])
                or MHItem.nameToId[rest]
            if hit then return (type(hit) == "string" and hit) or rest end
        end
    end
    return clean
end

do
    local folder = RS:FindFirstChild("Items")
    if folder then
        local items = folder:GetChildren()
        -- Pass 1: every id and name, so a base item is always known before any
        -- shiny is folded onto it.
        for _, item in ipairs(items) do
            local id = item:GetAttribute("ItemId")
            if not id then
                local v = item:FindFirstChild("ItemId")
                id = v and v.Value
            end
            if id then
                MHItem.byId[id] = item
                -- Only a base template may claim a clean name. Shiny variants
                -- share it, and otherwise win the lookup while owning zero.
                if stripShiny(item.Name) == item.Name then
                    if not MHItem.nameToId[item.Name] then MHItem.nameToId[item.Name] = id end
                elseif not MHItem.nameToId[item.Name] then
                    MHItem.nameToId[item.Name] = id
                end
            end
        end
        -- Pass 2: fold each shiny id onto its base now that all names exist.
        for _, item in ipairs(items) do
            local id = item:GetAttribute("ItemId")
            if not id then
                local v = item:FindFirstChild("ItemId")
                id = v and v.Value
            end
            if id and stripShiny(item.Name) ~= item.Name then
                MHItem.baseOfShiny[id] = resolveName(item.Name)
            end
        end
    end
end

function itemIdOf(model)
    local id = model:GetAttribute("ItemId")
    if not id then
        local v = model:FindFirstChild("ItemId")
        id = v and v.Value
    end
    if not id then id = MHItem.nameToId[resolveName(model.Name)] end
    return id
end

function itemKey(model)
    local id = itemIdOf(model)
    local shinyBase = id and MHItem.baseOfShiny[id]
    return resolveName(shinyBase or model.Name), id
end

do
    for name, entry in pairs(UPGRADER_DB) do
        local key = resolveName(name)
        MHItem.upgraderKey[key] = entry
        local id = MHItem.nameToId[key]
        if id then MHItem.upgraderId[id] = entry else table.insert(MHItem.orphaned, name) end
    end
    for name, entry in pairs(FURNACE_DB) do
        local key = resolveName(name)
        MHItem.furnaceKey[key] = entry
        local id = MHItem.nameToId[key]
        if id then MHItem.furnaceId[id] = entry else table.insert(MHItem.orphaned, name) end
    end
    -- every shiny id inherits its base entry
    for shinyId, base in pairs(MHItem.baseOfShiny) do
        local key = resolveName(base)
        if not MHItem.upgraderId[shinyId] then MHItem.upgraderId[shinyId] = MHItem.upgraderKey[key] end
        if not MHItem.furnaceId[shinyId] then MHItem.furnaceId[shinyId] = MHItem.furnaceKey[key] end
    end
end

function MHUpgrader(model)
    local key, id = itemKey(model)
    if id and MHItem.upgraderId[id] then return MHItem.upgraderId[id], key, id end
    return MHItem.upgraderKey[key], key, id
end

function MHFurnace(model)
    local key, id = itemKey(model)
    if id and MHItem.furnaceId[id] then return MHItem.furnaceId[id], key, id end
    return MHItem.furnaceKey[key], key, id
end

-- Items that only fire ONCE, right before sell. Never in upgrade cycles.
EDUCATION_UPGRADERS = {
    ["Ore Illuminator"]    = true,
    ["Ore Indoctrinator"]  = true,
    ["Draedon's Gauntlet"] = true,
}

-- Seconds each education touch stays safe before the ore dies. These are the
-- per-machine values from the game database ("education="), not the generic
-- 5 second Education status timer.
EDUCATION_TIMERS = {
    ["Ore Illuminator"]    = 5,
    ["Ore Indoctrinator"]  = 66,
    ["Draedon's Gauntlet"] = 10,
}

INCOMPATIBLE_AFTER = {
    ["Angel's Blessing"] = { ["Azure Spore"] = true },
}
BOX_TYPES = {}

-- ── BOXES ───────────────────────────────────────────────────────────
-- Verified against the game's own Boxes module:
--   definitions : ReplicatedStorage.Assets.Boxes
--   owned counts: LocalPlayer.Crates (".Value" is the total)
--   opening     : GUI.Unboxing.Unbox:Invoke(name, useClover)
--   clover flag : LocalPlayer.UseClover, toggled with ToggleBoxItem "Clover"
function boxFolder()
    return lp:FindFirstChild("Crates")
end

function boxCount(name)
    local crates = boxFolder()
    local slot = crates and crates:FindFirstChild(name)
    return slot and slot.Value or 0
end

function totalBoxes()
    local crates = boxFolder()
    return crates and crates.Value or 0
end

function cloverEnabled()
    local flag = lp:FindFirstChild("UseClover")
    return flag and flag.Value or false
end

-- never burn a clover we do not have: the flag can be on with 0 clovers
function cloverReady()
    local flag = lp:FindFirstChild("UseClover")
    local count = lp:FindFirstChild("Clovers")
    return flag and flag.Value == true and count and count.Value > 0
end

function toggleClover()
    pcall(function() Channel("ToggleBoxItem"):InvokeServer("Clover") end)
end

function discoverBoxes()
    local names, seen = {}, {}
    local assets = RS:FindFirstChild("Assets")
    assets = assets and assets:FindFirstChild("Boxes")
    if assets then
        for _, def in ipairs(assets:GetChildren()) do
            if not seen[def.Name] then
                seen[def.Name] = true
                names[#names + 1] = def.Name
            end
        end
    end
    table.sort(names)
    return names
end

function openBoxOnce(name)
    local gui = lp.PlayerGui:FindFirstChild("GUI")
    local unbox = gui and gui:FindFirstChild("Unboxing")
    unbox = unbox and unbox:FindFirstChild("Unbox")
    if unbox and unbox:IsA("BindableFunction") then
        local ok = pcall(function() unbox:Invoke(name, cloverReady()) end)
        if ok then return true end
    end
    return (pcall(function() Channel("MysteryBox"):InvokeServer(name) end))
end

local State = {
    RebirthPending = false,
    firecystalFeed    = false,
    cellFurnaceMode = false,
    oreBooster        = false,
    autoRemote        = false,
    autoBoxes         = false,
    autoOpenBoxes     = false,
    usePostDelayItems = false,
    rpFarm            = false,
    autoRebirth       = false,
    waitSkip          = false,
    skipCount         = 5,
    skipDestructive   = true,
    passDelay         = 0.005,
    noCapeStallWindow = 3,
    uiOpen            = true,  
    autoLoadLayout1       = false,
    sellForRebirth        = false,
    layout1Choice         = "Layout1",   -- which layout to load post-rebirth
    autoLoadLayout2       = false,
    layout2Choice         = "Layout2",   -- which layout to load as 2nd
    layout2TriggerType    = "Cost",      -- "Cost" | "Time"
    layout2TimeDelay      = 10,          -- seconds (1-60)
    autoLoadLayout3       = false,
    layout3Choice         = "Layout3",   -- which layout to load as 3rd
    fastLayout            = false,       -- always use the game's own layout loader
}

local activeBoxToggles = {}
for _, bt in ipairs(BOX_TYPES) do activeBoxToggles[bt] = true end

local OreStates     = {}
local EngineConns   = {}
local EngineStopped = false
local PostDelayLocks = {}

local Tycoons = workspace:FindFirstChild("Tycoons")

function startAntiAFK()
    local VirtualUser = game:GetService("VirtualUser")
    task.spawn(function()
        while lp.Parent do
            task.wait(240) -- 4 minutes
            pcall(function()
                VirtualUser:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
                task.wait(0.1)
                VirtualUser:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
            end)
            pcall(function()
                local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local cf = hrp.CFrame
                    hrp.CFrame = cf * CFrame.new(0.001, 0, 0)
                    task.wait(0.05)
                    hrp.CFrame = cf
                end
            end)
        end
    end)
end

startAntiAFK()
local MyFactory, MyOwner = nil, nil

function getMyFactory()
    local f, o = MyFactory, MyOwner
    if f and o and f.Parent and o.Parent and o.Value == lp.Name then return f end
    MyFactory, MyOwner = nil, nil
    if not Tycoons or not Tycoons.Parent then Tycoons = workspace:FindFirstChild("Tycoons") end
    if not Tycoons then return nil end
    for _, t in ipairs(Tycoons:GetChildren()) do
        local owner = t:FindFirstChild("Owner")
        if owner and owner.Value == lp.Name then
            MyFactory, MyOwner = t, owner
            return t
        end
    end
    return nil
end

function getOreContainer()
    local factory = getMyFactory()
    if not factory then return nil, nil end
    local dp = workspace:FindFirstChild("DroppedParts")
    if not dp then return nil, nil end
    return dp:FindFirstChild(factory.Name), factory
end

function isValidOre(ore, factoryName)
    if not ore or not ore.Parent then return false end
    if not ore:IsA("BasePart") then return false end
    if string.find(ore.Name, "[Cc][Oo][Aa][Ll]") then return false end
    if not ore:FindFirstChild("Cash") then return false end
    local owner = ore:GetAttribute("Owner")
    if owner and factoryName then return owner == factoryName end
    return true
end
UPGRADE_PART_PRIORITY = { "Upgrade", "Upgrader", "Cannon", "Beam", "Trigger", "Touch", "Scan", "Scanner", "Sensor" }
SKIP_PART_NAMES = { Conv=true, HitBox=true, Hitbox=true, hitbox=true, Conveyor=true, conveyor=true }

function findUpgradePart(item)
    local model = item:FindFirstChildOfClass("Model") or item
    for _, name in ipairs(UPGRADE_PART_PRIORITY) do
        local p = model:FindFirstChild(name)
        if p and p:IsA("BasePart") and p.CanTouch then return p end
    end
    for _, c in ipairs(model:GetChildren()) do
        if c:IsA("BasePart") and c.CanTouch and not SKIP_PART_NAMES[c.Name] then return c end
    end
    for _, name in ipairs(UPGRADE_PART_PRIORITY) do
        local p = item:FindFirstChild(name, true)  -- recursived
        if p and p:IsA("BasePart") and p.CanTouch and not SKIP_PART_NAMES[p.Name] then return p end
    end
    local hb = item:FindFirstChild("HitBox", true) or item:FindFirstChild("Hitbox", true)
    if hb and hb:IsA("BasePart") then return hb end
    return nil
end

function revalidateTrigger(rec)
    local tp = rec.TriggerPart
    if tp and tp.Parent then return tp end
    if rec.Model and rec.Model.Parent then
        local fresh = findUpgradePart(rec.Model)
        if fresh then rec.TriggerPart = fresh; return fresh end
    end
    return nil
end
function findFurnaceSellPart(item)
    local dbEntry = MHFurnace(item)
    local target  = dbEntry and dbEntry.SellPart or "Lava"
    local model   = item:FindFirstChildOfClass("Model") or item
    local sp = model:FindFirstChild(target)
    if sp and sp:IsA("BasePart") then return sp end
    local lower = target:lower()
    for _, c in ipairs(model:GetChildren()) do
        if c:IsA("BasePart") and c.Name:lower() == lower then return c end
    end
    local mini = model:FindFirstChild("MiniLava")
    if mini and mini:IsA("BasePart") then return mini end
    local found = item:FindFirstChild(target, true)
    if found and found:IsA("BasePart") then return found end
    return nil
end
TP_OFFSET   = Vector3.new(0, 0.5, 0)
CELL_OFFSET = Vector3.new(0, 0.6, 0)

function oreRawSet(ore, cf)
    ore.CFrame = cf
    ore.AssemblyLinearVelocity  = Vector3.zero
    ore.AssemblyAngularVelocity = Vector3.zero
end

function oreSet(ore, cf)
    return (pcall(oreRawSet, ore, cf))
end

function tpOre(ore, part)
    if not ore or not ore.Parent then return false end
    if not part or not part.Parent then return false end
    return oreSet(ore, part.CFrame + TP_OFFSET)
end

local INSTA_SELL_VALUE = 1e303


function formatScientific(value)
    if type(value) ~= "number" then return "0" end
    if value == 0 then return "0" end
    return string.format("%.3e", value)
end

-- Fifty-odd multipliers overflow a double, but the route is a pure product,
-- so the logarithm still carries the exact exponent.
function formatSciLog(logValue)
    if type(logValue) ~= "number" or logValue ~= logValue then return "0" end
    local e = math.floor(logValue)
    local m = 10 ^ (logValue - e)
    if m >= 10 then m, e = m / 10, e + 1 end
    return string.format("%.3fe+%d", m, e)
end

local DVGui = nil

-- One reusable reading surface: every "what am I missing" answer goes here
-- instead of a notification that vanishes before you can read it.
function DV_Dialog(title, subtitle, rows, opts)
    opts = opts or {}
    if type(subtitle) == "table" then
        local parts = {}
        for _, chip in ipairs(subtitle) do
            if type(chip) == "table" then
                if chip.text then parts[#parts + 1] = tostring(chip.text) end
            elseif chip ~= nil then
                parts[#parts + 1] = tostring(chip)
            end
        end
        subtitle = table.concat(parts, "  ·  ")
    end
    if DVGui then DVGui:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "DV_Dialog"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    -- Sit above anything already on screen, including the hub window, instead
    -- of trusting a fixed order that another ScreenGui can outbid.
    local pgui = lp:WaitForChild("PlayerGui")
    -- The hub itself lives in the protected UI layer, which always renders over
    -- PlayerGui no matter the DisplayOrder. Parent into the same layer so the
    -- dialog can actually sit above it.
    local container = pgui
    if type(gethui) == "function" then
        local hidden = gethui()
        if hidden then container = hidden end
    end
    local top = 10000
    for _, g in ipairs(container:GetChildren()) do
        if g:IsA("ScreenGui") and g.Name ~= "DV_Dialog" then
            top = math.max(top, g.DisplayOrder)
        end
    end
    -- DisplayOrder is a signed 32-bit int; +100 past 2^31-1 wraps negative and
    -- sinks the dialog under every other GUI, so clamp instead.
    gui.DisplayOrder = math.min(top + 100, 2147483000)
    gui.Parent = container
    DVGui = gui

    -- full-screen scrim: dims the game and swallows clicks so nothing behind
    -- the sheet can be pressed while it is open
    local scrim = Instance.new("TextButton")
    scrim.Name = "Scrim"
    scrim.Size = UDim2.new(1, 0, 1, 0)
    scrim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    scrim.BackgroundTransparency = 0.55
    scrim.BorderSizePixel = 0
    scrim.AutoButtonColor = false
    scrim.Text = ""
    scrim.Active = true
    scrim.Modal = true
    scrim.Parent = gui

    local card = Instance.new("Frame")
    card.Name = "Card"
    card.Size = UDim2.new(0, 540, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.Position = UDim2.new(0.5, -270, 0.5, 0)
    card.AnchorPoint = Vector2.new(0, 0.5)
    card.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
    card.BorderSizePixel = 0
    card.Active = true
    card.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(64, 68, 82)
    stroke.Transparency = 0.45
    stroke.Thickness = 1
    stroke.Parent = card

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 22)
    pad.PaddingRight = UDim.new(0, 22)
    pad.PaddingTop = UDim.new(0, 18)
    pad.PaddingBottom = UDim.new(0, 18)
    pad.Parent = card

    local stack = Instance.new("UIListLayout")
    stack.Padding = UDim.new(0, 8)
    stack.SortOrder = Enum.SortOrder.LayoutOrder
    stack.Parent = card

    local function label(order, text, size, color, bold)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, size)
        l.BackgroundTransparency = 1
        l.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
        l.TextSize = size
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextColor3 = color
        l.Text = text
        l.LayoutOrder = order
        l.Parent = card
        return l
    end

    local eyebrow = label(1, opts.eyebrow or "MISSING MATERIALS", 11, Color3.fromRGB(132, 138, 154))
    eyebrow.Text = string.upper(eyebrow.Text)

    local heading = label(2, title or "", 26, Color3.fromRGB(255, 255, 255), true)

    local chipRow = Instance.new("Frame")
    chipRow.Size = UDim2.new(1, 0, 0, 24)
    chipRow.BackgroundTransparency = 1
    chipRow.LayoutOrder = 3
    chipRow.Parent = card
    local chipLayout = Instance.new("UIListLayout")
    chipLayout.FillDirection = Enum.FillDirection.Horizontal
    chipLayout.Padding = UDim.new(0, 8)
    chipLayout.Parent = chipRow

    local chips = {}
    if type(subtitle) == "table" then
        for _, c in ipairs(subtitle) do chips[#chips + 1] = c end
    elseif subtitle and subtitle ~= "" then
        chips[1] = { text = subtitle, tone = "neutral" }
    end
    for _, c in ipairs(chips) do
        local chip = Instance.new("TextLabel")
        chip.AutomaticSize = Enum.AutomaticSize.X
        chip.Size = UDim2.new(0, 0, 1, 0)
        chip.BackgroundColor3 = c.tone == "warn" and Color3.fromRGB(58, 46, 20) or Color3.fromRGB(30, 32, 40)
        chip.BorderSizePixel = 0
        chip.Font = Enum.Font.GothamMedium
        chip.TextSize = 12
        chip.TextColor3 = c.tone == "warn" and Color3.fromRGB(235, 190, 90) or Color3.fromRGB(180, 188, 204)
        chip.Text = "  " .. tostring(c.text) .. "  "
        chip.Parent = chipRow
        local ccp = Instance.new("UIPadding")
        ccp.PaddingLeft = UDim.new(0, 8)
        ccp.PaddingRight = UDim.new(0, 8)
        ccp.Parent = chip
        local cc = Instance.new("UICorner")
        cc.CornerRadius = UDim.new(1, 0)
        cc.Parent = chip
    end

    local contentH = 0
    for _, row in ipairs(rows or {}) do
        if row.head then contentH = contentH + 28
        elseif row.bar then contentH = contentH + 32
        elseif row.check then contentH = contentH + 30
        else contentH = contentH + 26 end
    end

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 0, math.clamp(contentH, 40, 420))
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.CanvasSize = UDim2.new(0, 0, 0, contentH)
    scroll.LayoutOrder = 4
    scroll.Parent = card

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 6)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = scroll

    local order = 0
    local shortTotal, shortKinds = 0, 0
    for _, row in ipairs(rows or {}) do
        order = order + 1
        if row.head then
            local h = Instance.new("TextLabel")
            h.Size = UDim2.new(1, 0, 0, 22)
            h.BackgroundTransparency = 1
            h.Font = Enum.Font.GothamMedium
            h.TextSize = 11
            h.TextXAlignment = Enum.TextXAlignment.Left
            h.TextColor3 = Color3.fromRGB(132, 138, 154)
            h.Text = string.upper(row.head)
            h.LayoutOrder = 100 + order
            h.Parent = scroll
        elseif row.bar then
            shortKinds = shortKinds + 1
            local have = tonumber(row.have) or 0
            local need = math.max(1, tonumber(row.need) or 1)
            local frac = math.clamp(have / need, 0, 1)
            shortTotal = shortTotal + math.max(0, need - have)

            local line = Instance.new("Frame")
            line.Size = UDim2.new(1, 0, 0, 26)
            line.BackgroundTransparency = 1
            line.LayoutOrder = 100 + order
            line.Parent = scroll

            local name = Instance.new("TextLabel")
            name.Size = UDim2.new(0, 130, 1, 0)
            name.BackgroundTransparency = 1
            name.Font = Enum.Font.GothamMedium
            name.TextSize = 14
            name.TextXAlignment = Enum.TextXAlignment.Left
            name.TextColor3 = Color3.fromRGB(226, 231, 240)
            name.Text = tostring(row.label)
            name.Parent = line

            local barBg = Instance.new("Frame")
            barBg.Size = UDim2.new(1, -220, 0, 6)
            barBg.Position = UDim2.new(0, 140, 0.5, -3)
            barBg.BackgroundColor3 = Color3.fromRGB(36, 38, 46)
            barBg.BorderSizePixel = 0
            barBg.Parent = line
            local bbc = Instance.new("UICorner")
            bbc.CornerRadius = UDim.new(1, 0)
            bbc.Parent = barBg

            local fill = Instance.new("Frame")
            fill.Size = UDim2.new(frac, 0, 1, 0)
            fill.BackgroundColor3 = frac >= 1 and Color3.fromRGB(90, 210, 130) or Color3.fromRGB(170, 110, 250)
            fill.BorderSizePixel = 0
            fill.Parent = barBg
            local fc = Instance.new("UICorner")
            fc.CornerRadius = UDim.new(1, 0)
            fc.Parent = fill

            local delta = Instance.new("TextLabel")
            delta.Size = UDim2.new(0, 70, 1, 0)
            delta.Position = UDim2.new(1, -70, 0, 0)
            delta.BackgroundTransparency = 1
            delta.Font = Enum.Font.GothamBold
            delta.TextSize = 14
            delta.TextXAlignment = Enum.TextXAlignment.Right
            delta.TextColor3 = Color3.fromRGB(240, 120, 120)
            delta.Text = row.right or ("-" .. math.max(0, need - have))
            delta.Parent = line
        elseif row.check then
            local line = Instance.new("Frame")
            line.Size = UDim2.new(1, 0, 0, 24)
            line.BackgroundTransparency = 1
            line.LayoutOrder = 100 + order
            line.Parent = scroll

            local name = Instance.new("TextLabel")
            name.Size = UDim2.new(1, -90, 1, 0)
            name.BackgroundTransparency = 1
            name.Font = Enum.Font.GothamMedium
            name.TextSize = 14
            name.TextXAlignment = Enum.TextXAlignment.Left
            name.TextColor3 = Color3.fromRGB(190, 198, 212)
            name.Text = tostring(row.label)
            name.Parent = line

            local ok = Instance.new("TextLabel")
            ok.Size = UDim2.new(0, 90, 1, 0)
            ok.Position = UDim2.new(1, -90, 0, 0)
            ok.BackgroundTransparency = 1
            ok.Font = Enum.Font.GothamMedium
            ok.TextSize = 13
            ok.TextXAlignment = Enum.TextXAlignment.Right
            ok.TextColor3 = Color3.fromRGB(90, 205, 125)
            ok.Text = row.right or "Enough"
            ok.Parent = line
        else
            local t = Instance.new("TextLabel")
            t.Size = UDim2.new(1, 0, 0, 20)
            t.BackgroundTransparency = 1
            t.Font = Enum.Font.Code
            t.TextSize = 13
            t.TextXAlignment = Enum.TextXAlignment.Left
            t.TextColor3 = row.tone == "bad" and Color3.fromRGB(240, 130, 130)
                or row.tone == "good" and Color3.fromRGB(140, 220, 150)
                or row.tone == "head" and Color3.fromRGB(120, 200, 255)
                or Color3.fromRGB(214, 221, 232)
            t.Text = row.text or tostring(row)
            t.LayoutOrder = 100 + order
            t.Parent = scroll
        end
    end

    local footerRow = Instance.new("Frame")
    footerRow.Size = UDim2.new(1, 0, 0, 36)
    footerRow.BackgroundTransparency = 1
    footerRow.LayoutOrder = 999
    footerRow.Parent = card

    local footer = Instance.new("TextLabel")
    footer.Size = UDim2.new(1, -110, 1, 0)
    footer.BackgroundTransparency = 1
    footer.Font = Enum.Font.GothamMedium
    footer.TextSize = 13
    footer.TextXAlignment = Enum.TextXAlignment.Left
    footer.TextColor3 = Color3.fromRGB(190, 198, 212)
    footer.Text = opts.footer or (shortKinds > 0 and
        string.format("%d short across %d materials", shortTotal, shortKinds) or "")
    footer.Parent = footerRow

    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 90, 0, 32)
    close.Position = UDim2.new(1, -90, 0, 2)
    close.BackgroundColor3 = Color3.fromRGB(32, 34, 42)
    close.BorderSizePixel = 0
    close.Font = Enum.Font.GothamBold
    close.TextSize = 14
    close.TextColor3 = Color3.fromRGB(235, 240, 248)
    close.Text = "Close"
    close.Parent = footerRow
    local clc = Instance.new("UICorner")
    clc.CornerRadius = UDim.new(0, 8)
    clc.Parent = close
    close.MouseButton1Click:Connect(function() gui:Destroy() end)

    return gui
end

local INV_CACHE = { t = -100, data = nil }

-- Newest update: FetchInventory returns string keys -> {Quantity = n}.
-- Normalise once so every planner sees id -> count.
local function normalizeInventory(raw)
    local out = {}
    if type(raw) ~= "table" then return out end
    for id, rec in pairs(raw) do
        local n = 0
        if type(rec) == "number" then
            n = rec
        elseif type(rec) == "table" then
            n = tonumber(rec.Quantity or rec.quantity or rec.Count or rec.count
                or rec.Amount or rec.amount or rec.Value or rec.value) or 0
        end
        local key = tonumber(id)
        out[key or id] = n
    end
    return out
end

function LC_Inventory(force)
    local now = os.clock()
    if not force and INV_CACHE.data and now - INV_CACHE.t < 20 then return INV_CACHE.data end
    local ok, raw = pcall(function() return Net.FetchInventory:Invoke() end)
    if ok and type(raw) == "table" then
        INV_CACHE.data = normalizeInventory(raw)
        INV_CACHE.t = now
        return INV_CACHE.data
    end
    return INV_CACHE.data or {}
end

local OWNED_CACHE = {}

-- HasItem is the only reliable count source; FetchInventory is keyed by
-- something that is not the item id. Cache it so repeat plans are instant.
function LC_Owned(id, force)
    local now = os.clock()
    local hit = OWNED_CACHE[id]
    if not force and hit and now - hit.t < 20 then return hit.n end
    local ok, res = pcall(function() return Net.HasItem:Invoke(id) end)
    local n = (ok and type(res) == "number") and res or 0
    OWNED_CACHE[id] = { n = n, t = now }
    return n
end

function getOreCash(ore)
    if not ore or not ore.Parent then return nil end
    local c = ore:FindFirstChild("Cash")
    if not c then return nil end
    local value = c.Value
    if type(value) ~= "number" then return nil end
    return value
end


function oreIsAtMaxValue(ore)
    local cash = getOreCash(ore)

    return cash ~= nil and cash >= INSTA_SELL_VALUE
end

function getRoutePriority(entry)
    local loop = entry.Loopability

    if loop == "Unlimited" and entry.CapValue then
        return 1
    elseif loop == "Multi" then
        return 2
    elseif loop == "No" then
        return 3
    elseif loop == "Unlimited" then
        return 4
    end

    return 99
end

FIRST = {
    ["Angel's Blessing"] = 1,
    ["Ore Magnifier"] = 2,
    ["Astral Predictor"] = 3,
}

LAST = {
    ["Radioactive Refiner"] = 1,
    ["Ooftopian Refiner"] = 2,
    ["Flaming Ore Scanner"] = 3,
    ["Portable Flamethrower"] = 4,
    ["⭐ Ye Olde Hades' Palace ⭐"] = 5,
    ["Deadly Spore"] = 5,
}
-- Effects are one name on most machines and a list on multi-effect ones
-- (Wild Spore clears fire, poison and radioactive at once). Treat both shapes
-- the same so a machine that clears several effects never breaks the route.
local function effectLabel(effects)
    if type(effects) == "string" then return effects end
    if type(effects) ~= "table" then return nil end
    local out = {}
    for _, effect in ipairs(effects) do
        if type(effect) == "string" then out[#out + 1] = effect end
    end
    if #out == 0 then return nil end
    return table.concat(out, "/")
end

local function killerIn(effects)
    if type(effects) == "string" then effects = { effects } end
    if type(effects) ~= "table" then return nil end
    for _, effect in ipairs(effects) do
        if type(effect) == "string" and STATUS_KILLS[effect:lower()] then return effect end
    end
    return nil
end

local function applyEffects(tags, effects, on)
    if type(effects) == "string" then effects = { effects } end
    if type(effects) ~= "table" then return end
    for _, effect in ipairs(effects) do
        if type(effect) == "string" and effect ~= "" then tags[effect:lower()] = on end
    end
end

-- Lineage: a placed fusion/evolution makes its own ingredients redundant.
-- FusionReq holds component item ids as child names, RebornId is the item an
-- evolution consumes, and Tier orders them (30 reborn, 31 fusion, 32 evolved).
local ITEM_BY_ID = {}
do
    for _, m in ipairs(RS.Items:GetChildren()) do
        local id = m:GetAttribute("ItemId")
        if not id then
            local idv = m:FindFirstChild("ItemId")
            id = idv and idv.Value
        end
        if id then ITEM_BY_ID[id] = m end
    end
end

local LAST_SUPPRESSED = {}

local function defTier(id)
    local m = ITEM_BY_ID[id]
    local t = m and m:FindFirstChild("Tier")
    return t and t.Value or 0
end

local function defComponents(id)
    local out = {}
    local m = ITEM_BY_ID[id]
    if not m then return out end
    local fr = m:FindFirstChild("FusionReq")
    if fr then
        for _, c in ipairs(fr:GetChildren()) do
            local cid = tonumber(c.Name)
            if cid then out[#out + 1] = cid end
        end
    end
    local rb = m:FindFirstChild("RebornId")
    if rb and type(rb.Value) == "number" and rb.Value > 0 then out[#out + 1] = rb.Value end
    return out
end

-- id -> id that supersedes it. Only a strictly higher tier suppresses, so two
-- copies of the same machine never cancel each other out.
local function buildSuppressed(factory)
    local placed = {}
    for _, m in ipairs(factory:GetChildren()) do
        if m:IsA("Model") then
            local id = itemIdOf(m)
            if id then placed[id] = true end
        end
    end
    local suppressed = {}
    for id in pairs(placed) do
        for _, cid in ipairs(defComponents(id)) do
            if cid ~= id and placed[cid] and defTier(id) > defTier(cid) then
                suppressed[cid] = id
            end
        end
    end
    return suppressed
end

function detectUpgraders(factory)
    local byName = {}
    local teslaList = {}
    local educationList = {}

    local suppressed = buildSuppressed(factory)
    LAST_SUPPRESSED = suppressed

    for _, item in ipairs(factory:GetChildren()) do
        if not item:IsA("Model") then
            continue
        end

        local placedId = itemIdOf(item)
        if placedId and suppressed[placedId] then
            continue
        end

        local dbEntry, dbKey = MHUpgrader(item)
        if not dbEntry then
            continue
        end

        local tp = findUpgradePart(item)
        if not tp then
            continue
        end

        if dbEntry.IsTesla then
            table.insert(teslaList, {
                Name = dbKey,
                Model = item,
                TriggerPart = tp,
                DB = dbEntry
            })

            continue
        end

        local flag = dbEntry.SpecialFlag
        if flag == "launched_only" or flag == "coal_required" then
            continue
        end

        local isEducation = EDUCATION_UPGRADERS[dbKey] == true

        local rec = {
            Name            = dbKey,
            Model           = item,
            TriggerPart     = tp,
            Loopability     = dbEntry.Loopability,
            CapValue        = dbEntry.CapValue,
            FloorValue      = dbEntry.FloorValue,
            MaxUses         = dbEntry.MaxUses,
            MinInterval     = dbEntry.MinInterval,
            SpecialFlag     = dbEntry.SpecialFlag,
            Multiplier      = dbEntry.Multiplier,
            IsAdditive      = dbEntry.IsAdditive,
            EffMultOverride = dbEntry.EffMultOverride,
            PostDelay       = dbEntry.PostDelay,
            CleanUnlimited  = dbEntry.CleanUnlimited,
            AppliesEffect   = dbEntry.AppliesEffect,
            ClearsEffect    = dbEntry.ClearsEffect,
            ResetIncompatible = RESET_LOCKED[dbKey] == true or dbEntry.NotResettable == true,
            Conditional     = CONDITIONAL[dbKey],
            DestroyChance   = dbEntry.DestroyChance,
            ExplodeChance   = dbEntry.ExplodeChance,
            DestroysUnless  = dbEntry.DestroysUnless,
            LoopUnsafe      = dbEntry.LoopUnsafe,
            IsDestroyer     = dbEntry.DestroysOre,
        }

        if isEducation and not State.usePostDelayItems then
            -- Reserved for the single pre-sell touch: kept out of the cycles
            -- but still returned so the route can place it before the furnace.
            table.insert(educationList, rec)
        else
            if not byName[dbKey] then
                byName[dbKey] = {}
            end
            table.insert(byName[dbKey], rec)
        end
    end

    local names = {}

    for name in pairs(byName) do
        table.insert(names, name)
    end

    table.sort(names, function(a, b)
        if FIRST[a] and not FIRST[b] then
            return true
        end

        if FIRST[b] and not FIRST[a] then
            return false
        end

        if FIRST[a] and FIRST[b] then
            return FIRST[a] < FIRST[b]
        end
        if LAST[a] and not LAST[b] then
            return false
        end

        if LAST[b] and not LAST[a] then
            return true
        end

        if LAST[a] and LAST[b] then
            return LAST[a] < LAST[b]
        end
        local ra = getRoutePriority(byName[a][1])
        local rb = getRoutePriority(byName[b][1])

        if ra ~= rb then
            return ra < rb
        end
        if ra == 1 then
            local ca = byName[a][1].CapValue or 0
            local cb = byName[b][1].CapValue or 0

            if ca ~= cb then
                return ca < cb
            end
        end

        return a < b
    end)

    local normalList = {}

    for _, name in ipairs(names) do
        for _, rec in ipairs(byName[name]) do
            table.insert(normalList, rec)
        end
    end

    return normalList, teslaList, educationList
end

function detectBestEducationUpgrader(factory)
    local best, bestMult = nil, -math.huge
    for _, item in ipairs(factory:GetChildren()) do
        if not item:IsA("Model") then continue end
        local db, dbKey = MHUpgrader(item)
        if not db or not EDUCATION_UPGRADERS[dbKey] then continue end
        if not db then continue end
        local tp = findUpgradePart(item)
        if not tp then continue end
        local mult = db.Multiplier or 1.0
        if mult > bestMult then
            bestMult = mult
            best = {
                Name       = dbKey,
                Model      = item,
                TriggerPart = tp,
                Multiplier = mult,
                PostDelay  = db.PostDelay,
            }
        end
    end
    return best
end

function runEducationUpgraderNoWait(ore, snap)
    if not ore or not ore.Parent then return end
    local best = snap and snap.bestEdu
    if not best then return end
    local tp = revalidateTrigger(best)
    if not tp then return end
    tpOre(ore, tp)
    task.wait(0.3)
end

function detectBestFurnace(factory, preferRP, cellOnly)
    local best, bestScore = nil, -math.huge
    for _, item in ipairs(factory:GetChildren()) do
        if not item:IsA("Model") then continue end
        local dbEntry, dbKey = MHFurnace(item)
        if not dbEntry then continue end
        -- cellOnly mode: must have CellOnly flag
        if cellOnly and not dbEntry.CellOnly then continue end
        -- normal mode: skip CellOnly furnaces
        if not cellOnly and not preferRP and dbEntry.CellOnly then continue end
        local sellPart = findFurnaceSellPart(item)
        if not sellPart then continue end
        local score
        if preferRP then
            if not dbEntry.IsRPFurnace and dbEntry.Type ~= "Research" then continue end
            score = dbEntry.RPPerOre or 0
        else
            score = dbEntry.CashMult or 0
        end
        if score > bestScore then
            bestScore = score
            best = { Item=item, SellPart=sellPart, Name=dbKey, DB=dbEntry }
        end
    end
    return best
end


-- ── route summary: one line per step, values in scientific notation ──
MINES = {
["'Ol Faithful"]={kind="mine",oreValue=40000000,rate=0.5,oreSize="1x1x1",material="Corroded Metal",cellCompatible=true,size="6x4",rebornProof=true,tier="Vintage"},
["Ambrosia Mine"]={kind="mine",oreValue=495000000,rate=1,oreSize="0.7x0.7x0.7",material="Granite",cellCompatible=true,size="3x4",tier="Legendary"},
["Apollium Mine"]={kind="mine",oreValue=1000000000000,rate=1.5151515151515151,oreSize="1x1x1",material="Neon",cellCompatible=false,size="10x10",rebornProof=true,tier="Advanced Reborn"},
["Arachnid Mine"]={kind="mine",oreValue=500000,oreSize="1x1x1",material="Fabric",cellCompatible=true,size="4x6",rebornProof=true,sacrificeProof=true,conditional=true,tier="CollectibleHalloween"},
["Atomium Mine"]={kind="mine",oreValue=3500000000,rate=3.3333333333333335,oreSize="1x1x1",material="Neon",cellCompatible=false,size="3x3",rebornProof=true,tier="Reborn"},
["Atomyke Mine"]={kind="mine",oreValue=20000000000000,rate=3.3333333333333335,oreSize="1x1x1",material="Neon",cellCompatible=false,size="10x9",rebornProof=true,tier="Evolved Reborn"},
["Autumn Breeze"]={kind="mine",oreValue=0,rate=0.3333333333333333,oreSize="1.3x1.3x1.3",material="Grass",cellCompatible=true,size="6x5",rebornProof=true,sacrificeProof=true,tier="ExoticAutumn"},
["Basic Iron Mine"]={kind="mine",oreValue=2,rate=0.5,oreSize="1x1x1",material="Plastic",size="3x2",tier="Common"},
["Bazingium Mine"]={kind="mine",oreValue=2,rate=0.5,oreSize="1x1x1",material="Plastic",cellCompatible=true,size="3x4",rebornProof=true,sacrificeProof=true,tier="Redeemed"},
["Berezium Mine"]={kind="mine",oreValue=3000,rate=1,oreSize="1x1x1",material="Pebble",cellCompatible=true,size="9x6",rebornProof=true,sacrificeProof=true,tier="Collectible"},
["Bismuth Mine"]={kind="mine",oreValue=45000,rate=0.25,oreSize="0.8x0.8x0.8",material="Corroded Metal",cellCompatible=true,size="4x4",tier="Super Rare"},
["Boomite Mine"]={kind="mine",oreValue=5000000,oreSize="1x1x1",material="Granite",cellCompatible=true,size="4x5",rebornProof=true,conditional=true,tier="Vintage"},
["Breech Loader"]={kind="mine",oreValue=90000000000,rate=5,oreSize="1x1x1",material="Neon",cellCompatible=false,size="4x4",rebornProof=true,tier="Reborn"},
["Carat Carrot Mine"]={kind="mine",oreValue=1,oreSize="2x2x2",material="Foil",cellCompatible=true,size="4x4",rebornProof=true,sacrificeProof=true,tier="CollectibleEaster"},
["Clovium Mine"]={kind="mine",oreValue=444000,rate=1,oreSize="1x1x1",material="Cobblestone",cellCompatible=true,size="2x3",rebornProof=true,sacrificeProof=true,tier="CollectibleClover"},
["Coal Mine"]={kind="mine",oreValue=0,rate=0.3333333333333333,oreSize="1x1x1",material="Slate",cellCompatible=true,size="2x2",tier="Common"},
["Copper Mine"]={kind="mine",oreValue=20,rate=0.42857142857142855,oreSize="1x1x1",material="Slate",cellCompatible=true,size="5x2",tier="Common"},
["Crucible Iron Mine"]={kind="mine",oreValue=2,rate=0.6666666666666666,oreSize="1x1x1",material="Plastic",cellCompatible=true,size="3x2",tier="Common"},
["Crystal Mine"]={kind="mine",oreValue=35,rate=0.3333333333333333,oreSize="1x1x1",material="Glass",cellCompatible=true,size="3x2",tier="Uncommon"},
["Cupcakium Mine"]={kind="mine",oreValue=10000,rate=1,oreSize="1x1x1",material="Sand",cellCompatible=true,size="5x4",rebornProof=true,sacrificeProof=true,tier="CollectibleBirthday"},
["Dabium Mine"]={kind="mine",oreValue=12,size="2x2",tier="Fabled"},
["Darkmatter Mine"]={kind="mine",oreValue=14000000,rate=0.5,oreSize="0.5x0.5x0.5",material="Glass",cellCompatible=true,size="3x3",tier="Legendary"},
["Darkseedium Mine"]={kind="mine",oreValue=1000000,rate=1.25,oreSize="1x1x1",material="Granite",cellCompatible=true,size="8x10",rebornProof=true,sacrificeProof=true,tier="CollectibleHalloween"},
["Deluxe Santa's Workshop"]={kind="mine",oreValue=500000000,rate=2,oreSize="1.3x1.3x1.3",material="Sand",cellCompatible=false,size="6x5",rebornProof=true,sacrificeProof=true,tier="ExoticHolidays"},
["Diamond Breech Loader"]={kind="mine",oreValue=1000000000000000.0,rate=5,oreSize="1.5x1.5x1.5",material="Foil",cellCompatible=true,size="7x6",rebornProof=true,tier="Reborn Fusion"},
["Diamond Mine"]={kind="mine",oreValue=500,rate=0.5,oreSize="0.7x0.7x0.7",material="Foil",cellCompatible=true,size="3x3",tier="Uncommon"},
["Dimension Extractor"]={kind="mine",oreValue=30000000000000,rate=5,oreSize="1x1x1",material="Neon",cellCompatible=false,size="10x10",rebornProof=true,tier="Evolved Reborn"},
["Doge Chad Mine"]={kind="mine",oreValue=100000,rate=0.3333333333333333,oreSize="1x1x1",material="Sandstone",cellCompatible=true,size="4x2",rebornProof=true,sacrificeProof=true,tier="Redeemed"},
["Draconicglass Mine"]={kind="mine",oreValue=1e+17,manual=true,oreSize="1x1x1",material="Neon",cellCompatible=true,size="8x8",rebornProof=true,conditional=true,tier="Evolved Reborn"},
["Dragonglass Mine"]={kind="mine",oreValue=4000000000,manual=true,oreSize="1x1x1",material="Granite",cellCompatible=true,size="5x3",rebornProof=true,conditional=true,tier="Reborn"},
["Emerald Mine"]={kind="mine",oreValue=4000,rate=0.4,oreSize="1.5x1.5x1.5",material="Foil",cellCompatible=true,size="3x3",tier="Rare"},
["Fire Mine"]={kind="mine",oreValue=700,rate=0.25,oreSize="1x1x1",material="Granite",cellCompatible=false,size="2x3",rebornProof=true,tier="Quest"},
["Firecrystal Excavator"]={kind="mine",oreValue=1000000,rate=0.3333333333333333,oreSize="2x2x2",material="Pebble",cellCompatible=true,size="5x4",tier="Legendary"},
["Firecrystal Mine"]={kind="mine",oreValue=473000,rate=0.3333333333333333,oreSize="1x1x1",material="Glass",cellCompatible=true,size="3x2",tier="Legendary"},
["Firework Mine"]={kind="mine",oreValue=1000,rate=1,oreSize="1x1x1",material="Foil",cellCompatible=true,size="5x4",rebornProof=true,sacrificeProof=true,tier="Collectible"},
["Fool's Gold Mine"]={kind="mine",oreValue=100000,rate=0.5,oreSize="1x1x1",material="Foil",cellCompatible=true,size="2x3",rebornProof=true,conditional=true,tier="Exotic"},
["Frostarium Mine"]={kind="mine",oreValue=1000,rate=0.25,oreSize="1x1x1",cellCompatible=true,size="4x3",conditional=true,tier="Super Rare"},
["Frosty the Snowmine"]={kind="mine",oreValue=20000000,rate=1.3333333333333333,oreSize="1x1x1",material="Ice",cellCompatible=true,size="6x6",rebornProof=true,sacrificeProof=true,tier="CollectibleHolidays"},
["Gargantium Mine"]={kind="mine",oreValue=1e+22,rate=3.3333333333333335,oreSize="1.8x1.8x1.8",material="Neon",cellCompatible=true,size="12x10",rebornProof=true,tier="Enchanted"},
["Giftium Mine"]={kind="mine",oreValue=5000,rate=1,oreSize="1x1x1",material="Granite",cellCompatible=true,size="4x4",rebornProof=true,sacrificeProof=true,tier="CollectibleHolidays"},
["Gingerbreadium Mine"]={kind="mine",oreValue=1000000,manual=true,oreSize="2x2x2",material="Concrete",cellCompatible=false,size="12x9",rebornProof=true,sacrificeProof=true,tier="ExoticHolidays"},
["Gold Excavator"]={kind="mine",oreValue=250,manual=true,oreSize="2x2x2",material="Foil",cellCompatible=true,size="3x4",tier="Common"},
["Gold Mine"]={kind="mine",oreValue=75,rate=0.5,oreSize="1x1x1",material="Foil",cellCompatible=true,size="3x2",tier="Rare"},
["Goliath Gumball Machine"]={kind="mine",oreValue=450000,rate=1.3333333333333333,oreSize="1.3x1.3x1.3",material="Plastic",cellCompatible=false,size="5x5",rebornProof=true,sacrificeProof=true,tier="ExoticHalloween"},
["Grimstruct"]={kind="mine",oreValue=1,material="",size="9x11",rebornProof=true,tier="Advanced Reborn"},
["Hades' Fang"]={kind="mine",oreValue=10000000,oreSize="1.2x1.2x1.2",material="Granite",cellCompatible=true,size="3x5",rebornProof=true,sacrificeProof=true,tier="ExoticHalloween"},
["Havium Mine"]={kind="mine",oreValue=2e+22,rate=3.3333333333333335,oreSize="1x1x1",material="Neon",cellCompatible=false,size="6x7",rebornProof=true,tier="Superstitious"},
["Hyper Mine"]={kind="mine",oreValue=500,rate=0.5,oreSize="1x1x1",material="Neon",cellCompatible=true,size="3x2",rebornProof=true,sacrificeProof=true,tier="Collectible"},
["Ice Mine"]={kind="mine",oreValue=500,rate=0.3333333333333333,oreSize="1x1x1",material="Marble",cellCompatible=false,size="2x3",rebornProof=true,tier="Quest"},
["Incendium Mine"]={kind="mine",oreValue=8000000000000000.0,rate=7.692307692307692,oreSize="1x1x1",material="Neon",cellCompatible=false,size="7x3",tier="Slipstream"},
["Incendium Mine/Renegade"]={kind="mine",oreValue=8000000000000,rate=7.692307692307692,oreSize="1x1x1",material="Neon",cellCompatible=false,size="7x3",rebornProof=true,tier="Renegade"},
["Industrial Ancient Gourd"]={kind="mine",oreValue=250000000,oreSize="1.5x1.5x1.5",material="Glass",cellCompatible=true,size="6x5",rebornProof=true,sacrificeProof=true,tier="CollectibleHalloween"},
["Industrial Coal Mine"]={kind="mine",oreValue=0,manual=true,oreSize="1x1x1",material="Slate",size="3x5",rebornProof=true,tier="Fabled"},
["Industrial Diamond Mine"]={kind="mine",oreValue=8000,manual=true,oreSize="1x1x1",material="Foil",cellCompatible=true,size="4x6",tier="Rare"},
["Industrial Firecrystal Mine"]={kind="mine",oreValue=15000000,manual=true,oreSize="1x1x1",material="Glass",cellCompatible=true,size="5x3",rebornProof=true,tier="Reborn"},
["Industrial Firegem Quarry"]={kind="mine",oreValue=3200000000,manual=true,oreSize="1x1x1",material="Smooth plastic",cellCompatible=true,size="9x4",rebornProof=true,tier="Evolved Reborn"},
["Industrial Giftium Mine"]={kind="mine",oreValue=20000000,manual=true,oreSize="1x1x1",material="Granite",cellCompatible=true,size="6x7",rebornProof=true,sacrificeProof=true,tier="CollectibleHolidays"},
["Industrial Gold Mine"]={kind="mine",oreValue=100000,manual=true,oreSize="1x1x1",material="Foil",cellCompatible=true,size="3x5",rebornProof=true,sacrificeProof=true,tier="CollectibleClover"},
["Industrial Osmium Mine"]={kind="mine",oreValue=27000,manual=true,oreSize="1x1x1",material="Pebble",cellCompatible=true,size="5x4",tier="Super Rare"},
["Industrial Rainbow Mine"]={kind="mine",manual=true,oreSize="1x1x1",material="Plastic",cellCompatible=false,size="5x3",rebornProof=true,tier="Premium"},
["Industrial Ruby Mine"]={kind="mine",oreValue=650,manual=true,oreSize="1x1x1",material="Marble",cellCompatible=true,size="3x5",tier="Rare"},
["Iron Excavator"]={kind="mine",oreValue=20,manual=true,oreSize="2x2x2",material="Plastic",cellCompatible=true,size="3x3",tier="Common"},
["Iron Flakes Mine"]={kind="mine",oreValue=1,rate=5,material="Foil",cellCompatible=true,size="2x4",rebornProof=true,sacrificeProof=true,combos={"Iron Mine"},tier="Redeemed"},
["Iron Mine"]={kind="mine",oreValue=15000000,rate=0.5,oreSize="1x1x1",material="Plastic",cellCompatible=false,size="2x3",rebornProof=true,tier="Relic"},
["Iron Mine-Chan"]={kind="mine",oreValue=50000,rate=0.2,oreSize="1x1x1",material="Plastic",cellCompatible=true,size="2x4",tier="Rare"},
["King Gold Mine"]={kind="mine",oreValue=10000000000000,rate=0.1,oreSize="3.2x3.2x3.2",material="Metal",cellCompatible=true,size="7x8",rebornProof=true,tier="Rare Reborn"},
["Lightning Mine"]={kind="mine",oreValue=300,oreSize="1x1x1",material="Slate",cellCompatible=false,size="2x3",rebornProof=true,tier="Quest"},
["Massive Diamond Drill"]={kind="mine",oreValue=500000000000,rate=2,oreSize="4x4x4",material="Foil",cellCompatible=true,size="8x10",rebornProof=true,tier="Evolved Reborn"},
["Massive Diamond Mine"]={kind="mine",oreValue=10000000,rate=0.1,oreSize="3x3x3",material="Foil",cellCompatible=true,size="7x7",rebornProof=true,tier="Reborn"},
["Massive Gold Mine"]={kind="mine",oreValue=20700,rate=0.08333333333333333,oreSize="3x3x3",material="Foil",cellCompatible=true,size="6x5",tier="Super Rare"},
["Massive Iron Mine"]={kind="mine",oreValue=10000,rate=0.1111111111111111,oreSize="4x4x4",material="Plastic",cellCompatible=true,size="6x4",tier="Rare"},
["Mithril Mine"]={kind="mine",oreValue=75000,rate=0.5,oreSize="0.8x0.8x0.8",material="Marble",cellCompatible=true,size="6x5",tier="Epic"},
["Newtonium Excavator"]={kind="mine",oreValue=45000000000000,manual=true,oreSize="2x2x2",material="Foil",cellCompatible=false,size="6x10",rebornProof=true,tier="Evolved Reborn"},
["Newtonium Mine"]={kind="mine",oreValue=100000000,rate=2,oreSize="1x1x1",material="Foil",cellCompatible=false,size="7x4",rebornProof=true,tier="Reborn"},
["Nightmare"]={kind="mine",oreValue=5000000000,oreSize="1x1x1",material="Corroded Metal",cellCompatible=true,size="4x9",rebornProof=true,sacrificeProof=true,tier="ExoticHalloween"},
["Ninja Diamond Mine"]={kind="mine",oreValue=1000,rate=0.5,oreSize="0.7x0.7x0.7",material="Foil",cellCompatible=true,size="4x3",rebornProof=true,tier="Premium"},
["Noobite Mine"]={kind="mine",oreValue=10000,rate=0.5,oreSize="1x1x1",cellCompatible=true,size="4x3",rebornProof=true,tier="Vintage"},
["Oblivion Weaver"]={kind="mine",oreValue=144000000000,rate=0.25,oreSize="0.8x0.8x0.8",material="Neon",cellCompatible=false,size="10x6",tier="Slipstream"},
["Oblivion Weaver/Renegade"]={kind="mine",oreValue=144000000000,oreSize="0.8x0.8x0.8",material="Neon",cellCompatible=false,size="13x10",rebornProof=true,conditional=true,tier="Renegade"},
["Onyx Mine"]={kind="mine",oreValue=5400000000000,rate=2,oreSize="0.6x0.6x0.6",material="Foil",cellCompatible=true,size="5x6",tier="Divine"},
["Opal Mine"]={kind="mine",oreValue=8000,rate=0.5,oreSize="1x1x1",material="Corroded Metal",cellCompatible=true,size="5x5",tier="Super Rare"},
["Orbital Antimatter Uplink"]={kind="mine",oreValue=100000,rate=0.5,oreSize="1x1x1",material="Glass",cellCompatible=true,size="3x4",tier="Unique"},
["Orbital Christmas Uplink"]={kind="mine",oreValue=1000000,rate=3.3333333333333335,oreSize="1x1x2",material="Concrete",cellCompatible=true,size="6x8",rebornProof=true,sacrificeProof=true,tier="CollectibleHolidays"},
["Osmium Excavator"]={kind="mine",oreValue=40000,manual=true,oreSize="2x2x2",material="Granite",cellCompatible=true,size="5x4",tier="Super Rare"},
["Osmium Mine"]={kind="mine",oreValue=15000,rate=0.3333333333333333,oreSize="1x1x1",material="Pebble",cellCompatible=true,size="4x2",tier="Super Rare"},
["Painite Mine"]={kind="mine",oreValue=56000,rate=0.8333333333333334,oreSize="1x1x1",material="Granite",cellCompatible=true,size="3x5",tier="Unique"},
["Palladium Drill"]={kind="mine",oreValue=100000000000,rate=10,oreSize="2x2x2",material="Neon",size="8x9",rebornProof=true,tier="Advanced Reborn"},
["Parasitic Invader"]={kind="mine",oreValue=3000000,rate=0.5,oreSize="1.5x1.5x1.5",material="Granite",cellCompatible=true,size="9x10",rebornProof=true,sacrificeProof=true,tier="ExoticHalloween"},
["Phasecursor Mine"]={kind="mine",oreValue=900000000000000,rate=2,oreSize="1x1x1",material="Neon",cellCompatible=true,size="9x6",rebornProof=true,tier="Advanced Fusion"},
["Pilotite Mine"]={kind="mine",oreValue=2800000000,rate=1.4285714285714286,oreSize="1x1x1",material="Neon",cellCompatible=false,size="6x4",rebornProof=true,tier="Reborn"},
["Platinum Mine"]={kind="mine",oreValue=200,rate=0.5,oreSize="1.2x1.2x1.2",material="Granite",cellCompatible=true,size="3x2",tier="Common"},
["Plutonium Excavator"]={kind="mine",oreValue=20000,manual=true,oreSize="2x2x2",material="Granite",cellCompatible=true,size="4x4",tier="Rare"},
["Plutonium Mine"]={kind="mine",oreValue=5500,rate=0.5,oreSize="1x1x1",material="Granite",cellCompatible=true,size="4x5",tier="Rare"},
["Precursor Mine"]={kind="mine",oreValue=1000000000,rate=0.5,oreSize="1x1x1",material="Neon",cellCompatible=true,size="6x8",rebornProof=true,tier="Advanced Reborn"},
["Pulsar Octagnium Mine"]={kind="mine",manual=true,oreSize="1x1x1",material="Neon",size="5x5",tier="Slipstream"},
["Pulsar Octagnium Mine/Renegade"]={kind="mine",manual=true,oreSize="1x1x1",material="Neon",size="5x5",rebornProof=true,tier="Renegade"},
["Pumpkinite Mine"]={kind="mine",oreValue=4500000,manual=true,oreSize="1.5x1.5x1.5",material="Foil",cellCompatible=false,size="13x13",rebornProof=true,sacrificeProof=true,tier="ExoticHalloween"},
["Radium Mine"]={kind="mine",oreValue=1000,rate=1.25,oreSize="1x1x1",material="Foil",cellCompatible=true,size="4x4",rebornProof=true,tier="Premium"},
["Rainbonite Mine"]={kind="mine",oreValue=1000000000,rate=1,oreSize="1x1x1",material="Neon",cellCompatible=false,size="7x4",tier="Mythic"},
["Remote Ambrosia Mine"]={kind="mine",oreValue=800000000,manual=true,oreSize="1.4x1.4x1.4",material="Granite",cellCompatible=true,size="5x4",tier="Legendary"},
["Remote Diamond Mine"]={kind="mine",oreValue=1000,manual=true,oreSize="1.2x1.2x1.2",material="Foil",cellCompatible=true,size="4x3",tier="Uncommon"},
["Remote Iron Mine"]={kind="mine",oreValue=10,manual=true,oreSize="1.4x1.4x1.4",material="Plastic",cellCompatible=true,size="3x2",tier="Common"},
["Remote Opal Mine"]={kind="mine",oreValue=16000,manual=true,oreSize="0.8x0.8x0.8",material="Corroded Metal",cellCompatible=true,size="5x4",tier="Super Rare"},
["Remote Osmium Mine"]={kind="mine",oreValue=25000,manual=true,oreSize="1.2x1.2x1.2",material="Pebble",cellCompatible=true,size="4x2",tier="Super Rare"},
["Santa's Rage"]={kind="mine",oreValue=0,oreSize="1x1x1",material="Slate",cellCompatible=true,size="4x4",rebornProof=true,sacrificeProof=true,tier="ExoticHolidays"},
["Scorpium Mine"]={kind="mine",oreValue=1000000,rate=1,oreSize="1x1x1",material="Neon",cellCompatible=false,size="4x4",rebornProof=true,tier="Reborn"},
["Scorponyte Mine"]={kind="mine",oreValue=100000000000,rate=1,oreSize="1x1x1",material="Granite",cellCompatible=false,size="6x7",rebornProof=true,tier="Evolved Reborn"},
["Silicon Excavator"]={kind="mine",oreValue=20,manual=true,oreSize="1x1x1",material="Fabric",cellCompatible=true,size="4x3",rebornProof=true,tier="Quest"},
["Silver Mine"]={kind="mine",oreValue=5,rate=1.4285714285714286,oreSize="1x1x1",material="Plastic",cellCompatible=true,size="3x3",tier="Common"},
["Solarium Mine"]={kind="mine",oreValue=100000000000000,rate=0.5,oreSize="1.5x1.5x1.5",material="Neon",cellCompatible=false,size="9x14",rebornProof=true,tier="Advanced Evolution"},
["Spinnerite Mine"]={kind="mine",oreValue=500,rate=0.3333333333333333,oreSize="1.5x1.5x1.5",material="Plastic",cellCompatible=false,size="3x2",rebornProof=true,tier="Premium"},
["Spitfire Iron Mine"]={kind="mine",oreValue=2,rate=3,oreSize="1x1x1",material="Plastic",cellCompatible=true,size="3x2",rebornProof=true,tier="Premium"},
["SpookApocalypse-Ω"]={kind="mine",oreValue=1e+20,rate=4,oreSize="1.1x1.1x1.1",material="Neon",cellCompatible=true,size="12x16",rebornProof=true,tier="Superstitious"},
["SpookBaron-360,000"]={kind="mine",oreValue=500000000,material="Neon",cellCompatible=true,size="8x8",rebornProof=true,sacrificeProof=true,tier="ExoticHalloween"},
["Spookboy-500"]={kind="mine",oreValue=1000000,oreSize="1x1x1",material="Neon",cellCompatible=false,size="4x4",rebornProof=true,sacrificeProof=true,tier="CollectibleHalloween"},
["Spookmaster-5000"]={kind="mine",oreValue=950000000,rate=3.3333333333333335,oreSize="1x1x1",material="Plastic",cellCompatible=false,size="4x4",rebornProof=true,sacrificeProof=true,tier="ExoticHalloween"},
["SpookPhantasm-EX"]={kind="mine",oreValue=400000000000,rate=0.6666666666666666,oreSize="1.25x1.25x1.25",material="Ice",cellCompatible=true,size="12x9",rebornProof=true,sacrificeProof=true,tier="ExoticHalloween"},
["SpookStorm-X"]={kind="mine",oreValue=1000000,rate=0.5,oreSize="1x1x1",material="Plastic",cellCompatible=true,size="7x11",rebornProof=true,sacrificeProof=true,tier="ExoticHalloween"},
["Spooky Coal Mine"]={kind="mine",oreValue=0,rate=1,oreSize="1x1x1",material="Slate",size="2x2",rebornProof=true,sacrificeProof=true,tier="CollectibleHalloween"},
["Stellarite Mine"]={kind="mine",oreValue=1000000000000,rate=3.0303030303030303,oreSize="1x1x1",material="Neon",cellCompatible=true,size="4x6",rebornProof=true,conditional=true,tier="Rare Reborn"},
["Super Swintite Mine"]={kind="mine",oreValue=2500000,rate=0.6666666666666666,oreSize="2x2x2",material="Pebble",cellCompatible=false,size="7x9",rebornProof=true,sacrificeProof=true,tier="ExoticHalloween"},
["Superunobtainium Mine"]={kind="mine",oreValue=30000,oreSize="1x1x1",material="Foil",cellCompatible=false,size="4x4",rebornProof=true,sacrificeProof=true,tier="Contraband"},
["Swag Iron Mine"]={kind="mine",oreValue=2,rate=0.5,oreSize="1x1x1",size="3x2",rebornProof=true,tier="Fabled"},
["Swintite Mine"]={kind="mine",oreValue=300,manual=true,oreSize="1.2x1.2x1.2",material="Slate",cellCompatible=true,size="3x3",rebornProof=true,tier="Quest"},
["Symcorpium Mine"]={kind="mine",oreValue=250000000000000,rate=1,oreSize="1x1x1",material="Neon",cellCompatible=false,size="6x4",rebornProof=true,tier="Reborn Fusion"},
["Symmetrium Mine"]={kind="mine",oreValue=100000000,oreSize="1x1x1",material="Neon",cellCompatible=true,size="5x4",rebornProof=true,conditional=true,tier="Reborn"},
["Symmetryte Mine"]={kind="mine",oreValue=100000000000,rate=1,oreSize="1x1x1",material="Neon",cellCompatible=true,size="6x8",rebornProof=true,tier="Evolved Reborn"},
["Tankium Mine"]={kind="mine",oreValue=4000000,oreSize="1x1x1",material="Metal",cellCompatible=true,size="7x8",rebornProof=true,sacrificeProof=true,tier="Eggxotic"},
["The Abomination"]={kind="mine",oreValue=10000000,rate=2.25,material="Neon",cellCompatible=true,size="5x8",rebornProof=true,tier="Reborn"},
["The Daegelart"]={kind="mine",oreValue=420000000000000,rate=1,oreSize="1x1x1",material="Neon",cellCompatible=false,size="8x11",rebornProof=true,tier="Evolved Reborn"},
["Tiny Iron Mine"]={kind="mine",oreValue=100000,rate=1,oreSize="12x12x12",material="Plastic",cellCompatible=true,size="30x20",rebornProof=true,tier="Fabled"},
["Triple Coal Mine"]={kind="mine",oreValue=0,rate=0.75,oreSize="1x1x1",material="Slate",cellCompatible=true,size="2x2",rebornProof=true,tier="Premium"},
["Trollium Mine"]={kind="mine",oreValue=300000000,rate=30,oreSize="1x1.5x1",material="Foil",cellCompatible=true,size="4x4",rebornProof=true,tier="Exotic"},
["Twitchite Mine"]={kind="mine",oreValue=10000000,rate=1.4285714285714286,oreSize="1x1x1",material="Sand",size="6x6",rebornProof=true,sacrificeProof=true,tier="ExoticTwitch"},
["Unobtainium Mine"]={kind="mine",rate=0.5,oreSize="1x1x1",material="Foil",cellCompatible=false,size="3x2",rebornProof=true,conditional=true,tier="Premium"},
["Uranium Mine"]={kind="mine",oreValue=3000,rate=0.3333333333333333,oreSize="1.3x1.3x1.3",material="Granite",cellCompatible=true,size="3x4",tier="Uncommon"},
["V-tolite Mine"]={kind="mine",oreValue=2000000000000,rate=1.4285714285714286,oreSize="1x1x1",material="Neon",cellCompatible=false,size="11x14",rebornProof=true,tier="Evolved Reborn"},
["Wubium Mine"]={kind="mine",oreValue=300000000,rate=30,oreSize="1x1.5x1",material="Glass",cellCompatible=true,size="4x4",rebornProof=true,sacrificeProof=true,tier="ExoticSummer"},
["Yuge Iron Mine"]={kind="mine",oreValue=1000,rate=0.5,oreSize="0.2x0.2x0.2",material="Plastic",cellCompatible=true,size="1x1",rebornProof=true,sacrificeProof=true,tier="Redeemed"},
["Yunium Mine"]={kind="mine",oreValue=25000000,oreSize="1x1x1",material="Neon",cellCompatible=true,size="3x2",rebornProof=true,conditional=true,tier="Reborn"},
["Yuntonium Mine"]={kind="mine",oreValue=1000000000000,rate=1.6666666666666667,oreSize="1.2x1.2x1.2",material="Neon",cellCompatible=false,size="9x4",rebornProof=true,tier="Reborn Fusion"},
["Yuttrium Mine"]={kind="mine",oreValue=1000000000000,rate=4,oreSize="2x2x2",material="Neon",cellCompatible=true,size="7x5",rebornProof=true,tier="Evolved Reborn"},
}

-- Status semantics from the game database: which effects kill an ore
-- outright, how long they take, and whether a cleaner can remove them.
STATUS_INFO = {
    ["Fire"] = {kills=true, timer=4, clearable=true},
    ["Frostbite"] = {kills=true, timer=4, clearable=true},
    ["Poison"] = {kills=true, timer=4, clearable=true},
    ["Radioactive"] = {kills=true, timer=6, clearable=true},
    ["Sparkles"] = {kills=false, clearable=true},
    ["Smoking"] = {kills=false, clearable=true},
    ["Wet"] = {kills=false},
    ["Anti-Gravity"] = {kills=false, clearable=true},
    ["Education"] = {kills=true, timer=5},
    ["Draedon"] = {kills=true, timer=10},
    ["Void"] = {kills=true},
    ["Plague"] = {kills=true, timer=5, clearable=true},
    ["Shield"] = {kills=false},
    ["Fireproof"] = {kills=false},
    ["Poison Immunity"] = {kills=false},
    ["Radioactive Immunity"] = {kills=false},
    ["Frostbite Immunity"] = {kills=false},
    ["Plague Immunity"] = {kills=false},
    ["Hydrophobic"] = {kills=false},
    ["Gaia's Blessing"] = {kills=false},
    ["Chaotic Fire"] = {kills=false},
    ["Nova"] = {kills=false},
    ["Nova-Schro"] = {kills=false, timer=5},
    ["Golden"] = {kills=false},
    ["Stasis"] = {kills=false},
    ["Eternal Flame"] = {kills=false},
    ["Replicator Banned"] = {kills=false},
    ["Teleporter Banned"] = {kills=false},
    ["DON Banned"] = {kills=false},
    ["Swag Factor"] = {kills=false},
    ["Pulsar"] = {kills=false, clearable=true},
}

STATUS_KILLS = {}
for name, info in pairs(STATUS_INFO) do
    if info.kills then STATUS_KILLS[name:lower()] = true end
end

-- Effects, placement value and destruction risk from the game database.
-- Kept as a separate table so curated HP values in UPGRADER_DB/FURNACE_DB
-- below are never overwritten, only filled in where they are missing.
ITEM_DATA = {
    ["100M Upgrader"] = {mpu=1.4142, un=2, note="Pumpkin patch and pumpkin hero used before great pumpkin"},
    ["Abominable Screaming Tree"] = {mpu=1.3845, un=7, note="X8 is max during day, x11,5 max during night (if ores are 255 blue)"},
    ["Acorn Avenue"] = {mpu=1.2457, un=5},
    ["Alien Relic"] = {mpu=2, un=2},
    ["Ancient Coliseum"] = {mpu=1.5849, un=5, note="Assuming ore value is decimal"},
    ["Ancient Temple"] = {mpu=1.3195, un=5, note="Average multiplier (either x3 or x5) though it's likely a decimal either way"},
    ["Angel's Blessing"] = {ap={"Sparkles"}},
    ["Angel's Cake"] = {cn=true},
    ["Anti-Gravity Scanner"] = {mpu=1.4475, un=4, note="average account for 76% hit chance"},
    ["Arcane Lightning"] = {mpu=1.9257, un=6},
    ["Aromatic Holidays"] = {mpu=1.4422, un=3},
    ["Astral Setter"] = {mpu=2.0476, un=4, note="Using average multiplier, without accounting gaia or chaosrealm"},
    ["Atlantic Monolith"] = {mpu=1.3195, un=5},
    ["Atlantic Monument"] = {mpu=1.5334, un=6},
    ["Atmospheric Steamwork"] = {mpu=1.5525, un=6},
    ["Auroral Metropolis"] = {mpu=1.5838, un=7, note="25x for frozen ores, 10x (1,39) for normal ores"},
    ["Auroral Wings"] = {mpu=1.4142, un=2},
    ["Azure Purifier"] = {mpu=1.3687, un=7},
    ["Azure Refiner"] = {mpu=1.5874, un=3},
    ["Azure Spore"] = {mpu=1.71, un=6},
    ["BUNZILLA"] = {ap={"Fire"}},
    ["Banana Split Upgrader"] = {mpu=1.5314, un=4},
    ["Banana Sundae Refiner"] = {mpu=1.4422, un=6},
    ["Behemoth Snowflake"] = {mpu=1.3161, un=4, note="Gives ore frozen effect"},
    ["Big Alberto"] = {mpu=1.71, un=6},
    ["Big Bad Blaster"] = {ap={"Fire"}, dc=0.1, ec=0.2727, d=true, lu=true},
    ["Big Bertha"] = {mpu=3.1623, un=2, note="Hits at 22 units after cannon"},
    ["Big Bunny"] = {ap={"Fire"}},
    ["Big Candy Cane"] = {mpu=1.4142, un=2},
    ["Big Fluxxus"] = {mpu=2.361, un=12, note="using 2 Big Fluxxus (first time 100x, 2nd time 300x)"},
    ["Big Fungus"] = {mpu=2.1169, un=6},
    ["Birthday Upgrader"] = {mpu=1.3161, un=4},
    ["Blazing Agriculture"] = {mpu=1.4913, un=6, note="At max multiplier"},
    ["Blazing Annihilator"] = {rm={"Fireproof","Frostbite","Wet"}},
    ["Blizzard Predictor"] = {mpu=1.2434, un=4, note="Average multiplier"},
    ["Blueberry Pie"] = {mpu=1.3797, un=5},
    ["Borker's Luxury Villa"] = {ap={"Fireproof"}},
    ["Brimstone Spires"] = {mpu=1.6307, un=8, note="Best scenario"},
    ["Bubonic Plague"] = {mpu=1.219, un=7},
    ["CONTRALAND"] = {mpu=1.4913, un=6, note="When masked man is not here, else x15 (1,57)"},
    ["CYBEGG9000"] = {ap={"Fire"}},
    ["Cactus Mirage"] = {mpu=1.3077, un=6},
    ["Candy Cane Cannon"] = {ap={"Fire"}},
    ["Candy Castle"] = {mpu=1.2009, un=6},
    ["Candy Corn Real Estate"] = {mpu=1.1029, un=6},
    ["Candy Refiner"] = {mpu=1.0488, un=2},
    ["Candycorn Refiner"] = {mpu=1.0878, un=4},
    ["Caramel Birthday Cake"] = {mpu=1.3511, un=9},
    ["Castle Bravo"] = {mpu=2.2209, un=6},
    ["Castle of Apocalypse"] = {mpu=1.3077, un=6},
    ["Chemical Refiner"] = {mpu=1.3831, un=6, note="Both upgraders hitting"},
    ["Chicken Legg Cookout"] = {mpu=1.3678, un=4},
    ["Chocolate Coater"] = {mpu=1.1696, un=3},
    ["Chocolate Cupcake"] = {mpu=1.4758, un=5},
    ["Citrus Enhancer"] = {mpu=1.3656, un=5},
    ["Clockwork"] = {mpu=1.71, un=3},
    ["Cooling Chamber"] = {mpu=1.8212, un=4, note="Flaming ore (7x overheated)"},
    ["Cosmic Device"] = {mpu=1.8988, un=4},
    ["Crystallized Engine"] = {mpu=1.4913, un=6},
    ["Crystallized System"] = {mpu=1.431, un=5},
    ["Deadly Spore"] = {mpu=1.6266, un=4},
    ["Delta Phantom"] = {mpu=2.1544, un=6, note="Regular multi (not worth using in faster setups)"},
    ["Deluxe Beehive"] = {mpu=1.8028, un=2},
    ["Demon Core"] = {mpu=1.4913, un=6},
    ["Desert Monument"] = {mpu=1.6703, un=5},
    ["Devil's Spore"] = {mpu=1.7212, un=6},
    ["Deviled Blaster"] = {ap={"Fire"}},
    ["Diamond Egg"] = {mpu=1.5811, un=2},
    ["Draedon's Gauntlet"] = {mpu=7.407, un=4, note="Uses ore hypernova + gargantium mine or core, TO ALL PEOPLE THAT SEE THIS DO NOT USE THIS SHITTY ITEM"},
    ["Dragon Blaster"] = {ap={"Fire"}, dc=0.09, ec=0.18, d=true, lu=true},
    ["Dragon Cake"] = {ap={"Fire"}},
    ["Dragon Cannon"] = {mpu=1.7188, un=5},
    ["Dreamer's Life"] = {mpu=2.8403, un=6, note="+50 per dreamers placed.  Unpowered = 125x   (shinies count seperately, so you can use 1 shiny dreamers might and 1 non-shiny dreamers might and itll count as 100x)"},
    ["Eerie Marsh"] = {mpu=1.2009, un=6, note="X4 at night, +3x to wet ores (max x7)"},
    ["Eggplosive Refiner"] = {mpu=1.4142, un=4, note="X10 (1,78) if the ore is boomite"},
    ["Empyrean Monument"] = {mpu=2.3051, un=6, note="Best scenario"},
    ["Enchanted Library"] = {mpu=2.125, un=6, note="Average multi including random chance for 1.8x and multiplier over time, and accounting Astral, temporal, and swag are used prior (+15x)"},
    ["Eternal Cake"] = {mpu=1.8612, un=4, note="Assuming red velvet portable is used prior, 8x otherwise."},
    ["Executive Pillars"] = {mpu=2.3452, un=2},
    ["Father of Freon"] = {mpu=1.4422, un=6},
    ["Festive Spirit"] = {mpu=1.3077, un=6},
    ["Final Eclipse Gate"] = {mpu=1.4301, un=8, note="10 at day 25 at night"},
    ["Firecrystallized System"] = {mpu=1.5285, un=6},
    ["Flaming Ore Scanner"] = {ap={"Fire"}},
    ["Flaming Schrodinger"] = {dc=0.25, ec=0.05, d=true, lu=true},
    ["Forsaken Battleground"] = {mpu=1.2457, un=5},
    ["Fractured Reality"] = {mpu=1.8988, un=4, note="Assuming you use angel's blessing to get sparkling ores"},
    ["Frank'n'Cupcake"] = {mpu=1.1067, un=4},
    ["Freon Bombarder"] = {ap={"Fireproof","Frostbite"}},
    ["Freon Sprayer"] = {rm={"Fire"}},
    ["Freon-Blast Upgrader"] = {rm={"Fire"}},
    ["Freshly Baked Upsidedown Pineapple Cake"] = {ap={"Wet"}},
    ["Frigid Dystopia"] = {mpu=1.5704, un=6},
    ["Frostbite Chamber"] = {mpu=1.3797, un=5},
    ["Frosted Refiner"] = {mpu=1.75, un=1, note="Non-resettable"},
    ["Frozen Eclipse"] = {mpu=1.6256, un=7},
    ["Garden of Gaia"] = {mpu=1.9019, un=7, note="Additionally, gaia's blessing will multiply the ore's value by x1.02 Every time its upgrade count is changed"},
    ["Gate of Eclipse"] = {mpu=1.3895, un=7, note="day 4x, night 10x"},
    ["Gator's Cove"] = {mpu=1.4953, un=4},
    ["Ghastly Graveyard"] = {mpu=1.3161, un=4},
    ["Ghosdeeri's Antidote"] = {mpu=1.431, un=5},
    ["Ghost Town"] = {mpu=1.2322, un=6},
    ["Ghoul Lagoon"] = {mpu=1.3286, un=6},
    ["Glass Butterfly"] = {mpu=2, un=3},
    ["Gloom Refiner"] = {mpu=1.4422, un=3},
    ["Grand Fruitcake"] = {mpu=1.2917, un=7},
    ["Grand Wafer"] = {mpu=1.1187, un=3},
    ["Grand Willow"] = {nr=true, nt=true},
    ["Grandfather Clockwork"] = {mpu=2.0154, un=4, note="Depends on the time (average taken)"},
    ["Gravitational Gearwork"] = {mpu=1.4758, un=5},
    ["Gummy Refiner"] = {mpu=1.2599, un=3},
    ["Hades' Palace"] = {mpu=1.7627, un=6, note="Best scenario"},
    ["Hanging Wreath"] = {mpu=1.5131, un=6},
    ["Heavenly Flux"] = {mpu=1.6266, un=4, note="Length = height in this case"},
    ["Honeycomb Solace"] = {mpu=1.3077, un=6},
    ["Hydraulic Duality Refiner"] = {mpu=1.71, un=3},
    ["Ice Crusher"] = {mpu=1.431, un=5},
    ["Igneous Lightning"] = {mpu=1.984, un=7},
    ["Illusions of Void"] = {mpu=1.3195, un=5, note="Average multi"},
    ["Industrial Skeletal Salvation"] = {mpu=1.219, un=7, note="Needs coal"},
    ["King Birthday Cake"] = {mpu=1.5445, un=9},
    ["King Darkseed"] = {mpu=1.2599, un=6},
    ["Legendary Peppermint"] = {mpu=1.9896, un=3, note="6-10x avg"},
    ["Lightningbolt Refiner"] = {dc=0.2, d=true, lu=true},
    ["Lollipop-inator"] = {mpu=1.75, un=1},
    ["Lucky Hat"] = {mpu=1.3803, un=5, note="Accounting random chance to 0x"},
    ["Macaroon Upgrader"] = {mpu=1.3161, un=4},
    ["Maintenance Supporter"] = {mpu=1.4953, un=4},
    ["Malicious Incubator"] = {ap={"Poison"}},
    ["Massive Quantum Diamond Cleaner"] = {mpu=1.5525, un=6},
    ["Meatball Sandwich"] = {mpu=2.1544, un=3},
    ["Meralin's Sorcery"] = {mpu=4.0461, un=7, note="Meralins before mask, including mask in mpu."},
    ["Methane Sky Fleet"] = {mpu=1.71, un=3, note="Elevation level 8+"},
    ["Midas Blaster"] = {ap={"Fire"}, dc=0.3333, ec=0.6667, d=true, lu=true},
    ["Mighty Sugar Cookie"] = {mpu=1.5912, un=5, note="Both fire and poison increase the multiplier by 20% (average taken)"},
    ["Mineral Wheel"] = {mpu=1.5651, un=4},
    ["Moai God"] = {mpu=1.6818, un=4},
    ["Molten Forge"] = {mpu=1.348, un=6},
    ["Mystical Thunder"] = {mpu=2.1361, un=6},
    ["Newtonic Corroder"] = {mpu=1.6266, un=4},
    ["Northern Lights"] = {ap={"Sparkles"}},
    ["Nuclear Chamber"] = {mpu=1.3427, un=4, note="Assuming ore is on fire, which is most likely the case"},
    ["Octopi Council"] = {ap={"Wet"}},
    ["One Million Upgrader"] = {mpu=2.1544, un=3, note="Retired item it's never coming back"},
    ["Ooftopian Refiner"] = {mpu=2.1398, un=6, note="150x at max multi, 96x is average"},
    ["Optic Origin"] = {mpu=2.1317, un=7, note="Basic daytime setting or nighttime with neon ores"},
    ["Ore Caramelizer"] = {mpu=1.0914, un=3},
    ["Ore Chainsaw"] = {mpu=1.4142, un=6},
    ["Ore Gielder"] = {mpu=1.3161, un=4},
    ["Ore Hypernova"] = {ap={"Sparkles"}, nr=true, nt=true},
    ["Ore Indoctrinator"] = {mpu=2.9551, un=6, note="Horrible time drawback unless used with garg (or garg core) + stardust illuminator"},
    ["Ore Memer"] = {mpu=1.7945, un=4, note="Average multiplier between 4 numbers, 7.77x (80%), 13.37x (14%), 36.0x (4%), 42.0x (2%)"},
    ["Ore Negator"] = {nr=true, nt=true},
    ["Ore Striker"] = {mpu=1.0699, un=6, note="Average multiplier, all effects: (1,5x, 2x, 3x, +1m, kill)"},
    ["Ore Supernova"] = {nr=true, nt=true},
    ["Ornament Blaster"] = {ap={"Fire"}},
    ["Overlord Device"] = {mpu=1.3895, un=7},
    ["Permafrost Refiner"] = {mpu=1.3161, un=4},
    ["Phase Bombarder"] = {mpu=1.5704, un=6},
    ["Phase Refiner"] = {mpu=1.4142, un=4},
    ["Pillars of Creation"] = {mpu=1.5334, un=6},
    ["Pineapple Refiner"] = {mpu=1.1892, un=4},
    ["Pizza Blaster"] = {mpu=1.2599, un=6},
    ["Pizza Bombarder"] = {mpu=1.3335, un=8},
    ["Plague Doctor"] = {mpu=1.3077, un=6},
    ["Plasma Scanner"] = {mpu=1.348, un=6},
    ["Portable Flamethrower"] = {ap={"Fire"}},
    ["Precision Refiner"] = {ap={"Fire"}},
    ["Present Refiner"] = {mpu=1.5874, un=3},
    ["Present Schrodinger"] = {mpu=1.259, un=4, note="Average multiplier"},
    ["Pumpkin Carriage"] = {mpu=1.3161, un=4},
    ["Pumpkin Hut"] = {mpu=1.2599, un=6},
    ["Pumpkin Pie Refiner"] = {mpu=1.1583, un=4},
    ["Pumpkin Spice Refiner"] = {mpu=1.165, un=6},
    ["Quantum Clockwork"] = {mpu=2.3403, un=4, note="this is for 3 reset. Works best at 19 units"},
    ["Quantum Ore Cleaner"] = {mpu=1.4142, un=4},
    ["Quantum Ore Polisher"] = {mpu=1.5157, un=5},
    ["Radio Tower"] = {nr=true, nt=true},
    ["Rainbow Refiner"] = {mpu=2, un=2},
    ["Reaper's Fortress"] = {mpu=1.8376, un=3, note="Average taken"},
    ["Red Velvet Cake"] = {mpu=1.4262, un=7},
    ["Robotic Enhancer"] = {mpu=1.5651, un=4},
    ["Royal Rabbit"] = {mpu=1.5314, un=4},
    ["Ruby Crystallizer"] = {mpu=2.1544, un=3},
    ["Sacred Totem"] = {mpu=1.3831, un=6},
    ["Sandshark"] = {ap={"Fire"}},
    ["Santa's Nice List"] = {mpu=1.3449, un=5},
    ["Santa's Workclock"] = {mpu=2.2361, un=2},
    ["Satellite Beam"] = {mpu=1.4422, un=3, note="Can be used below hydraulic items"},
    ["Saturated Catalyst"] = {mpu=1.3459, un=7},
    ["Schrodinger Chamber"] = {dc=0.25, ec=0.05, d=true, lu=true},
    ["Schrodinger Evaluator"] = {ap={"Sparkles"}, dc=0.25, ec=0.05, d=true, lu=true},
    ["Scorching Heat"] = {mpu=1.3797, un=5},
    ["Searing Heat"] = {mpu=1.4913, un=6, note="Ore has to be on fire or fireproof"},
    ["Shard City"] = {mpu=1.486, un=7, note="Max multi"},
    ["Shard Park"] = {mpu=1.4678, un=6, note="Highest multi"},
    ["Silkweaver"] = {mpu=1.3229, un=2},
    ["Skyliner Flux"] = {mpu=1.5874, un=3, note="Length = height in this case"},
    ["Smore Cake"] = {ap={"Fire"}},
    ["Snowflake Wheel"] = {mpu=1.5651, un=4},
    ["Soapy Refiner"] = {mpu=1.4422, un=3},
    ["Soaring Chopper"] = {mpu=1.4142, un=4},
    ["Solar Apocalypse"] = {mpu=1.4142, un=6},
    ["Son of Poison"] = {mpu=1.5131, un=6},
    ["Speggtral Rose"] = {mpu=1.3831, un=6},
    ["Spider Queen"] = {ap={"Poison"}, cn=true},
    ["Spires of Conquest"] = {mpu=1.2009, un=6},
    ["Spirit of Fire"] = {mpu=1.4678, un=6},
    ["Spooklord Device"] = {mpu=1.3205, un=7},
    ["Sporegg Hut"] = {mpu=1.351, un=5, note="2,75 multi if <10 upgrade tags"},
    ["Stardust Pulsar"] = {nr=true, nt=true},
    ["Stratospheric Refiner"] = {mpu=1.4142, un=4, note="Elevation level 11"},
    ["Strawberry Cake"] = {mpu=1.4678, un=6},
    ["Sugar Corroder"] = {mpu=1.1419, un=4},
    ["Suitopian Refiner"] = {lu=true},
    ["Swag City"] = {mpu=2.3875, un=6},
    ["Temporal Armageddon"] = {mpu=2.4495, un=4, note="Average time taken in a 3 reset setup (13 seconds)."},
    ["The Baron"] = {mpu=1.2636, un=8},
    ["The Beehive"] = {mpu=1.8708, un=2},
    ["The Boy"] = {ap={"Fire"}},
    ["The Catalyst"] = {mpu=1.2599, un=6},
    ["The Chaosrealm"] = {mpu=1.4422, un=6},
    ["The Cookinator"] = {mpu=1.1402, un=2},
    ["The Cornucopia"] = {mpu=2.885, un=6, note="Base 10x, each food item used after it gets a 1.5x boost, which when accounting for a max of 10 items, makes it 576x"},
    ["The Cosmic Tower"] = {nr=true, nt=true},
    ["The Crazy Hamburger"] = {mpu=1.1487, un=5},
    ["The Death Cap"] = {mpu=1.8859, un=8, note="With angels blessing for +20x multi, and soapy/atlantic for +10x multi"},
    ["The Demon"] = {mpu=1.3912, un=6, note="X8,5 if ores were upgraded by the ghosts from spookdemon"},
    ["The Dust Devil"] = {mpu=1.3774, un=4},
    ["The Final Upgrader"] = {nr=true, nt=true},
    ["The Guillotine"] = {mpu=1.2457, un=5},
    ["The Heartbreaker"] = {mpu=1.2573, un=12},
    ["The Holy Cheese"] = {mpu=1.5874, un=3},
    ["The Hourglass"] = {mpu=2.0314, un=8},
    ["The Ice Fortress"] = {mpu=1.2397, un=7},
    ["The Lord"] = {mpu=1.2599, un=6, note="X7 if ores were upgraded by the ghosts from spooklord"},
    ["The Master"] = {mpu=1.3696, un=6, note="Doesn't include +1x per spook mine"},
    ["The Phantasm"] = {mpu=1.6739, un=6, note="Daytime x20, nighttime x25"},
    ["The Pizzalyst"] = {mpu=2.2657, un=5},
    ["The Sporest"] = {mpu=1.5157, un=5},
    ["The Storm"] = {mpu=1.2917, un=7},
    ["The Trinity"] = {mpu=2.0052, un=6, note="Base Multiplier, 125x if a trinity item is used prior"},
    ["The Ultimate Sacrifice"] = {nr=true, nt=true},
    ["Time-Space Scrambler"] = {mpu=1.71, un=3},
    ["Toxic Schrodinger Evaluator"] = {ap={"Poison"}, ec=0.1667, d=true, lu=true},
    ["Toxic Waste Disposal"] = {cn=true},
    ["Transylvanian Refiner"] = {mpu=1.3572, un=6},
    ["Tropical Breeze"] = {mpu=2.4495, un=2},
    ["True Overlord Device"] = {mpu=1.9307, un=7},
    ["Tsar Bomba"] = {mpu=1.6307, un=8},
    ["Turbine Chamber"] = {mpu=1.661, un=6, note="Flaming ore (13x if overheated)"},
    ["Turtle Dignifier"] = {ap={"Shield","Wet"}},
    ["Twitch Scanner"] = {mpu=2.2361, un=2},
    ["Undead Assistance"] = {mpu=1.2247, un=2},
    ["Universal Collapse"] = {mpu=1.9064, un=6},
    ["Utopian Refiner"] = {ap={"Sparkles"}},
    ["Vampire Spore"] = {mpu=1.8212, un=4, note="vampire spore changes ore size"},
    ["Vanilla Scanner"] = {mpu=1.7321, un=2},
    ["Virtual Enchanter"] = {mpu=2.1411, un=5, note="Taking max multi"},
    ["Virtual Enhancer"] = {mpu=1.9744, un=5, note="Highest multi"},
    ["Virtual Gearwork"] = {mpu=1.7826, un=5, note="Taking average multi"},
    ["Vitamin C-Coater"] = {mpu=1.5651, un=4},
    ["Vortex Chamber"] = {mpu=1.4953, un=4},
    ["Vulcan's Destiny"] = {mpu=2.2209, un=6, note="Highest multi, not resettable"},
    ["Vulcan's Grasp"] = {mpu=1.9786, un=6, note="Highest multi, not resettable"},
    ["Vulcan's Wrath"] = {mpu=2.5873, un=6, note="Inefficient as it requires higher ore count, which can cause inconsistency in a setup"},
    ["Wholesome Skull Blaster"] = {mpu=1.2917, un=7},
    ["Wild Spore"] = {cn=true},
    ["Winter Snowflake"] = {mpu=1.71, un=3},
    ["Winterheart"] = {mpu=1.3161, un=4},
}

for name, x in pairs(ITEM_DATA) do
    local e = UPGRADER_DB[name] or FURNACE_DB[name]
    if e then
        if x.ap and not e.AppliesEffect then e.AppliesEffect = x.ap end
        if x.rm and not e.ClearsEffect then e.ClearsEffect = x.rm end
        if x.mpu then e.MPU = x.mpu end
        if x.un then e.Units = x.un end
        if x.note and x.note ~= "" then e.Note = x.note end
        if x.dc then e.DestroyChance = x.dc end
        if x.ec then e.ExplodeChance = x.ec end
        if x.d then e.DestroysOre = true end
        if x.lu then e.LoopUnsafe = true end
        if x.du then e.DestroysUnless = x.du end
        if x.nr then e.NotResettable = true end
        if x.cn then e.ClearsNegative = true end
        if x.ds then e.DestroysStatus = true end
        if x.nt then e.NoTesla = true end
    end
end

DESTROY_CHANCE = {
    ["Aether Schrodinger"] = 0.25,
    ["Assembly Unit"] = 1.0,
    ["Azure Refiner"] = 1.0,
    ["Big Bad Blaster"] = 0.1,
    ["Deceptive Sorcery"] = 0.05,
    ["Dragon Blaster"] = 0.09,
    ["Dragonglass Blaster"] = 0.1,
    ["Flaming Schrodinger"] = 0.25,
    ["Hydra Blaster"] = 0.1,
    ["Illuminator Evaluator"] = 0.25,
    ["Legendary Peppermint"] = 1.0,
    ["Lightningbolt Predictor"] = 0.2,
    ["Lightningbolt Refiner"] = 0.2,
    ["Mad Monstrous Melter"] = 0.3,
    ["Midas Blaster"] = 0.3333,
    ["Ore Destroyinator"] = 1.0,
    ["Ore Striker"] = 0.1,
    ["Present Schrodinger"] = 0.2,
    ["Schrodinger Chamber"] = 0.25,
    ["Schrodinger Evaluator"] = 0.25,
    ["Scorching Heat"] = 1.0,
    ["Super Schrodinger"] = 0.25,
    ["Tempest Refiner"] = 1.0,
    ["Toxic Schrodinger Evaluator"] = 1.0,
}

RESET_LOCKED = {
    ["Black Dwarf"] = true,
    ["Candy Castle"] = true,
    ["Candy Corn Real Estate"] = true,
    ["DECADE HAVEN CAKE"] = true,
    ["Daestrophe"] = true,
    ["Frank'n'Cupcake"] = true,
    ["Frostbite Chamber"] = true,
    ["Grand Willow"] = true,
    ["Lollipop-inator"] = true,
    ["Ore Hypernova"] = true,
    ["Ore Negator"] = true,
    ["Ore Nova"] = true,
    ["Ore Supernova"] = true,
    ["Present Schrodinger"] = true,
    ["Pumpkin Pie Refiner"] = true,
    ["Radio Tower"] = true,
    ["Santa's Nice List"] = true,
    ["Snowflake Wheel"] = true,
    ["Stardust Illuminator"] = true,
    ["Stardust Pulsar"] = true,
    ["Teddy Bear Stuffer"] = true,
    ["Tesla Refuter"] = true,
    ["Tesla Resetter"] = true,
    ["The Cosmic Tower"] = true,
    ["The Eternal Overseer"] = true,
    ["The Final Upgrader"] = true,
    ["The Ultimate Sacrifice"] = true,
    ["Void Drive"] = true,
    ["Void Star"] = true,
    ["Vulcan's Destiny"] = true,
    ["Vulcan's Grasp"] = true,
}

CONDITIONAL = {
    ["Abominable Screaming Tree"] = { avg = nil, chance = false, conditional = true },
    ["Advanced Ore Scanner"] = { avg = nil, chance = true, conditional = false },
    ["Aerogel Refiner"] = { avg = nil, chance = false, conditional = true },
    ["Aether Schrodinger"] = { avg = 3.84, chance = false, conditional = true },
    ["Aethereal Synthesizer"] = { avg = nil, chance = false, conditional = true },
    ["All Star Sundae"] = { avg = nil, chance = false, conditional = true },
    ["Ambrosia Garden"] = { avg = nil, chance = false, conditional = true },
    ["Ancient Coliseum"] = { avg = nil, chance = false, conditional = true },
    ["Ancient Magic"] = { avg = nil, chance = true, conditional = true },
    ["Ancient Temple"] = { avg = nil, chance = false, conditional = true },
    ["Angel's Blessing"] = { avg = nil, chance = false, conditional = true },
    ["Anguished Guardian of the Gate"] = { avg = nil, chance = false, conditional = true },
    ["Arachnid Mine"] = { avg = nil, chance = false, conditional = true },
    ["Arcane Lightning"] = { avg = nil, chance = false, conditional = true },
    ["Assembly Unit"] = { avg = nil, chance = false, conditional = true },
    ["Astral Predictor"] = { avg = nil, chance = true, conditional = true },
    ["Astral Setter"] = { avg = nil, chance = true, conditional = true },
    ["Aurora Borealis"] = { avg = nil, chance = false, conditional = true },
    ["Auroral Wings"] = { avg = nil, chance = false, conditional = true },
    ["Azure Spore"] = { avg = nil, chance = false, conditional = true },
    ["Bag of Stars"] = { avg = nil, chance = false, conditional = true },
    ["Berezaa Car Upgrader"] = { avg = nil, chance = false, conditional = true },
    ["Big Bad Blaster"] = { avg = nil, chance = true, conditional = false },
    ["Birthday Cake"] = { avg = nil, chance = false, conditional = true },
    ["Blazing Agriculture"] = { avg = nil, chance = true, conditional = true },
    ["Blind Justice"] = { avg = nil, chance = false, conditional = true },
    ["Blizzard Predictor"] = { avg = nil, chance = false, conditional = true },
    ["Blood Magic"] = { avg = nil, chance = false, conditional = true },
    ["Boomite Mine"] = { avg = nil, chance = false, conditional = true },
    ["Bouncy House!!!!111!!11!1"] = { avg = nil, chance = true, conditional = true },
    ["Breached Motherboard"] = { avg = nil, chance = false, conditional = true },
    ["Brimstone Spires"] = { avg = nil, chance = false, conditional = true },
    ["Burst Refiner"] = { avg = nil, chance = false, conditional = true },
    ["Burst Refiner/Renegade"] = { avg = nil, chance = false, conditional = true },
    ["CONTRALAND"] = { avg = nil, chance = true, conditional = true },
    ["Candy Cane Cannon"] = { avg = nil, chance = true, conditional = false },
    ["Candy Factory"] = { avg = nil, chance = true, conditional = false },
    ["Candy Refiner"] = { avg = nil, chance = false, conditional = true },
    ["Canis Processus"] = { avg = nil, chance = false, conditional = true },
    ["Carrot Village"] = { avg = nil, chance = false, conditional = true },
    ["Catalyzed Star"] = { avg = nil, chance = false, conditional = true },
    ["Clover Crunch"] = { avg = nil, chance = false, conditional = true },
    ["Clover Schrodinger"] = { avg = 3.25, chance = false, conditional = true },
    ["Coconut Drencher"] = { avg = nil, chance = false, conditional = true },
    ["Conqueror's Delusion"] = { avg = nil, chance = false, conditional = true },
    ["Cooling Chamber"] = { avg = nil, chance = false, conditional = true },
    ["DECADE HAVEN CAKE"] = { avg = nil, chance = true, conditional = true },
    ["DECADE HAVEN SPOOKMINE-5,256,000"] = { avg = nil, chance = true, conditional = true },
    ["DECADE HAVEN UPGRADER"] = { avg = nil, chance = false, conditional = true },
    ["Daestrophe"] = { avg = nil, chance = false, conditional = true },
    ["Deadly Spore"] = { avg = nil, chance = false, conditional = true },
    ["Deceptive Sorcery"] = { avg = 2.5, chance = false, conditional = true },
    ["Devil's Cake"] = { avg = nil, chance = false, conditional = true },
    ["Devil's Spore"] = { avg = nil, chance = true, conditional = true },
    ["Deviled Blaster"] = { avg = nil, chance = true, conditional = true },
    ["Digital Ore Cleaner"] = { avg = nil, chance = false, conditional = true },
    ["Doom Incarnate"] = { avg = nil, chance = false, conditional = true },
    ["Draconicglass Mine"] = { avg = nil, chance = false, conditional = true },
    ["Dragon Blaster"] = { avg = nil, chance = true, conditional = false },
    ["Dragon Cake"] = { avg = nil, chance = true, conditional = true },
    ["Dragonglass Blaster"] = { avg = nil, chance = true, conditional = false },
    ["Dragonglass Mine"] = { avg = nil, chance = false, conditional = true },
    ["Dreamcatcher"] = { avg = nil, chance = false, conditional = true },
    ["Dreamer's Anguish"] = { avg = nil, chance = false, conditional = true },
    ["Dreamer's Birthday Cake"] = { avg = nil, chance = true, conditional = true },
    ["Dreamer's Fright"] = { avg = nil, chance = true, conditional = false },
    ["Dreamer's Life"] = { avg = nil, chance = false, conditional = true },
    ["Dreamer's Nightmare"] = { avg = nil, chance = false, conditional = true },
    ["Dreamer's Terror"] = { avg = nil, chance = true, conditional = true },
    ["Eerie Marsh"] = { avg = nil, chance = false, conditional = true },
    ["Eggmerald Geode"] = { avg = nil, chance = true, conditional = true },
    ["Empyrean Monument"] = { avg = nil, chance = false, conditional = true },
    ["Enchanted Library"] = { avg = nil, chance = true, conditional = true },
    ["Esoteric Citadel"] = { avg = nil, chance = false, conditional = true },
    ["Eternal Cake"] = { avg = nil, chance = false, conditional = true },
    ["Ethereal Sanctuary"] = { avg = nil, chance = false, conditional = true },
    ["Excalibur"] = { avg = nil, chance = false, conditional = true },
    ["Fidget Spinner-ifier"] = { avg = nil, chance = false, conditional = true },
    ["Final Fabergé"] = { avg = nil, chance = true, conditional = false },
    ["Firecrystallized System"] = { avg = nil, chance = false, conditional = true },
    ["Flaming Schrodinger"] = { avg = 1.92, chance = false, conditional = true },
    ["Flying Dutchman"] = { avg = nil, chance = true, conditional = true },
    ["Fool's Gold Mine"] = { avg = nil, chance = false, conditional = true },
    ["Forsaken Battleground"] = { avg = nil, chance = true, conditional = true },
    ["Forsaken Cake"] = { avg = nil, chance = false, conditional = true },
    ["Fractured Reality"] = { avg = nil, chance = false, conditional = true },
    ["Freshly Baked Upsidedown Pineapple Cake"] = { avg = nil, chance = false, conditional = true },
    ["Friends Forever"] = { avg = nil, chance = false, conditional = true },
    ["Frostarium Mine"] = { avg = nil, chance = false, conditional = true },
    ["Frostbite Chamber"] = { avg = nil, chance = false, conditional = true },
    ["Frozen Eclipse"] = { avg = nil, chance = false, conditional = true },
    ["Ghost of Christmas Past"] = { avg = nil, chance = false, conditional = true },
    ["Gift Blaster"] = { avg = nil, chance = true, conditional = false },
    ["Gladiator's Fury"] = { avg = nil, chance = false, conditional = true },
    ["Glass Butterfly"] = { avg = nil, chance = true, conditional = false },
    ["Grand Fruitcake"] = { avg = nil, chance = true, conditional = false },
    ["Grand Willow"] = { avg = nil, chance = true, conditional = false },
    ["Gravitational Gyrocopter"] = { avg = nil, chance = false, conditional = true },
    ["Great Parasite"] = { avg = nil, chance = false, conditional = true },
    ["Green Tea Kettle"] = { avg = nil, chance = false, conditional = true },
    ["Hades' Palace"] = { avg = nil, chance = false, conditional = true },
    ["Heavenly Wisp"] = { avg = nil, chance = true, conditional = true },
    ["Hellish Bat Cookie"] = { avg = nil, chance = false, conditional = true },
    ["Holiday Street Refiner"] = { avg = nil, chance = false, conditional = true },
    ["Hungry Spirit"] = { avg = nil, chance = false, conditional = true },
    ["Hydra Blaster"] = { avg = nil, chance = true, conditional = true },
    ["Hydraulic Ramp Upgrader"] = { avg = nil, chance = true, conditional = false },
    ["Igneous Forge"] = { avg = nil, chance = false, conditional = true },
    ["Igneous Lightning"] = { avg = nil, chance = false, conditional = true },
    ["Illuminator Evaluator"] = { avg = 5.745, chance = false, conditional = true },
    ["Illusions of Void"] = { avg = nil, chance = false, conditional = true },
    ["Inflatable Party Upgrader"] = { avg = nil, chance = false, conditional = true },
    ["Interstellar Conqueror"] = { avg = nil, chance = true, conditional = false },
    ["Kappa Investor"] = { avg = nil, chance = false, conditional = true },
    ["King Darkseed"] = { avg = nil, chance = false, conditional = true },
    ["Large Ore Upgrader"] = { avg = nil, chance = false, conditional = true },
    ["Legendary Peppermint"] = { avg = nil, chance = true, conditional = true },
    ["Leggendary Black Hole"] = { avg = nil, chance = true, conditional = false },
    ["Lemon Land"] = { avg = nil, chance = false, conditional = true },
    ["Lepretron"] = { avg = nil, chance = true, conditional = true },
    ["Lightningbolt Predictor"] = { avg = nil, chance = true, conditional = true },
    ["Lightningbolt Refiner"] = { avg = nil, chance = true, conditional = true },
    ["Lord of the Apocalypse"] = { avg = nil, chance = false, conditional = true },
    ["Lucky Hat"] = { avg = nil, chance = true, conditional = true },
    ["Lucky Seven's Cake"] = { avg = 7.231, chance = true, conditional = true },
    ["MONSTER TRUCKER!"] = { avg = nil, chance = false, conditional = true },
    ["Mad Monstrous Melter"] = { avg = nil, chance = true, conditional = false },
    ["Massive Quantum Diamond Cleaner"] = { avg = nil, chance = false, conditional = true },
    ["Methane Sky Fleet"] = { avg = nil, chance = false, conditional = true },
    ["Methuselah's Mask"] = { avg = nil, chance = true, conditional = true },
    ["Midas Blaster"] = { avg = 76.593, chance = false, conditional = true },
    ["Mighty Sugar Cookie"] = { avg = nil, chance = true, conditional = false },
    ["Moai God"] = { avg = nil, chance = true, conditional = true },
    ["Monstrous Mimic Cake"] = { avg = nil, chance = false, conditional = true },
    ["Monstrous Stitchwork"] = { avg = nil, chance = false, conditional = true },
    ["Morning Star"] = { avg = nil, chance = true, conditional = false },
    ["Mystical Thunder"] = { avg = nil, chance = false, conditional = true },
    ["Nature's Enchantment/Renegade"] = { avg = nil, chance = false, conditional = true },
    ["Nature's Temple"] = { avg = nil, chance = false, conditional = true },
    ["Neutron Star"] = { avg = nil, chance = false, conditional = true },
    ["Neutropian Refiner/Renegade"] = { avg = nil, chance = false, conditional = true },
    ["New Year's City"] = { avg = nil, chance = false, conditional = true },
    ["North Star"] = { avg = nil, chance = false, conditional = true },
    ["Northern Lights"] = { avg = nil, chance = false, conditional = true },
    ["Noxious Containment"] = { avg = nil, chance = false, conditional = true },
    ["Nuclear Chamber"] = { avg = nil, chance = false, conditional = true },
    ["Nuclear Stronghold"] = { avg = nil, chance = false, conditional = true },
    ["Oasis"] = { avg = nil, chance = false, conditional = true },
    ["Oblivion Emission"] = { avg = nil, chance = true, conditional = true },
    ["Oblivion Weaver/Renegade"] = { avg = nil, chance = false, conditional = true },
    ["Obsidian Infusion Device"] = { avg = nil, chance = false, conditional = true },
    ["Ooftopian Refiner"] = { avg = nil, chance = false, conditional = true },
    ["Optic Origin"] = { avg = nil, chance = false, conditional = true },
    ["Orbital Cataclysm"] = { avg = nil, chance = false, conditional = true },
    ["Orbital Cataclysm/Renegade"] = { avg = nil, chance = false, conditional = true },
    ["Ore Biplane"] = { avg = nil, chance = false, conditional = true },
    ["Ore Encapsulator"] = { avg = nil, chance = false, conditional = true },
    ["Ore Illuminator"] = { avg = nil, chance = true, conditional = false },
    ["Ore Magmafier"] = { avg = nil, chance = false, conditional = true },
    ["Ore Memer"] = { avg = nil, chance = false, conditional = true },
    ["Ore Nova"] = { avg = nil, chance = false, conditional = true },
    ["Ore Painter"] = { avg = nil, chance = false, conditional = true },
    ["Ore Roaster"] = { avg = nil, chance = false, conditional = true },
    ["Ore Skillet"] = { avg = nil, chance = false, conditional = true },
    ["Ore Striker"] = { avg = 1.5, chance = true, conditional = true },
    ["Ore Tixicator"] = { avg = nil, chance = false, conditional = true },
    ["Phantom of Christmas Future"] = { avg = nil, chance = false, conditional = true },
    ["Phase Processor"] = { avg = nil, chance = false, conditional = true },
    ["Phasecursor Furnace"] = { avg = nil, chance = false, conditional = true },
    ["Pillars of Creation"] = { avg = nil, chance = true, conditional = false },
    ["Pineapple! Stand"] = { avg = nil, chance = false, conditional = true },
    ["Pirate Cove"] = { avg = nil, chance = false, conditional = true },
    ["Pizza Oven"] = { avg = nil, chance = false, conditional = true },
    ["Pizza Parlor"] = { avg = nil, chance = false, conditional = true },
    ["Plague Doctor"] = { avg = nil, chance = true, conditional = false },
    ["Plagued Forest"] = { avg = nil, chance = false, conditional = true },
    ["Plasma Iron Polisher"] = { avg = nil, chance = true, conditional = false },
    ["Precursor Furnace"] = { avg = nil, chance = false, conditional = true },
    ["Present Refiner"] = { avg = nil, chance = true, conditional = true },
    ["Present Schrodinger"] = { avg = 2.2, chance = true, conditional = true },
    ["Pumpkin Possession"] = { avg = nil, chance = false, conditional = true },
    ["Quaint Skymill"] = { avg = nil, chance = false, conditional = true },
    ["Queen Birthday Cake"] = { avg = nil, chance = false, conditional = true },
    ["Rainbow Upgrader"] = { avg = nil, chance = true, conditional = true },
    ["Raised Wide Upgrader"] = { avg = nil, chance = false, conditional = true },
    ["Reaper's Fortress"] = { avg = nil, chance = true, conditional = false },
    ["Red Giant"] = { avg = nil, chance = false, conditional = true },
    ["Repulsion Device"] = { avg = nil, chance = false, conditional = true },
    ["Rose Palace"] = { avg = nil, chance = false, conditional = true },
    ["Rotary Upgrader"] = { avg = nil, chance = false, conditional = true },
    ["Rush Upgrader"] = { avg = nil, chance = false, conditional = true },
    ["Sage Justice"] = { avg = nil, chance = false, conditional = true },
    ["Sage King"] = { avg = nil, chance = false, conditional = true },
    ["Santa's Castle"] = { avg = nil, chance = false, conditional = true },
    ["Santa's Deluxe Sleigh"] = { avg = nil, chance = false, conditional = true },
    ["Santa's Nice List"] = { avg = nil, chance = false, conditional = true },
    ["Santa's Train"] = { avg = nil, chance = true, conditional = false },
    ["Satellite Beam"] = { avg = nil, chance = false, conditional = true },
    ["Saturated Catalyst"] = { avg = nil, chance = true, conditional = false },
    ["Scales of Disparity"] = { avg = nil, chance = false, conditional = true },
    ["Schrodinger Chamber"] = { avg = 1.739, chance = true, conditional = true },
    ["Schrodinger Evaluator"] = { avg = 1.665, chance = true, conditional = true },
    ["Searing Heat"] = { avg = nil, chance = false, conditional = true },
    ["Serpentine Upgrader"] = { avg = nil, chance = true, conditional = false },
    ["Sinister Sepulcher"] = { avg = nil, chance = true, conditional = false },
    ["Sinister Sepulcher/Renegade"] = { avg = nil, chance = true, conditional = false },
    ["Smore Cake"] = { avg = nil, chance = true, conditional = true },
    ["Solar Apocalypse"] = { avg = nil, chance = true, conditional = false },
    ["Solar Flare"] = { avg = nil, chance = true, conditional = true },
    ["Son of Poison"] = { avg = nil, chance = false, conditional = true },
    ["Spector of Christmas Present"] = { avg = nil, chance = false, conditional = true },
    ["Spectral Upgrader"] = { avg = nil, chance = false, conditional = true },
    ["Speggtral Rose"] = { avg = nil, chance = true, conditional = true },
    ["Sphinx of Luxor"] = { avg = nil, chance = false, conditional = true },
    ["Spires of Conquest"] = { avg = nil, chance = true, conditional = false },
    ["SpookLord-95,000"] = { avg = nil, chance = true, conditional = true },
    ["Spooky Fruit Punch Processor"] = { avg = nil, chance = false, conditional = true },
    ["Spooky Schrodinger"] = { avg = 2.667, chance = false, conditional = true },
    ["Sporegg Hut"] = { avg = nil, chance = true, conditional = true },
    ["Steel Refinery"] = { avg = nil, chance = false, conditional = true },
    ["Stellar Bombardment"] = { avg = 4.25, chance = false, conditional = true },
    ["Stellarite Mine"] = { avg = nil, chance = false, conditional = true },
    ["Stratospheric Refiner"] = { avg = nil, chance = false, conditional = true },
    ["Suitopian Refiner"] = { avg = nil, chance = true, conditional = false },
    ["Suitopian Refiner/Renegade"] = { avg = nil, chance = true, conditional = true },
    ["Super Schrodinger"] = { avg = 3.525, chance = false, conditional = true },
    ["Swag City"] = { avg = nil, chance = false, conditional = true },
    ["Swift Justice"] = { avg = nil, chance = false, conditional = true },
    ["Symmetrium Mine"] = { avg = nil, chance = false, conditional = true },
    ["THE DECADE"] = { avg = nil, chance = false, conditional = true },
    ["Teddy Bear Stuffer"] = { avg = nil, chance = false, conditional = true },
    ["Tempest Refiner"] = { avg = nil, chance = false, conditional = true },
    ["Tesla Refuter"] = { avg = nil, chance = false, conditional = true },
    ["The Cornucopia"] = { avg = nil, chance = true, conditional = true },
    ["The Demon"] = { avg = nil, chance = false, conditional = true },
    ["The Easter Shrine"] = { avg = nil, chance = false, conditional = true },
    ["The Final Upgrader"] = { avg = nil, chance = false, conditional = true },
    ["The Fissure"] = { avg = nil, chance = true, conditional = false },
    ["The Fracture"] = { avg = nil, chance = true, conditional = false },
    ["The Great Parasite"] = { avg = nil, chance = false, conditional = true },
    ["The Great Parasite/Renegade"] = { avg = nil, chance = false, conditional = true },
    ["The Guillotine"] = { avg = nil, chance = true, conditional = true },
    ["The Heartbreaker"] = { avg = nil, chance = true, conditional = true },
    ["The Hourglass"] = { avg = nil, chance = false, conditional = true },
    ["The Lord"] = { avg = nil, chance = false, conditional = true },
    ["The Master"] = { avg = nil, chance = false, conditional = true },
    ["The Sunken Past"] = { avg = nil, chance = false, conditional = true },
    ["The Trinity"] = { avg = nil, chance = true, conditional = true },
    ["The Ultimate Sacrifice"] = { avg = nil, chance = false, conditional = true },
    ["The Vault"] = { avg = nil, chance = false, conditional = true },
    ["Time-Space Scrambler"] = { avg = nil, chance = true, conditional = false },
    ["Toxic Schrodinger Evaluator"] = { avg = 3.32, chance = true, conditional = true },
    ["Toxic Waste Disposal"] = { avg = nil, chance = true, conditional = false },
    ["Transylvanian Refiner"] = { avg = nil, chance = false, conditional = true },
    ["Tsar Bomba"] = { avg = nil, chance = true, conditional = false },
    ["Turbine Chamber"] = { avg = nil, chance = false, conditional = true },
    ["Turtle Dignifier"] = { avg = nil, chance = false, conditional = true },
    ["Tyrant's Forge"] = { avg = nil, chance = false, conditional = true },
    ["Tyrant's Throne"] = { avg = nil, chance = false, conditional = true },
    ["Unobtainium Mine"] = { avg = nil, chance = false, conditional = true },
    ["Utopian Refiner"] = { avg = nil, chance = true, conditional = true },
    ["Utopian Refiner/Renegade"] = { avg = nil, chance = true, conditional = true },
    ["Vampire Spore"] = { avg = nil, chance = true, conditional = true },
    ["Vesterian Upgrader"] = { avg = nil, chance = false, conditional = true },
    ["Video Game Digitalizer"] = { avg = nil, chance = false, conditional = true },
    ["Virtual Enchanter"] = { avg = nil, chance = false, conditional = true },
    ["Virtual Enhancer"] = { avg = nil, chance = false, conditional = true },
    ["Virtual Gearwork"] = { avg = nil, chance = false, conditional = true },
    ["Vitamin C-Coater"] = { avg = nil, chance = true, conditional = true },
    ["Vulcan's Destiny"] = { avg = nil, chance = false, conditional = true },
    ["Vulcan's Grasp"] = { avg = nil, chance = false, conditional = true },
    ["Way-Up-High Upgrader"] = { avg = nil, chance = false, conditional = true },
    ["Whimsical Turbine"] = { avg = nil, chance = false, conditional = true },
    ["Wholesome Skull Blaster"] = { avg = nil, chance = false, conditional = true },
    ["Wild Spore"] = { avg = nil, chance = false, conditional = true },
    ["Winterheart"] = { avg = nil, chance = false, conditional = true },
    ["Yunium Mine"] = { avg = nil, chance = false, conditional = true },
}

DESTROYS_UNLESS = {
    ["Assembly Unit"] = "Hyper Mine ore",
    ["Scorching Heat"] = "Fire or Fireproof",
}

function sampleOreValue(factory)
    local best, bestName = 0, nil
    for _, item in ipairs(factory:GetChildren()) do
        if item:IsA("Model") then
            local entry = MINES[item.Name]
            if entry and entry.oreValue and entry.oreValue > best then
                best = entry.oreValue
                bestName = item.Name
            end
        end
    end
    if best > 0 then return best, -1, bestName end

    local dp = workspace:FindFirstChild("DroppedParts")
    local total, count = 0, 0
    if dp then
        local container = dp:FindFirstChild(factory.Name)
        local root = container or dp
        for _, d in ipairs(root:GetDescendants()) do
            if count >= 80 then break end
            if d:IsA("BasePart") then
                local cashObj = d:FindFirstChild("Cash")
                local v = cashObj and tonumber(cashObj.Value) or nil
                if type(v) == "number" and v > 0 then
                    total = total + v
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then return 0, 0, nil end
    return total / count, count, nil
end

function formatDuration(sec)
    if sec < 1 then return string.format("%.0f ms", sec * 1000) end
    if sec < 60 then return string.format("%.1fs", sec) end
    local m = math.floor(sec / 60)
    local r = sec - m * 60
    if m < 60 then return string.format("%dm %02.0fs", m, r) end
    local h = math.floor(m / 60)
    return string.format("%dh %02dm", h, m - h * 60)
end

function printRoute()
    local factory = getMyFactory()
    if not factory then
        UI:Notify({ Title = "Route", Content = "No base found.", Type = "Error" })
        return
    end
    local list, teslas, education = detectUpgraders(factory)
    if #list == 0 and #teslas == 0 then
        UI:Notify({ Title = "Route", Content = "Nothing upgradable on the base.", Type = "Error" })
        return
    end
    local furnace = detectBestFurnace(factory, false)
    local oreValue, samples, mineName = sampleOreValue(factory)
    local value = oreValue
    local logV = oreValue > 0 and math.log10(oreValue) or nil
    local function show(v)
        if v == math.huge and logV then return formatSciLog(logV) end
        return formatScientific(v)
    end
    local function showScaled(v, factor)
        if v == math.huge and logV and factor and factor > 0 then
            return formatSciLog(logV + math.log10(factor))
        end
        return formatScientific(v)
    end
    local cycles = #teslas + 1
    local seconds, survival, rolls, portals, passes = 0, 1, 0, 0, 0
    local risk = {}
    local dead = false
    local tags = {}
    if mineName then tags[mineName:lower()] = true end
    local line = string.rep("─", 68)

    print("")
    print("  DEEPVEIN · ROUTE SIMULATION")
    print("  " .. line)
    print(string.format("  %s   %d upgraders   %d resetters", factory.Name, #list, #teslas))
    local supCount = 0
    local supNames = {}
    for cid, byId in pairs(LAST_SUPPRESSED) do
        supCount = supCount + 1
        if supCount <= 4 then
            local cm, bm = ITEM_BY_ID[cid], ITEM_BY_ID[byId]
            supNames[#supNames + 1] = string.format("%s <- %s",
                cm and cm.Name or ("#" .. cid), bm and bm.Name or ("#" .. byId))
        end
    end
    if supCount > 0 then
        print(string.format("  suppressed %d  %s%s", supCount,
            table.concat(supNames, ", "), supCount > 4 and ", ..." or ""))
    end
    if oreValue > 0 then
        local src = samples == -1 and "database value" or string.format("avg of %d live ores", samples)
        print(string.format("  input  %s   %s  (%s)", mineName or "base", formatScientific(oreValue), src))
    else
        print(string.format("  input  %s   no live ore to sample", mineName or "base"))
    end
    print("  " .. line)
    print(string.format("  %-3s %-30s %-16s %s", "#", "machine", "mult", "ore value"))
    print("  " .. line)

    for cycle = 1, cycles do
        if cycle > 1 then
            print(string.format("  %-3s %-30s %-16s %s", "", "cycle " .. cycle, "", show(value)))
        end
        for i, rec in ipairs(list) do
            local mult = rec.Multiplier or 1
            if rec.Conditional and rec.Conditional.avg then mult = rec.Conditional.avg end
            local uses = (rec.Loopability == "Multi" and (rec.MaxUses or 1)) or 1
            local req = DESTROYS_UNLESS[rec.Name] or rec.DestroysUnless
            if type(req) == "table" then req = table.concat(req, " or ") end
            if req then
                local ok = false
                for token in string.gmatch(req .. " or ", "(.-)%s+or%s+") do
                    token = token:lower():gsub("%s*ore$", "")
                    if tags[token] or (mineName and mineName:lower():find(token, 1, true)) then ok = true end
                end
                if not ok then
                    survival = 0
                    rolls = rolls + 1
                    print(string.format("  ✖   %-30s %-16s %s", rec.Name, "destroyed", req))
                    dead = true
                    break
                end
            end
            seconds = seconds + ((rec.PostDelay or 0) + (tonumber(State.passDelay) or 0)) * uses
            passes = passes + uses
            local dc = DESTROY_CHANCE[rec.Name] or rec.DestroyChance
            local ec = rec.ExplodeChance
            if dc and dc > 0 then
                survival = survival * (1 - dc)
                rolls = rolls + 1
                risk[#risk + 1] = string.format("%s %d%%", rec.Name, math.floor(dc * 100 + 0.5))
            end
            if ec and ec > 0 then
                survival = survival * (1 - ec)
                rolls = rolls + 1
                risk[#risk + 1] = string.format("%s explodes %d%%", rec.Name, math.floor(ec * 100 + 0.5))
            end
            if rec.LoopUnsafe and cycles > 1 then risk[#risk + 1] = rec.Name .. " loop-unsafe" end
            if rec.SpecialFlag and tostring(rec.SpecialFlag):find("teleport") then
                portals = portals + 1
            end
            local locked = rec.ResetIncompatible == true
            if cycle > 1 and locked then
                print(string.format("  %02d  %-30s %-16s %s", i, rec.Name, "reset lock", show(value)))
            else
                local capped = rec.CapValue ~= nil and value >= rec.CapValue
                if not capped then
                    for _ = 1, uses do
                        if rec.IsAdditive then
                            value = value + mult
                            logV = nil
                        else
                            value = value * mult
                            if logV and mult > 0 then logV = logV + math.log10(mult) end
                        end
                        if rec.CapValue and value > rec.CapValue then value = rec.CapValue end
                        if rec.FloorValue and value < rec.FloorValue then value = rec.FloorValue end
                    end
                    applyEffects(tags, rec.AppliesEffect, true)
                    applyEffects(tags, rec.ClearsEffect, nil)
                end
                local label
                if rec.Conditional and rec.Conditional.avg then
                    label = "avg ×" .. formatScientific(mult)
                elseif capped then
                    label = "cap " .. formatScientific(rec.CapValue)
                elseif uses > 1 then
                    label = string.format("×%s×%d", formatScientific(mult), uses)
                else
                    label = "×" .. formatScientific(mult)
                end
                local given = effectLabel(rec.AppliesEffect)
                local removed = effectLabel(rec.ClearsEffect)
                local deadly = killerIn(rec.AppliesEffect)
                if deadly then risk[#risk + 1] = rec.Name .. " applies " .. deadly end
                if given then label = label .. " +" .. given end
                if removed then label = label .. " -" .. removed end
                local edu = EDUCATION_TIMERS[rec.Name]
                print(string.format("  %02d  %-30s %-16s %s", i, rec.Name, label, show(value))
                    .. (edu and string.format("  sells within %.0fs", edu) or ""))
            end
        end
        if cycle <= #teslas then
            local t = teslas[cycle]
            local db = t.DB or {}
            -- Resetter use ALWAYS comes first. This device cannot contribute an
            -- upgrade on the same visit until that reset step has happened, so
            -- the reset is printed and applied on its own before any multiplier.
            print(string.format("  %-3s %-30s %-16s %s", "↺", t.Name, "reset", show(value)))
            if db.FirstMult then
                value = value * db.FirstMult
                if logV and db.FirstMult > 0 then logV = logV + math.log10(db.FirstMult) end
                value = value * (db.SecondMult or 1)
                if logV and (db.SecondMult or 1) > 0 then logV = logV + math.log10((db.SecondMult or 1)) end
                for _ = 3, (db.MaxUses or 3) do
                    if db.LoopCap and value >= db.LoopCap then break end
                    value = value * (db.RepeatMult or 1.35)
                if logV and (db.RepeatMult or 1.35) > 0 then logV = logV + math.log10((db.RepeatMult or 1.35)) end
                end
                print(string.format("  %-3s %-30s %-16s %s", "↳", "", "then upgrade", show(value)))
            elseif (db.Multiplier or 1) > 1 then
                -- Pure resetters that also multiply (Void Star x10,
                -- Daestrophe x100). The reset above already happened and the
                -- cycle count is unchanged; this is only the value delta.
                value = value * db.Multiplier
                if logV and db.Multiplier > 0 then logV = logV + math.log10(db.Multiplier) end
                if db.FireMult and tags["fire"] then
                    value = value * db.FireMult
                    if logV then logV = logV + math.log10(db.FireMult) end
                end
                local note = "then ×" .. formatScientific(db.Multiplier)
                if db.FireMult and tags["fire"] then note = note .. " ×" .. formatScientific(db.FireMult) .. " fire" end
                print(string.format("  %-3s %-30s %-16s %s", "↳", "", note, show(value)))
            end
        end
        if dead then break end
    end

    if #education > 0 then
        -- Mirror the booster: a single education touch, the highest multiplier.
        local best, bestMult = nil, -math.huge
        for _, rec in ipairs(education) do
            local m = rec.Multiplier or 1
            if m > bestMult then bestMult, best = m, rec end
        end
        if best then
            print("  " .. line)
            value = value * bestMult
            if logV and bestMult > 0 then logV = logV + math.log10(bestMult) end
            local timer = EDUCATION_TIMERS[best.Name]
            print(string.format("  %-3s %-30s %-16s %s", "EDU", best.Name,
                "×" .. formatScientific(bestMult) .. (timer and string.format(" %.0fs", timer) or ""),
                show(value)))
        end
    end
    print("  " .. line)
    if furnace then
        print(string.format("  %-30s %-16s %s", "sell at " .. furnace.Name, "", show(value)))
        print(string.format("  %-30s %-16s %s", "cash per ore", "×" .. formatScientific(furnace.DB.CashMult or 0), showScaled(value * (furnace.DB.CashMult or 0), furnace.DB.CashMult or 0)))
        print(string.format("  %-30s %-16s %s", "research per ore", "×" .. formatScientific(furnace.DB.RPPerOre or 0), showScaled(value * (furnace.DB.RPPerOre or 0), furnace.DB.RPPerOre or 0)))
    else
        print(string.format("  %-30s %-16s %s", "no furnace on base", "", show(value)))
    end
    print("  " .. line)
    print(string.format("  %-30s %-16s %s", "time to sell", "", "~" .. formatDuration(seconds)))
    print(string.format("  %-30s %-16s %d passes @ %.3fs", "pass delay", "", passes, tonumber(State.passDelay) or 0))
    local killerTag = nil
    for tag in pairs(tags) do
        if STATUS_KILLS[tag] then killerTag = tag end
    end
    if killerTag then
        print(string.format("  %-30s %-16s %s", "status at sell", "", killerTag .. " still active — kills the ore"))
    end
    if #risk > 0 then
        local shown, extra = {}, #risk > 3 and string.format(" +%d more", #risk - 3) or ""
        for i = 1, math.min(#risk, 3) do shown[#shown + 1] = risk[i] end
        print(string.format("  %-30s %-16s %s", "destroy risk", "", table.concat(shown, ", ") .. extra))
    end
    print(string.format("  %-30s %-16s %.1f%%", "survival", "", survival * 100) .. (rolls > 0 and string.format("  (%d destroy rolls)", rolls) or "  (no destroy data)"))
    if portals > 0 then
        print(string.format("  %-30s %-16s %d portal waits @ 2.0s", "teleports", "", portals))
    end
    print("  " .. line)
    print("")
    UI:Notify({ Title = "Route", Content = string.format("%d steps · %s per ore", #list * cycles, show(value)), Type = "Info", Duration = 5 })
end

-- ── base audit: what resolved, what did not, what got renamed ────────
function printItemAudit()
    local factory = getMyFactory()
    if not factory then
        UI:Notify({ Title = "Audit", Content = "No base found.", Type = "Error" })
        return
    end
    local known, unknown, shiny = 0, 0, 0
    local missing = {}
    for _, item in ipairs(factory:GetChildren()) do
        if item:IsA("Model") then
            local key, id = itemKey(item)
            if id and MHItem.baseOfShiny[id] then shiny = shiny + 1 end
            if MHUpgrader(item) or MHFurnace(item) then
                known = known + 1
            else
                unknown = unknown + 1
                table.insert(missing, string.format("  %s  (id %s)", key, tostring(id)))
            end
        end
    end
    print(string.format("=== BASE AUDIT · %s ===", factory.Name))
    local withFx, withMpu, withRisk = 0, 0, 0
    for _, item in ipairs(factory:GetChildren()) do
        if item:IsA("Model") then
            local entry = MHUpgrader(item) or MHFurnace(item)
            if entry then
                if entry.AppliesEffect or entry.ClearsEffect then withFx = withFx + 1 end
                if entry.MPU then withMpu = withMpu + 1 end
                if entry.DestroyChance or entry.ExplodeChance or entry.DestroysOre then withRisk = withRisk + 1 end
            end
        end
    end
    print(string.format("  resolved %d · unknown %d · shiny %d", known, unknown, shiny))
    print(string.format("  data     %d effects · %d mpu · %d destroy", withFx, withMpu, withRisk))
    for _, line in ipairs(missing) do print(line) end
    if #MHItem.orphaned > 0 then
        table.sort(MHItem.orphaned)
        print("  database entries with no live item (renamed/removed):")
        for _, n in ipairs(MHItem.orphaned) do print("    - " .. n) end
    end
    UI:Notify({
        Title = "Audit",
        Content = string.format("%d resolved · %d unknown", known, unknown),
        Type = unknown > 0 and "Info" or "Success", Duration = 6,
    })
end

function upgraderCanAct(upgraderRec, cash)
    local flag  = upgraderRec.SpecialFlag
    local floor = upgraderRec.FloorValue
    local cap   = upgraderRec.CapValue
    if floor and cash < floor then return false end
    if cap and upgraderRec.Loopability == "Unlimited" and cash >= cap then return false end
    if flag == "launched_only" then return false end
    if flag == "coal_required" then return false end
    return true
end
local ORE_RADIUS  = 0.5   -- conservative ore half-size

function getTopSurfaceWorld(triggerPart)
    local cf = triggerPart.CFrame
    local s  = triggerPart.Size
    local worldHalfY =
        math.abs(cf.RightVector.Y) * (s.X / 2) +
        math.abs(cf.UpVector.Y)    * (s.Y / 2) +
        math.abs(cf.LookVector.Y)  * (s.Z / 2)
    return cf.Position.Y + worldHalfY
end

local FUND = { costT = -10, cost = nil, sumT = -10, sum = 0, skip = nil, wait = nil }

function rebirthTarget()
    local now = os.clock()
    if FUND.cost and now - FUND.costT < 0.5 and FUND.skip == State.skipCount and FUND.wait == State.waitSkip then
        return FUND.cost
    end
    local ok, cost = pcall(MoneyLib.RebornPrice, lp)
    if not ok or type(cost) ~= "number" then FUND.cost = nil return nil end
    if State.waitSkip and State.skipCount > 0 then
        local sok, scost = pcall(MoneyLib.CalculateLifeSkips, lp, State.skipCount)
        if sok and type(scost) == "number" then cost = math.max(cost, scost) end
    end
    FUND.cost, FUND.costT, FUND.skip, FUND.wait = cost, now, State.skipCount, State.waitSkip
    return cost
end

function getTotalLiveOreCash()
    local now = os.clock()
    if now - FUND.sumT < 0.25 then return FUND.sum end
    local total = 0
    local container, factory = getOreContainer()
    if container and factory then
        local factoryName = factory.Name
        local kids = container:GetChildren()
        for i = 1, #kids do
            local ore = kids[i]
            local owner = ore:GetAttribute("Owner")
            if not owner or owner == factoryName then
                local c = ore:FindFirstChild("Cash")
                local v = c and c.Value
                if type(v) == "number" then total = total + v end
            end
        end
    end
    FUND.sum, FUND.sumT = total, now
    return total
end

function getTotalLiveOreCash()
    local total = 0
    local container, factory = getOreContainer()
    if not container or not factory then return 0 end
    local factoryName = factory.Name
    for _, ore in ipairs(container:GetChildren()) do
        local ok, val = pcall(function()
            if not ore or not ore.Parent then return 0 end
            local owner = ore:GetAttribute("Owner")
            if owner and owner ~= factoryName then return 0 end
            local c = ore:FindFirstChild("Cash")
            return c and (c.Value or 0) or 0
        end)
        if ok and val then total = total + val end
    end
    return total
end

local CashSrc = nil
function getCash()
    local o = CashSrc
    if o and o.Parent then
        local v = o.Value
        return type(v) == "number" and v or (tonumber(v) or 0)
    end
    CashSrc = nil
    local mirror = RS:FindFirstChild("MoneyMirror")
    local m = mirror and mirror:FindFirstChild(lp.Name)
    if not m then
        -- the mirror has gone missing before; the GUI value is the same number
        local pg  = lp:FindFirstChild("PlayerGui")
        local gui = pg and pg:FindFirstChild("GUI")
        local mv  = gui and gui:FindFirstChild("Money")
        if mv and mv:IsA("ValueBase") then m = mv end
    end
    if m then
        CashSrc = m
        local v = m.Value
        return type(v) == "number" and v or (tonumber(v) or 0)
    end
    return 0
end

function checkAndFlagAllOresForRebirth()
    if not State.sellForRebirth then return false end
    local cost = rebirthTarget()
    if not cost then return false end
    if (getCash() + getTotalLiveOreCash()) < cost then return false end
    for _, st in pairs(OreStates) do
        if st then st.Status = "REBIRTH_FUNDED" end
    end
    return true
end

function oreWouldFundRebirth(oreCash)
    if not State.sellForRebirth then return false end
    local cost = rebirthTarget()
    if not cost then return false end
    if (getCash() + oreCash) >= cost then return true end
    return checkAndFlagAllOresForRebirth()
end

function upgradeOreOnUpgrader(ore, upgraderRec, st, snap)
    local delay = State.passDelay
    local loop  = upgraderRec.Loopability

    if loop == "No" then
        if rtHalt(st) then return "stopped" end
        local cash = getOreCash(ore)
        if cash and not upgraderCanAct(upgraderRec, cash) then return "exhausted" end
        local tp = revalidateTrigger(upgraderRec)
        if not tp then return "exhausted" end

        if upgraderRec.PostDelay then
            if not State.usePostDelayItems then return "exhausted" end
            -- the guard already cleaned the ore, because a hold outlasts every kill timer
            local parkCF   = CFrame.new(tp.Position.X, tp.Position.Y + 2000, tp.Position.Z)
            local lockName = upgraderRec.Name
            local soakEnd  = os.clock() + 2
            while os.clock() < soakEnd do
                if rtHalt(st) then return "stopped" end
                if not ore.Parent then return "destroyed" end
                oreSet(ore, parkCF)
                task.wait(0.016)
            end
            if not ore.Parent then return "destroyed" end
            while PostDelayLocks[lockName] do
                if rtHalt(st) then return "stopped" end
                if not ore.Parent then return "destroyed" end
                oreSet(ore, parkCF)
                task.wait(0.016)
            end
            PostDelayLocks[lockName] = true
            tpOre(ore, tp)
            task.wait(0.3)
            PostDelayLocks[lockName] = nil
            if not ore.Parent then return "destroyed" end

            local holdCF  = tp.CFrame + Vector3.new(0, 10, 0)
            local holdEnd = os.clock() + upgraderRec.PostDelay
            while os.clock() < holdEnd do
                if rtHalt(st) then return "stopped" end
                if State.sellForRebirth then
                    local c = getOreCash(ore)
                    if c and oreWouldFundRebirth(c) then return "exhausted" end
                end
                oreSet(ore, holdCF)
                task.wait(0.016)
            end
        else
            local before = getOreCash(ore)
            tpOre(ore, tp)
            task.wait(delay)
            -- A touch that lands inside the replication gap is silently lost and
            -- the ore moves on un-upgraded. Machines that always change the value
            -- get verified and re-touched (event driven, no per-frame cost).
            local mult = upgraderRec.Multiplier
            if before and mult and mult > 1 and not upgraderRec.PostDelay
                and not upgraderRec.SpecialFlag and not upgraderRec.Conditional and not upgraderRec.DestroysUnless then
                for _ = 1, 2 do
                    local patience = fxPing() * 2 + 0.12
                    local t0, changed = os.clock(), false
                    while os.clock() - t0 < patience do
                        local now = getOreCash(ore)
                        if now == nil then return "destroyed" end
                        if now ~= before then changed = true; break end
                        task.wait(0.016)
                    end
                    if changed then break end
                    if rtHalt(st) then return "stopped" end
                    if not ore.Parent then return "destroyed" end
                    local tp2 = revalidateTrigger(upgraderRec)
                    if not tp2 then break end
                    oreSet(ore, CFrame.new(tp2.Position.X, getTopSurfaceWorld(tp2) + 4.5, tp2.Position.Z))
                    task.wait(0.05)
                    tpOre(ore, tp2)
                    task.wait(delay)
                end
            end
        end
        if not ore.Parent then return "destroyed" end
        return "exhausted"
    end

    if loop == "Multi" then
        local uses     = upgraderRec.MaxUses or 1
        local interval = upgraderRec.MinInterval or 0
        for pass = 1, uses do
            if rtHalt(st) then return "stopped" end
            if not ore.Parent then return "destroyed" end
            if State.sellForRebirth then
                local c = getOreCash(ore)
                if c and oreWouldFundRebirth(c) then return "exhausted" end
            end
            local cash = getOreCash(ore)
            if cash and not upgraderCanAct(upgraderRec, cash) then return "exhausted" end
            local tp = revalidateTrigger(upgraderRec)
            if not tp then return "exhausted" end
            if pass > 1 then
                local hazard = fxTick(ore, st, snap)
                if hazard then return hazard end
                oreSet(ore, CFrame.new(tp.Position.X, getTopSurfaceWorld(tp) + 4.5, tp.Position.Z))
                task.wait(0.05)
                if rtHalt(st) then return "stopped" end
                if not ore.Parent then return "destroyed" end
            end
            tpOre(ore, tp)
            task.wait(0.03)
            if not ore.Parent then return "destroyed" end
            if interval > 0 and pass < uses then task.wait(interval) end
        end
        return "exhausted"
    end

    if loop == "Unlimited" and not upgraderRec.EffectOnlyUnlimited then
        local MIN_GAIN_FRACTION = 0.001
        local floor      = upgraderRec.FloorValue or 0
        local interval   = upgraderRec.MinInterval or 0
        local windowSize = State.noCapeStallWindow or 6
        local history    = {}
        local passes     = 0
        local lastGainT  = os.clock()
        local maxPasses  = st.tail and 3 or math.huge

        while true do
            if rtHalt(st) then return "stopped" end
            if not ore.Parent then return "destroyed" end

            local cashBefore = getOreCash(ore)
            if cashBefore == nil then return "destroyed" end
            if cashBefore < floor then return "exhausted" end
            if upgraderRec.CapValue and cashBefore >= upgraderRec.CapValue then return "exhausted" end

            local hazard = fxTick(ore, st, snap)
            if hazard then return hazard end

            local tp = revalidateTrigger(upgraderRec)
            if not tp then return "exhausted" end

            oreSet(ore, CFrame.new(tp.Position.X, getTopSurfaceWorld(tp) + 4.5, tp.Position.Z))
            task.wait(0.05)
            if rtHalt(st) then return "stopped" end
            if not ore.Parent then return "destroyed" end

            tpOre(ore, tp)
            if State.RebirthPending then return "stopped" end
            if interval > 0 then task.wait(interval) else task.wait(delay) end
            if State.RebirthPending then return "stopped" end
            if rtHalt(st) then return "stopped" end

            if State.sellForRebirth then
                local c = getOreCash(ore)
                if c and oreWouldFundRebirth(c) then return "exhausted" end
            end
            if not ore.Parent then return "destroyed" end

            local cashAfter = getOreCash(ore)
            if cashAfter == nil then return "destroyed" end
            if upgraderRec.CapValue and cashAfter >= upgraderRec.CapValue then return "exhausted" end

            local delta = cashAfter - cashBefore
            if cashAfter ~= cashBefore then lastGainT = os.clock() end
            history[#history + 1] = delta
            if #history > windowSize then table.remove(history, 1) end

            if #history >= windowSize then
                local allZero = true
                for _, d in ipairs(history) do
                    if d ~= 0 then allZero = false; break end
                end
                if allZero then
                    -- The server value arrives a ping later than the touch, so
                    -- three flat reads 5ms apart say nothing. Only call the machine
                    -- dead once nothing has moved for longer than the round trip.
                    local patience = math.max(0.5, fxPing() * 3 + 0.35)
                    if os.clock() - lastGainT >= patience then return "exhausted" end
                end

                if upgraderRec.CapValue and cashAfter >= upgraderRec.CapValue * 0.95 then
                    local threshold = cashAfter * MIN_GAIN_FRACTION
                    local allWeak = true
                    for _, d in ipairs(history) do
                        if d >= threshold then allWeak = false; break end
                    end
                    if allWeak then return "exhausted" end
                end
            end

            passes = passes + 1
            if passes >= maxPasses then return "exhausted" end
            if delta == 0 then task.wait(0.03) end
        end
    end

    return nil
end

function sellOre(ore, furnaceInfo)
    if not ore or not ore.Parent then return true end
    if not furnaceInfo then return false end

    local item = furnaceInfo.Item
    local part = furnaceInfo.SellPart
    local startTime = os.clock()

    while ore.Parent do
        if os.clock() - startTime >= 15 then break end
        if not item or not item.Parent then break end
        if not (part and part.Parent) then
            part = findFurnaceSellPart(item)
            furnaceInfo.SellPart = part
        end
        if part then oreSet(ore, part.CFrame + TP_OFFSET) end
        task.wait(0.03)
    end

    if ore.Parent and item and item.Parent then
        local model = item:FindFirstChildOfClass("Model")
        local mini = model and model:FindFirstChild("MiniLava")
        if mini and mini:IsA("BasePart") then
            local t0 = os.clock()
            while ore.Parent and os.clock() - t0 < 5 do
                oreSet(ore, mini.CFrame + TP_OFFSET)
                task.wait(0.03)
            end
        end
    end

    return not ore.Parent
end

function fireTesla(ore, teslaRec)
    if not ore or not ore.Parent then return false end
    local tp = revalidateTrigger(teslaRec)
    if not tp then return false end
    tpOre(ore, tp)
    task.wait(State.passDelay)
    return ore and ore.Parent ~= nil
end

function applyForcedUpgraderOrder(list)
    local first = {}
    local middle = {}
    local last = {}

    for _, u in ipairs(list) do
        local name = u.Name

        if FIRST[name] then
            first[FIRST[name]] = u

        elseif LAST[name] then
            last[LAST[name]] = u

        else
            table.insert(middle, u)
        end
    end

    local result = {}
    for i = 1, 100 do
        if first[i] then
            table.insert(result, first[i])
        end
    end
    for _, u in ipairs(middle) do
        table.insert(result, u)
    end
    for i = 1, 100 do
        if last[i] then
            table.insert(result, last[i])
        end
    end

    return result
end

-- ── TRINITY PRE-SEQUENCE OVERRIDE ────────────────────────────
-- If "The Trinity" is present on the base, the following upgraders
-- MUST appear immediately before it, in this exact priority order:
--   1. Father of Freon
--   2. Spirit of Fire
--   3. Son of Poison
-- Son of Poison is the highest priority of the three if only one slot
-- is available. If two are present, Son of Poison goes last (closest
-- to Trinity). All three precursors are pulled from wherever the normal
-- sort placed them and re-injected immediately before Trinity.

TRINITY_PRECURSORS_ORDERED = {
    "Father of Freon",
    "Spirit of Fire",
    "Son of Poison",
}
-- Priority for partial presence: Son of Poison > Spirit of Fire > Father of Freon
-- i.e. if only 1 is down, always prefer Son of Poison, then Spirit of Fire, then Father of Freon
TRINITY_PRECURSOR_PRIORITY = {
    ["Son of Poison"]  = 1,
    ["Spirit of Fire"] = 2,
    ["Father of Freon"]= 3,
}

function hasTrinityOnBase(factory)
    local s = FxSnap and FxSnap.snap
    if s and s.factory == factory then return s.hasTrinity == true end
    for _, item in ipairs(factory:GetChildren()) do
        if item:IsA("Model") and item.Name == "The Trinity" then
            if findUpgradePart(item) then return true end
        end
    end
    return false
end

-- Call this AFTER getOptimalUpgraderOrder, BEFORE applyForcedUpgraderOrder.
-- Mutates the list in-place. Returns the (possibly modified) list.
function applyTrinityOverride(list, factory)
    if not factory then return list end
    if not hasTrinityOnBase(factory) then return list end

    -- Find Trinity's position in the list
    local trinityIdx = nil
    for i, u in ipairs(list) do
        if u.Name == "The Trinity" then
            trinityIdx = i
            break
        end
    end
    if not trinityIdx then return list end -- Trinity in DB but no trigger part found, skip

    -- Collect which precursors are actually present in the list
    local precursorMap = {} -- name → rec
    for _, u in ipairs(list) do
        if TRINITY_PRECURSOR_PRIORITY[u.Name] then
            precursorMap[u.Name] = u
        end
    end

    local presentPrecursors = {}
    for name, rec in pairs(precursorMap) do
        table.insert(presentPrecursors, { name=name, rec=rec })
    end

    if #presentPrecursors == 0 then return list end -- nothing to inject

    -- Sort present precursors by their slot in the required sequence
    -- Full sequence order (1=first before Trinity, 3=directly before Trinity):
    --   Father of Freon (1), Spirit of Fire (2), Son of Poison (3)
    -- Partial rules:
    --   1 present  → use that one directly before Trinity
    --   2 present  → Son of Poison is always last (directly before Trinity)
    --   3 present  → full order: FoF, SoF, SoP

    local injectionOrder = {}

    if #presentPrecursors == 1 then
        injectionOrder = { presentPrecursors[1].rec }

    elseif #presentPrecursors == 2 then
        -- Son of Poison must be last. The other one goes before it.
        local hasSoP = precursorMap["Son of Poison"] ~= nil
        if hasSoP then
            -- Find the non-SoP one
            for _, p in ipairs(presentPrecursors) do
                if p.name ~= "Son of Poison" then
                    table.insert(injectionOrder, p.rec)
                end
            end
            table.insert(injectionOrder, precursorMap["Son of Poison"])
        else
            -- Both non-SoP: use canonical order (FoF before SoF)
            for _, name in ipairs(TRINITY_PRECURSORS_ORDERED) do
                if precursorMap[name] then
                    table.insert(injectionOrder, precursorMap[name])
                end
            end
        end

    else
        -- All 3: canonical order
        for _, name in ipairs(TRINITY_PRECURSORS_ORDERED) do
            table.insert(injectionOrder, precursorMap[name])
        end
    end

    -- Remove all precursors and Trinity from the list
    local precursorNames = {}
    for _, p in ipairs(injectionOrder) do precursorNames[p.Name] = true end

    local filtered = {}
    local trinityRec = nil
    for _, u in ipairs(list) do
        if u.Name == "The Trinity" then
            trinityRec = u -- pulled, re-inserted after precursors
        elseif precursorNames[u.Name] then
            -- pulled — will be re-injected in correct slot
        else
            table.insert(filtered, u)
        end
    end

    -- Re-insert Trinity at its original index position in the filtered list
    -- (clamped to bounds), then inject precursors immediately before it
    local insertAt = math.min(trinityIdx, #filtered + 1)

    -- Inject: precursors first, then Trinity
    for i = #injectionOrder, 1, -1 do
        table.insert(filtered, insertAt, injectionOrder[i])
    end
    -- Trinity goes after all injected precursors
    table.insert(filtered, insertAt + #injectionOrder, trinityRec)

    return filtered
end

function oreHasEffect(ore, effect)
    if not ore or not ore.Parent then return false end
    if effect == "fire" then
        local c = ore:FindFirstChild("Fire")
        return c ~= nil and c:IsA("Fire")
    elseif effect == "poison" then
        local c = ore:FindFirstChild("Smoke")
        return c ~= nil and c:IsA("Smoke")
    elseif effect == "radioactive" then
        local c = ore:FindFirstChild("Radio")
        return c ~= nil and c:IsA("BoolValue")
    elseif effect == "frostbite" then
        return ore.Material == Enum.Material.Ice
    end
    return false
end

function getOreEffects(ore)
    if not ore or not ore.Parent then return {} end
    return {
        fire        = oreHasEffect(ore, "fire"),
        poison      = oreHasEffect(ore, "poison"),
        radioactive = oreHasEffect(ore, "radioactive"),
        frostbite   = oreHasEffect(ore, "frostbite"),
    }
end

function getOptimalUpgraderOrder(ore, normalList)
    local cash = getOreCash(ore) or 0
    local additive, capped, uncapped, unknown, fireOnly = {}, {}, {}, {}, {}

    for _, u in ipairs(normalList) do
        if u.SpecialFlag == "fire_only" then
            fireOnly[#fireOnly + 1] = u
        elseif fxPureCleaner(u) then
            -- pure cleaners are only ever visited by a batched clean trip
        elseif u.IsAdditive then
            additive[#additive + 1] = u
        elseif u.Loopability == "Unlimited" and u.CapValue then
            if cash < u.CapValue then capped[#capped + 1] = { rec = u, cap = u.CapValue } end
        elseif u.Multiplier == nil then
            unknown[#unknown + 1] = u
        elseif u.FloorValue and cash < u.FloorValue then
            unknown[#unknown + 1] = u
        else
            local mult, eff = u.Multiplier, nil
            if u.EffMultOverride then eff = u.EffMultOverride
            elseif u.Loopability == "Multi" then eff = mult ^ (u.MaxUses or 1)
            elseif u.Loopability == "Unlimited" then eff = mult * 3
            else eff = mult end
            uncapped[#uncapped + 1] = { rec = u, eff = eff }
        end
    end

    table.sort(capped,   function(a, b) return a.cap < b.cap end)
    table.sort(uncapped, function(a, b) return a.eff < b.eff end)

    local result = {}
    for _, u in ipairs(additive) do result[#result + 1] = u end
    for _, e in ipairs(capped)   do result[#result + 1] = e.rec end
    for _, e in ipairs(uncapped) do result[#result + 1] = e.rec end
    for _, u in ipairs(unknown)  do result[#result + 1] = u end
    -- fire-only machines come after the base block; the pass applies fire on demand
    for _, u in ipairs(fireOnly) do result[#result + 1] = u end

    result = applyForcedUpgraderOrder(result)
    return applyTrinityOverride(result, getMyFactory())
end

-- ══════════════════════════════════════════════════════════════════════
--  EFFECT ENGINE: shared snapshot, live effect tracking, batched cleaning
-- ══════════════════════════════════════════════════════════════════════
EngineGen = 0
FX_NAMES  = { "fire", "poison", "frostbite" }
FX_KILL   = { fire = 4, poison = 4, frostbite = 4 }
for _, key in ipairs(FX_NAMES) do
    local info = STATUS_INFO[key:sub(1, 1):upper() .. key:sub(2)]
    if info and info.timer then FX_KILL[key] = info.timer end
end
FX_SAFETY = 1.1   -- clean when the earliest kill timer is this close (plus ping)
FX_TRIP   = 0.12  -- time spent on a cleaner

-- Machines that apply a killing status but have no AppliesEffect in the data
FX_APPLY_EXTRA = {
    ["Father of Freon"] = "frostbite",
    ["Spirit of Fire"]  = "fire",
    ["Son of Poison"]   = "poison",
}

FxSnap      = { snap = nil, dirty = true, dirtyAt = 0, conns = {}, watched = nil }
FxPingCache = { t = -10, v = 0.1 }

function fxList(v)
    local out = {}
    if type(v) == "string" then
        out[1] = v:lower()
    elseif type(v) == "table" then
        for _, e in ipairs(v) do
            if type(e) == "string" then out[#out + 1] = e:lower() end
        end
    end
    return out
end

function fxClassify(rec)
    local applies, seen = {}, {}
    for _, e in ipairs(fxList(rec.AppliesEffect)) do
        if FX_KILL[e] and not seen[e] then seen[e] = true; applies[#applies + 1] = e end
    end
    local extra = FX_APPLY_EXTRA[rec.Name]
    if extra and not seen[extra] then applies[#applies + 1] = extra end

    local clears = {}
    for _, e in ipairs(fxList(rec.ClearsEffect)) do
        if FX_KILL[e] then clears[e] = true end
    end
    local entry = UPGRADER_DB[rec.Name]
    if entry and entry.ClearsNegative then
        for e in pairs(FX_KILL) do clears[e] = true end
    end
    for _, e in ipairs(applies) do clears[e] = nil end
    rec.fxApplies, rec.fxClears = applies, clears

    local needs
    if rec.SpecialFlag == "fire_only" then needs = { fire = true, frostbite = true } end
    local du = DESTROYS_UNLESS[rec.Name] or rec.DestroysUnless
    if type(du) == "table" then du = table.concat(du, " or ") end
    rec.fxDu = du
    if type(du) == "string" and du:lower():find("fire", 1, true) then
        needs = needs or {}
        needs.fire = true
    end
    if rec.Name == "The Trinity" then needs = { fire = true, frostbite = true, poison = true } end
    rec.fxNeeds = needs
end

function fxIsDestructive(rec)
    if rec.SpecialFlag == "fire_only" then return false end
    local dc = DESTROY_CHANCE[rec.Name] or rec.DestroyChance
    if dc and dc > 0 then return true end
    if rec.ExplodeChance and rec.ExplodeChance > 0 then return true end
    return rec.IsDestroyer == true
end

function fxSkippable(rec)
    if rec.Loopability == nil then return true, "no loop data" end
    if rec.SpecialFlag == "teleports" then return true, "teleporter" end
    if State.skipDestructive and fxIsDestructive(rec) then return true, "destructive" end
    local du = rec.fxDu
    if type(du) == "string" and not du:lower():find("fire", 1, true) then
        return true, "destroys unless " .. du
    end
    return false
end

function fxPureCleaner(rec)
    return rec.fxClears ~= nil and next(rec.fxClears) ~= nil
        and (rec.Multiplier or 1) <= 1 and not rec.IsAdditive
end

function buildSnapshot(factory)
    local normal, teslas, education = detectUpgraders(factory)
    local s = {
        factory = factory, born = os.clock(),
        teslas = teslas, education = education,
        bestEdu = detectBestEducationUpgrader(factory),
        furnace = detectBestFurnace(factory, false),
        cell = detectBestFurnace(factory, false, true),
        cleanBy = {}, skipped = {}, hasTrinity = false,
        pd = State.usePostDelayItems, sd = State.skipDestructive,
    }
    local kept = {}
    for _, rec in ipairs(normal) do
        fxClassify(rec)
        local skip, why = fxSkippable(rec)
        if skip then
            s.skipped[#s.skipped + 1] = rec.Name .. " (" .. why .. ")"
        else
            kept[#kept + 1] = rec
            if rec.Name == "The Trinity" then s.hasTrinity = true end
            for e in pairs(rec.fxClears) do
                local list = s.cleanBy[e]
                if not list then list = {}; s.cleanBy[e] = list end
                list[#list + 1] = rec
            end
        end
    end
    s.normal = kept
    return s
end

function fxWatch(factory)
    if FxSnap.watched == factory then return end
    for _, c in ipairs(FxSnap.conns) do pcall(function() c:Disconnect() end) end
    FxSnap.conns = {}
    FxSnap.watched = factory
    local function mark() FxSnap.dirty = true; FxSnap.dirtyAt = os.clock() end
    FxSnap.conns[1] = factory.ChildAdded:Connect(mark)
    FxSnap.conns[2] = factory.ChildRemoved:Connect(mark)
end

-- One scan of the base shared by every ore. Rebuilt only when a machine is
-- placed or removed (debounced), when a relevant setting flips, or every 20 s.
function getSnapshot()
    local factory = getMyFactory()
    if not factory then return nil end
    fxWatch(factory)
    local s, now = FxSnap.snap, os.clock()
    local fresh = s and s.factory == factory and now - s.born < 20
        and s.pd == State.usePostDelayItems and s.sd == State.skipDestructive
    if fresh and (not FxSnap.dirty or now - FxSnap.dirtyAt < 0.4) then return s end
    FxSnap.dirty = false
    local ok, built = pcall(buildSnapshot, factory)
    if ok and built then FxSnap.snap = built; return built end
    return s
end

function fxPing()
    local now = os.clock()
    if now - FxPingCache.t > 1 then
        FxPingCache.t = now
        local ok, p = pcall(function() return lp:GetNetworkPing() end)
        if ok and type(p) == "number" then FxPingCache.v = math.clamp(p, 0, 0.4) end
    end
    return FxPingCache.v
end

function rtHalt(st)
    if not State.oreBooster or EngineStopped then return true end
    return st ~= nil and st.gen ~= nil and st.gen ~= EngineGen
end

-- Live read of the ore. A new effect is stamped with the time from BEFORE the
-- step that could have caused it, so its kill deadline is never optimistic.
function fxScan(ore, st, since)
    local fx = st.fx
    for i = 1, #FX_NAMES do
        local e = FX_NAMES[i]
        local present = false
        if e == "frostbite" and st.baseIce then
            present = false -- ore spawns on Ice material, so the signal is unusable
        else
            present = oreHasEffect(ore, e)
        end
        if present then
            if not fx[e] then fx[e] = since end
        else
            fx[e] = nil
        end
    end
end

function fxEarliest(st)
    local best, which
    for e, t0 in pairs(st.fx) do
        local d = t0 + FX_KILL[e]
        if not best or d < best then best, which = d, e end
    end
    return best, which
end

function fxStepCost(rec)
    local d = math.max(tonumber(State.passDelay) or 0.005, 0.02)
    local loop = rec.Loopability
    if loop == "No" then
        if rec.PostDelay then return 2.4 + rec.PostDelay end
        return d + 0.05
    elseif loop == "Multi" then
        local uses = rec.MaxUses or 1
        return uses * (0.09 + d) + math.max(0, uses - 1) * (rec.MinInterval or 0)
    end
    return 0.6
end

function fxReusable(rec)
    return rec.Loopability == "Unlimited" or rec.CleanUnlimited == true
end

function fxCleanerLeft(rec, st)
    local used = st.used[rec] or 0
    if used >= 1e9 then return false end
    if fxReusable(rec) then return true end
    return used < math.max(1, rec.MaxUses or 1)
end

-- A cleaner that touched this ore and left the effect on it is not tried again
-- for that effect, so the next candidate gets its turn.
function fxCleanerFailed(rec, e, st)
    local b = st.badClean and st.badClean[rec]
    return b ~= nil and b[e] == true
end

function fxAnyCleaner(e, snap, st)
    local list = snap.cleanBy[e]
    if not list then return false end
    for i = 1, #list do
        if fxCleanerLeft(list[i], st) and not fxCleanerFailed(list[i], e, st) then return true end
    end
    return false
end

-- Greedy cover: the cleaner that clears the most pending effects wins,
-- reusable (Unlimited) cleaners before limited ones.
function fxPickCleaner(pending, snap, st)
    local best, bestScore
    for e in pairs(pending) do
        local list = snap.cleanBy[e]
        if list then
            for i = 1, #list do
                local rec = list[i]
                if fxCleanerLeft(rec, st) and not fxCleanerFailed(rec, e, st) then
                    local cover = 0
                    for e2 in pairs(pending) do
                        if rec.fxClears[e2] and not fxCleanerFailed(rec, e2, st) then cover = cover + 1 end
                    end
                    local rank = fxReusable(rec) and 3 or (rec.Loopability == "Multi" and 2 or 1)
                    local score = cover * 10 + rank
                    if not bestScore or score > bestScore then best, bestScore = rec, score end
                end
            end
        end
    end
    return best
end

function fxUrgent(st, now, cost)
    local dl = fxEarliest(st)
    return dl ~= nil and dl - now < (cost or 0) + 0.6 + fxPing()
end

-- One batched trip: clears every pending effect that is not being held for an
-- upcoming machine. Returns "ok", "destroyed", "stopped" or "sellnow".
function fxCleanTrip(ore, st, snap, hold, cost)
    for _ = 1, 3 do
        if rtHalt(st) then return "stopped" end
        if not ore.Parent then return "destroyed" end
        local now = os.clock()
        local pending, n = {}, 0
        for e, t0 in pairs(st.fx) do
            local held = hold and hold[e] and (t0 + FX_KILL[e] - now) > (cost or 0) + FX_SAFETY
            if not held then pending[e] = true; n = n + 1 end
        end
        if n == 0 then return "ok" end

        local pick = fxPickCleaner(pending, snap, st)
        if not pick then
            if fxUrgent(st, now, cost) then st.hazDetail = fxDescribe(st, now, "no cleaner left"); return "sellnow" end
            return "ok"
        end
        local tp = fxCleanPart(pick)
        if not tp then
            st.used[pick] = 1e9
        else
            if fxReusable(pick) then
                oreSet(ore, CFrame.new(tp.Position.X, getTopSurfaceWorld(tp) + 4.5, tp.Position.Z))
                task.wait(0.05)
            end
            st.used[pick] = (st.used[pick] or 0) + 1
            st.trips = st.trips + 1
            st.probe = getOreCash(ore)
            tpOre(ore, tp)
            task.wait(FX_TRIP)
            -- The effect leaves the ore on the client a round trip after the touch.
            -- Judging it after 0.12s re-used the cleaner (and burned one-use ones)
            -- on effects that were already gone. Give the removal time to arrive.
            local t0 = os.clock()
            local patience = fxPing() * 2 + 0.1
            while os.clock() - t0 < patience do
                if not ore.Parent then return "destroyed" end
                if fxReusable(pick) then tpOre(ore, tp) end
                local still = false
                for e in pairs(pending) do
                    if pick.fxClears[e] and not (e == "frostbite" and st.baseIce) and oreHasEffect(ore, e) then still = true; break end
                end
                if not still then break end
                task.wait(0.016)
            end
            if not ore.Parent then return "destroyed" end
            fxScan(ore, st, os.clock())
            for e in pairs(pending) do
                if pick.fxClears[e] then
                    local key = pick.Name .. "|" .. e
                    local c = SellLog.clean[key]
                    if not c then c = { 0, 0 }; SellLog.clean[key] = c end
                    if st.fx[e] then c[2] = c[2] + 1 else c[1] = c[1] + 1 end
                end
                if pick.fxClears[e] and st.fx[e] then
                    st.cleanFails = st.cleanFails or {}
                    local f = st.cleanFails[pick]
                    if not f then f = {}; st.cleanFails[pick] = f end
                    f[e] = (f[e] or 0) + 1
                    if not fxReusable(pick) or f[e] >= 2 then
                        st.badClean = st.badClean or {}
                        local b = st.badClean[pick]
                        if not b then b = {}; st.badClean[pick] = b end
                        b[e] = true
                    end
                    st.hazTry = (st.hazTry or "") .. pick.Name .. " failed on " .. e .. " [" .. fxProbe(ore, tp, st) .. "]; "
                end
            end
        end
    end
    if fxUrgent(st, os.clock(), cost) then st.hazDetail = fxDescribe(st, os.clock(), "cleaners ran out"); return "sellnow" end
    return "ok"
end

FX_CLEAN_PARTS = { "clean", "purif", "wash", "scrub" }
FxPartDump = {}

function fxCleanPart(rec)
    local tp = revalidateTrigger(rec)
    if not rec.CleanUnlimited or not rec.Model then return tp end
    local m = rec.Model:FindFirstChildOfClass("Model") or rec.Model
    local pick
    for _, d in ipairs(m:GetDescendants()) do
        if not pick and d:IsA("BasePart") and d.CanTouch and d ~= tp then
            local n = d.Name:lower()
            for i = 1, #FX_CLEAN_PARTS do
                if n:find(FX_CLEAN_PARTS[i], 1, true) then pick = d; break end
            end
        end
    end
    if not FxPartDump[rec.Name] then
        FxPartDump[rec.Name] = true
        local out = {}
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then out[#out + 1] = string.format("%s(%s %s touch=%s)", d.Name, d.ClassName, tostring(d.Size), tostring(d.CanTouch)) end
        end
        local used = pick or tp
        print("[Deepvein] " .. rec.Name .. " parts: " .. table.concat(out, ", ") .. " | cleaning part: " .. (used and used.Name or "none"))
    end
    return pick or tp
end

function fxProbe(ore, tp, st)
    local c = getOreCash(ore)
    local g = "?"
    if c and st.probe and st.probe > 0 then g = string.format("x%.3g", c / st.probe) end
    return string.format("%s/%s touch=%s dist=%.1f cash=%s fire=%s smoke=%s radio=%s", tp.Name, tp.ClassName, tostring(tp.CanTouch), (ore.Position - tp.Position).Magnitude, g, tostring(oreHasEffect(ore, "fire")), tostring(oreHasEffect(ore, "poison")), tostring(oreHasEffect(ore, "radioactive")))
end

function fxDescribe(st, now, why)
    local parts = {}
    for e, t0 in pairs(st.fx) do parts[#parts + 1] = string.format("%s %.1fs left", e, t0 + FX_KILL[e] - now) end
    return why .. " | " .. table.concat(parts, ", ") .. (st.hazTry and (" | " .. st.hazTry) or "")
end

-- Effects the current or next few machines depend on stay on the ore.
function fxHoldSet(st, rec)
    local hold
    local function add(r)
        local n = r and r.fxNeeds
        if n then
            hold = hold or {}
            for e in pairs(n) do hold[e] = true end
        end
    end
    add(rec)
    local order, idx = st.order, st.idx or 0
    if order then
        for j = idx + 1, math.min(#order, idx + 3) do add(order[j]) end
    end
    return hold
end

-- Runs before every machine. Returns "ok", "defer", "destroyed", "stopped", "sellnow".
function fxGuard(ore, st, snap, rec)
    if rtHalt(st) then return "stopped" end
    if not ore.Parent then return "destroyed" end

    if rec and not st.tail then
        local ap = rec.fxApplies
        if ap then
            for i = 1, #ap do
                if not fxAnyCleaner(ap[i], snap, st) then return "defer" end
            end
        end
    end

    local dl = fxEarliest(st)
    if not dl then return "ok" end
    local now  = os.clock()
    local cost = rec and fxStepCost(rec) or 0.3
    if dl - now > cost + FX_SAFETY + fxPing() then return "ok" end
    return fxCleanTrip(ore, st, snap, rec and fxHoldSet(st, rec) or nil, cost)
end

-- Called between passes of long loops so a Multi/Unlimited step can't outlive a timer.
function fxTick(ore, st, snap)
    local now = os.clock()
    fxScan(ore, st, st.tickAt or now)
    st.tickAt = now
    local dl = fxEarliest(st)
    if dl and dl - now < 0.2 + FX_SAFETY + fxPing() then
        local r = fxCleanTrip(ore, st, snap, nil, 0.2)
        if r ~= "ok" then return r end
    end
    return nil
end

function fxFireApplier(snap, st)
    for _, rec in ipairs(snap.normal) do
        if rec.SpecialFlag ~= "fire_only" and rec.fxApplies then
            for _, e in ipairs(rec.fxApplies) do
                if e == "fire" and fxCleanerLeft(rec, st) then return rec end
            end
        end
    end
    return nil
end

function fxRunStep(ore, st, snap, u)
    local g = fxGuard(ore, st, snap, u)
    if g ~= "ok" then return g end
    st.stepStart = os.clock()
    st.tickAt = st.stepStart
    local r = upgradeOreOnUpgrader(ore, u, st, snap)
    st.used[u] = (st.used[u] or 0) + ((u.Loopability == "Multi" and (u.MaxUses or 1)) or 1)
    st.Passes += 1
    st.ran[u.Name] = true
    st.deferred[u] = nil
    if r == "destroyed" or r == "stopped" or r == "sellnow" then return r end
    if ore.Parent then fxScan(ore, st, st.stepStart) end
    return "ok"
end

-- Machines that apply a status the base cannot clean run once, last, then sell.
function fxRunTail(ore, st, snap)
    st.tail = true
    for _, rec in ipairs(snap.normal) do
        if st.deferred[rec] then
            local cash = getOreCash(ore)
            if cash and upgraderCanAct(rec, cash) then
                st.Status = "TAIL:" .. rec.Name
                local r = fxRunStep(ore, st, snap, rec)
                if r ~= "ok" and r ~= "defer" then return r end
            end
        end
    end
    return "ok"
end

function printEffectPlan()
    local snap = getSnapshot()
    if not snap then
        UI:Notify({ Title = "Effects", Content = "No base found.", Type = "Error" })
        return
    end
    local line = string.rep("─", 64)
    print("")
    print("  EFFECT PLAN")
    print("  " .. line)
    for _, e in ipairs(FX_NAMES) do
        local ap, cl = {}, {}
        for _, rec in ipairs(snap.normal) do
            for _, a in ipairs(rec.fxApplies) do
                if a == e then ap[#ap + 1] = rec.Name end
            end
            if rec.fxClears[e] then cl[#cl + 1] = rec.Name end
        end
        print(string.format("  %-12s kills in %ds", e, FX_KILL[e]))
        print("    applied by : " .. (#ap > 0 and table.concat(ap, ", ") or "-"))
        print("    cleaned by : " .. (#cl > 0 and table.concat(cl, ", ") or "NONE"))
        if #ap > 0 and #cl == 0 then
            print("    -> these run once, at the end of the last cycle, then sell")
        end
    end
    print("  " .. line)
    print("  skipped: " .. (#snap.skipped > 0 and table.concat(snap.skipped, ", ") or "none"))
    print("  " .. line)
    print("")
    UI:Notify({ Title = "Effects", Content = "Printed to console.", Type = "Info", Duration = 3 })
end
 
function runUpgraderPass(ore, snap, st, cycleIdx)
    local order = getOptimalUpgraderOrder(ore, snap.normal)
    st.order = order
    local passRan = {}

    -- One machine. Returns nil to carry on, or a terminal result string.
    local function step(i, u)
        st.idx = i
        if rtHalt(st) then return "stopped" end
        if not ore.Parent then return "destroyed" end

        local cash = getOreCash(ore)
        if cash then
            st.LastCash = cash
            if cash >= INSTA_SELL_VALUE then st.Status = "MAX_VALUE"; st.Reason = "MAX"; return "sellnow" end
            if State.sellForRebirth and oreWouldFundRebirth(cash) then
                st.Status = "REBIRTH_FUNDED"; st.Reason = "FUNDED"
                return "sellnow"
            end
        end

        for prev, list in pairs(INCOMPATIBLE_AFTER) do
            if st.ran[prev] and list[u.Name] then return nil end
        end
        if u.Loopability == "No" and (st.used[u] or 0) >= math.max(1, u.MaxUses or 1) then return nil end
        if cash and not upgraderCanAct(u, cash) then return nil end

        if u.SpecialFlag == "fire_only"
            and not (oreHasEffect(ore, "fire") or oreHasEffect(ore, "frostbite")) then
            local ap = fxFireApplier(snap, st)
            if not ap then return nil end
            local pr = fxRunStep(ore, st, snap, ap)
            if pr == "defer" then st.deferred[ap] = true; return nil end
            if pr ~= "ok" then
                if pr == "sellnow" then st.Reason = "HAZARD@" .. ap.Name end
                return pr
            end
            if not (oreHasEffect(ore, "fire") or oreHasEffect(ore, "frostbite")) then return nil end
        end

        st.UpgraderIndex = i
        st.Status = string.format("CYCLE%d:%s", cycleIdx, u.Name)
        st.lastU = u.Name

        local r = fxRunStep(ore, st, snap, u)
        if r == "defer" then st.deferred[u] = true; return nil end
        if r ~= "ok" then
            if r == "sellnow" then st.Reason = "HAZARD@" .. u.Name end
            return r
        end
        passRan[u] = true

        local after = getOreCash(ore)
        if after then
            st.LastCash = after
            if State.sellForRebirth and oreWouldFundRebirth(after) then
                st.Status = "REBIRTH_FUNDED"; st.Reason = "FUNDED"
                return "sellnow"
            end
            if after >= INSTA_SELL_VALUE then st.Status = "MAX_VALUE"; st.Reason = "MAX"; return "sellnow" end
        end
        return nil
    end

    for i = 1, #order do
        local r = step(i, order[i])
        if r then return r end
    end

    -- The order is fixed from the value the ore had when the pass began. A capped
    -- machine behind a floor (Molten, Horizon, Transistor...) was skipped for good
    -- if the ore had not reached the floor yet when its turn came. Now that the
    -- ore is worth more, give those machines their turn and let each unlock the next.
    for _ = 1, 3 do
        local c0 = getOreCash(ore)
        if not c0 then return "destroyed" end
        local order2 = getOptimalUpgraderOrder(ore, snap.normal)
        st.order = order2
        local ranAny = false
        for i = 1, #order2 do
            local u = order2[i]
            if u.Loopability == "Unlimited" and u.CapValue and not passRan[u] then
                local c = getOreCash(ore)
                if c and upgraderCanAct(u, c) then
                    local r = step(i, u)
                    if r then return r end
                    if passRan[u] then ranAny = true end
                end
            end
        end
        if not ranAny then break end
        local c1 = getOreCash(ore)
        if not c1 or c1 <= c0 then break end
    end

    return "ok"
end

-- ── SELL LOG ─────────────────────────────────────────────────
-- Why did that ore sell where it did? One tiny record per sale, 60 kept.
SellLog = { n = 0, ring = {}, counts = {}, dn = 0, dring = {}, dwipe = 0, clean = {} }
function recordSell(ore, st)
    local c = getOreCash(ore) or st.LastCash or 0
    local reason = st.Reason
    if not reason then reason = (c >= INSTA_SELL_VALUE) and "END_MAX" or "END_LOW" end
    local L = SellLog
    L.n = L.n + 1
    local cat = reason:match("^[^@]+") or reason
    L.counts[cat] = (L.counts[cat] or 0) + 1
    L.ring[(L.n - 1) % 60 + 1] = { n = L.n, cash = c, reason = reason, last = st.lastU or "-", cyc = st.Passes or 0, det = st.hazDetail }
end

function recordDeath(st)
    local L = SellLog
    L.dn = L.dn + 1
    local wipe = State.lastRebirthAt ~= nil and os.clock() - State.lastRebirthAt < 5
    if wipe then L.dwipe = L.dwipe + 1 end
    L.dring[(L.dn - 1) % 30 + 1] = {
        n = L.dn, wipe = wipe, age = os.clock() - (st.born or os.clock()), status = st.Status or "-",
        last = st.lastU or "-", cash = st.LastCash or 0, fx = fxDescribe(st, os.clock(), "fx"),
    }
end

function printSellReport()
    local L = SellLog
    if L.n == 0 and L.dn == 0 then
        UI:Notify({ Title = "Sell Report", Content = "No ores sold yet.", Type = "Info" })
        return
    end
    print("")
    print("  SELL REPORT  (" .. L.n .. " ores this session)")
    for cat, n in pairs(L.counts) do
        print(string.format("    %-10s %5d  %.0f%%", cat, n, n / L.n * 100))
    end
    print("  cleaner results (machine|effect):")
    for key, c in pairs(L.clean) do
        print(string.format("    %-34s cleared %d · stayed %d", key, c[1], c[2]))
    end
    print("  last sales (log10 value · reason · last machine):")
    local from = math.max(1, L.n - 14)
    for k = from, L.n do
        local r = L.ring[(k - 1) % 60 + 1]
        if r and r.n == k then
            print(string.format("    #%d  e%-6.1f  %-22s %s%s", r.n, r.cash > 0 and math.log10(r.cash) or 0, r.reason, r.last, r.det and ("\n          " .. r.det) or ""))
        end
    end
    print("")
    if L.dn > 0 then
        print("  DIED BEFORE SELLING  " .. L.dn .. "  (" .. L.dwipe .. " within 5s of a rebirth)  (age · status · last machine · value · effects)")
        for k = math.max(1, L.dn - 9), L.dn do
            local r = L.dring[(k - 1) % 30 + 1]
            if r and r.n == k then
                print(string.format("    #%d  %.1fs  %-22s %s  e%.1f  %s%s", r.n, r.age, r.status, r.last, r.cash > 0 and math.log10(r.cash) or 0, r.fx, r.wipe and "  [rebirth]" or ""))
            end
        end
        print("")
    end
    local maxN = (L.counts.MAX or 0) + (L.counts.END_MAX or 0)
    UI:Notify({ Title = "Sell Report", Content = string.format("%d sold · %d died · %d max · %d low (see console)", L.n, L.dn, maxN, L.counts.END_LOW or 0), Type = "Info", Duration = 6 })
end

local UpgraderCache = {}

-- ── REPLACEMENT 1: routeOreWorker ────────────────────────────
function routeOreWorker(ore, factoryName, gen)
    if OreStates[ore] then return end
    if State.cellFurnaceMode then return end
    local st = {
        UpgraderIndex = 0, Passes = 0, Status = "INIT", LastCash = nil,
        gen = gen or EngineGen, born = os.clock(), sold = false,
        fx = {}, used = {}, ran = {}, deferred = {},
        tail = false, trips = 0, baseIce = false,
    }
    OreStates[ore] = st

    local function release()
        if not st.sold and not ore.Parent then recordDeath(st) end
        if OreStates[ore] == st then OreStates[ore] = nil end
    end

    if not isValidOre(ore, factoryName) then release() return end
    local initCash = getOreCash(ore)
    if initCash ~= nil and initCash <= 0 then
        pcall(function() ore:Destroy() end)
        release() return
    end

    local snap = getSnapshot()
    if not snap or snap.factory.Name ~= factoryName then release() return end

    st.baseIce = ore.Material == Enum.Material.Ice
    fxScan(ore, st, os.clock())

    local function sellAndRelease()
        st.sold = true
        if ore.Parent then recordSell(ore, st) end
        if ore.Parent and snap.furnace then
            st.Status = "INSTA_SELL"
            sellOre(ore, snap.furnace)
        end
        release()
    end

    local cycleIdx = 0
    while cycleIdx < 40 do
        if rtHalt(st) or not ore.Parent then release() return end
        snap = getSnapshot() or snap
        if snap.factory.Name ~= factoryName then release() return end

        local result = runUpgraderPass(ore, snap, st, cycleIdx)
        if result == "destroyed" or result == "stopped" then release() return end
        if result == "sellnow" then sellAndRelease() return end

        local tesla = snap.teslas[cycleIdx + 1]
        if tesla then
            local g = fxGuard(ore, st, snap, nil)
            if g == "sellnow" then sellAndRelease() return end
            if g ~= "ok" then release() return end

            st.Status = string.format("RESET%d:%s", cycleIdx + 1, tesla.Name)
            local t0 = os.clock()
            local survived = fireTesla(ore, tesla)
            if not survived then release() return end
            st.used = {}
            st.badClean = nil
            st.cleanFails = nil
            st.hazTry = nil
            fxScan(ore, st, t0)
            task.wait(0.05)
            cycleIdx = cycleIdx + 1
        else
            local tr = fxRunTail(ore, st, snap)
            if tr == "destroyed" or tr == "stopped" then release() return end
            if tr == "ok" and not State.usePostDelayItems then
                st.Status = "EDU_PRESELL"
                runEducationUpgraderNoWait(ore, snap)
                if rtHalt(st) or not ore.Parent then release() return end
            end
            st.Status = "SELLING"
            sellAndRelease()
            return
        end
    end
    release()
end


local CellOreStates   = {}
local CellEngineConns = {}
local CellStopped     = false

CellGen = 0

function routeCellOreWorker(ore, factoryName)
    if CellOreStates[ore] then return end
    CellOreStates[ore] = true
    if not isValidOre(ore, factoryName) then CellOreStates[ore] = nil; return end

    local gen = CellGen
    local deadline = os.clock() + 20
    local part
    while ore.Parent do
        if not State.cellFurnaceMode or CellStopped or gen ~= CellGen then break end
        if os.clock() > deadline then break end

        if not (part and part.Parent) then
            local snap = getSnapshot()
            if not snap or snap.factory.Name ~= factoryName then break end
            local cell = snap.cell
            part = nil
            if cell then
                part = (cell.SellPart and cell.SellPart.Parent) and cell.SellPart or findFurnaceSellPart(cell.Item)
                cell.SellPart = part
            end
            if not part then
                task.wait(0.5)
                continue
            end
        end
        oreSet(ore, part.CFrame + CELL_OFFSET)
        task.wait(0.03)
    end

    CellOreStates[ore] = nil
end

function processCellOreCandidate(ore, factoryName)
    if CellOreStates[ore] then return end
    if not isValidOre(ore, factoryName) then return end
    task.spawn(routeCellOreWorker, ore, factoryName)
end

function stopCellDiscovery()
    CellGen = CellGen + 1
    CellStopped           = true
    State.cellFurnaceMode = false
    for _, conn in ipairs(CellEngineConns) do pcall(function() conn:Disconnect() end) end
    CellEngineConns = {}
    CellOreStates   = {}
end

function startCellDiscovery()
    CellGen = CellGen + 1
    local gen = CellGen
    CellStopped = false
    CellOreStates = {}
    for _, conn in ipairs(CellEngineConns) do pcall(function() conn:Disconnect() end) end
    CellEngineConns = {}

    local oreContainer, factory = getOreContainer()
    if not oreContainer or not factory then return end
    local factoryName = factory.Name

    local snap = getSnapshot()
    if not snap or not snap.cell then
        UI:Notify({
            Title   = "Cell Furnace Mode",
            Content = "No cell furnace found on base. Place one first.",
            Type    = "Error",
            Duration = 5,
        })
        State.cellFurnaceMode = false
        return
    end

    for _, ore in ipairs(oreContainer:GetChildren()) do
        processCellOreCandidate(ore, factoryName)
    end

    CellEngineConns[#CellEngineConns + 1] = oreContainer.ChildAdded:Connect(function(ore)
        if gen ~= CellGen or not State.cellFurnaceMode then return end
        task.delay(0.04, function()
            if gen == CellGen then processCellOreCandidate(ore, factoryName) end
        end)
    end)
    CellEngineConns[#CellEngineConns + 1] = oreContainer.ChildRemoved:Connect(function(ore)
        CellOreStates[ore] = nil
    end)

    task.spawn(function()
        while gen == CellGen and State.cellFurnaceMode and not CellStopped do
            task.wait(4)
            if gen ~= CellGen or not State.cellFurnaceMode or CellStopped then break end
            local container, fac = getOreContainer()
            if container and fac then
                local kids = container:GetChildren()
                for i = 1, #kids do processCellOreCandidate(kids[i], fac.Name) end
            end
        end
    end)
end

function processOreCandidate(ore, factoryName)
    if OreStates[ore] then return end
    if not isValidOre(ore, factoryName) then return end
    task.spawn(routeOreWorker, ore, factoryName, EngineGen)
end

function stopOreDiscovery()
    EngineGen        = EngineGen + 1
    EngineStopped    = true
    State.oreBooster = false
    for _, conn in ipairs(EngineConns) do pcall(function() conn:Disconnect() end) end
    EngineConns = {}
    OreStates   = {}
end

function startOreDiscovery()
    EngineGen     = EngineGen + 1
    local gen     = EngineGen
    EngineStopped = false
    OreStates     = {}
    for _, conn in ipairs(EngineConns) do pcall(function() conn:Disconnect() end) end
    EngineConns = {}

    -- One supervisor owns the engine for as long as the booster is on. It binds
    -- to whatever ore container exists, rebinds when the container is replaced
    -- (rebirth, new life, layout reload) and idles while there is none. Nothing
    -- ever has to stop and restart it, so a rebirth cannot leave it dead.
    task.spawn(function()
        local boundContainer, boundFactory, boundName
        local nextScan = 0

        local function unbind()
            for _, conn in ipairs(EngineConns) do pcall(function() conn:Disconnect() end) end
            EngineConns = {}
            boundContainer, boundFactory, boundName = nil, nil, nil
        end

        while gen == EngineGen and State.oreBooster and not EngineStopped do
            pcall(function()
                local container, fac = getOreContainer()
                if container and fac then
                    if container ~= boundContainer or fac ~= boundFactory then
                        unbind()
                        OreStates = {}
                        boundContainer, boundFactory, boundName = container, fac, fac.Name
                        local name = boundName
                        EngineConns[1] = container.ChildAdded:Connect(function(ore)
                            if gen ~= EngineGen or not State.oreBooster then return end
                            processOreCandidate(ore, name)
                        end)
                        EngineConns[2] = container.ChildRemoved:Connect(function(ore)
                            OreStates[ore] = nil
                        end)
                        getSnapshot() -- warm it once so the first ores don't each trigger the scan
                        nextScan = 0
                    end
                    local now = os.clock()
                    if now >= nextScan then
                        nextScan = now + 1
                        local list = container:GetChildren()
                        for i = 1, #list do processOreCandidate(list[i], boundName) end
                    end
                elseif boundContainer then
                    unbind()
                end
            end)
            task.wait(0.25)
        end
        if gen == EngineGen then unbind() end
    end)
end

function canAffordRebirth(cash)
    local ok, cost = pcall(MoneyLib.RebornPrice, lp)
    return ok and cash >= cost
end

RB = { t = -10, key = nil, reborn = math.huge, skip = 0 }

function rebirthCosts()
    local now = os.clock()
    local key = tostring(State.waitSkip) .. ":" .. tostring(State.skipCount)
    if RB.key == key and now - RB.t < 0.5 then return RB.reborn, RB.skip end

    local ok, price = pcall(MoneyLib.RebornPrice, lp)
    local reborn = (ok and tonumber(price)) or math.huge
    local skip = 0
    if State.waitSkip and State.skipCount > 0 then
        local sok, scost = pcall(MoneyLib.CalculateLifeSkips, lp, State.skipCount)
        if not sok then
            skip = math.huge
        else
            skip = tonumber(scost) or math.huge
        end
    end
    RB.key, RB.t, RB.reborn, RB.skip = key, now, reborn, skip
    return reborn, skip
end

function readyToRebirth()
    local cash = getCash()   -- single read, no race
    local reborn, skip = rebirthCosts()
    if reborn == math.huge or skip == math.huge then return false end
    return cash >= reborn + skip
end


local UpdateLimit = Channel("UpdateLimit")

local ChangeSetting = Channel("ChangeSetting")

function enableLifeSkipIfNeeded()
    local playerSettings = lp:FindFirstChild("PlayerSettings")
    if not playerSettings then return end
    local lifeSkipVal = playerSettings:FindFirstChild("LifeSkip")
    if lifeSkipVal and not lifeSkipVal.Value then
        pcall(function() ChangeSetting:InvokeServer("LifeSkip") end)
    end
end



function doRebirth()
    State.RebirthPending = false  -- reset for next life
    if State.waitSkip and State.skipCount > 0 then
        enableLifeSkipIfNeeded()
        local fraction = math.clamp(State.skipCount, 0, 20) / 20
        pcall(function() Channel("UpdateLimit"):FireServer("Skipped", fraction) end)
        callProcessAction("SkipLife", State.skipCount)
    end
    local okc, cashBefore = pcall(getCash)
    if not okc then cashBefore = nil end
    local fired, path = callRebirth()
    if fired then State.lastRebirthAt = os.clock() end
    if fired then pcall(function() onRebirthSignal({ cash = cashBefore }) end) end
    if fired and State.autoLoadLayout1 then
        State.layoutBusy = true
        task.spawn(function()
            for _ = 1, 300 do
                if LC_getMyBase() then break end
                task.wait()
            end
            for _ = 1, 3 do
                if callLayouts("Load", State.layout1Choice) then break end
                task.wait(0.2)
            end
            State.layoutBusy = false
        end)
    end
    return fired, path
end


function tpToFactory()
    local factory = getMyFactory()
    if not factory then return end
    local base = factory:FindFirstChild("Base")
    local hrp  = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if hrp and base then hrp.CFrame = base.CFrame + Vector3.new(0, 12, 0) end
end
function doWithdrawAll()
    -- DestroyAll is the server-side withdraw; Placement.withdrawAll() is only
    -- the local placement UI reset. The remote lives on the Net channels,
    -- not as an Instance in ReplicatedStorage.
    local sent = false
    local ch = Channel("DestroyAll")
    if ch then
        if type(ch.Invoke) == "function" then
            sent = pcall(function() ch:Invoke() end)
        elseif type(ch.InvokeServer) == "function" then
            sent = pcall(function() ch:InvokeServer() end)
        elseif type(ch.Fire) == "function" then
            sent = pcall(function() ch:Fire() end)
        end
    end
    local gui = lp.PlayerGui:FindFirstChild("GUI")
    local placement = gui and gui:FindFirstChild("Placement")
    if placement then
        local ok, mod = pcall(require, placement)
        if ok and type(mod) == "table" and mod.withdrawAll then
            pcall(function() mod.withdrawAll() end)
        end
    end
    return sent
end
-- Direct placement: read the saved layout, work out every CFrame up front (pure
-- math, no yields), then fire every PlaceItem at once instead of one at a time.
-- Returns ok, placedCalls, totalJobs.
function fastLoadLayout(key)
    if not Net.PlaceItem then return false, 0, nil end
    local num = tonumber(key:match("%d+")) or 1
    local okd, data = LC_DecodeLayout(lp.Name, num)
    if not okd or type(data) ~= "table" or #data == 0 then return false, 0, nil end
    local base = LC_getMyBase()
    if not base then return false, 0, nil end

    local jobs = {}
    for _, e in ipairs(data) do
        local id = tonumber(e.ItemId)
        local cf = id and LC_BuildCFrame(e, base)
        if cf then jobs[#jobs + 1] = { id = id, cf = cf } end
    end
    if #jobs == 0 then return false, 0, nil end

    local pending, placed = #jobs, 0
    local BATCH = 40 -- spread the burst over a few frames so it can't hitch
    for i = 1, #jobs do
        local j = jobs[i]
        task.spawn(function()
            if pcall(function() Net.PlaceItem:Invoke(j.id, j.cf, base) end) then placed = placed + 1 end
            pending = pending - 1
        end)
        if i % BATCH == 0 then task.wait() end
    end
    local t0 = os.clock()
    while pending > 0 and os.clock() - t0 < 8 do task.wait(0.05) end
    return placed >= #jobs * 0.9, placed, #jobs
end

function doLoadLayout(key)
    -- Never withdraw the base unless there is something to load it back with.
    if not layoutRemoteExists() and not (State.fastLayout and Net.PlaceItem) then
        pcall(function() UI:Notify({ Title = "Layout", Content = "Layouts remote not found.", Type = "Error" }) end)
        return false
    end
    local factory = getMyFactory()
    doWithdrawAll()
    task.wait(0.1)
    local before = factory and #factory:GetChildren() or 0
    local loaded = false
    if State.fastLayout then
        local _, _, total = fastLoadLayout(key)
        if total and factory then
            local t0 = os.clock()
            while os.clock() - t0 < 2 do
                if #factory:GetChildren() - before >= total * 0.9 then loaded = true; break end
                task.wait(0.1)
            end
        end
    end
    -- anything the direct placement could not do (unowned shiny ids, shop items)
    -- is left to the game's own loader
    for _ = 1, (loaded and 0 or 3) do
        callLayouts("Load", key)
        local t0 = os.clock()
        while os.clock() - t0 < 3 do
            if factory and #factory:GetChildren() > before then loaded = true; break end
            task.wait(0.1)
        end
        if loaded then break end
    end
    -- the base changed shape: have the next ore read a fresh snapshot
    FxSnap.dirty, FxSnap.dirtyAt = true, os.clock() - 1
    return loaded
end

function getBoxPart(box)
    if box:IsA("BasePart") then return box end
    if box:IsA("Model") then return box.PrimaryPart or box:FindFirstChildWhichIsA("BasePart") end
    return nil
end

-- ── ORE HIDE TOGGLE ──────────────────────────────────────────
local OreHideActive = false
local OreHideConn   = nil

function setOreVisibility(hidden)
    -- Apply to all currently existing ores
    local container, factory = getOreContainer()
    if container and factory then
        local factoryName = factory.Name
        for _, ore in ipairs(container:GetChildren()) do
            pcall(function()
                if not ore or not ore.Parent then return end
                local owner = ore:GetAttribute("Owner")
                if owner and owner ~= factoryName then return end
                if ore:IsA("BasePart") then
                    ore.LocalTransparencyModifier = hidden and 1 or 0
                    ore.CastShadow = not hidden
                end
            end)
        end
    end
end

function startOreHide()
    if OreHideConn then return end
    OreHideActive = true
    setOreVisibility(true)

    -- Watch for new ores and hide them immediately as they land
    local container, factory = getOreContainer()
    if not container or not factory then return end
    local factoryName = factory.Name

    OreHideConn = container.ChildAdded:Connect(function(ore)
        if not OreHideActive then return end
        pcall(function()
            if not ore or not ore.Parent then return end
            local owner = ore:GetAttribute("Owner")
            if owner and owner ~= factoryName then return end
            if ore:IsA("BasePart") then
                ore.LocalTransparencyModifier = 1
                ore.CastShadow = false
            end
        end)
    end)
end

function stopOreHide()
    OreHideActive = false
    if OreHideConn then
        pcall(function() OreHideConn:Disconnect() end)
        OreHideConn = nil
    end
    setOreVisibility(false)
end

-- ── FPS BOOST MODULE ─────────────────────────────────────────
local FPS = {
    particlesDisabled  = false,
    shadowsDisabled    = false,
    soundsMuted        = false,
    lodActive          = false,
    particleConns      = {},
    savedEmitterRates  = {},   -- [emitter] = originalRate
    savedSoundVolumes  = {},   -- [sound]   = originalVolume
    savedShadows       = {},
    savedFog           = nil,
}

-- PARTICLES: disable all emitters in workspace
function disableParticles()
    if FPS.particlesDisabled then return end
    FPS.particlesDisabled = true
    FPS.savedEmitterRates = {}

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ParticleEmitter") then
            FPS.savedEmitterRates[obj] = obj.Rate
            obj.Rate = 0
            pcall(function() obj:Clear() end)
        elseif obj:IsA("Beam") then
            FPS.savedEmitterRates[obj] = obj.Enabled
            obj.Enabled = false
        elseif obj:IsA("Trail") then
            FPS.savedEmitterRates[obj] = obj.Enabled
            obj.Enabled = false
        end
    end

    -- Watch for new ones added after the fact (mines spawning new effects)
    local conn = workspace.DescendantAdded:Connect(function(obj)
        if not FPS.particlesDisabled then return end
        if obj:IsA("ParticleEmitter") then
            task.defer(function()
                if FPS.particlesDisabled then
                    FPS.savedEmitterRates[obj] = obj.Rate
                    obj.Rate = 0
                    pcall(function() obj:Clear() end)
                end
            end)
        elseif obj:IsA("Beam") or obj:IsA("Trail") then
            task.defer(function()
                if FPS.particlesDisabled then
                    FPS.savedEmitterRates[obj] = obj.Enabled
                    obj.Enabled = false
                end
            end)
        end
    end)
    table.insert(FPS.particleConns, conn)
end

function enableParticles()
    if not FPS.particlesDisabled then return end
    FPS.particlesDisabled = false

    for _, conn in ipairs(FPS.particleConns) do
        pcall(function() conn:Disconnect() end)
    end
    FPS.particleConns = {}

    for obj, saved in pairs(FPS.savedEmitterRates) do
        pcall(function()
            if not obj or not obj.Parent then return end
            if obj:IsA("ParticleEmitter") then
                obj.Rate = saved
            elseif obj:IsA("Beam") or obj:IsA("Trail") then
                obj.Enabled = saved
            end
        end)
    end
    FPS.savedEmitterRates = {}
end

-- SHADOWS: drop to No shadows (biggest single GPU win on ShadowMap)
function disableShadows()
    if FPS.shadowsDisabled then return end
    FPS.shadowsDisabled = true
    FPS.savedShadows = {}
    local function strip(obj)
        if obj:IsA("BasePart") then
            if FPS.savedShadows[obj] == nil then FPS.savedShadows[obj] = obj.CastShadow end
            obj.CastShadow = false
        end
    end
    for _, obj in ipairs(workspace:GetDescendants()) do strip(obj) end
    FPS.shadowConn = workspace.DescendantAdded:Connect(function(obj)
        if not FPS.shadowsDisabled then return end
        task.defer(function()
            if FPS.shadowsDisabled and obj.Parent then strip(obj) end
        end)
    end)
end

function enableShadows()
    if not FPS.shadowsDisabled then return end
    FPS.shadowsDisabled = false
    if FPS.shadowConn then pcall(function() FPS.shadowConn:Disconnect() end) end
    FPS.shadowConn = nil
    for obj, saved in pairs(FPS.savedShadows) do
        pcall(function()
            if obj and obj.Parent then obj.CastShadow = saved end
        end)
    end
    FPS.savedShadows = {}
end

-- SOUNDS: mute all playing sounds
function muteSounds()
    if FPS.soundsMuted then return end
    FPS.soundsMuted = true
    FPS.savedSoundVolumes = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Sound") then
            FPS.savedSoundVolumes[obj] = obj.Volume
            obj.Volume = 0
        end
    end
    local conn = workspace.DescendantAdded:Connect(function(obj)
        if not FPS.soundsMuted then return end
        if obj:IsA("Sound") then
            task.defer(function()
                if FPS.soundsMuted then
                    FPS.savedSoundVolumes[obj] = obj.Volume
                    obj.Volume = 0
                end
            end)
        end
    end)
    table.insert(FPS.particleConns, conn)
end

function unmuteSounds()
    if not FPS.soundsMuted then return end
    FPS.soundsMuted = false
    for obj, vol in pairs(FPS.savedSoundVolumes) do
        pcall(function()
            if obj and obj.Parent then obj.Volume = vol end
        end)
    end
    FPS.savedSoundVolumes = {}
end

-- LOD: reduce render distance and disable decorations
-- Terrain.Decoration was removed in the update: reading it throws, so every
-- access is guarded and a missing property simply means "nothing to restore".
local function safeTerrainDecoration(terrain)
    if not terrain then return nil end
    local ok, value = pcall(function() return terrain.Decoration end)
    if ok then return value end
    return nil
end

function enableLOD()
    if FPS.lodActive then return end
    FPS.lodActive = true
    local L = game:GetService("Lighting")
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    FPS.savedFog = {
        start = L.FogStart,
        stop  = L.FogEnd,
        color = L.FogColor,
        deco  = safeTerrainDecoration(terrain),
    }
    pcall(function()
        L.FogStart = 200
        L.FogEnd   = 300
        L.FogColor = Color3.fromRGB(0, 0, 0)
    end)
    if terrain then pcall(function() terrain.Decoration = false end) end
end

function disableLOD()
    if not FPS.lodActive then return end
    FPS.lodActive = false
    local L = game:GetService("Lighting")
    local f = FPS.savedFog
    if f then
        pcall(function()
            L.FogStart = f.start
            L.FogEnd   = f.stop
            L.FogColor = f.color
        end)
        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if terrain and f.deco ~= nil then
            pcall(function() terrain.Decoration = f.deco end)
        end
    end
    FPS.savedFog = nil
end
-- ── END FPS BOOST MODULE ─────────────────────────────────────

-- ── NUKE MODE: hide everything except your base ───────────────
local NukeMode = {
    active = false,
    hidden = {},       -- [obj] = { parts that had transparency changed }
    conns  = {},
}

function nukeSetVisible(obj, visible)
    -- Make a model/part visible or invisible locally
    if not obj or not obj.Parent then return end
    local transparency = visible and 0 or 1
    local castShadow   = visible and true or false
    if obj:IsA("BasePart") then
        pcall(function()
            obj.LocalTransparencyModifier = transparency
            obj.CastShadow = castShadow
        end)
    end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("BasePart") then
            pcall(function()
                d.LocalTransparencyModifier = transparency
                d.CastShadow = castShadow
            end)
        elseif d:IsA("ParticleEmitter") then
            pcall(function() d.Rate = visible and d.Rate or 0 end)
        elseif d:IsA("Beam") or d:IsA("Trail") then
            pcall(function() d.Enabled = visible end)
        elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("ScreenGui") then
            pcall(function() d.Enabled = visible end)
        end
    end
end

function startNukeMode()
    if NukeMode.active then return end
    NukeMode.active = true
    NukeMode.hidden = {}

    local myFactory = getMyFactory()
    if not myFactory then
        UI:Notify({ Title="Nuke Mode", Content="Can't find your factory.", Type="Error" })
        NukeMode.active = false
        return
    end

    local myFactoryName = myFactory.Name
    local dp = workspace:FindFirstChild("DroppedParts")

    -- List of workspace children to completely nuke
    local nukeNames = {
        "LeaderboardModels",
        "Map",
        "Market",
        "ZOMBIE_SPAWNS",
        "Evil Roomba",
        "Boxes",
        "FakeBases",
        "TutorialHolograms",
        "TutorialObstructedHolograms",
        "GunRays",
        "New Models",
        "NewLocations",
        "SafeZones",
        "Paths",
        "Clovers",
    }

    -- Nuke named folders
    for _, name in ipairs(nukeNames) do
        local obj = workspace:FindFirstChild(name)
        if obj then
            table.insert(NukeMode.hidden, obj)
            task.spawn(nukeSetVisible, obj, false)
        end
    end

    -- Nuke Void Guardians (there are 2)
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name == "Void Guardian" then
            table.insert(NukeMode.hidden, obj)
            task.spawn(nukeSetVisible, obj, false)
        end
    end

    -- Nuke other players' tycoons
    local Tycoons = workspace:FindFirstChild("Tycoons")
    if Tycoons then
        for _, f in ipairs(Tycoons:GetChildren()) do
            if f.Name ~= myFactoryName then
                table.insert(NukeMode.hidden, f)
                task.spawn(nukeSetVisible, f, false)
            end
        end
    end

    -- Nuke other players' DroppedParts
    if dp then
        for _, container in ipairs(dp:GetChildren()) do
            if container.Name ~= myFactoryName then
                table.insert(NukeMode.hidden, container)
                task.spawn(nukeSetVisible, container, false)
            end
        end
    end

    -- Nuke other player character models (floating names in world)
    for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
        if p ~= lp and p.Character then
            table.insert(NukeMode.hidden, p.Character)
            task.spawn(nukeSetVisible, p.Character, false)
        end
    end

    -- Watch for new characters/tycoons that get added while nuke is active
    local c1 = game:GetService("Players").PlayerAdded:Connect(function(p)
        if not NukeMode.active then return end
        p.CharacterAdded:Connect(function(char)
            if not NukeMode.active then return end
            task.wait(0.1)
            table.insert(NukeMode.hidden, char)
            nukeSetVisible(char, false)
        end)
    end)
    local c2 = game:GetService("Players").PlayerRemoving:Connect(function() end)
    table.insert(NukeMode.conns, c1)
    table.insert(NukeMode.conns, c2)

    -- Watch for new tycoons added (shouldn't happen mid-session but just in case)
    if Tycoons then
        local c3 = Tycoons.ChildAdded:Connect(function(f)
            if not NukeMode.active then return end
            if f.Name ~= myFactoryName then
                task.wait(0.5)
                table.insert(NukeMode.hidden, f)
                nukeSetVisible(f, false)
            end
        end)
        table.insert(NukeMode.conns, c3)
    end

    UI:Notify({
        Title   = "Nuke Mode",
        Content = "Everything except Factory5 hidden. Everything except your base is hidden.",
        Type    = "Success",
        Duration = 5,
    })
end

function stopNukeMode()
    if not NukeMode.active then return end
    NukeMode.active = false

    for _, conn in ipairs(NukeMode.conns) do
        pcall(function() conn:Disconnect() end)
    end
    NukeMode.conns = {}

    for _, obj in ipairs(NukeMode.hidden) do
        task.spawn(nukeSetVisible, obj, true)
    end
    NukeMode.hidden = {}

    UI:Notify({ Title="Nuke Mode", Content="Everything restored.", Type="Info" })
end
-- ── END NUKE MODE ─────────────────────────────────────────────

-- ── ULTRA PERFORMANCE MODE ────────────────────────────────────
local UltraMode = {
    active          = false,
    savedTech       = nil,
    savedShadows    = nil,
    savedQuality    = nil,
    savedFogEnd     = nil,
    savedFogStart   = nil,
    savedBrightness = nil,
    savedTransparency = nil,
}

function startUltraMode()
    if UltraMode.active then return end
    UltraMode.active = true

    local L   = game:GetService("Lighting")
    local ugs = UserSettings().GameSettings

    -- Save current state
    UltraMode.savedShadows    = L.GlobalShadows
    UltraMode.savedFogEnd     = L.FogEnd
    UltraMode.savedFogStart   = L.FogStart
    UltraMode.savedBrightness = L.Brightness

    pcall(function() L.GlobalShadows   = false end)
    pcall(function() L.Brightness      = 2 end)

    -- 3. Aggressive fog — kills anything past 150 studs dead
    pcall(function()
        L.FogStart = 100
        L.FogEnd   = 150
        L.FogColor = Color3.fromRGB(0, 0, 0)
    end)

    -- 4. Kill decorations
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        pcall(function() terrain.Decoration = false end)
    end

    -- 5. Make every non-essential part on your base transparent that isn't
    --    a conveyor, hitbox, or sell part — purely visual decoration parts
    local Players = game:GetService("Players")
    local lp2     = Players.LocalPlayer
    local Tycoons = workspace:FindFirstChild("Tycoons")
    local factory
    if Tycoons then
        for _, f in ipairs(Tycoons:GetChildren()) do
            local o = f:FindFirstChild("Owner")
            if o and o.Value == lp2.Name then factory = f; break end
        end
    end

    if factory then
        -- Names of parts that MUST stay visible (functional)
        local KEEP = {
            Lava=true, MiniLava=true, Conv=true, Conveyor=true,
            Base=true, Upgrade=true, Upgrader=true, Cannon=true,
            Beam=true, Trigger=true, Touch=true, Scan=true,
            Scanner=true, Sensor=true, HitBox=true, Hitbox=true,
        }
        local hidden = 0
        for _, d in ipairs(factory:GetDescendants()) do
            if d:IsA("BasePart") and not KEEP[d.Name] then
                -- Only hide pure decoration (small, non-functional parts)
                -- Keep parts with functional children
                local hasFunctional = false
                for _, c in ipairs(d:GetChildren()) do
                    if c:IsA("Script") or c:IsA("LocalScript")
                        or c:IsA("TouchTransmitter") then
                        hasFunctional = true
                        break
                    end
                end
                if not hasFunctional and d.Size.Magnitude < 4 then
                    pcall(function()
                        UltraMode.savedTransparency = UltraMode.savedTransparency or {}
                        UltraMode.savedTransparency[d] = d.LocalTransparencyModifier
                        d.LocalTransparencyModifier = 1
                        d.CastShadow = false
                    end)
                    hidden += 1
                end
            end
        end
    end

    UI:Notify({
        Title   = "Ultra Performance Mode",
        Content = "Global shadows off, aggressive fog, decoration parts hidden. Use the FPS tab to measure the gain.",
        Type    = "Success",
        Duration = 6,
    })
end

function stopUltraMode()
    if not UltraMode.active then return end
    UltraMode.active = false

    local L   = game:GetService("Lighting")
    local ugs = UserSettings().GameSettings

    pcall(function() L.GlobalShadows = UltraMode.savedShadows end)
    pcall(function() L.Brightness    = UltraMode.savedBrightness end)
    pcall(function() L.FogEnd        = UltraMode.savedFogEnd end)
    pcall(function() L.FogStart      = UltraMode.savedFogStart end)

    -- Restore decoration parts
    local Players = game:GetService("Players")
    local lp2 = Players.LocalPlayer
    local Tycoons = workspace:FindFirstChild("Tycoons")
    local factory
    if Tycoons then
        for _, f in ipairs(Tycoons:GetChildren()) do
            local o = f:FindFirstChild("Owner")
            if o and o.Value == lp2.Name then factory = f; break end
        end
    end
    if factory then
        for _, d in ipairs(factory:GetDescendants()) do
            if d:IsA("BasePart") then
                pcall(function() d.LocalTransparencyModifier = UltraMode.savedTransparency and UltraMode.savedTransparency[d] or 0 end)
            end
        end
    end

    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then pcall(function() terrain.Decoration = true end) end

    UI:Notify({ Title="Ultra Mode", Content="Restored.", Type="Info" })
end
-- ── END ULTRA PERFORMANCE MODE ───────────────────────────────

local firecystalConn = nil

function findFirecystalMine(factory)
    for _, item in ipairs(factory:GetChildren()) do
        if item.Name == "Industrial Rainbow Mine"
            or item.Name == "Industrial Firecrystal Mine" then
            local model = item:FindFirstChildOfClass("Model") or item
            for _, partName in ipairs({"Lava"}) do
                local p = model:FindFirstChild(partName)
                if p and p:IsA("BasePart") then return item, p end
            end
            for _, c in ipairs(model:GetChildren()) do
                if c:IsA("BasePart") and c.Name ~= "Mine" and c.Name ~= "Base" then
                    return item, c
                end
            end
        end
    end
    return nil, nil
end

function findCoalInContainer(container, factoryName)
    local coal = {}
    for _, ore in ipairs(container:GetChildren()) do
        if ore and ore.Parent and ore:IsA("BasePart") then
            local name = ore.Name:lower()
            if name:find("coal") then
                local owner = ore:GetAttribute("Owner")
                if not owner or owner == factoryName then
                    table.insert(coal, ore)
                end
            end
        end
    end
    return coal
end

function startFirecystalFeed()
    if firecystalConn then return end
    firecystalConn = true
    local gen = _G.DeepveinGen
    task.spawn(function()
        local sellPart
        while State.firecystalFeed and _G.DeepveinGen == gen do
            local factory = getMyFactory()
            if factory then
                if not (sellPart and sellPart.Parent and sellPart:IsDescendantOf(factory)) then
                    local _, p = findFirecystalMine(factory)
                    sellPart = p
                end
                if sellPart then
                    local container, fac = getOreContainer()
                    if container and fac then
                        local kids = container:GetChildren()
                        for i = 1, #kids do
                            local ore = kids[i]
                            if ore:IsA("BasePart") and string.find(ore.Name, "[Cc][Oo][Aa][Ll]") then
                                local owner = ore:GetAttribute("Owner")
                                if not owner or owner == fac.Name then tpOre(ore, sellPart) end
                            end
                        end
                    end
                end
            end
            task.wait(0.1)
        end
        firecystalConn = nil
    end)
end

local layout2WatcherActive = false
local Layout2Gen = 0
local PlanCost = {}

-- LC_LayoutPlan decodes the layout and asks the server about every item, so it
-- is cached for a few seconds instead of being rebuilt on every 0.5s tick.
local function layoutCostCached(num)
    local c = PlanCost[num]
    if c and os.clock() - c.t < 3 then return c.cost end
    local ok, plan = pcall(LC_LayoutPlan, lp.Name, num)
    local cost = ok and plan and plan.cost or nil
    PlanCost[num] = { t = os.clock(), cost = cost }
    return cost
end

function startLayout2Watcher(force)
    if layout2WatcherActive and not force then return end
    -- A new generation retires any watcher still waiting from the previous life,
    -- so two watchers can never both load a layout.
    Layout2Gen = Layout2Gen + 1
    local gen = Layout2Gen
    layout2WatcherActive = true
    PlanCost = {}

    local function alive() return gen == Layout2Gen and State.autoLoadLayout2 end

    local function load(key, label, detail)
        local ok = doLoadLayout(key)
        UI:Notify({ Title = label, Content = key .. (ok and " loaded (" or " load unconfirmed (") .. detail .. ").", Type = ok and "Info" or "Error", Duration = 4 })
    end

    -- A layout is affordable when its own shop shortfall is covered. Owning
    -- everything (cost 0) counts as ready to place.
    local function waitForCost(key)
        local num = tonumber(key:match("%d+")) or 1
        while alive() do
            local cost = layoutCostCached(num)
            if cost and (cost <= 0 or getCash() >= cost) then return true end
            task.wait(0.5)
        end
        return false
    end

    local function waitForTime()
        local t0 = os.clock()
        while alive() and os.clock() - t0 < State.layout2TimeDelay do task.wait(0.25) end
        return alive()
    end

    task.spawn(function()
        local costMode = State.layout2TriggerType ~= "Time"
        local ok
        if costMode then ok = waitForCost(State.layout2Choice) else ok = waitForTime() end
        if not ok then
            if gen == Layout2Gen then layout2WatcherActive = false end
            return
        end
        load(State.layout2Choice, "Layout 2", costMode and "cost covered" or "time trigger")

        if State.autoLoadLayout3 and alive() then
            local ok3
            if costMode then ok3 = waitForCost(State.layout3Choice) else ok3 = waitForTime() end
            if ok3 then load(State.layout3Choice, "Layout 3", costMode and "cost covered" or "time trigger") end
        end
        if gen == Layout2Gen then layout2WatcherActive = false end
    end)
end
local Window = UI:CreateWindow({
    Title    = "Deepvein",
    Subtitle = "Miner's Haven",
    Version  = "1.0"
})

local AutoTab   = Window:CreateTab("Automation", "settings")
local OreTab    = Window:CreateTab("Ore Booster", "sparkles")
local BoxTab    = Window:CreateTab("Boxes", "box")
local LayoutTab = Window:CreateTab("Layouts", "files")
local ProgTab   = Window:CreateTab("Progression", "star")
local NpcTab    = Window:CreateTab("NPCs", "users")
local WebhookTab = Window:CreateTab("Webhook", "bell")

local WebhookState = {
    lastLifeNum     = 0,
    lastRebirthTick = 0,
    url             = "https://discord.com/api/webhooks/1537715992967516171/FWze-Rta0cw35mvNKzOeaf4r7467RBlGrtOwRzDBfjECOc-7J-WsUKyhn22P8pSGc086",
    pingUserId      = "",
    pingOnRebirth   = true,
    pingOnKick      = false,
    pingOnLife      = true,
    lifeThreshold   = 50000,
    pingOnItem      = false,
    watchedItems    = {},
    slipstreamTargets = {},
    sessionStart    = tick(),
    rebirthCount    = 0,
}

function getRequest()
    return request
        or http_request
        or (syn and syn.request)
        or (http and http.request)
        or (fluxus and fluxus.request)
end

function sendWebhook(payload, onDone)
    if WebhookState.url == "" then
        if onDone then onDone(false, "Webhook URL is empty") end
        return false, "Webhook URL is empty"
    end

    local requestFunc = getRequest()

    if typeof(requestFunc) ~= "function" then
        warn("[Webhook] No supported HTTP request function found.")
        if onDone then onDone(false, "No HTTP request function available") end
        return false, "No HTTP request function available"
    end

    local HttpService = game:GetService("HttpService")

    task.spawn(function()
        local success, response = pcall(function()
            return requestFunc({
                Url = WebhookState.url,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                },
                Body = HttpService:JSONEncode(payload),
            })
        end)

        if not success then
            warn("[Webhook] Request failed:", response)
            if onDone then onDone(false, tostring(response)) end
            return
        end

        -- A POST that reaches Discord never throws; a dead or revoked webhook
        -- just comes back as a 4xx. Discord answers 204 on success.
        local status = type(response) == "table" and (response.StatusCode or response.Status) or nil
        local good = type(response) == "table" and (response.Success == true or (type(status) == "number" and status >= 200 and status < 300))
        if good then
            print("[Webhook] Sent successfully (" .. tostring(status) .. ").")
            if onDone then onDone(true, tostring(status)) end
        else
            local body = type(response) == "table" and tostring(response.Body or response.StatusMessage or "") or tostring(response)
            warn("[Webhook] Discord rejected the request: HTTP " .. tostring(status) .. " " .. body)
            if onDone then onDone(false, "HTTP " .. tostring(status) .. " " .. body:sub(1, 120)) end
        end
    end)

    return true
end

function mentionStr()
    local id = WebhookState.pingUserId
    return id ~= "" and ("<@" .. id .. "> ") or ""
end

function fmtTime(secs)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    local s = math.floor(secs % 60)
    return h > 0 and string.format("%dh %dm %ds", h, m, s) or string.format("%dm %ds", m, s)
end

function resetSession()
    WebhookState.sessionStart    = tick()
    WebhookState.rebirthCount    = 0
    WebhookState.lastLifeNum     = 0
    WebhookState.lastRebirthTick = 0
    UI:Notify({ Title = "Session Reset", Content = "Stats reset.", Type = "Success" })
end

function fmtCash(n)
    if n == nil then return "—" end
    if math.abs(n) >= 1e15 then return string.format("%.3e", n) end
    return tostring(math.floor(n))
end

SUFFIXES = { k=1e3, m=1e6, b=1e9, t=1e12, q=1e15 }
function parseLifeNumeric(val)
    local s = tostring(val):gsub(",", ""):gsub("^[^%d%.]+", ""):gsub("[a-zA-Z]+$", function(sfx)
        return SUFFIXES[sfx:lower()] and sfx or ""
    end)
    local num, suffix = s:match("^([%d%.]+)([a-zA-Z]?)$")
    if num then return (tonumber(num) or 0) * (SUFFIXES[suffix:lower()] or 1) end
    return tonumber(s:match("^[%d%.]+")) or 0
end

function sendRebirthEmbed(lifeVal, itemName, rebirthSecs, cashVal, livesSkipped)
    local elapsed = fmtTime(tick() - WebhookState.sessionStart)
    local now = tick()
    local lifeStr = tostring(lifeVal):gsub(",", "")
    local lifeNum = tonumber(lifeStr:match("%d+")) or 0
    local livesGained = lifeNum - WebhookState.lastLifeNum
    local timeDelta = WebhookState.lastRebirthTick > 0 and (now - WebhookState.lastRebirthTick) or tonumber(rebirthSecs) or 0
    local livesPerHr = (timeDelta > 0 and livesGained > 0) and string.format("%.0f", (livesGained / timeDelta) * 3600) or "—"
    WebhookState.lastLifeNum = lifeNum
    WebhookState.lastRebirthTick = now
    local lifeDisplay = tostring(lifeVal):gsub("[snrt][tdh]$", "")
    sendWebhook({
        content = WebhookState.pingOnRebirth and (mentionStr() .. "Rebirth — Life " .. lifeDisplay) or nil,
        embeds = {{
            title = "⛏️ Rebirth — Life " .. lifeDisplay,
            description = "**Miner's Haven** — automated rebirth complete.",
            color = 0xFF6B35,
            fields = {
                { name = "Life Reached", value = lifeDisplay, inline = true },
                { name = "Rebirth Duration", value = rebirthSecs .. "s", inline = true },
                { name = "Cash at Rebirth", value = fmtCash(cashVal), inline = true },
                { name = "Lives Skipped", value = livesSkipped > 0 and tostring(livesSkipped) or "—", inline = true },
                { name = "Lives/hr", value = livesPerHr, inline = true },
                { name = "Session Time", value = elapsed, inline = true },
                { name = "Rebirths (session)", value = tostring(WebhookState.rebirthCount), inline = true },
                { name = "Reborn Item", value = itemName ~= "" and itemName or "—", inline = false },
            },
            footer = { text = "MH Hub v9 • " .. os.date("%X") },
        }},
    })
end

function sendItemEmbed(itemName, lifeVal)
    sendWebhook({
        content = mentionStr() .. "🎯 Watched item obtained: **" .. itemName .. "**",
        embeds = {{
            title = "🎁 " .. itemName,
            description = "Obtained at Life **" .. tostring(lifeVal) .. "**",
            color = 0xFFE135,
            footer = { text = "MH Hub v9 • " .. os.date("%X") },
        }},
    })
end

function sendLifeEmbed(lifeVal)
    sendWebhook({
        content = mentionStr() .. "🏁 Reached Life **" .. tostring(lifeVal) .. "**",
        embeds = {{ title = "Life Milestone", color = 0x10C550, footer = { text = "MH Hub v9 • " .. os.date("%X") } }},
    })
end


WebhookState.lastRebirthSent = -1e9
WebhookState.debugChat = false
WebhookState.pending = nil

function webhookReadLife()
    local plr = game:GetService("Players").LocalPlayer
    local ls = plr:FindFirstChild("leaderstats")
    local l = ls and ls:FindFirstChild("Life")
    return l and tostring(l.Value) or nil
end

function webhookReadCash()
    local ok, v = pcall(getCash)
    if ok and type(v) == "number" then return v end
    return nil
end

-- Every rebirth signal (script fired, Life value went up, chat message) lands
-- here. The first one opens a 3s window; a chat message arriving inside it adds
-- the reborn item and exact time. One embed is sent per rebirth.
function onRebirthSignal(info)
    info = info or {}
    if WebhookState.pending then
        if info.fromChat then
            for k, v in pairs(info) do WebhookState.pending[k] = v end
        end
        return
    end
    if os.clock() - WebhookState.lastRebirthSent < 10 then return end
    info.cash = info.cash or webhookReadCash()
    WebhookState.pending = info
    task.delay(3, function()
        local data = WebhookState.pending
        WebhookState.pending = nil
        if not data then return end
        WebhookState.lastRebirthSent = os.clock()
        WebhookState.rebirthCount = WebhookState.rebirthCount + 1
        local secs = data.secs
        if not secs then
            secs = WebhookState.lastRebirthTick > 0 and math.floor(tick() - WebhookState.lastRebirthTick) or 0
        end
        local skipped = data.skipped
        if skipped == nil then skipped = (State.waitSkip and State.skipCount) or 0 end
        if WebhookState.pingOnRebirth then
            sendRebirthEmbed(data.life or webhookReadLife() or "?", data.item or "", secs, data.cash or 0, skipped)
        end
    end)
end


function startWebhookHooks()
    local lp = game:GetService("Players").LocalPlayer
    local RS = game:GetService("ReplicatedStorage")

    -- Wait for leaderstats/Life to exist
    local ls = lp:FindFirstChild("leaderstats")

    if not ls then
        ls = lp:WaitForChild("leaderstats", 15)
    end

    local lifeObj = ls and ls:FindFirstChild("Life")

    if ls and not lifeObj then
        lifeObj = ls:WaitForChild("Life", 15)
    end

    -- Cash
    local mirror = RS:FindFirstChild("MoneyMirror")
    local cashObj = mirror and mirror:FindFirstChild(lp.Name)

    local lifeTriggered = false

    -- Life milestone listener
    if lifeObj then
        local prevLife = parseLifeNumeric(lifeObj.Value)
        lifeObj.Changed:Connect(function(val)
            local nowLife = parseLifeNumeric(val)
            if nowLife > prevLife then onRebirthSignal({ life = tostring(val) }) end
            prevLife = nowLife

            if not WebhookState.pingOnLife then
                lifeTriggered = false
                return
            end

            local n = parseLifeNumeric(val)

            if not lifeTriggered and n >= WebhookState.lifeThreshold then
                lifeTriggered = true
                sendLifeEmbed(val)
            end

            if n < WebhookState.lifeThreshold then
                lifeTriggered = false
            end
        end)
    end

    -- Rebirth / watched-item listener (chat text)
    local TCS = game:GetService("TextChatService")
    local lastChatText, lastChatAt = "", 0

    local function handleChatText(raw)
        local plain = tostring(raw or ""):gsub("<[^>]+>", "")
        if WebhookState.debugChat then print("[Webhook chat] " .. plain) end
        if not plain:find("was born into", 1, true) then return end
        if plain == lastChatText and os.clock() - lastChatAt < 5 then return end
        lastChatText, lastChatAt = plain, os.clock()

        -- the name sits right before "was born into"; accept username or display name,
        -- and ignore any chat prefix such as "[Server]:"
        local prefix = plain:match("^(.-) was born into")
        if not prefix then return end
        local mine = prefix:sub(-#lp.Name) == lp.Name or prefix:sub(-#lp.DisplayName) == lp.DisplayName
        if not mine then return end

        local life, item, secs = plain:match("was born into their (%S+) life with an? (.-) in (%d+)s")
        if not life then
            print("[Webhook] your rebirth message did not match the expected format: " .. plain)
        end
        local skippedCount = tonumber(plain:match("Skipped (%d+) live")) or 0
        local actualRebirth = life and (tostring(life):gsub("[snrt][tdh]$", "")) or nil

        onRebirthSignal({
            fromChat = true,
            life = actualRebirth,
            item = item,
            secs = secs,
            skipped = skippedCount,
        })

        if WebhookState.pingOnItem and item then
            local norm = item:lower():match("^%s*(.-)%s*$")
            for _, watched in ipairs(WebhookState.watchedItems) do
                local target = watched:lower():match("^%s*(.-)%s*$")
                if target ~= "" and norm:find(target, 1, true) then
                    sendItemEmbed(item, actualRebirth or "?")
                    break
                end
            end
        end
    end

    pcall(function()
        TCS.MessageReceived:Connect(function(msg) handleChatText(msg.Text) end)
    end)
    -- legacy chat
    pcall(function()
        local ev = RS:FindFirstChild("DefaultChatSystemChatEvents")
        local f = ev and ev:FindFirstChild("OnMessageDoneFiltering")
        if f then f.OnClientEvent:Connect(function(d) handleChatText(d and d.Message) end) end
    end)
    -- text the game itself draws on screen (custom announcement feeds)
    pcall(function()
        lp:WaitForChild("PlayerGui").DescendantAdded:Connect(function(d)
            if d:IsA("TextLabel") then
                task.defer(function()
                    if d.Text:find("was born into", 1, true) then handleChatText(d.Text) end
                end)
            end
        end)
    end)

    -- Slipstream listener (the game's remotes live in Net, not ReplicatedStorage)
    local function onItemObtained(arg1, _qty)
        local itemName, tierOk
        if typeof(arg1) == "Instance" then
            itemName = tostring(arg1)
            local tv = arg1:FindFirstChild("Tier")
            tierOk = tv and tv.Value == 78
        elseif type(arg1) == "string" then
            itemName, tierOk = arg1, true -- no tier info; the watch names decide
        elseif type(arg1) == "table" then
            itemName = tostring(arg1.Name or arg1.name or "")
            tierOk = true
        end
        if WebhookState.debugChat then
            print("[Webhook item] " .. typeof(arg1) .. " " .. tostring(itemName) .. " tierOk=" .. tostring(tierOk))
        end
        if not itemName or itemName == "" or not tierOk then return end

        local lowerItemName = itemName:lower()
        local matchedTarget
        for _, target in ipairs(WebhookState.slipstreamTargets or {}) do
            target = target:match("^%s*(.-)%s*$")
            if target ~= "" and lowerItemName:find(target:lower(), 1, true) then
                matchedTarget = target
                break
            end
        end
        if not matchedTarget then return end

        -- Stop auto rebirth
        if typeof(_G.MHDisableAutoRebirth) == "function" then
            _G.MHDisableAutoRebirth()
        end
        State.autoRebirth = false

        UI:Notify({
            Title = "Slipstream Found!",
            Content = itemName .. " — Auto Rebirth stopped.",
            Type = "Success",
        })

        sendWebhook({
            content = mentionStr() .. "🌀 Slipstream obtained: **" .. itemName .. "**",
            embeds = {{
                title = "🌀 " .. itemName,
                description = "Auto Rebirth has been **disabled**. Check your inventory.",
                color = 0x6365FF,
                footer = { text = "MH Hub v9 • " .. os.date("%X") },
            }},
        })
    end

    local itemSource = "none"
    local itemObtained = RS:FindFirstChild("ItemObtained")
    if itemObtained and itemObtained:IsA("RemoteEvent") then
        itemObtained.OnClientEvent:Connect(onItemObtained)
        itemSource = "RemoteEvent"
    else
        local keys = netKeysLike("obtain")
        for _, k in ipairs(keys) do
            if pcall(function() Channel(k).OnClientEvent:Connect(onItemObtained) end) then
                itemSource = "Net." .. k
                break
            end
        end
        if itemSource == "none" then
            print("[Webhook] no item-obtained channel found. Net keys containing 'item': " .. table.concat(netKeysLike("item"), ", "))
        end
    end

    print(string.format("[Webhook] listeners ready - Life value: %s | cash: %s | chat: %s | item events: %s | HTTP fn: %s",
        tostring(lifeObj ~= nil), tostring(webhookReadCash() ~= nil), tostring(TCS.ChatVersion),
        itemSource, tostring(typeof(getRequest()) == "function")))

end

-- Webhook UI
do
local WebhookSection = WebhookTab:CreateSection("Configuration")
WebhookSection:AddTextbox({
    Name = "Discord Webhook URL",
    Placeholder = "https://discord.com/api/webhooks/...",
    Default = WebhookState.url,
    Callback = function(v)
        WebhookState.url = v:match("^%s*(.-)%s*$")
        if WebhookState.url ~= "" then UI:Notify({ Title = "Webhook", Content = "URL saved.", Type = "Success" }) end
    end,
})
WebhookSection:AddTextbox({
    Name = "Your Discord User ID",
    Placeholder = "123456789012345678",
    Callback = function(v) WebhookState.pingUserId = v:match("%d+") or "" end,
})
WebhookSection:AddButton({ Name = "Reset Session", Callback = resetSession })
WebhookSection:AddToggle({ Name = "Log Chat To Console (debug)", Default = false, Callback = function(v) WebhookState.debugChat = v end })
WebhookSection:AddButton({
    Name = "Test Webhook",
    Callback = function()
        if WebhookState.url == "" then
            UI:Notify({
                Title = "Webhook",
                Content = "No URL set.",
                Type = "Error",
            })
            return
        end

        local started, startErr = sendWebhook({
            embeds = {{
                title = "✅ Webhook Connected",
                description = "Miner's Haven Hub v9 webhook is working.",
                color = 0x10C550,
                footer = {
                    text = "MH Hub v9 • " .. os.date("%X"),
                },
            }},
        }, function(ok, info)
            if ok then
                UI:Notify({ Title = "Webhook", Content = "Delivered (HTTP " .. tostring(info) .. ") - check Discord.", Type = "Success" })
            else
                UI:Notify({ Title = "Webhook Error", Content = tostring(info), Type = "Error", Duration = 8 })
            end
        end)

        if not started then
            UI:Notify({ Title = "Webhook Error", Content = tostring(startErr), Type = "Error" })
        end
    end,
})

local PingSection = WebhookTab:CreateSection("Ping Settings")
PingSection:AddToggle({ Name = "Ping on Rebirth", Default = true, Callback = function(v) WebhookState.pingOnRebirth = v end })
PingSection:AddToggle({ Name = "Ping on Kick / Disconnect", Default = false, Callback = function(v) WebhookState.pingOnKick = v end })
PingSection:AddToggle({ Name = "Ping on Life Milestone", Default = true, Callback = function(v) WebhookState.pingOnLife = v end })
PingSection:AddTextbox({
    Name = "Life Milestone Threshold",
    Default = "50000",
    Callback = function(v) local n = tonumber(v); if n then WebhookState.lifeThreshold = n end end,
})

local WatchSection = WebhookTab:CreateSection("Item Watchlist")
WatchSection:AddToggle({ Name = "Ping on Watched Item", Default = false, Callback = function(v) WebhookState.pingOnItem = v end })
WatchSection:AddTextbox({
    Name = "Watched Items",
    Placeholder = "Neutron Star, Morning Star, Nova",
    Callback = function(v)
        WebhookState.watchedItems = {}
        for item in v:gmatch("[^,]+") do
            local trimmed = item:match("^%s*(.-)%s*$")
            if trimmed ~= "" then table.insert(WebhookState.watchedItems, trimmed) end
        end
    end,
})
WatchSection:AddButton({
    Name = "Print Watchlist",
    Callback = function()
        print("=== WATCHLIST ===")
        for i, name in ipairs(WebhookState.watchedItems) do print(string.format("  [%d] %s", i, name)) end
        print("===============")
    end,
})

local SlipSection = WebhookTab:CreateSection("Slipstream Watch")
SlipSection:AddTextbox({
    Name = "Target Slipstreams",
    Placeholder = "Oblivion Weaver, Morning Star, Nova",
    Callback = function(v)
        WebhookState.slipstreamTargets = {}
        for item in v:gmatch("[^,]+") do
            local trimmed = item:match("^%s*(.-)%s*$")
            if trimmed ~= "" then table.insert(WebhookState.slipstreamTargets, trimmed) end
        end
    end,
})
end

task.spawn(function()
    task.wait(1)
    startWebhookHooks()
end)

-- Automation Tab
do
local CoreAuto = AutoTab:CreateSection("Core Automation")
CoreAuto:AddToggle({
    Name = "Auto Remote Drop",
    Callback = function(v)
        State.autoRemote = v
        if v then 
            task.spawn(function()
                while State.autoRemote do 
                    pcall(function() Channel("RemoteDrop"):FireServer() end)
                    task.wait(0.05)
                end
            end) 
        end
    end,
})
CoreAuto:AddToggle({
    Name = "Firecrystal Mine Feed",
    Callback = function(v)
        State.firecystalFeed = v
        if v then
            local factory = getMyFactory()
            local _, sellPart = factory and findFirecystalMine(factory) or nil, nil
            if not sellPart and factory then _, sellPart = findFirecystalMine(factory) end
            if not sellPart and factory then 
                UI:Notify({ Title="Error", Content="Mine not found.", Type="Error" })
                State.firecystalFeed = false
                return 
            end
            startFirecystalFeed()
            UI:Notify({ Title="Active", Content="Coal feed active.", Type="Success" })
        else 
            UI:Notify({ Title="Stopped", Content="Feed stopped.", Type="Info" }) 
        end
    end,
})

local AutoRebirthGen = 0

-- After a rebirth: wait for the new factory, then run the layout chain. The
-- booster is deliberately not touched; its supervisor rebinds by itself.
function afterRebirth()
    local t0 = os.clock()
    while os.clock() - t0 < 15 and not getMyFactory() do task.wait(0.1) end
    task.wait(1.0)
    t0 = os.clock()
    while State.layoutBusy and os.clock() - t0 < 20 do task.wait(0.1) end
    if State.autoLoadLayout2 then startLayout2Watcher(true) end
end

function startAutoRebirth()
    AutoRebirthGen = AutoRebirthGen + 1
    local gen = AutoRebirthGen
    task.spawn(function()
        local retryAt, lastWarn = 0, -100
        while gen == AutoRebirthGen and State.autoRebirth do
            local ok, err = pcall(function()
                if os.clock() < retryAt or not readyToRebirth() then return end
                local before = getCash()
                local fired, path = doRebirth()
                if not fired then
                    retryAt = os.clock() + 3
                    if os.clock() - lastWarn > 30 then
                        lastWarn = os.clock()
                        local keys = netKeysLike("rebirth", "reborn", "birth")
                        warn("[Deepvein] rebirth remote not found. Net keys like it: " .. (#keys > 0 and table.concat(keys, ", ") or "none"))
                        UI:Notify({ Title = "Auto Rebirth", Content = "Rebirth remote not found (see console).", Type = "Error" })
                    end
                    return
                end
                -- confirm it landed: cash resets on a new life
                local t0, landed = os.clock(), false
                while os.clock() - t0 < 8 do
                    if getCash() < before * 0.5 then landed = true; break end
                    task.wait(0.1)
                end
                if not landed then retryAt = os.clock() + 2; return end
                UI:Notify({ Title = "Rebirth!", Content = "Reborn via " .. tostring(path) .. ".", Type = "Success" })
                afterRebirth()
                retryAt = os.clock() + 1
            end)
            if not ok then warn("[Deepvein] auto rebirth: " .. tostring(err)); retryAt = os.clock() + 2 end
            task.wait(0.2)
        end
    end)
end

local RebirthAuto = AutoTab:CreateSection("Auto Rebirth")
RebirthAuto:AddToggle({
    Name = "Auto Rebirth",
    Callback = function(v)
        State.autoRebirth = v
        _G.MHDisableAutoRebirth = function() State.autoRebirth = false end
        if v then startAutoRebirth() else AutoRebirthGen = AutoRebirthGen + 1 end
    end,
})
RebirthAuto:AddButton({
    Name = "Rebirth Diagnostics (console)",
    Callback = function()
        local reborn, skip = rebirthCosts()
        local _, rn = resolveNet("rebirth", REBIRTH_NAMES)
        local ri = findRemoteInstance(REBIRTH_NAMES)
        local _, ln = resolveNet("layouts", LAYOUT_NAMES)
        print("")
        print("  REBIRTH DIAGNOSTICS")
        print("    cash             " .. tostring(getCash()))
        print("    rebirth price    " .. tostring(reborn) .. "   skip cost " .. tostring(skip))
        print("    ready            " .. tostring(readyToRebirth()))
        print("    rebirth remote   Net=" .. tostring(rn) .. "  Instance=" .. (ri and ri:GetFullName() or "nil"))
        print("    layouts remote   Net=" .. tostring(ln) .. "  Instance=" .. (LayoutsRemote and LayoutsRemote:GetFullName() or "nil"))
        print("    Net keys         " .. table.concat(netKeysLike("rebirth", "reborn", "layout", "action", "skip"), ", "))
        print("")
        UI:Notify({ Title = "Diagnostics", Content = "Printed to console.", Type = "Info", Duration = 3 })
    end,
})

local SkipSection = AutoTab:CreateSection("Life Skip")
SkipSection:AddToggle({ Name = "Wait for Skip Affordability", Callback = function(v) State.waitSkip = v end })
SkipSection:AddSlider({ Name = "Lives to Skip", Min = 1, Max = 20, Default = 5, Callback = function(v) State.skipCount = v end })

local FactorySection = AutoTab:CreateSection("Factory")
FactorySection:AddSlider({
    Name = "Conveyor Speed Multiplier", Min = 1, Max = 20, Default = 1,
    Callback = function(v)
        local factory = getMyFactory()
        if not factory then return end
        local adj = factory:FindFirstChild("AdjustSpeed")
        if adj then adj.Value = v end
        for _, item in ipairs(factory:GetChildren()) do
            local model = item:FindFirstChildOfClass("Model")
            if model then
                local conv = model:FindFirstChild("Conv")
                if conv then 
                    local cs = conv:FindFirstChild("ConveyorSpeed")
                    if cs then cs.Value = 82*v end 
                end
            end
        end
    end,
})
FactorySection:AddButton({ Name = "Go to Factory", Callback = tpToFactory })
end

-- Ore Booster Tab
do
local BoosterMain = OreTab:CreateSection("Booster Control")
BoosterMain:AddToggle({
    Name = "Ore Booster",
    Callback = function(v)
        State.oreBooster = v
        if v then
            if State.cellFurnaceMode then 
                stopCellDiscovery()
                State.cellFurnaceMode = false
                UI:Notify({ Title="Cell Mode", Content="Stopped.", Type="Info" }) 
            end
            startOreDiscovery()
            UI:Notify({ Title="Ore Booster", Content="v9 started.", Type="Success" })
        else 
            stopOreDiscovery()
            UI:Notify({ Title="Ore Booster", Content="Stopped.", Type="Info" }) 
        end
    end,
})

BoosterMain:AddButton({ Name = "Sell Report (console)", Callback = printSellReport })

local CellSection = OreTab:CreateSection("Cell Furnace Mode")
CellSection:AddToggle({
    Name = "Use Cell Furnace Only",
    Callback = function(v)
        if v and State.oreBooster then 
            stopOreDiscovery()
            State.oreBooster = false
            UI:Notify({ Title="Ore Booster", Content="Stopped.", Type="Info" }) 
        end
        State.cellFurnaceMode = v
        if v then 
            startCellDiscovery()
            UI:Notify({ Title="Cell Mode", Content="Active.", Type="Success" })
        else 
            stopCellDiscovery()
            UI:Notify({ Title="Cell Mode", Content="Stopped.", Type="Info" }) 
        end
    end,
})

local BoosterSettings = OreTab:CreateSection("Settings")
BoosterSettings:AddToggle({ Name = "Skip Destructive Upgraders", Default = true, Callback = function(v) State.skipDestructive = v end })
BoosterSettings:AddToggle({ Name = "Use Education/Hold Items", Default = true, Callback = function(v) State.usePostDelayItems = v end })
BoosterSettings:AddToggle({
    Name = "Sell for Rebirth (Instant Sell When Funded)",
    Default = false,
    Callback = function(v)
        State.sellForRebirth = v
        if v then
            UI:Notify({
                Title   = "Sell for Rebirth",
                Content = "Ores will sell the moment they can fund a rebirth.",
                Type    = "Success",
            })
        else
            UI:Notify({
                Title   = "Sell for Rebirth",
                Content = "Disabled.",
                Type    = "Info",
            })
        end
    end,
})
BoosterSettings:AddSlider({ Name = "Pass Delay (ms)", Min = 0, Max = 250, Default = 5, Callback = function(v) State.passDelay = v/1000 end })
BoosterSettings:AddSlider({ Name = "No-Cap Stall Window", Min = 3, Max = 20, Default = 6, Callback = function(v) State.noCapeStallWindow = v end })

local TrackerSection = OreTab:CreateSection("Display")
TrackerSection:AddToggle({ Name = "Hide Ores (Performance)", Default = false, Callback = function(v)
    if v then startOreHide() else stopOreHide() end
end })

local FpsTab = Window:CreateTab("FPS", "gauge")
local FPSSection = FpsTab:CreateSection("Performance")

FPSSection:AddToggle({
    Name = "Nuke Mode (Base Only)",
    Default = false,
    Callback = function(v)
        if v then startNukeMode() else stopNukeMode() end
    end,
})

FPSSection:AddToggle({
    Name = "Ultra Performance Mode",
    Default = false,
    Callback = function(v)
        if v then startUltraMode() else stopUltraMode() end
    end,
})

FPSSection:AddToggle({
    Name = "Disable Particles & Beams",
    Default = false,
    Callback = function(v)
        if v then disableParticles() else enableParticles() end
        UI:Notify({ Title="Particles", Content=v and "Disabled (532 effects killed)." or "Restored.", Type=v and "Success" or "Info" })
    end,
})
FPSSection:AddToggle({
    Name = "Disable Shadows",
    Default = false,
    Callback = function(v)
        if v then disableShadows() else enableShadows() end
        UI:Notify({ Title="Shadows", Content=v and "Disabled." or "Restored.", Type=v and "Success" or "Info" })
    end,
})
FPSSection:AddToggle({
    Name = "Mute All Sounds",
    Default = false,
    Callback = function(v)
        if v then muteSounds() else unmuteSounds() end
        UI:Notify({ Title="Sounds", Content=v and "Muted (45 sources)." or "Restored.", Type=v and "Success" or "Info" })
    end,
})
FPSSection:AddToggle({
    Name = "Reduce Render Distance (LOD)",
    Default = false,
    Callback = function(v)
        if v then enableLOD() else disableLOD() end
        UI:Notify({ Title="LOD", Content=v and "Active." or "Restored.", Type=v and "Success" or "Info" })
    end,
})

local RouteSection = OreTab:CreateSection("Route")
RouteSection:AddButton({ Name = "Print Current Route", Callback = printRoute })
RouteSection:AddButton({ Name = "Print Effect Plan", Callback = printEffectPlan })

end

-- Boxes Tab
do
BOX_TYPES = discoverBoxes()

local OpenSection = BoxTab:CreateSection("Auto Open")

OpenSection:AddToggle({
    Name = "Auto Open (loop)",
    Callback = function(v)
        State.autoOpenBoxes = v
        if not v then return end
        task.spawn(function()
            while State.autoOpenBoxes do
                local opened = 0
                for _, bt in ipairs(BOX_TYPES) do
                    if not State.autoOpenBoxes then break end
                    if activeBoxToggles[bt] and boxCount(bt) > 0 then
                        if openBoxOnce(bt) then opened = opened + 1 end
                        task.wait(0.06)
                    end
                end
                if opened == 0 then task.wait(0.4) end
            end
        end)
    end,
})

OpenSection:AddButton({
    Name = "Open All Once",
    Callback = function()
        task.spawn(function()
            local opened = 0
            for _, bt in ipairs(BOX_TYPES) do
                if activeBoxToggles[bt] and boxCount(bt) > 0 then
                    if openBoxOnce(bt) then opened = opened + 1 end
                    task.wait(0.06)
                end
            end
            UI:Notify({ Title = "Boxes", Content = opened .. " opened.", Type = "Success" })
        end)
    end,
})

OpenSection:AddButton({
    Name = "Refresh Counts",
    Callback = function()
        BOX_TYPES = discoverBoxes()
        local parts = {}
        for _, bt in ipairs(BOX_TYPES) do
            local n = boxCount(bt)
            if n > 0 then table.insert(parts, bt .. " " .. n) end
        end
        UI:Notify({
            Title = "Boxes",
            Content = string.format("%d types · %d total%s",
                #BOX_TYPES, totalBoxes(),
                #parts > 0 and ("\n" .. table.concat(parts, ", ")) or ""),
            Type = "Info", Duration = 8,
        })
    end,
})

OpenSection:AddButton({
    Name = "Toggle Clover Pet",
    Callback = function()
        toggleClover()
        task.wait(0.15)
        UI:Notify({
            Title = "Clover",
            Content = cloverEnabled() and "Clover ON (uses one per box)" or "Clover OFF",
            Type = "Info",
        })
    end,
})

local CollectSection = BoxTab:CreateSection("Collection")
CollectSection:AddToggle({
    Name = "Auto Collect Boxes",
    Callback = function(v)
        State.autoBoxes = v
        if v then 
            task.spawn(function()
                while State.autoBoxes do
                    local boxFolder = workspace:FindFirstChild("Boxes")
                    local boxList = boxFolder and boxFolder:GetChildren() or {}
                    if #boxList == 0 then 
                        tpToFactory()
                        task.wait(2)
                    else
                        for _, box in ipairs(boxList) do
                            if not State.autoBoxes then break end
                            local part = getBoxPart(box)
                            local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                            if hrp and part then 
                                hrp.CFrame = part.CFrame + Vector3.new(0,0.1,0)
                                task.wait(0.05) 
                            end
                        end
                        task.wait(0.3)
                    end
                end
            end) 
        end
    end,
})

BoxTab:CreateSection("Box Types")
BoxTab:AddMultiDropdown({
    Name = "Enabled Boxes",
    Options = BOX_TYPES,
    Default = BOX_TYPES,
    Callback = function(selected)
        local keep = {}
        for _, name in ipairs(selected or {}) do keep[name] = true end
        for _, name in ipairs(BOX_TYPES) do activeBoxToggles[name] = keep[name] == true end
    end,
})
end

-- Layouts Tab
do
local PostRebirthSection = LayoutTab:CreateSection("Auto Load — Post Rebirth")
PostRebirthSection:AddToggle({ Name = "Auto Load After Rebirth", Callback = function(v) State.autoLoadLayout1 = v end })
PostRebirthSection:AddDropdown({ Name = "Layout 1 Choice", Options = {"Layout1", "Layout2", "Layout3"}, Default = "Layout1", Callback = function(v) State.layout1Choice = v end })

local ConditionalSection = LayoutTab:CreateSection("Auto Load — Layouts 2 & 3 (cost gated)")
ConditionalSection:AddToggle({ Name = "Enable Auto Load Chain", Callback = function(v) State.autoLoadLayout2 = v; if v and not layout2WatcherActive then startLayout2Watcher() end end })
ConditionalSection:AddDropdown({ Name = "Layout 2 Choice", Options = {"Layout1", "Layout2", "Layout3"}, Default = "Layout2", Callback = function(v) State.layout2Choice = v end })
ConditionalSection:AddToggle({ Name = "Also Load Layout 3", Callback = function(v) State.autoLoadLayout3 = v end })
ConditionalSection:AddDropdown({ Name = "Layout 3 Choice", Options = {"Layout1", "Layout2", "Layout3"}, Default = "Layout3", Callback = function(v) State.layout3Choice = v end })
ConditionalSection:AddDropdown({ Name = "Trigger Type", Options = {"Cost", "Time"}, Default = "Cost", Callback = function(v) State.layout2TriggerType = v end })
ConditionalSection:AddSlider({ Name = "Time Delay (s)", Min = 1, Max = 60, Default = 10, Callback = function(v) State.layout2TimeDelay = v end })
ConditionalSection:AddButton({
    Name = "Show Layout Costs",
    Callback = function()
        UI:Notify({ Title = "Layout Costs", Content = "Calculating...", Type = "Info", Duration = 2 })
        task.spawn(function()
            local lines = {}
            for i = 1, 3 do
                local ok, plan, err = pcall(LC_LayoutPlan, lp.Name, i)
                if not ok then
                    table.insert(lines, string.format("Layout%d  error: %s", i, tostring(plan)))
                elseif plan then
                    table.insert(lines, string.format("Layout%d  %s  (%d missing)", i, formatCash(plan.cost), plan.totalMissing))
                else
                    table.insert(lines, string.format("Layout%d  %s", i, tostring(err)))
                end
            end
            UI:Notify({ Title = "Layout Costs", Content = table.concat(lines, "\n"), Type = "Info", Duration = 8 })
        end)
    end,
})

local LayoutActions = LayoutTab:CreateSection("Quick Actions")
LayoutActions:AddButton({ Name = "Withdraw All", Callback = function() doWithdrawAll(); UI:Notify({ Title="Sold!", Content="Withdrawn.", Type="Info" }) end })

local ManualSection = LayoutTab:CreateSection("Manual Load")
ManualSection:AddDropdown({ Name = "Layout to Load", Options = {"Layout1", "Layout2", "Layout3"}, Default = "Layout1", Callback = function(v) _G._ManualLayoutChoice = v end })
ManualSection:AddButton({
    Name = "Load Layout",
    Callback = function()
        local key = _G._ManualLayoutChoice or "Layout1"
        task.spawn(function()
            local ok = doLoadLayout(key)
            UI:Notify({ Title="Layout", Content=key .. (ok and " loaded." or " load unconfirmed."), Type = ok and "Success" or "Error" })
        end)
    end,
})
end

-- Layout Copier
local HS_LC = game:GetService("HttpService")
local Players_LC = game:GetService("Players")
local FetchItem_LC = require(RS.Modules.Game.FetchItem)
function getCashLC() return lp.PlayerGui.GUI.Money.Value end
function LC_getMyBase() 
    local t = lp:FindFirstChild("PlayerTycoon")
    local tv = t and t.Value
    return tv and tv:FindFirstChild("Base") 
end
function LC_HasItem(itemId) 
    local ok, r = pcall(function() return Net.HasItem:Invoke(itemId) end)
    return ok and type(r) == "number" and r > 0 
end

function LC_ItemCount(itemId)
    local ok, n = pcall(function() return Net.HasItem:Invoke(itemId) end)
    return (ok and type(n) == "number") and n or 0
end
function LC_IsShopItem(itemId) 
    local def = FetchItem_LC:Get(itemId)
    if not def then return false end
    local itemEntry = RS.Items:FindFirstChild(def.Name)
    return itemEntry ~= nil and itemEntry:FindFirstChild("Cost") ~= nil 
end
function LC_GetItemCost(itemId) 
    local def = FetchItem_LC:Get(itemId)
    if not def then return math.huge end
    local itemEntry = RS.Items:FindFirstChild(def.Name)
    if not itemEntry then return math.huge end
    local cost = itemEntry:FindFirstChild("Cost")
    return cost and cost.Value or math.huge 
end

-- Shop entries price in one of three currencies. Only Cash is safe to spend
-- automatically: Shards and Crystals are premium.
function LC_GetPrice(itemId)
    local def = FetchItem_LC:Get(itemId)
    if not def then return nil end
    local entry = RS.Items:FindFirstChild(def.Name)
    if not entry then return nil end
    local shard = entry:FindFirstChild("ShardPrice")
    if shard and shard:IsA("ValueBase") then return "ShardsOfLife", shard.Value end
    local crystal = entry:FindFirstChild("Crystals")
    if crystal and crystal:IsA("ValueBase") then return "Crystals", crystal.Value end
    local cost = entry:FindFirstChild("Cost")
    if cost and cost:IsA("ValueBase") then return "Cash", cost.Value end
    return nil
end

local LayoutCopier = { Busy = false, SelectedPlayer = "", SelectedLayout = 1, PlayersList = {} }
function LC_RefreshPlayers()
    LayoutCopier.PlayersList = {}

    for _, p in ipairs(Players_LC:GetPlayers()) do
        table.insert(LayoutCopier.PlayersList, p.Name)
    end

    local found = false
    for _, n in ipairs(LayoutCopier.PlayersList) do
        if n == LayoutCopier.SelectedPlayer then
            found = true
            break
        end
    end

    if not found then
        -- Default to yourself
        LayoutCopier.SelectedPlayer = lp.Name
    end
end

LC_RefreshPlayers()
Players_LC.PlayerAdded:Connect(LC_RefreshPlayers)
Players_LC.PlayerRemoving:Connect(function(p) 
    if LayoutCopier.SelectedPlayer == p.Name then 
        LayoutCopier.SelectedPlayer = ""
        UI:Notify({ Title = "Copier", Content = p.Name .. " left.", Type = "Info" }) 
    end
    LC_RefreshPlayers() 
end)

function LC_DecodeLayout(targetPlayer, layoutNum)
    local p = Players_LC:FindFirstChild(targetPlayer)
    if not p then return false, "Player not in server" end
    local layouts = p:FindFirstChild("Layouts")
    if not layouts then return false, "No Layouts" end
    local lv = layouts:FindFirstChild("Layout" .. layoutNum)
    if not lv then return false, "Layout not found" end
    local raw = lv.Value
    if not raw or raw == "" or raw == "[]" then return true, {} end
    local ok, data = pcall(HS_LC.JSONDecode, HS_LC, raw)
    if not ok then return false, "Decode failed" end
    return true, (type(data) == "table" and data or {})
end

function LC_BuildCFrame(entry, base)
      local pos = entry.Position
    if not pos then return nil end
    local topLeft = base.CFrame * CFrame.new(Vector3.new(base.Size.X / 2, 0, base.Size.Z / 2))
    local worldPos = topLeft * Vector3.new(tonumber(pos[1]) or 0, tonumber(pos[2]) or 0, tonumber(pos[3]) or 0)
    local rot = Vector3.new(tonumber(pos[4]) or 0, tonumber(pos[5]) or 0, tonumber(pos[6]) or 0)
    return CFrame.new(worldPos, worldPos + (rot * 5))
end

function formatCash(n)
    if type(n) ~= "number" then return "?" end
    if n >= 1e12 then return string.format("%.2fT", n / 1e12) end
    if n >= 1e9  then return string.format("%.2fB", n / 1e9) end
    if n >= 1e6  then return string.format("%.2fM", n / 1e6) end
    if n >= 1e3  then return string.format("%.1fK", n / 1e3) end
    return tostring(math.floor(n))
end

-- What a layout actually costs to stand up: the shop price of everything on it
-- you do not own yet. Shiny ids fold onto their base, so a shiny and its normal
-- version are one line and owning either counts towards the same machine.
function LC_LayoutPlan(playerName, layoutNum)
    local ok, data = LC_DecodeLayout(playerName or lp.Name, layoutNum or 1)
    if not ok then return nil, data end
    if #data == 0 then return nil, "empty layout slot" end
    local need, ids = {}, {}
    for _, entry in ipairs(data) do
        local id = tonumber(entry.ItemId)
        if id then
            local def = FetchItem_LC:Get(id)
            local base = def and resolveName(def.Name) or ("Unknown #" .. id)
            need[base] = (need[base] or 0) + 1
            ids[base] = ids[base] or {}
            table.insert(ids[base], id)
        end
    end
    -- Sequential HasItem calls made this take seconds; warm every id at once.
    local warm, pending = {}, 0
    for _, list in pairs(ids) do
        for _, id in ipairs(list) do warm[id] = true end
    end
    for id in pairs(warm) do
        local hit = OWNED_CACHE[id]
        if not hit or os.clock() - hit.t > 20 then
            pending = pending + 1
            task.spawn(function()
                LC_Owned(id, true)
                pending = pending - 1
            end)
        end
    end
    while pending > 0 do task.wait() end

    local plan = { cost = 0, totalMissing = 0, shop = {}, other = {}, lines = {} }
    for base, qty in pairs(need) do
        local candidates, seen = {}, {}
        for _, id in ipairs(ids[base]) do
            if not seen[id] then seen[id] = true; candidates[#candidates + 1] = id end
        end
        local baseId = tonumber(MHItem.nameToId[base] or "")
        if baseId and not seen[baseId] then candidates[#candidates + 1] = baseId end
        local owned, unitCost, shop = 0, 0, false
        for _, id in ipairs(candidates) do
            owned = owned + LC_Owned(id)
            if LC_IsShopItem(id) then
                shop = true
                local c = LC_GetItemCost(id)
                if c > unitCost and c < math.huge then unitCost = c end
            end
        end
        local short = qty - owned
        if short > 0 then
            local row = { name = base, qty = short, shop = shop, cost = shop and unitCost * short or nil }
            if shop then
                table.insert(plan.shop, row)
                plan.cost = plan.cost + unitCost * short
            else
                table.insert(plan.other, row)
            end
            plan.totalMissing = plan.totalMissing + short
        end
    end
    table.sort(plan.shop, function(p, q)
        if p.cost == q.cost then return p.name < q.name end
        return p.cost > q.cost
    end)
    table.sort(plan.other, function(p, q)
        if p.qty == q.qty then return p.name < q.name end
        return p.qty > q.qty
    end)
    local lines = {}
    if #plan.shop > 0 then
        table.insert(lines, string.format("SHOP · %d missing · %s", #plan.shop, formatCash(plan.cost)))
        for i, row in ipairs(plan.shop) do
            if i > 6 then table.insert(lines, string.format("  +%d more", #plan.shop - 6)) break end
            table.insert(lines, string.format("  %dx %-24s %s", row.qty, row.name, formatCash(row.cost)))
        end
    end
    if #plan.other > 0 then
        table.insert(lines, string.format("OTHER · %d missing", #plan.other))
        for i, row in ipairs(plan.other) do
            if i > 6 then table.insert(lines, string.format("  +%d more", #plan.other - 6)) break end
            table.insert(lines, string.format("  %dx %s", row.qty, row.name))
        end
    end
    if #lines == 0 then lines = { "Nothing missing - layout is fully owned." } end
    plan.lines = lines
    plan.text = table.concat(lines, "\n")
    return plan
end

function LC_GetMissingItems()
    -- A player leaving clears the dropdown, so fall back to your own layouts
    -- instead of failing the button.
    if LayoutCopier.SelectedPlayer == "" then LayoutCopier.SelectedPlayer = lp.Name end
    return LC_LayoutPlan(LayoutCopier.SelectedPlayer, LayoutCopier.SelectedLayout)
end
function LayoutCopier.Build()
    if LayoutCopier.Busy or LayoutCopier.SelectedPlayer == "" then 
        UI:Notify({ Title="Copier", Content="Busy or no player.", Type="Error" })
        return 
    end
    task.spawn(function()
        LayoutCopier.Busy = true
        local ok, data = LC_DecodeLayout(LayoutCopier.SelectedPlayer, LayoutCopier.SelectedLayout)
        if not ok or #data == 0 then 
            UI:Notify({ Title="Copier", Content="Error.", Type="Error" })
            LayoutCopier.Busy = false
            return 
        end
        local base = LC_getMyBase()
        if not base then 
            UI:Notify({ Title="Copier", Content="No base.", Type="Error" })
            LayoutCopier.Busy = false
            return 
        end
        UI:Notify({ Title = "Copier", Content = "Building...", Type = "Info" })
        local stats = { placed=0, purchased=0, cant_afford=0, unavailable=0, failed=0 }
        for _, entry in ipairs(data) do
            base = LC_getMyBase()
            if not base then break end
            local itemId = entry.ItemId
            if not itemId then stats.failed = stats.failed + 1; continue end
            local def = FetchItem_LC:Get(itemId)
            if not def then stats.failed = stats.failed + 1; continue end
            local cf = LC_BuildCFrame(entry, base)
            if not cf then stats.failed = stats.failed + 1; continue end
            local currency, price = LC_GetPrice(itemId)
            if LC_HasItem(itemId) then 
                local plOk = pcall(function() Net.PlaceItem:Invoke(tonumber(itemId) or itemId, cf, base) end)
                if plOk then stats.placed = stats.placed + 1 else stats.failed = stats.failed + 1 end
                task.wait()
            elseif currency == "Cash" then
                local cost = price
                if getCashLC() >= cost then 
                    pcall(function() Net.BuyItem:Invoke(tonumber(itemId) or itemId, 1) end)
                    task.wait()
                    base = LC_getMyBase()
                    if base and LC_HasItem(itemId) then 
                        stats.purchased = stats.purchased + 1
                        cf = LC_BuildCFrame(entry, base)
                        local plOk2 = pcall(function() Net.PlaceItem:Invoke(tonumber(itemId) or itemId, cf, base) end)
                        if plOk2 then stats.placed = stats.placed + 1 else stats.failed = stats.failed + 1 end
                    else 
                        stats.failed = stats.failed + 1 
                    end
                    task.wait()
                else 
                    stats.cant_afford = stats.cant_afford + 1 
                end
            else 
                stats.unavailable = stats.unavailable + 1 
            end
        end
        LayoutCopier.Busy = false
        UI:Notify({ Title="Copier", Content="Done.", Type="Success" })
    end)
end

local CopierSection = LayoutTab:CreateSection("Layout Copier")

local _lcInit = {}
for _, n in ipairs(LayoutCopier.PlayersList) do
    table.insert(_lcInit, n)
end

if #_lcInit == 0 then
    _lcInit = { lp.Name }
end

-- Make yourself the default target
LayoutCopier.SelectedPlayer = lp.Name

local TargetPlayer = CopierSection:AddDropdown({
    Name = "Target Player",
    Options = _lcInit,
    Default = lp.Name,

    Callback = function(v)
        local p = Players_LC:FindFirstChild(v)

        if p then
            LayoutCopier.SelectedPlayer = v
        else
            LayoutCopier.SelectedPlayer = ""
        end
    end
})
CopierSection:AddDropdown({ Name = "Target Layout", Options = {"Layout1", "Layout2", "Layout3"}, Default = "Layout1", Callback = function(v) LayoutCopier.SelectedLayout = tonumber(v:match("%d+")) or 1 end })
CopierSection:AddButton({
    Name = "Refresh Players",
    Callback = function()
        LC_RefreshPlayers()

        local newList = {}

        for _, n in ipairs(LayoutCopier.PlayersList) do
            table.insert(newList, n)
        end

        if #newList == 0 then
            newList = { lp.Name }
        end

        TargetPlayer:SetOptions(newList)

        -- Keep yourself selected if nothing else is selected
        if LayoutCopier.SelectedPlayer == "" then
            LayoutCopier.SelectedPlayer = lp.Name
        end

        UI:Notify({
            Title = "Copier",
            Content = "Player list refreshed.",
            Type = "Success"
        })
    end
})
CopierSection:AddButton({
    Name = "Build",
    Callback = function() LayoutCopier.Build() end,
})

CopierSection:AddButton({
    Name = "Missing",
    Callback = function()
        local plan, err = LC_GetMissingItems()
        if not plan then
            UI:Notify({ Title = "Missing", Content = tostring(err), Type = "Error" })
            return
        end
        local rows = {}
        table.insert(rows, { text = string.format("cost %s   ·   %d missing", formatCash(plan.cost), plan.totalMissing), tone = "head" })
        if #plan.shop > 0 then
            table.insert(rows, { text = "SHOP", tone = "head" })
            for _, r in ipairs(plan.shop) do
                table.insert(rows, string.format("x%-3d %-28s %s", r.qty, r.name, formatCash(r.cost)))
            end
        end
        if #plan.other > 0 then
            table.insert(rows, { text = "OTHER", tone = "head" })
            for _, r in ipairs(plan.other) do
                table.insert(rows, string.format("x%-3d %s", r.qty, r.name))
            end
        end
        if #rows == 1 then table.insert(rows, { text = "Everything is owned.", tone = "good" }) end
        DV_Dialog("Layout " .. tostring(LayoutCopier.SelectedLayout),
            { { text = tostring(LayoutCopier.SelectedPlayer), tone = "neutral" },
              { text = formatCash(plan.cost) .. " to build", tone = "warn" } },
            rows,
            { eyebrow = "MISSING ITEMS", footer = string.format("%d missing", plan.totalMissing) })
    end,
})
local SaveSection = LayoutTab:CreateSection("Save Layouts")

function doSaveLayout(i)
    local key = "Layout" .. i
    local layouts = game.Players.LocalPlayer:FindFirstChild("Layouts")
    local slot = layouts and layouts:FindFirstChild(key)
    local hasExisting = slot and slot.Value and slot.Value ~= "" and slot.Value ~= "[]"

    if hasExisting then
        pcall(function() LayoutsRemote:InvokeServer("Save", key) end)
        task.wait(0.15)
    end

    pcall(function() LayoutsRemote:InvokeServer("Save", key) end)
    UI:Notify({ Title = "Layout Saved", Content = key .. " written.", Type = "Success" })
end

for i = 1, 3 do
    SaveSection:AddButton({
        Name = "Save to Slot " .. i,
        Callback = function() doSaveLayout(i) end,
    })
end

-- Quick actions (old Utility tab removed; these live in Automation)
do
local UtilActions = AutoTab:CreateSection("Quick Actions")
UtilActions:AddButton({
    Name = "Rebirth",
    Callback = function()
        task.spawn(function()
            local fired = doRebirth()
            if not fired then
                UI:Notify({ Title="Rebirth", Content="Rebirth remote not found (see Rebirth Diagnostics).", Type="Error" })
                return
            end
            afterRebirth()
            UI:Notify({ Title="Rebirth", Content="Done.", Type="Success" })
        end)
    end,
})
UtilActions:AddButton({ Name = "Redeem Free Box", Callback = function() pcall(function() Channel("RedeemFreeBox"):FireServer() end); UI:Notify({ Title="Free Box", Content="Redeemed.", Type="Success" }) end })
UtilActions:AddButton({ Name = "PANIC — Stop All", Callback = function() State.oreBooster = false; stopOreDiscovery(); State.cellFurnaceMode = false; stopCellDiscovery(); State.autoRemote = false; State.autoBoxes = false; State.autoRebirth = false; UI:Notify({ Title="PANIC", Content="Stopped.", Type="Error" }) end })

local DiagSection = LayoutTab:CreateSection("Diagnostics")
DiagSection:AddButton({ Name = "Audit Current Base", Callback = printItemAudit })
end

-- ── MENUS · Focus.change(frame) is the real open path ───────────────
-- Verified in-game: setting the Open attribute does nothing; Focus.change
-- makes the frame visible and Focus.close() hides it.
function focusModule()
    local ok, mod = pcall(require, lp.PlayerGui:FindFirstChild("Focus"))
    return ok and mod or nil
end

function openMenu(frameName)
    local pg = lp.PlayerGui
    local want = string.lower((string.gsub(frameName, "%s+", "")))
    local menus = pg:FindFirstChild("Menus")
    local frame = menus and menus:FindFirstChild(frameName)

    -- Some vendors (Erebus) are not inside Menus and are cloned in only after
    -- interaction, so search every ScreenGui and compare names with spaces
    -- and case ignored before giving up.
    if not frame then
        for _, gui in ipairs(pg:GetChildren()) do
            if gui:IsA("ScreenGui") or gui:IsA("LayerCollector") then
                for _, d in ipairs(gui:GetDescendants()) do
                    if d:IsA("Frame") or d:IsA("CanvasGroup") then
                        local name = string.lower((string.gsub(d.Name, "%s+", "")))
                        if name == want or string.find(name, want, 1, true) then
                            frame = d
                            break
                        end
                    end
                end
            end
            if frame then break end
        end
    end

    local focus = focusModule()
    if not frame or not focus then return false end
    return (pcall(function() focus.change(frame) end))
end

function closeAllMenus()
    local focus = focusModule()
    if focus then pcall(function() focus.close() end) end
end

local NPC_MENUS = {
    { Label = "Craftsman",       Frame = "Craftsman" },
    { Label = "Draedon",         Frame = "Superstitious" },
    { Label = "Fleabag",         Frame = "Fleabag" },
    { Label = "SpookMcDook",     Frame = "SpookMcDook" },
    { Label = "Masked Man",      Frame = "MaskedMan" },
    { Label = "Phantasm",        Frame = "Phantasm" },
    { Label = "Event",           Frame = "Event" },
    { Label = "Book of Knowledge", Frame = "BookOfKnowledge" },
}

local MenuSection = NpcTab:CreateSection("NPC Menus")
for _, m in ipairs(NPC_MENUS) do
    MenuSection:AddButton({
    Name = "Open " .. m.Label,
        Callback = function()
            local ok = openMenu(m.Frame)
            UI:Notify({
                Title = "Menu",
                Content = ok and m.Label or (m.Frame .. " did not open"),
                Type = ok and "Info" or "Error",
            })
        end,
    })
end
function fireDataReset()
    local model = workspace:FindFirstChild("DataResetModel", true)
    local part = model and model:FindFirstChild("Internal", true)
    local prompt = part and part:FindFirstChildOfClass("ProximityPrompt")
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not prompt or not hrp then
        UI:Notify({
            Title = "Erebus",
            Content = "Data reset not loaded.",
            Type = "Error",
        })
        return
    end

    -- Trip there, fire it, come straight back: the prompt only exists in range,
    -- so the reset needs proximity even though the button does not.
    local startCF = hrp.CFrame
    local dest = part.Position + Vector3.new(0, 4, 0)
    pcall(function() workspace:RequestStreamAroundAsync(dest) end)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    hrp.CFrame = CFrame.new(dest)
    task.wait(0.25)

    pcall(function() prompt:InputHoldBegin() end)
    task.wait(0.2)
    pcall(function() prompt:InputHoldEnd() end)
    task.wait(0.4)

    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    hrp.CFrame = startCF

    UI:Notify({ Title = "Erebus", Content = "Data reset fired, back in place.", Type = "Info" })
end

MenuSection:AddButton({ Name = "Run Erebus Reset", Callback = fireDataReset })

MenuSection:AddButton({
    Name = "Close All Menus",
    Callback = function()
        closeAllMenus()
        UI:Notify({ Title = "Menu", Content = "Closed.", Type = "Info" })
    end,
})

-- NPC shop buttons open the vendor's own frame
-- ── CRAFTING ─────────────────────────────────────────────────────────
-- Recipes live on the item model itself: FusionReq / RebornId+Count /
-- EnchantCost / ElementCraftingPrice. BlueprintPrice is Research Points.
local CRAFT_BY_NAME = {}
do
    for _, m in ipairs(RS.Items:GetChildren()) do
        if m:GetAttribute("ItemId") or m:FindFirstChild("ItemId") then
            CRAFT_BY_NAME[m.Name] = m
        end
    end
end

-- Superstitious items are item recipes, not element totals. Each entry is a
-- list of recipes; the planner picks the one with the fewest missing items.
local SUPER_RECIPES = {
    ["Draedon's Gauntlet"] = {
        { {"Pilotite Mine", 11}, {"Quantum Ore Cleaner", 7}, {"Vortex Chamber", 4}, {"Lightningbolt Refiner", 4} },
        { {"Pilotite Mine", 11}, {"Frozen Justice", 3}, {"Lightningbolt Refiner", 3}, {"Gate of Eclipse", 3}, {"The Grand Prism", 1} },
        { {"Frozen Justice", 8}, {"Tesla Resetter", 5}, {"Pilotite Mine", 4}, {"Lightningbolt Refiner", 3}, {"Quantum Ore Cleaner", 1}, {"Ore Supernova", 1} },
    },
    ["Daestrophe"] = {
        { {"Toxic Waste Disposal", 24}, {"The Catalyst", 10}, {"Scorching Heat", 9} },
        { {"Plasma Scanner", 11}, {"Yunium Mine", 6}, {"Toxic Waste Disposal", 5}, {"Scorpium Mine", 3}, {"Nuclear Stronghold", 3}, {"Dragonglass Mine", 3}, {"Flaming Schrodinger", 1}, {"Oblivion Weaver", 1} },
        { {"Plasma Scanner", 8}, {"Flaming Schrodinger", 8}, {"Toxic Waste Disposal", 5}, {"Green Tea Latte", 5}, {"Dragonglass Mine", 3}, {"Yunium Mine", 3}, {"Astral Predictor", 1}, {"Mineral Wheel", 1}, {"Orbital Cataclysm", 1} },
    },
    ["Delta Phantom"] = {
        { {"Newtonium Mine", 26}, {"Yunium Mine", 11} },
        { {"Vortex Chamber", 10}, {"Green Tea Latte", 8}, {"Toxic Waste Disposal", 5}, {"Big Bertha", 1}, {"Wild Spore", 1}, {"Sinister Sepulcher", 1} },
    },
    ["Pandora's Box"] = {
        { {"Dreamer's Fright", 23}, {"Frozen Justice", 3}, {"Big Bad Blaster", 1}, {"Nature's Grip", 1}, {"Ore Illuminator", 7}, {"The Catalyst", 7} },
    },
    ["Elysium Solemnity"] = {
        { {"The Catalyst", 13}, {"Dark Magic", 11}, {"Atomium Mine", 5}, {"Dreamer's Might", 3}, {"Frozen Justice", 3}, {"Nature's Grip", 3}, {"Timeless Enhancement", 2}, {"Ore Illuminator", 1} },
    },
    ["Midas Blaster"] = {
        { {"Industrial Firecrystal Mine", 10}, {"Scorpium Mine", 10}, {"Nature's Grip", 9}, {"Ore Illuminator", 2} },
        { {"Massive Diamond Mine", 11}, {"Scorpium Mine", 7}, {"Wild Spore", 7}, {"Atomium Mine", 1} },
        { {"Azure Refiner", 10}, {"Flaming Schrodinger", 10}, {"Industrial Firecrystal Mine", 8}, {"Atomium Mine", 2} },
        { {"Crystallized System", 18}, {"Eternal Journey", 5}, {"Big Bad Blaster", 3} },
        { {"Shard Park", 14}, {"Scorpium Mine", 9}, {"Eternal Journey", 1}, {"Big Bad Blaster", 1} },
        { {"Dreamer's Fright", 20}, {"Atomium Mine", 14}, {"Morning Star", 2} },
        { {"Industrial Firecrystal Mine", 14}, {"Scorpium Mine", 14}, {"Atomium Mine", 5}, {"Nature's Enchantment", 1} },
        { {"Industrial Firecrystal Mine", 7}, {"Scorpium Mine", 7}, {"Dragonglass Mine", 5}, {"Dreamer's Fright", 5}, {"Dreamer's Anguish", 5}, {"Atomium Mine", 4}, {"Crystalized System", 1}, {"Massive Diamond Mine", 1}, {"Behemoth Blossom", 1} },
    },
    ["Optic Origin"] = {
        { {"Ore Illuminator", 16}, {"The Catalyst", 5}, {"Tesla Resetter", 2} },
    },
    ["The Death Cap"] = {
        { {"Dragonglass Mine", 25}, {"Quantum Ore Cleaner", 15}, {"Sage Redeemer", 4} },
        { {"Dreamer's Fright", 10}, {"Newtonium Mine", 10}, {"Atlantic Monolith", 4}, {"Industrial Firecrystal Mine", 4}, {"Ore Illuminator", 3}, {"Scorpium Mine", 3}, {"Azure Refiner", 2}, {"Frozen Justice", 2}, {"Tesla Resetter", 1} },
        { {"Dark Magic", 6}, {"Mineral Wheel", 4}, {"Dragonglass Mine", 3}, {"Dreamer's Fright", 3}, {"Dreamer's Anguish", 3}, {"Nuclear Stronghold", 3}, {"The Sporest", 2}, {"Big Bertha", 2}, {"Crystallized System", 2}, {"Azure Refiner", 1}, {"Lightningbolt Refiner", 1}, {"Orbital Cataclysm", 1} },
    },
    ["Havium Mine"] = {
        { {"Nature's Grip", 17}, {"Massive Diamond Mine", 9} },
        { {"Nature's Grip", 9}, {"Massive Diamond Mine", 7}, {"Tesla Resetter", 2}, {"Pizza Blaster", 1}, {"Behemoth Blossom", 1} },
    },
    ["Tyrant's Throne"] = {
        { {"Quantum Ore Cleaner", 12}, {"Atomium Mine", 10}, {"Massive Diamond Mine", 9}, {"Tesla Resetter", 9} },
    },
    ["Vulcan's Wrath"] = {
        { {"Industrial Firecrystal Mine", 25}, {"Tesla Resetter", 7} },
        { {"Morning Star", 15}, {"Big Bad Blaster", 11}, {"Nature's Grip", 8}, {"Dark Magic", 2} },
        { {"Morning Star", 6}, {"Red Giant", 6}, {"Scorpium Mine", 5}, {"Industrial Firecrystal Mine", 5}, {"Crystalized System", 3}, {"Dragonglass Mine", 2}, {"Dreamer's Fright", 2}, {"Dreamer's Anguish", 2}, {"Flaming Schrodinger", 2}, {"Scorching Heat", 2}, {"Tesla Resetter", 2}, {"Esoteric Citadel", 1} },
    },
    ["Ore Hypernova"] = {
        { {"Tesla Resetter", 40}, {"Industrial Firecrystal Mine", 10} },
    },
    ["Garden of Gaia"] = {
        { {"Azure Refiner", 27}, {"Industrial Firecrystal Mine", 9}, {"Lightningbolt Refiner", 7}, {"The Catalyst", 6} },
        { {"Azure Refiner", 20}, {"Red Giant", 6}, {"Cooling Chamber", 6}, {"Atomium Mine", 2}, {"Toxic Waste Disposal", 2}, {"Newtonium Mine", 1}, {"Behemoth Blossom", 1} },
    },
    ["Enchanted Library"] = {
        { {"Guardian of the Gate", 13}, {"Blind Justice", 13}, {"Gravitational Gearwork", 6}, {"Skyliner Flux", 6}, {"Phase Processor", 5}, {"Phase Refiner", 5}, {"Timeless Enhancement", 3}, {"Ore Illuminator", 1}, {"Clockwork", 1}, {"Neutropian Refiner", 1} },
        { {"Ore Illuminator", 7}, {"Dreamer's Might", 7}, {"Clockwork", 7}, {"Dark Magic", 5}, {"Phase Processor", 2}, {"Phase Refiner", 2}, {"Breech Loader", 1}, {"Gate of Eclipse", 1}, {"Pulsar Octagnium Mine", 1} },
    },
    ["The Hourglass"] = {
        { {"Dark Magic", 24}, {"Solar Flare", 17}, {"Mineral Wheel", 14}, {"Clockwork", 11}, {"Cooling Chamber", 9}, {"Dreamer's Might", 7}, {"Green Tea Latte", 2} },
        { {"Vortex Chamber", 34}, {"Massive Diamond Mine", 26}, {"Ore Illuminator", 16}, {"Green Tea Latte", 10} },
        { {"Ore Sawmill", 20}, {"The Catalyst", 17}, {"Quantum Ore Cleaner", 15}, {"Nature's Grip", 15}, {"Green Tea Latte", 6}, {"Industrial Firecrystal Mine", 4}, {"Tesla Resetter", 3}, {"Atomium Mine", 2}, {"Atlantic Monolith", 1} },
        { {"Vortex Chamber", 20}, {"Dreamer's Fright", 10}, {"Dragonglass Mine", 10}, {"Dreamer's Anguish", 10}, {"Clockwork", 10}, {"Massive Diamond Mine", 10}, {"Breech Loader", 10}, {"Mineral Wheel", 6}, {"Ore Illuminator", 5}, {"Frozen Justice", 2}, {"Nuclear Stronghold", 2}, {"Burst Refiner", 1} },
    },
    ["Methuselah's Mask"] = {
        { {"Toxic Waste Disposal", 24}, {"Atomium Mine", 15}, {"Breech Loader", 12}, {"Big Bad Blaster", 10} },
        { {"Atlantic Monolith", 10}, {"Dreamer's Fright", 9}, {"Dreamer's Anguish", 9}, {"Dragonglass Mine", 9}, {"Quantum Ore Cleaner", 3}, {"Nuclear Stronghold", 3}, {"Blind Justice", 1}, {"Guardian of the Gate", 1}, {"Clockwork", 1}, {"Breech Loader", 1}, {"The Abomination", 1}, {"Shard Park", 1}, {"Oblivion Weaver", 1} },
    },
    ["Swag City"] = {
        { {"Industrial Firecrystal Mine", 18}, {"Quantum Ore Cleaner", 10}, {"Toxic Waste Disposal", 9}, {"Green Tea Latte", 3}, {"Newtonium Mine", 2}, {"Atomium Mine", 2}, {"Ancient Temple", 1} },
    },
    ["Meralin's Sorcery"] = {
        { {"The Catalyst", 23}, {"Green Tea Latte", 15}, {"Nature's Grip", 8}, {"Wild Spore", 6}, {"Dreamer's Fright", 4}, {"Newtonium Mine", 3} },
    },
    ["The Heart of Void"] = {
        { {"Toxic Waste Disposal", 30}, {"Tesla Resetter", 18}, {"Flaming Schrodinger", 15}, {"Scorpium Mine", 10}, {"Azure Refiner", 8}, {"Sage Redeemer", 5} },
    },
    ["SpookApocalypse-Ω"] = {
        { {"Dreamer's Fright", 38}, {"Yunium Mine", 7}, {"The Catalyst", 7}, {"Blind Justice", 5} },
        { {"The Abomination", 25}, {"Plasma Scanner", 15}, {"Scorching Heat", 10}, {"Sage Redeemer", 5} },
    },
}

-- Every Superstitious craft consumes exactly one catalyst. The catalyst is
-- part of the recipe requirement, not a free-floating element cost, so a craft
-- is never attempted without it.
local SUPER_CATALYST = {
    ["Daestrophe"]          = "Catalyst of Void",
    ["Draedon's Gauntlet"]  = "Catalyst of Thunder",
    ["Havium Mine"]         = "Catalyst of Earth",
    ["Pandora's Box"]       = "Catalyst of Destruction",
    ["Delta Phantom"]       = "Catalyst of Spirits",
    ["Optic Origin"]        = "Catalyst of Light",
    ["Elysium Solemnity"]   = "Catalyst of the Supreme",
    ["The Death Cap"]       = "Catalyst of Death",
    ["Vulcan's Wrath"]      = "Catalyst of Fire",
    ["Midas Blaster"]       = "Catalyst of Fortune",
    ["Tyrant's Throne"]     = "Catalyst of Power",
    ["Garden of Gaia"]      = "Catalyst of Nature",
    ["Ore Hypernova"]       = "Catalyst of Space",
    ["Enchanted Library"]   = "Catalyst of Knowledge",
    ["The Hourglass"]       = "Catalyst of Time",
    ["Swag City"]           = "Catalyst of Blood Magic",
    ["Methuselah's Mask"]   = "Catalyst of Necromancy",
    ["Meralin's Sorcery"]   = "Catalyst of Magic",
    ["The Heart of Void"]   = "Catalyst of Oblivion",
    ["SpookApocalypse-Ω"]   = "Catalyst of Chaos",
}

local function superItemId(name)
    local base = resolveName and resolveName(name) or name
    local id = MHItem.nameToId[base]
    if id then return id, base end
    local want = name:lower()
    for _, m in ipairs(RS.Items:GetChildren()) do
        local mn = m.Name:lower()
        if mn == want then
            local idv = m:FindFirstChild("ItemId")
            if idv then return idv.Value, m.Name end
        end
    end
    for _, m in ipairs(RS.Items:GetChildren()) do
        local mn = m.Name:lower()
        if mn:find(want, 1, true) or want:find(mn, 1, true) then
            local idv = m:FindFirstChild("ItemId")
            if idv then return idv.Value, m.Name end
        end
    end
    -- "Catalyst of the Supreme" and "Catalyst of Supreme" are the same item.
    local alt = want:gsub(" of the ", " of ")
    if alt ~= want then
        for _, m in ipairs(RS.Items:GetChildren()) do
            local mn = m.Name:lower()
            if mn:find(alt, 1, true) or alt:find(mn, 1, true) then
                local idv = m:FindFirstChild("ItemId")
                if idv then return idv.Value, m.Name end
            end
        end
    end
    return nil, name
end

local function craftKind(m, name)
    if not m then return nil end
    name = name or m.Name
    if m:FindFirstChild("FusionReq") then return "Fusion" end
    local rb = m:FindFirstChild("RebornId")
    if rb and type(rb.Value) == "number" and rb.Value > 0 then return "Evolution" end
    if m:FindFirstChild("EnchantCost") then return "Enchanted" end
    -- Recipe tables first: the model children were renamed/removed in the
    -- newest update, and the tables are the only stable description.
    if SUPER_RECIPES[name] or SUPER_CATALYST[name] then return "Superstitious" end
    if m:FindFirstChild("ElementCraftingPrice") then return "Superstitious" end
    return nil
end

local function craftItemName(id)
    local m = ITEM_BY_ID[id]
    if m then return m.Name end
    local ok, def = pcall(function() return FetchItem_LC:Get(id) end)
    if ok and def then return def.Name end
    return "#" .. tostring(id)
end

function CRAFT_Names()
    local out = {}
    for name, m in pairs(CRAFT_BY_NAME) do
        if craftKind(m, name) then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

function CRAFT_Plan(name)
    local m = CRAFT_BY_NAME[name]
    if not m then return nil, "Unknown recipe" end
    local kind = craftKind(m, name)
    if not kind then return nil, "Not craftable" end
    local id = itemIdOf(m)
    local plan = { name = name, id = id, kind = kind, lines = {}, missing = 0, need = {}, elements = {}, shards = nil }
    local bp = m:FindFirstChild("BlueprintPrice")
    plan.blueprint = bp and bp.Value or nil
    plan.points = lp.Points and lp.Points.Value or 0

    local reqs = {}
    plan.catalyst = SUPER_CATALYST[kind == "Superstitious" and name or ""]
    if kind == "Fusion" then
        for _, c in ipairs(m.FusionReq:GetChildren()) do
            local cid = tonumber(c.Name)
            if cid then reqs[#reqs + 1] = { id = cid, qty = c.Value } end
        end
    elseif kind == "Evolution" then
        reqs[1] = { id = m.RebornId.Value, qty = (m.RebornCount and m.RebornCount.Value) or 1 }
    elseif kind == "Enchanted" then
        for _, c in ipairs(m.EnchantCost:GetChildren()) do
            local cid = tonumber(c.Name)
            if cid then reqs[#reqs + 1] = { id = cid, qty = c.Value }
            elseif c.Name == "Shards" then plan.shards = c.Value end
        end
    elseif kind == "Superstitious" then
        local recipes = SUPER_RECIPES[name]
        if recipes then
            local best, bestMissing = nil, nil
            for _, rec in ipairs(recipes) do
                local miss = 0
                for _, ing in ipairs(rec) do
                    local iid = superItemId(ing[1])
                    local owned = iid and LC_Owned(iid) or 0
                    miss = miss + math.max(0, ing[2] - owned)
                end
                if not bestMissing or miss < bestMissing then best, bestMissing = rec, miss end
            end
            if best then
                for _, ing in ipairs(best) do
                    local iid, resolved = superItemId(ing[1])
                    reqs[#reqs + 1] = { id = iid, name = resolved, qty = ing[2] }
                end
            end
        end
        -- One catalyst is mandatory for every Superstitious item. Draedon
        -- consumes it alongside the item recipe, so it belongs in the missing
        -- list and blocks the craft exactly like any other material.
        local catName = SUPER_CATALYST[name]
        if catName then
            local cid, resolved = superItemId(catName)
            plan.catalystName = resolved or catName
            plan.catalystId = cid
            reqs[#reqs + 1] = { id = cid, name = resolved or catName, qty = 1, catalyst = true }
        end
    end

    for _, r in ipairs(reqs) do
        local owned = 0
        if r.id then owned = LC_Owned(r.id) end
        local short = math.max(0, r.qty - owned)
        plan.missing = plan.missing + short
        local label = r.name or craftItemName(r.id)
        table.insert(plan.lines, string.format("  %dx %-26s owned %d%s", r.qty, label, owned,
            short > 0 and ("  (-" .. short .. ")") or ""))
        plan.need[#plan.need + 1] = { id = r.id, name = label, qty = r.qty, owned = owned, short = short }
    end
    for _, e in ipairs(plan.elements) do
        table.insert(plan.lines, string.format("  %s %d", e.name, e.qty))
    end

    plan.craftable = plan.missing == 0 and #plan.elements == 0 and plan.shards == nil
    local head = string.format("%s · %s%s", kind, name,
        plan.blueprint and (" · blueprint " .. formatCash(plan.blueprint) .. " RP") or "")
    local tail
    if plan.shards then
        tail = string.format("costs %d shards - manual only", plan.shards)
    elseif #plan.elements > 0 then
        tail = string.format("needs %d element types - check Draedon", #plan.elements)
    elseif plan.missing > 0 then
        tail = string.format("missing %d items", plan.missing)
    else
        tail = "materials complete"
    end
    plan.text = head .. "\n" .. table.concat(plan.lines, "\n") .. "\n" .. tail
    return plan
end

-- ── PROGRESSION ─────────────────────────────────────────────────────
local function craftsmanCall(action, id)
    local ce = Net.CraftsmanEvents
    if ce == nil then return false, "no remote" end
    for _, method in ipairs({ "InvokeServer", "Invoke", "FireServer", "Fire" }) do
        if type(ce[method]) == "function" then
            local ok, res = pcall(ce[method], ce, action, id)
            if ok then return true, res end
        end
    end
    if ce.Event and type(ce.Event.InvokeServer) == "function" then
        local ok, res = pcall(function() return ce.Event:InvokeServer(action, id) end)
        if ok then return true, res end
    end
    return false, "unsupported remote"
end

local function craftFamilies()
    local out = { Fusion = {}, Evolution = {}, Enchanted = {}, Superstitious = {} }
    for _, n in ipairs(CRAFT_Names()) do
        local k = craftKind(CRAFT_BY_NAME[n], n)
        if k and out[k] then table.insert(out[k], n) end
    end
    return out
end

local function craftRows(plan)
    local rows = {}
    local covered = {}
    for _, r in ipairs(plan.need) do
        if r.short > 0 then
            table.insert(rows, { bar = true, label = r.name or craftItemName(r.id), have = r.owned, need = r.qty,
                right = "-" .. r.short })
        else
            covered[#covered + 1] = { check = true, label = r.name or craftItemName(r.id) }
        end
    end
    for _, e in ipairs(plan.elements) do
        table.insert(rows, { bar = true, label = e.name, have = 0, need = e.qty, right = "-" .. e.qty })
    end
    if #covered > 0 then
        table.insert(rows, { head = "Covered" })
        for _, c in ipairs(covered) do table.insert(rows, c) end
        covered = {}
    end
    if plan.shards then
        table.insert(rows, { text = string.format("%d shards - manual crafting only", plan.shards), tone = "bad" })
    end
    return rows, covered
end

-- Expands only into recipes you are actually short of; anything owned stays
-- a single line.
local function craftTree(plan)
    local rows = craftRows(plan)
    local function walk(need, depth)
        if depth > 2 then return end
        for _, r in ipairs(need) do
            if r.short > 0 and r.id then
                local m = ITEM_BY_ID[r.id]
                local sub = m and CRAFT_Plan(m.Name)
                if sub and sub.kind ~= "Superstitious" and sub.kind ~= "Enchanted" and sub.missing > 0 then
                    table.insert(rows, { head = craftItemName(r.id) .. " - " .. sub.kind })
                    local scaled = {}
                    for _, q in ipairs(sub.need) do
                        local want = q.qty * r.short
                        scaled[#scaled + 1] = { id = q.id, qty = want, owned = q.owned, short = math.max(0, want - q.owned) }
                    end
                    walk(scaled, depth + 1)
                end
            end
        end
    end
    walk(plan.need, 1)
    return rows
end

local function craftChips(plan)
    local chips = { { text = plan.kind, tone = "neutral" } }
    if plan.catalystName then
        chips[#chips + 1] = { text = plan.catalystName, tone = "warn" }
    end
    if plan.blueprint then
        chips[#chips + 1] = { text = formatCash(plan.blueprint) .. " RP blueprint", tone = "warn" }
    end
    return chips
end

-- The game talks to every channel through Net.invoke -> channel.Invoke, which
-- returns (callOk, response). Actions are namespaced "type:" strings, and
-- Superstitious crafting moved to its own remote in the newest update.
local function remoteInvoke(channel, ...)
    if channel == nil then return false, "no remote" end
    if type(Net.invoke) == "function" then
        local ok, res = Net.invoke(channel, ...)
        if ok then return true, res end
        return false, tostring(res)
    end
    local ok, res = pcall(channel.Invoke, channel, ...)
    if ok then return true, res end
    return false, tostring(res)
end

local function buyBlueprint(id)
    local ce = Net.CraftsmanEvents
    local ok = remoteInvoke(ce, "type:buyblueprint", id)
    if ok then return true end
    return remoteInvoke(ce, "BuyBlueprint", id)
end

local CRAFT_VERBS = {
    Fusion = "type:fusions",
    Evolution = "type:evolution",
    Enchanted = "type:enchant",
}

-- A craft only counts when the item count goes up. A server that returns true
-- but never grants the item is still a failure.
local function craftIngredients(plan)
    local out = {}
    for _, r in ipairs(plan.need) do
        -- The catalyst is validated separately by the server, exactly like the
        -- game's own Draedon UI, so it is not part of the used-items list.
        if r.id and r.qty and r.qty > 0 and not r.catalyst and r.id ~= plan.catalystId then
            out[#out + 1] = { itemId = r.id, quantity = r.qty }
        end
    end
    return out
end

local function craftUntilCrafted(plan)
    local before = LC_ItemCount(plan.id)
    local tried = {}
    local function attempt(label, fn)
        local ok, res = fn()
        tried[#tried + 1] = label .. " -> " .. (ok and tostring(res) or ("error " .. tostring(res)))
        task.wait(1.1)
        return LC_ItemCount(plan.id) > before
    end

    if plan.kind == "Superstitious" then
        local cs = Net.CraftSuperstitious
        if cs == nil then return false, "no CraftSuperstitious remote" end
        -- Confirmed from the game's Superstitious menu:
        --   Net.invoke(CraftSuperstitious, itemId, { {itemId=, quantity=}, ... })
        local items = craftIngredients(plan)
        if attempt("super(id,items)", function() return remoteInvoke(cs, plan.id, items) end) then
            return true, "super(id,items)"
        end
        if attempt("super(id)", function() return remoteInvoke(cs, plan.id) end) then
            return true, "super(id)"
        end
        return false, table.concat(tried, "   ")
    end

    local verb = CRAFT_VERBS[plan.kind]
    if not verb then return false, plan.kind .. " has no confirmed craftsman verb" end
    local ce = Net.CraftsmanEvents
    if ce == nil then return false, "no CraftsmanEvents remote" end
    -- Confirmed from the game's Craftsman menu: the second argument is the
    -- numeric item id, never the display name.
    if attempt(verb, function() return remoteInvoke(ce, verb, plan.id) end) then
        return true, verb
    end
    return false, table.concat(tried, "   ")
end

CraftSection = ProgTab:CreateSection("Crafting")
CraftSection:AddButton({ Name = "Craftsman", Callback = function() openMenu("Craftsman") end })
CraftSection:AddButton({ Name = "Draedon", Callback = function() openMenu("Superstitious") end })

local families = craftFamilies()
local function addFamily(title, list)
    if #list == 0 then return end
    local sec = ProgTab:CreateSection(title)
    local chosen = list[1]
    sec:AddDropdown({ Name = "Item", Options = list, Default = list[1], Callback = function(v) chosen = v end })
    sec:AddButton({ Name = "Show", Callback = function()
        local plan, err = CRAFT_Plan(chosen)
        if not plan then UI:Notify({ Title = title, Content = tostring(err), Type = "Error" }) return end
        DV_Dialog(plan.name, craftChips(plan), craftTree(plan))
    end })
    sec:AddButton({ Name = "Craft", Callback = function()
        local plan, err = CRAFT_Plan(chosen)
        if not plan then UI:Notify({ Title = title, Content = tostring(err), Type = "Error" }) return end
        if plan.shards then
            UI:Notify({ Title = "Craft", Content = "Costs shards - craft manually.", Type = "Error" })
            DV_Dialog(plan.name, craftChips(plan), craftRows(plan))
            return
        end
        if not plan.craftable then
            UI:Notify({ Title = "Craft", Content = "Missing materials.", Type = "Error" })
            DV_Dialog(plan.name, craftChips(plan), craftTree(plan))
            return
        end
        task.spawn(function()
            local ok, detail = craftUntilCrafted(plan)
            if ok then
                UI:Notify({ Title = "Craft", Content = plan.name .. " crafted.", Type = "Success" })
            else
                UI:Notify({ Title = "Craft", Content = "Server did not craft it.", Type = "Error" })
                DV_Dialog(plan.name, craftChips(plan), {
                    { text = "Materials are present but the server rejected every action.", tone = "bad" },
                    { head = "Responses" },
                    { text = detail },
                }, { footer = "Check blueprint ownership or the Craftsman action name." })
            end
        end)
    end })
end
addFamily("Fusions", families.Fusion)
addFamily("Evolutions", families.Evolution)
addFamily("Enchanted", families.Enchanted)
addFamily("Superstitious", families.Superstitious)

-- Auto buy: only when the RP is actually there, and each blueprint is retried
-- on a long cooldown so an unowned-but-rejected entry cannot spam popups.
local AutoBlueprints = { on = false, tried = {} }
local BuySection = ProgTab:CreateSection("Blueprints")
BuySection:AddToggle({ Name = "Auto Buy Blueprints", Default = false, Callback = function(v) AutoBlueprints.on = v end })

local function blueprintList()
    local out = {}
    for name, m in pairs(CRAFT_BY_NAME) do
        local bp = m:FindFirstChild("BlueprintPrice")
        if bp and m.ItemId then out[#out + 1] = { name = name, id = m.ItemId.Value, price = bp.Value } end
    end
    table.sort(out, function(a, b) return a.price < b.price end)
    return out
end

task.spawn(function()
    local gen = _G.DeepveinGen
    local list
    while lp.Parent and _G.DeepveinGen == gen do
        task.wait(3)
        if AutoBlueprints.on then
            list = list or blueprintList()
            local points = lp.Points and lp.Points.Value or 0
            for _, bp in ipairs(list) do
                if not AutoBlueprints.on then break end
                local last = AutoBlueprints.tried[bp.name]
                if points >= bp.price and (not last or os.clock() - last > 60) then
                    AutoBlueprints.tried[bp.name] = os.clock()
                    buyBlueprint(bp.id)
                end
            end
        end
    end
end)
-- ── AUTO PLACE ─────────────────────────────────────────────────────
-- Everything is derived from what is actually in the inventory and the local
-- item database: no name guessing, no fixed layout. The packer is a guillotine
-- rectangle solver with 90 degree rotation, then a gravity compaction pass so
-- no reachable gap is left inside the packed area.
-- Full machine data from the current mh_database. The legacy tables below are
-- kept for the route UI, but every value the planner uses comes from here.
DB_MACHINES = {
["'Ol Faithful"]={k="mine",v=40000000,r=0.5,s="6x4"},
["100M Upgrader"]={k="upgrader",m=2,p=1.4142,u=1,s="2x4"},
["Abominable Screaming Tree"]={k="upgrader",m=8,mm=14,p=1.3845,u=1,s="7x10"},
["Acorn Avenue"]={k="upgrader",m=3,p=1.2457,u=1,s="5x12"},
["Advanced Furnace"]={k="furnace",m=1.5,s="4x2"},
["Advanced Ore Atomizer"]={k="upgrader",m=1.4,u=-1,s="8x4"},
["Advanced Ore Scanner"]={k="upgrader",m=3,u=1,s="4x4"},
["Aerogel Refiner"]={k="upgrader",m=2,u=3,s="2x6"},
["Aether Refinery"]={k="furnace",m=90,mm=300,s="4x6"},
["Aether Schrodinger"]={k="upgrader",m=300,d=0.25,x=1,u=-1,s="4x4"},
["Aethereal Synthesizer"]={k="furnace",m=1000,mm=5000,s="7x10"},
["Airborne Pathogenic Spewer"]={k="upgrader",m=200,mm=3200,u=1,s="9x12"},
["Alien Relic"]={k="upgrader",m=4,p=2,u=1,s="2x3"},
["All Star Behemoth Cake"]={k="furnace",m=645,s="14x12"},
["All Star Sundae"]={k="upgrader",m=16.667,mm=25,u=1,s="8x10"},
["Amber Fossilizer"]={k="upgrader",m=2.5,u=1,s="2x5"},
["Ambrosia Forest"]={k="furnace",m=300,mm=1100,s="4x6"},
["Ambrosia Fountain"]={k="furnace",m=30,mm=110,s="4x6"},
["Ambrosia Garden"]={k="furnace",m=25000,s="8x7"},
["Ambrosia Mine"]={k="mine",v=495000000,r=1,s="3x4"},
["Ancient Catalyst"]={k="upgrader",m=55,mm=65,u=1,s="6x6"},
["Ancient Coliseum"]={k="upgrader",m=10,mm=19,p=1.5849,u=1,s="5x10"},
["Ancient Magic"]={k="furnace",m=35,s="6x8"},
["Ancient Temple"]={k="upgrader",m=3,mm=5,p=1.3195,u=1,s="5x6"},
["Angel's Blessing"]={k="upgrader",m=150,u=1,s="6x5"},
["Angel's Cake"]={k="upgrader",m=6,mm=10,u=3,s="7x10"},
["Angelic Grace"]={k="furnace",m=100,s="6x10"},
["Anguished Garden"]={k="furnace",m=17000,s="8x7"},
["Anguished Guardian of the Gate"]={k="furnace",m=800,mm=25600,s="12x8"},
["Anti-Gravity Scanner"]={k="upgrader",m=7,p=1.4475,u=1,s="4x4"},
["Apollium Mine"]={k="mine",v=1000000000000,r=1.515151515,s="10x10"},
["Arachnid Mine"]={k="mine",v=500000,s="4x6"},
["Arcane Lightning"]={k="upgrader",m=1,p=1.9257,u=1,s="6x6"},
["Aromatic Holidays"]={k="upgrader",m=3,p=1.4422,u=1,s="3x5"},
["Assembly Unit"]={k="furnace",d=1,x=1,s="2x6"},
["Astral Predictor"]={k="upgrader",m=1.08,mm=2.3316,u=1,s="4x4"},
["Astral Setter"]={k="upgrader",m=1.2,p=2.0476,u=1,s="4x6"},
["Atlantic Monolith"]={k="upgrader",m=4,p=1.3195,u=1,s="5x6"},
["Atlantic Monument"]={k="upgrader",m=13,p=1.5334,u=1,s="6x8"},
["Atmospheric Steamwork"]={k="upgrader",m=14,p=1.5525,u=1,s="8x6"},
["Atomium Mine"]={k="mine",v=3500000000,r=3.333333333,s="3x3"},
["Atomyke Mine"]={k="mine",v=20000000000000,r=3.333333333,s="10x9"},
["Aurora Borealis"]={k="furnace",m=0,s="12x8"},
["Auroral Metropolis"]={k="upgrader",m=10,mm=25,p=1.5838,u=1,s="7x10"},
["Auroral Wings"]={k="upgrader",m=2,p=1.4142,u=1,s="2x4"},
["Australis Fornacem"]={k="furnace",m=1,s="3x4"},
["Autumn Breeze"]={k="mine",v=0,r=0.3333333333,s="6x5"},
["Awakened Jack O Lantern"]={k="furnace",m=40,mm=2600,s="9x10"},
["Azure Purifier"]={k="upgrader",m=9,p=1.3687,u=1,s="7x10"},
["Azure Refiner"]={k="upgrader",m=4,p=1.5874,x=1,u=1,s="3x4"},
["Azure Spore"]={k="upgrader",m=50,mm=58,p=1.71,u=1,s="6x6"},
["Azurian Castle"]={k="upgrader",m=9,p=1.5518,u=1,s="5x8"},
["BUNZILLA"]={k="upgrader",m=7,u=1,s="4x8"},
["Bag of Stars"]={k="furnace",m=83500,mm=9950000,s="5x6"},
["Banana Split Upgrader"]={k="upgrader",m=5.5,p=1.5314,u=1,s="4x6"},
["Banana Sundae Refiner"]={k="upgrader",m=9,p=1.4422,u=1,s="6x8"},
["Basic Cell Furnace"]={k="furnace",m=20,s="2x2"},
["Basic Furnace"]={k="furnace",m=1,s="2x2"},
["Basic Iron Mine"]={k="mine",v=2,r=0.5,s="3x2"},
["Basic Ore Purifier"]={k="upgrader",m=1.1,u=-1,s="4x4"},
["Basic Research Center"]={k="furnace",m=1,s="3x3"},
["Bazingium Mine"]={k="mine",v=2,r=0.5,s="3x4"},
["Behemoth Blossom"]={k="upgrader",m=60,mm=100,u=1,s="8x10"},
["Behemoth Blossom/Renegade"]={k="upgrader",m=30,u=1,s="8x10"},
["Behemoth Snowflake"]={k="upgrader",m=3,p=1.3161,u=1,s="4x8"},
["Belated 4th Birthday Cake"]={k="furnace",m=100,s="10x10"},
["Berezaa Car Upgrader"]={k="upgrader",m=5,mm=10,u=1,s="4x8"},
["Berezium Mine"]={k="mine",v=3000,r=1,s="9x6"},
["Big Alberto"]={k="upgrader",m=25,p=1.71,u=1,s="6x10"},
["Big Bad Blaster"]={k="upgrader",m=2.65,d=0.1,x=1,u=-1,s="2x3"},
["Big Bertha"]={k="upgrader",m=10,p=3.1623,u=1,s="5x2"},
["Big Bunny"]={k="upgrader",m=4,u=1,s="3x2"},
["Big Candy Cane"]={k="upgrader",m=2,p=1.4142,u=1,s="2x4"},
["Big Fluxxus"]={k="upgrader",m=100,mm=300,p=2.361,u=2,s="6x6"},
["Big Fungus"]={k="upgrader",m=30,mm=50,p=2.1169,u=1,s="6x10"},
["Birthday Cake"]={k="furnace",m=1,mm=100,s="8x6"},
["Birthday Upgrader"]={k="upgrader",m=3,p=1.3161,u=1,s="4x4"},
["Bismuth Mine"]={k="mine",v=45000,r=0.25,s="4x4"},
["Black Dwarf"]={k="upgrader",t=1,nt=1,u=1,s="6x8"},
["Blazing Agriculture"]={k="upgrader",m=1,p=1.4913,u=1,s="6x8"},
["Blazing Annihilator"]={k="upgrader",u=-1,s="5x6"},
["Blind Justice"]={k="furnace",m=700000000,s="4x5"},
["Blizzard Predictor"]={k="upgrader",m=1.08,p=1.2434,u=1,s="4x6"},
["Blood Magic"]={k="furnace",m=20,mm=300,s="5x8"},
["Blue Supergiant"]={k="upgrader",m=3,mm=75,u=-1,s="6x6"},
["Blueberry Pie"]={k="upgrader",m=5,p=1.3797,u=1,s="5x8"},
["Book of Knowledge"]={k="furnace",m=1,s="6x8"},
["Boomite Mine"]={k="mine",v=5000000,s="4x5"},
["Borker's Luxury Villa"]={k="upgrader",m=1,mm=7,u=1,s="3x5"},
["Bouncy House!!!!111!!11!1"]={k="upgrader",m=6,mm=9,u=1,s="7x8"},
["Breached Motherboard"]={k="furnace",m=500,mm=4000,s="10x7"},
["Breech Loader"]={k="mine",v=90000000000,r=5,s="4x4"},
["Brick Wall Enhancer"]={k="upgrader",s="3x6"},
["Brimstone Spires"]={k="upgrader",m=10,p=1.6307,u=1,s="8x12"},
["Bubonic Plague"]={k="upgrader",m=15,p=1.219,u=1,s="7x12"},
["Burgor Diner"]={k="upgrader",m=4,p=1.4142,u=1,s="4x6"},
["Burst Refiner"]={k="upgrader",m=15,mm=500,u=1,s="6x5"},
["Burst Refiner/Renegade"]={k="upgrader",m=5,mm=12,u=1,s="6x5"},
["CONTRALAND"]={k="upgrader",m=11,mm=15,p=1.4913,u=1,s="6x8"},
["CYBEGG9000"]={k="upgrader",m=10,u=1,s="5x6"},
["Cactus Mirage"]={k="upgrader",m=5,p=1.3077,u=1,s="6x10"},
["Candy Bag"]={k="furnace",s="2x4"},
["Candy Cane Cannon"]={k="upgrader",m=2.65,u=-1,s="2x3"},
["Candy Castle"]={k="upgrader",m=3,p=1.2009,nt=1,u=1,s="6x5"},
["Candy Center"]={k="furnace",m=5,s="4x4"},
["Candy Core"]={k="upgrader",m=3,u=1,s="3x3"},
["Candy Corn Real Estate"]={k="upgrader",m=1.8,p=1.1029,nt=1,u=1,s="6x8"},
["Candy Factory"]={k="furnace",m=25,s="5x4"},
["Candy Metropolis"]={k="furnace",m=25,s="5x8"},
["Candy Refiner"]={k="upgrader",m=1.1,p=1.0488,u=1,s="2x4"},
["Candy Research Center"]={k="furnace",m=3,s="4x4"},
["Candycorn Refiner"]={k="upgrader",m=1.4,p=1.0878,u=1,s="6x4"},
["Canis Processus"]={k="furnace",m=75,mm=300,s="4x4"},
["Caramel Birthday Cake"]={k="upgrader",m=15,p=1.3511,u=1,s="9x10"},
["Carat Carrot Factory"]={k="furnace",s="6x8"},
["Carat Carrot Mine"]={k="mine",v=1,s="4x4"},
["Carrot Farm"]={k="upgrader",m=3,u=1,s="4x8"},
["Carrot Village"]={k="upgrader",m=9,mm=36,p=2.0477,u=1,s="5x8"},
["Castle Bravo"]={k="upgrader",m=120,p=2.2209,u=1,s="6x14"},
["Castle of Apocalypse"]={k="upgrader",m=5,p=1.3077,u=1,s="6x7"},
["Catalyzed Star"]={k="upgrader",m=1.6,mm=5,u=1,s="6x6"},
["Cell Collider"]={k="furnace",m=120000000000000,s="5x5"},
["Cell Incinerator"]={k="furnace",m=200,s="2x4"},
["Cell Particalizer"]={k="furnace",m=5000000000000,s="4x4"},
["Cell Processor"]={k="furnace",m=1000,s="6x2"},
["Cell Singularity"]={k="furnace",m=20,s="4x4"},
["Chemical Refiner"]={k="upgrader",m=7,p=1.3831,u=1,s="6x4"},
["Chicken Legg Cookout"]={k="upgrader",m=3.5,p=1.3678,u=1,s="4x6"},
["Chocolate Coater"]={k="upgrader",m=1.666666,p=1.1696,u=1,s="3x6"},
["Chocolate Cupcake"]={k="upgrader",m=7,p=1.4758,u=1,s="5x8"},
["Chocolate Forest"]={k="upgrader",m=1.4,u=1,s="5x6"},
["Citrus Cake"]={k="upgrader",m=5,mm=10,u=3,s="7x8"},
["Citrus Enhancer"]={k="upgrader",m=4.75,p=1.3656,u=1,s="5x8"},
["Clockwork"]={k="upgrader",m=5,p=1.71,u=1,s="3x4"},
["Clover Crunch"]={k="furnace",m=0,mm=1000,s="4x3"},
["Clover Refiner"]={k="upgrader",m=1.8,u=1,s="2x2"},
["Clover Rune"]={k="upgrader",m=2,u=4,s="1x4"},
["Clover Schrodinger"]={k="upgrader",m=2,mm=7,u=1,s="4x4"},
["Clover Shrine"]={k="upgrader",m=3,u=1,s="7x5"},
["Clovium Mine"]={k="mine",v=444000,r=1,s="2x3"},
["Coal Mine"]={k="mine",v=0,r=0.3333333333,s="2x2"},
["Coconut Drencher"]={k="furnace",m=1000000,mm=4000000,s="6x4"},
["Coliseum Catharsis"]={k="furnace",m=42500,s="14x10"},
["Combustion Engine"]={k="upgrader",m=5,mm=9,u=1,s="5x8"},
["Conquered Wasteland"]={k="furnace",m=45,s="8x10"},
["Conqueror's Delusion"]={k="upgrader",m=80,mm=1280,p=2.118,u=1,s="8x12"},
["Cooling Chamber"]={k="upgrader",m=11,p=1.8212,u=1,s="4x8"},
["Copper Mine"]={k="mine",v=20,r=0.4285714286,s="5x2"},
["Cosmic Device"]={k="upgrader",m=13,p=1.8988,u=1,s="4x6"},
["Crucible Iron Mine"]={k="mine",v=2,r=0.6666666667,s="3x2"},
["Cryogenic Upgrader"]={k="upgrader",m=1.45,u=3,s="4x6"},
["Cryptic Graveyard"]={k="upgrader",m=5,p=1.3077,u=1,s="6x10"},
["Crystal Altar"]={k="furnace",m=20000,s="14x13"},
["Crystal Mine"]={k="mine",v=35,r=0.3333333333,s="3x2"},
["Crystal Shrine"]={k="furnace",m=3000,s="6x8"},
["Crystallized Engine"]={k="upgrader",m=11,p=1.4913,u=1,s="6x8"},
["Crystallized System"]={k="upgrader",m=6,p=1.431,u=1,s="5x6"},
["Cupcakium Mine"]={k="mine",v=10000,r=1,s="5x4"},
["Cupid's Arrow"]={k="upgrader",m=5,u=1,s="2x2"},
["Cursed Ore Purifier"]={k="upgrader",u=-1,s="4x4"},
["DECADE HAVEN CAKE"]={k="furnace",m=2,nt=1,u=1,s="14x16"},
["DECADE HAVEN CHRISTMAS TREE"]={k="furnace",s="14x14"},
["DECADE HAVEN SPOOKMINE-5,256,000"]={k="upgrader",m=10,u=1,s="8x8"},
["DECADE HAVEN UPGRADER"]={k="upgrader",m=5,mm=59.7,u=1,s="6x8"},
["Da Mechanism"]={k="upgrader",m=7.77,u=1,s="8x5"},
["Dabium Mine"]={k="mine",v=12,s="2x2"},
["Daestrophe"]={k="upgrader",m=100,mm=200,t=1,nt=1,u=1,s="6x10"},
["Dark Illuminator"]={k="furnace",m=500,mm=5000,s="5x2"},
["Dark Magic"]={k="furnace",m=12,mm=45,s="6x2"},
["Darkmatter Mine"]={k="mine",v=14000000,r=0.5,s="3x3"},
["Darkseedium Mine"]={k="mine",v=1000000,r=1.25,s="8x10"},
["Deadly Spore"]={k="upgrader",m=10,mm=11,p=1.6266,u=1,s="4x6"},
["Deceptive Sorcery"]={k="upgrader",m=5,d=0.05,x=1,u=1,s="5x3"},
["Delightful Minty Cake"]={k="upgrader",m=7,u=1,s="6x10"},
["Delta Phantom"]={k="upgrader",m=100,mm=5000,p=2.1544,u=1,s="6x8"},
["Deluxe Beehive"]={k="upgrader",m=3.5,mm=7,p=1.8028,u=1,s="2x4"},
["Deluxe Santa's Workshop"]={k="mine",v=500000000,r=2,s="6x5"},
["Demon Core"]={k="upgrader",m=8,mm=14,p=1.4913,u=1,s="6x8"},
["Desert Monument"]={k="upgrader",m=13,p=1.6703,u=1,s="5x6"},
["Devil's Cake"]={k="upgrader",m=7,u=3,s="7x10"},
["Devil's Spore"]={k="upgrader",m=22,mm=27,p=1.7212,u=1,s="6x8"},
["Deviled Blaster"]={k="upgrader",m=13,u=-1,s="5x4"},
["Devourer of Nightmares"]={k="furnace",m=10000,s="5x6"},
["Diamond Breech Loader"]={k="mine",v=1e+15,r=5,s="7x6"},
["Diamond Egg"]={k="upgrader",m=2.5,p=1.5811,u=4,s="2x3"},
["Diamond Falls"]={k="furnace",m=21,s="12x10"},
["Diamond Mine"]={k="mine",v=500,r=0.5,s="3x3"},
["Digital Ore Cleaner"]={k="upgrader",m=1,u=-1,s="4x8"},
["Digital Peppermint Refiner"]={k="upgrader",m=4,u=1,s="4x8"},
["Dimension Extractor"]={k="mine",v=30000000000000,r=5,s="10x10"},
["Doge Chad Mine"]={k="mine",v=100000,r=0.3333333333,s="4x2"},
["Donut Refiner"]={k="upgrader",m=1.75,u=1,s="2x3"},
["Doom Incarnate"]={k="upgrader",m=2,mm=3.5,u=1,s="6x8"},
["Draconicglass Mine"]={k="mine",v=1e+17,s="8x8"},
["Dracula's Coffin"]={k="furnace",s="7x10"},
["Draedon's Gauntlet"]={k="upgrader",m=50,mm=2866.85,p=7.407,e=10,u=1,s="4x8"},
["Dragon Blaster"]={k="upgrader",m=4,d=0.09,x=1,u=-1,s="4x5"},
["Dragon Cake"]={k="upgrader",m=8,u=3,s="8x10"},
["Dragon Cannon"]={k="upgrader",m=15,p=1.7188,u=1,s="5x4"},
["Dragonglass Blaster"]={k="upgrader",m=9,d=0.1,x=1,u=-1,s="4x6"},
["Dragonglass Mine"]={k="mine",v=4000000000,s="5x3"},
["Dreamcatcher"]={k="furnace",m=7,u=1,s="8x6"},
["Dreamer's Anguish"]={k="furnace",m=10,mm=80,s="5x8"},
["Dreamer's Birthday Cake"]={k="upgrader",m=11,u=1,s="11x11"},
["Dreamer's Blight"]={k="furnace",m=500,s="8x7"},
["Dreamer's Devastation"]={k="furnace",m=14000,s="10x10"},
["Dreamer's Fright"]={k="furnace",m=5,mm=45,s="6x5"},
["Dreamer's Life"]={k="upgrader",m=125,p=2.8403,u=1,s="6x10"},
["Dreamer's Might"]={k="furnace",m=40,s="6x4"},
["Dreamer's Nightmare"]={k="furnace",m=100,s="10x7"},
["Dreamer's Sight"]={k="furnace",m=75,s="7x10"},
["Dreamer's Terror"]={k="furnace",m=1,mm=10000,s="14x11"},
["Dreamer's Valor"]={k="furnace",m=9500,s="12x9"},
["Drone Upgrader"]={k="upgrader",m=2,u=1,s="4x4"},
["Dual Festive Refiner"]={k="upgrader",m=2,mm=4,u=1,s="2x3"},
["Dystopian Refiner"]={k="upgrader",m=40,u=1,s="6x8"},
["Dystopian Refiner/Renegade"]={k="upgrader",m=5,u=1,s="6x8"},
["Easter Statues ðŸ—¿"]={k="upgrader",m=3,mm=6,u=1,s="7x6"},
["Eerie Marsh"]={k="upgrader",m=3,mm=7,p=1.2009,u=1,s="6x10"},
["Eggcelent Refiner"]={k="upgrader",m=2,u=1,s="1x4"},
["Eggmerald Geode"]={k="upgrader",m=4,p=1.3195,u=1,s="5x12"},
["Eggplosive Refiner"]={k="upgrader",m=4,mm=10,p=1.4142,u=1,s="4x5"},
["Eggscream Refiner"]={k="upgrader",m=4,u=1,s="3x3"},
["Electronic Furnace"]={k="furnace",m=1,mm=20,s="5x4"},
["Elevated Furnace"]={k="furnace",m=5,s="3x3"},
["Elysium Solemnity"]={k="furnace",m=200000,s="8x8"},
["Emerald Mine"]={k="mine",v=4000,r=0.4,s="3x3"},
["Empyrean Monument"]={k="upgrader",m=15,p=2.3051,u=1,s="6x8"},
["Enchanted Library"]={k="upgrader",m=65,p=2.125,u=1,s="6x10"},
["Endpoint Refiner"]={k="upgrader",m=1.6,mm=3.2,u=-1,s="2x4"},
["Energy Core"]={k="upgrader",m=4,u=1,s="3x4"},
["Equinox"]={k="furnace",m=70,s="8x5"},
["Eros Elixir"]={k="upgrader",m=5,u=1,s="4x6"},
["Esoteric Citadel"]={k="upgrader",m=40,p=2.5149,u=1,s="4x10"},
["Eternal Cake"]={k="upgrader",m=8,p=1.8612,u=1,s="4x10"},
["Eternal Fracture"]={k="furnace",m=2000000000,s="9x10"},
["Eternal Journey"]={k="furnace",m=100,s="10x6"},
["Eternal Limbo"]={k="furnace",m=19000,s="12x10"},
["Ethereal Sanctuary"]={k="furnace",m=25,s="9x10"},
["Excalibur"]={k="furnace",s="8x5"},
["Executive Pillars"]={k="upgrader",m=5.5,p=2.3452,u=1,s="2x4"},
["FRIGHT FOLLY"]={k="upgrader",m=6.66,u=1,s="4x3"},
["Famished Farm"]={k="upgrader",m=8,u=1,s="5x9"},
["Famished Wasteland"]={k="upgrader",m=4,u=1,s="6x10"},
["Father of Freon"]={k="upgrader",m=9,mm=45,p=1.4422,u=1,s="6x10"},
["Festive Spirit"]={k="upgrader",m=5,p=1.3077,u=1,s="6x6"},
["Fidget Spinner-ifier"]={k="upgrader",u=1,s="4x6"},
["Final Eclipse Gate"]={k="upgrader",m=10,mm=25,p=1.4301,u=1,s="8x14"},
["Final FabergÃ©"]={k="upgrader",m=6,u=1,s="5x5"},
["Fine-Point Upgrader"]={k="upgrader",u=-1,s="2x4"},
["Fire Mine"]={k="mine",v=700,r=0.25,s="2x3"},
["Fire-Blast Upgrader"]={k="upgrader",m=2,u=-1,s="2x4"},
["Firecrystal Excavator"]={k="mine",v=1000000,r=0.3333333333,s="5x4"},
["Firecrystal Mine"]={k="mine",v=473000,r=0.3333333333,s="3x2"},
["Firecrystallized System"]={k="upgrader",m=12.75,p=1.5285,u=1,s="6x8"},
["Firework Mine"]={k="mine",v=1000,r=1,s="5x4"},
["Flaming Ore Scanner"]={k="upgrader",m=5,u=1,s="5x4"},
["Flaming Schrodinger"]={k="upgrader",m=2.7,mm=7,d=0.25,x=1,u=-1,s="4x4"},
["Flying Dutchman"]={k="furnace",m=25,mm=70,s="10x6"},
["Fool's Gold Mine"]={k="mine",v=100000,r=0.5,s="2x3"},
["Forbidden Magic"]={k="furnace",m=100,mm=600,s="6x6"},
["Forsaken Battleground"]={k="upgrader",m=12,p=1.2457,u=1,s="5x10"},
["Forsaken Cake"]={k="furnace",m=15,mm=30,s="9x10"},
["Fractured Reality"]={k="upgrader",m=7,mm=13,p=1.8988,u=1,s="4x6"},
["Frank'n'Cupcake"]={k="upgrader",m=1.5,p=1.1067,nt=1,u=1,s="4x8"},
["Freon Bombarder"]={k="upgrader",u=-1,s="4x6"},
["Freon Sprayer"]={k="upgrader",u=-1,s="4x2"},
["Freon Supressor"]={k="upgrader",m=1.7,u=-1,s="4x2"},
["Freon-Blast Upgrader"]={k="upgrader",m=1.5,u=-1,s="2x4"},
["Freshly Baked Upsidedown Pineapple Cake"]={k="upgrader",m=10,u=1,s="4x4"},
["Friends Forever"]={k="upgrader",m=10,mm=20,u=1,s="5x7"},
["Frightful Cotton Candy"]={k="upgrader",m=3,u=1,s="3x4"},
["Frigid Dystopia"]={k="upgrader",m=15,p=1.5704,u=1,s="6x10"},
["Frostarium Mine"]={k="mine",v=1000,r=0.25,s="4x3"},
["Frostbite Chamber"]={k="upgrader",m=5,p=1.3797,nt=1,u=1,s="5x6"},
["Frosted Refiner"]={k="upgrader",m=1.75,p=1.75,u=1,s="1x4"},
["Frosty the Snowmine"]={k="mine",v=20000000,r=1.333333333,s="6x6"},
["Frozen Eclipse"]={k="upgrader",m=20,mm=40,p=1.6256,u=1,s="7x10"},
["Frozen Justice"]={k="furnace",m=10,mm=26,s="12x7"},
["Frozen Peaks"]={k="furnace",m=100,mm=600,s="6x10"},
["Fruitcake Blaster"]={k="upgrader",m=4,u=1,s="6x6"},
["Funky Town"]={k="furnace",m=600,s="10x5"},
["Funnel Cake"]={k="upgrader",m=44,u=1,s="7x8"},
["Fusion Reactor"]={k="furnace",m=5,s="5x6"},
["Gaia's Grasp"]={k="furnace",m=3000000000000,s="9x6"},
["Garden of Gaia"]={k="upgrader",m=90,p=1.9019,u=1,s="7x10"},
["Gargantium Core"]={k="furnace",m=1,s="12x12"},
["Gargantium Mine"]={k="mine",v=1e+22,r=3.333333333,s="12x10"},
["Gate of Eclipse"]={k="upgrader",m=4,mm=10,p=1.3895,u=1,s="7x8"},
["Gator's Cove"]={k="upgrader",m=10,p=1.4953,u=1,s="4x6"},
["Ghastly Graveyard"]={k="upgrader",m=2,p=1.3161,u=1,s="4x4"},
["Ghastly Saloon"]={k="upgrader",m=10,mm=12,u=1,s="6x10"},
["Ghosdeeri's Antidote"]={k="upgrader",m=12,p=1.431,u=1,s="5x6"},
["Ghost Town"]={k="upgrader",m=3.5,p=1.2322,u=1,s="6x9"},
["Ghost of Christmas Past"]={k="upgrader",m=3,u=1,s="2x2"},
["Ghoul Lagoon"]={k="upgrader",m=5.5,p=1.3286,u=1,s="6x10"},
["Giant Pretzel"]={k="upgrader",m=1,p=1,u=1,s="2x4"},
["Gift Blaster"]={k="upgrader",m=3.15,u=3,s="5x6"},
["Giftium Mine"]={k="mine",v=5000,r=1,s="4x4"},
["Gingerbread Boat"]={k="upgrader",m=5,u=1,s="3x9"},
["Gingerbread House"]={k="upgrader",m=5,u=1,s="2x5"},
["Gingerbread Mansion"]={k="upgrader",m=6,mm=9,u=1,s="4x7"},
["Gingerbreadium Mine"]={k="mine",v=1000000,s="12x9"},
["Gladiator's Fury"]={k="furnace",m=4,mm=32,s="5x8"},
["Glass Butterfly"]={k="upgrader",m=8,p=2,u=1,s="3x5"},
["Gloom Refiner"]={k="upgrader",m=3,p=1.4422,u=1,s="3x6"},
["Gold Excavator"]={k="mine",v=250,s="3x4"},
["Gold Mine"]={k="mine",v=75,r=0.5,s="3x2"},
["Golden Bell Upgrader"]={k="upgrader",m=3,u=1,s="2x3"},
["Golden Clover Blaster"]={k="upgrader",m=4,u=1,s="4x3"},
["Golden Clover Refiner"]={k="upgrader",m=5,mm=17.5,u=1,s="4x8"},
["Golden Horseshoe"]={k="upgrader",m=5,u=1,s="4x8"},
["Goliath Gumball Machine"]={k="mine",v=450000,r=1.333333333,s="5x5"},
["Goliath Skull"]={k="upgrader",m=20,u=1},
["Grand Birthday Cake"]={k="furnace",m=35,mm=350,s="8x5"},
["Grand Christmas Tree"]={k="furnace",m=675,mm=1125,s="9x10"},
["Grand Fruitcake"]={k="upgrader",m=6,p=1.2917,u=1,s="7x8"},
["Grand Wafer"]={k="upgrader",m=1.4,p=1.1187,u=1,s="3x8"},
["Grand Willow"]={k="furnace",m=35,mm=1575,nt=1,u=1,s="8x10"},
["Grandfather Clockwork"]={k="upgrader",m=5,mm=28,p=2.0154,u=1,s="4x8"},
["Gravitational Gearwork"]={k="upgrader",m=7,p=1.4758,u=1,s="5x6"},
["Gravitational Gyrocopter"]={k="furnace",m=802,mm=877,s="8x8"},
["Great Parasite"]={k="furnace",m=7000000000,mm=350000000000000,s="6x5"},
["Great Pumpkin"]={k="upgrader",m=3,mm=10,u=1,s="6x5"},
["Green Giant"]={k="upgrader",m=8,u=1,s="5x8"},
["Green Rock Candyizer"]={k="upgrader",m=1.5,u=1,s="4x8"},
["Green Tea Kettle"]={k="upgrader",m=9,u=1,s="6x6"},
["Green Tea Latte"]={k="upgrader",m=5,u=1,s="3x3"},
["Grimstruct"]={k="mine",v=1,s="9x11"},
["Guardian of the Gate"]={k="furnace",m=20,mm=200,s="5x7"},
["Guardian of the Portal"]={k="furnace",m=300,mm=900,s="8x7"},
["Gummy Refiner"]={k="upgrader",m=2,p=1.2599,u=1,s="3x6"},
["Hades' Fang"]={k="mine",v=10000000,s="3x5"},
["Hades' Palace"]={k="upgrader",m=6,p=1.7627,u=1,s="6x10"},
["Hanging Wreath"]={k="upgrader",m=12,p=1.5131,u=1,s="6x8"},
["Haunted Carnival"]={k="furnace",m=80000000,s="4x7"},
["Havenpreneur Upgrader"]={k="upgrader",m=3,u=1,s="5x8"},
["Havium Mine"]={k="mine",v=2e+22,r=3.333333333,s="6x7"},
["Heart of Dusk"]={k="furnace",m=150,s="14x11"},
["Hearty Refiner"]={k="upgrader",m=1.25,mm=3.43,u=4,s="1x3"},
["Heat Condenser"]={k="upgrader",m=3,u=4,s="5x4"},
["Heavenly Flux"]={k="upgrader",m=7,p=1.6266,u=3,s="6x6"},
["Heavenly Forge"]={k="furnace",m=6,s="5x9"},
["Heavenly Wisp"]={k="furnace",m=300,s="6x8"},
["Helium Blaster"]={k="upgrader",u=1,s="4x4"},
["Hellish Bat Cookie"]={k="upgrader",m=3,mm=5,u=1,s="4x4"},
["Hive Mind Extravaganza"]={k="upgrader",m=7,p=1.4758,u=1,s="5x6"},
["Hogog"]={k="upgrader",m=5,p=1.4953,u=1,s="5x4"},
["Holiday Street Refiner"]={k="upgrader",u=1,s="6x6"},
["Honeycomb Cake"]={k="upgrader",m=6,u=3,s="9x12"},
["Honeycomb Solace"]={k="upgrader",m=5,p=1.3077,u=1,s="6x8"},
["Hopeless Bog"]={k="upgrader",m=2,u=1,s="4x6"},
["Horizon Centrifuge"]={k="upgrader",m=1.55,u=-1,s="2x3"},
["Hungry Spirit"]={k="furnace",m=50,mm=100,s="6x7"},
["Hydra Blaster"]={k="upgrader",m=3,mm=91.1,d=0.1,x=1,u=-1,s="5x6"},
["Hydraulic Duality Refiner"]={k="upgrader",m=5,p=1.71,u=1,s="3x2"},
["Hydraulic Freefall Upgrader"]={k="upgrader",m=1.3,u=5,s="3x2"},
["Hydraulic Presser"]={k="upgrader",u=-1,s="4x6"},
["Hydraulic Ramp Upgrader"]={k="upgrader",m=1.25,u=4,s="2x4"},
["Hyper Mine"]={k="mine",v=500,r=0.5,s="3x2"},
["ITeleporter"]={k="upgrader",m=9,u=1,s="6x5"},
["Ice Crusher"]={k="upgrader",m=6,p=1.431,u=1,s="5x8"},
["Ice Mine"]={k="mine",v=500,r=0.3333333333,s="2x3"},
["Igloo Refiner"]={k="upgrader",m=1.15,u=1,s="6x6"},
["Igneous Forge"]={k="furnace",m=1,s="7x3"},
["Igneous Lightning"]={k="upgrader",m=1,p=1.984,u=1,s="7x10"},
["Illuminator Evaluator"]={k="upgrader",m=3.1,mm=66,d=0.25,x=1,u=-1,s="4x4"},
["Illusions of Void"]={k="upgrader",m=1,mm=7,p=1.3195,u=1,s="5x8"},
["Incendium Mine"]={k="mine",v=8e+15,r=7.692307692,s="7x3"},
["Incendium Mine/Renegade"]={k="mine",v=8000000000000,r=7.692307692,s="7x3"},
["Industrial Ancient Gourd"]={k="mine",v=250000000,s="6x5"},
["Industrial Coal Mine"]={k="mine",v=0,s="3x5"},
["Industrial Diamond Mine"]={k="mine",v=8000,s="4x6"},
["Industrial Firecrystal Mine"]={k="mine",v=15000000,s="5x3"},
["Industrial Firegem Quarry"]={k="mine",v=3200000000,s="9x4"},
["Industrial Giftium Mine"]={k="mine",v=20000000,s="6x7"},
["Industrial Gold Mine"]={k="mine",v=100000,s="3x5"},
["Industrial Ore Welder"]={k="upgrader",m=2,mm=18.758,u=5,s="4x5"},
["Industrial Osmium Mine"]={k="mine",v=27000,s="5x4"},
["Industrial Rainbow Mine"]={k="mine",s="5x3"},
["Industrial Ruby Mine"]={k="mine",v=650,s="3x5"},
["Industrial Scarab"]={k="furnace",m=6826,mm=9752,s="10x11"},
["Industrial Skeletal Salvation"]={k="upgrader",m=4,p=1.219,u=1,s="7x12"},
["Inflatable Party Upgrader"]={k="upgrader",m=4,u=1,s="3x8"},
["Innovator's Research Center"]={k="furnace",m=2,s="4x4"},
["Interstellar Conqueror"]={k="furnace",m=22500000000,s="12x8"},
["Invasive Cyberlord"]={k="furnace",m=125,mm=250,u=1,s="5x8"},
["Ion Field"]={k="upgrader",m=2.5,u=4,s="4x4"},
["Iron Excavator"]={k="mine",v=20,s="3x3"},
["Iron Flakes Mine"]={k="mine",v=1,r=5,s="2x4"},
["Iron Mine"]={k="mine",v=15000000,r=0.5,s="2x3"},
["Iron Mine-Chan"]={k="mine",v=50000,r=0.2,s="2x4"},
["Jagged Enhancer"]={k="upgrader",m=3.5,u=-1,s="4x4"},
["Jelly Cake"]={k="upgrader",m=8,u=3,s="10x12"},
["Kappa Investor"]={k="furnace",m=0.5,s="8x5"},
["King Birthday Cake"]={k="upgrader",m=50,p=1.5445,u=1,s="9x12"},
["King Darkseed"]={k="upgrader",m=34,mm=102,p=1.2599,u=1,s="6x10"},
["King Gold Mine"]={k="mine",v=10000000000000,r=0.1,s="7x8"},
["L.I.M.E"]={k="upgrader",m=1.2,u=3,s="4x6"},
["Large Ore Upgrader"]={k="upgrader",m=1.5,u=-1,s="6x4"},
["Legendary Peppermint"]={k="upgrader",m=6,mm=10,p=1.9896,x=1,u=1,s="3x6"},
["Leggendary Black Hole"]={k="upgrader",m=20,u=1,s="2x2"},
["Lemon Land"]={k="furnace",m=35,s="7x10"},
["Leprechaun Trap"]={k="upgrader",m=5,mm=10,u=1,s="4x6"},
["Leprechaun's Hat"]={k="furnace",m=1511200000,s="5x6"},
["Lepretron"]={k="upgrader",m=1.486,mm=16,u=1,s="7x6"},
["Lightning Mine"]={k="mine",v=300,s="2x3"},
["Lightningbolt Predictor"]={k="upgrader",m=3,mm=13.8,d=0.2,x=1,u=-1,s="4x3"},
["Lightningbolt Refiner"]={k="upgrader",m=2,mm=7,d=0.2,x=1,u=-1,s="6x3"},
["Lollipop-inator"]={k="upgrader",m=1.75,p=1.75,nt=1,u=1,s="1x4"},
["Loop-de-Loop"]={k="upgrader",m=3,u=1,s="9x6"},
["Lord of the Apocalypse"]={k="upgrader",m=300,mm=1300,u=1,s="8x12"},
["Lucky Hat"]={k="upgrader",m=6,p=1.3803,u=1,s="5x7"},
["Lucky Research Center"]={k="furnace",m=7,s="4x4"},
["Lucky Seven's Cake"]={k="upgrader",m=0,mm=70,u=1,s="6x10"},
["Lunar Bombardment"]={k="furnace",m=150,mm=475,s="9x10"},
["Lunar Refiner"]={k="upgrader",m=8,u=3,s="4x4"},
["Lunar Spectacle"]={k="upgrader",m=25,mm=50,u=1,s="4x10"},
["Lunar Spectacle/Renegade"]={k="upgrader",m=10,mm=20,u=1,s="4x10"},
["MONSTER TRUCKER!"]={k="upgrader",u=1,s="4x6"},
["Macaroon Upgrader"]={k="upgrader",m=3,p=1.3161,u=1,s="4x6"},
["Mad Monstrous Melter"]={k="upgrader",m=6.1,d=0.3,x=1,u=-1,s="7x7"},
["Maintenance Supporter"]={k="upgrader",m=5,p=1.4953,u=1,s="4x6"},
["Malicious Incubator"]={k="upgrader",m=15,u=1,s="5x9"},
["Massive Diamond Drill"]={k="mine",v=500000000000,r=2,s="8x10"},
["Massive Diamond Mine"]={k="mine",v=10000000,r=0.1,s="7x7"},
["Massive Gold Mine"]={k="mine",v=20700,r=0.08333333333,s="6x5"},
["Massive Iron Mine"]={k="mine",v=10000,r=0.1111111111,s="6x4"},
["Massive Quantum Diamond Cleaner"]={k="upgrader",m=14,p=1.5525,u=1,s="6x10"},
["Meatball Sandwich"]={k="upgrader",m=10,p=2.1544,u=1,s="3x8"},
["Melancholy Holidays"]={k="upgrader",m=1.75,u=1,s="3x5"},
["Meralin's Sorcery"]={k="upgrader",m=105,mm=220,p=4.0461,u=1,s="7x8"},
["Methane Sky Fleet"]={k="upgrader",m=1,mm=5,p=1.71,u=1,s="3x4"},
["Methuselah's Mask"]={k="upgrader",m=140,u=1,s="6x7"},
["Midas Blaster"]={k="upgrader",m=36,mm=123,d=0.3333,x=1,u=-1,s="5x6"},
["Mighty Sugar Cookie"]={k="upgrader",m=8.5,p=1.5912,u=1,s="5x8"},
["Mineral Wheel"]={k="upgrader",m=6,p=1.5651,u=1,s="4x4"},
["Mini Upgrader"]={k="upgrader",m=1.25,mm=3.75,u=6,s="1x3"},
["Mithril Mine"]={k="mine",v=75000,r=0.5,s="6x5"},
["Moai God"]={k="upgrader",m=8,p=1.6818,u=1,s="4x6"},
["Molten Forge"]={k="upgrader",m=3,p=1.348,u=1,s="6x6"},
["Molten Upgrader"]={k="upgrader",m=1.8,u=-1,s="2x2"},
["Monstrous Mimic Cake"]={k="upgrader",m=4,mm=16,u=1,s="7x12"},
["Monstrous Stitchwork"]={k="upgrader",m=7,u=1,s="5x8"},
["Morning Star"]={k="upgrader",m=1.7,u=-1,s="4x4"},
["Mycolympus"]={k="upgrader",m=20,u=1,s="5x10"},
["Mystical Thunder"]={k="upgrader",m=1,p=2.1361,u=1,s="6x8"},
["Natural Spring"]={k="furnace",m=8,s="4x6"},
["Nature's Enchantment"]={k="furnace",m=0.5,mm=55000,s="8x7"},
["Nature's Enchantment/Renegade"]={k="furnace",mm=22500,s="7x8"},
["Nature's Grip"]={k="furnace",m=200000000000,s="4x2"},
["Nature's Temple"]={k="furnace",m=30000000000000,s="7x4"},
["Neutron Star"]={k="upgrader",m=1.65,mm=2,u=-1,s="6x4"},
["Neutropian Refiner"]={k="upgrader",m=90,mm=125,u=1,s="6x8"},
["Neutropian Refiner/Renegade"]={k="upgrader",m=10,mm=20,u=1,s="6x8"},
["New Year's City"]={k="furnace",m=25,mm=65,s="8x8"},
["Newtonic Corroder"]={k="upgrader",m=7,p=1.6266,u=1,s="4x6"},
["Newtonium Excavator"]={k="mine",v=45000000000000,s="6x10"},
["Newtonium Mine"]={k="mine",v=100000000,r=2,s="7x4"},
["Nightmare"]={k="mine",v=5000000000,s="4x9"},
["Ninja Diamond Mine"]={k="mine",v=1000,r=0.5,s="4x3"},
["Noobite Mine"]={k="mine",v=10000,r=0.5,s="4x3"},
["North Star"]={k="upgrader",m=3,u=1,s="4x6"},
["Northern Lights"]={k="furnace",m=80,mm=2000,s="10x6"},
["Nova Evaluator"]={k="upgrader",m=1.3,u=-1,s="4x6"},
["Nova Star"]={k="upgrader",m=4,mm=25,u=-1,s="4x5"},
["Noxious Containment"]={k="furnace",m=1,mm=5000000000,s="4x4"},
["Nuclear Castle"]={k="furnace",m=2100,mm=3100,s="10x14"},
["Nuclear Chamber"]={k="upgrader",m=2,p=1.3427,u=1,s="4x4"},
["Nuclear Stronghold"]={k="furnace",m=200,mm=290,s="8x6"},
["Oasis"]={k="furnace",m=50,s="8x7"},
["Oblivion Emission"]={k="furnace",m=25000,mm=33000,s="6x6"},
["Oblivion Weaver"]={k="mine",v=144000000000,r=0.25,s="10x6"},
["Oblivion Weaver/Renegade"]={k="mine",v=144000000000,s="13x10"},
["Obsidian Infusion Device"]={k="upgrader",m=12,u=1,s="5x10"},
["Octopi Council"]={k="furnace",m=50,mm=100,s="10x9"},
["One Million Upgrader"]={k="upgrader",m=10,p=2.1544,u=1,s="3x3"},
["Onyx Mine"]={k="mine",v=5400000000000,r=2,s="5x6"},
["Ooftopian Refiner"]={k="upgrader",m=1.5,p=2.1398,u=1,s="6x8"},
["Opal Mine"]={k="mine",v=8000,r=0.5,s="5x5"},
["Optic Origin"]={k="upgrader",m=400,p=2.1317,u=1,s="7x10"},
["Orange Rock Candyizer"]={k="upgrader",m=1.5,u=1,s="4x8"},
["Orbitable Upgrader"]={k="upgrader",m=1.4,u=3,s="3x2"},
["Orbital Antimatter Uplink"]={k="mine",v=100000,r=0.5,s="3x4"},
["Orbital Cataclysm"]={k="upgrader",m=45,u=1,s="6x8"},
["Orbital Cataclysm/Renegade"]={k="upgrader",m=20,u=1,s="6x8"},
["Orbital Christmas Uplink"]={k="mine",v=1000000,r=3.333333333,s="6x8"},
["Ore Basket"]={k="upgrader",m=2.5,u=1,s="2x6"},
["Ore Biplane"]={k="upgrader",m=4,mm=7,u=1,s="5x8"},
["Ore Cannon"]={k="upgrader",m=1.5,u=5,s="3x2"},
["Ore Caramelizer"]={k="upgrader",m=1.3,p=1.0914,u=1,s="3x4"},
["Ore Chainsaw"]={k="upgrader",m=8,p=1.4142,u=1,s="6x8"},
["Ore Collider"]={k="upgrader",m=5,u=5,s="3x2"},
["Ore Crane"]={k="upgrader",m=2,u=2,s="3x3"},
["Ore Destroyinator"]={k="upgrader",d=1,x=1,u=-1,s="8x2"},
["Ore Encapsulator"]={k="furnace",m=1,s="4x4"},
["Ore Gielder"]={k="upgrader",m=3,p=1.3161,u=1,s="4x8"},
["Ore Hoister"]={k="upgrader",m=2.5,u=1,s="3x2"},
["Ore Hypernova"]={k="upgrader",m=1500,nt=1,u=1,s="6x3"},
["Ore Illuminator"]={k="upgrader",m=7,e=5,u=1,s="5x4"},
["Ore Incinerator"]={k="furnace",m=3,s="2x5"},
["Ore Indoctrinator"]={k="upgrader",m=666,p=2.9551,e=66,u=1,s="6x6"},
["Ore Magmafier"]={k="upgrader",m=1.25,mm=2.73,u=1,s="7x6"},
["Ore Magnifier"]={k="upgrader",m=5,u=1,s="8x6"},
["Ore Memer"]={k="upgrader",m=300,p=1.7945,u=1,s="4x8"},
["Ore Negator"]={k="upgrader",m=2,nt=1,u=1,s="4x6"},
["Ore Nova"]={k="upgrader",m=70,nt=1,u=1,s="4x4"},
["Ore Painter"]={k="upgrader",u=-1,s="3x3"},
["Ore Recliner"]={k="upgrader",m=1.5,u=4,s="3x1"},
["Ore Replicator"]={k="upgrader",u=1,s="3x3"},
["Ore Roaster"]={k="upgrader",m=2,u=6,s="4x4"},
["Ore Sawmill"]={k="upgrader",u=1,s="6x5"},
["Ore Scanner"]={k="upgrader",m=2.5,u=1,s="4x4"},
["Ore Skillet"]={k="upgrader",m=2,mm=10,u=1,s="6x6"},
["Ore Steamer"]={k="upgrader",m=2,u=1,s="4x4"},
["Ore Striker"]={k="upgrader",m=1.5,mm=3,p=1.0699,d=0.1,x=1,u=1,s="6x6"},
["Ore Supernova"]={k="upgrader",m=500,nt=1,u=1,s="3x4"},
["Ore Thermocrusher"]={k="upgrader",m=1.3,u=-1,s="4x4"},
["Ore Tixicator"]={k="upgrader",u=1,s="4x4"},
["Ore Tracker"]={k="upgrader",u=1,s="2x4"},
["Ore Transistor"]={k="upgrader",m=1.45,u=-1,s="2x3"},
["Ore Transponder"]={k="upgrader",m=2,u=-1,s="6x6"},
["Ore Winder"]={k="upgrader",m=3,u=3,s="3x1"},
["Ore Wrapper"]={k="upgrader",u=-1,s="6x4"},
["Ore Zapper"]={k="upgrader",m=1.25,u=3,s="2x3"},
["Ornament Blaster"]={k="upgrader",m=3,u=1,s="4x4"},
["Osmium Excavator"]={k="mine",v=40000,s="5x4"},
["Osmium Mine"]={k="mine",v=15000,r=0.3333333333,s="4x2"},
["Overhang Upgrader"]={k="upgrader",m=4,u=1,s="3x4"},
["Overlord Device"]={k="upgrader",m=10,p=1.3895,u=1,s="7x6"},
["Painite Mine"]={k="mine",v=56000,r=0.8333333333,s="3x5"},
["Palladium Drill"]={k="mine",v=100000000000,r=10,s="8x9"},
["Pancake Stack"]={k="upgrader",m=33,u=1,s="5x8"},
["Pandora's Box"]={k="furnace",m=1000000,s="3x3"},
["Parasitic Invader"]={k="mine",v=3000000,r=0.5,s="9x10"},
["Peanut Butter Cake"]={k="upgrader",m=5,u=3,s="10x12"},
["Permafrost Refiner"]={k="upgrader",m=3,p=1.3161,u=1,s="8x4"},
["Phantom of Christmas Future"]={k="upgrader",m=5,u=1,s="2x2"},
["Phase Bombarder"]={k="upgrader",m=15,mm=50,p=1.5704,u=1,s="6x8"},
["Phase Processor"]={k="furnace",m=70,mm=500,s="8x6"},
["Phase Refiner"]={k="upgrader",m=4,mm=8,p=1.4142,u=1,s="4x8"},
["Phasecursor Furnace"]={k="furnace",m=1000,mm=10000,s="10x9"},
["Phasecursor Mine"]={k="mine",v=900000000000000,r=2,s="9x6"},
["Pillars of Creation"]={k="upgrader",m=9,mm=17,p=1.5334,u=1,s="6x8"},
["Pilotite Mine"]={k="mine",v=2800000000,r=1.428571429,s="6x4"},
["Pineapple Refiner"]={k="upgrader",m=2,p=1.1892,u=1,s="4x4"},
["Pineapple! Stand"]={k="upgrader",m=3,mm=4,u=1,s="3x3"},
["Pirate Cove"]={k="upgrader",m=1.13,mm=21.2,u=1,s="4x6"},
["Pirate's Loot Collector"]={k="furnace",m=1500,s="2x4"},
["Pistachio Slice"]={k="upgrader",m=11,u=1,s="4x6"},
["Pizza Blaster"]={k="upgrader",m=4,p=1.2599,u=1,s="6x6"},
["Pizza Bombarder"]={k="upgrader",m=10,p=1.3335,u=1,s="8x8"},
["Pizza Cutter"]={k="upgrader",m=5,u=1,s="5x4"},
["Pizza Furnace"]={k="furnace",m=1000,s="6x8"},
["Pizza Oven"]={k="upgrader",m=8,mm=80000,u=1,s="6x6"},
["Pizza Parlor"]={k="upgrader",m=50000,u=1,s="6x7"},
["Pizza Research Center"]={k="furnace",m=5,s="4x4"},
["Plague Doctor"]={k="upgrader",m=5,p=1.3077,u=1,s="6x10"},
["Plagued Forest"]={k="furnace",m=20,mm=75,s="8x11"},
["Plasma Iron Polisher"]={k="upgrader",m=4,u=1,s="2x4"},
["Plasma Scanner"]={k="upgrader",m=6,p=1.348,u=1,s="6x6"},
["Platinum Mine"]={k="mine",v=200,r=0.5,s="3x2"},
["Plutonium Excavator"]={k="mine",v=20000,s="4x4"},
["Plutonium Mine"]={k="mine",v=5500,r=0.5,s="4x5"},
["Portable Flamethrower"]={k="upgrader",u=-1,s="2x2"},
["Portable Macrowave"]={k="upgrader",m=1.8,u=1,s="2x3"},
["Portable Ore Advancer"]={k="upgrader",m=1.15,u=10,s="3x2"},
["Portable Ore Enhancer"]={k="upgrader",m=1.25,u=10,s="2x2"},
["Portable Ore Stopper"]={k="upgrader",m=1.5,u=10,s="2x2"},
["Portable Pearl Enhancer"]={k="upgrader",m=6,u=1,s="5x6"},
["Portable Tractor Beam"]={k="upgrader",m=1.2,u=16,s="4x4"},
["Pot of Gold"]={k="furnace",m=5000,s="5x7"},
["Pot of Gold-inator"]={k="upgrader",m=6,u=1,s="6x10"},
["Precision Refiner"]={k="upgrader",m=1.5,u=-1,s="4x6"},
["Precursor Furnace"]={k="furnace",m=70,mm=500,s="8x9"},
["Precursor Mine"]={k="mine",v=1000000000,r=0.5,s="6x8"},
["Present Center"]={k="furnace",m=5,s="4x4"},
["Present Refiner"]={k="upgrader",m=4,p=1.5874,u=1,s="3x6"},
["Present Schrodinger"]={k="upgrader",m=2.2,mm=7,p=1.259,d=0.2,x=1,nt=1,u=1,s="4x4"},
["Professional Upgrader"]={k="upgrader",m=1.3,u=4,s="5x4"},
["Proficient Research Center"]={k="furnace",m=1,s="4x4"},
["Protector of the Passage"]={k="upgrader",m=95,mm=125,u=1,s="7x10"},
["Pulsar Octagnium Mine"]={k="mine",s="5x5"},
["Pulsar Octagnium Mine/Renegade"]={k="mine",s="5x5"},
["Pumpkin Carriage"]={k="upgrader",m=3,p=1.3161,u=1,s="4x8"},
["Pumpkin Hero"]={k="upgrader",m=4,u=1,s="4x4"},
["Pumpkin Hut"]={k="upgrader",m=4,p=1.2599,u=1,s="6x8"},
["Pumpkin Patch"]={k="upgrader",m=2,u=1,s="5x6"},
["Pumpkin Pie Refiner"]={k="upgrader",m=1.8,p=1.1583,nt=1,u=1,s="4x8"},
["Pumpkin Possession"]={k="furnace",m=100000000,s="5x5"},
["Pumpkin Spice Refiner"]={k="upgrader",m=2.5,p=1.165,u=1,s="6x8"},
["Pumpkinite Mine"]={k="mine",v=4500000,s="13x13"},
["Purple Rock Candyizer"]={k="upgrader",m=1.5,u=1,s="4x8"},
["PurrÃ±ata"]={k="upgrader",m=3,u=1,s="3x6"},
["Putrid Farmyard"]={k="upgrader",m=4,p=1.2599,u=1,s="6x8"},
["Quaint Skymill"]={k="upgrader",m=9,mm=13.2,u=1,s="6x4"},
["Quantum Clockwork"]={k="upgrader",m=5,mm=30,p=2.3403,u=1,s="4x8"},
["Quantum Ore Cleaner"]={k="upgrader",m=4,p=1.4142,u=1,s="4x8"},
["Quantum Ore Polisher"]={k="upgrader",m=8,p=1.5157,u=1,s="5x8"},
["Quantum Processor"]={k="furnace",m=4,s="4x4"},
["Quantum Research Center"]={k="furnace",m=2,s="4x4"},
["Queen Birthday Cake"]={k="furnace",m=500,s="13x12"},
["Radio Tower"]={k="upgrader",m=20,nt=1,u=1,s="8x6"},
["Radioactive Refiner"]={k="upgrader",m=3,u=1,s="6x4"},
["Radium Mine"]={k="mine",v=1000,r=1.25,s="4x4"},
["Rainbonite Mine"]={k="mine",v=1000000000,r=1,s="7x4"},
["Rainbow Blaster"]={k="upgrader",m=5,u=1,s="3x2"},
["Rainbow Refiner"]={k="upgrader",m=4,p=2,u=1,s="2x5"},
["Rainbow Upgrader"]={k="upgrader",m=1.05,mm=2,u=-1,s="6x4"},
["Raised Furnace"]={k="furnace",m=6,s="4x4"},
["Raised Wide Upgrader"]={k="upgrader",u=-1,s="1x4"},
["Reaper's Fortress"]={k="upgrader",m=5,mm=7.5,p=1.8376,u=1,s="3x3"},
["Red Giant"]={k="upgrader",m=1.7,u=-1,s="6x6"},
["Red Velvet Cake"]={k="upgrader",m=12,p=1.4262,u=1,s="7x8"},
["Red Velvet Cupcake"]={k="upgrader",u=1,s="6x6"},
["Redwood Compass"]={k="furnace",m=385,s="6x8"},
["Reinforced Furnace"]={k="furnace",m=5,s="6x4"},
["Remote Ambrosia Mine"]={k="mine",v=800000000,s="5x4"},
["Remote Diamond Mine"]={k="mine",v=1000,s="4x3"},
["Remote Iron Mine"]={k="mine",v=10,s="3x2"},
["Remote Opal Mine"]={k="mine",v=16000,s="5x4"},
["Remote Osmium Mine"]={k="mine",v=25000,s="4x2"},
["Repulsion Device"]={k="upgrader",m=6,u=1,s="2x4"},
["Research Center"]={k="furnace",m=3,s="4x4"},
["Robotic Enhancer"]={k="upgrader",m=2,mm=6,p=1.5651,u=1,s="4x4"},
["Rock Candy Center"]={k="furnace",s="6x8"},
["Rose Palace"]={k="upgrader",m=5,u=1,s="4x7"},
["Rotary Upgrader"]={k="upgrader",m=4,u=1,s="5x5"},
["Royal Rabbit"]={k="upgrader",m=5.5,p=1.5314,u=1,s="4x8"},
["Ruby Crystallizer"]={k="upgrader",m=10,p=2.1544,u=1,s="3x6"},
["Rush Upgrader"]={k="upgrader",m=5,u=1,s="6x4"},
["Sacred Totem"]={k="upgrader",m=7,p=1.3831,u=1,s="6x6"},
["Sacrificial Altar"]={k="furnace",m=10,s="8x7"},
["Sacrificial Cell"]={k="furnace",m=50000,s="6x2"},
["Sage Justice"]={k="furnace",m=1.25,s="5x4"},
["Sage King"]={k="furnace",m=1.75,s="10x12"},
["Sage Redeemer"]={k="furnace",m=50,s="9x9"},
["Sakura Falls"]={k="furnace",m=9500,s="8x10"},
["Sakura Garden"]={k="furnace",m=300,s="6x7"},
["Sandshark"]={k="upgrader",m=10,u=1},
["Santa's Castle"]={k="upgrader",m=6,u=1,s="7x9"},
["Santa's Chimney"]={k="furnace",m=50000,mm=5000000000,s="3x3"},
["Santa's Deluxe Sleigh"]={k="upgrader",m=3,mm=4,u=1,s="5x4"},
["Santa's Nice List"]={k="upgrader",m=1,mm=5,p=1.3449,nt=1,u=1,s="5x10"},
["Santa's Rage"]={k="mine",v=0,s="4x4"},
["Santa's Sleigh"]={k="upgrader",m=4,u=1,s="4x2"},
["Santa's Train"]={k="upgrader",u=1,s="5x3"},
["Santa's Workclock"]={k="upgrader",m=5,p=2.2361,u=1,s="2x4"},
["Santa's Workshop"]={k="upgrader",m=1.07,u=5,s="5x3"},
["Satellite Beam"]={k="upgrader",m=2,mm=3,p=1.4422,u=1,s="3x3"},
["Saturated Catalyst"]={k="upgrader",m=8,p=1.3459,u=1,s="6x7"},
["Scales of Disparity"]={k="upgrader",m=0.925,mm=60,p=2.1054,u=1,s="7x12"},
["Schrodinger Chamber"]={k="upgrader",m=2.08,mm=7.65,d=0.25,x=1,u=-1,s="2x2"},
["Schrodinger Evaluator"]={k="upgrader",m=2.1,mm=7,d=0.25,x=1,u=-1,s="4x4"},
["Scorching Heat"]={k="upgrader",m=5,p=1.3797,d=1,x=1,u=1,s="5x6"},
["Scorpium Mine"]={k="mine",v=1000000,r=1,s="4x4"},
["Scorponyte Mine"]={k="mine",v=100000000000,r=1,s="6x7"},
["Searing Heat"]={k="upgrader",m=11,p=1.4913,u=1,s="6x7"},
["Serpentine Upgrader"]={k="upgrader",m=1.4,u=-1,s="4x5"},
["Shamrock Factory"]={k="upgrader",m=9,u=1,s="6x10"},
["Shard City"]={k="upgrader",m=16,p=1.486,u=1,s="7x10"},
["Shard Park"]={k="upgrader",m=10,p=1.4678,u=1,s="6x8"},
["Shiny Red Upgrader"]={k="upgrader",m=1.5,u=1,s="4x3"},
["Shrine of Penitence"]={k="furnace",m=25,s="4x6"},
["Silicon Excavator"]={k="mine",v=20,s="4x3"},
["Silkweaver"]={k="upgrader",m=1.75,p=1.3229,u=1,s="2x5"},
["Silver Mine"]={k="mine",v=5,r=1.428571429,s="3x3"},
["Sinister Sepulcher"]={k="upgrader",m=10000,u=-1,s="5x8"},
["Sinister Sepulcher/Renegade"]={k="upgrader",m=10000,u=-1,s="5x8"},
["Skydance Serenade"]={k="upgrader",m=70,u=1,s="6x12"},
["Skydance Serenade/Renegade"]={k="upgrader",m=45,u=1,s="6x12"},
["Skyliner Flux"]={k="upgrader",m=4,p=1.5874,u=3,s="6x6"},
["Smore Cake"]={k="upgrader",m=7,u=3,s="5x8"},
["Snowflake Suppressor"]={k="upgrader",m=1.25,u=1,s="3x4"},
["Snowflake Wheel"]={k="upgrader",m=6,p=1.5651,nt=1,u=1,s="4x6"},
["Snowglobe Refiner"]={k="upgrader",m=2.5,u=4,s="4x4"},
["Soapy Refiner"]={k="upgrader",m=3,p=1.4422,u=1,s="3x6"},
["Soaring Chopper"]={k="upgrader",m=4,p=1.4142,u=1,s="4x6"},
["Solar Apocalypse"]={k="upgrader",m=8,p=1.4142,u=1,s="6x10"},
["Solar Eruption"]={k="furnace",m=190,s="10x10"},
["Solar Flare"]={k="furnace",m=25,mm=50,s="6x5"},
["Solar Large Upgrader"]={k="upgrader",m=1.35,u=1,s="6x4"},
["Solarium Mine"]={k="mine",v=100000000000000,r=0.5,s="9x14"},
["Son of Poison"]={k="upgrader",m=12,mm=80,p=1.5131,u=1,s="6x10"},
["Soul Blossom"]={k="furnace",m=0,mm=1,u=1,s="5x6"},
["Spaghetti & Meatballs"]={k="upgrader",m=75,u=1,s="5x8"},
["Sparking Boba"]={k="upgrader",m=22,u=1,s="5x6"},
["Spector of Christmas Present"]={k="upgrader",m=3,u=1,s="2x2"},
["Spectral Purgatory"]={k="upgrader",m=6,p=1.431,u=1,s="5x8"},
["Spectral Research Center"]={k="furnace",m=1,s="4x6"},
["Spectral Upgrader"]={k="upgrader",m=2,u=1,s="1x5"},
["Speggtral Rose"]={k="upgrader",m=8,p=1.3831,u=1,s="6x10"},
["Sphinx of Luxor"]={k="upgrader",m=0.2,mm=8,p=1.5157,u=1,s="5x8"},
["Spider Queen"]={k="upgrader",m=1.75,u=1,s="4x5"},
["Spinnerite Mine"]={k="mine",v=500,r=0.3333333333,s="3x2"},
["Spires of Conquest"]={k="upgrader",m=20,mm=25,p=1.2009,u=1,s="6x14"},
["Spirit of Fire"]={k="upgrader",m=10,p=1.4678,u=1,s="6x8"},
["Spitfire Iron Mine"]={k="mine",v=2,r=3,s="3x2"},
["SpookApocalypse-Î©"]={k="mine",v=1e+20,r=4,s="12x16"},
["SpookBaron-360,000"]={k="mine",v=500000000,s="8x8"},
["SpookDemon-66,666"]={k="upgrader",m=2,u=5,s="6x5"},
["SpookLord-95,000"]={k="upgrader",m=3,u=1,s="5x5"},
["SpookPhantasm-EX"]={k="mine",v=400000000000,r=0.6666666667,s="12x9"},
["SpookStorm-X"]={k="mine",v=1000000,r=0.5,s="7x11"},
["Spookboy-500"]={k="mine",v=1000000,s="4x4"},
["Spooklord Device"]={k="upgrader",m=7,p=1.3205,u=1,s="6x7"},
["Spookmaster-5000"]={k="mine",v=950000000,r=3.333333333,s="4x4"},
["Spooktastic Refiner"]={k="upgrader",m=1.9,u=1,s="4x4"},
["Spooky Coal Mine"]={k="mine",v=0,r=1,s="2x2"},
["Spooky Fruit Punch Processor"]={k="furnace",m=1,s="6x4"},
["Spooky Research Center"]={k="furnace",m=3,s="4x4"},
["Spooky Schrodinger"]={k="upgrader",m=2,mm=10,u=1,s="4x4"},
["Sporegg Hut"]={k="upgrader",m=4.5,p=1.351,u=1,s="5x6"},
["Stardust Illuminator"]={k="upgrader",m=66,nt=1,u=1,s="6x6"},
["Stardust Pulsar"]={k="upgrader",m=35,nt=1,u=1,s="4x4"},
["Statue of Knowledge"]={k="upgrader",m=2.5,u=1,s="2x2"},
["Steel Refinery"]={k="upgrader",u=-1,s="4x6"},
["Stellar Bombardment"]={k="upgrader",m=2,mm=6,p=1.4358,u=1,s="5x12"},
["Stellarite Mine"]={k="mine",v=1000000000000,r=3.03030303,s="4x6"},
["Stratospheric Refiner"]={k="upgrader",m=4,p=1.4142,u=1,s="4x6"},
["Strawberry Cake"]={k="upgrader",m=10,p=1.4678,u=1,s="6x6"},
["Sugar Corroder"]={k="upgrader",m=1.7,p=1.1419,u=1,s="4x6"},
["Suitopian Refiner"]={k="upgrader",m=0,mm=10,u=10,s="6x8"},
["Suitopian Refiner/Renegade"]={k="upgrader",m=0,mm=10,u=10,s="6x8"},
["Sun Mask"]={k="upgrader",m=8,u=1,s="4x8"},
["Super Schrodinger"]={k="upgrader",m=4,mm=20,d=0.25,x=1,u=-1,s="6x6"},
["Super Swintite Mine"]={k="mine",v=2500000,r=0.6666666667,s="7x9"},
["Superunobtainium Mine"]={k="mine",v=30000,s="4x4"},
["Supreme Birthday Cake"]={k="furnace",m=70,mm=700,s="11x12"},
["Supreme Christmas Tree"]={k="furnace",m=50,mm=5000,s="11x12"},
["Suspended Lava Refiner"]={k="upgrader",m=1.4,u=-1,s="6x4"},
["Suspended Refiner"]={k="upgrader",m=1.7,u=-1,s="6x4"},
["Swag City"]={k="upgrader",m=4.5,mm=185.193,p=2.3875,u=1,s="6x8"},
["Swag Iron Mine"]={k="mine",v=2,r=0.5,s="3x2"},
["Sweet Tooth"]={k="furnace",m=25,s="5x8"},
["Swift Justice"]={k="furnace",m=5000000000,s="8x5"},
["Swintite Mine"]={k="mine",v=300,s="3x3"},
["Sword Master's Spirit"]={k="furnace",m=75,s="10x6"},
["Symcorpium Mine"]={k="mine",v=250000000000000,r=1,s="6x4"},
["Symmetrium Mine"]={k="mine",v=100000000,s="5x4"},
["Symmetryte Mine"]={k="mine",v=100000000000,r=1,s="6x8"},
["THE DECADE"]={k="upgrader",m=5,mm=11.66,u=1,s="5x6"},
["THE UNDERTAKER"]={k="furnace",m=1.00666,s="6x5"},
["Tankium Mine"]={k="mine",v=4000000,s="7x8"},
["Tea Eggle Gardens"]={k="upgrader",m=4,p=1.4142,u=1,s="4x8"},
["Teddy Bear Stuffer"]={k="upgrader",nt=1,u=1,s="4x6"},
["Tempest Refiner"]={k="upgrader",m=6,mm=10,x=1,u=-1,s="6x7"},
["Temporal Armageddon"]={k="upgrader",m=35,mm=48,p=2.4495,u=1,s="4x6"},
["Temporal Enchantment"]={k="furnace",m=900,s="12x9"},
["Tesla Refuter"]={k="upgrader",m=1,mm=10,t=1,nt=1,u=1,s="5x6"},
["Tesla Resetter"]={k="upgrader",t=1,nt=1,u=1,s="6x8"},
["Test Upgrader"]={k="upgrader",u=1,s="2x2"},
["The Abomination"]={k="mine",v=10000000,r=2.25,s="5x8"},
["The Baron"]={k="upgrader",m=6.5,p=1.2636,u=1,s="8x12"},
["The Beehive"]={k="upgrader",m=3.5,p=1.8708,u=1,s="2x4"},
["The Black Hole"]={k="furnace",m=50,s="6x6"},
["The Boy"]={k="upgrader",m=1.75,u=1,s="4x4"},
["The Catalyst"]={k="upgrader",m=4,p=1.2599,u=1,s="6x4"},
["The Chaosrealm"]={k="upgrader",m=7,mm=11,p=1.4422,u=1,s="6x10"},
["The Cherry Pie"]={k="upgrader",m=1.8,mm=3.6,u=3,s="7x10"},
["The Cookinator"]={k="upgrader",m=1.3,p=1.1402,u=1,s="2x6"},
["The Cornucopia"]={k="upgrader",m=10,p=2.885,u=1,s="6x10"},
["The Cosmic Tower"]={k="upgrader",m=35,nt=1,u=1,s="8x8"},
["The Crazy Hamburger"]={k="upgrader",m=2,p=1.1487,u=1,s="5x8"},
["The Cryolyst"]={k="upgrader",m=4,u=1,s="6x4"},
["The Daegelart"]={k="mine",v=420000000000000,r=1,s="8x11"},
["The Darkest Upgrader"]={k="upgrader",m=5,u=1,s="3x3"},
["The Death Cap"]={k="upgrader",m=130,p=1.8859,u=1,s="8x10"},
["The Demon"]={k="upgrader",m=6,p=1.3912,u=1,s="6x10"},
["The Dream-Maker"]={k="furnace",m=15,s="4x6"},
["The Dust Devil"]={k="upgrader",m=0.6,mm=10,p=1.3774,u=1,s="4x6"},
["The Easter Shrine"]={k="furnace",m=125,s="10x6"},
["The Egg Portal"]={k="upgrader",m=10,mm=16,u=1,s="5x10"},
["The Eternal Overseer"]={k="upgrader",m=15,nt=1,u=1,s="9x10"},
["The Final Upgrader"]={k="upgrader",m=50,mm=1000,t=1,nt=1,u=1,s="7x12"},
["The Fissure"]={k="furnace",m=1250000000,s="15x9"},
["The Fracture"]={k="furnace",m=300000000,s="10x7"},
["The Grand Prism"]={k="upgrader",m=100,u=1,s="6x8"},
["The Grand Prism/Renegade"]={k="upgrader",m=25,u=1,s="6x8"},
["The Great Parasite"]={k="furnace",m=7000000000,mm=350000000000000,s="6x5"},
["The Great Parasite/Renegade"]={k="furnace",m=7000000000,mm=350000000000000,s="6x5"},
["The Guillotine"]={k="upgrader",m=15,mm=45,p=1.2457,u=1,s="5x8"},
["The Haunted House"]={k="upgrader",m=8.71,u=1,s="6x10"},
["The Heart of Void"]={k="furnace",m=66666,u=1,s="7x10"},
["The Heartbreaker"]={k="upgrader",m=2.5,p=1.2573,u=5,s="4x8"},
["The Holy Cheese"]={k="upgrader",m=4,p=1.5874,u=1,s="3x6"},
["The Hourglass"]={k="upgrader",m=90,p=2.0314,u=1,s="8x12"},
["The Ice Fortress"]={k="upgrader",m=4.5,p=1.2397,u=1,s="7x10"},
["The Lord"]={k="upgrader",m=4,p=1.2599,u=1,s="6x10"},
["The Master"]={k="upgrader",m=6.6,p=1.3696,u=1,s="6x8"},
["The Phantasm"]={k="upgrader",m=20,mm=25,p=1.6739,u=1,s="6x8"},
["The Pizzalyst"]={k="upgrader",m=5.06,mm=29.854,p=2.2657,u=1,s="5x4"},
["The Rock"]={k="upgrader",u=1,s="4x8"},
["The Sporest"]={k="upgrader",m=8,p=1.5157,u=1,s="5x8"},
["The Storm"]={k="upgrader",m=6,p=1.2917,u=1,s="7x10"},
["The Stormcrow"]={k="upgrader",m=10,mm=19,p=2.1544,u=1,s="3x9"},
["The Sunken Past"]={k="furnace",m=20,mm=30,s="6x10"},
["The Trinity"]={k="upgrader",m=65,mm=125,p=2.0052,u=1,s="6x10"},
["The Ultimate Sacrifice"]={k="upgrader",m=2.5,mm=50,t=1,nt=1,u=1,s="8x10"},
["The Vault"]={k="furnace",s="6x8"},
["The Void Ritual"]={k="upgrader",m=6,p=1.2599,u=1,s="6x10"},
["Thingamajig"]={k="furnace",m=1.1,s="3x5"},
["Three Years Upgrader"]={k="upgrader",m=3,u=1,s="7x6"},
["Time-Space Scrambler"]={k="upgrader",m=5,p=1.71,u=1,s="3x3"},
["Timeless Enhancement"]={k="furnace",m=80,s="6x5"},
["Tiny Iron Mine"]={k="mine",v=100000,r=1,s="30x20"},
["Tortoise Fortifier"]={k="upgrader",m=25,p=7.609,u=-1,s="8x10"},
["Toxic Schrodinger Evaluator"]={k="upgrader",m=2.1,mm=8,d=0.1667,x=1,u=3,s="3x3"},
["Toxic Waste Disposal"]={k="upgrader",m=3,mm=6,u=1,s="4x8"},
["Transylvanian Refiner"]={k="upgrader",m=2.5,mm=6.25,p=1.3572,u=1,s="6x8"},
["Tree of Giving"]={k="upgrader",m=5,u=1,s="8x6"},
["Triple Coal Mine"]={k="mine",v=0,r=0.75,s="2x2"},
["Trollium Mine"]={k="mine",v=300000000,r=30,s="4x4"},
["Tropical Breeze"]={k="upgrader",m=6,p=2.4495,u=1,s="2x6"},
["Tropical Holidays"]={k="upgrader",m=2,u=1,s="3x5"},
["True Overlord Device"]={k="upgrader",m=100,p=1.9307,u=1,s="7x6"},
["Tsar Bomba"]={k="upgrader",m=50,p=1.6307,u=3,s="6x8"},
["Turbine Chamber"]={k="upgrader",m=21,p=1.661,u=1,s="6x8"},
["Turtle Dignifier"]={k="upgrader",m=8,u=1,s="5x6"},
["Twitch Scanner"]={k="upgrader",m=5,p=2.2361,u=1,s="2x4"},
["Twitch-Powered Upgrader"]={k="upgrader",m=1.6,u=1,s="4x4"},
["Twitchite Mine"]={k="mine",v=10000000,r=1.428571429,s="6x6"},
["Tyrant's Forge"]={k="furnace",m=1,s="10x8"},
["Tyrant's Throne"]={k="furnace",m=85000,mm=85000,s="10x8"},
["Undead Assistance"]={k="upgrader",m=1.5,p=1.2247,u=6,s="2x3"},
["Universal Collapse"]={k="upgrader",m=35,mm=48,p=1.9064,u=1,s="6x8"},
["Unobtainium Mine"]={k="mine",r=0.5,s="3x2"},
["Uranium Mine"]={k="mine",v=3000,r=0.3333333333,s="3x4"},
["Utopian Refiner"]={k="upgrader",m=50,u=1,s="8x6"},
["Utopian Refiner/Renegade"]={k="upgrader",m=8,u=1,s="6x8"},
["V-tolite Mine"]={k="mine",v=2000000000000,r=1.428571429,s="11x14"},
["Vampire Spore"]={k="upgrader",m=14,mm=15,p=1.8212,u=1,s="4x4"},
["Vanilla Scanner"]={k="upgrader",m=3,p=1.7321,u=1,s="2x6"},
["Vaporwave Vibe Visualizer"]={k="upgrader",m=7,u=1,s="4x6"},
["Verdant Pincher"]={k="upgrader",m=10,u=1,s="3x3"},
["Vesterian Upgrader"]={k="upgrader",m=6,u=1,s="5x8"},
["Video Game Digitalizer"]={k="upgrader",m=1,u=-1,s="6x4"},
["Virtual Enchanter"]={k="upgrader",m=1,mm=45,p=2.1411,u=-1,s="8x5"},
["Virtual Enhancer"]={k="upgrader",m=1,mm=30,p=1.9744,u=1,s="5x6"},
["Virtual Gearwork"]={k="upgrader",m=1,p=1.7826,u=1,s="5x10"},
["Vitamin C-Coater"]={k="upgrader",m=6,p=1.5651,u=1,s="4x8"},
["Void Drive"]={k="upgrader",m=100,nt=1,u=1,s="8x14"},
["Void Star"]={k="upgrader",m=1,mm=1000,t=1,nt=1,u=1,s="8x12"},
["Volcango"]={k="furnace",m=500,s="4x4"},
["Vortex Chamber"]={k="upgrader",m=5,p=1.4953,u=1,s="4x6"},
["Vortex Singularity"]={k="upgrader",m=9,u=1,s="5x8"},
["Vulcan's Destiny"]={k="upgrader",m=1,p=2.2209,nt=1,u=1,s="6x12"},
["Vulcan's Grasp"]={k="upgrader",m=2,p=1.9786,nt=1,u=1,s="6x10"},
["Vulcan's Wrath"]={k="upgrader",m=65,mm=165,p=2.5873,u=1,s="6x8"},
["Vulcanus Wyvern"]={k="upgrader",m=5,p=1.3797,u=1,s="5x10"},
["Walrus Blaster"]={k="upgrader",m=5,u=1,s="6x5"},
["Way-Up-High Cake Pop"]={k="upgrader",m=1.5,u=3,s="5x3"},
["Way-Up-High Upgrader"]={k="upgrader",m=1,mm=1.8,u=-1,s="2x2"},
["Wedding Cake"]={k="upgrader",m=8,p=1.2968,u=1,s="8x10"},
["Whimsical Turbine"]={k="upgrader",m=50,mm=90,p=2.1169,u=1,s="8x6"},
["Wholesome Skull Blaster"]={k="upgrader",m=6,mm=12,p=1.2917,u=1,s="7x8"},
["Widow's Outpost"]={k="upgrader",m=4,p=1.4142,u=1,s="4x10"},
["Wild Spore"]={k="upgrader",m=5,mm=6,u=1,s="4x6"},
["Winter Snowflake"]={k="upgrader",m=4.75,p=1.71,u=1,s="3x3"},
["Winter Wonderworld"]={k="upgrader",m=5,mm=10,u=1,s="5x10"},
["Winterheart"]={k="upgrader",m=3,p=1.3161,u=1,s="3x4"},
["Witch's Cauldron"]={k="upgrader",m=15,u=-1,s="6x7"},
["Wubium Mine"]={k="mine",v=300000000,r=30,s="4x4"},
["Yuge Furnace"]={k="furnace",m=10,s="1x1"},
["Yuge Iron Mine"]={k="mine",v=1000,r=0.5,s="1x1"},
["Yunium Mine"]={k="mine",v=25000000,s="3x2"},
["Yuntonium Mine"]={k="mine",v=1000000000000,r=1.666666667,s="9x4"},
["Yuttrium Mine"]={k="mine",v=1000000000000,r=4,s="7x5"}
}

do
    for name, r in pairs(DB_MACHINES) do
        if r.k == "mine" then
            local t = MINES[name] or {}
            t.kind = "mine"
            if r.v then t.oreValue = r.v end
            if r.r then t.rate = r.r end
            if r.s then t.size = r.s end
            MINES[name] = t
        elseif r.k == "furnace" then
            local t = FURNACE_DB[name] or {}
            t.Type = t.Type or "Standard"
            t.CashMult = r.m or t.CashMult or 1
            if r.mm then t.CashMultMax = r.mm end
            t.SellPart = t.SellPart or "Lava"
            FURNACE_DB[name] = t
        else
            local t = UPGRADER_DB[name] or {}
            if r.m and not t.Multiplier then t.Multiplier = r.m end
            if r.p then t.MPU = r.p end
            if r.d then t.DestroyChance = r.d end
            if r.e then t.Education = r.e end
            if r.t then t.IsTesla = true; t.IsResetter = true end
            if r.nt then t.NoTesla = true end
            if r.u and not t.MaxUses then t.MaxUses = r.u end
            UPGRADER_DB[name] = t
        end
    end
end

UI:Finalize()
print("")
print("  ██████╗ ███████╗███████╗██████╗ ██╗   ██╗███████╗██╗███╗   ██╗")
print("  ██╔══██╗██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██║████╗  ██║")
print("  ██║  ██║█████╗  █████╗  ██████╔╝██║   ██║█████╗  ██║██╔██╗ ██║")
print("  ██║  ██║██╔══╝  ██╔══╝  ██╔═══╝ ╚██╗ ██╔╝██╔══╝  ██║██║╚██╗██║")
print("  ██████╔╝███████╗███████╗██║      ╚████╔╝ ███████╗██║██║ ╚████║")
print("  ╚═════╝ ╚══════╝╚══════╝╚═╝       ╚═══╝  ╚══════╝╚═╝╚═╝  ╚═══╝")
print("")
print("  Miner's Haven   ·   v1.0   ·   Halcyon")
print("  ─────────────────────────────────────────────────────────────")
print("  RightShift  toggle window")
print("  Automation  Print Route for a per-ore value simulation")
print("  FPS         measured visual cutbacks, all revertible")
print("")

_G.DV = {
    route = printRoute,
    effects = printEffectPlan,
    audit = printItemAudit,
    menu = openMenu,
    closeMenus = closeAllMenus,
    erebus = fireDataReset,
    withdraw = doWithdrawAll,
    item = MHItem,
    resolve = resolveName,
    strip = stripShiny,
    sample = sampleOreValue,
    detect = detectUpgraders,
    snapshot = getSnapshot,
    factory = getMyFactory,
    state = State,
    lodOn = enableLOD,
    lodOff = disableLOD,
    layoutPlan = LC_LayoutPlan,
    missing = LC_GetMissingItems,
    price = LC_GetPrice,
    craftPlan = CRAFT_Plan,
    craftRun = craftUntilCrafted,
    craftNames = CRAFT_Names,
    dialog = DV_Dialog,
    owned = LC_Owned,
}

_G.DeepveinKill = function()
    State.oreBooster, State.cellFurnaceMode = false, false
    State.autoRemote, State.autoBoxes, State.autoOpenBoxes = false, false, false
    State.autoRebirth, State.firecystalFeed, State.autoLoadLayout2 = false, false, false
    pcall(stopOreDiscovery)
    pcall(stopCellDiscovery)
    for _, c in ipairs(FxSnap.conns) do pcall(function() c:Disconnect() end) end
    -- the old webhook listeners can't be disconnected from here, so mute them
    WebhookState.url = ""
    WebhookState.pingOnRebirth, WebhookState.pingOnLife, WebhookState.pingOnItem = false, false, false
    pcall(stopNukeMode)
    pcall(stopUltraMode)
    pcall(stopOreHide)
    pcall(enableParticles)
    pcall(enableShadows)
    pcall(unmuteSounds)
    pcall(disableLOD)
    if DVGui then pcall(function() DVGui:Destroy() end) end
    for _, m in ipairs({ "Destroy", "Unload", "Close" }) do
        if type(Halcyon[m]) == "function" then
            pcall(Halcyon[m], Halcyon)
            break
        end
    end
end

UI:Notify({ Title = "Ready", Content = "Deepvein loaded.", Type = "Success", Duration = 5 })
