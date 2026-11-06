--[[
  AC Phone v0.2  -  iPhone-style phone for Assetto Corsa (CSP Lua app)
  by smartnajeeri, built with Claude

  Apps: Messages, Friends, Camera, Walk, Video, Chase Cam, Plates, Skins, Weather, App Library, Settings.
  Skin swapping technique adapted from Skin Companion by Ligneel; plate rendering uses CSP's shared plates module,
  network formats compatible with Hacka Plates and Skin Companion so friends using those apps stay in sync.
]]

local VERSION = '0.5'
local BUILD = 5
-- update feed for the crew (set once the GitHub repo exists)
local UPDATE_FEED = 'https://raw.githubusercontent.com/hackatuner/hackaphone-ac/main/update.json'

-- ===========================================================================
-- Utilities
-- ===========================================================================

local function has(t, k) return t ~= nil and t[k] ~= nil end
local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, speed, dt) return lerp(a, b, 1 - math.exp(-speed * dt)) end
local function easeOut(t) t = clamp(t, 0, 1) return 1 - (1 - t) ^ 3 end
local function easeInOut(t) t = clamp(t, 0, 1) return t < 0.5 and 4 * t * t * t or 1 - (-2 * t + 2) ^ 3 / 2 end

local function utf8Trim(s, maxBytes)
  s = tostring(s or '')
  if #s <= maxBytes then return s end
  local cut = maxBytes
  while cut > 0 do
    local b = s:byte(cut + 1)
    if b == nil or b < 0x80 or b >= 0xC0 then break end
    cut = cut - 1
  end
  return s:sub(1, cut)
end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

