-- IllWill - Death Wish tracker for Turtle WoW (Vanilla 1.12)
-- Tracks raid warriors: READY (green), ACTIVE (yellow), COOLDOWN timer (red), plus usage count.

IllWill = {}
local IW = IllWill

local ADDON_NAME = "IllWill"

-- Death Wish timings (user described 30s active, 3 min cooldown)
local DW_ACTIVE = 30
local DW_COOLDOWN = 180

-- Icon texture match (Vanilla Death Wish commonly uses Spell_Shadow_DeathPact)
-- We match case-insensitively on substring to be robust to full paths.
local DW_ICON_SUBSTR_1 = "spell_shadow_deathpact"
-- Extra fallback substrings if needed (harmless to include)
local DW_ICON_SUBSTR_2 = "deathpact"
local DW_ICON_SUBSTR_3 = "death_wish"
local DW_ICON_SUBSTR_4 = "deathwish"

-- Update throttles
local SCAN_INTERVAL = 0.20
local ROSTER_REBUILD_INTERVAL = 3.00

-- Colors
local C_READY   = { 0.2, 1.0, 0.2 }   -- green
local C_ACTIVE  = { 1.0, 0.85, 0.2 }  -- yellow
local C_CD      = { 1.0, 0.25, 0.25 } -- red
local C_UNKNOWN = { 0.7, 0.7, 0.7 }   -- gray
local C_OFFLINE = { 0.6, 0.6, 0.6 }   -- gray

-- Localization-safe Warrior name (Vanilla provides these tables on most clients)
local WARRIOR_LOCAL = "Warrior"
if LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE["WARRIOR"] then
  WARRIOR_LOCAL = LOCALIZED_CLASS_NAMES_MALE["WARRIOR"]
end

-- SavedVariables defaults
local function ApplyDefaults()
  if not IllWillDB then IllWillDB = {} end
  if IllWillDB.locked == nil then IllWillDB.locked = false end
  if IllWillDB.scale == nil then IllWillDB.scale = 1.0 end
  if IllWillDB.assumeReady == nil then IllWillDB.assumeReady = true end -- if never seen, show READY by default
  if IllWillDB.sort == nil then IllWillDB.sort = "status" end           -- "status" or "name"
  if IllWillDB.showOffline == nil then IllWillDB.showOffline = true end
  if IllWillDB.pos == nil then
    IllWillDB.pos = { x = 450, y = 450 }
  end
end

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. ADDON_NAME .. "|r: " .. msg)
end

local function Clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function FormatTime(sec)
  if not sec then sec = 0 end
  if sec < 0 then sec = 0 end
  sec = math.floor(sec + 0.5)
  local m = math.floor(sec / 60)
  local s = sec - (m * 60)
  if s < 10 then
    return m .. ":0" .. s
  end
  return m .. ":" .. s
end

local function Lower(s)
  if not s then return "" end
  return string.lower(s)
end

-- Scan buffs/debuffs for a matching texture
local function UnitHasDeathWish(unit)
  local i
  for i = 1, 16 do
    local tex = UnitDebuff(unit, i)
    if not tex then break end
    local t = Lower(tex)
    if string.find(t, DW_ICON_SUBSTR_1) or string.find(t, DW_ICON_SUBSTR_2)
      or string.find(t, DW_ICON_SUBSTR_3) or string.find(t, DW_ICON_SUBSTR_4) then
      return true
    end
  end
  for i = 1, 16 do
    local tex = UnitBuff(unit, i)
    if not tex then break end
    local t = Lower(tex)
    if string.find(t, DW_ICON_SUBSTR_1) or string.find(t, DW_ICON_SUBSTR_2)
      or string.find(t, DW_ICON_SUBSTR_3) or string.find(t, DW_ICON_SUBSTR_4) then
      return true
    end
  end
  return false
end

-- State ranking for sorting
local function GetStateRank(state)
  if state == "ACTIVE" then return 1 end
  if state == "COOLDOWN" then return 2 end
  if state == "READY" then return 3 end
  if state == "UNKNOWN" then return 4 end
  if state == "OFFLINE" then return 5 end
  return 9