local function splitList(s)
  local t = {}
  for v in tostring(s or ''):gmatch('[^|]+') do t[#t + 1] = v end
  return t
end

local function listHas(s, v) return ('|' .. (s or '') .. '|'):find('|' .. v .. '|', 1, true) ~= nil end

local function listToggle(s, v)
  local out, found = {}, false
  for _, x in ipairs(splitList(s)) do if x == v then found = true else out[#out + 1] = x end end
  if not found then out[#out + 1] = v end
  return table.concat(out, '|')
end

local clock = os.preciseClock or os.clock

-- ===========================================================================
-- Saved settings
-- ===========================================================================

local S = ac.storage({
  status = 'Cruising',
  notifications = true,
  dnd = false,
  autoUpdate = true,
  updatedTo = '',
  updateNotes = '',
  lockScreen = true,
  hudLayouts = '{}',
  livery = '',
  liverySync = true,
  liveryShowOthers = true,
  mapFollow = true,
  mapZoom = 1.0,
  liveActivity = true,
  sounds = true,
  wallpaper = 1,
  accent = 0,          -- 0 = use the theme's colour
  theme = 1,
  themeId = 'classic',
  thick = true,
  font = 1,
  motifs = false,
  wallMode = 'theme',
  wallPath = '',
  wallDim = 0.35,
  iconStyle = 1,
  barStyle = 1,
  hiddenApps = '',
  liveryPresets = '[]',
  skinFavs = '',
  hesiOn = true,
  hesiPB = 0,
  hesiTotal = 0,
  hesiRuns = 0,
  hesiNear = 0,
  hesiCrew = '{}',
  actionBar = true,
  favorites = '',          -- favourite drivers
  pinnedApps = '',         -- app library windows pinned to home page 2
  -- chase cam
  chaseOn = false,
  chaseOnlyInChase = true,
  chaseDist = 5.2,
  chaseHeight = 1.45,
  chasePivot = 0.7,
  chaseFov = 52,
  chaseStiff = 5.0,
  chaseLookAhead = 1.5,
  chaseSpeedFov = 8,
  chaseFollowMotion = false,
  chaseTilt = 0.5,
  -- camera
  camFov = 50,
  camHideApps = true,
  -- plates
  plateData = '{}',
  plateAutoApply = true,
  plateShowOthers = true,
  plateSync = true,
  -- skins
  skinSync = true,
  skinShowOthers = true,
})

local ACCENTS = {
  { name = 'Blue',   c = rgbm(0.04, 0.52, 1.00, 1) },
  { name = 'Orange', c = rgbm(1.00, 0.58, 0.00, 1) },
  { name = 'Pink',   c = rgbm(1.00, 0.18, 0.45, 1) },
  { name = 'Green',  c = rgbm(0.20, 0.78, 0.35, 1) },
  { name = 'Purple', c = rgbm(0.69, 0.32, 0.87, 1) },
}

local WALLPAPERS = {
  { name = 'Midnight', top = rgbm(0.10, 0.12, 0.30, 1), bottom = rgbm(0.02, 0.02, 0.06, 1) },
  { name = 'Sunset',   top = rgbm(0.98, 0.45, 0.30, 1), bottom = rgbm(0.30, 0.08, 0.32, 1) },
  { name = 'Ocean',    top = rgbm(0.05, 0.55, 0.75, 1), bottom = rgbm(0.03, 0.10, 0.25, 1) },
  { name = 'Track',    top = rgbm(0.18, 0.18, 0.20, 1), bottom = rgbm(0.70, 0.08, 0.10, 1) },
  { name = 'Forest',   top = rgbm(0.20, 0.45, 0.30, 1), bottom = rgbm(0.03, 0.10, 0.06, 1) },
}

local THEME -- current theme, set by applyTheme()
local function accent() if S.accent and S.accent > 0 and ACCENTS[S.accent] then return ACCENTS[S.accent].c end return THEME and THEME.accent or ACCENTS[1].c end

-- ===========================================================================
-- Theme (iOS dark mode)
-- ===========================================================================

local T = {
  body     = rgbm(0.03, 0.03, 0.035, 1),
  frame    = rgbm(0.24, 0.24, 0.26, 1),
  bg       = rgbm(0, 0, 0, 1),
  grouped  = rgbm(0.11, 0.11, 0.12, 1),     -- secondary system grouped background
  cell     = rgbm(0.11, 0.11, 0.12, 1),
  cellHi   = rgbm(0.17, 0.17, 0.18, 1),
  fill     = rgbm(0.46, 0.46, 0.50, 0.24),  -- tertiary fill (search bars, tracks)
  sep      = rgbm(0.33, 0.33, 0.35, 0.6),
  label    = rgbm(1, 1, 1, 1),
  label2   = rgbm(0.92, 0.92, 0.96, 0.6),
  label3   = rgbm(0.92, 0.92, 0.96, 0.3),
  green    = rgbm(0.19, 0.82, 0.35, 1),
  red      = rgbm(1.00, 0.27, 0.23, 1),
  yellow   = rgbm(1.00, 0.84, 0.04, 1),
  white    = rgbm(1, 1, 1, 1),
  bubbleIn = rgbm(0.15, 0.15, 0.16, 1),
  clear    = rgbm(0, 0, 0, 0),
}

-- ===========================================================================
-- Fonts (DirectWrite system fonts, with colour emoji)
-- ===========================================================================

local FONT_FAMILIES = {
  { name = 'Modern', family = 'Segoe UI Variable Display' },
  { name = 'Classic', family = 'Segoe UI' },
  { name = 'Sport', family = 'Bahnschrift' },
}

local function makeFont(weight, key, family)
  local f = ui.DWriteFont(family or 'Segoe UI')
  if weight then f = f:weight(weight) end
  if f.allowEmoji then f = f:allowEmoji(true) end
  return { f = f, key = key }
end

local F = {}
local function buildFonts()
  local W_ = ui.DWriteFont.Weight
  local fam = (FONT_FAMILIES[S.font] or FONT_FAMILIES[1]).family
  if S.thick then
    F.r, F.m, F.sb, F.b, F.l = makeFont(W_.Medium, 'r', fam), makeFont(W_.SemiBold, 'm', fam), makeFont(W_.Bold, 'sb', fam), makeFont(W_.Black, 'b', fam), makeFont(W_.Regular, 'l', fam)
  else
    F.r, F.m, F.sb, F.b, F.l = makeFont(W_.Regular, 'r', fam), makeFont(W_.Medium, 'm', fam), makeFont(W_.SemiBold, 'sb', fam), makeFont(W_.Bold, 'b', fam), makeFont(W_.Light, 'l', fam)
  end
  -- numbers: Bahnschrift (DIN style, motorsport look)
  F.num = makeFont(W_.SemiBold, 'n', 'Bahnschrift')
  F.numb = makeFont(W_.Bold, 'nb', 'Bahnschrift')
  F.numl = makeFont(W_.Light, 'nl', 'Bahnschrift')
  local suffix = (S.thick and 'T' or '') .. (S.font or 1)
  for _, f in pairs(F) do f.key = f.key .. suffix end
end
buildFonts()

-- ===========================================================================
-- Themes: colours, wallpaper art, motif and icon style
-- ===========================================================================

local THEMES = {
  { id = 'classic', name = 'Classic', tag = 'Clean iOS dark', motif = nil, art = 'glow',
    top = rgbm(0.10, 0.12, 0.30, 1), bottom = rgbm(0.02, 0.02, 0.06, 1), bg = rgbm(0, 0, 0, 1),
    cell = rgbm(0.11, 0.11, 0.12, 1), accent = rgbm(0.04, 0.52, 1, 1), accent2 = rgbm(0.35, 0.8, 1, 1), icons = 'color' },
  { id = 'graphite', name = 'Graphite', tag = 'Monochrome · minimal', motif = nil, art = 'graphite',
    top = rgbm(0.16, 0.16, 0.17, 1), bottom = rgbm(0.02, 0.02, 0.02, 1), bg = rgbm(0.01, 0.01, 0.01, 1),
    cell = rgbm(0.10, 0.10, 0.10, 1), accent = rgbm(0.92, 0.92, 0.94, 1), accent2 = rgbm(0.6, 0.6, 0.62, 1), icons = 'color' },
  { id = 'aurora', name = 'Aurora', tag = 'Soft northern lights', motif = nil, art = 'aurora',
    top = rgbm(0.02, 0.06, 0.12, 1), bottom = rgbm(0.01, 0.02, 0.04, 1), bg = rgbm(0.01, 0.02, 0.04, 1),
    cell = rgbm(0.06, 0.09, 0.13, 1), accent = rgbm(0.30, 0.95, 0.75, 1), accent2 = rgbm(0.6, 0.4, 1, 1), icons = 'color' },
  { id = 'carbon', name = 'Carbon', tag = 'Weave · race red', motif = nil, art = 'carbon',
    top = rgbm(0.07, 0.07, 0.08, 1), bottom = rgbm(0.02, 0.02, 0.02, 1), bg = rgbm(0.02, 0.02, 0.02, 1),
    cell = rgbm(0.09, 0.09, 0.10, 1), accent = rgbm(0.95, 0.12, 0.18, 1), accent2 = rgbm(1, 1, 1, 1), icons = 'color' },
  { id = 'blood', name = 'Blood Moon', tag = 'Dark red · skulls', motif = '💀', art = 'moon',
    top = rgbm(0.28, 0.02, 0.04, 1), bottom = rgbm(0.03, 0.0, 0.01, 1), bg = rgbm(0.04, 0.0, 0.01, 1),
    cell = rgbm(0.14, 0.03, 0.04, 1), accent = rgbm(0.95, 0.10, 0.15, 1), accent2 = rgbm(1, 0.45, 0.3, 1), icons = 'tint' },
  { id = 'gold', name = 'Gold Rush', tag = 'Black & gold · gunmetal', motif = '🔫', art = 'hazard',
    top = rgbm(0.16, 0.13, 0.02, 1), bottom = rgbm(0.02, 0.02, 0.01, 1), bg = rgbm(0.03, 0.03, 0.01, 1),
    cell = rgbm(0.12, 0.11, 0.05, 1), accent = rgbm(1, 0.80, 0.05, 1), accent2 = rgbm(1, 0.95, 0.6, 1), icons = 'tint' },
  { id = 'neon', name = 'Neon Tokyo', tag = 'Synthwave grid', motif = '⚡', art = 'grid',
    top = rgbm(0.20, 0.03, 0.30, 1), bottom = rgbm(0.02, 0.01, 0.08, 1), bg = rgbm(0.03, 0.01, 0.07, 1),
    cell = rgbm(0.10, 0.05, 0.17, 1), accent = rgbm(1, 0.20, 0.75, 1), accent2 = rgbm(0.2, 0.95, 1, 1), icons = 'tint' },
  { id = 'toxic', name = 'Toxic', tag = 'Acid green · hazard', motif = '☢️', art = 'drip',
    top = rgbm(0.06, 0.20, 0.02, 1), bottom = rgbm(0.0, 0.03, 0.0, 1), bg = rgbm(0.01, 0.03, 0.01, 1),
    cell = rgbm(0.05, 0.12, 0.04, 1), accent = rgbm(0.55, 1, 0.10, 1), accent2 = rgbm(0.85, 1, 0.3, 1), icons = 'tint' },
  { id = 'inferno', name = 'Inferno', tag = 'Flames from below', motif = '🔥', art = 'flames',
    top = rgbm(0.06, 0.02, 0.02, 1), bottom = rgbm(0.45, 0.10, 0.02, 1), bg = rgbm(0.05, 0.02, 0.01, 1),
    cell = rgbm(0.15, 0.06, 0.03, 1), accent = rgbm(1, 0.45, 0.05, 1), accent2 = rgbm(1, 0.8, 0.2, 1), icons = 'tint' },
  { id = 'frost', name = 'Frostbite', tag = 'Ice blue · snow', motif = '❄️', art = 'snow',
    top = rgbm(0.30, 0.55, 0.75, 1), bottom = rgbm(0.03, 0.08, 0.18, 1), bg = rgbm(0.02, 0.05, 0.10, 1),
    cell = rgbm(0.08, 0.14, 0.22, 1), accent = rgbm(0.45, 0.85, 1, 1), accent2 = rgbm(0.9, 0.97, 1, 1), icons = 'tint' },
  { id = 'money', name = 'Cash Money', tag = 'Green bills raining', motif = '💵', art = 'rain',
    top = rgbm(0.04, 0.22, 0.10, 1), bottom = rgbm(0.01, 0.05, 0.02, 1), bg = rgbm(0.01, 0.04, 0.02, 1),
    cell = rgbm(0.05, 0.13, 0.07, 1), accent = rgbm(0.25, 0.90, 0.45, 1), accent2 = rgbm(0.85, 1, 0.6, 1), icons = 'tint' },
  { id = 'jdm', name = 'Midnight JDM', tag = 'Checkered · street', motif = '🏁', art = 'checker',
    top = rgbm(0.05, 0.08, 0.20, 1), bottom = rgbm(0.01, 0.01, 0.04, 1), bg = rgbm(0.01, 0.02, 0.05, 1),
    cell = rgbm(0.07, 0.09, 0.16, 1), accent = rgbm(0.95, 0.95, 1, 1), accent2 = rgbm(1, 0.2, 0.3, 1), icons = 'color' },
}

local function mix(a, b, t) return rgbm(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t), lerp(a.mult, b.mult, t)) end

local function applyTheme(i)
  THEME = THEMES[i] or THEMES[1]
  S.theme = i
  S.themeId = THEME.id
  local th = THEME
  T.bg = th.bg
  T.cell = th.cell
  T.grouped = th.cell
  T.cellHi = mix(th.cell, th.accent, 0.18)
  T.bubbleIn = mix(th.cell, rgbm(1, 1, 1, 1), 0.06)
  T.fill = rgbm(lerp(0.46, th.accent.r, 0.25), lerp(0.46, th.accent.g, 0.25), lerp(0.50, th.accent.b, 0.25), 0.24)
  T.border = rgbm(th.accent.r, th.accent.g, th.accent.b, 0.22)
  T.sep = rgbm(th.accent.r * 0.4 + 0.2, th.accent.g * 0.4 + 0.2, th.accent.b * 0.4 + 0.2, 0.35)
end
do
  local idx = 1
  for i, th in ipairs(THEMES) do if th.id == S.themeId then idx = i end end
  applyTheme(idx)
end

-- ===========================================================================
-- Drawing layer: every draw call goes through here so screens can be slid,
-- faded and scrolled as a whole.
-- ===========================================================================

local D = { x = 0, y = 0, a = 1 }        -- current offset (window-local px) and alpha
local SCREEN = { x = 10, y = 10, w = 352, h = 756, r = 46 } -- phone screen rect inside window

local function A(c, extra)
  local a = D.a * (extra or 1)
  if a >= 0.999 then return c end
  return rgbm(c.r, c.g, c.b, c.mult * a)
end

local function P(x, y) return vec2(D.x + x, D.y + y) end

local function rect(x1, y1, x2, y2, c, r, flags)
  ui.drawRectFilled(P(x1, y1), P(x2, y2), A(c), r or 0, flags)
end

local function rectLine(x1, y1, x2, y2, c, r, th)
  ui.drawRect(P(x1, y1), P(x2, y2), A(c), r or 0, nil, th or 1)
end

local function circle(x, y, rad, c) ui.drawCircleFilled(P(x, y), rad, A(c), 32) end
local function circleLine(x, y, rad, c, th) ui.drawCircle(P(x, y), rad, A(c), 32, th or 1) end
local function line(x1, y1, x2, y2, c, th) ui.drawLine(P(x1, y1), P(x2, y2), A(c), th or 1) end

local mcache, mcount = {}, 0
-- emoji in the UI are replaced by CSP's monochrome icon set for a clean, modern look
local ICON_MAP = {
  ['🔥'] = 'BURN', ['📯'] = 'BELL', ['💬'] = 'CHAT', ['✓'] = 'CONFIRM', ['♫'] = 'MUSIC', ['☆'] = 'STAR_EMPTY',
  ['⏱️'] = 'STOPWATCH', ['⏱'] = 'STOPWATCH', ['👥'] = 'GROUP', ['🚶'] = 'PERSON', ['🏎️'] = 'CAR_FRONT',
  ['🌫️'] = 'WEATHER_FOG', ['🌦️'] = 'WEATHER_RAIN_LIGHT', ['🌧️'] = 'WEATHER_RAIN', ['🎛️'] = 'SLIDERS', ['⚠️'] = 'WARNING',
  ['👋'] = 'BEFRIEND', ['🌐'] = 'GLOBAL', ['⭐'] = 'STAR_FULL', ['★'] = 'STAR_FULL', ['🏁'] = 'FLAG', ['📡'] = 'SATELLITE_DISH',
  ['🎨'] = 'PALETTE', ['⛅'] = 'WEATHER_FEW_CLOUDS', ['⛈️'] = 'WEATHER_STORM', ['❄️'] = 'WEATHER_SNOW', ['💨'] = 'WIND',
  ['🗺️'] = 'MAP', ['🖥️'] = 'MONITOR', ['📉'] = 'DOWN_ALT', ['📈'] = 'UP_ALT', ['🔒'] = 'PADLOCK', ['🌙'] = 'MOON',
  ['✨'] = 'PALETTE', ['📷'] = 'CAMERA', ['🎬'] = 'CLAPPERBOARD', ['🔍'] = 'SEARCH', ['👁'] = 'EYE', ['📸'] = 'CAMERA_ALT',
  ['🌤️'] = 'WEATHER_FEW_CLOUDS', ['🌨️'] = 'WEATHER_SNOW_LIGHT', ['🌡️'] = 'THERMOMETER', ['🕒'] = 'CLOCK', ['🎥'] = 'VIDEO_CAMERA',
  ['🚁'] = 'PLANE', ['🌀'] = 'WIND', ['⚙️'] = 'SETTINGS', ['🏷️'] = 'TAG', ['🔧'] = 'WRENCH', ['📊'] = 'STATS',
  ['🎚️'] = 'SLIDERS', ['📱'] = 'CELLPHONE', ['🔔'] = 'NOTIFICATIONS', ['⬆️'] = 'DOWNLOAD', ['🧩'] = 'APPS', ['💥'] = 'COLLISION',
  ['🏆'] = 'TROPHY', ['📍'] = 'LOCATION', ['🫥'] = 'HIDE', ['🚗'] = 'CAR_FRONT', ['🎲'] = 'DICE', ['👤'] = 'USER',
  ['⏳'] = 'HOURGLASS', ['☀️'] = 'WEATHER_CLEAR', ['🌥️'] = 'WEATHER_OVERCAST', ['☁️'] = 'WEATHER_OVERCAST', ['🛣️'] = 'ROAD',
  ['💧'] = 'WEATHER_DRIZZLE', ['🚦'] = 'TRAFFIC_LIGHT', ['🧭'] = 'COMPASS', ['🧑'] = 'DRIVER', ['🎡'] = 'STEERING_WHEEL',
  ['🦶'] = 'PEDALS', ['🌅'] = 'LANDSCAPE', ['⌨️'] = 'KEYBOARD', ['🔄'] = 'RESTART', ['🎯'] = 'TARGET', ['🖌️'] = 'PALETTE',
  ['🅱️'] = 'FONT', ['🚪'] = 'LEAVE', ['⛽'] = 'FUEL', ['➤'] = 'NAVIGATION', ['⌖'] = 'CROSSHAIR', ['💾'] = 'SAVE', ['📋'] = 'CLIPBOARD',
  ['⤢'] = 'MAXIMIZE', ['⟳'] = 'RESTART', ['●'] = 'RECORD', ['🌌'] = 'CONSTELLATION',
}
ICON_MAP['⤡'] = 'FULLSCREEN'

local iconSplit = {}
-- returns glyph id, rest of the string (or nil when there is no leading icon)
local function leadingIcon(s)
  local v = iconSplit[s]
  if v ~= nil then if v == false then return nil end return v[1], v[2] end
  local b = s:byte(1)
  if b == 64 then -- '@ICON_ID rest'
    local id, rest = s:match('^@([A-Z0-9_]+)%s*(.*)$')
    if id then iconSplit[s] = { id, rest } return id, rest end
  end
  if b and b >= 0xE2 then
    for len = math.min(#s, 14), 1, -1 do
      local g = ICON_MAP[s:sub(1, len)]
      if g then
        local rest = s:sub(len + 1):gsub('^[\239\184\143]*', ''):gsub('^%s+', '')
        iconSplit[s] = { g, rest }
        return g, rest
      end
    end
  end
  iconSplit[s] = false
  return nil
end

local function rawMeasure(s, size, font)
  local k = font.key .. size .. '\1' .. s
  local v = mcache[k]
  if v then return v end
  ui.pushDWriteFont(font.f)
  v = ui.measureDWriteText(s, size)
  ui.popDWriteFont()
  mcount = mcount + 1
  if mcount > 3000 then mcache, mcount = {}, 0 end
  mcache[k] = v
  return v
end

local function measure(s, size, font)
  font = font or F.r
  local g, rest = leadingIcon(s)
  if g then
    local w = size * 1.05
    if rest ~= '' then w = w + size * 0.4 + rawMeasure(rest, size, font).x end
    return vec2(w, size * 1.33)
  end
  return rawMeasure(s, size, font)
end

local function glyph(id, x, y, size, c)
  ui.drawIcon(id, P(x, y), P(x + size, y + size), A(c or T.label))
end

-- align: 0 = left (x is left edge), 0.5 = centred on x, 1 = right edge at x
local function text(s, size, x, y, c, font, align)
  s = tostring(s)
  font = font or F.r
  if align and align ~= 0 then x = x - measure(s, size, font).x * align end
  local g, rest = leadingIcon(s)
  if g then
    local gs = size * 1.05
    glyph(g, x, y + size * 0.16, gs, c)
    if rest == '' then return end
    x = x + gs + size * 0.4
    s = rest
  end
  ui.pushDWriteFont(font.f)
  ui.dwriteDrawText(s, size, P(x, y), A(c or T.label))
  ui.popDWriteFont()
end

-- text inside a box, wrapped, top-left aligned
local function textBox(s, size, x1, y1, x2, y2, c, font)
  ui.pushDWriteFont((font or F.r).f)
  ui.dwriteDrawTextClipped(tostring(s), size, P(x1, y1), P(x2, y2), ui.Alignment.Start, ui.Alignment.Start, true, A(c or T.label))
  ui.popDWriteFont()
end

local function measureWrapped(s, size, width, font)
  font = font or F.r
  local k = 'w' .. font.key .. size .. '|' .. math.floor(width) .. '\1' .. tostring(s)
  local v = mcache[k]
  if v then return v end
  ui.pushDWriteFont(font.f)
  v = ui.measureDWriteText(tostring(s), size, width)
  ui.popDWriteFont()
  mcount = mcount + 1
  mcache[k] = v
  return v
end

-- single line that gets an ellipsis when too long
local function textFit(s, size, x, y, maxW, c, font, align)
  s = tostring(s)
  font = font or F.r
  if measure(s, size, font).x > maxW then
    local cut = #s
    while cut > 1 and measure(s:sub(1, cut) .. '…', size, font).x > maxW do cut = cut - 1 end
    s = utf8Trim(s, cut) .. '…'
  end
  text(s, size, x, y, c, font, align)
end

-- iOS chevron ">"
local function chevron(x, y, c, size)
  size = size or 6
  line(x, y - size, x + size * 0.75, y, c, 2)
  line(x + size * 0.75, y, x, y + size, c, 2)
end

local function chevronLeft(x, y, c, size)
  size = size or 8
  line(x + size * 0.75, y - size, x, y, c, 2.4)
  line(x, y, x + size * 0.75, y + size, c, 2.4)
end

-- ===========================================================================
-- Input: our own hit testing and taps, so nothing looks like stock ImGui
-- ===========================================================================

local IN = {
  m = vec2(), clicked = false, down = false, released = false, wheel = 0,
  delta = vec2(), pressPos = vec2(), active = nil, dragScroll = false, dragId = nil,
  locked = false, dt = 0.016, rightDown = false, hovered = false,
}

local clipStack = {}

local function pushClip(x1, y1, x2, y2)
  local p1, p2 = P(x1, y1), P(x2, y2)
  ui.pushClipRect(p1, p2, true)
  local top = clipStack[#clipStack]
  if top then
    p1 = vec2(math.max(p1.x, top[1].x), math.max(p1.y, top[1].y))
    p2 = vec2(math.min(p2.x, top[2].x), math.min(p2.y, top[2].y))
  end
  clipStack[#clipStack + 1] = { p1, p2 }
end

local function popClip()
  ui.popClipRect()
  clipStack[#clipStack] = nil
end

local function hit(x1, y1, x2, y2)
  if not IN.hovered then return false end
  local m = IN.m
  local ax1, ay1, ax2, ay2 = D.x + x1, D.y + y1, D.x + x2, D.y + y2
  if m.x < ax1 or m.y < ay1 or m.x > ax2 or m.y > ay2 then return false end
  local c = clipStack[#clipStack]
  if c and (m.x < c[1].x or m.y < c[1].y or m.x > c[2].x or m.y > c[2].y) then return false end
  return true
end

-- returns fired, pressed
local function tap(id, x1, y1, x2, y2)
  if IN.locked then return false, false end
  local h = hit(x1, y1, x2, y2)
  if IN.clicked and h and IN.active == nil then IN.active = id end
  if IN.active ~= id or IN.dragScroll then return false, false end
  return IN.released and h, IN.down and h
end

local anims = {}
local function anim(id, target, speed)
  local v = anims[id]
  if v == nil then v = target end
  v = damp(v, target, speed or 14, IN.dt)
  if math.abs(v - target) < 0.001 then v = target end
  anims[id] = v
  return v
end

-- ===========================================================================
-- Scroll views with momentum and rubber-banding
-- ===========================================================================

local scrolls = {}

local function scrollBegin(id, top, bottom)
  local s = scrolls[id]
  if not s then s = { y = 0, v = 0, content = 0 } scrolls[id] = s end
  s.top, s.bottom = top, bottom
  local viewH = bottom - top
  local maxY = math.max(0, s.content - viewH)
  local dt = IN.dt
  if not IN.locked and hit(0, top, SCREEN.w, bottom) then
    if IN.wheel ~= 0 then s.v = s.v - IN.wheel * 1100 end
    if IN.down and not IN.dragScroll and not IN.sliderActive and math.abs(IN.m.y - IN.pressPos.y) > 6 then
      IN.dragScroll, IN.dragId = true, id
    end
  end
  if IN.dragScroll and IN.dragId == id and IN.down then
    local dy = IN.delta.y
    if s.y < 0 or s.y > maxY then dy = dy * 0.4 end
    s.y = s.y - dy
    s.v = -dy / math.max(dt, 0.001)
  else
    s.y = s.y + s.v * dt
    s.v = s.v * math.exp(-5 * dt)
    if math.abs(s.v) < 4 then s.v = 0 end
    if s.y < 0 then s.y = damp(s.y, 0, 14, dt) s.v = s.v * 0.5 end
    if s.y > maxY then s.y = damp(s.y, maxY, 14, dt) s.v = s.v * 0.5 end
  end
  pushClip(0, top, SCREEN.w, bottom)
  D.y = D.y - s.y
  return s
end

local function scrollEnd(s, contentBottom)
  D.y = D.y + s.y
  popClip()
  s.content = contentBottom - s.top
end

local function scrollToEnd(id)
  local s = scrolls[id]
  if s then s.y = math.max(0, s.content - (s.bottom - s.top)) s.v = 0 end
end

-- ===========================================================================
-- Widgets
-- ===========================================================================

local W = {}

-- Pill / rounded button. style: 'filled' | 'tinted' | 'plain' | 'gray'
function W.button(id, label, x, y, w, h, style, color)
  color = color or accent()
  local fired, pressed = tap(id, x, y, x + w, y + h)
  local p = anim(id .. '#p', pressed and 1 or 0, 30)
  local bg, fg
  if style == 'tinted' then bg, fg = rgbm(color.r, color.g, color.b, 0.18), color
  elseif style == 'plain' then bg, fg = T.clear, color
  elseif style == 'gray' then bg, fg = T.fill, T.label
  elseif style == 'danger' then bg, fg = rgbm(1, 0.27, 0.23, 0.16), T.red
  else bg, fg = color, T.white end
  if bg.mult > 0 then rect(x, y, x + w, y + h, bg, math.min(h / 2, 12)) end
  if p > 0.01 then rect(x, y, x + w, y + h, rgbm(1, 1, 1, 0.12 * p), math.min(h / 2, 12)) end
  local size = h >= 44 and 16 or 14
  text(label, size, x + w / 2, y + (h - size * 1.33) / 2, A(fg, 1 - p * 0.3), F.sb, 0.5)
  return fired
end

-- iOS switch, returns new value
function W.toggle(id, value, x, y)
  local w, h = 50, 30
  local fired = tap(id, x - 6, y - 6, x + w + 6, y + h + 6)
  if fired then value = not value end
  local t = anim(id, value and 1 or 0, 16)
  local onC = T.green
  local c = rgbm(lerp(0.22, onC.r, t), lerp(0.22, onC.g, t), lerp(0.24, onC.b, t), 1)
  rect(x, y, x + w, y + h, c, h / 2)
  local kx = lerp(x + h / 2, x + w - h / 2, t)
  circle(kx, y + h / 2 + 1, h / 2 - 2, rgbm(0, 0, 0, 0.25))
  circle(kx, y + h / 2, h / 2 - 2, T.white)
  return value, fired
end

-- slider, returns new value and whether it changed
function W.slider(id, value, minV, maxV, x, y, w, color)
  color = color or accent()
  local h = 28
  local t = clamp((value - minV) / (maxV - minV), 0, 1)
  local hov = hit(x - 8, y, x + w + 8, y + h)
  if IN.clicked and hov and IN.active == nil and not IN.locked then IN.active = id end
  local changed = false
  if IN.active == id and IN.down then
    IN.dragScroll = false
    IN.sliderActive = true
    local nt = clamp((IN.m.x - D.x - x) / w, 0, 1)
    if math.abs(nt - t) > 0.0001 then t, changed = nt, true end
    value = minV + (maxV - minV) * t
  end
  local cy = y + h / 2
  rect(x, cy - 2, x + w, cy + 2, T.fill, 2)
  rect(x, cy - 2, x + w * t, cy + 2, color, 2)
  local kx = x + w * t
  circle(kx, cy + 1.5, 13, rgbm(0, 0, 0, 0.25))
  circle(kx, cy, 13, T.white)
  return value, changed
end

-- segmented control, returns index
function W.segmented(id, items, idx, x, y, w)
  local h = 32
  local n = #items
  local sw = (w - 4) / n
  rect(x, y, x + w, y + h, T.fill, 9)
  local pos = anim(id, idx, 18)
  rect(x + 2 + (pos - 1) * sw, y + 2, x + 2 + pos * sw, y + h - 2, rgbm(0.39, 0.39, 0.40, 1), 7)
  for i, label in ipairs(items) do
    local x1 = x + 2 + (i - 1) * sw
    if tap(id .. i, x1, y, x1 + sw, y + h) then idx = i end
    text(label, 13, x1 + sw / 2, y + 7, T.label, i == idx and F.sb or F.m, 0.5)
  end
  return idx
end

-- styled single-line text field (an ImGui input made invisible, drawn our way)
local fieldState = {}
function W.field(id, value, placeholder, x, y, w, h, opts)
  opts = opts or {}
  h = h or 36
  rect(x, y, x + w, y + h, opts.bg or T.fill, opts.round or 10)
  local pad = opts.icon and 30 or 12
  if opts.icon then text(opts.icon, 15, x + 10, y + (h - 20) / 2, T.label2) end
  local visible = true
  local c = clipStack[#clipStack]
  if c and (D.y + y < c[1].y or D.y + y + h > c[2].y) then visible = false end
  local enter = false
  if visible and not IN.locked then
    ui.pushStyleColor(ui.StyleColor.FrameBg, T.clear)
    ui.pushStyleColor(ui.StyleColor.FrameBgHovered, T.clear)
    ui.pushStyleColor(ui.StyleColor.FrameBgActive, T.clear)
    ui.pushStyleColor(ui.StyleColor.Text, T.label)
    ui.pushStyleColor(ui.StyleColor.TextSelectedBg, rgbm(accent().r, accent().g, accent().b, 0.4))
    ui.pushStyleVar(ui.StyleVar.FramePadding, vec2(0, (h - 16) / 2))
    ui.pushStyleVar(ui.StyleVar.FrameBorderSize, 0)
    ui.setCursor(P(x + pad, y))
    ui.setNextItemWidth(w - pad - 8)
    local newV, _, e = ui.inputText('##' .. id, value, opts.flags or 0)
    if opts.focus then ui.setKeyboardFocusHere(-1) end
    fieldState[id] = ui.itemActive()
    ui.popStyleVar(2)
    ui.popStyleColor(5)
    if newV ~= nil then value = newV end
    enter = e
  end
  if value == '' and not fieldState[id] then
    text(placeholder or '', 15, x + pad, y + (h - 20) / 2, T.label3)
  end
  return value, enter
end

-- grouped (inset) list section. rows drawn by callback via W.row
local LIST = { x = 16, w = 320 }
function W.sectionHeader(label, y)
  text(label:upper(), 12, LIST.x + 16, y, T.label2, F.r)
  return y + 22
end

function W.sectionFooter(label, y)
  local sz = measureWrapped(label, 12, LIST.w - 32)
  textBox(label, 12, LIST.x + 16, y + 6, LIST.x + LIST.w - 16, y + 6 + sz.y + 4, T.label2)
  return y + sz.y + 18
end

-- draws a group background; rows must be drawn after with W.row
function W.groupBg(y, rowCount, rowH)
  rowH = rowH or 46
  rect(LIST.x, y, LIST.x + LIST.w, y + rowCount * rowH, T.cell, 14)
  if S.thick and T.border then rectLine(LIST.x, y, LIST.x + LIST.w, y + rowCount * rowH, T.border, 14, 1.5) end
end

-- a list row. opts: icon(emoji), iconBg, value, chevron, last, onTap returns fired
function W.row(id, label, y, opts)
  opts = opts or {}
  local h = opts.h or 46
  local x1, x2 = LIST.x, LIST.x + LIST.w
  local fired, pressed = false, false
  if opts.tappable ~= false and (opts.chevron or opts.tap) then fired, pressed = tap(id, x1, y, x2, y + h) end
  local p = anim(id .. '#p', pressed and 1 or 0, 30)
  if p > 0.01 then
    local flags = nil
    if opts.first and opts.last then flags = ui.CornerFlags.All
    elseif opts.first then flags = ui.CornerFlags.Top
    elseif opts.last then flags = ui.CornerFlags.Bottom
    else flags = ui.CornerFlags.None end
    rect(x1, y, x2, y + h, rgbm(1, 1, 1, 0.08 * p), 12, flags)
  end
  local tx = x1 + 16
  if opts.icon then
    rect(x1 + 14, y + (h - 30) / 2, x1 + 44, y + (h + 30) / 2, opts.iconBg or accent(), 7)
    text(opts.icon, 16, x1 + 29, y + (h - 22) / 2, T.white, F.r, 0.5)
    tx = x1 + 58
  end
  local rightX = x2 - 16
  if opts.chevron then chevron(x2 - 22, y + h / 2, T.label3) rightX = x2 - 32 end
  local labelMax = (opts.value and (LIST.w * 0.55) or (rightX - tx))
  if opts.sub then
    textFit(label, 16, tx, y + 5, labelMax, opts.labelColor or T.label, F.r)
    textFit(opts.sub, 13, tx, y + 26, rightX - tx, T.label2, F.r)
  else
    textFit(label, 16, tx, y + (h - 22) / 2, labelMax, opts.labelColor or T.label, F.r)
  end
  if opts.value then textFit(opts.value, 16, rightX, y + (h - 22) / 2, rightX - tx - 120, T.label2, F.r, 1) end
  if not opts.last then line(tx, y + h - 0.5, x2, y + h - 0.5, T.sep, 1) end
  return fired, rightX
end

-- row with a switch on the right
function W.toggleRow(id, label, value, y, opts)
  opts = opts or {}
  W.row(id .. 'r', label, y, opts)
  local v, changed = W.toggle(id, value, LIST.x + LIST.w - 66, y + 8)
  return v, changed
end

-- row with label, value text, and slider underneath
function W.sliderRow(id, label, value, minV, maxV, fmt, y, opts)
  opts = opts or {}
  local h = 74
  local x1, x2 = LIST.x, LIST.x + LIST.w
  text(label, 15, x1 + 16, y + 10, T.label, F.r)
  text(string.format(fmt, value), 15, x2 - 16, y + 10, T.label2, F.r, 1)
  local v, ch = W.slider(id, value, minV, maxV, x1 + 18, y + 36, LIST.w - 36)
  if not opts.last then line(x1 + 16, y + h - 0.5, x2, y + h - 0.5, T.sep, 1) end
  return v, ch, h
end

-- ===========================================================================
-- Navigation (push/pop with iOS slide, app open/close zoom)
-- ===========================================================================

local NAV = {
  stack = {},        -- current app's screens: { draw = fn(self, w, h), title = '' }
  app = nil,         -- current app object (nil = home)
  trans = nil,       -- { kind = 'push'|'pop'|'open'|'close', t = 0, from = screen, to = screen, icon = {x,y} }
}

local function navTop() return NAV.stack[#NAV.stack] end

local function navPush(screen)
  local from = navTop()
  NAV.stack[#NAV.stack + 1] = screen
  NAV.trans = { kind = 'push', t = 0, from = from, to = screen }
end

local function navPop()
  if #NAV.stack <= 1 then return end
  local from = table.remove(NAV.stack)
  NAV.trans = { kind = 'pop', t = 0, from = from, to = navTop() }
  if from.onClose then from.onClose(from) end
end

-- Standard iOS nav bar. Returns content top y.
-- opts: large (big title that collapses on scroll), back label, right {label, fn}
local function navBar(title, opts, scrollY)
  opts = opts or {}
  local top = 50
  local barH = 44
  local large = opts.large
  local collapse = large and clamp((scrollY or 0) / 40, 0, 1) or 1
  -- bar background shows once content scrolls under it
  if collapse > 0.05 then
    rect(0, 0, SCREEN.w, top + barH, rgbm(0.08, 0.08, 0.09, 0.94 * collapse), SCREEN.r, ui.CornerFlags.Top)
    line(0, top + barH, SCREEN.w, top + barH, rgbm(1, 1, 1, 0.12 * collapse), 1)
  end
  text(title, 17, SCREEN.w / 2, top + 11, A(T.label, collapse), F.sb, 0.5)
  if #NAV.stack > 1 or opts.back then
    local label = opts.back or 'Back'
    local fired, pressed = tap('nav.back', 0, top, 120, top + barH)
    local c = A(accent(), pressed and 0.5 or 1)
    chevronLeft(14, top + barH / 2, c, 10)
    text(label, 17, 30, top + 10, c, F.r)
    if fired then
      if #NAV.stack > 1 then navPop() elseif opts.onBack then opts.onBack() end
    end
  end
  if opts.right then
    local lw = measure(opts.right.label, 17, F.r).x
    local fired, pressed = tap('nav.right', SCREEN.w - lw - 30, top, SCREEN.w, top + barH)
    text(opts.right.label, 17, SCREEN.w - 16, top + 10, A(accent(), pressed and 0.5 or 1), opts.right.bold and F.sb or F.r, 1)
    if fired then opts.right.fn() end
  end
  return top + barH
end

local function largeTitle(title, y, scrollY)
  text(title, 34, 16, y, T.label, F.b)
  if S.thick then rect(18, y + 46, 18 + math.min(60, measure(title, 34, F.b).x), y + 50, accent(), 2) end
  return y + 60
end

-- ===========================================================================
-- Notifications (in-phone banners, or AC messages when the phone is closed)
-- ===========================================================================

local BANNERS = {}   -- { title, body, icon, t, action }
local PHONE_STATE = nil  -- set later to the PHONE table

local function phoneOpen()
  return ac.isWindowOpen and ac.isWindowOpen('main') or false
end

local NOTIFS = {}    -- notification history for Notification Center / lock screen
local lastNotifyAt = -10

local function phoneVisibleNow()
  return phoneOpen() and not (PHONE_STATE and PHONE_STATE.minimized)
end

-- iOS-style notification: banner on the phone, AC message when the phone is closed, always kept in history
local function notify(title, body, icon, action, opts)
  opts = opts or {}
  NOTIFS[#NOTIFS + 1] = { title = title, body = body or '', icon = icon or '💬', time = os.date('%H:%M'), action = action, at = clock() }
  if #NOTIFS > 60 then table.remove(NOTIFS, 1) end
  if not S.notifications or S.dnd then return end
  if not opts.force and clock() - lastNotifyAt < 0.8 then return end
  lastNotifyAt = clock()
  if phoneVisibleNow() then
    BANNERS[#BANNERS + 1] = { title = title, body = body or '', icon = icon or '💬', t = 0, action = action }
    if #BANNERS > 3 then table.remove(BANNERS, 1) end
  elseif not opts.quietWhenClosed then
    ac.setMessage(title, body or '')
  end
end

local function toast(title, body, icon)
  BANNERS[#BANNERS + 1] = { title = title, body = body or '', icon = icon or '📱', t = 0 }
end

-- ===========================================================================
-- Players
-- ===========================================================================

local function mySessionID()
  local me = ac.getCar(0)
  return me and me.sessionID or -1
end

local presence = {}  -- sessionID -> { status }

local function getPlayers()
  local list, sim = {}, ac.getSim()
  local me = ac.getCar(0)
  for i = 1, sim.carsCount - 1 do
    local c = ac.getCar(i)
    if c and c.isConnected then
      local name = ac.getDriverName(i) or ('Car ' .. i)
      local p = presence[c.sessionID]
      list[#list + 1] = {
        index = i, sid = c.sessionID, name = name,
        car = ac.getCarName(i) or '',
        speed = c.speedKmh or 0,
        dist = (me and c.position:distance(me.position)) or 0,
        status = p and p.status or nil,
        hasApp = p ~= nil,
        fav = listHas(S.favorites, name),
      }
    end
  end
  table.sort(list, function(a, b)
    if a.fav ~= b.fav then return a.fav end
    if a.hasApp ~= b.hasApp then return a.hasApp end
    return a.name:lower() < b.name:lower()
  end)
  return list
end

local function initials(name)
  local a, b = name:match('^(%S)%S*%s+(%S)')
  if a then return (a .. b):upper() end
  return (name:sub(1, 2)):upper()
end

local AVATAR_COLORS = {
  rgbm(0.36, 0.55, 0.98, 1), rgbm(0.95, 0.45, 0.35, 1), rgbm(0.30, 0.75, 0.55, 1),
  rgbm(0.80, 0.45, 0.90, 1), rgbm(0.98, 0.70, 0.25, 1), rgbm(0.45, 0.70, 0.85, 1),
}
local function avatarColor(name)
  local h = 0
  for i = 1, #name do h = (h * 31 + name:byte(i)) % 1000 end
  return AVATAR_COLORS[h % #AVATAR_COLORS + 1]
end

local function avatar(name, x, y, size)
  local c = avatarColor(name)
  circle(x + size / 2, y + size / 2, size / 2, c)
  local fs = size * 0.4
  text(initials(name), fs, x + size / 2, y + (size - fs * 1.33) / 2, T.white, F.sb, 0.5)
end

-- ===========================================================================
-- Messaging (compatible with AC Phone v0.1)
-- ===========================================================================

local GROUP = -1
local threads = {}
local MAX_MESSAGES = 250
local CHAT = { open = nil }   -- thread id currently on screen

local function getThread(id, title)
  local t = threads[id]
  if not t then
    t = { id = id, title = title or '?', messages = {}, unread = 0, lastAt = 0 }
    threads[id] = t
  elseif title and title ~= '?' then
    t.title = title
  end
  return t
end
getThread(GROUP, 'Everyone')

local openThread -- forward declaration (set by Messages app)

local function addMessage(threadId, title, from, body, mine, kind)
  local t = getThread(threadId, title)
  t.messages[#t.messages + 1] = { from = from, text = body, mine = mine, time = os.date('%H:%M'), kind = kind or 0, t = 0 }
  if #t.messages > MAX_MESSAGES then table.remove(t.messages, 1) end
  t.lastAt = clock()
  if not mine then
    local viewing = phoneOpen() and CHAT.open == threadId
    if not viewing then
      t.unread = t.unread + 1
      if kind == 1 then
        notify(from, 'Honked at you 📯', '📯', function() openThread(threadId) end)
      else
        notify(threadId == GROUP and (from .. ' · Everyone') or from, body, '💬', function() openThread(threadId) end)
      end
    end
  end
end

local function totalUnread()
  local n = 0
  for _, t in pairs(threads) do n = n + t.unread end
  return n
end

local sendMsg = ac.OnlineEvent({
  ac.StructItem.key('acphone.msg.v1'),
  to = ac.StructItem.int32(),
  kind = ac.StructItem.byte(),
  text = ac.StructItem.string(140),
}, function(sender, data)
  if sender == nil or sender.index == 0 then return end
  local fromName = ac.getDriverName(sender.index) or '?'
  if data.to == GROUP then
    addMessage(GROUP, 'Everyone', fromName, tostring(data.text), false, data.kind)
  elseif data.to == mySessionID() then
    addMessage(sender.sessionID, fromName, fromName, tostring(data.text), false, data.kind)
  end
end)

local sendPresence = ac.OnlineEvent({
  ac.StructItem.key('acphone.presence.v1'),
  status = ac.StructItem.string(40),
}, function(sender, data)
  if sender == nil or sender.index == 0 then return end
  presence[sender.sessionID] = { status = tostring(data.status) }
end)

local function broadcastPresence()
  pcall(sendPresence, { status = utf8Trim(S.status, 40) }, true)
end

local lastSend = -10
local function sendText(threadId, body)
  body = trim(body)
  if body == '' or clock() - lastSend < 0.35 then return false end
  body = utf8Trim(body, 140)
  pcall(sendMsg, { to = threadId, kind = 0, text = body })
  lastSend = clock()
  addMessage(threadId, nil, 'You', body, true, 0)
  return true
end

local function sendHonk(sid, name)
  pcall(sendMsg, { to = sid, kind = 1, text = 'HONK' })
  addMessage(sid, name, 'You', 'HONK', true, 1)
end

-- ===========================================================================
-- Plates (same network format as Hacka Plates)
-- ===========================================================================

local PL = {}
do
  local ok, plates = pcall(require, 'shared/sim/plates')
  PL.lib = ok and plates or nil
  local okj, db = pcall(JSON.parse, S.plateData)
  PL.db = (okj and type(db) == 'table') and db or {}
  PL.db.cars = PL.db.cars or {}
  PL.db.favs = PL.db.favs or {}
  PL.db.recent = PL.db.recent or {}
  PL.carKey = (ac.getCarID(0) or '?') .. '/' .. (ac.getCarSkinID(0) or '?')
  local mine = PL.db.cars[PL.carKey] or {}
  PL.text = mine.text or ''
  PL.country = mine.country or '(none)'
  PL.upper = true
  PL.others, PL.applied, PL.muted = {}, {}, {}
  PL.status = ''
  PL.countries = { '(none)', 'Jamaica', 'UnitedStates', 'UnitedKingdom', 'Japan', 'Germany', 'Italy', 'France',
    'Spain', 'Colombia', 'Brazil', 'Mexico', 'Netherlands', 'Sweden' }
  PL.flags = { ['(none)'] = '🏳', Jamaica = '🇯🇲', UnitedStates = '🇺🇸', UnitedKingdom = '🇬🇧', Japan = '🇯🇵',
    Germany = '🇩🇪', Italy = '🇮🇹', France = '🇫🇷', Spain = '🇪🇸', Colombia = '🇨🇴', Brazil = '🇧🇷', Mexico = '🇲🇽',
    Netherlands = '🇳🇱', Sweden = '🇸🇪' }
  PL.quick = { 'DRIFT', 'SENDIT', 'NO LIMIT', '2JZ', 'V8 BOOST', 'GHOST', '500KMH', 'HELLCAT' }
end

do
local function plateSave() S.plateData = JSON.stringify(PL.db) end

local function plateNation(name)
  if not name or name == '(none)' or not ac.NationCode then return nil end
  local ok, v = pcall(function() return ac.NationCode[name] end)
  return ok and v or nil
end

local function plateMeshes(i)
  return ac.findNodes('carRoot:' .. i):findMeshes('{ texture:plate_d.dds & texture:plate_nm.dds }')
end

local function plateApply(i, body, country)
  if not PL.lib then return false end
  if not body or body == '' then
    pcall(PL.lib.reset, plateMeshes(i), i)
    return true
  end
  local ok, res = pcall(PL.lib.kunos, plateMeshes(i), body, plateNation(country))
  return ok and res ~= false
end

local plateEvent = ac.OnlineEvent({
  hackaPlateText = ac.StructItem.string(24),
  hackaPlateCountry = ac.StructItem.string(16),
}, function(sender, msg)
  if not sender or sender.index == 0 then return end
  PL.others[sender.index] = { text = tostring(msg.hackaPlateText), country = tostring(msg.hackaPlateCountry) }
  PL.applied[sender.index] = nil
end)

local function plateBroadcast()
  if S.plateSync then pcall(plateEvent, { hackaPlateText = PL.text, hackaPlateCountry = PL.country }, true) end
end

local function remember(list, v)
  if v == '' then return end
  for i = #list, 1, -1 do if list[i] == v then table.remove(list, i) end end
  table.insert(list, 1, v)
  while #list > 12 do table.remove(list) end
end

local function plateCommit()
  if PL.upper then PL.text = PL.text:upper() end
  PL.db.cars[PL.carKey] = { text = PL.text, country = PL.country }
  remember(PL.db.recent, PL.text)
  plateSave()
  if not PL.lib then
    PL.status = 'Plates need a newer CSP.'
  elseif plateApply(0, PL.text, PL.country) then
    PL.status = PL.text == '' and 'Back to the default plate.' or 'Plate applied.'
  else
    PL.status = 'This car has no standard plate.'
  end
  plateBroadcast()
end

local plateTimer
local function plateSchedule()
  if plateTimer then clearTimeout(plateTimer) end
  plateTimer = setTimeout(function() plateTimer = nil plateCommit() end, 0.5)
end

local function plateRandom()
  local L, N = 'ABCDEFGHJKLMNPRSTUVWXYZ', '0123456789'
  local function c(s) local k = math.random(#s) return s:sub(k, k) end
  local styles = {
    function() return c(L) .. c(L) .. c(L) .. ' ' .. c(N) .. c(N) .. c(N) end,
    function() return c(L) .. c(L) .. c(N) .. c(N) .. ' ' .. c(L) .. c(L) .. c(L) end,
    function() return c(N) .. c(L) .. c(L) .. c(L) .. c(N) .. c(N) .. c(N) end,
  }
  return styles[math.random(#styles)]()
end

local function plateUpdate()
  if S.plateShowOthers then
    for i, p in pairs(PL.others) do
      local key = p.text .. p.country
      if not PL.muted[i] and PL.applied[i] ~= key then
        PL.applied[i] = key
        plateApply(i, p.text, p.country)
      end
    end
  end
end


PL.save = plateSave
PL.nation = plateNation
PL.meshes = plateMeshes
PL.apply = plateApply
PL.broadcast = plateBroadcast
PL.remember = remember
PL.commit = plateCommit
PL.schedule = plateSchedule
PL.random = plateRandom
PL.update = plateUpdate
end

-- ===========================================================================
-- Skins (technique adapted from Skin Companion by Ligneel; same network events)
-- ===========================================================================

local SK = { data = {}, active = {}, original = {}, busy = {}, status = '' }

local skinRequest
do
local IMG_EXT = { ['.png'] = true, ['.jpg'] = true, ['.jpeg'] = true, ['.dds'] = true }

local function prettySkin(folder)
  local s = folder:gsub('_', ' ')
  return (s:gsub('(%S+)', function(w) return w:sub(1, 1):upper() .. w:sub(2):lower() end))
end

local function skinScan(carID)
  if SK.data[carID] then return SK.data[carID] end
  local list, byKey = {}, {}
  local base = ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carID .. '/skins'
  pcall(io.scanDir, base, function(folderName, attr)
    if attr and attr.isDirectory then
      local path = base .. '/' .. folderName
      local info = { folder = folderName, key = folderName:lower(), path = path, name = prettySkin(folderName), number = '', team = '' }
      local f = io.open(path .. '/ui_skin.json', 'r')
      if f then
        local ok, j = pcall(JSON.parse, f:read('*all'))
        f:close()
        if ok and type(j) == 'table' then
          if j.skinname and j.skinname ~= '' then info.name = j.skinname end
          info.number = tostring(j.number or '')
          info.team = tostring(j.team or '')
        end
      end
      if io.fileExists(path .. '/preview.jpg') then info.preview = path .. '/preview.jpg'
      elseif io.fileExists(path .. '/preview.png') then info.preview = path .. '/preview.png' end
      if io.fileExists(path .. '/livery.png') then info.livery = path .. '/livery.png' end
      list[#list + 1] = info
      byKey[info.key] = info
    end
  end)
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  SK.data[carID] = { list = list, byKey = byKey }
  return SK.data[carID]
end

local function skinOriginal(i)
  if not SK.original[i] then
    local c = ac.getCar(i)
    SK.original[i] = c and c:skin():lower() or ''
  end
  return SK.original[i]
end

local function skinActive(i)
  return SK.active[i] or skinOriginal(i)
end

-- wait for textures to load before swapping, so the car never flashes white
local function whenImagesReady(paths, cb, timeout)
  local list = {}
  for _, p in pairs(paths) do list[#list + 1] = p end
  if #list == 0 then cb() return end
  for _, p in ipairs(list) do ui.imageSize(p) end
  local i, started = 1, os.time()
  local id
  id = setInterval(function()
    while list[i] and ui.imageSize(list[i]).x > 0 do i = i + 1 started = os.time() end
    if list[i] and os.difftime(os.time(), started) > (timeout or 8) then i = i + 1 started = os.time() end
    if not list[i] then clearInterval(id) cb() end
  end)
end

local function skinApply(index, key)
  local carID = ac.getCarID(index)
  if not carID then return end
  local data = skinScan(carID)
  local skin = data.byKey[key or skinOriginal(index)]
  local files = {}
  if skin then
    for _, file in ipairs(io.scanDir(skin.path, '*') or {}) do
      local lower = file:lower()
      local ext = lower:match('^.+(%..+)$')
      if ext and IMG_EXT[ext] and lower ~= 'preview.jpg' and lower ~= 'preview.png' and lower ~= 'livery.png' and lower ~= 'livery.jpg' then
        files[file] = skin.path .. '/' .. lower
      end
    end
  end
  SK.busy[index] = true
  SK.active[index] = skin and skin.key or ''
  whenImagesReady(files, function()
    local node = ac.findNodes('carRoot:' .. index)
    pcall(function() node:resetSkin() end)
    pcall(function() node:applySkin(files) end)
    if skin and io.fileExists(skin.path .. '/ext_config.ini') then
      pcall(function() node:applyShaderReplacements(ac.INIConfig.load(skin.path .. '/ext_config.ini'):serialize()) end)
    end
    pcall(ac.refreshCarColor, index)
    SK.busy[index] = nil
    if index == 0 then SK.status = skin and ('Now wearing ' .. skin.name) or 'Back to the original skin' end
  end, 8)
end

local skinEvent = ac.OnlineEvent({
  ac.StructItem.key('AppBasedSkinChangeEvent'),
  AppBasedSkinID = ac.StructItem.string(175),
}, function(sender, data)
  if not sender or sender.index == 0 or not S.skinShowOthers then return end
  local key = tostring(data.AppBasedSkinID):lower()
  local carID = ac.getCarID(sender.index)
  if not carID then return end
  if skinActive(sender.index) == key then return end
  local d = skinScan(carID)
  skinApply(sender.index, d.byKey[key] and key or nil)
end, ac.SharedNamespace.Global, false)

skinRequest = ac.OnlineEvent({
  ac.StructItem.key('GetActiveSkinsEvent'),
  received = ac.StructItem.boolean(),
}, function(sender, data)
  if sender and sender.index ~= 0 and S.skinSync and SK.active[0] then
    pcall(skinEvent, { AppBasedSkinID = SK.active[0] })
  end
end, ac.SharedNamespace.Global, false)

local function skinSet(key)
  skinApply(0, key)
  if S.skinSync then pcall(skinEvent, { AppBasedSkinID = key or skinOriginal(0) }) end
end

SK.prettySkin = prettySkin
SK.skinScan = skinScan
SK.skinOriginal = skinOriginal
SK.skinActive = skinActive
SK.skinApply = skinApply
SK.skinSet = skinSet
end

-- ===========================================================================
-- Live updates: server chat, joins/leaves, laps, personal bests, contact,
-- fuel, weather and session changes, plus Live Activity data
-- ===========================================================================

local SERVER_CHAT = -2
getThread(SERVER_CHAT, 'Server chat')

local LIVE = {
  lastLapMs = 0, bestMs = 0, lapCount = 0, pos = 0, weather = nil, fuelWarned = false,
  lastContact = -10, expanded = 0, music = nil, musicCheck = 0, topSpeed = 0,
}

local function fmtLap(ms)
  if not ms or ms <= 0 then return '--:--.---' end
  local m = math.floor(ms / 60000)
  local s = (ms % 60000) / 1000
  return string.format('%d:%06.3f', m, s)
end

local function fmtLapShort(ms)
  if not ms or ms <= 0 then return '0:00.0' end
  local m = math.floor(ms / 60000)
  local s = (ms % 60000) / 1000
  return string.format('%d:%04.1f', m, s)
end

-- real AC chat lands in Messages > Server chat
if ac.onChatMessage then
  ac.onChatMessage(function(message, senderCarIndex, senderSessionID)
    if senderCarIndex == 0 then return false end
    local from = senderCarIndex and senderCarIndex >= 0 and (ac.getDriverName(senderCarIndex) or 'Driver') or 'Server'
    addMessage(SERVER_CHAT, 'Server chat', from, tostring(message), false, 0)
    return false
  end)
end

local function sendServerChat(body)
  body = trim(body)
  if body == '' then return false end
  local ok = ac.sendChatMessage(body)
  if ok ~= false then addMessage(SERVER_CHAT, 'Server chat', 'You', body, true, 0) return true end
  toast('Not sent', 'Chat is only available online.', '⚠️')
  return false
end

if ac.onClientConnected then
  ac.onClientConnected(function(carIndex, sessionID)
    setTimeout(function()
      local name = ac.getDriverName(carIndex) or 'Someone'
      local fav = listHas(S.favorites, name)
      notify(name .. ' joined', (ac.getCarName(carIndex) or '') .. (fav and ' ⭐' or ''), '👋', nil, { quietWhenClosed = not fav })
      if PL.text ~= '' then PL.broadcast() end
    end, 3)
  end)
end

if ac.onClientDisconnected then
  ac.onClientDisconnected(function(carIndex, sessionID)
    local name = ac.getDriverName(carIndex) or 'Someone'
    presence[sessionID] = nil
    notify(name .. ' left', 'Disconnected from the server', '🚪', nil, { quietWhenClosed = true })
  end)
end

if ac.onLapCompleted then
  ac.onLapCompleted(0, function(carIndex, lapTime, valid, cuts, lapsCount)
    local pb = valid and lapTime > 0 and (LIVE.bestMs <= 0 or lapTime < LIVE.bestMs)
    local delta = LIVE.bestMs > 0 and (lapTime - LIVE.bestMs) or 0
    if pb then LIVE.bestMs = lapTime end
    LIVE.lastLapMs = lapTime
    LIVE.fuelWarned = false
    if pb then
      notify('Personal best! 🏆', 'Lap ' .. lapsCount .. ' · ' .. fmtLap(lapTime), '⏱️', nil, { force = true })
    elseif not valid then
      notify('Lap ' .. lapsCount .. ' invalid', fmtLap(lapTime) .. (cuts > 0 and (' · ' .. cuts .. ' cut' .. (cuts > 1 and 's' or '')) or ''), '⏱️', nil, { quietWhenClosed = true })
    else
      notify('Lap ' .. lapsCount, fmtLap(lapTime) .. string.format('  (%+.3f)', delta / 1000), '⏱️', nil, { quietWhenClosed = true })
    end
  end)
end

if ac.onCarCollision then
  ac.onCarCollision(0, function()
    if clock() - LIVE.lastContact < 6 then return end
    LIVE.lastContact = clock()
    local car = ac.getCar(0)
    local other = car and car.collidedWith or -1
    if other and other > 0 then
      local name = ac.getDriverName(other - 1) or 'another car'
      notify('Contact', 'You touched ' .. name, '💥', nil, { quietWhenClosed = true })
    end
  end)
end

if ac.onSessionStart then
  ac.onSessionStart(function()
    LIVE.bestMs = 0
    notify('New session', 'The session just started', '🏁', nil, { quietWhenClosed = true })
  end)
end

-- polled every frame from script.update
local function liveUpdate()
  local car, sim = ac.getCar(0), ac.getSim()
  if not car then return end
  if car.bestLapTimeMs and car.bestLapTimeMs > 0 and (LIVE.bestMs <= 0 or car.bestLapTimeMs < LIVE.bestMs) then LIVE.bestMs = car.bestLapTimeMs end
  if car.speedKmh > LIVE.topSpeed then LIVE.topSpeed = car.speedKmh end
  -- fuel
  if car.maxFuel and car.maxFuel > 0 and car.fuel / car.maxFuel < 0.08 and not LIVE.fuelWarned and car.fuel > 0 then
    LIVE.fuelWarned = true
    notify('Low fuel', string.format('%.1f L left', car.fuel), '⛽')
  end
  -- race position
  if car.racePosition and car.racePosition > 0 and sim.carsCount > 1 then
    if LIVE.pos > 0 and car.racePosition ~= LIVE.pos and car.speedKmh > 20 then
      local up = car.racePosition < LIVE.pos
      notify(up and 'Position gained' or 'Position lost', 'You’re P' .. car.racePosition .. ' of ' .. sim.carsCount, up and '📈' or '📉', nil, { quietWhenClosed = true })
    end
    LIVE.pos = car.racePosition
  end
  -- weather
  if LIVE.weather ~= nil and sim.weatherType ~= LIVE.weather then
    local name = tostring(sim.weatherType)
    for k, v in pairs(ac.WeatherType or {}) do if v == sim.weatherType then name = k:gsub('(%l)(%u)', '%1 %2') end end
    notify('Weather update', 'Now: ' .. name, '🌦️', nil, { quietWhenClosed = true })
  end
  LIVE.weather = sim.weatherType
  -- music (Windows media), checked a few times a second
  if clock() - LIVE.musicCheck > 0.5 and ac.currentlyPlaying then
    LIVE.musicCheck = clock()
    local ok, m = pcall(ac.currentlyPlaying)
    LIVE.music = ok and m or nil
  end
end

local function musicPlaying()
  local m = LIVE.music
  return m and m.isPlaying and m.title and m.title ~= '' and m or nil
end

-- ===========================================================================
-- Camera controller: one owner at a time (chase | walk | photo | video)
-- ===========================================================================

local CAM = {
  mode = nil, grab = nil, share = 0, last = clock(),
  pos = vec3(), yaw = 0, pitch = 0, fov = 50, vy = 0, bob = 0,
  target = 0,              -- car index for video shots
  shot = 'orbit',          -- video shot type
  orbit = 0, recStart = 0, recording = false, hidden = false,
  chaseDir = nil, chaseOffset = nil, chaseFov = 52, roll = 0,
  hiddenApps = {}, shutterPending = 0, flash = 0,
}

local camGrab, camRelease, camStartFromCurrent, hideOtherApps, walkStart, videoStart, VIDEO_SHOTS
do
local UP = vec3(0, 1, 0)

local function dirFromYawPitch(yaw, pitch)
  local cp = math.cos(pitch)
  return vec3(math.sin(yaw) * cp, math.sin(pitch), math.cos(yaw) * cp)
end

local function groundAt(pos)
  local origin = vec3(pos.x, pos.y + 2.5, pos.z)
  local d = physics.raycastTrack(origin, vec3(0, -1, 0), 60)
  if d and d >= 0 then return origin.y - d end
  return nil
end

camGrab = function(mode)
  if CAM.grab and CAM.grab:active() then CAM.mode = mode return true end
  local g, err = ac.grabCamera('AC Phone: ' .. mode)
  if not g then
    toast('Camera busy', tostring(err or 'Another script is using the camera.'), '⚠️')
    return false
  end
  CAM.grab, CAM.mode = g, mode
  CAM.grab.ownShare = 0
  CAM.share = 0
  return true
end

camRelease = function()
  if CAM.grab then pcall(function() CAM.grab:dispose() end) end
  CAM.grab, CAM.mode = nil, nil
end

camStartFromCurrent = function()
  local sim = ac.getSim()
  CAM.pos = vec3():set(sim.cameraPosition)
  local look = sim.cameraLook
  CAM.yaw = math.atan2(look.x, look.z)
  CAM.pitch = math.asin(clamp(look.y, -1, 1))
  CAM.fov = S.camFov
end

-- hide every other app window (for clean photos/video), restore later
hideOtherApps = function(hide)
  if not ac.getAppWindows then return end
  if hide then
    CAM.hiddenApps = {}
    for _, w in ipairs(ac.getAppWindows()) do
      if w.visible and w.title ~= 'AC Phone' then
        local acc = ac.accessAppWindow(w.name)
        if acc and acc:valid() then acc:setVisible(false) CAM.hiddenApps[#CAM.hiddenApps + 1] = w.name end
      end
    end
  else
    for _, n in ipairs(CAM.hiddenApps) do
      local acc = ac.accessAppWindow(n)
      if acc and acc:valid() then acc:setVisible(true) end
    end
    CAM.hiddenApps = {}
  end
end

-- free movement input (WASD + Q/E, Shift faster, right mouse to look)
local function freeLook(dt)
  if ui.mouseDown(ui.MouseButton.Right) and not IN.hovered then
    local d = ui.mouseDelta()
    CAM.yaw = CAM.yaw - d.x * 0.0035 * (CAM.fov / 60)
    CAM.pitch = clamp(CAM.pitch - d.y * 0.0035 * (CAM.fov / 60), -1.5, 1.5)
  end
  -- arrow keys also look around
  if ac.isKeyDown(ui.KeyIndex.Left) then CAM.yaw = CAM.yaw + dt * 1.6 end
  if ac.isKeyDown(ui.KeyIndex.Right) then CAM.yaw = CAM.yaw - dt * 1.6 end
  if ac.isKeyDown(ui.KeyIndex.Up) then CAM.pitch = clamp(CAM.pitch + dt * 1.2, -1.5, 1.5) end
  if ac.isKeyDown(ui.KeyIndex.Down) then CAM.pitch = clamp(CAM.pitch - dt * 1.2, -1.5, 1.5) end
end

local function moveInput()
  local f, s, u = 0, 0, 0
  if ac.isKeyDown(ui.KeyIndex.W) then f = f + 1 end
  if ac.isKeyDown(ui.KeyIndex.S) then f = f - 1 end
  if ac.isKeyDown(ui.KeyIndex.D) then s = s + 1 end
  if ac.isKeyDown(ui.KeyIndex.A) then s = s - 1 end
  if ac.isKeyDown(ui.KeyIndex.E) then u = u + 1 end
  if ac.isKeyDown(ui.KeyIndex.Q) then u = u - 1 end
  return f, s, u, ac.isKeyDown(ui.KeyIndex.Shift)
end

local function setTransform(pos, look, up, fov)
  local t = CAM.grab.transform
  t.position:set(pos)
  t.look:set(look)
  t.up:set(up or UP)
  CAM.grab.fov = fov
end

-- ---------------------------------------------------------------- photo/drone
local function updatePhoto(dt)
  freeLook(dt)
  local f, s, u, fast = moveInput()
  local speed = (fast and 22 or 6)
  local look = dirFromYawPitch(CAM.yaw, CAM.pitch)
  local side = vec3(math.cos(CAM.yaw), 0, -math.sin(CAM.yaw))
  CAM.pos = CAM.pos + look * (f * speed * dt) - side * (s * speed * dt) + UP * (u * speed * dt)
  local g = groundAt(CAM.pos)
  if g and CAM.pos.y < g + 0.15 then CAM.pos.y = g + 0.15 end
  if not IN.hovered and IN.wheelGlobal ~= 0 then CAM.fov = clamp(CAM.fov - IN.wheelGlobal * 3, 8, 100) S.camFov = CAM.fov end
  setTransform(CAM.pos, look, UP, CAM.fov)
end

-- ---------------------------------------------------------------- walk
local function updateWalk(dt)
  freeLook(dt)
  local f, s, _, fast = moveInput()
  local speed = fast and 5.5 or 1.6
  local fwd = vec3(math.sin(CAM.yaw), 0, math.cos(CAM.yaw))
  local side = vec3(math.cos(CAM.yaw), 0, -math.sin(CAM.yaw))
  local move = fwd * f - side * s
  if move:length() > 0.01 then
    move = move:normalize() * speed * dt
    -- stop at walls and barriers
    local chest = CAM.pos - UP * 0.6
    local hitD = physics.raycastTrack(chest, move:clone():normalize(), 0.5)
    if not hitD or hitD < 0 then CAM.pos = CAM.pos + move end
    CAM.bob = CAM.bob + dt * (fast and 13 or 8)
  end
  local g = groundAt(CAM.pos - UP * 1.2)
  local eye = 1.68
  if g then
    local targetY = g + eye
    if CAM.pos.y > targetY + 0.05 then
      CAM.vy = CAM.vy - 9.8 * dt
      CAM.pos.y = math.max(targetY, CAM.pos.y + CAM.vy * dt)
    else
      CAM.vy = 0
      CAM.pos.y = damp(CAM.pos.y, targetY, 18, dt)
    end
  end
  if ac.isKeyDown(ui.KeyIndex.Space) and CAM.vy == 0 and g and math.abs(CAM.pos.y - (g + eye)) < 0.05 then CAM.vy = 3.6 CAM.pos.y = CAM.pos.y + 0.01 end
  local moving = f ~= 0 or s ~= 0
  local bob = moving and math.sin(CAM.bob) * 0.025 or 0
  local look = dirFromYawPitch(CAM.yaw, CAM.pitch)
  setTransform(CAM.pos + UP * bob, look, UP, 68)
end

walkStart = function()
  local car = ac.getCar(0)
  if not car then return end
  if not camGrab('walk') then return end
  -- step out next to the driver's door
  local side = car.side
  CAM.pos = car.position + side * 1.6 + UP * 1.7
  local g = groundAt(CAM.pos)
  if g then CAM.pos.y = g + 1.68 end
  local toCar = (car.position - CAM.pos)
  CAM.yaw = math.atan2(toCar.x, toCar.z)
  CAM.pitch = -0.12
  CAM.vy = 0
end

-- ---------------------------------------------------------------- video shots
VIDEO_SHOTS = {
  { id = 'orbit',   name = 'Orbit',     icon = '🔄' },
  { id = 'drone',   name = 'Drone',     icon = '🚁' },
  { id = 'tracker', name = 'Tracking',  icon = '🎯' },
  { id = 'flyby',   name = 'Flyby',     icon = '💨' },
  { id = 'low',     name = 'Low Chase', icon = '📉' },
  { id = 'free',    name = 'Handheld',  icon = '🎥' },
}

local function updateVideo(dt)
  local car = ac.getCar(CAM.target) or ac.getCar(0)
  local sim = ac.getSim()
  local center = car.position + car.up * 0.6
  local shot = CAM.shot
  if shot == 'free' then updatePhoto(dt) return end
  local pos, fov = CAM.pos, 45
  if shot == 'orbit' then
    CAM.orbit = CAM.orbit + dt * 0.35
    local r = 6.5
    pos = center + vec3(math.sin(CAM.orbit) * r, 1.2, math.cos(CAM.orbit) * r)
    fov = 42
  elseif shot == 'drone' then
    local back = car.look:clone() back.y = 0
    if back:length() < 0.01 then back = vec3(0, 0, 1) end
    back = back:normalize()
    local target = center - back * 14 + UP * 7
    CAM.pos = CAM.pos:distance(target) > 60 and target or CAM.pos + (target - CAM.pos) * (1 - math.exp(-2.2 * dt))
    pos, fov = CAM.pos, 38
  elseif shot == 'tracker' then
    local target = center + car.side * 4.2 + car.look * 0.5
    CAM.pos = CAM.pos:distance(target) > 30 and target or CAM.pos + (target - CAM.pos) * (1 - math.exp(-6 * dt))
    pos, fov = CAM.pos, 46
  elseif shot == 'low' then
    local target = center - car.look * 5.5 - car.up * 0.35 + car.side * 0.9
    CAM.pos = CAM.pos:distance(target) > 30 and target or CAM.pos + (target - CAM.pos) * (1 - math.exp(-8 * dt))
    pos, fov = CAM.pos, 55
  elseif shot == 'flyby' then
    local d = CAM.pos:distance(center)
    local behind = (center - CAM.pos):dot(car.look) > 8
    if d > 90 or behind or CAM.flybyInit ~= CAM.target then
      CAM.flybyInit = CAM.target
      local ahead = center + car.velocity * 2.2 + car.look * 15 + car.side * (math.random() > 0.5 and 7 or -7)
      local g = groundAt(ahead)
      CAM.pos = vec3(ahead.x, (g or ahead.y) + 1.1, ahead.z)
    end
    pos = CAM.pos
    fov = clamp(1800 / math.max(d, 5), 8, 55)
  end
  local g = groundAt(pos)
  if g and pos.y < g + 0.2 then pos = vec3(pos.x, g + 0.2, pos.z) end
  local look = (center - pos):normalize()
  setTransform(pos, look, UP, fov)
end

videoStart = function()
  if not camGrab('video') then return end
  camStartFromCurrent()
  CAM.orbit = 0
  CAM.flybyInit = nil
end

-- ---------------------------------------------------------------- chase cam
local function chaseWanted()
  if not S.chaseOn or (CAM.mode and CAM.mode ~= 'chase') then return false end
  local sim = ac.getSim()
  if sim.isReplayActive then return false end
  if S.chaseOnlyInChase then
    return sim.cameraMode == ac.CameraMode.Drivable and
      (sim.driveableCameraMode == ac.DrivableCamera.Chase or sim.driveableCameraMode == ac.DrivableCamera.Chase2)
  end
  return true
end

local function updateChase(dt)
  local sim = ac.getSim()
  local idx = sim.focusedCar >= 0 and sim.focusedCar or 0
  local car = ac.getCar(idx)
  if not car then return end
  local look = car.look:clone()
  look.y = 0
  if look:length() < 0.01 then look = vec3(0, 0, 1) end
  look = look:normalize()
  local dir = look
  if S.chaseFollowMotion and car.speedKmh > 15 then
    local v = car.velocity:clone()
    v.y = 0
    if v:length() > 1 then dir = (look * 0.35 + v:normalize() * 0.65):normalize() end
  end
  if not CAM.chaseDir then CAM.chaseDir = dir:clone() end
  local k = 1 - math.exp(-S.chaseStiff * dt)
  CAM.chaseDir = (CAM.chaseDir + (dir - CAM.chaseDir) * k)
  if CAM.chaseDir:length() < 0.01 then CAM.chaseDir = dir:clone() end
  CAM.chaseDir = CAM.chaseDir:normalize()
  local base = car.position + UP * S.chaseHeight
  local pos = base - CAM.chaseDir * S.chaseDist
  local g = groundAt(pos)
  if g and pos.y < g + 0.3 then pos.y = g + 0.3 end
  local target = car.position + UP * S.chasePivot + CAM.chaseDir * S.chaseLookAhead
  local speedFov = S.chaseSpeedFov * (1 - math.exp(-car.speedKmh / 140))
  CAM.chaseFov = damp(CAM.chaseFov, S.chaseFov + speedFov, 3, dt)
  -- slight roll into corners from lateral g
  local lat = car.acceleration and car.acceleration.x or 0
  CAM.roll = damp(CAM.roll, clamp(-lat * 0.012 * S.chaseTilt, -0.08, 0.08), 3, dt)
  local fwd = (target - pos):normalize()
  local side = fwd:clone():cross(UP):normalize()
  local up = (UP + side * CAM.roll):normalize()
  setTransform(pos, fwd, up, CAM.chaseFov)
end

-- ---------------------------------------------------------------- frame hook
function script.camUpdate()
  local now = clock()
  local dt = clamp(now - CAM.last, 0, 0.1)
  CAM.last = now
  if CAM.flash > 0 then CAM.flash = math.max(0, CAM.flash - dt * 3) end

  -- chase cam takes the camera only when wanted and nothing else is using it
  local wantChase = chaseWanted()
  if wantChase and not CAM.mode then
    if camGrab('chase') then CAM.chaseDir = nil CAM.chaseFov = S.chaseFov end
  elseif CAM.mode == 'chase' and not wantChase then
    if CAM.grab then CAM.grab.ownShare = 0 end
    camRelease()
  end

  if not CAM.grab then return end
  if not CAM.grab:active() then CAM.grab, CAM.mode = nil, nil return end
  CAM.share = damp(CAM.share, 1, CAM.mode == 'chase' and 30 or 6, dt)
  CAM.grab.ownShare = CAM.share
  local ok, err = pcall(function()
    if CAM.mode == 'photo' then updatePhoto(dt)
    elseif CAM.mode == 'walk' then updateWalk(dt)
    elseif CAM.mode == 'video' then updateVideo(dt)
    elseif CAM.mode == 'chase' then updateChase(dt) end
  end)
  if not ok then ac.log('AC Phone camera error: ' .. tostring(err)) end
end

end

local function takePhoto()
  CAM.hidden = true
  if S.camHideApps then hideOtherApps(true) end
  CAM.shutterPending = 3   -- wait a couple frames so the phone is hidden in the shot
end

local function shutterTick()
  if CAM.shutterPending > 0 then
    CAM.shutterPending = CAM.shutterPending - 1
    if CAM.shutterPending == 0 then
      ac.makeScreenshot(nil, ac.ScreenshotFormat.Auto, function(err)
        setTimeout(function()
          CAM.hidden = false
          if S.camHideApps and not CAM.recording then hideOtherApps(false) end
          CAM.flash = 1
          if err then toast('Photo failed', tostring(err), '⚠️') else toast('Photo saved', 'Documents › Assetto Corsa › screens', '📸') end
        end, 0.05)
      end)
    end
  end
end

-- ===========================================================================
-- Software Update: checks the crew's update feed, downloads new versions,
-- checks them, installs them and reloads the phone. Like iOS updates.
-- ===========================================================================

local UPD = {
  url = UPDATE_FEED,       -- set in 1_core
  state = 'idle',          -- idle | checking | downloading | installing | uptodate | error | ready
  message = '', latest = nil, notes = '', lastCheck = 0, nextCheck = clock() + 15, progress = 0,
  pendingRestart = false, files = nil,
}

do
local ALLOWED_FILES = { ['ACPhone.lua'] = true, ['manifest.ini'] = true, ['README.md'] = true, ['icon.png'] = true }

local function appFolder() return ac.getFolder(ac.FolderID.ScriptOrigin) end

-- refuse anything that isn't a valid, complete AC Phone script
local function verifyScript(body)
  if type(body) ~= 'string' or #body < 10000 then return false, 'download looks incomplete' end
  if not body:find('AC Phone', 1, true) then return false, 'not an AC Phone file' end
  local compile = loadstring or load
  local fn, err = compile(body, '=ACPhone-update')
  if not fn then return false, 'update has an error: ' .. tostring(err) end
  return true
end

local function updSetState(state, message)
  UPD.state = state
  UPD.message = message or ''
end

local function installFiles(feed)
  local pending = {}
  for _, f in ipairs(feed.files or {}) do
    if ALLOWED_FILES[f.path] and type(f.url) == 'string' and f.url:match('^https://') then pending[#pending + 1] = f end
  end
  if #pending == 0 then updSetState('error', 'Update has no files') return end
  local got, total, failed = {}, #pending, false
  updSetState('downloading', 'Downloading ' .. feed.version .. '…')
  local function finish()
    if failed then return end
    -- verify everything before touching the installed app
    for _, f in ipairs(pending) do
      local body = got[f.path]
      if f.size and #body ~= f.size then failed = true updSetState('error', f.path .. ' size mismatch') return end
      if f.path == 'ACPhone.lua' then
        local ok, why = verifyScript(body)
        if not ok then failed = true updSetState('error', why) return end
      end
    end
    updSetState('installing', 'Installing…')
    local dir = appFolder()
    -- keep the current version so it can be restored by hand
    pcall(io.copyFile, dir .. '/ACPhone.lua', dir .. '/ACPhone.lua.prev', false)
    for _, f in ipairs(pending) do
      if not io.save(dir .. '/' .. f.path, got[f.path], true) then
        updSetState('error', 'Could not write ' .. f.path)
        return
      end
    end
    S.updateNotes = utf8Trim(feed.notes or '', 900)
    S.updatedTo = tostring(feed.version)
    UPD.pendingRestart = true
    updSetState('ready', 'Installed ' .. feed.version)
  end
  for _, f in ipairs(pending) do
    web.get(f.url .. (f.url:find('?', 1, true) and '&' or '?') .. 't=' .. os.time(), function(err, res)
      if failed then return end
      if err or not res or res.status ~= 200 then
        failed = true
        updSetState('error', 'Download failed (' .. tostring(err or (res and res.status)) .. ')')
        return
      end
      got[f.path] = res.body
      local n = 0
      for _ in pairs(got) do n = n + 1 end
      UPD.progress = n / total
      if n == total then finish() end
    end)
  end
end

local function checkForUpdates(manual)
  if UPD.url == '' then updSetState('error', 'Updates aren’t set up yet') return end
  if UPD.state == 'checking' or UPD.state == 'downloading' or UPD.state == 'installing' then return end
  UPD.lastCheck = clock()
  UPD.nextCheck = clock() + 30 * 60
  updSetState('checking', 'Checking for update…')
  web.get(UPD.url .. '?t=' .. os.time(), function(err, res)
    if err or not res or res.status ~= 200 then
      updSetState(manual and 'error' or 'idle', manual and ('Can’t reach the update server (' .. tostring(err or (res and res.status)) .. ')') or '')
      return
    end
    local ok, feed = pcall(JSON.parse, res.body)
    if not ok or type(feed) ~= 'table' or not tonumber(feed.build) then updSetState('error', 'Update info is damaged') return end
    UPD.latest = feed
    UPD.notes = tostring(feed.notes or '')
    if tonumber(feed.build) <= BUILD then
      updSetState('uptodate', 'AC Phone ' .. VERSION .. ' is up to date')
      return
    end
    if S.autoUpdate or manual then installFiles(feed)
    else updSetState('available', 'AC Phone ' .. tostring(feed.version) .. ' is available') end
  end)
end

-- called every frame; restarts the app at a calm moment once an update is installed
local function updateTick()
  if UPD.url ~= '' and clock() > UPD.nextCheck then checkForUpdates(false) end
  if UPD.pendingRestart then
    local car = ac.getCar(0)
    local calm = not car or car.speedKmh < 8 or ac.getSim().isPaused
    if calm and not CAM.mode and not CAM.recording then
      UPD.pendingRestart = false
      ac.restartApp()
    end
  end
end

-- after a restart into a new version, say what's new once
local function announceUpdate()
  if S.updatedTo ~= '' and S.updatedTo == VERSION then
    notify('AC Phone updated', 'Now on version ' .. VERSION .. '. Tap to see what’s new.', '⬆️', function()
      if UPD.openScreen then UPD.openScreen() end
    end, { force = true })
    S.updatedTo = ''
  end
end

UPD.check, UPD.install, UPD.tick, UPD.announce = checkForUpdates, installFiles, updateTick, announceUpdate
end

-- ===========================================================================
-- CUT-UP: traffic points system (No Hesi style, extended)
--  * points flow from speed while you're in a run
--  * Near Miss / Close Call / Overtake / Oncoming / Lane Split / Slipstream / Speed Trap events
--  * multiplier grows with clean events, combo timer keeps it alive
--  * slow down to BANK the run; crash and the run is LOST
--  * live leaderboard shared with everyone running AC Phone
-- ===========================================================================

local HESI = {
  running = false, run = 0, mult = 1, combo = 0, comboMax = 7, slowT = 0, events = {}, feed = {},
  cars = {}, lastPassSide = 0, lastPassAt = -10, near = 0, best = 0, sessionBest = 0, sessionTotal = 0,
  board = {}, sendAt = 0, stats = { maxMult = 1, top = 0 }, lastRun = nil, heat = 0, crashFlash = 0, bankFlash = 0, lastBank = 0, runTime = 0,
  startSpeed = 70, endSpeed = 30,
}
local HESI_EVENTS = {
  overtake  = { name = 'OVERTAKE',   pts = 120, mult = 0.10, color = rgbm(1, 1, 1, 1) },
  near      = { name = 'NEAR MISS',  pts = 350, mult = 0.30, color = rgbm(1, 0.8, 0.2, 1) },
  close     = { name = 'CLOSE CALL', pts = 800, mult = 0.60, color = rgbm(1, 0.35, 0.2, 1) },
  oncoming  = { name = 'ONCOMING',   pts = 600, mult = 0.40, color = rgbm(0.3, 0.8, 1, 1) },
  split     = { name = 'LANE SPLIT', pts = 1500, mult = 1.00, color = rgbm(0.9, 0.3, 1, 1) },
  slip      = { name = 'SLIPSTREAM', pts = 200, mult = 0.10, color = rgbm(0.5, 1, 0.6, 1) },
  trap      = { name = 'SPEED TRAP', pts = 1000, mult = 0.50, color = rgbm(1, 0.25, 0.4, 1) },
}

do
local MAX_MULT = 20

local function fmtPts(n)
  n = math.floor(n + 0.5)
  local s = tostring(n)
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  if out:sub(1, 1) == ',' then out = out:sub(2) end
  return out
end
HESI.fmt = fmtPts

local function pushFeed(text, color, big)
  table.insert(HESI.feed, 1, { text = text, color = color, t = 0, big = big })
  while #HESI.feed > 6 do table.remove(HESI.feed) end
end

local TIERS = {
  { at = 1, name = '' }, { at = 3, name = 'HEATING UP' }, { at = 6, name = 'ON FIRE' },
  { at = 10, name = 'UNTOUCHABLE' }, { at = 15, name = 'GOD MODE' },
}
local function tierFor(m)
  local t = TIERS[1]
  for _, x in ipairs(TIERS) do if m >= x.at then t = x end end
  return t
end
HESI.tier = function() return tierFor(HESI.mult).name end

local function addEvent(kind, extra)
  local e = HESI_EVENTS[kind]
  if not e then return end
  local before = tierFor(HESI.mult)
  local car = ac.getCar(0)
  local speedFactor = clamp(car.speedKmh / 120, 0.6, 3)
  local pts = e.pts * HESI.mult * speedFactor * (extra or 1)
  HESI.run = HESI.run + pts
  HESI.mult = math.min(MAX_MULT, HESI.mult + e.mult)
  HESI.combo = HESI.comboMax
  HESI.heat = math.min(1, HESI.heat + 0.25)
  if kind ~= 'overtake' then HESI.near = HESI.near + 1 end
  local st = HESI.stats
  st[kind] = (st[kind] or 0) + 1
  if HESI.mult > st.maxMult then st.maxMult = HESI.mult end
  pushFeed(e.name .. '  +' .. fmtPts(pts), e.color, kind == 'split' or kind == 'close' or kind == 'trap')
  local after = tierFor(HESI.mult)
  if after.at > before.at and after.name ~= '' then pushFeed(after.name, rgbm(1, 0.8, 0.25, 1), true) end
end

local function startRun()
  HESI.running, HESI.run, HESI.mult, HESI.combo, HESI.slowT, HESI.runTime = true, 0, 1, 0, 0, 0
  HESI.cars = {}
  HESI.trapDone = false
  HESI.stats = { maxMult = 1, top = 0 }
  pushFeed('RUN STARTED', rgbm(0.4, 1, 0.5, 1))
end

local hesiSend
local function broadcast()
  if not hesiSend then return end
  pcall(hesiSend, {
    run = math.floor(HESI.run), best = math.floor(HESI.sessionBest), total = math.floor(HESI.sessionTotal),
    pb = math.floor(S.hesiPB), mult = math.floor(HESI.mult * 10), state = HESI.running and 1 or 0,
  }, true)
end

local function endRun(crashed)
  if not HESI.running then return end
  HESI.running = false
  local score = math.floor(HESI.run)
  local st = HESI.stats or {}
  HESI.lastRun = { score = score, crashed = crashed, time = HESI.runTime, top = st.top or 0, maxMult = st.maxMult or 1,
    near = (st.near or 0), close = (st.close or 0), split = (st.split or 0), oncoming = (st.oncoming or 0),
    overtake = (st.overtake or 0), pb = (not crashed) and score > S.hesiPB, at = os.date('%H:%M') }
  S.hesiRuns = S.hesiRuns + 1
  S.hesiNear = S.hesiNear + HESI.near
  HESI.near = 0
  if crashed then
    HESI.crashFlash = 1
    pushFeed('CRASHED  -' .. fmtPts(score), T.red, true)
    if score > 2000 then notify('Run lost 💥', fmtPts(score) .. ' points gone. Bank before you crash!', '🔥', nil, { quietWhenClosed = true }) end
  else
    HESI.bankFlash = 1
    HESI.lastBank = score
    HESI.sessionTotal = HESI.sessionTotal + score
    S.hesiTotal = S.hesiTotal + score
    if score > HESI.sessionBest then HESI.sessionBest = score end
    pushFeed('BANKED  +' .. fmtPts(score), rgbm(0.3, 1, 0.5, 1), true)
    if score > S.hesiPB then
      S.hesiPB = score
      notify('New personal best! 🏆', fmtPts(score) .. ' points', '🔥', nil, { force = true })
    elseif score > 5000 then
      notify('Run banked', fmtPts(score) .. ' points', '🔥', nil, { quietWhenClosed = true })
    end
  end
  HESI.run, HESI.mult, HESI.combo = 0, 1, 0
  broadcast()
end
HESI.endRun = endRun

-- online leaderboard
hesiSend = ac.OnlineEvent({
  ac.StructItem.key('acphone.cutup.v1'),
  run = ac.StructItem.int32(), best = ac.StructItem.int32(), total = ac.StructItem.int32(),
  pb = ac.StructItem.int32(), mult = ac.StructItem.int16(), state = ac.StructItem.byte(),
}, function(sender, d)
  if not sender or sender.index == 0 then return end
  local name = ac.getDriverName(sender.index) or '?'
  local prev = HESI.board[sender.sessionID]
  HESI.board[sender.sessionID] = { name = name, run = d.run, best = d.best, total = d.total, pb = d.pb, mult = d.mult / 10,
    running = d.state == 1, at = clock(), index = sender.index }
  -- crew all-time board (kept on this PC)
  local ok, crew = pcall(JSON.parse, S.hesiCrew)
  crew = (ok and type(crew) == 'table') and crew or {}
  if (crew[name] or 0) < d.pb then crew[name] = d.pb S.hesiCrew = JSON.stringify(crew) end
  if prev and d.best > (prev.best or 0) and d.best > 5000 and d.best >= HESI.sessionBest then
    notify(name .. ' set the top run 🔥', fmtPts(d.best) .. ' points', '🔥', nil, { quietWhenClosed = true })
  end
end)

-- detection, every frame
local function hesiUpdate(dt)
  local me = ac.getCar(0)
  if not me or ac.getSim().isPaused or ac.getSim().isReplayActive then return end
  local speed = me.speedKmh
  HESI.heat = math.max(0, HESI.heat - dt * 0.15)
  for _, f in ipairs(HESI.feed) do f.t = f.t + dt end
  for i = #HESI.feed, 1, -1 do if HESI.feed[i].t > 3 then table.remove(HESI.feed, i) end end
  HESI.crashFlash = math.max(0, HESI.crashFlash - dt * 1.2)
  HESI.bankFlash = math.max(0, HESI.bankFlash - dt * 1.2)

  if not S.hesiOn then if HESI.running then endRun(false) end return end
  if me.isInPitlane then if HESI.running then endRun(false) end return end

  if not HESI.running then
    if speed > HESI.startSpeed then startRun() else return end
  end

  HESI.runTime = HESI.runTime + dt
  if HESI.stats and speed > HESI.stats.top then HESI.stats.top = speed end
  -- speed points
  HESI.run = HESI.run + dt * (speed / 12) * HESI.mult
  -- combo timer / multiplier decay
  if HESI.combo > 0 then
    HESI.combo = HESI.combo - dt
    if HESI.combo <= 0 then HESI.mult = math.max(1, HESI.mult * 0.7) if HESI.mult > 1.05 then HESI.combo = 2.5 end end
  end
  -- speed trap
  if speed > 260 and not HESI.trapDone then HESI.trapDone = true addEvent('trap') end
  if speed < 200 then HESI.trapDone = false end
  -- bank when slow for a few seconds
  if speed < HESI.endSpeed then
    HESI.slowT = HESI.slowT + dt
    if HESI.slowT > 3 then endRun(false) return end
  else
    HESI.slowT = 0
  end

  -- traffic passes
  local fwd, side = me.look, me.side
  local sim = ac.getSim()
  for i = 1, sim.carsCount - 1 do
    local c = ac.getCar(i)
    if c and c.isConnected ~= false and c.isActive ~= false then
      local rel = c.position - me.position
      local dist = rel:length()
      local st = HESI.cars[i]
      if dist < 30 then
        local along = rel:dot(fwd)
        local lat = rel:dot(side)
        if not st then st = { along = along, minLat = 99, slip = 0 } HESI.cars[i] = st end
        if math.abs(along) < 4 then st.minLat = math.min(st.minLat, math.abs(lat)) st.sideSign = lat > 0 and 1 or -1 end
        -- slipstream: close behind a car at speed
        if along > 3 and along < 14 and math.abs(lat) < 1.2 and speed > 120 then
          st.slip = st.slip + dt
          if st.slip > 1.2 then st.slip = -6 addEvent('slip') end
        end
        -- passed it (it went from ahead to behind)
        if st.along > 0 and along <= 0 and speed > HESI.startSpeed - 10 then
          local relSpeed = me.velocity:dot(fwd) - c.velocity:dot(fwd)
          local oncoming = c.velocity:dot(fwd) < -3
          if relSpeed > 2 or oncoming then
            local kind = 'overtake'
            if st.minLat < 2.2 then kind = 'close' elseif st.minLat < 3.0 then kind = 'near' end
            addEvent(kind)
            if oncoming then addEvent('oncoming', st.minLat < 3.0 and 1.5 or 1) end
            -- lane split: two passes on opposite sides within half a second
            local now = clock()
            if now - HESI.lastPassAt < 0.5 and st.sideSign and st.sideSign ~= HESI.lastPassSide and st.minLat < 3.2 then addEvent('split') end
            HESI.lastPassAt, HESI.lastPassSide = now, st.sideSign or 0
          end
          st.minLat = 99
        end
        st.along = along
      else
        HESI.cars[i] = nil
      end
    end
  end

  -- share live state every couple of seconds
  if clock() > HESI.sendAt then HESI.sendAt = clock() + 2 broadcast() end
end
HESI.update = hesiUpdate

if ac.onCarCollision then
  ac.onCarCollision(0, function()
    if HESI.running and HESI.runTime > 1 then endRun(true) end
  end)
end
end

-- ===========================================================================
-- Music controls (Windows media keys) and image wallpapers
-- ===========================================================================

local MEDIA = { pendingPlay = nil, pendingAt = 0, lastSend = 0 }
local WALL = {}

do
-- media keys through Windows Script Host: 179 play/pause, 176 next, 177 previous, 175 vol up, 174 vol down
local function sendMediaKey(vk)
  if clock() - MEDIA.lastSend < 0.25 then return end
  MEDIA.lastSend = clock()
  if not os.runConsoleProcess then toast('Music controls', 'Needs a newer CSP', '⚠️') return end
  pcall(os.runConsoleProcess, {
    filename = 'powershell.exe',
    arguments = { '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command',
      '(New-Object -ComObject WScript.Shell).SendKeys([char]' .. vk .. ')' },
    timeout = 6000, terminateWithScript = false,
  }, function() end)
end

function MEDIA.playPause()
  local m = LIVE.music
  MEDIA.pendingPlay = not (m and m.isPlaying)
  MEDIA.pendingAt = clock()
  sendMediaKey(179)
end
function MEDIA.next() sendMediaKey(176) end
function MEDIA.prev() sendMediaKey(177) end
function MEDIA.volUp() sendMediaKey(175) end
function MEDIA.volDown() sendMediaKey(174) end

-- current track, with an optimistic play state right after a tap
function MEDIA.now()
  local m = LIVE.music
  if not m or not m.title or m.title == '' then return nil end
  local playing = m.isPlaying
  if MEDIA.pendingPlay ~= nil then
    if clock() - MEDIA.pendingAt < 1.5 then playing = MEDIA.pendingPlay else MEDIA.pendingPlay = nil end
  end
  return m, playing
end

-- round icon button
function MEDIA.button(id, icon, cx, cy, size, c, bg)
  local fired, pressed = tap(id, cx - size / 2 - 6, cy - size / 2 - 6, cx + size / 2 + 6, cy + size / 2 + 6)
  local p = anim(id .. '#p', pressed and 1 or 0, 30)
  if bg then circle(cx, cy, size / 2 + 8, A(bg, 1 - p * 0.3)) end
  if p > 0.01 then circle(cx, cy, size / 2 + 8, rgbm(1, 1, 1, 0.12 * p)) end
  glyph(icon, cx - size / 2, cy - size / 2, size, A(c or T.white, 1 - p * 0.3))
  return fired
end

-- previous / play-pause / next row centred on cx
function MEDIA.controls(idp, cx, cy, size, c)
  local _, playing = MEDIA.now()
  local gap = size * 2.4
  if MEDIA.button(idp .. 'prev', 'PREVIOUS', cx - gap, cy, size * 0.8, c) then MEDIA.prev() end
  if MEDIA.button(idp .. 'pp', playing and 'PAUSE' or 'PLAY', cx, cy, size, c) then MEDIA.playPause() end
  if MEDIA.button(idp .. 'next', 'NEXT', cx + gap, cy, size * 0.8, c) then MEDIA.next() end
end

-- album art (or a gradient placeholder)
function MEDIA.cover(m, x1, y1, x2, y2, r)
  rect(x1, y1, x2, y2, accent(), r)
  ui.drawRectFilledMultiColor(P(x1, y1 + r), P(x2, y2 - r), A(accent()), A(accent()), A(mix(accent(), rgbm(0, 0, 0, 1), 0.5)), A(mix(accent(), rgbm(0, 0, 0, 1), 0.5)))
  local drawn = false
  if m and m.hasCover then drawn = pcall(ui.drawImageRounded, m, P(x1, y1), P(x2, y2), A(T.white), nil, nil, r) end
  if not drawn then
    local s = (x2 - x1) * 0.4
    glyph('MUSIC', (x1 + x2) / 2 - s / 2, (y1 + y2) / 2 - s / 2, s, rgbm(1, 1, 1, 0.85))
  end
end

local function fmtTime(sec)
  if not sec or sec < 0 then return '--:--' end
  return string.format('%d:%02d', math.floor(sec / 60), math.floor(sec % 60))
end
MEDIA.fmtTime = fmtTime

-- ---------------------------------------------------------------- wallpapers
function WALL.folder() return ac.getFolder(ac.FolderID.ScriptOrigin) .. '/wallpapers' end

function WALL.path(mode)
  mode = mode or S.wallMode
  if mode == 'car' then
    local base = ac.getFolder(ac.FolderID.ContentCars) .. '/' .. (ac.getCarID(0) or '') .. '/skins/' .. (ac.getCarSkinID(0) or '')
    if io.fileExists(base .. '/preview.jpg') then return base .. '/preview.jpg' end
    if io.fileExists(base .. '/preview.png') then return base .. '/preview.png' end
  elseif mode == 'track' then
    local p = ac.getFolder(ac.FolderID.CurrentTrackLayoutUI) .. '/preview.png'
    if io.fileExists(p) then return p end
  elseif mode == 'custom' then
    if S.wallPath ~= '' and io.fileExists(S.wallPath) then return S.wallPath end
  end
  return nil
end

-- draws an image filling the box (cropped, never stretched)
function WALL.cover(path, x1, y1, x2, y2, rounding, tint)
  local sz = ui.imageSize(path)
  if not sz or sz.x <= 0 or sz.y <= 0 then return false end
  local boxAR, imgAR = (x2 - x1) / (y2 - y1), sz.x / sz.y
  local uv1, uv2
  if imgAR > boxAR then
    local f = boxAR / imgAR
    uv1, uv2 = vec2((1 - f) / 2, 0), vec2((1 + f) / 2, 1)
  else
    local f = imgAR / boxAR
    uv1, uv2 = vec2(0, (1 - f) / 2), vec2(1, (1 + f) / 2)
  end
  ui.drawImageRounded(path, P(x1, y1), P(x2, y2), A(tint or T.white), uv1, uv2, rounding or 0, ui.CornerFlags.All)
  return true
end

function WALL.saved()
  local out = {}
  local ok, list = pcall(io.scanDir, WALL.folder(), '*')
  if ok and type(list) == 'table' then
    for _, f in ipairs(list) do
      local e = f:lower():match('%.(%w+)$')
      if e == 'png' or e == 'jpg' or e == 'jpeg' or e == 'bmp' or e == 'dds' then out[#out + 1] = WALL.folder() .. '/' .. f end
    end
  end
  return out
end

-- pick any image on the PC; it's copied into the phone so it stays available
function WALL.import()
  if not os.openFileDialog then toast('Not available', 'Needs a newer CSP', '⚠️') return end
  os.openFileDialog({
    title = 'Choose a wallpaper',
    fileTypes = { { name = 'Images', mask = '*.png;*.jpg;*.jpeg;*.bmp' } },
  }, function(err, filename)
    if err or not filename or filename == '' then return end
    pcall(io.createDir, WALL.folder())
    local name = filename:match('[^/\\]+$') or ('wall' .. os.time() .. '.jpg')
    local dest = WALL.folder() .. '/' .. name
    if io.copyFile(filename, dest, false) or io.fileExists(dest) then
      S.wallPath, S.wallMode = dest, 'custom'
      toast('Wallpaper set', name, '🌅')
    else
      toast('Couldn’t copy image', name, '⚠️')
    end
  end)
end
end

local APPMOD = { Messages = {}, Friends = {}, Camera = {}, Walk = {}, Video = {}, Chase = {}, Plates = {}, Skins = {}, Weather = {}, Library = {}, Settings = {}, Maps = {}, Hud = {}, Livery = {}, Themes = {}, CutUp = {}, Music = {} }

-- ===========================================================================
-- Shared pieces for app screens
-- ===========================================================================

local SW, SH = SCREEN.w, SCREEN.h
local BOTTOM = SH - 34          -- above home indicator
local PHONE = { minimized = false, minimizeReason = nil, locked = false }
PHONE_STATE = PHONE

local function setMinimized(v, reason)
  PHONE.minimized = v
  PHONE.minimizeReason = v and reason or nil
  if ac.setWindowSizeConstraints then
    if v then ac.setWindowSizeConstraints('main', vec2(372, 96), vec2(372, 96))
    else ac.setWindowSizeConstraints('main', vec2(372, 776), vec2(372, 776)) end
  end
end

local function bgFill(c)
  rect(0, 0, SW, SH, c or T.bg, SCREEN.r)
  if c == nil and THEME then
    -- theme flair: soft accent glow up top and a faded motif watermark
    ui.drawRectFilledMultiColor(P(0, 40), P(SW, 260), A(THEME.accent, 0.10), A(THEME.accent, 0.10), A(THEME.accent, 0), A(THEME.accent, 0))
    if THEME.motif then
      local oldA = D.a
      D.a = D.a * 0.07
      text(THEME.motif, 150, SW - 70, SH - 260, T.white, F.r, 0.5)
      D.a = oldA
    end
  end
end

local function chip(id, label, x, y, selected, color)
  local w = measure(label, 14, F.m).x + 24
  local fired, pressed = tap(id, x, y, x + w, y + 32)
  local bg = selected and (color or accent()) or T.fill
  rect(x, y, x + w, y + 32, A(bg, pressed and 0.7 or 1), 16)
  text(label, 14, x + 12, y + 6, T.label, F.m)
  return fired, w
end

-- lays out chips left to right, wrapping; returns clicked label (or nil) and bottom y
local function chipFlow(idPrefix, items, x, y, maxW, isSelected)
  local cx, cy, clicked = x, y, nil
  for i, label in ipairs(items) do
    local w = measure(label, 14, F.m).x + 24
    if cx + w > x + maxW then cx = x cy = cy + 40 end
    if chip(idPrefix .. i, label, cx, cy, isSelected and isSelected(label)) then clicked = label end
    cx = cx + w + 8
  end
  return clicked, cy + 40
end

local function helpCard(lines, y)
  local h = #lines * 24 + 20
  rect(16, y, SW - 16, y + h, T.cell, 14)
  for i, l in ipairs(lines) do
    text(l[1], 14, 32, y + 10 + (i - 1) * 24, T.label, F.sb)
    text(l[2], 14, 120, y + 10 + (i - 1) * 24, T.label2, F.r)
  end
  return y + h
end

local function shutterButton(id, x, y, size, red)
  local fired, pressed = tap(id, x - size / 2, y - size / 2, x + size / 2, y + size / 2)
  local p = anim(id .. '#p', pressed and 1 or 0, 30)
  circleLine(x, y, size / 2 - 2, T.white, 4)
  local inner = size / 2 - 8 - p * 3
  if red then rect(x - inner * 0.55, y - inner * 0.55, x + inner * 0.55, y + inner * 0.55, T.red, 6)
  else circle(x, y, inner, T.white) end
  return fired
end

local function findWindow(keyword)
  if not ac.getAppWindows then return nil end
  keyword = keyword:lower()
  for _, w in ipairs(ac.getAppWindows()) do
    if (w.title or ''):lower():find(keyword, 1, true) then return w end
  end
  return nil
end

local function toggleWindow(name, visible)
  local acc = ac.accessAppWindow(name)
  if acc and acc:valid() then
    if visible == nil then visible = not acc:visible() end
    acc:setVisible(visible)
    return true
  end
  return false
end

-- ===========================================================================
-- MESSAGES
-- ===========================================================================


local threadScreen
do
threadScreen = function(id)
  local scr = { title = '' }
  local compose = ''
  local firstFrame = true
  function scr.draw()
    local t = getThread(id)
    CHAT.open = id
    t.unread = 0
    bgFill()
    local inputH = 52
    local s = scrollBegin('thread' .. id, 94, BOTTOM - inputH)
    local y = 104
    local maxW = SW * 0.72
    local isGroup = id == GROUP or id == SERVER_CHAT
    local lastFrom = nil
    for i, m in ipairs(t.messages) do
      m.t = math.min(1, m.t + IN.dt * 5)
      local body = m.kind == 1 and (m.mine and '📯 You honked' or ('📯 ' .. m.from .. ' honked')) or m.text
      local sz = measureWrapped(body, 16, maxW - 24)
      local bw, bh = math.max(sz.x + 26, 44), sz.y + 16
      if isGroup and not m.mine and lastFrom ~= m.from then
        text(m.from, 12, 20, y, T.label2) y = y + 18
      end
      local slide = (1 - easeOut(m.t)) * 30
      local x = m.mine and (SW - 12 - bw + slide) or (12 - slide)
      local bg = m.kind == 1 and rgbm(1, 0.62, 0.04, 1) or (m.mine and accent() or T.bubbleIn)
      local oldA = D.a
      D.a = D.a * easeOut(m.t)
      rect(x, y, x + bw, y + bh, bg, 18)
      textBox(body, 16, x + 13, y + 7, x + bw - 10, y + bh, T.white)
      D.a = oldA
      y = y + bh + 4
      local nextM = t.messages[i + 1]
      if not nextM or nextM.mine ~= m.mine or nextM.from ~= m.from then
        text(m.time, 11, m.mine and (SW - 16) or 16, y, T.label3, F.r, m.mine and 1 or 0)
        y = y + 20
      end
      lastFrom = m.from
    end
    if #t.messages == 0 then
      text(id == SERVER_CHAT and 'Server chat shows here, same as AC’s chat' or (isGroup and 'Say hi to everyone on the server 👋' or 'Say hi 👋'), 15, SW / 2, 260, T.label2, F.r, 0.5)
    end
    scrollEnd(s, y + 8)
    if firstFrame or t.newSinceDraw then scrollToEnd('thread' .. id) firstFrame = false t.newSinceDraw = false end
    if s.lastCount ~= #t.messages then s.lastCount = #t.messages scrollToEnd('thread' .. id) end

    -- header with avatar
    rect(0, 0, SW, 94, rgbm(0.08, 0.08, 0.09, 0.96), SCREEN.r, ui.CornerFlags.Top)
    line(0, 94, SW, 94, rgbm(1, 1, 1, 0.12), 1)
    navBar('', { back = 'Messages' })
    if isGroup then
      circle(SW / 2, 66, 16, id == SERVER_CHAT and rgbm(0.2, 0.5, 0.9, 1) or rgbm(0.4, 0.4, 0.45, 1))
      text(id == SERVER_CHAT and '🌐' or '👥', 16, SW / 2, 55, T.white, F.r, 0.5)
    else
      avatar(t.title, SW / 2 - 16, 50, 32)
    end
    textFit(t.title, 12, SW / 2, 82 - 2, 200, T.label, F.r, 0.5)
    if not isGroup then
      local fired = tap('th.honk', SW - 56, 50, SW - 10, 90)
      text('📯', 22, SW - 30, 56, T.white, F.r, 0.5)
      if fired then sendHonk(id, t.title) end
    end

    -- compose bar
    local by = BOTTOM - inputH
    rect(0, by, SW, SH, rgbm(0.08, 0.08, 0.09, 0.96), SCREEN.r, ui.CornerFlags.Bottom)
    line(0, by, SW, by, rgbm(1, 1, 1, 0.12), 1)
    local enter
    compose, enter = W.field('compose' .. id, compose, 'Message', 12, by + 8, SW - 68, 36,
      { round = 18, bg = rgbm(0, 0, 0, 1) })
    rectLine(12, by + 8, SW - 56, by + 44, rgbm(1, 1, 1, 0.18), 18, 1)
    local canSend = trim(compose) ~= ''
    local fired = tap('send', SW - 48, by + 6, SW - 8, by + 46)
    circle(SW - 30, by + 26, 15, canSend and accent() or T.fill)
    line(SW - 30, by + 33, SW - 30, by + 19, T.white, 2.4)
    line(SW - 36, by + 25, SW - 30, by + 19, T.white, 2.4)
    line(SW - 24, by + 25, SW - 30, by + 19, T.white, 2.4)
    if (enter or fired) and canSend then
      local sent
      if id == SERVER_CHAT then sent = sendServerChat(compose) else sent = sendText(id, compose) end
      if sent then compose = '' end
    end
    local left = 140 - #compose
    if left < 20 then text(tostring(left), 11, SW - 60, by - 16, left < 0 and T.red or T.label2, F.r, 1) end
  end
  function scr.onClose() CHAT.open = nil end
  return scr
end

openThread = function(id)
  -- jump straight to a conversation (from a notification)
  APPMOD.Messages.openRoot()
  navPush(threadScreen(id))
  NAV.trans = nil
end

function APPMOD.Messages.root()
  local scr = { title = 'Messages' }
  local search = ''
  function scr.draw()
    CHAT.open = nil
    bgFill()
    local s = scrollBegin('msgs', 50, BOTTOM)
    local y = largeTitle('Messages', 96, s.y)
    search = W.field('msgsearch', search, 'Search', 16, y, SW - 32, 36, { icon = '🔍' })
    y = y + 50
    local list = {}
    for tid, t in pairs(threads) do
      if search == '' or t.title:lower():find(search:lower(), 1, true) then list[#list + 1] = t end
    end
    table.sort(list, function(a, b)
      local ra = a.id == GROUP and 0 or (a.id == SERVER_CHAT and 1 or 2)
      local rb = b.id == GROUP and 0 or (b.id == SERVER_CHAT and 1 or 2)
      if ra ~= rb then return ra < rb end
      return a.lastAt > b.lastAt
    end)
    for _, t in ipairs(list) do
      local fired, pressed = tap('th' .. t.id, 0, y, SW, y + 76)
      if pressed then rect(0, y, SW, y + 76, T.cellHi) end
      if t.id == GROUP or t.id == SERVER_CHAT then
        circle(44, y + 38, 26, t.id == SERVER_CHAT and rgbm(0.2, 0.5, 0.9, 1) or rgbm(0.4, 0.4, 0.45, 1))
        text(t.id == SERVER_CHAT and '🌐' or '👥', 22, 44, y + 23, T.white, F.r, 0.5)
      else
        avatar(t.title, 18, y + 12, 52)
      end
      if t.unread > 0 then circle(8, y + 38, 5, accent()) end
      local last = t.messages[#t.messages]
      textFit(t.title, 16, 84, y + 14, SW - 160, T.label, F.sb)
      if last then text(last.time, 14, SW - 34, y + 15, T.label2, F.r, 1) chevron(SW - 22, y + 25, T.label3, 5) end
      local preview = last and ((last.mine and 'You: ' or ((t.id == GROUP or t.id == SERVER_CHAT) and (last.from .. ': ') or '')) .. (last.kind == 1 and '📯 Honk' or last.text)) or 'No messages yet'
      textFit(preview, 14, 84, y + 38, SW - 110, T.label2, F.r)
      line(84, y + 76, SW, y + 76, T.sep, 1)
      if fired then navPush(threadScreen(t.id)) end
      y = y + 77
    end
    y = y + 12
    textBox('Message a friend from the Friends app. Everyone on the server needs AC Phone to receive messages.', 12, 24, y, SW - 24, y + 60, T.label3)
    scrollEnd(s, y + 60)
    navBar('Messages', { large = true }, s.y)
  end
  return scr
end

end

-- ===========================================================================
-- FRIENDS
-- ===========================================================================


do
local function profileScreen(sid)
  local scr = { title = '' }
  function scr.draw()
    bgFill(T.bg)
    local idx
    for i = 1, ac.getSim().carsCount - 1 do local c = ac.getCar(i) if c and c.sessionID == sid then idx = i end end
    local s = scrollBegin('prof' .. sid, 50, BOTTOM)
    if not idx or not ac.getCar(idx).isConnected then
      text('This driver left the server.', 16, SW / 2, 200, T.label2, F.r, 0.5)
      scrollEnd(s, 300)
      navBar('', { back = 'Friends' })
      return
    end
    local car = ac.getCar(idx)
    local name = ac.getDriverName(idx) or '?'
    local p = presence[sid]
    local y = 110
    avatar(name, SW / 2 - 50, y, 100)
    if p then circle(SW / 2 + 36, y + 88, 10, T.bg) circle(SW / 2 + 36, y + 88, 7, T.green) end
    y = y + 112
    textFit(name, 26, SW / 2, y, SW - 40, T.label, F.b, 0.5)
    y = y + 38
    textFit(ac.getCarName(idx) or '', 15, SW / 2, y, SW - 40, T.label2, F.r, 0.5)
    y = y + 24
    if p then text(p.status, 14, SW / 2, y, T.green, F.m, 0.5) else text('No AC Phone', 14, SW / 2, y, T.label3, F.r, 0.5) end
    y = y + 36
    -- action buttons (iOS contact style)
    local actions = {
      { '💬', 'message' }, { '📯', 'honk' }, { '👁', 'watch' }, { listHas(S.favorites, name) and '⭐' or '☆', 'star' },
    }
    local bw = (SW - 32 - 24) / 4
    for i, a in ipairs(actions) do
      local x = 16 + (i - 1) * (bw + 8)
      local fired, pressed = tap('pa' .. i, x, y, x + bw, y + 62)
      rect(x, y, x + bw, y + 62, pressed and T.cellHi or T.cell, 12)
      text(a[1], 20, x + bw / 2, y + 8, T.white, F.r, 0.5)
      text(a[2], 12, x + bw / 2, y + 38, accent(), F.m, 0.5)
      if fired then
        if a[2] == 'message' then getThread(sid, name) navPush(threadScreen(sid))
        elseif a[2] == 'honk' then sendHonk(sid, name) toast('Honk sent', 'to ' .. name, '📯')
        elseif a[2] == 'watch' then ac.focusCar(idx) toast('Watching', name, '👁')
        else S.favorites = listToggle(S.favorites, name) end
      end
    end
    y = y + 78
    W.groupBg(y, 4)
    W.row('pf1', 'Speed', y, { value = string.format('%d km/h', math.floor(car.speedKmh)) })
    W.row('pf2', 'Distance', y + 46, { value = string.format('%d m', math.floor(car.position:distance(ac.getCar(0).position))) })
    local pl = PL.others[idx]
    W.row('pf3', 'Plate', y + 92, { value = pl and pl.text or '—' })
    W.row('pf4', 'Skin', y + 138, { value = SK.prettySkin(SK.skinActive(idx) or ''), last = true })
    y = y + 184 + 20
    scrollEnd(s, y)
    navBar('', { back = 'Friends' })
  end
  return scr
end

function APPMOD.Friends.root()
  local scr = { title = 'Friends' }
  function scr.draw()
    bgFill()
    local players = getPlayers()
    local s = scrollBegin('friends', 50, BOTTOM)
    local y = largeTitle('Friends', 96, s.y)
    local online = ac.getSim().isOnlineRace
    if #players == 0 then
      text(online and '🏁' or '📡', 44, SW / 2, y + 80, T.white, F.r, 0.5)
      text(online and 'Nobody else is here yet' or 'You’re offline', 20, SW / 2, y + 150, T.label, F.sb, 0.5)
      textBox(online and 'When friends join your server they show up here.' or 'Join your server to see friends, message them and sync plates and skins.',
        14, 40, y + 182, SW - 40, y + 240, T.label2)
      scrollEnd(s, y + 260)
      navBar('Friends', { large = true }, s.y)
      return
    end
    y = W.sectionHeader(#players .. ' on this server', y)
    for i, p in ipairs(players) do
      local fired, pressed = tap('fr' .. p.sid, 0, y, SW, y + 68)
      if pressed then rect(0, y, SW, y + 68, T.cellHi) end
      avatar(p.name, 16, y + 10, 48)
      if p.hasApp then circle(56, y + 52, 8, T.bg) circle(56, y + 52, 5.5, T.green) end
      textFit((p.fav and '⭐ ' or '') .. p.name, 16, 78, y + 12, SW - 150, T.label, F.sb)
      textFit(p.status and (p.status .. ' · ' .. p.car) or p.car, 13, 78, y + 36, SW - 150, T.label2, F.r)
      text(string.format('%d m', math.floor(p.dist)), 13, SW - 34, y + 25, T.label2, F.r, 1)
      chevron(SW - 22, y + 34, T.label3, 5)
      if i < #players then line(78, y + 68, SW, y + 68, T.sep, 1) end
      if fired then navPush(profileScreen(p.sid)) end
      y = y + 69
    end
    scrollEnd(s, y + 20)
    navBar('Friends', { large = true }, s.y)
  end
  return scr
end

end

-- ===========================================================================
-- CAMERA (free photo camera), WALK, VIDEO
-- ===========================================================================


function APPMOD.Camera.root()
  local scr = { title = 'Camera' }
  function scr.draw()
    bgFill(rgbm(0, 0, 0, 1))
    if CAM.mode ~= 'photo' and NAV.app and NAV.app.id == 'camera' and not NAV.trans then
      if CAM.mode == 'chase' then camRelease() end
      if not CAM.mode then
        camStartFromCurrent()
        camGrab('photo')
      end
    end
    -- viewfinder frame
    local fx1, fy1, fx2, fy2 = 16, 70, SW - 16, 70 + (SW - 32) * 1.25
    rect(fx1, fy1, fx2, fy2, rgbm(0.06, 0.06, 0.07, 1), 14)
    for i = 1, 2 do
      local gx = fx1 + (fx2 - fx1) * i / 3
      local gy = fy1 + (fy2 - fy1) * i / 3
      line(gx, fy1, gx, fy2, rgbm(1, 1, 1, 0.08), 1)
      line(fx1, gy, fx2, gy, rgbm(1, 1, 1, 0.08), 1)
    end
    text('Free camera', 20, SW / 2, fy1 + 24, T.yellow, F.sb, 0.5)
    local y = fy1 + 70
    y = helpCard({ { 'W A S D', 'move' }, { 'Q / E', 'down / up' }, { 'Shift', 'move faster' },
      { 'Right mouse', 'look around' }, { 'Scroll', 'zoom' } }, y)
    if CAM.mode == 'video' or CAM.mode == 'walk' then
      text('Another camera mode is active', 13, SW / 2, y + 12, T.label2, F.r, 0.5)
    end
    -- zoom
    local zy = fy2 + 14
    local zooms = { { '0.5×', 90 }, { '1×', 50 }, { '2×', 25 }, { '5×', 10 } }
    local zx = SW / 2 - (#zooms * 46) / 2
    for i, z in ipairs(zooms) do
      local cx = zx + (i - 1) * 46 + 23
      local sel = math.abs(CAM.fov - z[2]) < 2
      local fired = tap('zoom' .. i, cx - 20, zy, cx + 20, zy + 40)
      circle(cx, zy + 20, 18, rgbm(1, 1, 1, sel and 0.25 or 0.1))
      text(z[1], 12, cx, zy + 12, sel and T.yellow or T.white, F.sb, 0.5)
      if fired then CAM.fov = z[2] S.camFov = z[2] end
    end
    -- bottom controls
    local by = BOTTOM - 60
    if shutterButton('shutter', SW / 2, by, 72) then takePhoto() end
    if W.button('cam.hide', '⤡', 30, by - 22, 44, 44, 'gray') then setMinimized(true, 'photo') end
    if W.button('cam.exit', 'Done', SW - 90, by - 18, 70, 36, 'gray') then camRelease() APPMOD.Camera.close() end
    navBar('', {})
  end
  function scr.onExit() if CAM.mode == 'photo' then camRelease() end end
  return scr
end

function APPMOD.Walk.root()
  local scr = { title = 'Walk' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('walk', 50, BOTTOM)
    local y = largeTitle('Walk', 96, s.y)
    local walking = CAM.mode == 'walk'
    rect(16, y, SW - 16, y + 150, walking and rgbm(0.12, 0.30, 0.18, 1) or T.cell, 18)
    text(walking and '🚶' or '🚗', 44, 48, y + 22, T.white, F.r, 0)
    text(walking and 'You’re out of the car' or 'In the car', 20, 112, y + 30, T.label, F.b)
    textBox(walking and 'Walk around and take photos of the cars. Your car stays where you left it.'
      or 'Step out next to your car and explore on foot.', 14, 112, y + 62, SW - 32, y + 140, T.label2)
    y = y + 166
    if walking then
      if W.button('walk.back', 'Back to car', 16, y, SW - 32, 50, 'filled') then camRelease() end
      y = y + 62
      if W.button('walk.photo', '📸  Take photo', 16, y, (SW - 40) / 2, 46, 'gray') then takePhoto() end
      if W.button('walk.hide', '⤡  Hide phone', 24 + (SW - 40) / 2, y, (SW - 40) / 2, 46, 'gray') then setMinimized(true, 'walk') end
      y = y + 60
    else
      if W.button('walk.go', 'Step out', 16, y, SW - 32, 50, 'filled') then
        if CAM.mode then camRelease() end
        walkStart()
      end
      y = y + 66
    end
    y = W.sectionHeader('Controls', y + 6)
    y = helpCard({ { 'W A S D', 'walk' }, { 'Shift', 'run' }, { 'Space', 'jump' }, { 'Right mouse', 'look around' }, { 'Arrows', 'look around' } }, y)
    y = W.sectionFooter('If you drive with a keyboard, WASD and arrows may also move your car. Stop and use the handbrake first.', y)
    scrollEnd(s, y + 20)
    navBar('Walk', { large = true }, s.y)
  end
  return scr
end

function APPMOD.Video.root()
  local scr = { title = 'Video' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('video', 50, BOTTOM - 96)
    local y = largeTitle('Video', 96, s.y)
    y = W.sectionHeader('Shot', y)
    local cols, gap = 3, 8
    local cw = (SW - 32 - gap * (cols - 1)) / cols
    for i, shot in ipairs(VIDEO_SHOTS) do
      local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
      local x, yy = 16 + c * (cw + gap), y + r * 88
      local sel = CAM.shot == shot.id
      local fired, pressed = tap('shot' .. i, x, yy, x + cw, yy + 80)
      rect(x, yy, x + cw, yy + 80, sel and A(accent(), 0.25) or (pressed and T.cellHi or T.cell), 14)
      if sel then rectLine(x, yy, x + cw, yy + 80, accent(), 14, 2) end
      text(shot.icon, 24, x + cw / 2, yy + 12, T.white, F.r, 0.5)
      text(shot.name, 13, x + cw / 2, yy + 50, T.label, F.m, 0.5)
      if fired then CAM.shot = shot.id CAM.flybyInit = nil if shot.id == 'free' then camStartFromCurrent() end end
    end
    y = y + 2 * 88 + 12
    y = W.sectionHeader('Film', y)
    local targets = { { 0, 'Me · ' .. (ac.getDriverName(0) or '') } }
    for _, p in ipairs(getPlayers()) do targets[#targets + 1] = { p.index, p.name } end
    W.groupBg(y, #targets)
    for i, tg in ipairs(targets) do
      local fired = W.row('vt' .. i, tg[2], y, { tap = true, last = i == #targets, first = i == 1 })
      if CAM.target == tg[1] then text('✓', 17, SW - 36, y + 11, accent(), F.sb, 0) end
      if fired then CAM.target = tg[1] CAM.flybyInit = nil end
      y = y + 46
    end
    y = y + 8
    W.groupBg(y, 1)
    S.camHideApps = W.toggleRow('vhide', 'Hide other apps while filming', S.camHideApps, y, { last = true, first = true })
    y = W.sectionFooter('AC can’t encode video itself. Press REC here, then start OBS or NVIDIA ShadowPlay (Alt+F9) to capture in 4K.', y + 46)
    scrollEnd(s, y + 10)
    navBar('Video', { large = true }, s.y)
    -- bottom bar: preview + record
    local by = BOTTOM - 96
    rect(0, by, SW, SH, rgbm(0.08, 0.08, 0.09, 0.96), SCREEN.r, ui.CornerFlags.Bottom)
    local live = CAM.mode == 'video'
    if W.button('v.preview', live and 'Stop preview' or 'Preview', 16, by + 26, 110, 40, 'gray') then
      if live then camRelease() else if CAM.mode then camRelease() end videoStart() end
    end
    if shutterButton('rec', SW / 2, by + 46, 64, true) then
      if CAM.mode ~= 'video' then if CAM.mode then camRelease() end videoStart() end
      CAM.recording = true
      CAM.recStart = clock()
      if S.camHideApps then hideOtherApps(true) end
      setMinimized(true, 'rec')
    end
    text('REC', 12, SW / 2, by + 82, T.label2, F.sb, 0.5)
  end
  return scr
end

-- ===========================================================================
-- CHASE CAM
-- ===========================================================================

do
local CHASE_PRESETS = {
  { 'Street', { chaseDist = 5.2, chaseHeight = 1.45, chasePivot = 0.7, chaseFov = 52, chaseStiff = 5, chaseLookAhead = 1.5, chaseSpeedFov = 8, chaseFollowMotion = false, chaseTilt = 0.5 } },
  { 'Drift', { chaseDist = 6.0, chaseHeight = 1.7, chasePivot = 0.6, chaseFov = 58, chaseStiff = 2.6, chaseLookAhead = 0.5, chaseSpeedFov = 6, chaseFollowMotion = true, chaseTilt = 0.8 } },
  { 'Low', { chaseDist = 4.2, chaseHeight = 0.75, chasePivot = 0.55, chaseFov = 60, chaseStiff = 7, chaseLookAhead = 2.5, chaseSpeedFov = 12, chaseFollowMotion = false, chaseTilt = 0.3 } },
  { 'Cinema', { chaseDist = 8.5, chaseHeight = 2.2, chasePivot = 0.8, chaseFov = 34, chaseStiff = 1.8, chaseLookAhead = 2, chaseSpeedFov = 4, chaseFollowMotion = false, chaseTilt = 1 } },
}

function APPMOD.Chase.root()
  local scr = { title = 'Chase Cam' }
  local preset = 1
  function scr.draw()
    bgFill()
    local s = scrollBegin('chase', 50, BOTTOM)
    local y = largeTitle('Chase Cam', 96, s.y)
    -- hero toggle
    rect(16, y, SW - 16, y + 96, T.cell, 18)
    rect(32, y + 22, 84, y + 74, rgbm(0.55, 0.30, 0.95, 1), 12)
    text('🏎️', 28, 58, y + 28, T.white, F.r, 0.5)
    text('Chase Cam', 18, 100, y + 24, T.label, F.sb)
    local active = CAM.mode == 'chase'
    text(S.chaseOn and (active and 'Active now' or (S.chaseOnlyInChase and 'Waiting for chase view' or 'On')) or 'Off', 14, 100, y + 50,
      S.chaseOn and (active and T.green or T.label2) or T.label2)
    S.chaseOn = W.toggle('chaseOn', S.chaseOn, SW - 82, y + 33)
    y = y + 112
    W.groupBg(y, 2)
    S.chaseOnlyInChase = W.toggleRow('chOnly', 'Only in chase view', S.chaseOnlyInChase, y, { first = true })
    S.chaseFollowMotion = W.toggleRow('chMot', 'Follow slides (drift)', S.chaseFollowMotion, y + 46, { last = true })
    y = W.sectionFooter('“Only in chase view” replaces AC’s chase camera (F1) and leaves cockpit and other views alone.', y + 92)
    y = W.sectionHeader('Presets', y + 4)
    local names = {}
    for i, p in ipairs(CHASE_PRESETS) do names[i] = p[1] end
    local np = W.segmented('chp', names, preset, 16, y, SW - 32)
    if np ~= preset then
      preset = np
      for k, v in pairs(CHASE_PRESETS[np][2]) do S[k] = v end
    end
    y = y + 48
    y = W.sectionHeader('Tune', y)
    local rows = {
      { 'chaseDist', 'Distance', 2.5, 12, '%.1f m' }, { 'chaseHeight', 'Height', 0.3, 4, '%.2f m' },
      { 'chasePivot', 'Look height', 0, 1.5, '%.2f m' }, { 'chaseFov', 'Field of view', 25, 90, '%d°' },
      { 'chaseStiff', 'Stiffness', 0.8, 14, '%.1f' }, { 'chaseLookAhead', 'Look ahead', 0, 6, '%.1f m' },
      { 'chaseSpeedFov', 'Speed zoom', 0, 25, '%d°' }, { 'chaseTilt', 'Corner tilt', 0, 2, '%.1f' },
    }
    rect(LIST.x, y, LIST.x + LIST.w, y + #rows * 74, T.cell, 12)
    for i, r in ipairs(rows) do
      local v = W.sliderRow('cs' .. r[1], r[2], S[r[1]], r[3], r[4], r[5], y, { last = i == #rows })
      S[r[1]] = v
      y = y + 74
    end
    y = y + 16
    if W.button('ch.reset', 'Reset to Street', 16, y, SW - 32, 44, 'tinted') then
      preset = 1
      for k, v in pairs(CHASE_PRESETS[1][2]) do S[k] = v end
    end
    scrollEnd(s, y + 64)
    navBar('Chase Cam', { large = true }, s.y)
  end
  return scr
end

end

-- ===========================================================================
-- PLATES
-- ===========================================================================


do
local function drawPlate(x, y, w, h, body, country)
  rect(x + 2, y + 4, x + w + 2, y + h + 4, rgbm(0, 0, 0, 0.35), 10)
  rect(x, y, x + w, y + h, rgbm(0.96, 0.96, 0.93, 1), 10)
  rectLine(x + 4, y + 4, x + w - 4, y + h - 4, rgbm(0.08, 0.08, 0.12, 1), 7, 2.5)
  rect(x + 7, y + 7, x + 40, y + h - 7, rgbm(0.06, 0.22, 0.75, 1), 5, ui.CornerFlags.Left)
  text(PL.flags[country] or '🏳', 18, x + 23, y + 14, T.white, F.r, 0.5)
  local s = body ~= '' and body or 'YOUR TEXT'
  local size = 40
  while size > 16 and measure(s, size, F.b).x > w - 64 do size = size - 2 end
  text(s, size, x + 40 + (w - 48) / 2, y + (h - size * 1.33) / 2, body ~= '' and rgbm(0.08, 0.08, 0.10, 1) or rgbm(0, 0, 0, 0.25), F.b, 0.5)
end

local function countryScreen()
  local scr = { title = 'Country' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('country', 94, BOTTOM)
    local y = 104
    W.groupBg(y, #PL.countries)
    for i, c in ipairs(PL.countries) do
      local label = (PL.flags[c] or '') .. '  ' .. (c == '(none)' and 'No flag' or c:gsub('(%l)(%u)', '%1 %2'))
      if W.row('cty' .. i, label, y, { tap = true, first = i == 1, last = i == #PL.countries }) then
        PL.country = c
        PL.schedule()
        navPop()
      end
      if PL.country == c then text('✓', 17, SW - 36, y + 11, accent(), F.sb) end
      y = y + 46
    end
    scrollEnd(s, y + 20)
    navBar('Country', { back = 'Plates' })
  end
  return scr
end

function APPMOD.Plates.root()
  local scr = { title = 'Plates' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('plates', 50, BOTTOM)
    local y = largeTitle('Plates', 96, s.y)
    textFit((ac.getCarName(0) or '') .. ' · ' .. SK.prettySkin(ac.getCarSkinID(0) or ''), 14, 16, y - 10, SW - 32, T.label2)
    y = y + 18
    drawPlate(30, y, SW - 60, 76, PL.text, PL.country)
    y = y + 96
    local newText, enter = W.field('plateText', PL.text, 'Type your plate', 16, y, SW - 32, 44, { round = 12 })
    if newText ~= PL.text then
      PL.text = utf8Trim(newText, 24)
      PL.schedule()
    end
    if enter then PL.commit() end
    y = y + 54
    local bw = (SW - 32 - 16) / 3
    if W.button('pl.rand', '🎲 Random', 16, y, bw, 40, 'gray') then PL.text = PL.random() PL.schedule() end
    if W.button('pl.name', '👤 My name', 24 + bw, y, bw, 40, 'gray') then PL.text = utf8Trim((ac.getDriverName(0) or ''):upper(), 24) PL.schedule() end
    if W.button('pl.reset', 'Reset', 32 + bw * 2, y, bw, 40, 'danger') then
      PL.text = '' PL.db.cars[PL.carKey] = nil PL.save() PL.apply(0, '', nil) PL.broadcast() PL.status = 'Back to the default plate.'
    end
    y = y + 50
    if PL.status ~= '' then text(PL.status, 13, SW / 2, y, T.label2, F.r, 0.5) y = y + 22 end
    y = y + 6
    W.groupBg(y, 2)
    if W.row('pl.cty', 'Country', y, { chevron = true, first = true, value = (PL.flags[PL.country] or '') .. ' ' .. (PL.country == '(none)' and 'None' or PL.country:gsub('(%l)(%u)', '%1 %2')) }) then
      navPush(countryScreen())
    end
    PL.upper = W.toggleRow('pl.up', 'Force capitals', PL.upper, y + 46, { last = true })
    y = y + 108
    y = W.sectionHeader('Quick picks', y)
    local clicked
    clicked, y = chipFlow('plq', PL.quick, 16, y, SW - 32)
    if clicked then PL.text = clicked PL.schedule() end
    if #PL.db.favs > 0 or PL.text ~= '' then
      y = W.sectionHeader('Favourites', y + 8)
      if #PL.db.favs > 0 then
        clicked, y = chipFlow('plf', PL.db.favs, 16, y, SW - 32, function(l) return l == PL.text end)
        if clicked then PL.text = clicked PL.schedule() end
      end
      if PL.text ~= '' then
        local isFav = false
        for _, f in ipairs(PL.db.favs) do if f == PL.text then isFav = true end end
        if W.button('pl.fav', isFav and '★ Remove from favourites' or '☆ Save to favourites', 16, y, SW - 32, 40, 'tinted') then
          if isFav then for i = #PL.db.favs, 1, -1 do if PL.db.favs[i] == PL.text then table.remove(PL.db.favs, i) end end
          else PL.remember(PL.db.favs, PL.text) end
          PL.save()
        end
        y = y + 52
      end
    end
    if #PL.db.recent > 0 then
      y = W.sectionHeader('Recent', y + 4)
      clicked, y = chipFlow('plr', PL.db.recent, 16, y, SW - 32)
      if clicked then PL.text = clicked PL.schedule() end
    end
    y = W.sectionHeader('Online', y + 8)
    W.groupBg(y, 3)
    S.plateAutoApply = W.toggleRow('pl.auto', 'Apply on start', S.plateAutoApply, y, { first = true })
    local v = W.toggleRow('pl.sync', 'Share my plate', S.plateSync, y + 46)
    if v ~= S.plateSync then S.plateSync = v if v then PL.broadcast() end end
    v = W.toggleRow('pl.oth', 'Show friends’ plates', S.plateShowOthers, y + 92, { last = true })
    if v ~= S.plateShowOthers then
      S.plateShowOthers = v
      if not v then for i in pairs(PL.others) do PL.apply(i, '', nil) PL.applied[i] = nil end end
    end
    y = y + 138
    local any = {}
    for i, p in pairs(PL.others) do any[#any + 1] = { i, p } end
    if #any > 0 then
      y = W.sectionHeader('Friends’ plates', y + 12)
      W.groupBg(y, #any)
      for k, e in ipairs(any) do
        local i, p = e[1], e[2]
        W.row('plo' .. i, ac.getDriverName(i) or ('Car ' .. i), y, { sub = (PL.flags[p.country] or '') .. ' ' .. p.text, h = 56, first = k == 1, last = k == #any })
        local muted = PL.muted[i]
        if W.button('plm' .. i, muted and 'Show' or 'Hide', SW - 90, y + 12, 60, 32, 'tinted') then
          PL.muted[i] = not muted
          if PL.muted[i] then PL.apply(i, '', nil) end
          PL.applied[i] = nil
        end
        y = y + 56
      end
    end
    y = W.sectionFooter('Works with Hacka APPMOD.Plates: friends using either app see each other’s plates.', y + 4)
    scrollEnd(s, y + 20)
    navBar('Plates', { large = true }, s.y)
  end
  return scr
end

end

-- ===========================================================================
-- SKINS
-- ===========================================================================


function APPMOD.Skins.root()
  local scr = { title = 'Skins' }
  local search, filter = '', 1
  function scr.draw()
    bgFill()
    local carID = ac.getCarID(0) or ''
    local data = SK.skinScan(carID)
    local favKey = function(k) return carID .. '/' .. k end
    local s = scrollBegin('skins', 50, BOTTOM)
    local y = largeTitle('Skins', 96, s.y)
    local active = SK.skinActive(0)
    local cur = data.byKey[active]
    -- hero: the skin you're wearing
    local hw, hh = SW - 32, (SW - 32) * 0.56
    if not (cur and cur.preview and WALL.cover(cur.preview, 16, y, 16 + hw, y + hh, 18)) then
      rect(16, y, 16 + hw, y + hh, T.cell, 18)
      glyph('PHOTOGRAPH', SW / 2 - 20, y + hh / 2 - 20, 40, T.label3)
    end
    ui.drawRectFilledMultiColor(P(16, y + hh * 0.45), P(16 + hw, y + hh), A(rgbm(0, 0, 0, 0)), A(rgbm(0, 0, 0, 0)), A(rgbm(0, 0, 0, 0.75)), A(rgbm(0, 0, 0, 0.75)))
    text('WEARING NOW', 11, 30, y + hh - 62, accent(), F.b)
    textFit(cur and cur.name or SK.prettySkin(active), 20, 30, y + hh - 46, hw - 120, T.white, F.b)
    textFit(ac.getCarName(0) or carID, 13, 30, y + hh - 22, hw - 120, rgbm(1, 1, 1, 0.7), F.m)
    if SK.busy[0] then ui.drawLoadingSpinner(P(16 + hw - 44, y + 14), P(16 + hw - 14, y + 44), A(T.white)) end
    if W.button('sk.rand', '@DICE Random', 16 + hw - 112, y + hh - 50, 96, 34, 'gray') and #data.list > 1 and not SK.busy[0] then
      local pick
      repeat pick = data.list[math.random(#data.list)] until pick.key ~= active
      SK.skinSet(pick.key)
    end
    y = y + hh + 14
    search = W.field('sk.search', search, 'Search ' .. #data.list .. ' skins', 16, y, SW - 32, 38, { icon = '🔍' })
    y = y + 48
    filter = W.segmented('sk.filter', { 'All', 'Favourites', 'Friends' }, filter, 16, y, SW - 32)
    y = y + 48
    if filter == 3 then
      local any = false
      for _, p in ipairs(getPlayers()) do
        any = true
        local k = SK.skinActive(p.index)
        local d = SK.skinScan(ac.getCarID(p.index) or '')
        local info = d.byKey[k]
        rect(16, y, SW - 16, y + 74, T.cell, 14)
        if info and info.preview then WALL.cover(info.preview, 16, y, 130, y + 74, 14) else rect(16, y, 130, y + 74, T.cellHi, 14) end
        textFit(p.name, 15, 142, y + 12, SW - 170, T.label, F.sb)
        textFit(info and info.name or SK.prettySkin(k or ''), 13, 142, y + 34, SW - 170, T.label2)
        textFit(p.car, 11, 142, y + 52, SW - 170, T.label3)
        y = y + 82
      end
      if not any then text('No friends on the server', 14, SW / 2, y + 20, T.label2, F.r, 0.5) y = y + 60 end
    else
      local items = {}
      local q = search:lower()
      for _, sk in ipairs(data.list) do
        local fav = listHas(S.skinFavs, favKey(sk.key))
        if (filter == 1 or fav) and (q == '' or sk.name:lower():find(q, 1, true) or sk.key:find(q, 1, true)) then items[#items + 1] = sk end
      end
      local cols, gap = 2, 12
      local cw = (SW - 32 - gap) / cols
      local ih = cw * 0.6
      local ch = ih + 44
      for i, sk in ipairs(items) do
        local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
        local x, yy = 16 + c * (cw + gap), y + r * (ch + gap)
        local sel = active == sk.key
        local fav = listHas(S.skinFavs, favKey(sk.key))
        local starHit = tap('skf' .. i, x + cw - 40, yy, x + cw, yy + 36)
        if starHit then S.skinFavs = listToggle(S.skinFavs, favKey(sk.key)) end
        local fired, pressed = tap('sk' .. i, x, yy, x + cw, yy + ch)
        rect(x, yy, x + cw, yy + ch, pressed and T.cellHi or T.cell, 14)
        local c2 = clipStack[#clipStack]
        local onScreen = not c2 or (D.y + yy + ch > c2[1].y and D.y + yy < c2[2].y)
        if not (sk.preview and onScreen and WALL.cover(sk.preview, x, yy, x + cw, yy + ih, 14)) then
          rect(x, yy, x + cw, yy + ih, rgbm(0.18, 0.18, 0.2, 1), 14, ui.CornerFlags.Top)
          glyph('PALETTE', x + cw / 2 - 14, yy + ih / 2 - 14, 28, T.label3)
        end
        circle(x + cw - 20, yy + 18, 13, rgbm(0, 0, 0, 0.45))
        glyph(fav and 'STAR_FULL' or 'STAR_EMPTY', x + cw - 29, yy + 9, 18, fav and T.yellow or T.white)
        if sel then
          rectLine(x, yy, x + cw, yy + ch, accent(), 14, 2.5)
          circle(x + 18, yy + 18, 11, accent())
          glyph('CONFIRM', x + 11, yy + 11, 14, T.white)
        end
        textFit(sk.name, 13, x + 10, yy + ih + 6, cw - 20, T.label, F.sb)
        local sub = sk.number ~= '' and ('#' .. sk.number .. (sk.team ~= '' and (' · ' .. sk.team) or '')) or (sk.key == SK.skinOriginal(0) and 'Server skin' or sk.folder)
        textFit(sub, 11, x + 10, yy + ih + 25, cw - 20, T.label2)
        if fired and not starHit and not sel and not SK.busy[0] then SK.skinSet(sk.key) end
      end
      y = y + math.ceil(#items / cols) * (ch + gap)
      if #items == 0 then
        text(filter == 2 and 'Tap ☆ on a skin to favourite it' or 'No skins match', 14, SW / 2, y + 20, T.label2, F.r, 0.5)
        y = y + 70
      end
    end
    y = W.sectionHeader('Online', y + 10)
    W.groupBg(y, 2)
    S.skinSync = W.toggleRow('sk.sync', 'Share my skin', S.skinSync, y, { first = true })
    S.skinShowOthers = W.toggleRow('sk.oth', 'Show friends’ skins', S.skinShowOthers, y + 46, { last = true })
    y = W.sectionFooter('Works with Skin Companion. Friends need the same skin installed to see it.', y + 92)
    scrollEnd(s, y + 20)
    navBar('Skins', { large = true }, s.y)
  end
  return scr
end

-- ===========================================================================
-- WEATHER
-- ===========================================================================

local WEATHER_NAMES, WEATHER_ICON = {}, {}
do
  for k, v in pairs(ac.WeatherType or {}) do WEATHER_NAMES[v] = k:gsub('(%l)(%u)', '%1 %2') end
  local icons = { Clear = '☀️', FewClouds = '🌤️', ScatteredClouds = '⛅', BrokenClouds = '🌥️', OvercastClouds = '☁️',
    Fog = '🌫️', Mist = '🌫️', Haze = '🌫️', Smoke = '🌫️', LightRain = '🌦️', Rain = '🌧️', HeavyRain = '🌧️',
    LightDrizzle = '🌦️', Drizzle = '🌦️', HeavyDrizzle = '🌧️', LightThunderstorm = '⛈️', Thunderstorm = '⛈️',
    HeavyThunderstorm = '⛈️', LightSnow = '🌨️', Snow = '❄️', HeavySnow = '❄️', Windy = '💨', Hail = '🌨️' }
  for k, v in pairs(ac.WeatherType or {}) do WEATHER_ICON[v] = icons[k] or '🌡️' end
end

local function weatherNow()
  local sim = ac.getSim()
  local hours = sim.timeHours + sim.timeMinutes / 60
  return {
    type = sim.weatherType, name = WEATHER_NAMES[sim.weatherType] or 'Unknown', icon = WEATHER_ICON[sim.weatherType] or '🌡️',
    temp = sim.ambientTemperature or 0, road = sim.roadTemperature or 0, wind = sim.windSpeedKmh or 0,
    windDir = sim.windDirectionDeg or 0, rain = sim.rainIntensity or 0, wet = sim.rainWetness or 0,
    hours = hours, timeStr = string.format('%02d:%02d', sim.timeHours, sim.timeMinutes),
  }
end

local function skyColors(w)
  local h = w.hours
  local day = clamp(1 - math.abs(h - 13) / 7, 0, 1)
  local dusk = clamp(1 - math.abs(h - 19) / 1.5, 0, 1) + clamp(1 - math.abs(h - 6.5) / 1.5, 0, 1)
  local grey = (w.type and w.type <= 14 or w.type == 19 or w.type == 20 or w.type == 21) and 0.6 or 0
  local top = rgbm(lerp(0.05, 0.20, day) + dusk * 0.4, lerp(0.07, 0.48, day) + dusk * 0.1, lerp(0.20, 0.85, day), 1)
  local bottom = rgbm(lerp(0.10, 0.45, day) + dusk * 0.5, lerp(0.10, 0.65, day) + dusk * 0.25, lerp(0.25, 0.95, day) - dusk * 0.2, 1)
  local g = rgbm(0.45, 0.48, 0.52, 1)
  top = rgbm(lerp(top.r, g.r * day + 0.1, grey), lerp(top.g, g.g * day + 0.1, grey), lerp(top.b, g.b * day + 0.15, grey), 1)
  bottom = rgbm(lerp(bottom.r, g.r * day + 0.15, grey), lerp(bottom.g, g.g * day + 0.15, grey), lerp(bottom.b, g.b * day + 0.2, grey), 1)
  return top, bottom
end

function APPMOD.Weather.root()
  local scr = { title = 'Weather' }
  local timeOffset = 0
  function scr.draw()
    local w = weatherNow()
    local top, bottom = skyColors(w)
    bgFill(bottom)
    ui.drawRectFilledMultiColor(P(0, 0), P(SW, SH * 0.55), A(top), A(top), A(bottom), A(bottom))
    local tp = WALL.path('track')
    if tp and WALL.cover(tp, 0, 0, SW, SH * 0.5, SCREEN.r, rgbm(1, 1, 1, 0.55)) then
      ui.drawRectFilledMultiColor(P(0, SH * 0.2), P(SW, SH * 0.5), A(rgbm(bottom.r, bottom.g, bottom.b, 0)), A(rgbm(bottom.r, bottom.g, bottom.b, 0)), A(bottom), A(bottom))
    end
    local s = scrollBegin('weather', 50, BOTTOM)
    local y = 70
    text(ac.getTrackName and ac.getTrackName() or 'Track', 26, SW / 2, y, T.white, F.m, 0.5)
    y = y + 38
    text(string.format('%d°', math.floor(w.temp + 0.5)), 92, SW / 2 + 12, y - 12, T.white, F.numl, 0.5)
    y = y + 114
    text(w.icon .. '  ' .. w.name, 18, SW / 2, y, T.white, F.m, 0.5)
    y = y + 28
    text('Local time ' .. w.timeStr, 15, SW / 2, y, rgbm(1, 1, 1, 0.75), F.r, 0.5)
    y = y + 44
    -- tiles
    local tw = (SW - 44) / 2
    local tiles = {
      { '🛣️ ROAD', string.format('%d°', math.floor(w.road + 0.5)), w.road > 35 and 'Hot track' or (w.road < 15 and 'Cold track' or 'Good grip') },
      { '💨 WIND', string.format('%d', math.floor(w.wind)), 'km/h' },
      { '🌧️ RAIN', string.format('%d%%', math.floor(w.rain * 100)), w.rain > 0.01 and 'Raining' or 'Dry' },
      { '💧 WETNESS', string.format('%d%%', math.floor(w.wet * 100)), w.wet > 0.3 and 'Wet surface' or 'Dry surface' },
    }
    for i, t in ipairs(tiles) do
      local c, r = (i - 1) % 2, math.floor((i - 1) / 2)
      local x, yy = 16 + c * (tw + 12), y + r * (tw * 0.8 + 12)
      rect(x, yy, x + tw, yy + tw * 0.8, rgbm(0, 0, 0, 0.22), 16)
      text(t[1], 12, x + 14, yy + 12, rgbm(1, 1, 1, 0.65), F.m)
      text(t[2], 34, x + 14, yy + 30, T.white, F.numl)
      text(t[3], 13, x + 14, yy + tw * 0.8 - 26, rgbm(1, 1, 1, 0.8), F.r)
    end
    y = y + 2 * (tw * 0.8 + 12) + 4
    -- time control (offline only)
    rect(16, y, SW - 16, y + 104, rgbm(0, 0, 0, 0.22), 16)
    text('🕒 TIME OF DAY', 12, 30, y + 12, rgbm(1, 1, 1, 0.65), F.m)
    local online = ac.getSim().isOnlineRace
    if online then
      textBox('Online, the server controls time. Use your weather app below for client-side changes.', 14, 30, y + 36, SW - 30, y + 100, T.white)
    else
      text(string.format('%+.1f h', timeOffset / 3600), 14, SW - 30, y + 12, T.white, F.sb, 1)
      local nv, ch = W.slider('wtime', timeOffset, -12 * 3600, 12 * 3600, 30, y + 44, SW - 60, T.white)
      if ch then
        local delta = nv - timeOffset
        if ac.setWeatherTimeOffset(delta, true) then timeOffset = nv end
      end
    end
    y = y + 116
    -- external weather apps
    local apps = {}
    for _, kw in ipairs({ 'dream realism weather', 'pure planner', 'pure config', 'weather' }) do
      local win = findWindow(kw)
      if win then
        local dup = false
        for _, a in ipairs(apps) do if a.name == win.name then dup = true end end
        if not dup then apps[#apps + 1] = win end
      end
    end
    if #apps > 0 then
      text('WEATHER APPS', 12, 30, y + 4, rgbm(1, 1, 1, 0.65), F.m)
      y = y + 24
      rect(16, y, SW - 16, y + #apps * 50, rgbm(0, 0, 0, 0.22), 16)
      for i, a in ipairs(apps) do
        local fired, pressed = tap('wa' .. i, 16, y, SW - 16, y + 50)
        if pressed then rect(16, y, SW - 16, y + 50, rgbm(1, 1, 1, 0.08), 16) end
        textFit(a.title, 16, 32, y + 13, SW - 140, T.white, F.r)
        text(a.visible and 'Close' or 'Open', 15, SW - 32, y + 14, a.visible and rgbm(1, 1, 1, 0.6) or T.white, F.sb, 1)
        if fired then toggleWindow(a.name) end
        if i < #apps then line(32, y + 50, SW - 16, y + 50, rgbm(1, 1, 1, 0.15), 1) end
        y = y + 50
      end
      y = y + 12
    end
    scrollEnd(s, y + 20)
    navBar('', {})
  end
  return scr
end

-- ===========================================================================
-- APP LIBRARY (every installed app window)
-- ===========================================================================

local KNOWN_ICONS = {
  { 'weather', '⛅' }, { 'pure', '🌤️' }, { 'radar', '📡' }, { 'map', '🗺️' }, { 'traffic', '🚦' }, { 'cam', '🎥' },
  { 'drone', '🚁' }, { 'chat', '💬' }, { 'tacho', '⏱️' }, { 'turbo', '🌀' }, { 'meter', '📈' }, { 'shift', '⚙️' },
  { 'hud', '🖥️' }, { 'skin', '🎨' }, { 'plate', '🏷️' }, { 'setup', '🔧' }, { 'tuning', '🔧' }, { 'copilot', '🧭' },
  { 'logger', '📊' }, { 'driver', '🧑' }, { 'simhub', '🎛️' }, { 'moza', '🎡' }, { 'preset', '🎚️' }, { 'pp', '🎚️' },
  { 'time', '🕒' }, { 'lap', '⏱️' }, { 'pedal', '🦶' }, { 'delta', '📉' }, { 'unbound', '🌀' }, { 'horizon', '🌅' },
}
local function appIcon(title)
  local t = (title or ''):lower()
  for _, k in ipairs(KNOWN_ICONS) do if t:find(k[1], 1, true) then return k[2] end end
  return nil
end

local function listWindows()
  local out = {}
  if not ac.getAppWindows then return out end
  for _, w in ipairs(ac.getAppWindows()) do
    if w.title and w.title ~= '' and w.title ~= 'AC Phone' and not w.layerDuplicate then out[#out + 1] = w end
  end
  table.sort(out, function(a, b) return a.title:lower() < b.title:lower() end)
  return out
end

function APPMOD.Library.root()
  local scr = { title = 'App Library' }
  local search = ''
  function scr.draw()
    bgFill()
    local s = scrollBegin('lib', 50, BOTTOM)
    local y = largeTitle('App Library', 96, s.y)
    search = W.field('libsearch', search, 'Search apps', 16, y, SW - 32, 36, { icon = '🔍' })
    y = y + 52
    local wins = listWindows()
    local shown = {}
    for _, w in ipairs(wins) do
      if search == '' or w.title:lower():find(search:lower(), 1, true) then shown[#shown + 1] = w end
    end
    if #shown == 0 then text('No apps found', 15, SW / 2, y + 30, T.label2, F.r, 0.5) end
    W.groupBg(y, #shown, 56)
    for i, w in ipairs(shown) do
      local icon = appIcon(w.title)
      W.row('lw' .. i, w.title, y, { h = 56, icon = icon or utf8Trim(w.title, 1):upper(), iconBg = avatarColor(w.title),
        sub = listHas(S.pinnedApps, w.name) and 'On home screen' or nil, first = i == 1, last = i == #shown })
      local pinned = listHas(S.pinnedApps, w.name)
      local pf = tap('lp' .. i, SW - 120, y, SW - 74, y + 56)
      text(pinned and '★' or '☆', 20, SW - 98, y + 14, pinned and T.yellow or T.label3, F.r, 0.5)
      if pf then S.pinnedApps = listToggle(S.pinnedApps, w.name) end
      local nv = W.toggle('lt' .. i, w.visible, SW - 82, y + 13)
      if nv ~= w.visible then toggleWindow(w.name, nv) end
      y = y + 56
    end
    y = W.sectionFooter('Switch any installed app on or off. Tap ☆ to put it on your home screen (swipe left on the home screen).', y + 4)
    scrollEnd(s, y + 20)
    navBar('App Library', { large = true }, s.y)
  end
  return scr
end

-- ===========================================================================
-- SETTINGS
-- ===========================================================================

local phoneButton
do
local STATUS_PRESETS = { 'Cruising', 'Racing', 'Drifting', 'In the pits', 'Filming', 'AFK' }
phoneButton = ac.ControlButton and ac.ControlButton('acphone/Toggle phone', { keyboard = { key = ui.KeyIndex.P, ctrl = true } }) or nil

local function updateScreen()
  local scr = { title = 'Software Update' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('upd', 94, BOTTOM)
    local y = 110
    rect(16, y, SW - 16, y + 200, T.cell, 16)
    rect(32, y + 18, 92, y + 78, rgbm(0.04, 0.52, 1, 1), 14)
    text('📱', 30, 62, y + 28, T.white, F.r, 0.5)
    local busy = UPD.state == 'checking' or UPD.state == 'downloading' or UPD.state == 'installing'
    local latest = UPD.latest
    local newer = latest and tonumber(latest.build) and tonumber(latest.build) > BUILD
    text('AC Phone ' .. (newer and tostring(latest.version) or VERSION), 18, 108, y + 24, T.label, F.sb)
    text(newer and 'New version' or ('Installed · build ' .. BUILD), 13, 108, y + 50, T.label2)
    local status = UPD.message ~= '' and UPD.message or ('AC Phone ' .. VERSION .. ' is installed')
    if busy then
      local dots = string.rep('•', math.floor(clock() * 3) % 4)
      status = status .. ' ' .. dots
    end
    textBox(status, 14, 32, y + 92, SW - 32, y + 130, UPD.state == 'error' and T.red or T.label2)
    if UPD.state == 'downloading' then
      rect(32, y + 124, SW - 32, y + 130, T.fill, 3)
      rect(32, y + 124, 32 + (SW - 64) * UPD.progress, y + 130, accent(), 3)
    end
    if UPD.state == 'ready' then
      if W.button('upd.restart', 'Restart phone now', 32, y + 142, SW - 64, 44, 'filled') then ac.restartApp() end
    elseif newer and not busy then
      if W.button('upd.install', 'Install Now', 32, y + 142, SW - 64, 44, 'filled') then UPD.install(latest) end
    else
      if W.button('upd.check', busy and 'Working…' or 'Check for Updates', 32, y + 142, SW - 64, 44, busy and 'gray' or 'tinted') and not busy then UPD.check(true) end
    end
    y = y + 216
    W.groupBg(y, 1)
    S.autoUpdate = W.toggleRow('upd.auto', 'Automatic Updates', S.autoUpdate, y, { first = true, last = true })
    y = W.sectionFooter('New versions download and install on their own, then the phone reloads when you’re stopped.', y + 46)
    local notes = (newer and UPD.notes ~= '' and UPD.notes) or S.updateNotes
    if notes and notes ~= '' then
      y = W.sectionHeader('What’s new', y + 8)
      local sz = measureWrapped(notes, 14, SW - 64)
      rect(16, y, SW - 16, y + sz.y + 28, T.cell, 14)
      textBox(notes, 14, 32, y + 14, SW - 32, y + sz.y + 24, T.label)
      y = y + sz.y + 40
    end
    scrollEnd(s, y + 20)
    navBar('Software Update', { back = 'Settings' })
  end
  return scr
end
UPD.screen = updateScreen

local function statusScreen()
  local scr = { title = 'Status' }
  local custom = ''
  function scr.draw()
    bgFill()
    local y = 110
    W.groupBg(y, #STATUS_PRESETS)
    for i, st in ipairs(STATUS_PRESETS) do
      if W.row('st' .. i, st, y, { tap = true, first = i == 1, last = i == #STATUS_PRESETS }) then S.status = st broadcastPresence() end
      if S.status == st then text('✓', 17, SW - 36, y + 11, accent(), F.sb) end
      y = y + 46
    end
    y = W.sectionHeader('Custom', y + 20)
    local enter
    custom, enter = W.field('stc', custom, 'What are you up to?', 16, y, SW - 32, 44, { round = 12, bg = T.cell })
    y = y + 56
    if (W.button('st.set', 'Set status', 16, y, SW - 32, 44, 'filled') or enter) and trim(custom) ~= '' then
      S.status = utf8Trim(trim(custom), 40) custom = '' broadcastPresence()
    end
    navBar('Status', { back = 'Settings' })
  end
  return scr
end

local function wallpaperScreen()
  local scr = { title = 'Wallpaper' }
  function scr.draw()
    bgFill()
    local y = 110
    local cols, gap = 3, 12
    local cw = (SW - 32 - gap * 2) / cols
    for i, wp in ipairs(WALLPAPERS) do
      local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
      local x, yy = 16 + c * (cw + gap), y + r * (cw * 2 + 40)
      local fired = tap('wp' .. i, x, yy, x + cw, yy + cw * 2)
      ui.drawRectFilledMultiColor(P(x, yy), P(x + cw, yy + cw * 2), A(wp.top), A(wp.top), A(wp.bottom), A(wp.bottom))
      rectLine(x, yy, x + cw, yy + cw * 2, S.wallpaper == i and accent() or rgbm(1, 1, 1, 0.15), 6, S.wallpaper == i and 3 or 1)
      text(wp.name, 13, x + cw / 2, yy + cw * 2 + 8, T.label, F.m, 0.5)
      if fired then S.wallpaper = i end
    end
    navBar('Wallpaper', { back = 'Settings' })
  end
  return scr
end

local function keyScreen()
  local scr = { title = 'Phone key' }
  function scr.draw()
    bgFill()
    local y = 110
    textBox('Pick a key or button that opens and closes the phone.', 15, 24, y, SW - 24, y + 50, T.label2)
    y = y + 56
    if phoneButton then
      ui.setCursor(P(16, y))
      phoneButton:control(vec2(SW - 32, 40))
    else
      text('Needs a newer CSP.', 15, 24, y, T.label2)
    end
    navBar('Phone key', { back = 'Settings' })
  end
  return scr
end

function APPMOD.Settings.root()
  local scr = { title = 'Settings' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('settings', 50, BOTTOM)
    local y = largeTitle('Settings', 96, s.y)
    -- profile card
    local name = ac.getDriverName(0) or 'Driver'
    rect(LIST.x, y, LIST.x + LIST.w, y + 76, T.cell, 12)
    avatar(name, LIST.x + 14, y + 12, 52)
    textFit(name, 19, LIST.x + 80, y + 14, LIST.w - 100, T.label, F.sb)
    textFit((ac.getCarName(0) or '') .. ' · ' .. S.status, 13, LIST.x + 80, y + 42, LIST.w - 100, T.label2)
    y = y + 96
    W.groupBg(y, 3)
    if W.row('se.status', 'Status', y, { icon = '💬', iconBg = rgbm(0.2, 0.75, 0.35, 1), value = S.status, chevron = true, first = true }) then navPush(statusScreen()) end
    S.notifications = W.toggleRow('se.notif', 'Notifications', S.notifications, y + 46, { icon = '🔔', iconBg = T.red })
    if W.row('se.key', 'Phone key', y + 92, { icon = '⌨️', iconBg = rgbm(0.45, 0.45, 0.5, 1), value = phoneButton and (phoneButton:boundTo() or 'None') or '', chevron = true, last = true }) then navPush(keyScreen()) end
    y = y + 138 + 24
    W.groupBg(y, 3)
    S.lockScreen = W.toggleRow('se.lock', 'Lock screen', S.lockScreen, y, { icon = '🔒', iconBg = rgbm(0.35, 0.35, 0.4, 1), first = true })
    S.liveActivity = W.toggleRow('se.live', 'Live Activities', S.liveActivity, y + 46, { icon = '⏱', iconBg = T.green })
    S.dnd = W.toggleRow('se.dnd', 'Do Not Disturb', S.dnd, y + 92, { icon = '🌙', iconBg = rgbm(0.4, 0.35, 0.95, 1), last = true })
    y = W.sectionFooter('Tap the left of the status bar for notifications, the right for Control Centre. Tap the Dynamic Island to expand it.', y + 138)
    y = y + 8
    W.groupBg(y, 1)
    if W.row('se.wp', 'Personalize', y, { icon = '@SLIDERS', iconBg = rgbm(0.6, 0.3, 0.9, 1), value = (THEME or THEMES[1]).name, chevron = true, first = true, last = true }) then navPush(APPMOD.Themes.root()) end
    y = y + 66
    W.groupBg(y, 3)
    local hasUpd = UPD.latest and tonumber(UPD.latest.build) and tonumber(UPD.latest.build) > BUILD
    if W.row('se.upd', 'Software Update', y, { icon = '⬆️', iconBg = rgbm(0.45, 0.45, 0.5, 1), value = hasUpd and '1 new' or '', chevron = true, first = true }) then navPush(updateScreen()) end
    if hasUpd then circle(LIST.x + LIST.w - 70, y + 23, 9, T.red) text('1', 12, LIST.x + LIST.w - 70, y + 15, T.white, F.sb, 0.5) end
    y = y + 46
    W.row('se.ver', 'Version', y, { value = VERSION })
    W.row('se.srv', 'Server', y + 46, { value = ac.getSim().isOnlineRace and ((ac.getServerName and ac.getServerName()) or 'Online') or 'Offline', last = true })
    y = W.sectionFooter('AC Phone by smartnajeeri. Messages, plates and skins sync with friends on the same server.', y + 92)
    scrollEnd(s, y + 20)
    navBar('Settings', { large = true }, s.y)
  end
  return scr
end

end


local LIVERY_API = {}

-- ===========================================================================
-- MAPS
-- ===========================================================================

do
local MAPD = nil

local function loadTeleports()
  local out = {}
  if not (ac.getSim().isOnlineRace and ac.INIConfig and ac.INIConfig.onlineExtras) then return out end
  local ok, ini = pcall(ac.INIConfig.onlineExtras)
  if not ok or not ini then return out end
  local n = 0
  pcall(function()
    for _, key in ini:iterateValues('TELEPORT_DESTINATIONS', 'POINT', true) do
      out[#out + 1] = {
        index = n,
        name = tostring(ini:get('TELEPORT_DESTINATIONS', key, 'Point ' .. (n + 1))),
        group = tostring(ini:get('TELEPORT_DESTINATIONS', key .. '_GROUP', '')),
        pos = ini:get('TELEPORT_DESTINATIONS', key .. '_POS', vec3()),
      }
      n = n + 1
    end
  end)
  return out
end

local function mapLoad()
  if MAPD then return MAPD end
  local base = ac.getFolder(ac.FolderID.ContentTracks) .. '/' .. ac.getTrackFullID('/')
  local cfg = { SCALE_FACTOR = 1, X_OFFSET = 0, Z_OFFSET = 0, WIDTH = 500, HEIGHT = 500 }
  pcall(function()
    cfg = ac.INIConfig.load(base .. '/data/map.ini'):mapSection('PARAMETERS', cfg)
  end)
  MAPD = {
    img = base .. '/map.png', has = io.fileExists(base .. '/map.png'),
    sf = (cfg.SCALE_FACTOR and cfg.SCALE_FACTOR ~= 0) and cfg.SCALE_FACTOR or 1,
    ox = cfg.X_OFFSET or 0, oz = cfg.Z_OFFSET or 0, w = cfg.WIDTH or 500, h = cfg.HEIGHT or 500,
    teleports = loadTeleports(),
    center = nil, zoom = nil, follow = true, tab = 1, selected = nil, confirm = nil, confirmAt = 0,
  }
  return MAPD
end

local function mapPx(pos)
  return vec2((pos.x + MAPD.ox) / MAPD.sf, (pos.z + MAPD.oz) / MAPD.sf)
end

function APPMOD.Maps.root()
  local scr = { title = 'Maps' }
  function scr.draw()
    local M = mapLoad()
    bgFill(rgbm(0.07, 0.08, 0.10, 1))
    local imgSize = M.has and ui.imageSize(M.img) or vec2(0, 0)
    if imgSize.x <= 0 then imgSize = vec2(M.w, M.h) end
    local top, sheetTop = 50, SH - 270
    local vx1, vy1, vx2, vy2 = 0, top, SW, sheetTop + 20
    local vc = vec2((vx1 + vx2) / 2, (vy1 + vy2) / 2)
    if not M.zoom then M.zoom = math.min((vx2 - vx1) / imgSize.x, (vy2 - vy1) / imgSize.y) * 0.95 * S.mapZoom end
    local me = ac.getCar(0)
    if not M.center then M.center = me and mapPx(me.position) or imgSize * 0.5 end
    if M.follow and me then M.center = M.center + (mapPx(me.position) - M.center) * (1 - math.exp(-6 * IN.dt)) end
    -- pan & zoom
    local overMap = hit(vx1, vy1, vx2, vy2 - 20)
    if overMap and not IN.locked then
      if IN.wheel ~= 0 then M.zoom = clamp(M.zoom * (1 + IN.wheel * 0.15), 0.05, 12) end
      if IN.down and IN.active == nil and (IN.m - IN.pressPos):length() > 6 then IN.active = '__map' end
      if IN.active == '__map' and IN.down then
        M.center = M.center - IN.delta * (1 / M.zoom)
        M.follow = false
      end
    end
    local function toScreen(px) return vc + (px - M.center) * M.zoom end
    pushClip(vx1, vy1, vx2, vy2)
    if M.has then
      local p1 = toScreen(vec2(0, 0))
      local p2 = toScreen(imgSize)
      ui.drawImage(M.img, P(p1.x, p1.y), P(p2.x, p2.y), A(rgbm(1, 1, 1, 0.95)))
    else
      text('No map image for this track', 15, SW / 2, (vy1 + vy2) / 2 - 10, T.label2, F.r, 0.5)
    end
    -- teleport pins
    if M.tab == 2 then
      for _, tp in ipairs(M.teleports) do
        local s = toScreen(mapPx(tp.pos))
        circle(s.x, s.y, 5, T.yellow)
      end
    end
    -- other cars
    local players = getPlayers()
    for _, p in ipairs(players) do
      local c = ac.getCar(p.index)
      local s = toScreen(mapPx(c.position))
      local sel = M.selected == p.sid
      circle(s.x, s.y, sel and 14 or 11, T.white)
      circle(s.x, s.y, sel and 12 or 9, avatarColor(p.name))
      text(initials(p.name), 9, s.x, s.y - 7, T.white, F.b, 0.5)
      if sel or M.zoom > 1.5 then
        local nw = measure(p.name, 11, F.sb).x + 12
        rect(s.x - nw / 2, s.y - 34, s.x + nw / 2, s.y - 16, rgbm(0, 0, 0, 0.7), 9)
        text(p.name, 11, s.x, s.y - 33, T.white, F.sb, 0.5)
      end
      if tap('mapcar' .. p.sid, s.x - 14, s.y - 14, s.x + 14, s.y + 14) then M.selected = sel and nil or p.sid end
    end
    -- me
    if me then
      local s = toScreen(mapPx(me.position))
      local heading = math.atan2(me.look.x, me.look.z)
      local f = vec2(math.sin(heading), math.cos(heading))
      local sd = vec2(f.y, -f.x)
      circle(s.x, s.y, 20, rgbm(0.04, 0.52, 1, 0.18))
      circle(s.x, s.y, 9, T.white)
      circle(s.x, s.y, 7, rgbm(0.04, 0.52, 1, 1))
      ui.drawTriangleFilled(P(s.x + f.x * 16, s.y + f.y * 16), P(s.x + sd.x * 6 + f.x * 8, s.y + sd.y * 6 + f.y * 8), P(s.x - sd.x * 6 + f.x * 8, s.y - sd.y * 6 + f.y * 8), A(rgbm(0.04, 0.52, 1, 1)))
    end
    popClip()
    -- floating map buttons
    local bx = SW - 54
    rect(bx, top + 56, bx + 40, top + 176, rgbm(0.15, 0.15, 0.17, 0.95), 12)
    if tap('map.loc', bx, top + 56, bx + 40, top + 96) then M.follow = true end
    text(M.follow and '➤' or '⌖', 18, bx + 20, top + 64, M.follow and accent() or T.label, F.r, 0.5)
    line(bx + 8, top + 96, bx + 32, top + 96, T.sep, 1)
    if tap('map.in', bx, top + 96, bx + 40, top + 136) then M.zoom = clamp(M.zoom * 1.4, 0.05, 12) end
    text('+', 22, bx + 20, top + 100, T.label, F.r, 0.5)
    line(bx + 8, top + 136, bx + 32, top + 136, T.sep, 1)
    if tap('map.out', bx, top + 136, bx + 40, top + 176) then M.zoom = clamp(M.zoom / 1.4, 0.05, 12) end
    text('−', 22, bx + 20, top + 140, T.label, F.r, 0.5)

    -- bottom sheet
    rect(0, sheetTop, SW, SH, rgbm(0.11, 0.11, 0.12, 0.98), 22, ui.CornerFlags.Top)
    rect(0, SH - 40, SW, SH, rgbm(0.11, 0.11, 0.12, 0.98), SCREEN.r, ui.CornerFlags.Bottom)
    rect(SW / 2 - 18, sheetTop + 6, SW / 2 + 18, sheetTop + 11, T.label3, 3)
    M.tab = W.segmented('map.tab', { 'Friends', 'Teleports' }, M.tab, 16, sheetTop + 20, SW - 32)
    local s = scrollBegin('mapsheet', sheetTop + 60, BOTTOM)
    local y = sheetTop + 64
    if M.tab == 1 then
      if M.selected then
        local idx
        for _, p in ipairs(players) do if p.sid == M.selected then idx = p end end
        if idx then
          rect(16, y, SW - 16, y + 64, T.cellHi, 14)
          avatar(idx.name, 28, y + 12, 40)
          textFit(idx.name, 15, 78, y + 12, SW - 230, T.label, F.sb)
          text(string.format('%d m · %d km/h', math.floor(idx.dist), math.floor(idx.speed)), 12, 78, y + 34, T.label2)
          if W.button('map.watch', 'Watch', SW - 150, y + 16, 64, 32, 'tinted') then ac.focusCar(idx.index) end
          if W.button('map.msg', 'Text', SW - 80, y + 16, 54, 32, 'filled') then
            getThread(idx.sid, idx.name)
            M.selected = nil
            NAV.app = nil
            openThread(idx.sid)
          end
          y = y + 76
        end
      end
      if #players == 0 then text('No one else on the server', 14, SW / 2, y + 20, T.label2, F.r, 0.5) y = y + 60 end
      for _, p in ipairs(players) do
        local fired, pressed = tap('ms' .. p.sid, 0, y, SW, y + 52)
        if pressed then rect(0, y, SW, y + 52, rgbm(1, 1, 1, 0.05)) end
        avatar(p.name, 18, y + 8, 36)
        textFit(p.name, 15, 66, y + 8, SW - 170, T.label, F.m)
        textFit(p.status or p.car, 12, 66, y + 28, SW - 170, T.label2)
        text(string.format('%d m', math.floor(p.dist)), 13, SW - 20, y + 16, T.label2, F.r, 1)
        if fired then
          M.selected = p.sid
          M.follow = false
          M.center = mapPx(ac.getCar(p.index).position)
        end
        y = y + 52
      end
    else
      if #M.teleports == 0 then
        textBox('This server has no teleport points. Servers with CSP teleport destinations show them here.', 14, 24, y + 10, SW - 24, y + 80, T.label2)
        y = y + 90
      end
      for _, tp in ipairs(M.teleports) do
        local confirming = M.confirm == tp.index and clock() - M.confirmAt < 3
        local fired, pressed = tap('tp' .. tp.index, 0, y, SW, y + 52)
        if pressed then rect(0, y, SW, y + 52, rgbm(1, 1, 1, 0.05)) end
        rect(18, y + 10, 50, y + 42, rgbm(1, 0.6, 0.1, 1), 8)
        text('📍', 15, 34, y + 15, T.white, F.r, 0.5)
        textFit(tp.name, 15, 64, y + 8, SW - 170, T.label, F.m)
        if tp.group ~= '' then textFit(tp.group, 12, 64, y + 28, SW - 170, T.label2) end
        text(confirming and 'Tap to go' or 'Go', 14, SW - 20, y + 16, confirming and T.yellow or accent(), F.sb, 1)
        if fired then
          if confirming then
            if ac.teleportToServerPoint(tp.index) then toast('Teleported', tp.name, '📍') else toast('Can’t teleport', 'Spot is busy or not allowed right now', '⚠️') end
            M.confirm = nil
          else
            M.confirm, M.confirmAt = tp.index, clock()
          end
        end
        y = y + 52
      end
    end
    scrollEnd(s, y + 10)
    -- title pill
    local tname = ac.getTrackName and ac.getTrackName() or 'Map'
    local tw = math.min(measure(tname, 14, F.sb).x + 28, SW - 140)
    rect(SW / 2 - tw / 2, top + 6, SW / 2 + tw / 2, top + 36, rgbm(0.15, 0.15, 0.17, 0.92), 15)
    textFit(tname, 14, SW / 2, top + 12, tw - 20, T.label, F.sb, 0.5)
  end
  return scr
end

end

-- ===========================================================================
-- HUD (switch HUD apps, clean screen, saved layouts)
-- ===========================================================================

do
local HUD_WORDS = { 'hud', 'tacho', 'speedo', 'meter', 'delta', 'dash', 'gauge', 'essential', 'horizon', 'turbo', 'pedal', 'shift', 'radar', 'map' }

local function isHudWindow(title)
  local t = (title or ''):lower()
  for _, w in ipairs(HUD_WORDS) do if t:find(w, 1, true) then return true end end
  return false
end

local function hudLayouts()
  local ok, t = pcall(JSON.parse, S.hudLayouts)
  if ok and type(t) == 'table' then return t end
  return {}
end

local function hudSaveLayouts(t) S.hudLayouts = JSON.stringify(t) end

local function captureLayout(name)
  local entries = {}
  for _, w in ipairs(listWindows()) do
    entries[#entries + 1] = { n = w.name, v = w.visible, x = w.position and w.position.x or 0, y = w.position and w.position.y or 0,
      w = w.size and w.size.x or 0, h = w.size and w.size.y or 0 }
  end
  return { name = name, apps = entries, at = os.date('%d %b %H:%M') }
end

local function applyLayout(layout)
  for _, e in ipairs(layout.apps or {}) do
    local acc = ac.accessAppWindow(e.n)
    if acc and acc:valid() then
      pcall(function()
        if e.v and e.w > 0 then acc:move(vec2(e.x, e.y)) acc:resize(vec2(e.w, e.h)) end
        acc:setVisible(e.v)
      end)
    end
  end
end

function APPMOD.Hud.root()
  local scr = { title = 'HUD' }
  local newName = ''
  function scr.draw()
    bgFill()
    local s = scrollBegin('hud', 50, BOTTOM)
    local y = largeTitle('HUD', 96, s.y)
    local wins = listWindows()
    local huds = {}
    for _, w in ipairs(wins) do if isHudWindow(w.title) then huds[#huds + 1] = w end end
    -- clean screen hero
    local clean = #CAM.hiddenApps > 0
    rect(16, y, SW - 16, y + 84, clean and rgbm(0.10, 0.28, 0.45, 1) or T.cell, 18)
    text(clean and '🫥' or '🖥️', 30, 50, y + 22, T.white, F.r, 0.5)
    text('Clean screen', 17, 84, y + 18, T.label, F.sb)
    text(clean and (#CAM.hiddenApps .. ' apps hidden') or 'Hide every app except the phone', 13, 84, y + 44, T.label2)
    local nv = W.toggle('hud.clean', clean, SW - 82, y + 27)
    if nv ~= clean then hideOtherApps(nv) end
    y = y + 100
    y = W.sectionHeader('Switch HUD', y)
    if #huds == 0 then
      y = W.sectionFooter('No HUD apps found. Any app with HUD, tacho, meter, dash or delta in its name shows here.', y - 6)
    else
      local cw = (SW - 44) / 2
      for i, w in ipairs(huds) do
        local c, r = (i - 1) % 2, math.floor((i - 1) / 2)
        local x, yy = 16 + c * (cw + 12), y + r * 104
        local fired, pressed = tap('hudw' .. i, x, yy, x + cw, yy + 92)
        rect(x, yy, x + cw, yy + 92, w.visible and A(accent(), 0.22) or (pressed and T.cellHi or T.cell), 16)
        if w.visible then rectLine(x, yy, x + cw, yy + 92, accent(), 16, 2) end
        text(appIcon(w.title) or '🖥️', 24, x + 14, yy + 12, T.white)
        textFit(w.title, 13, x + 14, yy + 48, cw - 28, T.label, F.sb)
        text(w.visible and 'On' or 'Off', 12, x + 14, yy + 68, w.visible and accent() or T.label2, F.m)
        if fired then toggleWindow(w.name, not w.visible) end
      end
      y = y + math.ceil(#huds / 2) * 104 + 4
      local bw = (SW - 44) / 2
      if W.button('hud.solo', 'Only first on', 16, y, bw, 38, 'gray') then
        for i, w in ipairs(huds) do toggleWindow(w.name, i == 1) end
      end
      if W.button('hud.alloff', 'All HUDs off', 28 + bw, y, bw, 38, 'gray') then
        for _, w in ipairs(huds) do toggleWindow(w.name, false) end
      end
      y = y + 50
      y = W.sectionFooter('Tap a HUD to turn it on or off. Mix and match, then save it as a layout below.', y)
    end
    y = W.sectionHeader('Layouts', y + 8)
    local layouts = hudLayouts()
    if #layouts > 0 then
      W.groupBg(y, #layouts, 56)
      for i, l in ipairs(layouts) do
        if W.row('hl' .. i, l.name, y, { h = 56, sub = (#(l.apps or {})) .. ' apps · saved ' .. (l.at or ''), tap = true, first = i == 1, last = i == #layouts }) then
          applyLayout(l)
          toast('Layout applied', l.name, '🎛️')
        end
        if W.button('hld' .. i, 'Delete', SW - 96, y + 12, 66, 32, 'danger') then
          table.remove(layouts, i)
          hudSaveLayouts(layouts)
          break
        end
        y = y + 56
      end
      y = y + 12
    end
    local enter
    newName, enter = W.field('hud.name', newName, 'Layout name (e.g. Race, Cruise)', 16, y, SW - 32, 44, { round = 12, bg = T.cell })
    y = y + 54
    if (W.button('hud.save', 'Save current layout', 16, y, SW - 32, 44, 'filled') or enter) then
      local name = trim(newName) ~= '' and trim(newName) or ('Layout ' .. (#layouts + 1))
      layouts[#layouts + 1] = captureLayout(name)
      hudSaveLayouts(layouts)
      newName = ''
      toast('Layout saved', name, '💾')
    end
    y = W.sectionFooter('A layout remembers which apps are open and where they sit on screen.', y + 50)
    scrollEnd(s, y + 20)
    navBar('HUD', { large = true }, s.y)
  end
  return scr
end

end

-- ===========================================================================
-- LIVERY (repaint body, rims and calipers live; synced online)
-- ===========================================================================

do
local LV_PARTS = {
  body = { 'car_paint.dds', 'car_paint.png', 'car_paint.jpg', 'metal_details.dds', 'metal_detail.dds', 'carpaint_detail.dds' },
  rims = { 'car_paint_rims.dds', 'metal_detail_rim.dds', 'rim_detail.dds', 'rim_color.dds', 'rim_colour.dds' },
  calipers = { 'caliper_color.dds', 'caliper_colour.dds', 'metal_detail_caliper.dds', 'caliper_detail.dds', 'ext_caliper_color.dds' },
}
local LV_PATTERNS = { 'Solid', 'Fade', 'Stripes', 'Checker', 'Camo', 'Carbon', 'Racing', 'Diagonal', 'Split', 'Forged' }
local LV_NEEDS2 = { Fade = true, Stripes = true, Checker = true, Camo = true, Racing = true, Diagonal = true, Split = true }
local LV_FINISHES = { 'Original', 'Gloss', 'Matte', 'Metallic', 'Pearl', 'Chrome', 'Satin', 'Candy' }
local LV_FINISH_PROPS = {
  Gloss = { ksSpecular = 0.6, ksSpecularEXP = 120, fresnelMaxLevel = 0.5, fresnelC = 0.06 },
  Matte = { ksSpecular = 0.06, ksSpecularEXP = 6, fresnelMaxLevel = 0.04, fresnelC = 0.01 },
  Metallic = { ksSpecular = 0.95, ksSpecularEXP = 60, fresnelMaxLevel = 0.65, fresnelC = 0.12 },
  Pearl = { ksSpecular = 0.85, ksSpecularEXP = 220, fresnelMaxLevel = 0.85, fresnelC = 0.3 },
  Chrome = { ksSpecular = 1.5, ksSpecularEXP = 500, fresnelMaxLevel = 1, fresnelC = 0.9, ksDiffuse = 0.08 },
  Satin = { ksSpecular = 0.35, ksSpecularEXP = 30, fresnelMaxLevel = 0.2, fresnelC = 0.03 },
  Candy = { ksSpecular = 1.1, ksSpecularEXP = 320, fresnelMaxLevel = 0.9, fresnelC = 0.25 },
}
local SWATCHES = {
  { 0.95, 0.95, 0.95 }, { 0.05, 0.05, 0.06 }, { 0.55, 0.57, 0.60 }, { 0.85, 0.08, 0.10 }, { 1.0, 0.45, 0.05 },
  { 1.0, 0.82, 0.05 }, { 0.35, 0.80, 0.20 }, { 0.05, 0.45, 0.25 }, { 0.10, 0.75, 0.85 }, { 0.05, 0.30, 0.85 },
  { 0.05, 0.10, 0.35 }, { 0.55, 0.20, 0.85 }, { 1.0, 0.35, 0.65 }, { 0.45, 0.25, 0.12 },
}

local function hsv(h, s, v)
  local i = math.floor(h * 6)
  local f = h * 6 - i
  local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
  i = i % 6
  if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
  elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v end
  return v, p, q
end

local function lvDefault()
  return { c1 = { 0.85, 0.08, 0.10 }, c2 = { 0.05, 0.05, 0.06 }, pattern = 1, finish = 1, full = true, strength = 0.7,
    rimsOn = false, rims = { 0.05, 0.05, 0.06 }, calOn = false, cal = { 0.95, 0.75, 0.05 }, on = false }
end

local LV = { cfg = nil, applyTimer = nil, others = {}, tab = 1, hue = 0, sat = 1, val = 1, target = 'c1' }
do
  local ok, all = pcall(JSON.parse, S.livery ~= '' and S.livery or '{}')
  LV.all = (ok and type(all) == 'table') and all or {}
  LV.cfg = LV.all[ac.getCarID(0) or '?'] or lvDefault()
end

local function lvSave()
  LV.all[ac.getCarID(0) or '?'] = LV.cfg
  S.livery = JSON.stringify(LV.all)
end

local function col(t, a) return rgbm(t[1], t[2], t[3], a or 1) end

local function lvMeshes(index, part)
  local root = ac.findNodes('carRoot:' .. index)
  local out = {}
  for _, tex in ipairs(LV_PARTS[part]) do
    local ok, m = pcall(function() return root:findMeshes('{ texture:' .. tex .. ' }') end)
    if ok and m and m:size() > 0 then out[#out + 1] = m end
  end
  return out
end

local function lvDrawPattern(cfg, size)
  local c1, c2 = col(cfg.c1), col(cfg.c2)
  local a = cfg.full and 1 or cfg.strength
  local p = LV_PATTERNS[cfg.pattern] or 'Solid'
  if not cfg.full then display.rect({ pos = vec2(0, 0), size = vec2(size, size), color = col(cfg.c1, a) }) end
  if p == 'Fade' then
    local bands = 48
    for i = 0, bands - 1 do
      local t = i / (bands - 1)
      display.rect({ pos = vec2(0, size * i / bands), size = vec2(size, size / bands + 1),
        color = rgbm(lerp(cfg.c1[1], cfg.c2[1], t), lerp(cfg.c1[2], cfg.c2[2], t), lerp(cfg.c1[3], cfg.c2[3], t), a) })
    end
  elseif p == 'Stripes' then
    for i = 0, 7 do display.rect({ pos = vec2(0, i * size / 8 + size / 32), size = vec2(size, size / 24), color = col(cfg.c2, a) }) end
  elseif p == 'Checker' then
    local n = 12
    for i = 0, n - 1 do for j = 0, n - 1 do
      if (i + j) % 2 == 0 then display.rect({ pos = vec2(i * size / n, j * size / n), size = vec2(size / n, size / n), color = col(cfg.c2, a) }) end
    end end
  elseif p == 'Camo' then
    local seed = 7
    local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
    for _ = 1, 140 do
      local w, h = size * (0.04 + rnd() * 0.12), size * (0.03 + rnd() * 0.08)
      local shade = rnd()
      local c = shade < 0.5 and col(cfg.c2, a) or rgbm(cfg.c1[1] * 0.6, cfg.c1[2] * 0.6, cfg.c1[3] * 0.6, a)
      display.rect({ pos = vec2(rnd() * size, rnd() * size), size = vec2(w, h), color = c })
    end
  elseif p == 'Racing' then
    for _, cx in ipairs({ 0.40, 0.53 }) do display.rect({ pos = vec2(size * cx, 0), size = vec2(size * 0.07, size), color = col(cfg.c2, a) }) end
  elseif p == 'Diagonal' then
    local steps = 64
    for k = -6, 6 do for j = 0, steps - 1 do
      local x = j * size / steps
      local yy = x * 0.55 + k * size / 5
      if yy > -size / 20 and yy < size then display.rect({ pos = vec2(x, yy), size = vec2(size / steps + 1, size / 22), color = col(cfg.c2, a) }) end
    end end
  elseif p == 'Split' then
    display.rect({ pos = vec2(0, size / 2), size = vec2(size, size / 2), color = col(cfg.c2, a) })
  elseif p == 'Forged' then
    local seed = 3
    local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
    display.rect({ pos = vec2(0, 0), size = vec2(size, size), color = rgbm(0.06, 0.06, 0.065, a) })
    for _ = 1, 420 do
      local v = 0.08 + rnd() * 0.14
      display.rect({ pos = vec2(rnd() * size, rnd() * size), size = vec2(size * (0.01 + rnd() * 0.05), size * (0.005 + rnd() * 0.03)), color = rgbm(v, v, v * 1.04, a) })
    end
  elseif p == 'Carbon' then
    local n = 64
    for i = 0, n - 1 do for j = 0, n - 1 do
      local v = ((i + j) % 2 == 0) and 0.07 or 0.13
      display.rect({ pos = vec2(i * size / n, j * size / n), size = vec2(size / n, size / n), color = rgbm(v, v, v * 1.05, a) })
    end end
  end
end

local function lvApplyFinish(meshes, finish)
  local props = LV_FINISH_PROPS[LV_FINISHES[finish] or 'Original']
  if not props then return end
  for _, m in ipairs(meshes) do
    for k, v in pairs(props) do pcall(function() m:setMaterialProperty(k, v) end) end
  end
end

local function lvApply(index, cfg)
  if not cfg or not cfg.on then return 0 end
  local count = 0
  local body = lvMeshes(index, 'body')
  for _, m in ipairs(body) do
    count = count + 1
    pcall(function()
      m:ensureUniqueMaterials()
      m:setMaterialTexture('txDiffuse', {
        textureSize = vec2(1024, 1024),
        background = cfg.full and col(cfg.c1) or nil,
        callback = function() lvDrawPattern(cfg, 1024) end,
      })
    end)
  end
  lvApplyFinish(body, cfg.finish)
  if cfg.rimsOn then
    for _, m in ipairs(lvMeshes(index, 'rims')) do count = count + 1 pcall(function() m:ensureUniqueMaterials() m:setMaterialTexture('txDiffuse', col(cfg.rims)) end) end
  end
  if cfg.calOn then
    for _, m in ipairs(lvMeshes(index, 'calipers')) do count = count + 1 pcall(function() m:ensureUniqueMaterials() m:setMaterialTexture('txDiffuse', col(cfg.cal)) end) end
  end
  return count
end

local function lvPack(cfg)
  if not cfg.on then return 'off' end
  local function c3(t) return string.format('%d,%d,%d', math.floor(t[1] * 255), math.floor(t[2] * 255), math.floor(t[3] * 255)) end
  return table.concat({ c3(cfg.c1), c3(cfg.c2), cfg.pattern, cfg.finish, cfg.full and 1 or 0, math.floor(cfg.strength * 100),
    cfg.rimsOn and 1 or 0, c3(cfg.rims), cfg.calOn and 1 or 0, c3(cfg.cal) }, ',')
end

local function lvUnpack(s)
  if s == 'off' then return { on = false } end
  local n = {}
  for v in s:gmatch('[^,]+') do n[#n + 1] = tonumber(v) or 0 end
  if #n < 22 then return nil end
  local function c(i) return { n[i] / 255, n[i + 1] / 255, n[i + 2] / 255 } end
  return { on = true, c1 = c(1), c2 = c(4), pattern = n[7], finish = n[8], full = n[9] == 1, strength = n[10] / 100,
    rimsOn = n[11] == 1, rims = c(12), calOn = n[15] == 1, cal = c(16) }
end

local liveryEvent = ac.OnlineEvent({
  ac.StructItem.key('acphone.livery.v1'),
  data = ac.StructItem.string(96),
}, function(sender, msg)
  if not sender or sender.index == 0 or not S.liveryShowOthers then return end
  local cfg = lvUnpack(tostring(msg.data))
  if not cfg then return end
  LV.others[sender.index] = cfg
  if cfg.on then lvApply(sender.index, cfg) else SK.skinApply(sender.index, SK.skinActive(sender.index)) end
end)

local function lvBroadcast()
  if S.liverySync then pcall(liveryEvent, { data = lvPack(LV.cfg) }, true) end
end

local function lvCommit()
  lvSave()
  if LV.cfg.on then
    local n = lvApply(0, LV.cfg)
    LV.status = n > 0 and 'Livery applied' or 'This car’s paint wasn’t recognised'
  end
  lvBroadcast()
end

local function lvSchedule()
  LV.cfg.on = true
  if LV.applyTimer then clearTimeout(LV.applyTimer) end
  LV.applyTimer = setTimeout(function() LV.applyTimer = nil lvCommit() end, 0.35)
end

local function lvReset()
  LV.cfg.on = false
  lvSave()
  SK.skinApply(0, SK.skinActive(0))
  lvBroadcast()
  LV.status = 'Back to your skin'
end

-- side-view car preview
local function lvPreview(x, y, w, h)
  local cfg = LV.cfg
  rect(x, y, x + w, y + h, rgbm(0.14, 0.14, 0.16, 1), 18)
  local gy = y + h - 28
  rect(x + 20, gy + 14, x + w - 20, gy + 18, rgbm(0, 0, 0, 0.35), 2)
  local c1 = cfg.on and col(cfg.c1) or rgbm(0.5, 0.5, 0.55, 1)
  local bx1, bx2 = x + 30, x + w - 30
  local by1, by2 = gy - 44, gy - 4
  -- body
  rect(bx1, by1, bx2, by2, c1, 14)
  -- cabin
  ui.drawQuadFilled(P(bx1 + w * 0.22, by1 + 2), P(bx1 + w * 0.32, by1 - 34), P(bx2 - w * 0.30, by1 - 34), P(bx2 - w * 0.12, by1 + 2), A(c1))
  ui.drawQuadFilled(P(bx1 + w * 0.26, by1 - 2), P(bx1 + w * 0.34, by1 - 29), P(bx2 - w * 0.31, by1 - 29), P(bx2 - w * 0.16, by1 - 2), A(rgbm(0.12, 0.16, 0.22, 1)))
  if cfg.on then
    local p = LV_PATTERNS[cfg.pattern]
    if p == 'Stripes' then rect(bx1, by1 + 14, bx2, by1 + 22, col(cfg.c2), 0)
    elseif p == 'Fade' then ui.drawRectFilledMultiColor(P(bx1, by1 + 8), P(bx2, by2), A(col(cfg.c1)), A(col(cfg.c1)), A(col(cfg.c2)), A(col(cfg.c2)))
    elseif p == 'Checker' then for i = 0, 9 do if i % 2 == 0 then rect(bx1 + 20 + i * 14, by1 + 10, bx1 + 34 + i * 14, by1 + 24, col(cfg.c2), 0) end end
    elseif p == 'Camo' then for i = 0, 6 do rect(bx1 + 15 + i * 30, by1 + 6 + (i % 3) * 9, bx1 + 38 + i * 30, by1 + 16 + (i % 3) * 9, col(cfg.c2), 4) end
    elseif p == 'Carbon' then rect(bx1, by1, bx2, by2, rgbm(0.1, 0.1, 0.11, 1), 14) end
  end
  -- shine
  local fin = LV_FINISHES[cfg.finish]
  if fin ~= 'Matte' then rect(bx1 + 10, by1 + 4, bx2 - 10, by1 + 9, rgbm(1, 1, 1, fin == 'Chrome' and 0.5 or 0.18), 3) end
  -- wheels
  for _, wx in ipairs({ bx1 + w * 0.17, bx2 - w * 0.17 }) do
    circle(wx, gy, 19, rgbm(0.05, 0.05, 0.05, 1))
    circle(wx, gy, 11, (cfg.on and cfg.rimsOn) and col(cfg.rims) or rgbm(0.7, 0.7, 0.72, 1))
    circle(wx, gy, 4, rgbm(0.2, 0.2, 0.2, 1))
    if cfg.on and cfg.calOn then rect(wx - 12, gy - 5, wx - 8, gy + 5, col(cfg.cal), 2) end
  end
end

local function colourPicker(id, target, y)
  -- swatches
  local per = 7
  local sw = (SW - 32 - (per - 1) * 8) / per
  for i, c in ipairs(SWATCHES) do
    local cx, cy = 16 + ((i - 1) % per) * (sw + 8) + sw / 2, y + math.floor((i - 1) / per) * (sw + 8) + sw / 2
    local sel = math.abs(target[1] - c[1]) + math.abs(target[2] - c[2]) + math.abs(target[3] - c[3]) < 0.02
    if tap(id .. 'sw' .. i, cx - sw / 2, cy - sw / 2, cx + sw / 2, cy + sw / 2) then
      target[1], target[2], target[3] = c[1], c[2], c[3]
      lvSchedule()
    end
    circle(cx, cy, sw / 2 - 2, col(c))
    if sel then circleLine(cx, cy, sw / 2 + 1, T.white, 2) end
  end
  y = y + 2 * (sw + 8) + 6
  -- hue bar + brightness
  local bx, bw = 16, SW - 32
  local steps = 36
  for i = 0, steps - 1 do
    local r, g, b = hsv(i / steps, 1, 1)
    rect(bx + bw * i / steps, y + 6, bx + bw * (i + 1) / steps + 0.5, y + 22, rgbm(r, g, b, 1), (i == 0 or i == steps - 1) and 8 or 0)
  end
  local nh, ch = W.slider(id .. 'hue', LV.hue, 0, 1, bx, y, bw, T.clear)
  if ch then LV.hue = nh local r, g, b = hsv(LV.hue, LV.sat, LV.val) target[1], target[2], target[3] = r, g, b lvSchedule() end
  y = y + 36
  text('Brightness', 13, 16, y, T.label2)
  local nv, cv = W.slider(id .. 'val', LV.val, 0.05, 1, 100, y - 4, SW - 116)
  if cv then LV.val = nv local r, g, b = hsv(LV.hue, LV.sat, LV.val) target[1], target[2], target[3] = r, g, b lvSchedule() end
  y = y + 30
  text('Saturation', 13, 16, y, T.label2)
  local ns, cs = W.slider(id .. 'sat', LV.sat, 0, 1, 100, y - 4, SW - 116)
  if cs then LV.sat = ns local r, g, b = hsv(LV.hue, LV.sat, LV.val) target[1], target[2], target[3] = r, g, b lvSchedule() end
  return y + 34
end

function APPMOD.Livery.root()
  local scr = { title = 'Livery' }
  function scr.draw()
    bgFill()
    local cfg = LV.cfg
    local s = scrollBegin('livery', 50, BOTTOM)
    local y = largeTitle('Livery', 96, s.y)
    textFit(ac.getCarName(0) or '', 14, 16, y - 10, SW - 32, T.label2)
    y = y + 18
    lvPreview(16, y, SW - 32, 150)
    y = y + 162
    if LV.status then text(LV.status, 13, SW / 2, y, T.label2, F.r, 0.5) y = y + 22 end
    local bw = (SW - 44) / 2
    if W.button('lv.apply', cfg.on and 'Re-apply' or 'Paint my car', 16, y, bw, 40, 'filled') then cfg.on = true lvCommit() end
    if W.button('lv.reset', 'Back to skin', 28 + bw, y, bw, 40, 'danger') then lvReset() end
    y = y + 54
    LV.tab = W.segmented('lv.tab', { 'Body', 'Rims', 'Calipers' }, LV.tab, 16, y, SW - 32)
    y = y + 48
    if LV.tab == 1 then
      y = W.sectionHeader('Main colour', y)
      y = colourPicker('c1', cfg.c1, y)
      y = W.sectionHeader('Pattern', y + 4)
      local clicked
      clicked, y = chipFlow('lvp', LV_PATTERNS, 16, y, SW - 32, function(l) return LV_PATTERNS[cfg.pattern] == l end)
      if clicked then for i, n in ipairs(LV_PATTERNS) do if n == clicked then cfg.pattern = i end end lvSchedule() end
      if LV_NEEDS2[LV_PATTERNS[cfg.pattern] or ''] then
        y = W.sectionHeader('Second colour', y + 6)
        local per = 7
        local sw = (SW - 32 - (per - 1) * 8) / per
        for i, c in ipairs(SWATCHES) do
          local cx, cy = 16 + ((i - 1) % per) * (sw + 8) + sw / 2, y + math.floor((i - 1) / per) * (sw + 8) + sw / 2
          if tap('c2sw' .. i, cx - sw / 2, cy - sw / 2, cx + sw / 2, cy + sw / 2) then cfg.c2 = { c[1], c[2], c[3] } lvSchedule() end
          circle(cx, cy, sw / 2 - 2, col(c))
          if math.abs(cfg.c2[1] - c[1]) + math.abs(cfg.c2[2] - c[2]) + math.abs(cfg.c2[3] - c[3]) < 0.02 then circleLine(cx, cy, sw / 2 + 1, T.white, 2) end
        end
        y = y + 2 * (sw + 8) + 6
      end
      y = W.sectionHeader('Finish', y + 6)
      clicked, y = chipFlow('lvf', LV_FINISHES, 16, y, SW - 32, function(l) return LV_FINISHES[cfg.finish] == l end)
      if clicked then for i, n in ipairs(LV_FINISHES) do if n == clicked then cfg.finish = i end end lvSchedule() end
      y = y + 6
      W.groupBg(y, 1)
      local full = W.toggleRow('lv.full', 'Full repaint', cfg.full, y, { first = true, last = true })
      if full ~= cfg.full then cfg.full = full lvSchedule() end
      y = y + 46
      if not cfg.full then
        rect(LIST.x, y + 8, LIST.x + LIST.w, y + 82, T.cell, 12)
        local v, ch = W.sliderRow('lv.str', 'Tint over skin', cfg.strength * 100, 10, 100, '%d%%', y + 8, { last = true })
        if ch then cfg.strength = v / 100 lvSchedule() end
        y = y + 90
      end
      y = W.sectionFooter(cfg.full and 'Full repaint covers the whole skin in your colours.' or 'Tint keeps the skin’s decals and blends your colour over it.', y)
    elseif LV.tab == 2 then
      W.groupBg(y, 1)
      local on = W.toggleRow('lv.rims', 'Paint rims', cfg.rimsOn, y, { first = true, last = true })
      if on ~= cfg.rimsOn then cfg.rimsOn = on lvSchedule() end
      y = y + 58
      if cfg.rimsOn then y = colourPicker('rims', cfg.rims, y) end
    else
      W.groupBg(y, 1)
      local on = W.toggleRow('lv.cal', 'Paint calipers', cfg.calOn, y, { first = true, last = true })
      if on ~= cfg.calOn then cfg.calOn = on lvSchedule() end
      y = y + 58
      if cfg.calOn then y = colourPicker('cal', cfg.cal, y) end
    end
    -- saved looks + share codes
    y = W.sectionHeader('My liveries', y + 10)
    local okp, presets = pcall(JSON.parse, S.liveryPresets)
    presets = (okp and type(presets) == 'table') and presets or {}
    if #presets > 0 then
      W.groupBg(y, #presets, 56)
      for i, pr in ipairs(presets) do
        local pc = lvUnpack(pr.code or '')
        if W.row('lvp' .. i, pr.name, y, { h = 56, sub = pc and ((LV_PATTERNS[pc.pattern] or '') .. ' · ' .. (LV_FINISHES[pc.finish] or '')) or '', tap = true, first = i == 1, last = i == #presets }) and pc then
          local carNow = LV.cfg
          for k, v2 in pairs(pc) do carNow[k] = v2 end
          lvCommit()
        end
        if pc then
          circle(SW - 118, y + 28, 10, col(pc.c1))
          if LV_NEEDS2[LV_PATTERNS[pc.pattern] or ''] then circle(SW - 100, y + 28, 10, col(pc.c2)) end
        end
        if W.button('lvpd' .. i, '@TRASH', SW - 74, y + 12, 40, 32, 'danger') then
          table.remove(presets, i)
          S.liveryPresets = JSON.stringify(presets)
          break
        end
        y = y + 56
      end
      y = y + 10
    end
    local enter
    LV.newName, enter = W.field('lv.pname', LV.newName or '', 'Name this look', 16, y, SW - 32 - 96, 40, { round = 12, bg = T.cell })
    if (W.button('lv.psave', 'Save', SW - 104, y, 88, 40, 'filled') or enter) then
      local nm = trim(LV.newName or '') ~= '' and trim(LV.newName) or ('Livery ' .. (#presets + 1))
      local copy = {}
      for k, v2 in pairs(LV.cfg) do copy[k] = v2 end
      copy.on = true
      presets[#presets + 1] = { name = nm, code = lvPack(copy) }
      S.liveryPresets = JSON.stringify(presets)
      LV.newName = ''
      toast('Livery saved', nm, '💾')
    end
    y = y + 52
    local bw2 = (SW - 44) / 2
    if W.button('lv.copy', '@COPY Copy code', 16, y, bw2, 40, 'gray') then
      local copy = {}
      for k, v2 in pairs(LV.cfg) do copy[k] = v2 end
      copy.on = true
      ac.setClipboardText('ACPL1:' .. lvPack(copy))
      toast('Livery code copied', 'Paste it in chat for your friends', '📋')
    end
    if W.button('lv.paste', '@PASTE Paste code', 28 + bw2, y, bw2, 40, 'gray') then
      local clip = tostring(ui.getClipboardText() or '')
      local code = clip:match('ACPL1:([%d,]+)')
      local pc = code and lvUnpack(code)
      if pc and pc.on then
        for k, v2 in pairs(pc) do LV.cfg[k] = v2 end
        lvCommit()
        toast('Livery imported', 'Applied from your clipboard', '📋')
      else
        toast('No livery code', 'Copy an ACPL1: code first', '⚠️')
      end
    end
    y = y + 50
    y = W.sectionFooter('Share codes work through chat or Discord. Copy, send, and your friend taps Paste.', y)
    y = W.sectionHeader('Online', y + 10)
    W.groupBg(y, 2)
    local v = W.toggleRow('lv.sync', 'Share my livery', S.liverySync, y, { first = true })
    if v ~= S.liverySync then S.liverySync = v if v then lvBroadcast() end end
    S.liveryShowOthers = W.toggleRow('lv.oth', 'Show friends’ liveries', S.liveryShowOthers, y + 46, { last = true })
    y = W.sectionFooter('Friends with AC Phone see your paint live. Swapping skins replaces the livery until you re-apply it.', y + 92)
    scrollEnd(s, y + 20)
    navBar('Livery', { large = true }, s.y)
  end
  return scr
end

LIVERY_API.apply = lvApply
LIVERY_API.broadcast = lvBroadcast
LIVERY_API.cfg = function() return LV.cfg end
end

-- ===========================================================================
-- THEMES
-- ===========================================================================


do
function APPMOD.Music.root()
  local scr = { title = 'Music' }
  function scr.draw()
    local m, playing = MEDIA.now()
    bgFill()
    -- blurred-looking colour wash from the accent
    ui.drawRectFilledMultiColor(P(0, 0), P(SW, SH * 0.7), A(mix(accent(), T.bg, 0.55)), A(mix(accent(), T.bg, 0.7)), A(T.bg), A(T.bg))
    local cs = SW - 72
    local y = 92
    MEDIA.cover(m, 36, y, 36 + cs, y + cs, 22)
    y = y + cs + 26
    if m then
      textFit(m.title, 22, 36, y, SW - 72, T.white, F.b)
      textFit((m.artist ~= '' and m.artist or 'Unknown artist') .. (m.album ~= '' and (' · ' .. m.album) or ''), 15, 36, y + 32, SW - 72, T.label2, F.m)
      y = y + 70
      local dur, pos = m.trackDuration or -1, m.trackPosition or -1
      local t = (dur > 0 and pos >= 0) and clamp(pos / dur, 0, 1) or 0
      rect(36, y, SW - 36, y + 5, rgbm(1, 1, 1, 0.18), 3)
      rect(36, y, 36 + (SW - 72) * t, y + 5, T.white, 3)
      circle(36 + (SW - 72) * t, y + 2.5, 6, T.white)
      text(MEDIA.fmtTime(pos), 12, 36, y + 12, T.label2, F.num)
      text(dur > 0 and ('-' .. MEDIA.fmtTime(dur - pos)) or '', 12, SW - 36, y + 12, T.label2, F.num, 1)
      y = y + 54
    else
      text('Not playing', 22, 36, y, T.white, F.b)
      textBox('Start Spotify, YouTube, Apple Music or any Windows player. The play button below also resumes your last player.', 14, 36, y + 34, SW - 36, y + 80, T.label2)
      y = y + 100
    end
    MEDIA.controls('mu.', SW / 2, y + 10, 34, T.white)
    y = y + 70
    if MEDIA.button('mu.vd', 'VOLUME_LOW', 60, y, 20, T.label2) then MEDIA.volDown() end
    rect(90, y - 2, SW - 90, y + 2, rgbm(1, 1, 1, 0.18), 2)
    if MEDIA.button('mu.vu', 'VOLUME_HIGH', SW - 60, y, 20, T.label2) then MEDIA.volUp() end
    navBar('', {})
  end
  return scr
end

local function personalizeHome()
  local scr = { title = 'Home Screen' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('phome', 94, BOTTOM)
    local y = 104
    local list = {}
    for _, a in ipairs(APPMOD.APPS) do if a.id ~= 'settings' then list[#list + 1] = a end end
    W.groupBg(y, #list)
    for i, a in ipairs(list) do
      local shown = not listHas(S.hiddenApps, a.id)
      local v = W.toggleRow('ph' .. a.id, a.name, shown, y, { icon = a.icon, iconBg = a.c2, first = i == 1, last = i == #list })
      if v ~= shown then S.hiddenApps = listToggle(S.hiddenApps, a.id) end
      y = y + 46
    end
    y = W.sectionFooter('Hidden apps stay available from Control Centre, Settings and search.', y)
    scrollEnd(s, y + 20)
    navBar('Home Screen', { back = 'Personalize' })
  end
  return scr
end

function APPMOD.Themes.root()
  local scr = { title = 'Personalize' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('themes', 50, BOTTOM)
    local y = largeTitle('Personalize', 96, s.y)
    -- live preview of the current look
    local pw, ph = 150, 300
    local px = SW / 2 - pw / 2
    rect(px - 5, y - 5, px + pw + 5, y + ph + 5, rgbm(0.2, 0.2, 0.22, 1), 30)
    local wp = WALL.path()
    local th = THEME or THEMES[1]
    if not (wp and WALL.cover(wp, px, y, px + pw, y + ph, 26)) then
      rect(px, y, px + pw, y + ph, th.bottom, 26)
      ui.drawRectFilledMultiColor(P(px, y + 26), P(px + pw, y + ph - 26), A(th.top), A(th.top), A(th.bottom), A(th.bottom))
    elseif S.wallDim > 0 then
      rect(px, y, px + pw, y + ph, rgbm(0, 0, 0, S.wallDim), 26)
    end
    rect(px + pw / 2 - 22, y + 8, px + pw / 2 + 22, y + 20, rgbm(0, 0, 0, 1), 6)
    text(os.date('%H:%M'), 30, px + pw / 2, y + 40, T.white, F.numl, 0.5)
    for k = 0, 7 do
      local ix = px + 16 + (k % 4) * 31
      local iy = y + 120 + math.floor(k / 4) * 40
      local a = APPMOD.APPS[k + 1]
      if a then
        if S.iconStyle == 2 then rect(ix, iy, ix + 24, iy + 24, rgbm(0.08, 0.08, 0.09, 0.62), 7)
        elseif S.iconStyle == 3 then circle(ix + 12, iy + 12, 11, rgbm(1, 1, 1, 0.08))
        else rect(ix, iy, ix + 24, iy + 24, a.c2, 7) end
        local g = leadingIcon(a.icon)
        if g then glyph(g, ix + 5, iy + 5, 14, S.iconStyle == 2 and mix(a.c1, T.white, 0.35) or T.white) end
      end
    end
    rect(px + 14, y + ph - 34, px + pw - 14, y + ph - 18, accent(), 8)
    text('Aa  ' .. (FONT_FAMILIES[S.font] or FONT_FAMILIES[1]).name, 13, px + pw / 2, y + ph - 64, T.white, F.sb, 0.5)
    y = y + ph + 24

    -- themes strip
    y = W.sectionHeader('Theme', y)
    local cw, ch = 96, 150
    local perRow = 3
    local gap = (SW - 32 - cw * perRow) / (perRow - 1)
    for i, t in ipairs(THEMES) do
      local c, r = (i - 1) % perRow, math.floor((i - 1) / perRow)
      local x, yy = 16 + c * (cw + gap), y + r * (ch + 36)
      local fired, pressed = tap('theme' .. i, x, yy, x + cw, yy + ch + 26)
      local sel = S.theme == i
      rect(x - 3, yy - 3, x + cw + 3, yy + ch + 3, sel and t.accent or rgbm(0.18, 0.18, 0.2, 1), 18)
      rect(x, yy, x + cw, yy + ch, t.bottom, 16)
      ui.drawRectFilledMultiColor(P(x, yy + 16), P(x + cw, yy + ch - 16), A(t.top), A(t.top), A(t.bottom), A(t.bottom))
      rect(x + 10, yy + ch - 30, x + cw - 10, yy + ch - 18, t.accent, 6)
      rect(x + 10, yy + ch - 50, x + cw * 0.6, yy + ch - 38, t.cell, 6)
      if sel then circle(x + cw - 14, yy + 14, 9, t.accent) glyph('CONFIRM', x + cw - 20, yy + 8, 12, T.white) end
      if pressed then rect(x, yy, x + cw, yy + ch, rgbm(1, 1, 1, 0.1), 16) end
      textFit(t.name, 13, x + cw / 2, yy + ch + 6, cw, T.label, F.sb, 0.5)
      if fired then applyTheme(i) end
    end
    y = y + math.ceil(#THEMES / perRow) * (ch + 36) + 6

    -- wallpaper
    y = W.sectionHeader('Wallpaper', y)
    local modes = { 'theme', 'car', 'track', 'custom' }
    local labels = { 'Theme', 'My car', 'Track', 'Photo' }
    local cur = 1
    for i, m in ipairs(modes) do if S.wallMode == m then cur = i end end
    local ni = W.segmented('wp.mode', labels, cur, 16, y, SW - 32)
    if ni ~= cur then S.wallMode = modes[ni] end
    y = y + 44
    if S.wallMode == 'custom' then
      local saved = WALL.saved()
      local tw = (SW - 32 - 3 * 8) / 4
      for i = 1, math.min(#saved, 7) do
        local x = 16 + ((i - 1) % 4) * (tw + 8)
        local yy = y + math.floor((i - 1) / 4) * (tw * 1.7 + 8)
        if not WALL.cover(saved[i], x, yy, x + tw, yy + tw * 1.7, 10) then rect(x, yy, x + tw, yy + tw * 1.7, T.cell, 10) end
        if saved[i] == S.wallPath then rectLine(x, yy, x + tw, yy + tw * 1.7, accent(), 10, 3) end
        if tap('wps' .. i, x, yy, x + tw, yy + tw * 1.7) then S.wallPath = saved[i] end
      end
      local n = math.min(#saved, 7)
      local x = 16 + (n % 4) * (tw + 8)
      local yy = y + math.floor(n / 4) * (tw * 1.7 + 8)
      local fired, pressed = tap('wp.add', x, yy, x + tw, yy + tw * 1.7)
      rect(x, yy, x + tw, yy + tw * 1.7, pressed and T.cellHi or T.cell, 10)
      rectLine(x, yy, x + tw, yy + tw * 1.7, T.border or T.sep, 10, 1.5)
      glyph('PLUS', x + tw / 2 - 12, yy + tw * 0.85 - 12, 24, accent())
      if fired then WALL.import() end
      y = y + (math.floor(n / 4) + 1) * (tw * 1.7 + 8) + 4
      y = W.sectionFooter('Pick any image on your PC, 4K works great. It’s copied into the phone so it stays.', y)
    elseif S.wallMode ~= 'theme' and not WALL.path() then
      y = W.sectionFooter(S.wallMode == 'car' and 'This skin has no preview image yet. Content Manager can generate one.' or 'This track has no preview image.', y)
    end
    if S.wallMode ~= 'theme' then
      rect(LIST.x, y + 4, LIST.x + LIST.w, y + 78, T.cell, 14)
      local v, ch2 = W.sliderRow('wp.dim', 'Dim', S.wallDim * 100, 0, 80, '%d%%', y + 4, { last = true })
      if ch2 then S.wallDim = v / 100 end
      y = y + 92
    end

    -- type & icons
    y = W.sectionHeader('Font', y + 4)
    local fl = {}
    for i, f in ipairs(FONT_FAMILIES) do fl[i] = f.name end
    local nf = W.segmented('pf.font', fl, S.font or 1, 16, y, SW - 32)
    if nf ~= S.font then S.font = nf buildFonts() end
    y = y + 44
    y = W.sectionHeader('App icons', y + 8)
    S.iconStyle = W.segmented('pf.icons', { 'Colour', 'Glass', 'Minimal' }, S.iconStyle or 1, 16, y, SW - 32)
    y = y + 52
    W.groupBg(y, 3)
    local v = W.toggleRow('th.thick', 'Bold text', S.thick, y, { first = true })
    if v ~= S.thick then S.thick = v buildFonts() end
    S.motifs = W.toggleRow('th.motif', 'Theme symbols', S.motifs, y + 46)
    if W.row('th.home', 'Home Screen apps', y + 92, { chevron = true, last = true }) then navPush(personalizeHome()) end
    y = y + 150

    y = W.sectionHeader('Accent colour', y)
    rect(LIST.x, y, LIST.x + LIST.w, y + 64, T.cell, 14)
    local opts = { { 0, (THEME or THEMES[1]).accent } }
    for i, a in ipairs(ACCENTS) do opts[#opts + 1] = { i, a.c } end
    local step = (LIST.w - 20) / #opts
    for k, o in ipairs(opts) do
      local cx = LIST.x + 10 + step * (k - 0.5)
      if tap('tacc' .. k, cx - 22, y + 8, cx + 22, y + 56) then S.accent = o[1] end
      circle(cx, y + 32, 16, o[2])
      if o[1] == 0 then text('T', 12, cx, y + 24, T.white, F.b, 0.5) end
      if S.accent == o[1] then circleLine(cx, y + 32, 21, o[2], 2.5) end
    end
    y = y + 84
    y = W.sectionHeader('Action bar', y)
    S.barStyle = W.segmented('pf.bar', { 'Pro', 'Minimal' }, S.barStyle or 1, 16, y, SW - 32)
    y = y + 60
    scrollEnd(s, y + 20)
    navBar('Personalize', { large = true }, s.y)
  end
  return scr
end

-- ===========================================================================
-- CUT-UP (points + leaderboard)
-- ===========================================================================

local function boardRows(kind)
  local rows = {}
  local myName = ac.getDriverName(0) or 'You'
  if kind == 3 then
    local ok, crew = pcall(JSON.parse, S.hesiCrew)
    crew = (ok and type(crew) == 'table') and crew or {}
    crew[myName] = math.max(crew[myName] or 0, S.hesiPB)
    for name, pb in pairs(crew) do rows[#rows + 1] = { name = name, score = pb, me = name == myName } end
  else
    rows[#rows + 1] = { name = myName, me = true, score = kind == 1 and HESI.run or HESI.sessionBest, running = HESI.running, mult = HESI.mult, total = HESI.sessionTotal }
    for _, b in pairs(HESI.board) do
      if clock() - b.at < 120 then
        rows[#rows + 1] = { name = b.name, score = kind == 1 and b.run or b.best, running = b.running, mult = b.mult, total = b.total }
      end
    end
  end
  table.sort(rows, function(a, b) return a.score > b.score end)
  return rows
end

function APPMOD.CutUp.root()
  local scr = { title = 'Cut-Up' }
  local tab = 1
  function scr.draw()
    bgFill()
    local s = scrollBegin('cutup', 50, BOTTOM)
    local y = largeTitle('Cut-Up', 96, s.y)
    -- hero card
    local ac1 = accent()
    local hot = HESI.running and clamp(HESI.mult / 10, 0, 1) or 0
    rect(16, y, SW - 16, y + 178, mix(T.cell, rgbm(1, 0.3, 0.1, 1), hot * 0.35), 22)
    rectLine(16, y, SW - 16, y + 178, A(ac1, 0.5 + hot * 0.5), 22, 2)
    if HESI.running then
      text('@BURN RUN IN PROGRESS', 12, 34, y + 14, ac1, F.b)
      text(HESI.fmt(HESI.run), 46, 34, y + 30, T.white, F.numb)
      if HESI.tier() ~= '' then text(HESI.tier(), 12, 36, y + 86, rgbm(1, 0.8, 0.25, 1), F.b) end
      text(string.format('x%.1f', HESI.mult), 30, SW - 34, y + 40, rgbm(1, 0.8, 0.2, 1), F.numb, 1)
      rect(34, y + 104, SW - 34, y + 112, rgbm(1, 1, 1, 0.1), 4)
      rect(34, y + 104, 34 + (SW - 68) * clamp(HESI.combo / HESI.comboMax, 0, 1), y + 112, ac1, 4)
      text('Combo', 11, 34, y + 116, T.label2, F.m)
      textBox('Slow under 30 km/h for 3 seconds to BANK. Crash and the run is gone.', 12, 34, y + 136, SW - 34, y + 172, T.label2)
    else
      glyph('BURN', 32, y + 24, 44, ac1)
      text('Ready to run', 22, 92, y + 26, T.white, F.b)
      text('Go over ' .. HESI.startSpeed .. ' km/h to start', 13, 92, y + 56, T.label2)
      if HESI.lastBank > 0 then text('Last banked  ' .. HESI.fmt(HESI.lastBank), 14, 34, y + 104, rgbm(0.4, 1, 0.55, 1), F.sb) end
      textBox('Weave through traffic. Near misses, close calls, lane splits and oncoming passes stack your multiplier.', 12, 34, y + 128, SW - 34, y + 172, T.label2)
    end
    y = y + 192
    local lr = HESI.lastRun
    if lr and not HESI.running then
      rect(16, y, SW - 16, y + 132, T.cell, 18)
      if S.thick then rectLine(16, y, SW - 16, y + 132, T.border, 18, 1.5) end
      text(lr.crashed and '@COLLISION LAST RUN · CRASHED' or (lr.pb and '@TROPHY LAST RUN · NEW PB' or '@CONFIRM LAST RUN · BANKED'), 11, 32, y + 14,
        lr.crashed and T.red or (lr.pb and T.yellow or T.green), F.b)
      text(HESI.fmt(lr.score), 30, 32, y + 32, T.white, F.numb)
      text(lr.at, 12, SW - 32, y + 16, T.label2, F.num, 1)
      local cells = {
        { string.format('%d:%02d', math.floor(lr.time / 60), math.floor(lr.time % 60)), 'TIME' },
        { tostring(math.floor(lr.top)), 'TOP KM/H' },
        { string.format('x%.1f', lr.maxMult), 'BEST MULT' },
        { tostring(lr.near + lr.close), 'NEAR/CLOSE' },
        { tostring(lr.split), 'SPLITS' },
      }
      local cw = (SW - 64) / #cells
      for i, c in ipairs(cells) do
        local x = 32 + (i - 1) * cw
        text(c[1], 17, x, y + 82, T.white, F.num)
        text(c[2], 9, x, y + 106, T.label2, F.b)
      end
      y = y + 146
    end
    -- stat tiles
    local tw = (SW - 32 - 24) / 3
    local stats = { { 'PERSONAL BEST', HESI.fmt(S.hesiPB) }, { 'SESSION BEST', HESI.fmt(HESI.sessionBest) }, { 'BANKED', HESI.fmt(S.hesiTotal) } }
    for i, st in ipairs(stats) do
      local x = 16 + (i - 1) * (tw + 12)
      rect(x, y, x + tw, y + 66, T.cell, 14)
      if S.thick then rectLine(x, y, x + tw, y + 66, T.border, 14, 1.5) end
      text(st[1], 9, x + 10, y + 10, T.label2, F.b)
      textFit(st[2], 19, x + 10, y + 30, tw - 20, T.white, F.numb)
    end
    y = y + 82
    tab = W.segmented('cu.tab', { 'Live', 'Session', 'All-time' }, tab, 16, y, SW - 32)
    y = y + 46
    local rows = boardRows(tab)
    rect(LIST.x, y, LIST.x + LIST.w, y + math.max(1, #rows) * 54, T.cell, 14)
    if S.thick then rectLine(LIST.x, y, LIST.x + LIST.w, y + math.max(1, #rows) * 54, T.border, 14, 1.5) end
    for i, r in ipairs(rows) do
      local yy = y + (i - 1) * 54
      if r.me then rect(LIST.x, yy, LIST.x + LIST.w, yy + 54, A(ac1, 0.14), 14) end
      local medal = i == 1 and '🥇' or (i == 2 and '🥈' or (i == 3 and '🥉' or tostring(i)))
      text(medal, i <= 3 and 20 or 15, LIST.x + 24, yy + (i <= 3 and 13 or 16), T.label, F.b, 0.5)
      avatar(r.name, LIST.x + 44, yy + 10, 34)
      textFit(r.name .. (r.me and '  (you)' or ''), 15, LIST.x + 88, yy + 9, LIST.w - 200, T.label, F.sb)
      local sub = tab == 1 and (r.running and string.format('🔥 running · x%.1f', r.mult or 1) or 'idle') or (tab == 2 and ('banked ' .. HESI.fmt(r.total or 0)) or 'personal best')
      textFit(sub, 12, LIST.x + 88, yy + 30, LIST.w - 200, r.running and ac1 or T.label2)
      text(HESI.fmt(r.score), 17, LIST.x + LIST.w - 14, yy + 16, T.white, F.numb, 1)
      if i < #rows then line(LIST.x + 88, yy + 54, LIST.x + LIST.w, yy + 54, T.sep, 1) end
    end
    y = y + math.max(1, #rows) * 54 + 6
    y = W.sectionFooter('Everyone with AC Phone shows here live. All-time bests are remembered on this PC.', y)
    -- settings
    W.groupBg(y + 6, 2)
    S.hesiOn = W.toggleRow('cu.on', 'Points system', S.hesiOn, y + 6, { first = true, icon = '🔥', iconBg = rgbm(1, 0.4, 0.1, 1) })
    local ab = W.toggleRow('cu.bar', 'Action bar on screen', S.actionBar, y + 52, { last = true, icon = '📊', iconBg = ac1 })
    if ab ~= S.actionBar then S.actionBar = ab ac.setWindowOpen('actionbar', ab) end
    y = y + 112
    -- scoring guide
    y = W.sectionHeader('How points work', y + 4)
    local guide = { { 'overtake', 'Pass traffic' }, { 'near', 'Pass within a lane' }, { 'close', 'Pass with inches to spare' },
      { 'oncoming', 'Pass oncoming traffic' }, { 'split', 'Thread between two cars' }, { 'slip', 'Draft close behind a car' }, { 'trap', 'Hit 260 km/h' } }
    rect(LIST.x, y, LIST.x + LIST.w, y + #guide * 44, T.cell, 14)
    for i, g in ipairs(guide) do
      local e = HESI_EVENTS[g[1]]
      local yy = y + (i - 1) * 44
      rect(LIST.x + 14, yy + 14, LIST.x + 20, yy + 30, e.color, 3)
      text(e.name, 13, LIST.x + 30, yy + 6, T.label, F.b)
      text(g[2], 12, LIST.x + 30, yy + 24, T.label2)
      text('+' .. e.pts .. '  ·  +' .. string.format('%.1f', e.mult) .. 'x', 12, LIST.x + LIST.w - 14, yy + 14, e.color, F.sb, 1)
    end
    y = y + #guide * 44
    y = W.sectionFooter('Points scale with your speed and multiplier (up to x20). The multiplier fades if you go 7 seconds without a pass.', y + 4)
    scrollEnd(s, y + 20)
    navBar('Cut-Up', { large = true }, s.y)
  end
  return scr
end
end
-- ===========================================================================
-- App registry
-- ===========================================================================

local APPS = {
  { id = 'messages', name = 'Messages', icon = '@CHAT', c1 = rgbm(0.35, 0.90, 0.40, 1), c2 = rgbm(0.10, 0.70, 0.25, 1), root = APPMOD.Messages.root, badge = totalUnread },
  { id = 'friends',  name = 'Friends',  icon = '@GROUP', c1 = rgbm(0.30, 0.65, 1.00, 1), c2 = rgbm(0.05, 0.40, 0.95, 1), root = APPMOD.Friends.root },
  { id = 'camera',   name = 'Camera',   icon = '@CAMERA', c1 = rgbm(0.62, 0.62, 0.66, 1), c2 = rgbm(0.35, 0.35, 0.38, 1), root = APPMOD.Camera.root },
  { id = 'walk',     name = 'Walk',     icon = '@PERSON', c1 = rgbm(1.00, 0.70, 0.25, 1), c2 = rgbm(0.95, 0.45, 0.05, 1), root = APPMOD.Walk.root },
  { id = 'video',    name = 'Video',    icon = '@CLAPPERBOARD', c1 = rgbm(1.00, 0.40, 0.40, 1), c2 = rgbm(0.85, 0.12, 0.18, 1), root = APPMOD.Video.root },
  { id = 'chase',    name = 'Chase Cam', icon = '@CAR_FRONT', c1 = rgbm(0.70, 0.45, 1.00, 1), c2 = rgbm(0.45, 0.20, 0.85, 1), root = APPMOD.Chase.root },
  { id = 'plates',   name = 'Plates',   icon = '@TAG', c1 = rgbm(1.00, 0.88, 0.35, 1), c2 = rgbm(0.95, 0.65, 0.05, 1), root = APPMOD.Plates.root },
  { id = 'skins',    name = 'Skins',    icon = '@PHOTOGRAPH', c1 = rgbm(1.00, 0.45, 0.70, 1), c2 = rgbm(0.90, 0.15, 0.45, 1), root = APPMOD.Skins.root },
  { id = 'maps',     name = 'Maps',     icon = '@MAP', c1 = rgbm(0.40, 0.85, 0.55, 1), c2 = rgbm(0.10, 0.55, 0.85, 1), root = APPMOD.Maps.root },
  { id = 'hud',      name = 'HUD',      icon = '@SPEEDOMETER', c1 = rgbm(0.35, 0.35, 0.40, 1), c2 = rgbm(0.10, 0.10, 0.12, 1), root = APPMOD.Hud.root },
  { id = 'livery',   name = 'Livery',   icon = '@PALETTE', c1 = rgbm(1.00, 0.55, 0.30, 1), c2 = rgbm(0.85, 0.20, 0.50, 1), root = APPMOD.Livery.root },
  { id = 'cutup',    name = 'Cut-Up',   icon = '@BURN', c1 = rgbm(1.00, 0.55, 0.10, 1), c2 = rgbm(0.85, 0.10, 0.05, 1), root = APPMOD.CutUp.root },
  { id = 'themes',   name = 'Personalize',   icon = '@SLIDERS', c1 = rgbm(0.95, 0.45, 0.95, 1), c2 = rgbm(0.40, 0.20, 0.85, 1), root = APPMOD.Themes.root },
  { id = 'music',    name = 'Music',    icon = '@MUSIC', c1 = rgbm(1.00, 0.36, 0.45, 1), c2 = rgbm(0.86, 0.10, 0.30, 1), root = APPMOD.Music.root },
  { id = 'weather',  name = 'Weather',  icon = '@WEATHER_FEW_CLOUDS', c1 = rgbm(0.45, 0.75, 1.00, 1), c2 = rgbm(0.15, 0.45, 0.90, 1), root = APPMOD.Weather.root },
  { id = 'library',  name = 'Apps',     icon = '@APPS', c1 = rgbm(0.45, 0.50, 1.00, 1), c2 = rgbm(0.25, 0.25, 0.80, 1), root = APPMOD.Library.root },
  { id = 'settings', name = 'Settings', icon = '@SETTINGS', c1 = rgbm(0.60, 0.60, 0.64, 1), c2 = rgbm(0.36, 0.36, 0.40, 1), root = APPMOD.Settings.root, badge = function() return (UPD.latest and tonumber(UPD.latest.build) and tonumber(UPD.latest.build) > BUILD and UPD.state ~= 'ready') and 1 or 0 end },
}
local APP_BY_ID = {}
APPMOD.APPS = APPS
for _, a in ipairs(APPS) do APP_BY_ID[a.id] = a end
local DOCK = { 'messages', 'music', 'camera', 'settings' }
local GRID = { 'cutup', 'maps', 'friends', 'walk', 'video', 'chase', 'livery', 'skins', 'plates', 'hud', 'weather', 'themes', 'library' }

local appIconRects = {}   -- id -> {x, y, size} for open/close zoom

local function openApp(id)
  local app = APP_BY_ID[id]
  if not app then return end
  NAV.app = app
  NAV.stack = { app.root() }
  local r = appIconRects[id]
  NAV.trans = { kind = 'open', t = 0, icon = r }
end

local function closeApp()
  if not NAV.app then return end
  NAV.trans = { kind = 'close', t = 0, icon = appIconRects[NAV.app.id], app = NAV.app, stack = NAV.stack }
  for _, scr in ipairs(NAV.stack) do if scr.onClose then scr.onClose(scr) end end
  if NAV.app.id == 'camera' and CAM.mode == 'photo' then camRelease() end
  NAV.app = nil
  CHAT.open = nil
end

APPMOD.Messages.openRoot = function()
  if not NAV.app or NAV.app.id ~= 'messages' then
    NAV.app = APP_BY_ID.messages
    NAV.stack = { APPMOD.Messages.root() }
  else
    while #NAV.stack > 1 do table.remove(NAV.stack) end
  end
end
APPMOD.Camera.close = closeApp

-- test hook (only active inside the offline test harness)
if rawget(_G, '__ACPHONE_TEST') then
  local T_ = rawget(_G, '__ACPHONE_TEST')
  T_.openApp, T_.closeApp, T_.APPS, T_.NAV, T_.CAM, T_.navPop = openApp, closeApp, APPS, NAV, CAM, navPop
  T_.addMessage, T_.threadScreen, T_.navPush, T_.setMinimized, T_.PHONE = addMessage, threadScreen, navPush, setMinimized, PHONE
  T_.walkStart, T_.videoStart, T_.S, T_.IN, T_.UPD = walkStart, videoStart, S, IN, UPD
  T_.HESI, T_.applyTheme, T_.buildFonts = HESI, applyTheme, buildFonts
end

UPD.openScreen = function()
  openApp('settings')
  NAV.trans = nil
  navPush(UPD.screen())
  NAV.trans = nil
end
do

-- ===========================================================================
-- Phone chrome: wallpaper, status bar, dynamic island, banners
-- ===========================================================================

local POWER = { battery = nil, charging = true }
if ac.onPowerStateUpdate then
  pcall(ac.onPowerStateUpdate, function(st)
    POWER.battery = st.batteryPercentage
    POWER.charging = st.powerSource ~= 'dc'
  end)
end

local SCATTER = {}
do
  local seed = 11
  local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
  for i = 1, 16 do SCATTER[i] = { x = rnd(), y = rnd(), s = 18 + rnd() * 26, r = (rnd() - 0.5) * 50, a = 0.10 + rnd() * 0.12, v = 0.3 + rnd() } end
end

local function motifScatter(motif, falling)
  if not S.motifs or not motif then return end
  local t = clock()
  for _, p in ipairs(SCATTER) do
    local y = p.y * SH
    if falling then y = ((p.y + t * 0.02 * p.v) % 1.1 - 0.05) * SH end
    local oldA = D.a
    D.a = D.a * p.a
    ui.beginRotation()
    text(motif, p.s, p.x * SW, y, T.white, F.r, 0.5)
    ui.endRotation(p.r + (falling and math.sin(t + p.x * 9) * 12 or 0))
    D.a = oldA
  end
end

local function wallpaper()
  local th = THEME or THEMES[1]
  local wp = WALL.path()
  if wp and WALL.cover(wp, 0, 0, SW, SH, SCREEN.r) then
    if S.wallDim > 0 then rect(0, 0, SW, SH, rgbm(0, 0, 0, S.wallDim), SCREEN.r) end
    ui.drawRectFilledMultiColor(P(0, SH * 0.55), P(SW, SH), A(rgbm(0, 0, 0, 0)), A(rgbm(0, 0, 0, 0)), A(rgbm(0, 0, 0, 0.55)), A(rgbm(0, 0, 0, 0.55)))
    return
  end
  ui.drawRectFilledMultiColor(P(0, 0), P(SW, SH), A(th.top), A(th.top), A(th.bottom), A(th.bottom))
  local art, ac1, ac2 = th.art, th.accent, th.accent2
  local t = clock()
  if art == 'graphite' then
    ui.drawRectFilledMultiColor(P(0, 0), P(SW, SH * 0.5), A(rgbm(1, 1, 1, 0.06)), A(rgbm(1, 1, 1, 0.0)), A(rgbm(1, 1, 1, 0)), A(rgbm(1, 1, 1, 0.02)))
    for i = 0, 6 do line(-40 + i * 70, SH, 160 + i * 70, 0, rgbm(1, 1, 1, 0.025), 1) end
  elseif art == 'aurora' then
    local bands = { { 0.30, 0.95, 0.75 }, { 0.20, 0.55, 1.0 }, { 0.65, 0.40, 1.0 } }
    for k, c in ipairs(bands) do
      for i = 0, 9 do
        local x = SW * (i / 9)
        local y = SH * (0.22 + k * 0.07) + math.sin(t * 0.25 + i * 0.7 + k) * 26
        circle(x, y, 70, rgbm(c[1], c[2], c[3], 0.045))
      end
    end
  elseif art == 'carbon' then
    for i = -20, 40 do
      local x = i * 14
      line(x, 0, x + SH * 0.5, SH, rgbm(1, 1, 1, 0.022), 1)
      line(x + SH * 0.5, 0, x, SH, rgbm(1, 1, 1, 0.016), 1)
    end
    rect(0, SH * 0.62, SW, SH * 0.62 + 3, A(ac1, 0.8))
  elseif art == 'glow' then
    circle(SW * 0.8, SH * 0.18, 140, rgbm(1, 1, 1, 0.05))
    circle(SW * 0.15, SH * 0.7, 180, rgbm(1, 1, 1, 0.03))
  elseif art == 'moon' then
    for i = 5, 1, -1 do circle(SW * 0.68, 190, 60 + i * 16, A(ac1, 0.05)) end
    circle(SW * 0.68, 190, 62, rgbm(0.75, 0.06, 0.08, 1))
    circle(SW * 0.64, 180, 14, rgbm(0.6, 0.04, 0.06, 1))
    circle(SW * 0.74, 214, 9, rgbm(0.6, 0.04, 0.06, 1))
    motifScatter(th.motif, false)
  elseif art == 'hazard' then
    local y1, y2 = SH - 330, SH - 290
    rect(0, y1, SW, y2, rgbm(0.95, 0.75, 0.05, 0.9))
    for i = -2, 14 do
      local x = i * 32 + (t * 12) % 32
      ui.drawQuadFilled(P(x, y1), P(x + 16, y1), P(x - 4, y2), P(x - 20, y2), A(rgbm(0.05, 0.05, 0.05, 1)))
    end
    motifScatter(th.motif, false)
    for i = 4, 1, -1 do circle(SW * 0.25, 170, 30 + i * 22, A(ac1, 0.04)) end
  elseif art == 'grid' then
    local hz = SH * 0.48
    -- sun with stripes
    for i = 4, 1, -1 do circle(SW / 2, hz - 10, 70 + i * 12, A(ac1, 0.05)) end
    pushClip(0, 0, SW, hz)
    circle(SW / 2, hz - 10, 72, rgbm(1, 0.35, 0.6, 1))
    for i = 0, 5 do rect(SW / 2 - 80, hz - 40 + i * 8, SW / 2 + 80, hz - 37 + i * 8 + i * 0.6, th.top) end
    popClip()
    rect(0, hz, SW, SH, rgbm(0.02, 0.0, 0.05, 1))
    local scroll = (t * 0.4) % 1
    for i = 0, 12 do
      local k = (i + scroll) / 12
      local y = hz + (SH - hz) * k * k
      line(0, y, SW, y, A(ac2, 0.25 + k * 0.4), 1.2)
    end
    for i = -8, 8 do line(SW / 2 + i * 6, hz, SW / 2 + i * 70, SH, A(ac2, 0.35), 1.2) end
    line(0, hz, SW, hz, A(ac1, 0.9), 2)
  elseif art == 'drip' then
    for i = 0, 11 do
      local x = i * (SW / 11)
      local len = 60 + ((i * 37) % 7) * 22 + math.sin(t * 0.8 + i) * 8
      rect(x - 6, 0, x + 6, len, A(ac1, 0.55), 6)
      circle(x, len, 9, A(ac1, 0.55))
    end
    for i = 4, 1, -1 do circle(SW / 2, SH * 0.42, 40 + i * 24, A(ac1, 0.05)) end
    text(th.motif, 96, SW / 2, SH * 0.42 - 64, A(T.white, 0.25), F.r, 0.5)
  elseif art == 'flames' then
    for i = 0, 22 do
      local x = (i / 22) * SW
      local h = 120 + math.sin(t * 2.2 + i * 1.7) * 30 + ((i * 53) % 5) * 18
      circle(x, SH - 10, h * 0.55, rgbm(1, 0.35, 0.05, 0.10))
      circle(x, SH + 10, h * 0.35, rgbm(1, 0.7, 0.1, 0.10))
    end
    motifScatter(th.motif, false)
  elseif art == 'snow' then
    for i = 1, 60 do
      local x = (i * 73 % 100) / 100 * SW + math.sin(t + i) * 6
      local y = (((i * 41 % 100) / 100) + t * 0.03 * (0.5 + (i % 5) / 5)) % 1 * SH
      circle(x, y, 1 + (i % 3), rgbm(1, 1, 1, 0.5))
    end
    motifScatter(th.motif, true)
  elseif art == 'rain' then
    motifScatter(th.motif, true)
  elseif art == 'checker' then
    local y0, n, sz = SH - 330, 12, SW / 12
    for r = 0, 1 do for c = 0, n - 1 do
      if (r + c) % 2 == 0 then rect(c * sz, y0 + r * sz, (c + 1) * sz, y0 + (r + 1) * sz, rgbm(1, 1, 1, 0.85)) end
    end end
    line(0, y0 + sz * 2 + 6, SW, y0 + sz * 2 + 6, ac2, 3)
    for i = 4, 1, -1 do circle(SW * 0.75, 170, 30 + i * 22, A(ac2, 0.05)) end
  end
end

-- paints the phone body over the square corners of whatever is on screen
local function cornerMasks()
  local r = SCREEN.r
  local corners = {
    { 0, 0, r, r, math.pi, math.pi * 1.5 },
    { SW, 0, SW - r, r, math.pi * 1.5, math.pi * 2 },
    { SW, SH, SW - r, SH - r, 0, math.pi * 0.5 },
    { 0, SH, r, SH - r, math.pi * 0.5, math.pi },
  }
  for _, c in ipairs(corners) do
    ui.pathLineTo(P(c[1], c[2]))
    for i = 0, 12 do
      local a = lerp(c[5], c[6], i / 12)
      ui.pathLineTo(P(c[3] + math.cos(a) * r, c[4] + math.sin(a) * r))
    end
    ui.pathFillConvex(T.body)
  end
end

local function lapActive()
  local car = ac.getCar(0)
  return S.liveActivity and car and (car.speedKmh > 3 or (car.lapTimeMs or 0) > 0) and not ac.getSim().isPaused
end

-- returns left text, right text, colour, kind
local function islandInfo()
  if CAM.recording then
    local s = math.floor(clock() - CAM.recStart)
    return '●', string.format('%02d:%02d', math.floor(s / 60), s % 60), T.red, 'rec'
  elseif CAM.mode == 'walk' then return '🚶', 'Walking', T.green, 'cam'
  elseif CAM.mode == 'photo' then return '📷', 'Camera', T.yellow, 'cam'
  elseif CAM.mode == 'video' then return '🎬', 'Preview', T.red, 'cam' end
  if HESI.running then
    return '🔥 ' .. HESI.fmt(HESI.run), string.format('x%.1f', HESI.mult), rgbm(1, 0.75, 0.2, 1), 'hesi'
  end
  if lapActive() then
    local car = ac.getCar(0)
    local d = car.performanceMeter or 0
    local hasBest = LIVE.bestMs > 0
    return '⏱ ' .. fmtLapShort(car.lapTimeMs), hasBest and string.format('%+.2f', d) or (math.floor(car.speedKmh) .. ' km/h'),
      hasBest and (d <= 0 and T.green or T.red) or T.white, 'lap'
  end
  if CAM.mode == 'chase' then return '🏎️', 'Chase', rgbm(0.7, 0.5, 1, 1), 'cam' end
  local m = musicPlaying()
  if m then return '♫', utf8Trim(m.title, 16), rgbm(1, 0.35, 0.5, 1), 'music' end
  return nil
end

-- expanded Live Activity card under the island
local function islandExpanded(kind)
  local e = easeOut(clamp(LIVE.expanded, 0, 0.3) / 0.3)
  if e <= 0.01 then return end
  local oldA = D.a
  D.a = D.a * e
  local x1, y1, x2, y2 = 14, 10, SW - 14, 10 + 120 * e
  rect(x1, y1, x2, y2, rgbm(0, 0, 0, 1), 34)
  if e > 0.7 then
    if kind == 'lap' then
      local car = ac.getCar(0)
      text('LAP ' .. ((car.lapCount or 0) + 1), 12, x1 + 22, y1 + 46, T.label2, F.sb)
      text(fmtLap(car.lapTimeMs), 26, x1 + 22, y1 + 62, T.white, F.numb)
      text('Last ' .. fmtLap(car.previousLapTimeMs) .. '   Best ' .. fmtLap(LIVE.bestMs), 12, x1 + 22, y1 + 96, T.label2)
      text(math.floor(car.speedKmh) .. '', 30, x2 - 22, y1 + 50, T.white, F.b, 1)
      text('km/h · ' .. (car.gear == 0 and 'N' or (car.gear < 0 and 'R' or tostring(car.gear))) .. (car.racePosition and car.racePosition > 0 and ('  ·  P' .. car.racePosition) or ''), 12, x2 - 22, y1 + 90, T.label2, F.r, 1)
    elseif kind == 'music' then
      local m = MEDIA.now()
      if m then
        MEDIA.cover(m, x1 + 20, y1 + 44, x1 + 70, y1 + 94, 10)
        textFit(m.title, 15, x1 + 82, y1 + 46, x2 - x1 - 190, T.white, F.sb)
        textFit(m.artist or '', 12, x1 + 82, y1 + 68, x2 - x1 - 190, T.label2)
        MEDIA.controls('isl.m', x2 - 70, y1 + 70, 16, T.white)
        LIVE.expanded = math.max(LIVE.expanded, 0.5)
      end
    elseif kind == 'hesi' then
      text('🔥 CUT-UP RUN', 12, x1 + 22, y1 + 46, rgbm(1, 0.75, 0.2, 1), F.b)
      text(HESI.fmt(HESI.run), 28, x1 + 22, y1 + 62, T.white, F.numb)
      text(string.format('x%.1f', HESI.mult), 28, x2 - 22, y1 + 50, rgbm(1, 0.75, 0.2, 1), F.b, 1)
      rect(x1 + 22, y1 + 100, x2 - 22, y1 + 105, rgbm(1, 1, 1, 0.15), 3)
      rect(x1 + 22, y1 + 100, x1 + 22 + (x2 - x1 - 44) * clamp(HESI.combo / HESI.comboMax, 0, 1), y1 + 105, rgbm(1, 0.75, 0.2, 1), 3)
    elseif kind == 'rec' or kind == 'cam' then
      local icon, label, c = islandInfo()
      text(icon, 30, x1 + 40, y1 + 54, c, F.r, 0.5)
      text(label, 20, x1 + 72, y1 + 58, T.white, F.sb)
    end
  end
  D.a = oldA
end

local function statusBar(dark)
  local c = dark and rgbm(0, 0, 0, 1) or T.white
  text(os.date('%H:%M'), 16, 46, 15, c, F.sb, 0.5)
  -- island (Live Activity)
  local left, right, col, kind = islandInfo()
  local target = left and ((kind == 'lap' or kind == 'hesi') and 230 or 196) or 118
  local iw = anim('island', target, 10)
  local x1 = SW / 2 - iw / 2
  rect(x1, 10, x1 + iw, 44, rgbm(0, 0, 0, 1), 17)
  if left and iw > target - 20 then
    text(left, 13, x1 + 16, 18, (kind == 'lap' or kind == 'hesi') and T.white or col, (kind == 'lap' or kind == 'hesi') and F.sb or F.r)
    text(right, 13, x1 + iw - 16, 18, col, F.sb, 1)
  end
  if left and not IN.locked and tap('island', x1, 8, x1 + iw, 46) then LIVE.expanded = LIVE.expanded > 0 and 0 or 4 end
  if LIVE.expanded > 0 then
    LIVE.expanded = math.max(0, LIVE.expanded - IN.dt)
    if left then islandExpanded(kind) end
  end
  -- right side: network + battery
  local online = ac.getSim().isOnlineRace
  local bx = SW - 34
  for i = 1, 4 do
    local h = 3 + i * 2.2
    rect(bx - 48 + i * 5, 26 - h, bx - 45 + i * 5, 26, A(c, (online or i == 1) and 1 or 0.3), 1)
  end
  local pct = POWER.battery and clamp(POWER.battery / 100, 0, 1) or 1
  rectLine(bx - 12, 16, bx + 14, 28, A(c, 0.4), 3.5, 1.2)
  rect(bx + 15, 20, bx + 17, 24, A(c, 0.4), 1)
  rect(bx - 10, 18, bx - 10 + 22 * pct, 26, (pct < 0.2 and not POWER.charging) and T.red or c, 2)
  if S.dnd then text('🌙', 11, 78, 17, rgbm(0.6, 0.5, 1, 1)) end
end

-- ===========================================================================
-- Lock screen, Notification Center, Control Center
-- ===========================================================================

local SHEET = { kind = nil, t = 0, closing = false }
if rawget(_G, '__ACPHONE_TEST') then rawget(_G, '__ACPHONE_TEST').SHEET = SHEET end

local function openSheet(kind) SHEET.kind, SHEET.t, SHEET.closing = kind, 0, false end
local function closeSheet() if SHEET.kind then SHEET.closing = true end end

local function notifCard(n, y, idp)
  local fired, pressed = tap(idp, 12, y, SW - 12, y + 70)
  rect(12, y, SW - 12, y + 70, rgbm(0.18, 0.18, 0.2, pressed and 0.98 or 0.88), 20)
  rect(24, y + 14, 64, y + 54, rgbm(0.32, 0.32, 0.35, 1), 10)
  text(n.icon, 20, 44, y + 20, T.white, F.r, 0.5)
  textFit(n.title, 15, 76, y + 12, SW - 150, T.white, F.sb)
  text(n.time, 12, SW - 26, y + 14, T.label2, F.r, 1)
  textFit(n.body, 13, 76, y + 36, SW - 100, T.label2)
  return fired
end

local function nowPlayingCard(y, idp)
  local m = MEDIA.now()
  if not m then return y end
  idp = idp or 'np'
  rect(12, y, SW - 12, y + 128, rgbm(0.14, 0.14, 0.16, 0.86), 22)
  MEDIA.cover(m, 26, y + 14, 82, y + 70, 10)
  textFit(m.title, 15, 94, y + 18, SW - 130, T.white, F.sb)
  textFit(m.artist or '', 13, 94, y + 40, SW - 130, T.label2)
  if m.trackDuration and m.trackDuration > 0 and m.trackPosition and m.trackPosition >= 0 then
    local t = clamp(m.trackPosition / m.trackDuration, 0, 1)
    rect(26, y + 82, SW - 26, y + 85, rgbm(1, 1, 1, 0.2), 2)
    rect(26, y + 82, 26 + (SW - 52) * t, y + 85, T.white, 2)
  end
  MEDIA.controls(idp, SW / 2, y + 106, 20, T.white)
  return y + 138
end

local function lapCard(y)
  if not lapActive() then return y end
  local car = ac.getCar(0)
  rect(12, y, SW - 12, y + 84, rgbm(0.18, 0.18, 0.2, 0.88), 20)
  text('⏱  LIVE LAP ' .. ((car.lapCount or 0) + 1), 12, 28, y + 12, T.label2, F.sb)
  text(fmtLap(car.lapTimeMs), 28, 28, y + 30, T.white, F.numb)
  text(math.floor(car.speedKmh) .. ' km/h', 15, SW - 28, y + 38, T.white, F.m, 1)
  if LIVE.bestMs > 0 then
    local d = car.performanceMeter or 0
    text(string.format('%+.2f', d), 13, SW - 28, y + 14, d <= 0 and T.green or T.red, F.sb, 1)
  end
  return y + 94
end

local function lockScreen()
  wallpaper()
  local u = PHONE.unlock or 0
  local oldY = D.y
  D.y = D.y - u * SH
  text('🔒', 16, SW / 2, 58, T.white, F.r, 0.5)
  text(os.date('%A, %d %B'), 17, SW / 2, 86, rgbm(1, 1, 1, 0.85), F.m, 0.5)
  text(os.date('%H:%M'), 88, SW / 2, 100, T.white, F.numl, 0.5)
  local y = 230
  y = lapCard(y)
  y = nowPlayingCard(y, 'lk')
  local shown = 0
  for i = #NOTIFS, 1, -1 do
    if y > SH - 140 then break end
    local n = NOTIFS[i]
    if notifCard(n, y, 'ln' .. i) then PHONE.locked = false PHONE.unlock = 0 if n.action then n.action() end end
    y = y + 78
    shown = shown + 1
    if shown >= 4 then break end
  end
  text('Swipe up to open', 14, SW / 2, SH - 52, rgbm(1, 1, 1, 0.7), F.m, 0.5)
  D.y = oldY
  -- swipe up anywhere / tap the bottom to unlock
  if not IN.locked then
    if IN.down and IN.active == nil and IN.clicked == false and (IN.pressPos.y - IN.m.y) > 8 then IN.active = '__unlock' end
    if IN.active == '__unlock' then
      PHONE.unlock = clamp((IN.pressPos.y - IN.m.y) / SH, 0, 1)
      if IN.released then
        if PHONE.unlock > 0.12 then PHONE.unlocking = true else PHONE.unlock = 0 end
      end
    elseif tap('unlockbar', 0, SH - 70, SW, SH) then
      PHONE.unlocking = true
    end
  end
  if PHONE.unlocking then
    PHONE.unlock = damp(PHONE.unlock or 0, 1.05, 12, IN.dt)
    if PHONE.unlock >= 1 then PHONE.locked = false PHONE.unlocking = false PHONE.unlock = 0 end
  end
end

local function notificationCenter(e)
  rect(0, 0, SW, SH, rgbm(0.02, 0.02, 0.04, 0.88 * e), SCREEN.r)
  local oldY = D.y
  D.y = D.y - (1 - e) * SH * 0.4
  text(os.date('%H:%M'), 62, SW / 2, 60, T.white, F.numl, 0.5)
  text(os.date('%A, %d %B'), 15, SW / 2, 140, rgbm(1, 1, 1, 0.8), F.m, 0.5)
  text('Notification Centre', 20, 16, 176, T.white, F.b)
  if #NOTIFS > 0 and W.button('nc.clear', 'Clear', SW - 80, 172, 64, 30, 'gray') then
    for i = #NOTIFS, 1, -1 do NOTIFS[i] = nil end
  end
  local s = scrollBegin('nc', 214, SH - 40)
  local y = 220
  y = lapCard(y)
  y = nowPlayingCard(y, 'ncm')
  if #NOTIFS == 0 then text('No notifications', 15, SW / 2, y + 30, T.label2, F.r, 0.5) y = y + 80 end
  for i = #NOTIFS, 1, -1 do
    local n = NOTIFS[i]
    if notifCard(n, y, 'nc' .. i) then
      closeSheet()
      if n.action then n.action() end
    end
    y = y + 78
  end
  scrollEnd(s, y)
  D.y = oldY
end

local function ccTile(id, x, y, w, h, on, icon, label, onColor)
  local fired, pressed = tap(id, x, y, x + w, y + h)
  local bg = on and (onColor or T.white) or rgbm(0.25, 0.25, 0.28, 0.9)
  rect(x, y, x + w, y + h, A(bg, pressed and 0.75 or 1), 22)
  local fg = on and (onColor and T.white or rgbm(0.05, 0.05, 0.06, 1)) or T.white
  text(icon, 22, x + w / 2, y + h / 2 - (label and 24 or 15), fg, F.r, 0.5)
  if label then textFit(label, 11, x + w / 2, y + h - 26, w - 12, fg, F.m, 0.5) end
  return fired
end

local function controlCenter(e)
  rect(0, 0, SW, SH, rgbm(0.02, 0.02, 0.04, 0.82 * e), SCREEN.r)
  local oldY = D.y
  D.y = D.y - (1 - e) * 60
  local a = D.a
  D.a = D.a * e
  local g, t = 12, 74
  local cw = (SW - 32 - g * 3) / 4
  local x0, y = 16, 64
  -- connectivity block (2x2 round toggles)
  rect(x0, y, x0 + cw * 2 + g, y + cw * 2 + g, rgbm(0.25, 0.25, 0.28, 0.9), 22)
  local toggles = {
    { 'cc.chase', S.chaseOn, '🏎️', rgbm(0.55, 0.30, 0.95, 1), function() S.chaseOn = not S.chaseOn end },
    { 'cc.dnd', S.dnd, '🌙', rgbm(0.40, 0.35, 0.95, 1), function() S.dnd = not S.dnd end },
    { 'cc.notif', S.notifications, '🔔', T.red, function() S.notifications = not S.notifications end },
    { 'cc.live', S.liveActivity, '⏱', T.green, function() S.liveActivity = not S.liveActivity end },
  }
  for i, tg in ipairs(toggles) do
    local cx = x0 + (cw * 2 + g) * (((i - 1) % 2) == 0 and 0.28 or 0.72)
    local cy = y + (cw * 2 + g) * (i <= 2 and 0.28 or 0.72)
    if tap(tg[1], cx - 26, cy - 26, cx + 26, cy + 26) then tg[5]() end
    circle(cx, cy, 25, tg[2] and tg[4] or rgbm(0.38, 0.38, 0.42, 1))
    text(tg[3], 20, cx, cy - 14, T.white, F.r, 0.5)
  end
  -- now playing block
  local mx = x0 + cw * 2 + g * 2
  rect(mx, y, mx + cw * 2 + g, y + cw * 2 + g, rgbm(0.25, 0.25, 0.28, 0.9), 22)
  local m = MEDIA.now()
  local bw2 = cw * 2 + g
  if m then
    MEDIA.cover(m, mx + 12, y + 12, mx + 48, y + 48, 8)
    textFit(m.title, 12, mx + 56, y + 14, bw2 - 64, T.white, F.sb)
    textFit(m.artist or '', 11, mx + 56, y + 32, bw2 - 64, T.label2)
  else
    glyph('MUSIC', mx + 14, y + 16, 26, T.label2)
    text('Not playing', 12, mx + 48, y + 22, T.label2, F.m)
  end
  MEDIA.controls('cc.m', mx + bw2 / 2, y + bw2 - 36, 18, T.white)
  y = y + cw * 2 + g * 2
  -- quick tiles
  if ccTile('cc.clean', x0, y, cw, cw, #CAM.hiddenApps > 0, '🫥', 'Clean') then hideOtherApps(#CAM.hiddenApps == 0) end
  if ccTile('cc.walk', x0 + (cw + g), y, cw, cw, CAM.mode == 'walk', '🚶', 'Walk', T.green) then
    if CAM.mode == 'walk' then camRelease() else if CAM.mode then camRelease() end walkStart() end
  end
  if ccTile('cc.cam', x0 + (cw + g) * 2, y, cw, cw, CAM.mode == 'photo', '📷', 'Camera') then closeSheet() openApp('camera') end
  if ccTile('cc.lock', x0 + (cw + g) * 3, y, cw, cw, false, '🔒', 'Lock') then closeSheet() PHONE.locked = true PHONE.unlock = 0 end
  y = y + cw + g
  -- wide tiles
  local online = ac.getSim().isOnlineRace
  rect(x0, y, SW - 16, y + 64, rgbm(0.25, 0.25, 0.28, 0.9), 22)
  text(online and '🌐' or '📡', 22, x0 + 30, y + 16, T.white, F.r, 0.5)
  textFit(online and ((ac.getServerName and ac.getServerName()) or 'Online') or 'Offline', 14, x0 + 56, y + 12, SW - 120, T.white, F.sb)
  text(online and ((#getPlayers() + 1) .. ' drivers · ' .. ((ac.getTrackName and ac.getTrackName()) or '')) or 'Single player', 12, x0 + 56, y + 36, T.label2)
  y = y + 76
  if ccTile('cc.hud', x0, y, cw * 2 + g, cw, false, '🎛️', 'HUD') then closeSheet() openApp('hud') end
  if ccTile('cc.map', x0 + cw * 2 + g * 2, y, cw * 2 + g, cw, false, '🗺️', 'Maps') then closeSheet() openApp('maps') end
  D.a = a
  D.y = oldY
end

local function sheets()
  if not SHEET.kind then return end
  if SHEET.closing then SHEET.t = SHEET.t - IN.dt * 4 else SHEET.t = math.min(1, SHEET.t + IN.dt * 4) end
  if SHEET.t <= 0 then SHEET.kind, SHEET.closing = nil, false return end
  local e = easeOut(SHEET.t)
  if SHEET.kind == 'nc' then notificationCenter(e) else controlCenter(e) end
  -- close by tapping the status bar or swiping up from the bottom
  if not IN.locked and tap('sheet.close', 0, SH - 40, SW, SH) then closeSheet() end
end

local function statusGestures()
  if IN.locked then return end
  local fired = tap('sb.left', 0, 0, SW * 0.32, 48)
  if fired then if SHEET.kind == 'nc' then closeSheet() else openSheet('nc') end end
  fired = tap('sb.right', SW * 0.68, 0, SW, 48)
  if fired then if SHEET.kind == 'cc' then closeSheet() else openSheet('cc') end end
  -- pull down from the top edge
  if IN.down and IN.pressPos.y - SCREEN.y < 48 and IN.active ~= 'island' and (IN.m.y - IN.pressPos.y) > 40 and not SHEET.kind then
    openSheet(IN.pressPos.x - SCREEN.x < SW / 2 and 'nc' or 'cc')
    IN.active = '__sheet'
  end
end

local function banners()
  local y0 = 52
  for i = #BANNERS, 1, -1 do
    local b = BANNERS[i]
    b.t = b.t + IN.dt
    local life = 4.5
    local inT = easeOut(b.t / 0.35)
    local outT = b.t > life and easeOut((b.t - life) / 0.3) or 0
    if b.t > life + 0.3 then table.remove(BANNERS, i)
    else
      local y = y0 - 90 * (1 - inT) - 90 * outT
      local oldA = D.a
      D.a = D.a * (1 - outT)
      rect(10, y, SW - 10, y + 72, rgbm(0.16, 0.16, 0.17, 0.97), 22)
      rect(22, y + 14, 66, y + 58, rgbm(0.30, 0.30, 0.33, 1), 11)
      text(b.icon, 22, 44, y + 20, T.white, F.r, 0.5)
      textFit(b.title, 15, 78, y + 14, SW - 150, T.label, F.sb)
      text('now', 13, SW - 24, y + 15, T.label2, F.r, 1)
      textFit(b.body, 14, 78, y + 38, SW - 104, T.label2, F.r)
      local fired = tap('banner' .. tostring(b), 10, y, SW - 10, y + 72)
      D.a = oldA
      if fired then
        if b.action then b.action() end
        b.t = math.max(b.t, life)
      end
      y0 = y0 + 6
    end
  end
end

-- ===========================================================================
-- Home screen
-- ===========================================================================

local HOME = { page = 1, offset = 0, dragging = false }
local ICON, COLS = 60, 4
local GAPX = (SW - 48 - ICON * COLS) / (COLS - 1)

local function appIconDraw(id, icon, label, x, y, c1, c2, badgeN, onTap, dot)
  local fired, pressed = tap('icon.' .. id, x - 6, y - 6, x + ICON + 6, y + ICON + 24)
  local p = anim('icon.' .. id .. '#p', pressed and 1 or 0, 25)
  local sh = p * 3
  local style = S.iconStyle or 1
  local x1, y1, x2, y2 = x + sh, y + sh, x + ICON - sh, y + ICON - sh
  local g, rest = leadingIcon(icon)
  local gc = T.white
  if style == 2 then
    -- glass: frosted dark tile, accent glyph
    rect(x1, y1, x2, y2, rgbm(0.08, 0.08, 0.09, 0.62), 16)
    ui.drawRectFilledMultiColor(P(x1 + 8, y1 + 1), P(x2 - 8, y1 + 2), A(rgbm(1, 1, 1, 0)), A(rgbm(1, 1, 1, 0)), A(rgbm(1, 1, 1, 0.35)), A(rgbm(1, 1, 1, 0.35)))
    rectLine(x1, y1, x2, y2, rgbm(1, 1, 1, 0.14), 16, 1)
    gc = mix(c1, T.white, 0.35)
  elseif style == 3 then
    -- minimal: just the glyph on a faint circle
    circle(x + ICON / 2, y + ICON / 2, ICON / 2 - 4 - sh, rgbm(1, 1, 1, 0.08))
    gc = T.white
  else
    -- colour: smooth two-tone gradient tile with a soft top sheen
    rect(x1, y1, x2, y2, c2, 16)
    rect(x1, y1, x2, y + ICON * 0.55, c1, 16, ui.CornerFlags.Top)
    ui.drawRectFilledMultiColor(P(x1, y + ICON * 0.4), P(x2, y + ICON * 0.62), A(c1), A(c1), A(c2), A(c2))
    rect(x1, y1, x2, y + ICON * 0.3, rgbm(1, 1, 1, 0.08), 16, ui.CornerFlags.Top)
  end
  if p > 0.01 then rect(x, y, x + ICON, y + ICON, rgbm(0, 0, 0, 0.25 * p), 16) end
  if g then
    local gs = ICON * 0.46
    glyph(g, x + (ICON - gs) / 2, y + (ICON - gs) / 2, gs, gc)
  else
    text(icon, 28, x + ICON / 2, y + 11, T.white, F.sb, 0.5)
  end
  if label then textFit(label, 12, x + ICON / 2, y + ICON + 5, ICON + 18, T.white, F.m, 0.5) end
  if badgeN and badgeN > 0 then
    local s = badgeN > 99 and '99+' or tostring(badgeN)
    local bw = math.max(22, measure(s, 13, F.sb).x + 12)
    rect(x + ICON - bw / 2 - 4, y - 7, x + ICON + bw / 2 - 4, y + 15, T.red, 11)
    text(s, 13, x + ICON - 4, y - 5, T.white, F.sb, 0.5)
  end
  if dot then circle(x + ICON / 2, y + ICON + 26, 2.5, T.white) end
  appIconRects[id] = { x = D.x + x + ICON / 2, y = D.y + y + ICON / 2 }
  if fired and onTap then onTap() end
end

local function widgetFriends(x, y, w, h)
  rect(x, y, x + w, y + h, rgbm(0.10, 0.10, 0.12, 0.72), 22)
  local players = getPlayers()
  text('👥 Friends', 13, x + 14, y + 12, T.label2, F.sb)
  text(tostring(#players), 40, x + 14, y + 26, T.white, F.numl)
  text('online', 13, x + 14 + measure(tostring(#players), 40, F.numl).x + 6, y + 52, T.label2, F.r)
  for i = 1, math.min(4, #players) do
    avatar(players[i].name, x + 14 + (i - 1) * 24, y + h - 46, 32)
  end
  if #players == 0 then text(ac.getSim().isOnlineRace and 'Waiting for the crew' or 'Offline', 12, x + 14, y + h - 32, T.label2) end
  if tap('w.friends', x, y, x + w, y + h) then openApp('friends') end
end

local function widgetWeather(x, y, w, h)
  local wt = weatherNow()
  local top, bottom = skyColors(wt)
  rect(x, y, x + w, y + h, bottom, 22)
  rect(x, y, x + w, y + h * 0.5, top, 22, ui.CornerFlags.Top)
  rect(x, y + h * 0.35, x + w, y + h * 0.55, rgbm(lerp(top.r, bottom.r, 0.5), lerp(top.g, bottom.g, 0.5), lerp(top.b, bottom.b, 0.5), 1), 0)
  textFit(ac.getTrackName and ac.getTrackName() or 'Track', 13, x + 14, y + 12, w - 28, T.white, F.sb)
  text(string.format('%d°', math.floor(wt.temp + 0.5)), 40, x + 14, y + 26, T.white, F.numl)
  text(wt.icon, 18, x + 14, y + h - 52, T.white, F.r)
  textFit(wt.name, 12, x + 14, y + h - 28, w - 28, T.white, F.m)
  text(wt.timeStr, 12, x + w - 14, y + 14, rgbm(1, 1, 1, 0.8), F.m, 1)
  if tap('w.weather', x, y, x + w, y + h) then openApp('weather') end
end

local function homePage1(ox)
  local oldX = D.x
  D.x = D.x + ox
  local ww = ICON * 2 + GAPX
  widgetFriends(24, 62, ww, 132)
  widgetWeather(24 + ww + GAPX, 62, ww, 132)
  local y0 = 212
  local n = 0
  for _, id in ipairs(GRID) do
    local a = APP_BY_ID[id]
    if not listHas(S.hiddenApps, id) then
      n = n + 1
      local c, r = (n - 1) % COLS, math.floor((n - 1) / COLS)
      local x, y = 24 + c * (ICON + GAPX), y0 + r * 92
      appIconDraw(id, a.icon, a.name, x, y, a.c1, a.c2, a.badge and a.badge() or 0, function() openApp(id) end)
    end
  end
  D.x = oldX
end

local function homePage2(ox)
  local oldX = D.x
  D.x = D.x + ox
  local top0 = 70
  if MEDIA.now() then top0 = nowPlayingCard(58, 'hm') + 6 end
  local pinned = splitList(S.pinnedApps)
  local wins = {}
  if ac.getAppWindows then for _, w in ipairs(ac.getAppWindows()) do wins[w.name] = w end end
  local n = 0
  for _, name in ipairs(pinned) do
    local w = wins[name]
    if w then
      n = n + 1
      local c, r = (n - 1) % COLS, math.floor((n - 1) / COLS)
      local x, y = 24 + c * (ICON + GAPX), top0 + r * 100
      local col = avatarColor(w.title)
      local icon = appIcon(w.title) or utf8Trim(w.title, 1):upper()
      appIconDraw('win.' .. name, icon, w.title, x, y, rgbm(col.r * 1.15, col.g * 1.15, col.b * 1.15, 1), col, 0,
        function() toggleWindow(name) end, w.visible)
    end
  end
  if n == 0 then
    text('🧩', 40, SW / 2, 200, T.white, F.r, 0.5)
    text('Your apps', 20, SW / 2, 260, T.white, F.sb, 0.5)
    textBox('Open the Apps app and tap ☆ next to the apps you use. They show up here, one tap to open or close.', 14, 50, 292, SW - 50, 360, rgbm(1, 1, 1, 0.75))
    if W.button('h2.lib', 'Open Apps', SW / 2 - 70, 370, 140, 40, 'filled') then openApp('library') end
  end
  D.x = oldX
end

local function homeScreen()
  wallpaper()
  -- page swipe
  local act = IN.active
  local canDrag = act == nil or (type(act) == 'string' and (act:sub(1, 5) == 'icon.' or act:sub(1, 2) == 'w.'))
  if not IN.locked and IN.down and not HOME.dragging and canDrag and hit(0, 50, SW, SH - 120) then
    local dx = IN.m.x - IN.pressPos.x
    if math.abs(dx) > 10 and math.abs(dx) > math.abs(IN.m.y - IN.pressPos.y) then HOME.dragging = true IN.active = '__page' end
  end
  if HOME.dragging and IN.clicked == false and IN.active == '__page' then
    local dx = IN.m.x - IN.pressPos.x
    HOME.offset = clamp(-(HOME.page - 1) * SW + dx, -SW - 40, 40)
    if IN.released then
      if dx < -60 then HOME.page = 2 elseif dx > 60 then HOME.page = 1 end
      HOME.dragging = false
    end
  else
    HOME.offset = damp(HOME.offset, -(HOME.page - 1) * SW, 14, IN.dt)
  end
  pushClip(0, 0, SW, SH)
  homePage1(HOME.offset)
  homePage2(HOME.offset + SW)
  popClip()
  -- page dots
  local dy = SH - 140
  rect(SW / 2 - 26, dy - 8, SW / 2 + 26, dy + 8, rgbm(0, 0, 0, 0.2), 8)
  for i = 1, 2 do
    local sel = HOME.page == i
    circle(SW / 2 - 9 + (i - 1) * 18, dy, 3.5, rgbm(1, 1, 1, sel and 1 or 0.4))
    if tap('dot' .. i, SW / 2 - 18 + (i - 1) * 18, dy - 10, SW / 2 + (i - 1) * 18, dy + 10) then HOME.page = i end
  end
  -- dock
  local dockY = SH - 112
  rect(12, dockY, SW - 12, SH - 18, rgbm(1, 1, 1, 0.16), 32)
  local dgap = (SW - 24 - 24 - ICON * 4) / 3
  for i, id in ipairs(DOCK) do
    local a = APP_BY_ID[id]
    appIconDraw(id, a.icon, nil, 24 + (i - 1) * (ICON + dgap), dockY + 17, a.c1, a.c2, a.badge and a.badge() or 0, function() openApp(id) end)
  end
end

-- ===========================================================================
-- Screen compositor (transitions)
-- ===========================================================================

local function drawScreen(scr, ox, alpha, dim)
  local oldX, oldA = D.x, D.a
  D.x = D.x + ox
  D.a = D.a * alpha
  scr.draw(scr)
  if dim and dim > 0.01 then rect(0, 0, SW, SH, rgbm(0, 0, 0, 0.35 * dim), SCREEN.r) end
  D.x, D.a = oldX, oldA
end

local function compose()
  local tr = NAV.trans
  if tr then
    tr.t = tr.t + IN.dt
    IN.locked = true
  end
  if tr and (tr.kind == 'open' or tr.kind == 'close') then
    local dur = 0.38
    local e = easeOut(tr.t / dur)
    if tr.kind == 'close' then e = 1 - e end
    homeScreen()
    local scr = tr.kind == 'open' and navTop() or (tr.stack and tr.stack[#tr.stack])
    if scr then
      local cx, cy = SW / 2, SH / 2
      local ix, iy = cx, cy
      if tr.icon then ix, iy = tr.icon.x - SCREEN.x, tr.icon.y - SCREEN.y end
      local oldX, oldY, oldA = D.x, D.y, D.a
      D.x = D.x + (ix - cx) * (1 - e)
      D.y = D.y + (iy - cy) * (1 - e)
      D.a = D.a * clamp(e * 1.6, 0, 1)
      ui.beginScale()
      scr.draw(scr)
      cornerMasks()
      ui.endScale(lerp(0.12, 1, e))
      D.x, D.y, D.a = oldX, oldY, oldA
    end
    if tr.t >= dur then NAV.trans = nil end
    return
  end
  if not NAV.app then homeScreen() return end
  if tr and (tr.kind == 'push' or tr.kind == 'pop') then
    local dur = 0.34
    local e = easeInOut(tr.t / dur)
    pushClip(0, 0, SW, SH)
    if tr.kind == 'push' then
      if tr.from then drawScreen(tr.from, -SW * 0.3 * e, 1, e) end
      drawScreen(tr.to, SW * (1 - e), 1, 0)
    else
      drawScreen(tr.to, -SW * 0.3 * (1 - e), 1, 1 - e)
      drawScreen(tr.from, SW * e, 1, 0)
    end
    popClip()
    if tr.t >= dur then NAV.trans = nil end
    return
  end
  local top = navTop()
  if top then top.draw(top) end
end

-- ===========================================================================
-- Minimised capsule (while filming, walking or framing a photo)
-- ===========================================================================

local function capsule()
  D.x, D.y, D.a = 0, 0, 1
  local x1, y1, x2, y2 = 10, 10, 362, 86
  rect(x1, y1, x2, y2, rgbm(0.06, 0.06, 0.07, 0.94), 38)
  rectLine(x1, y1, x2, y2, rgbm(1, 1, 1, 0.1), 38, 1)
  local reason = PHONE.minimizeReason
  if reason == 'rec' then
    local s = math.floor(clock() - CAM.recStart)
    local blink = (math.floor(clock() * 2) % 2 == 0)
    circle(44, 48, 8, blink and T.red or rgbm(0.5, 0.1, 0.1, 1))
    text(string.format('REC  %02d:%02d', math.floor(s / 60), s % 60), 20, 62, 34, T.white, F.sb)
    local shot = CAM.shot
    for _, v in ipairs(VIDEO_SHOTS) do if v.id == shot then shot = v.icon .. ' ' .. v.name end end
    text(shot, 12, 62, 60, T.label2, F.r)
    if W.button('cap.next', '⟳', 222, 28, 40, 40, 'gray') then
      local idx = 1
      for i, v in ipairs(VIDEO_SHOTS) do if v.id == CAM.shot then idx = i end end
      CAM.shot = VIDEO_SHOTS[idx % #VIDEO_SHOTS + 1].id
      CAM.flybyInit = nil
      if CAM.shot == 'free' then camStartFromCurrent() end
    end
    if W.button('cap.stop', 'Stop', 272, 28, 76, 40, 'filled', T.red) then
      CAM.recording = false
      hideOtherApps(false)
      camRelease()
      setMinimized(false)
      toast('Recording stopped', 'Stop your OBS / ShadowPlay capture too', '🎬')
    end
  else
    if W.button('cap.expand', '⤢', 24, 28, 44, 40, 'gray') then setMinimized(false) end
    if shutterButton('cap.shutter', SW / 2 + 10, 48, 54) then takePhoto() end
    if reason == 'walk' then
      if W.button('cap.car', 'To car', 270, 28, 78, 40, 'gray') then camRelease() setMinimized(false) end
    else
      if W.button('cap.done', 'Done', 270, 28, 78, 40, 'gray') then camRelease() setMinimized(false) closeApp() end
    end
  end
end

-- ===========================================================================
-- Window
-- ===========================================================================

local lastDraw = -1
local openAnim = 1
local swipeHome = nil

local function readInput(dt)
  local wp = ui.windowPos()
  local mp = ui.mousePos()
  IN.m = mp - wp
  local ws = ui.windowSize()
  local inside = IN.m.x >= 0 and IN.m.y >= 0 and IN.m.x <= ws.x and IN.m.y <= ws.y
  IN.hovered = inside and ui.windowHovered(ui.HoveredFlags.AllowWhenBlockedByActiveItem)
  IN.dt = dt
  IN.down = ui.mouseDown(ui.MouseButton.Left)
  IN.clicked = IN.hovered and ui.mouseClicked(ui.MouseButton.Left)
  IN.released = ui.mouseReleased(ui.MouseButton.Left)
  IN.delta = ui.mouseDelta()
  local wheel = ui.mouseWheel()
  IN.wheel = IN.hovered and wheel or 0
  IN.wheelGlobal = IN.hovered and 0 or wheel
  if IN.clicked then IN.pressPos = IN.m end
  IN.locked = false
end

local function endInput()
  if IN.released or not IN.down then
    IN.active = nil
    IN.dragScroll = false
    IN.sliderActive = false
    HOME.dragging = false
  end
end

function script.windowMain(dt)
  local now = clock()
  if now - lastDraw > 0.3 then
    openAnim = 0
    if S.lockScreen and lastDraw > 0 and now - lastDraw > 30 then PHONE.locked = true PHONE.unlock = 0 SHEET.kind = nil end
  end
  lastDraw = now
  dt = clamp(dt or 0.016, 0, 0.1)
  readInput(dt)
  if CAM.hidden then endInput() return end      -- taking a photo: draw nothing
  if PHONE.minimized then
    capsule()
    endInput()
    return
  end

  openAnim = math.min(1, openAnim + dt / 0.35)
  local e = easeOut(openAnim)
  D.x, D.y, D.a = 0, 60 * (1 - e), e
  if openAnim < 1 then IN.locked = true end

  -- phone body
  local ws = ui.windowSize()
  rect(0, 0, ws.x, ws.y, T.body, 56)
  rectLine(1.5, 1.5, ws.x - 1.5, ws.y - 1.5, T.frame, 55, 2.5)

  -- screen
  D.x, D.y = SCREEN.x, SCREEN.y + 60 * (1 - e)
  local baseX, baseY = D.x, D.y
  if PHONE.locked then
    IN.locked = openAnim < 1 or SHEET.kind ~= nil
    lockScreen()
    if not PHONE.locked and not IN.locked then IN.active = '__unlocked' end
  else
    IN.locked = IN.locked or SHEET.kind ~= nil
    compose()
  end
  D.x, D.y = baseX, baseY
  IN.locked = (NAV.trans ~= nil) or openAnim < 1
  sheets()
  cornerMasks()
  statusBar(false)
  statusGestures()
  banners()

  -- home indicator: tap or swipe up to go home
  local hy = SH - 12
  rect(SW / 2 - 67, hy - 2.5, SW / 2 + 67, hy + 2.5, rgbm(1, 1, 1, 0.85), 3)
  if SHEET.kind and not IN.locked then
    if IN.clicked and hit(SW / 2 - 110, SH - 34, SW / 2 + 110, SH) then closeSheet() end
  elseif NAV.app and not IN.locked and not PHONE.locked then
    if IN.clicked and hit(SW / 2 - 110, SH - 34, SW / 2 + 110, SH) then swipeHome = IN.m.y IN.active = '__home' end
    if swipeHome and IN.active == '__home' then
      if IN.m.y < swipeHome - 40 or (IN.released and hit(SW / 2 - 110, SH - 34, SW / 2 + 110, SH)) then
        swipeHome = nil
        closeApp()
      end
    end
    if IN.released then swipeHome = nil end
  end

  if CAM.flash > 0 then rect(0, 0, SW, SH, rgbm(1, 1, 1, CAM.flash * 0.8), SCREEN.r) end

  -- invisible catcher so clicks on the screen don't drag the window (drag by the status bar / frame instead)
  ui.setCursor(vec2(SCREEN.x, SCREEN.y))
  ui.invisibleButton('##acphone_screen', vec2(SW, SH))
  endInput()
end

-- ===========================================================================
-- Action bar: on-screen Cut-Up HUD (its own window, works with the phone closed)
-- ===========================================================================

function script.actionBar(dt)
  D.x, D.y, D.a = 0, 0, 1
  local ws = ui.windowSize()
  local cx = ws.x / 2
  local ac1 = accent()
  local gold = rgbm(1, 0.78, 0.22, 1)
  local minimal = S.barStyle == 2
  -- event feed: clean chips rising above the bar
  for i, f in ipairs(HESI.feed) do
    local a = clamp(1 - (f.t - 2) / 1, 0, 1) * clamp(f.t * 8, 0, 1)
    local y = 72 - (i - 1) * 26 - f.t * 5
    if y > -10 and a > 0.01 then
      local size = f.big and 17 or 14
      local oldA = D.a
      D.a = a
      local w = measure(f.text, size, F.numb).x + 30
      rect(cx - w / 2, y, cx + w / 2, y + size + 10, rgbm(0.03, 0.03, 0.04, 0.72), (size + 10) / 2)
      rect(cx - w / 2 + 8, y + 7, cx - w / 2 + 11, y + size + 3, f.color, 2)
      text(f.text, size, cx + 6, y + 4, T.white, F.numb, 0.5)
      D.a = oldA
    end
  end
  local y0 = 100
  if HESI.running then
    local hot = clamp(HESI.mult / 12, 0, 1)
    local bw = minimal and 300 or 480
    local bh = minimal and 50 or 64
    local x1, x2 = cx - bw / 2, cx + bw / 2
    -- glass bar
    rect(x1, y0, x2, y0 + bh, rgbm(0.03, 0.03, 0.04, 0.78), bh / 2)
    ui.drawRectFilledMultiColor(P(x1 + bh / 2, y0), P(x2 - bh / 2, y0 + 1.5), A(rgbm(1, 1, 1, 0)), A(rgbm(1, 1, 1, 0)), A(rgbm(1, 1, 1, 0.25)), A(rgbm(1, 1, 1, 0.25)))
    rectLine(x1, y0, x2, y0 + bh, A(mix(ac1, gold, hot), 0.35 + hot * 0.5), bh / 2, 1.5)
    -- combo timer underline
    local frac = clamp(HESI.combo / HESI.comboMax, 0, 1)
    rect(x1 + bh / 2, y0 + bh - 3, x1 + bh / 2 + (bw - bh) * frac, y0 + bh - 1, mix(ac1, gold, hot), 1)
    if minimal then
      text(HESI.fmt(HESI.run), 30, cx - 20, y0 + 7, T.white, F.numb, 0.5)
      text(string.format('x%.1f', HESI.mult), 20, x2 - 22, y0 + 13, gold, F.numb, 1)
    else
      -- multiplier
      text(string.format('x%.1f', HESI.mult), 26, x1 + 34, y0 + 14, gold, F.numb, 0)
      local tier = HESI.tier()
      if tier ~= '' then text(tier, 9, x1 + 36, y0 + 46, rgbm(1, 0.8, 0.3, 0.85), F.b) end
      -- score
      text(HESI.fmt(HESI.run), 38, cx, y0 + 8, T.white, F.numb, 0.5)
      -- PB progress
      if S.hesiPB > 0 then
        local pbt = clamp(HESI.run / S.hesiPB, 0, 1)
        rect(cx - 70, y0 + 52, cx + 70, y0 + 54, rgbm(1, 1, 1, 0.12), 1)
        rect(cx - 70, y0 + 52, cx - 70 + 140 * pbt, y0 + 54, pbt >= 1 and T.green or rgbm(1, 1, 1, 0.6), 1)
      end
      -- speed
      local car = ac.getCar(0)
      text(tostring(math.floor(car and car.speedKmh or 0)), 26, x2 - 58, y0 + 12, T.white, F.numb, 1)
      text('KM/H', 9, x2 - 30, y0 + 22, T.label2, F.b, 0.5)
    end
    if HESI.slowT > 0.3 then
      local w = 170
      rect(cx - w / 2, y0 + bh + 6, cx + w / 2, y0 + bh + 28, rgbm(0.1, 0.55, 0.3, 0.92), 11)
      text(string.format('BANKING  %.1f', math.max(0, 3 - HESI.slowT)), 12, cx, y0 + bh + 10, T.white, F.numb, 0.5)
    end
  else
    local label = S.hesiOn and ('@BURN  PB ' .. HESI.fmt(S.hesiPB) .. '   ·   ' .. HESI.startSpeed .. '+ KM/H TO START') or '@BURN  CUT-UP OFF'
    local w = measure(label, 12, F.numb).x + 34
    rect(cx - w / 2, y0 + 24, cx + w / 2, y0 + 52, rgbm(0.03, 0.03, 0.04, 0.6), 14)
    text(label, 12, cx, y0 + 31, rgbm(1, 1, 1, 0.85), F.numb, 0.5)
  end
  if HESI.crashFlash > 0 then
    local oldA = D.a D.a = HESI.crashFlash
    text('CRASHED', 30, cx, 22, T.red, F.numb, 0.5)
    D.a = oldA
  elseif HESI.bankFlash > 0 then
    local oldA = D.a D.a = HESI.bankFlash
    text('BANKED +' .. HESI.fmt(HESI.lastBank), 28, cx, 22, rgbm(0.35, 1, 0.55, 1), F.numb, 0.5)
    D.a = oldA
  end
end

-- ===========================================================================
-- Background work
-- ===========================================================================

local started = false
function script.update(dt)
  if not started then
    started = true
    setTimeout(function()
      if ac.getSim().isOnlineRace then
        broadcastPresence()
        pcall(skinRequest, { received = true })
      end
      if S.plateAutoApply and PL.text ~= '' then PL.apply(0, PL.text, PL.country) PL.broadcast() end
      UPD.announce()
      if S.actionBar then ac.setWindowOpen('actionbar', true) end
      local lv = LIVERY_API.cfg()
      if lv and lv.on then LIVERY_API.apply(0, lv) LIVERY_API.broadcast() end
    end, 2)
  end
  if phoneButton and phoneButton:pressed() then
    ac.setWindowOpen('main', not ac.isWindowOpen('main'))
  end
  shutterTick()
  PL.update()
  liveUpdate()
  UPD.tick()
  HESI.update(dt)
  -- walking/video/photo stop if the phone is closed while minimised? keep running; chase handled in camUpdate
end

end