end

-- Data stores
IW.warriors = {} -- [name] = { uses, lastCast, cdUntil, activeUntil, active, seen, offline }
IW.order = {}    -- sorted names to render

-- UI
IW.frame = nil
IW.rows = {}
IW.maxRows = 40

local function MakeBackdrop(f)
  if not f.SetBackdrop then return end
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  f:SetBackdropColor(0, 0, 0, 0.65)
  f:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.9)
end

local function SavePosition()
  if not IW.frame then return end
  local x = IW.frame:GetLeft()
  local y = IW.frame:GetBottom()
  if x and y then
    IllWillDB.pos.x = x
    IllWillDB.pos.y = y
  end
end

local function RestorePosition()
  if not IW.frame then return end
  IW.frame:ClearAllPoints()
  IW.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", IllWillDB.pos.x or 400, IllWillDB.pos.y or 400)
end

local function SetLocked(locked)
  IllWillDB.locked = locked and true or false
  if IllWillDB.locked then
    IW.frame:EnableMouse(false)
    Print("Locked.")
  else
    IW.frame:EnableMouse(true)
    Print("Unlocked. Drag to move.")
  end
end

local function SetScale(scale)
  scale = tonumber(scale or 1.0) or 1.0
  scale = Clamp(scale, 0.6, 2.0)
  IllWillDB.scale = scale
  IW.frame:SetScale(scale)
  Print("Scale set to " .. scale)
end

local function SetSort(mode)
  mode = string.lower(mode or "")
  if mode == "name" or mode == "status" then
    IllWillDB.sort = mode
    Print("Sort set to " .. mode)
  else
    Print("Sort options: name | status")
  end
end

local function ResetAll()
  IW.warriors = {}
  IW.order = {}
  Print("Reset counts + timers.")
end

local function EnsureRow(i, parent, y)
  if IW.rows[i] then return IW.rows[i] end

  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(14)
  row:SetWidth(parent:GetWidth() - 14)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 7, y)

  row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.count:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.count:SetJustifyH("LEFT")
  row.count:SetWidth(22)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.name:SetPoint("LEFT", row, "LEFT", 26, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWidth(140)

  row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.status:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.status:SetJustifyH("RIGHT")
  row.status:SetWidth(90)

  IW.rows[i] = row
  return row
end

local function BuildFrame()
  local f = CreateFrame("Frame", "IllWillFrame", UIParent)
  IW.frame = f
  f:SetWidth(270)
  f:SetHeight(22 + (IW.maxRows * 14) + 8)
  MakeBackdrop(f)

  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function()
    if IllWillDB.locked then return end
    f:StartMoving()
  end)
  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    SavePosition()
  end)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
  title:SetText("IllWill - Death Wish")

  local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  subtitle:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -22)
  subtitle:SetText("Count  Name                          Status")

  -- Create rows lazily in UpdateDisplay

  RestorePosition()
  f:SetScale(IllWillDB.scale or 1.0)

  if IllWillDB.locked then
    f:EnableMouse(false)
  end

  f:Show()
end

-- Determine group units list
local function ForEachGroupUnit(callback)
  local nRaid = GetNumRaidMembers()
  if nRaid and nRaid > 0 then
    local i
    for i = 1, nRaid do
      callback("raid" .. i)
    end
    return
  end

  local nParty = GetNumPartyMembers()
  if nParty and nParty > 0 then
    callback("player")
    local i
    for i = 1, nParty do
      callback("party" .. i)
    end
    return
  end

  callback("player")
end

-- Gather/update warriors and detect transitions
function IW:Scan()
  local now = GetTime()

  local seen = {}
  local names = {}

  ForEachGroupUnit(function(unit)
    if UnitExists(unit) then
      local class = UnitClass(unit)
      if class == WARRIOR_LOCAL then
        local name = UnitName(unit)
        if name and name ~= "" then
          local w = IW.warriors[name]
          if not w then
            w = { uses = 0, seen = false, active = false, offline = false, cdUntil = 0, activeUntil = 0 }
            IW.warriors[name] = w
          end

          w.unit = unit
          w.present = true
          w.offline = (UnitIsConnected(unit) == nil) or (UnitIsConnected(unit) == false)

          seen[name] = true
          table.insert(names, name)

          -- Offline handling: keep them but mark status
          if w.offline then
            -- no aura scan (optional)
            return
          end

          local hasDW = UnitHasDeathWish(unit)

          -- Transition: not active -> active
          if hasDW and not w.active then
            w.active = true
            w.seen = true
            w.uses = (w.uses or 0) + 1
            w.lastCast = now
            w.activeUntil = now + DW_ACTIVE
            w.cdUntil = now + DW_COOLDOWN
          end

          -- Still active
          if hasDW then
            w.active = true
            -- refresh activeUntil if we somehow missed the first detection
            if not w.activeUntil or w.activeUntil < now then
              w.activeUntil = now + DW_ACTIVE
            end
          else
            -- Not currently detected active
            if w.active and w.activeUntil and now > w.activeUntil + 0.5 then
              w.active = false
            end
          end
        end
      end
    end
  end)

  -- mark missing
  for name, w in pairs(IW.warriors) do
    if not seen[name] then
      w.present = false
      w.unit = nil
    end
  end

  IW.order = names
end

local function GetDisplayState(w, now)
  if w.offline then
    return "OFFLINE"
  end

  if w.active and w.activeUntil and (now < w.activeUntil) then
    return "ACTIVE"
  end

  if w.cdUntil and (now < w.cdUntil) then
    return "COOLDOWN"
  end

  if w.seen then
    return "READY"
  end

  if IllWillDB.assumeReady then
    return "READY"
  end

  return "UNKNOWN"
end

function IW:SortOrder()
  local now = GetTime()
  if not IW.order then return end

  if IllWillDB.sort == "name" then
    table.sort(IW.order, function(a, b)
      return string.lower(a) < string.lower(b)
    end)
  else
    table.sort(IW.order, function(a, b)
      local wa = IW.warriors[a]
      local wb = IW.warriors[b]
      if not wa or not wb then
        return string.lower(a) < string.lower(b)
      end
      local sa = GetDisplayState(wa, now)
      local sb = GetDisplayState(wb, now)
      local ra = GetStateRank(sa)
      local rb = GetStateRank(sb)
      if ra ~= rb then
        return ra < rb
      end
      return string.lower(a) < string.lower(b)
    end)
  end
end

function IW:UpdateDisplay()
  if not IW.frame or not IW.frame:IsShown() then return end

  local now = GetTime()
  IW:SortOrder()

  local shown = 0
  local i

  for i = 1, IW.maxRows do
    local row = EnsureRow(i, IW.frame, -36 - ((i - 1) * 14))
    row:Hide()
  end

  for i = 1, #IW.order do
    local name = IW.order[i]
    local w = IW.warriors[name]
    if w then
      if (not w.offline) or IllWillDB.showOffline then
        shown = shown + 1
        if shown > IW.maxRows then break end

        local row = EnsureRow(shown, IW.frame, -36 - ((shown - 1) * 14))
        row:Show()

        row.count:SetText(tostring(w.uses or 0))
        row.name:SetText(name)

        local state = GetDisplayState(w, now)

        if state == "ACTIVE" then
          local left = (w.activeUntil or now) - now
          row.status:SetText("ACTIVE " .. FormatTime(left))
          row.status:SetTextColor(C_ACTIVE[1], C_ACTIVE[2], C_ACTIVE[3])
        elseif state == "COOLDOWN" then
          local left = (w.cdUntil or now) - now
          row.status:SetText(FormatTime(left))
          row.status:SetTextColor(C_CD[1], C_CD[2], C_CD[3])
        elseif state == "READY" then
          row.status:SetText("READY")
          row.status:SetTextColor(C_READY[1], C_READY[2], C_READY[3])
        elseif state == "OFFLINE" then
          row.status:SetText("OFFLINE")
          row.status:SetTextColor(C_OFFLINE[1], C_OFFLINE[2], C_OFFLINE[3])
        else
          row.status:SetText("??")
          row.status:SetTextColor(C_UNKNOWN[1], C_UNKNOWN[2], C_UNKNOWN[3])
        end
      end
    end
  end
end

-- Engine OnUpdate throttling
IW._scanElapsed = 0
IW._rosterElapsed = 0

local function OnUpdate(self, elapsed)
  if not IW.frame or not IW.frame:IsShown() then return end

  IW._scanElapsed = IW._scanElapsed + elapsed
  IW._rosterElapsed = IW._rosterElapsed + elapsed

  if IW._rosterElapsed >= ROSTER_REBUILD_INTERVAL then
    IW._rosterElapsed = 0
    -- rebuild order list and unit bindings
    IW:Scan()
  end

  if IW._scanElapsed >= SCAN_INTERVAL then
    IW._scanElapsed = 0
    -- quick scan + display refresh
    IW:Scan()
    IW:UpdateDisplay()
  end
end

-- Slash commands
local function ShowHelp()
  Print("Commands:")
  Print("/iw toggle | show | hide")
  Print("/iw lock | unlock")
  Print("/iw reset  (clears counts/timers)")
  Print("/iw assume ready | unknown  (what to show before first seen cast)")
  Print("/iw sort status | name")
  Print("/iw scale <0.6-2.0>")
  Print("/iw offline on | off")
end

local function HandleSlash(msg)
  msg = msg or ""
  msg = string.gsub(msg, "^%s+", "")
  msg = string.gsub(msg, "%s+$", "")
  local cmd, rest = msg, ""
  local sp = string.find(msg, "%s")
  if sp then
    cmd = string.sub(msg, 1, sp - 1)
    rest = string.sub(msg, sp + 1)
  end
  cmd = string.lower(cmd or "")

  if cmd == "" or cmd == "help" then
    ShowHelp()
    return
  end

  if cmd == "toggle" then
    if IW.frame:IsShown() then IW.frame:Hide() else IW.frame:Show() end
    return
  end
  if cmd == "show" then IW.frame:Show() return end
  if cmd == "hide" then IW.frame:Hide() return end

  if cmd == "lock" then SetLocked(true) return end
  if cmd == "unlock" then SetLocked(false) return end

  if cmd == "reset" then
    ResetAll()
    IW:Scan()
    IW:UpdateDisplay()
    return
  end

  if cmd == "assume" then
    rest = string.lower(rest or "")
    if rest == "ready" then
      IllWillDB.assumeReady = true
      Print("Assume-ready mode: ON (unknowns show READY).")
    elseif rest == "unknown" then
      IllWillDB.assumeReady = false
      Print("Assume-ready mode: OFF (unknowns show ?? until first DW seen).")
    else
      Print("Usage: /iw assume ready | unknown")
    end
    IW:UpdateDisplay()
    return
  end

  if cmd == "sort" then
    SetSort(rest)
    IW:UpdateDisplay()
    return
  end

  if cmd == "scale" then
    SetScale(rest)
    return
  end

  if cmd == "offline" then
    rest = string.lower(rest or "")
    if rest == "on" then
      IllWillDB.showOffline = true
      Print("Show offline warriors: ON")
    elseif rest == "off" then
      IllWillDB.showOffline = false
      Print("Show offline warriors: OFF")
    else
      Print("Usage: /iw offline on | off")
    end
    IW:UpdateDisplay()
    return
  end

  ShowHelp()
end

-- Loader frame
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("RAID_ROSTER_UPDATE")
loader:RegisterEvent("PARTY_MEMBERS_CHANGED")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")

loader:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    ApplyDefaults()
    BuildFrame()

    IW.frame:SetScript("OnUpdate", OnUpdate)

    -- Slash registration
    SLASH_ILLWILL1 = "/illwill"
    SLASH_ILLWILL2 = "/iw"
    SlashCmdList["ILLWILL"] = HandleSlash

    Print("Loaded. Use /iw for options.")
    IW:Scan()
    IW:UpdateDisplay()
    return
  end

  -- roster changes
  if IW.frame then
    IW:Scan()
    IW:UpdateDisplay()
  end
end)
