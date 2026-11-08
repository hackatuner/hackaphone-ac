--[[
  HackaPhone (formerly AC Phone)  -  iPhone-style phone for Assetto Corsa (CSP Lua app)
  by smartnajeeri, built with Claude

  Apps: Messages, Friends, Camera, Walk, Video, Chase Cam, Plates, Skins, Weather, App Library, Settings.
  Skin swapping technique adapted from Skin Companion by Ligneel; plate rendering uses CSP's shared plates module,
  network formats compatible with Hacka Plates and Skin Companion so friends using those apps stay in sync.
]]

local VERSION = '1.6.2'
local BUILD = 48
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
  phoneScale = 1.0,
  barScale = 1.0,
  musicBlur = true,
  iconStyle = 1,
  barStyle = 1,
  hiddenApps = '',
  liveryPresets = '[]',
  skinFavs = '',
  hesiOn = true,
  homeLayout = '', raceLB = '', camTweaks = '',
  carHeadOn = false, carHeadCol = 1, carHeadPow = 1.0, carTailOn = false, carTailCol = 3, carTailPow = 1.0,
  hesiPB = 0,
  hesiTotal = 0,
  hesiRuns = 0,
  hesiNear = 0,
  hesiCrew = '{}',
  -- economy
  cash = 1000, saved = 0, savedAt = 0, listSeq = 0, pwEquip = '', title = 'rookie',
  perks = '{}', titles = '{}', hold = '{}', inv = '{}', txLog = '[]', runLog = '[]', myList = '[]',
  -- race mode
  raceWins = 0, raceLosses = 0, raceStreak = 0, raceBests = '{}', raceLog = '[]', userLog = '{}',
  -- camera angles
  shotCfg = '{}', shotPresets = '{}',
  -- welcome screen
  welcomeOn = true, welcomeTitle = 'Welcome back', welcomeTag = 'Let\'s cut some traffic', welcomeStyle = 1, welcomeSecs = 5,
  welcomeStats = true, greetJoin = true, welcomeSeen = '',
  -- music
  musicArtMode = 2, musicBlurAmt = 0.6, vaultFolder = '', vaultVol = 0.85, vaultShuffle = false, vaultRepeat = 1, vaultLast = '', untitledUrl = 'https://untitled.stream',
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
  camHideApps = true, recApp = 1,
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
  { name = 'Clean', family = 'Calibri' },
  { name = 'Soft', family = 'Candara' },
  { name = 'Friendly', family = 'Trebuchet MS' },
  { name = 'Techno', family = 'Corbel' },
  { name = 'Wide', family = 'Verdana' },
  { name = 'Retro', family = 'Franklin Gothic Medium' },
  { name = 'Elegant', family = 'Georgia' },
  { name = 'Luxe', family = 'Palatino Linotype' },
  { name = 'Mono', family = 'Consolas' },
  { name = 'Rounded', family = 'Segoe UI Semibold' },
  { name = 'Impact', family = 'Impact' },
  { name = 'Handwritten', family = 'Segoe Print' },
  samples = {},
}

local function makeFont(weight, key, family)
  local f = ui.DWriteFont(family or 'Segoe UI', '@System')   -- system fonts need the @System collection
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
local SCREEN = { x = 14, y = 14, w = 352, h = 756, r = 33 } -- phone screen rect inside window

local function A(c, extra)
  local a = D.a * (extra or 1)
  if a >= 0.999 then return c end
  return rgbm(c.r, c.g, c.b, c.mult * a)
end

-- Global scale: the whole phone is drawn in design units (352x756 screen) and scaled uniformly,
-- so resizing never breaks the layout. Text and inputs are drawn unscaled at k-times size to stay sharp.
local GS = { k = 1, active = false, raw = false, pivot = vec2(0, 0) }

local function P(x, y)
  if GS.raw then return vec2((D.x + x) * GS.k, (D.y + y) * GS.k) end
  return vec2(D.x + x, D.y + y)
end

function GS.begin(k)
  GS.k = k or 1
  GS.active = math.abs(GS.k - 1) > 0.001
  if GS.active then ui.beginScale() end
end

function GS.finish()
  if GS.active then ui.endPivotScale(GS.k, GS.pivot) end
  GS.active = false
end

-- run fn outside the vertex scaling, with P() returning final (scaled) positions
function GS.unscaled(fn)
  if not GS.active then return fn() end
  ui.endPivotScale(GS.k, GS.pivot)
  GS.raw = true
  local ok, err = pcall(fn)
  GS.raw = false
  ui.beginScale()
  if not ok then error(err, 0) end
end

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
  if GS.active then
    GS.unscaled(function()
      ui.pushDWriteFont(font.f)
      ui.dwriteDrawText(s, size * GS.k, P(x, y), A(c or T.label))
      ui.popDWriteFont()
    end)
  else
    ui.pushDWriteFont(font.f)
    ui.dwriteDrawText(s, size, P(x, y), A(c or T.label))
    ui.popDWriteFont()
  end
end

-- text inside a box, wrapped, top-left aligned
local function textBox(s, size, x1, y1, x2, y2, c, font)
  local function draw()
    ui.pushDWriteFont((font or F.r).f)
    ui.dwriteDrawTextClipped(tostring(s), size * (GS.raw and GS.k or 1), P(x1, y1), P(x2, y2), ui.Alignment.Start, ui.Alignment.Start, true, A(c or T.label))
    ui.popDWriteFont()
  end
  if GS.active then GS.unscaled(draw) else draw() end
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
  ui.pushClipRect(p1 * GS.k, p2 * GS.k, true)
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
    local newV, e
    GS.unscaled(function()
      ui.pushStyleVar(ui.StyleVar.FramePadding, vec2(0, math.max(0, (h * GS.k - 16) / 2)))
      ui.pushStyleVar(ui.StyleVar.FrameBorderSize, 0)
      ui.setCursor(P(x + pad, y))
      ui.setNextItemWidth((w - pad - 8) * GS.k)
      local _
      newV, _, e = ui.inputText('##' .. id, value, opts.flags or 0)
      if opts.focus then ui.setKeyboardFocusHere(-1) end
      fieldState[id] = ui.itemActive()
      ui.popStyleVar(2)
    end)
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

-- ===========================================================================
-- Network pacing + health log. Every online message goes through one queue: the server drops anything that comes
-- too fast, so messages go out one at a time, most important first, and are retried until the game says they left.
-- ===========================================================================
local DIAG = { errs = {}, hitches = 0, worst = 0, frames = 0, cost = 0, since = clock() }
DIAG.cost, DIAG.peak = {}, {}
-- run one piece of per-frame work, remember how long it takes, and make sure its failure can't stop the rest
function DIAG.time(name, fn, a)
  local t0 = os.preciseClock()
  local ok, e = pcall(fn, a)
  local d = os.preciseClock() - t0
  DIAG.cost[name] = (DIAG.cost[name] or d) * 0.97 + d * 0.03
  if d > (DIAG.peak[name] or 0) then DIAG.peak[name] = d end
  if not ok then DIAG.err(name, e) end
end
-- A running log written to health_log.txt next to the phone, so a problem can be read afterwards without copy-pasting.
-- It stays on this PC; nothing is sent anywhere.
DIAG.lines, DIAG.marks, DIAG.dirty, DIAG.flushAt = {}, {}, false, 0
function DIAG.note(text)
  local l = DIAG.lines
  l[#l + 1] = os.date('%H:%M:%S') .. '  ' .. text
  while #l > 250 do table.remove(l, 1) end
  DIAG.dirty = true
end
function DIAG.mark(text)   -- remember what just happened, to explain the next hitch
  local m = DIAG.marks
  m[#m + 1] = { t = clock(), text = text }
  while #m > 6 do table.remove(m, 1) end
end
function DIAG.flush(force)
  if not DIAG.dirty or (not force and clock() < DIAG.flushAt) then return end
  DIAG.flushAt = clock() + 20
  DIAG.dirty = false
  pcall(function()
    local f = ac.getFolder(ac.FolderID.ScriptOrigin) .. '/health_log.txt'
    io.save(f, 'HackaPhone ' .. VERSION .. ' build ' .. BUILD .. '\n' .. table.concat(DIAG.lines, '\n') .. '\n', true)
  end)
end
function DIAG.err(tag, e)
  DIAG.note('ERROR [' .. tag .. '] ' .. tostring(e):gsub('%s+', ' '):sub(1, 160))
  local list = DIAG.errs
  local msg = tostring(e):gsub('%s+', ' '):sub(1, 140)
  for _, it in ipairs(list) do if it.tag == tag and it.msg == msg then it.n = it.n + 1 it.at = os.time() return end end
  table.insert(list, 1, { tag = tag, msg = msg, n = 1, at = os.time() })
  while #list > 30 do table.remove(list) end
end
local NET = { q = {}, nextAt = 0, sent = 0, dropped = 0, retried = 0 }
function NET.send(fn, prio, key)
  if key then for _, it in ipairs(NET.q) do if it.key == key then it.fn = fn return end end end
  NET.q[#NET.q + 1] = { fn = fn, prio = prio or 3, key = key, tries = 0 }
  if #NET.q > 60 then   -- never let a backlog build: drop the least important oldest
    local wi = 1
    for i, it in ipairs(NET.q) do if it.prio > NET.q[wi].prio then wi = i end end
    table.remove(NET.q, wi) NET.dropped = NET.dropped + 1
  end
end
function NET.tick()
  local now = clock()
  if now < NET.nextAt or #NET.q == 0 then return end
  local bi = 1
  for i, it in ipairs(NET.q) do if it.prio < NET.q[bi].prio then bi = i end end
  local it = NET.q[bi]
  local ok, sent = pcall(it.fn)
  it.tries = it.tries + 1
  if not ok then DIAG.err('net', sent) table.remove(NET.q, bi) NET.dropped = NET.dropped + 1 NET.nextAt = now + 0.1
  elseif sent ~= false then table.remove(NET.q, bi) NET.sent = NET.sent + 1 NET.nextAt = now + 0.25
  else
    NET.retried = NET.retried + 1
    NET.nextAt = now + 0.3
    if it.tries >= 10 then table.remove(NET.q, bi) NET.dropped = NET.dropped + 1 end
  end
end

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
-- Messaging (compatible with HackaPhone v0.1)
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
  NET.send(function() return sendPresence({ status = utf8Trim(S.status, 40) }) end, 3, 'presence')
end

local lastSend = -10
local function sendText(threadId, body)
  body = trim(body)
  if body == '' or clock() - lastSend < 0.35 then return false end
  body = utf8Trim(body, 140)
  NET.send(function() return sendMsg({ to = threadId, kind = 0, text = body }) end, 1)
  lastSend = clock()
  addMessage(threadId, nil, 'You', body, true, 0)
  return true
end

local function sendHonk(sid, name)
  NET.send(function() return sendMsg({ to = sid, kind = 1, text = 'HONK' }) end, 1)
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
  local t, c = tostring(msg.hackaPlateText), tostring(msg.hackaPlateCountry)
  local old = PL.others[sender.index]
  if old and old.text == t and old.country == c then return end   -- same plate again: nothing to redo
  PL.others[sender.index] = { text = t, country = c }
  PL.applied[sender.index] = nil
end)

local function plateBroadcast()
  if S.plateSync then NET.send(function() return plateEvent({ hackaPlateText = PL.text, hackaPlateCountry = PL.country }, true) end, 3, 'plate') end
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
    NET.send(function() return skinEvent({ AppBasedSkinID = SK.active[0] }) end, 3, 'skin')
  end
end, ac.SharedNamespace.Global, false)

local function skinSet(key)
  skinApply(0, key)
  if S.skinSync then local k = key or skinOriginal(0) NET.send(function() return skinEvent({ AppBasedSkinID = k }) end, 3, 'skin') end
end

SK.prettySkin = prettySkin
SK.skinScan = skinScan
SK.skinOriginal = skinOriginal
SK.skinActive = skinActive
SK.skinApply = skinApply
SK.skinSet = skinSet
end
-- ===========================================================================
-- Economy: wallet, bank, run payouts, power-ups, exchange, player-to-player trading,
-- and the run log. UI lives in 4d_apps4.lua. Hooks into Cut-Up via XM.eco.*
-- ===========================================================================

local XM = { rich = {}, listings = {}, pending = {} }

do
local jcache = {}
local function jget(key, def)
  local raw = S[key]
  local c = jcache[key]
  if c and c.raw == raw then return c.v end
  local ok, v = pcall(JSON.parse, raw)
  if not ok or type(v) ~= 'table' then v = def or {} end
  jcache[key] = { raw = raw, v = v }
  return v
end
local function jset(key, v)
  local raw = JSON.stringify(v)
  S[key] = raw
  jcache[key] = { raw = raw, v = v }
end
XM.jget, XM.jset = jget, jset

local function money(n)
  n = math.floor((n or 0) + 0.5)
  local neg = n < 0
  local out = tostring(math.abs(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse()
  if out:sub(1, 1) == ',' then out = out:sub(2) end
  return (neg and '-$' or '$') .. out
end
XM.money = money

-- ---------------------------------------------------------------- power-up catalogue
-- kind: mult (one slot) | fx (two slots) | crate (opens into another power-up)
local RC = { rgbm(0.62, 0.68, 0.78, 1), rgbm(0.30, 0.65, 1, 1), rgbm(0.75, 0.40, 1, 1), rgbm(1, 0.72, 0.2, 1) }
XM.rarityName = { 'COMMON', 'RARE', 'EPIC', 'LEGENDARY' }
XM.rarityColor = RC
local PW = {
  { id = 'x2',    name = 'Ember',        tag = '2x', kind = 'mult', val = 2,  price = 800,   rarity = 1, icon = '@BURN',   desc = 'Every point you score is doubled for your next run.' },
  { id = 'x3',    name = 'Blaze',        tag = '3x', kind = 'mult', val = 3,  price = 2000,  rarity = 2, icon = '@BURN',   desc = 'Triple points for your next run.' },
  { id = 'x5',    name = 'Inferno',      tag = '5x', kind = 'mult', val = 5,  price = 6500,  rarity = 3, icon = '@BURN',   desc = 'Five times the points. Big PBs live here.' },
  { id = 'x7',    name = 'Supernova',    tag = '7x', kind = 'mult', val = 7,  price = 16000, rarity = 3, icon = '@BURN',   desc = 'Seven times the points for one run.' },
  { id = 'x10',   name = 'Singularity',  tag = '10x', kind = 'mult', val = 10, price = 45000, rarity = 4, icon = '@BURN',  desc = 'Ten times the points. One run to bend the leaderboard.' },
  { id = 'shield', name = 'Ghost Shield', tag = 'SAVE', kind = 'fx', price = 1500,  rarity = 2, icon = '@PADLOCK', desc = 'Soaks up one crash so your run keeps going.' },
  { id = 'magnet', name = 'Traffic Magnet', tag = '+60%', kind = 'fx', price = 1200, rarity = 2, icon = '@TARGET', desc = 'Near misses, close calls, oncoming and lane splits pay 60% more.' },
  { id = 'hyper',  name = 'Hyper Combo', tag = '+4s', kind = 'fx', price = 1000, rarity = 1, icon = '@STOPWATCH', desc = 'Your combo timer lasts 4 seconds longer.' },
  { id = 'warp',   name = 'Time Warp',   tag = 'SLOW', kind = 'fx', price = 2200, rarity = 3, icon = '@HOURGLASS', desc = 'Your combo timer drains at less than half speed.' },
  { id = 'lucky',  name = 'Lucky Charm', tag = '777', kind = 'fx', price = 1800, rarity = 2, icon = '@DICE', desc = '1 in 8 events hits a JACKPOT and pays triple.' },
  { id = 'drive',  name = 'Overdrive',   tag = '2x MULT', kind = 'fx', price = 2500, rarity = 3, icon = '@UP_ALT', desc = 'Your multiplier climbs twice as fast.' },
  { id = 'cow',    name = 'Cash Cow',    tag = '$x3', kind = 'fx', price = 1400, rarity = 2, icon = '@STATS', desc = 'The run pays triple cash, whether you bank it or crash it.' },
  { id = 'quick',  name = 'Quick Bank',  tag = '1.2s', kind = 'fx', price = 700, rarity = 1, icon = '@FLAG', desc = 'Banking takes 1.2 seconds of slow driving instead of 3.' },
  { id = 'head',   name = 'Head Start',  tag = 'x3', kind = 'fx', price = 900, rarity = 1, icon = '@NAVIGATION', desc = 'Your run begins at a x3 multiplier.' },
  { id = 'hunter', name = 'PB Hunter',   tag = '+25%', kind = 'fx', price = 3500, rarity = 3, icon = '@TROPHY', desc = 'Beat your personal best and the banked score gets 25% extra.' },
  { id = 'crate',  name = 'Mystery Crate', tag = '???', kind = 'crate', price = 1000, rarity = 2, icon = '@APPS', desc = 'Opens into a random power-up. Might be a Singularity.' },
}
local PW_BY = {}
for i, p in ipairs(PW) do p.n = i PW_BY[p.id] = p end
XM.PW, XM.PW_BY = PW, PW_BY

-- exchange assets
local TOKENS = {
  { id = 'CUT',  n = 101, name = 'Cut Coin',     base = 120, vol = 0.45, ph = 0.0, icon = '@BURN' },
  { id = 'NOS',  n = 102, name = 'Nitro Bond',   base = 400, vol = 0.24, ph = 2.1, icon = '@FUEL' },
  { id = 'GRIP', n = 103, name = 'Grip Index',   base = 45,  vol = 0.12, ph = 4.2, icon = '@STEERING_WHEEL' },
}
local TOK_BY = {}
for _, t in ipairs(TOKENS) do TOK_BY[t.id] = t TOK_BY[t.n] = t end
XM.TOKENS, XM.TOK_BY = TOKENS, TOK_BY

-- every phone computes the same price from the clock, so the whole server sees one live market
local function priceAt(t, ts)
  local x = ts
  local w = 0.5 * math.sin(x / 1800 * 6.2832 + t.ph) + 0.3 * math.sin(x / 420 * 6.2832 + t.ph * 1.7) + 0.2 * math.sin(x / 95 * 6.2832 + t.ph * 2.3)
  -- Nitro Bond grows tenfold over ten minutes from the release moment, the same on every phone
  local g = t.id == 'NOS' and (1 + 10 * math.max(0, math.min(1, (ts - 1794083935) / 600))) or 1
  return math.max(t.base * 0.2, t.base * (1 + t.vol * w)) * g
end
XM.priceAt = priceAt
function XM.price(id) return priceAt(TOK_BY[id], os.time()) end

-- titles (cosmetic products)
XM.TITLES = {
  { id = 'rookie',  name = 'Rookie',        price = 0 },
  { id = 'weaver',  name = 'Traffic Weaver', price = 4000 },
  { id = 'ghost',   name = 'Ghost',          price = 15000 },
  { id = 'king',    name = 'Cut-Up King',    price = 40000 },
  { id = 'untouch', name = 'Untouchable',    price = 90000 },
  { id = 'whale',   name = 'Whale',          price = 250000 },
}
XM.PERKS = {
  { id = 'pay',  name = 'Better Payouts', desc = '+10% cash from every run, per level.', icon = '@STATS', base = 3000, max = 5 },
  { id = 'int',  name = 'Savings Boost',  desc = '+0.1% interest per minute, per level.', icon = '@UP_ALT', base = 4000, max = 5 },
  { id = 'luck', name = 'Crate Luck',     desc = 'Mystery Crates favour rarer power-ups, per level.', icon = '@DICE', base = 5000, max = 5 },
}
function XM.perkLevel(id) return (jget('perks', {})[id] or 0) end
function XM.perkPrice(p) return p.base * 2 ^ XM.perkLevel(p.id) end
function XM.buyPerk(p)
  local lv = XM.perkLevel(p.id)
  if lv >= p.max then return false end
  if not XM.spend(XM.perkPrice(p), p.name .. ' level ' .. (lv + 1)) then return false end
  local t = jget('perks', {}) t[p.id] = lv + 1 jset('perks', t)
  return true
end
function XM.buyTitle(tt)
  local owned = jget('titles', { rookie = true })
  if owned[tt.id] then S.title = tt.id return true end
  if not XM.spend(tt.price, 'Title: ' .. tt.name) then return false end
  owned[tt.id] = true jset('titles', owned) S.title = tt.id
  return true
end
function XM.titleName()
  for _, t in ipairs(XM.TITLES) do if t.id == S.title then return t.name end end
  return 'Rookie'
end

-- ---------------------------------------------------------------- wallet
function XM.cash() return math.floor(S.cash) end
function XM.log(a, why)
  local log = jget('txLog', {})
  table.insert(log, 1, { t = os.time(), a = math.floor(a), why = why })
  while #log > 60 do table.remove(log) end
  jset('txLog', log)
end
function XM.add(a, why)
  a = math.floor(a)
  if a == 0 then return end
  S.cash = XM.cash() + a
  XM.log(a, why or 'Income')
end
function XM.spend(a, why)
  a = math.floor(a)
  if a > XM.cash() then return false end
  S.cash = XM.cash() - a
  XM.log(-a, why or 'Purchase')
  return true
end

-- ---------------------------------------------------------------- inventory + loadout
function XM.have(id) return (jget('inv', {})[id] or 0) end
function XM.give(id, n)
  local inv = jget('inv', {})
  inv[id] = math.max(0, (inv[id] or 0) + n)
  if inv[id] == 0 then inv[id] = nil end
  jset('inv', inv)
end
function XM.buyPW(p, qty)
  qty = qty or 1
  if not XM.spend(p.price * qty, p.name .. (qty > 1 and (' x' .. qty) or '')) then return false end
  XM.give(p.id, qty)
  return true
end

local function equippedList()
  local out = {}
  for id in tostring(S.pwEquip):gmatch('[^,]+') do if PW_BY[id] then out[#out + 1] = id end end
  return out
end
XM.equippedList = equippedList
function XM.isEquipped(id)
  for _, e in ipairs(equippedList()) do if e == id then return true end end
  return false
end
function XM.toggleEquip(id)
  local p = PW_BY[id]
  if not p or p.kind == 'crate' then return end
  local list = equippedList()
  for i, e in ipairs(list) do if e == id then table.remove(list, i) S.pwEquip = table.concat(list, ',') return end end
  if p.kind == 'mult' then
    for i = #list, 1, -1 do if PW_BY[list[i]].kind == 'mult' then table.remove(list, i) end end
  else
    local fx = 0
    for _, e in ipairs(list) do if PW_BY[e].kind == 'fx' then fx = fx + 1 end end
    if fx >= 2 then
      for i, e in ipairs(list) do if PW_BY[e].kind == 'fx' then table.remove(list, i) break end end
    end
  end
  list[#list + 1] = id
  S.pwEquip = table.concat(list, ',')
end

-- loot table for crates; Crate Luck pushes weight towards rarer drops
function XM.openCrate()
  if XM.have('crate') < 1 then return nil end
  XM.give('crate', -1)
  local luck = XM.perkLevel('luck')
  local weights = { x2 = 22, x3 = 11, x5 = 3.5 + luck, x7 = 1.2 + luck * 0.6, x10 = 0.4 + luck * 0.4, shield = 10, magnet = 10, hyper = 12,
    warp = 5, lucky = 8, drive = 5, cow = 10, quick = 14, head = 12, hunter = 4 }
  local total = 0
  for _, w in pairs(weights) do total = total + w end
  local r = math.random() * total
  local pick = 'x2'
  for _, p in ipairs(PW) do
    local w = weights[p.id]
    if w then r = r - w if r <= 0 then pick = p.id break end end
  end
  XM.give(pick, 1)
  return PW_BY[pick]
end

-- called when a run starts: arm the equipped power-ups, spend one of each
function XM.armRun()
  local fx = { names = {} }
  for _, id in ipairs(equippedList()) do
    local p = PW_BY[id]
    if p and XM.have(id) > 0 then
      XM.give(id, -1)
      if p.kind == 'mult' then fx.mult = p.val else fx[id] = true end
      fx.names[#fx.names + 1] = p.tag == p.name and p.name or (p.kind == 'mult' and p.tag or p.name)
      if XM.have(id) == 0 then -- ran out: unequip so the loadout stays honest
        local list = equippedList()
        for i, e in ipairs(list) do if e == id then table.remove(list, i) break end end
        S.pwEquip = table.concat(list, ',')
      end
    end
  end
  return fx
end

-- ---------------------------------------------------------------- run payouts + log
function XM.payoutFor(score, crashed, fx)
  local base
  base = 60 + score * 0.04   -- crash or bank, a run pays the same
  local mult = 1 + 0.1 * XM.perkLevel('pay')
  if fx and fx.cow then mult = mult * 3 end
  return math.floor(base * mult)
end

function XM.recordRun(r)
  local log = jget('runLog', {})
  table.insert(log, 1, r)
  while #log > 120 do table.remove(log) end
  jset('runLog', log)
end

-- ---------------------------------------------------------------- savings + exchange
function XM.saved() return math.floor(S.saved) end
function XM.deposit(a)
  a = math.floor(math.min(a, XM.cash()))
  if a <= 0 then return end
  S.cash = XM.cash() - a
  S.saved = XM.saved() + a
  XM.log(-a, 'To savings')
end
function XM.withdraw(a)
  a = math.floor(math.min(a, XM.saved()))
  if a <= 0 then return end
  S.saved = XM.saved() - a
  S.cash = XM.cash() + a
  XM.log(a, 'From savings')
end
function XM.rate() return 0.004 + 0.001 * XM.perkLevel('int') end   -- per minute
local function accrue()
  local now = os.time()
  if S.savedAt <= 0 then S.savedAt = now return end
  local mins = math.floor((now - S.savedAt) / 60)
  if mins >= 1 then
    S.savedAt = S.savedAt + mins * 60
    if XM.saved() > 0 then
      mins = math.min(mins, 600)   -- offline earnings stop after 10 hours
      local before = XM.saved()
      S.saved = math.floor(before * (1 + XM.rate()) ^ mins)
      XM.interestEarned = (XM.interestEarned or 0) + (S.saved - before)
    end
  end
end

function XM.holdings() return jget('hold', {}) end
function XM.holdValue()
  local v = 0
  for id, h in pairs(XM.holdings()) do if TOK_BY[id] then v = v + h.n * XM.price(id) end end
  return v
end
function XM.buyToken(id, qty)
  local px = XM.price(id)
  local cost = math.ceil(px * qty * 1.01)
  if not XM.spend(cost, 'Bought ' .. qty .. ' ' .. id) then return false end
  local h = XM.holdings()
  local e = h[id] or { n = 0, cost = 0 }
  e.n, e.cost = e.n + qty, e.cost + cost
  h[id] = e jset('hold', h)
  return true
end
function XM.sellToken(id, qty)
  local h = XM.holdings()
  local e = h[id]
  if not e or e.n < qty then return false end
  local gain = math.floor(XM.price(id) * qty * 0.99)
  local costPart = e.cost * (qty / e.n)
  e.n, e.cost = e.n - qty, e.cost - costPart
  if e.n <= 0 then h[id] = nil end
  jset('hold', h)
  XM.add(gain, 'Sold ' .. qty .. ' ' .. id)
  return true, gain - costPart
end
function XM.netWorth() return XM.cash() + XM.saved() + XM.holdValue() end

-- ---------------------------------------------------------------- online: payments + player market
local ecoSend
local pendingBuy = {}
local function myName() return ac.getDriverName(0) or 'You' end
local function itemName(n)
  if TOK_BY[n] then return TOK_BY[n].name end
  for _, p in ipairs(PW) do if p.n == n then return p.name end end
  return 'item'
end
local function itemId(n)
  if TOK_BY[n] then return TOK_BY[n].id end
  for _, p in ipairs(PW) do if p.n == n then return p.id end end
end
XM.itemName, XM.itemId = itemName, itemId

local function giveItem(n, qty)
  if TOK_BY[n] then
    local h = XM.holdings()
    local e = h[TOK_BY[n].id] or { n = 0, cost = 0 }
    e.n, e.cost = e.n + qty, e.cost + XM.price(TOK_BY[n].id) * qty
    h[TOK_BY[n].id] = e jset('hold', h)
  else
    XM.give(itemId(n), qty)
  end
end
local function takeItem(n, qty)
  if TOK_BY[n] then
    local h = XM.holdings()
    local e = h[TOK_BY[n].id]
    if not e or e.n < qty then return false end
    e.cost = e.cost * ((e.n - qty) / e.n)
    e.n = e.n - qty
    if e.n <= 0 then h[TOK_BY[n].id] = nil end
    jset('hold', h)
    return true
  end
  if XM.have(itemId(n)) < qty then return false end
  XM.give(itemId(n), -qty)
  return true
end
XM.giveItem, XM.takeItem = giveItem, takeItem

local function send(d)
  if not ecoSend then return end
  d.kind = d.kind or 0
  d.to, d.id, d.item, d.qty, d.price = d.to or 0, d.id or 0, d.item or 0, d.qty or 0, d.price or 0
  d.wealth = math.floor(math.min(XM.netWorth(), 2100000000))
  if d.kind == 0 then NET.send(function() return ecoSend(d) end, 3, 'wealth') else NET.send(function() return ecoSend(d) end, 2) end
end
XM.ecoBeacon = function() send({ kind = 0 }) end

ecoSend = ac.OnlineEvent({
  ac.StructItem.key('acphone.eco.v1'),
  kind = ac.StructItem.byte(), to = ac.StructItem.int32(), id = ac.StructItem.int32(),
  item = ac.StructItem.byte(), qty = ac.StructItem.int16(), price = ac.StructItem.int32(), wealth = ac.StructItem.int32(),
}, function(sender, d)
  if not sender or sender.index == 0 then return end
  local name = ac.getDriverName(sender.index) or '?'
  local sid = sender.sessionID
  XM.rich[sid] = { name = name, wealth = d.wealth, at = clock() }
  local me = mySessionID()
  if d.kind == 2 and d.to == me then                      -- money sent to me
    XM.add(d.price, 'From ' .. name)
    notify(name .. ' sent you ' .. money(d.price), 'Added to your balance', '💾', nil, { force = true })
  elseif d.kind == 3 then                                 -- listing (re)announced
    XM.listings[sid .. ':' .. d.id] = { sid = sid, id = d.id, seller = name, item = d.item, qty = d.qty, price = d.price, at = clock() }
  elseif d.kind == 4 then
    XM.listings[sid .. ':' .. d.id] = nil
  elseif d.kind == 5 and d.to == me then                  -- someone wants to buy my listing
    local mine = jget('myList', {})
    for i, l in ipairs(mine) do
      if l.id == d.id then
        table.remove(mine, i) jset('myList', mine)
        XM.add(l.price, 'Sold ' .. itemName(l.item) .. ' to ' .. name)
        send({ kind = 6, to = sid, id = l.id, item = l.item, qty = l.qty, price = l.price })
        send({ kind = 4, id = l.id })
        notify(name .. ' bought ' .. itemName(l.item), '+' .. money(l.price), '💾', nil, { force = true })
        return
      end
    end
    send({ kind = 6, to = sid, id = d.id, item = d.item, qty = 0, price = d.price })   -- already gone
  elseif d.kind == 6 and d.to == me then                  -- result of my purchase
    local key = sid .. ':' .. d.id
    local pend = pendingBuy[key]
    if not pend then return end
    pendingBuy[key] = nil
    if d.qty > 0 then
      giveItem(d.item, d.qty)
      XM.log(0, 'Got ' .. d.qty .. 'x ' .. itemName(d.item) .. ' from ' .. name)
      notify('Purchase complete', d.qty .. 'x ' .. itemName(d.item) .. ' from ' .. name, '💾', nil, { force = true })
    else
      XM.add(pend.price, 'Refund: listing gone')
      toast('Too slow', 'That listing was already sold. You were refunded.', '⚠️')
    end
    XM.listings[key] = nil
  end
end)

function XM.sendMoney(sid, name, amount)
  amount = math.floor(amount)
  if amount <= 0 or not XM.spend(amount, 'Sent to ' .. name) then return false end
  send({ kind = 2, to = sid, price = amount })
  return true
end

function XM.listItem(n, qty, price)
  if qty < 1 or price < 1 then return false end
  if not takeItem(n, qty) then return false end
  local mine = jget('myList', {})
  S.listSeq = (S.listSeq + 1) % 30000
  mine[#mine + 1] = { id = S.listSeq, item = n, qty = qty, price = math.floor(price) }
  jset('myList', mine)
  send({ kind = 3, id = S.listSeq, item = n, qty = qty, price = math.floor(price) })
  return true
end
function XM.unlist(id)
  local mine = jget('myList', {})
  for i, l in ipairs(mine) do
    if l.id == id then
      table.remove(mine, i) jset('myList', mine)
      giveItem(l.item, l.qty)
      send({ kind = 4, id = id })
      return true
    end
  end
end
function XM.buyListing(l)
  if pendingBuy[l.sid .. ':' .. l.id] then return false end
  if not XM.spend(l.price, 'Buying ' .. itemName(l.item)) then return false end
  pendingBuy[l.sid .. ':' .. l.id] = { price = l.price, at = clock() }
  send({ kind = 5, to = l.sid, id = l.id, item = l.item, price = l.price })
  return true
end
function XM.isPending(l) return pendingBuy[l.sid .. ':' .. l.id] ~= nil end

function XM.marketRows()
  local rows = {}
  for k, l in pairs(XM.listings) do
    if clock() - l.at > 75 then XM.listings[k] = nil else rows[#rows + 1] = l end
  end
  table.sort(rows, function(a, b) return (a.price / math.max(1, a.qty)) < (b.price / math.max(1, b.qty)) end)
  return rows
end
function XM.richList()
  local rows = { { name = myName(), wealth = XM.netWorth(), me = true } }
  for sid, r in pairs(XM.rich) do
    if clock() - r.at < 120 then rows[#rows + 1] = { name = r.name, wealth = r.wealth } end
  end
  table.sort(rows, function(a, b) return a.wealth > b.wealth end)
  return rows
end

local tickAt, listAt, accAt = 0, 0, 0
function XM.tick(dt)
  local now = clock()
  if now > accAt then accAt = now + 5 accrue() end
  -- refund purchases that never got an answer (seller left the server)
  for key, p in pairs(pendingBuy) do
    if now - p.at > 15 then
      pendingBuy[key] = nil
      XM.add(p.price, 'Refund: seller offline')
    end
  end
  if not ac.getSim().isOnlineRace then return end
  if now > tickAt then tickAt = now + 12 send({ kind = 1 }) end
  if now > listAt then
    listAt = now + 20
    for _, l in ipairs(jget('myList', {})) do send({ kind = 3, id = l.id, item = l.item, qty = l.qty, price = l.price }) end
  end
end

-- Cut-Up hooks (called from 2d_hesi.lua)
function XM.onRunEnd(summary, crashed, fx)
  local pay = XM.payoutFor(summary.score, crashed, fx)
  if summary.pb and fx and fx.hunter then pay = math.floor(pay * 1.25) end
  XM.add(pay, crashed and 'Run banked (crashed)' or (summary.pb and 'Run banked · new PB' or 'Run banked'))
  summary.pay = pay
  local car = ac.getCarName(0) or '?'
  XM.recordRun({
    t = os.time(), score = summary.score, crashed = crashed and true or false, pb = summary.pb and true or false, car = car,
    track = ac.getTrackName and ac.getTrackName() or '', top = math.floor(summary.top or 0), avg = math.floor(summary.avg or 0),
    time = math.floor(summary.time or 0), mult = summary.maxMult or 1, near = summary.near or 0, close = summary.close or 0,
    split = summary.split or 0, oncoming = summary.oncoming or 0, pay = pay, boost = fx and fx.mult or 1,
    fx = fx and table.concat(fx.names or {}, ', ') or '',
  })
  return pay
end

-- say hi to a new player, but only from one phone (the longest-connected) so chat isn't flooded
function XM.greet(name, sid)
  if not (S.greetJoin and S.welcomeOn) or not presence[sid] then return end
  local me = mySessionID()
  for other in pairs(presence) do if other < me and other ~= sid then return end end
  pcall(sendText, GROUP, 'Welcome to the server, ' .. name .. '!')
end
end
-- ===========================================================================
-- Race mode: challenge a friend (distance races, speed pulls, rolling starts, cash wagers),
-- live tracker, full timing sheet, and solo runs with personal records.
-- UI lives in 4e_apps5.lua. The HUD is drawn in the action bar window.
-- ===========================================================================

XM.race = { state = 'idle', cur = nil, run = nil, soloResult = nil, hudFade = 0 }

do
local R = XM.race
local MILE, QMILE, EMILE = 1609.344, 402.336, 201.168

-- kind 1 = distance (x metres), kind 2 = speed pull (y km/h up to x km/h)
R.PRESETS = {
  { id = 'e8',   name = '1/8 mile',  kind = 1, x = EMILE,  y = 0 },
  { id = 'q4',   name = '1/4 mile',  kind = 1, x = QMILE,  y = 0 },
  { id = 'h2',   name = '1/2 mile',  kind = 1, x = QMILE * 2, y = 0 },
  { id = 'm1',   name = '1 mile',    kind = 1, x = MILE,   y = 0 },
  { id = 'k1',   name = '1 km',      kind = 1, x = 1000,   y = 0 },
  { id = 'p60',  name = '0-60 mph',  kind = 2, x = 96.56,  y = 0 },
  { id = 'p100', name = '0-100',     kind = 2, x = 100,    y = 0 },
  { id = 'p200', name = '0-200',     kind = 2, x = 200,    y = 0 },
  { id = 'p300', name = '0-300',     kind = 2, x = 300,    y = 0 },
  { id = 'r100', name = '100-200',   kind = 2, x = 200,    y = 100 },
  { id = 'r60',  name = '60-130',    kind = 2, x = 130,    y = 60 },
  { id = 'full', name = 'Full pull', kind = 2, x = 250,    y = 0 },
}
local DIST_MARKS = { { 18.288, '60 ft' }, { 100, '100 m' }, { EMILE, '1/8 mi' }, { QMILE, '1/4 mi' }, { QMILE * 2, '1/2 mi' }, { 1000, '1 km' }, { MILE, '1 mi' } }
local SPEED_MARKS = { { 100, '0-100' }, { 160, '0-160' }, { 200, '0-200' }, { 250, '0-250' }, { 300, '0-300' } }

function R.specName(sp)
  for _, p in ipairs(R.PRESETS) do if p.kind == sp.kind and math.abs(p.x - sp.x) < 0.5 and p.y == sp.y then return p.name end end
  if sp.kind == 1 then
    return sp.x >= 1000 and string.format('%.2f km', sp.x / 1000) or string.format('%d m', sp.x)
  end
  return sp.y .. '-' .. sp.x
end
local function specKey(sp) return sp.kind .. ':' .. math.floor(sp.x) .. ':' .. sp.y end
function R.specCode(sp) return sp.kind .. ':' .. sp.x .. ':' .. sp.y end

function R.busy() return R.run ~= nil and (R.run.phase == 'countdown' or R.run.phase == 'running') end

-- ---------------------------------------------------------------- network
local raceSend
-- Servers drop messages that come too fast or too close to other traffic, so everything goes through an outbox:
-- one message at a time, retried until the game confirms it left, and the important ones are sent again a bit later.
local function push(msg)
  NET.send(function() return raceSend(msg) end, 1, msg.kind == 6 and 'race6' or nil)
end
local function send(kind, to, f)
  if not raceSend then return end
  f = f or {}
  local c = R.cur
  local msg = {
    kind = kind, to = to or (c and c.oppSid) or 0, rid = f.rid or (c and c.rid) or 0, rtype = f.rtype or 0,
    x = math.floor(f.x or 0), y = math.floor(f.y or 0), wager = math.floor(f.wager or 0),
    t = f.t or 0, react = f.react or 0, d = f.d or 0, v = math.floor(f.v or 0), flags = f.flags or 0,
  }
  push(msg)
  if kind ~= 1 and kind ~= 6 then      -- everything except the invite (re-sent while waiting) and progress is repeated, receivers ignore duplicates
    setTimeout(function() push(msg) end, 1.3)
    setTimeout(function() push(msg) end, 3.1)
  end
end
function R.pump() end

local function reset()
  R.state, R.cur, R.run = 'idle', nil, nil
end
R.reset = reset

local function refund()
  local c = R.cur
  if c and c.escrow and c.wager > 0 then XM.add(c.wager, 'Race wager refunded') end
  if c then c.escrow = false end
end

-- never throw away a finished race that hasn't been paid yet: settle it (or give the wager back) before anything resets it
local function resolveNow() if R.resolveFn then R.resolveFn() end end
function R.settle()
  local c = R.cur
  if not c or c.outcome or R.state ~= 'finished' then return end
  if c.my and c.opp and c.opp.fin then resolveNow()
  elseif c.my then
    -- their result never arrived: don't leave the wager stuck
    if c.my.dnf then resolveNow() else refund() end
  end
end

local function openUI() if R.openUI then R.openUI() end end

local function newRun(spec, mode)
  return { spec = spec, mode = mode, phase = 'armed', t = 0, d = 0, v = 0, prevV = 0, top = 0, splits = {}, timing = false,
    fromZero = spec.y == 0, falseStart = false, car = ac.getCarName(0) or '?' }
end

function R.startCountdown()
  local c = R.cur
  R.run = newRun(c.spec, 'race')
  R.run.phase = 'countdown'
  R.run.goAt = clock() + 5.2
  R.state = 'countdown'
  c.my, c.outcome = nil, nil
  c.opp = { d = 0, v = 0, at = clock() }
  if not ac.isWindowOpen('actionbar') then ac.setWindowOpen('actionbar', true) end
end

local function logRace(c, outcome)
  local log = XM.jget('raceLog', {})
  table.insert(log, 1, { t = os.time(), opp = c.oppName, spec = R.specName(c.spec), win = outcome.win, mine = outcome.mine, theirs = outcome.theirs,
    wager = c.wager, car = ac.getCarName(0) or '?', track = ac.getTrackName and ac.getTrackName() or '', forfeit = outcome.forfeit })
  while #log > 60 do table.remove(log) end
  XM.jset('raceLog', log)
end

-- both times are in: decide it, pay out, keep the books
local function resolve(forfeitWin)
  local c = R.cur
  if not c or c.outcome then return end
  local mine = c.my and c.my.score
  local theirs = c.opp and c.opp.fin and c.opp.fin.score
  local o = { mine = mine, theirs = theirs }
  if forfeitWin then
    o.win, o.forfeit = true, true
  elseif c.my and c.my.dnf then o.win, o.forfeit = false, true
  elseif c.opp.fin and c.opp.fin.dnf then o.win, o.forfeit = true, true
  elseif mine and theirs then
    if math.abs(mine - theirs) < 0.0005 then o.win = nil else o.win = mine < theirs end
  else return end
  o.payout = 0
  if o.win == true then
    o.payout = c.wager * 2
    S.raceWins = S.raceWins + 1 S.raceStreak = S.raceStreak + 1 R.lbAt = 0
  elseif o.win == false then
    S.raceLosses = S.raceLosses + 1 S.raceStreak = 0
  else
    o.payout = c.wager
  end
  if o.payout > 0 and c.escrow then XM.add(o.payout, o.win and ('Won race vs ' .. c.oppName) or 'Race tie, wager back') end
  c.escrow = false
  c.outcome = o
  logRace(c, o)
  R.hudFade = 1
  if o.win == true then notify('You won the race', c.oppName .. (o.payout > 0 and (' · +' .. XM.money(o.payout)) or ''), '🏁', openUI, { force = true })
  elseif o.win == false then notify('You lost the race', c.oppName .. (c.wager > 0 and (' · -' .. XM.money(c.wager)) or ''), '🏁', openUI, { force = true }) end
end

R.resolveFn = function() resolve() end
local onEvent
raceSend = ac.OnlineEvent({
  ac.StructItem.key('acphone.race.v1'),
  kind = ac.StructItem.byte(), to = ac.StructItem.int32(), rid = ac.StructItem.int32(), rtype = ac.StructItem.byte(),
  x = ac.StructItem.int32(), y = ac.StructItem.int32(), wager = ac.StructItem.int32(),
  t = ac.StructItem.float(), react = ac.StructItem.float(), d = ac.StructItem.float(), v = ac.StructItem.int16(), flags = ac.StructItem.byte(),
}, function(sender, d) onEvent(sender, d) end)

onEvent = function(sender, d)
  if not sender or sender.index == 0 or d.to ~= mySessionID() then return end
  local sid = sender.sessionID
  local name = ac.getDriverName(sender.index) or '?'
  local c = R.cur
  if d.kind == 1 then                                         -- invite
    if c and c.rid == d.rid and c.oppSid == sid then return end   -- the same invite sent again
    if R.state == 'finished' or (R.state == 'idle' and R.run and not R.busy()) then R.settle() reset() end   -- stale result or armed solo pull
    if R.state ~= 'idle' or R.busy() then send(3, sid, { rid = d.rid, flags = 1 }) return end
    local spec = { kind = d.rtype, x = d.x, y = d.y }
    R.cur = { rid = d.rid, role = 'guest', oppSid = sid, oppName = name, spec = spec, wager = d.wager, at = clock(), opp = { d = 0, v = 0, at = clock() } }
    R.state = 'invited_in'
    notify(name .. ' wants to race you', R.specName(spec) .. (d.wager > 0 and (' · for ' .. XM.money(d.wager)) or ''), '🏁', openUI, { force = true })
  elseif not c or c.rid ~= d.rid or c.oppSid ~= sid then
    return
  elseif d.kind == 2 then                                     -- accepted
    if R.state ~= 'invited_out' then return end
    if c.wager > 0 and not XM.spend(c.wager, 'Race wager vs ' .. name) then
      send(4, sid) toast('Race cancelled', 'You can’t cover the wager', '⚠️') reset() return
    end
    c.escrow = c.wager > 0
    R.state = 'staging'
    notify(name .. ' accepted', 'Line up, then hit Start', '🏁', openUI, { force = true })
  elseif d.kind == 3 then                                     -- declined
    toast(name .. (d.flags == 1 and ' is busy' or ' declined'), 'No race this time', '🏁')
    reset()
  elseif d.kind == 4 then                                     -- cancelled
    if R.state == 'countdown' or R.state == 'racing' then R.run = nil end
    refund()
    toast('Race cancelled', name .. ' called it off', '🏁')
    reset()
  elseif d.kind == 5 then                                     -- GO: start the countdown
    if R.state == 'staging' then R.startCountdown() end
  elseif d.kind == 6 then                                     -- live progress
    c.opp.d, c.opp.v, c.opp.at = d.d, d.v, clock()
  elseif d.kind == 7 then                                     -- they finished
    if c.opp.fin then return end
    c.opp.fin = { t = d.t, react = d.react, trap = d.v, dnf = d.flags % 2 == 1, falseStart = d.flags >= 2, score = d.t + (d.flags >= 2 and 1 or 0), top = d.d }
    if c.my then resolve() end
  end
end
R.handle = onEvent

-- ---------------------------------------------------------------- leaderboard
-- every HackaPhone driver shares their best 0-60 mph, best 0-200 km/h and race wins; the crew board is remembered between sessions
local LB_KEYS = { t60 = '2:96:0', t200 = '2:200:0' }
function R.myBest(code)
  local best, car
  for _, b in pairs(XM.jget('raceBests', {})) do
    if b.spec and b.spec.kind == 2 and b.spec.y == 0 and (b.spec.kind .. ':' .. math.floor(b.spec.x) .. ':' .. b.spec.y) == code then
      if not best or b.t < best then best, car = b.t, b.car end
    end
  end
  return best, car
end
local lbSend
lbSend = ac.OnlineEvent({
  ac.StructItem.key('acphone.rlb.v1'),
  t60 = ac.StructItem.float(), t200 = ac.StructItem.float(), wins = ac.StructItem.int32(),
  car60 = ac.StructItem.string(24), car200 = ac.StructItem.string(24),
}, function(sender, d)
  if not sender or sender.index == 0 then return end
  local name = ac.getDriverName(sender.index)
  if not name or name == '' then return end
  local store = XM.jget('raceLB', {})
  store[name] = { t60 = d.t60 > 0 and d.t60 or nil, t200 = d.t200 > 0 and d.t200 or nil, wins = d.wins, car60 = d.car60, car200 = d.car200, at = os.time() }
  XM.jset('raceLB', store)
end)
function R.lbBroadcast()
  local t60, c60 = R.myBest(LB_KEYS.t60)
  local t200, c200 = R.myBest(LB_KEYS.t200)
  local d = { t60 = t60 or 0, t200 = t200 or 0, wins = S.raceWins, car60 = (c60 or ''):sub(1, 22), car200 = (c200 or ''):sub(1, 22) }
  NET.send(function() return lbSend(d) end, 3, 'lb')
  R.lbAt = clock() + 25
end
-- kind: 'wins' | 't60' | 't200'; rows sorted best first
function R.boardRows(kind)
  local rows, me = {}, ac.getDriverName(0) or 'You'
  local store = XM.jget('raceLB', {})
  local mine = { t60 = (R.myBest(LB_KEYS.t60)), t200 = (R.myBest(LB_KEYS.t200)), wins = S.raceWins }
  local _, c60 = R.myBest(LB_KEYS.t60)
  local _, c200 = R.myBest(LB_KEYS.t200)
  store[me] = { t60 = mine.t60, t200 = mine.t200, wins = mine.wins, car60 = c60, car200 = c200 }
  for name, e in pairs(store) do
    local v = e[kind]
    if v and v > 0 then rows[#rows + 1] = { name = name, value = v, me = name == me, car = kind == 't60' and e.car60 or (kind == 't200' and e.car200 or nil) } end
  end
  if kind == 'wins' then
    table.sort(rows, function(a, b) if a.value ~= b.value then return a.value > b.value end return a.name < b.name end)
  else
    table.sort(rows, function(a, b) if a.value ~= b.value then return a.value < b.value end return a.name < b.name end)
  end
  return rows
end

-- ---------------------------------------------------------------- actions
function R.challenge(player, spec, wager)
  if R.state == 'finished' or (R.state == 'idle' and R.run and not R.busy()) then R.settle() reset() end
  if R.state ~= 'idle' or R.busy() then return false end
  wager = math.max(0, math.floor(wager or 0))
  if wager > XM.cash() then toast('Not enough cash', 'Lower the wager', '⚠️') return false end
  R.cur = { rid = math.random(1, 2 ^ 30), role = 'host', oppSid = player.sid, oppName = player.name, spec = spec, wager = wager, at = clock(), opp = { d = 0, v = 0, at = clock() } }
  R.state = 'invited_out'
  send(1, player.sid, { rid = R.cur.rid, rtype = spec.kind, x = spec.x, y = spec.y, wager = wager })
  R.cur.inviteMsg = { player.sid, 'Race you? ' .. R.specName(spec) .. (wager > 0 and (' for ' .. XM.money(wager)) or '') .. '. Open the Race app to accept.' }
  R.cur.resendAt = clock() + 2.5
  return true
end
function R.accept()
  local c = R.cur
  if R.state ~= 'invited_in' or not c then return end
  if c.wager > 0 and not XM.spend(c.wager, 'Race wager vs ' .. c.oppName) then toast('Not enough cash', 'You can’t cover the wager', '⚠️') R.decline() return end
  c.escrow = c.wager > 0
  R.state = 'staging'
  send(2, c.oppSid)
end
function R.decline()
  local c = R.cur
  if c then send(3, c.oppSid) end
  reset()
end
function R.cancel()
  local c = R.cur
  if not c then return end
  send(4, c.oppSid)
  refund()
  reset()
end
function R.start()
  if R.state ~= 'staging' or R.cur.role ~= 'host' then return end
  send(5, R.cur.oppSid)
  R.startCountdown()
end
-- quit mid-race: counts as a forfeit
function R.abort()
  local c = R.cur
  if R.run and R.run.mode == 'race' and c then
    if R.state == 'countdown' then send(4, c.oppSid) refund() reset() return end
    send(7, c.oppSid, { flags = 1 })
    R.run.phase = 'done'
    R.state = 'finished'
    c.my = { dnf = true }
    c.finishedAt = clock()
    resolve()
  elseif R.run then
    R.run = nil
  end
end
function R.dismiss() if R.state == 'finished' or R.state == 'idle' then R.settle() reset() end R.run = nil end

function R.soloArm(spec)
  if R.busy() or R.state ~= 'idle' then return end
  R.run = newRun(spec, 'solo')
  R.soloResult = nil
  if not ac.isWindowOpen('actionbar') then ac.setWindowOpen('actionbar', true) end
end

-- ---------------------------------------------------------------- results
local function finishRun(run, tFin, v, extra)
  run.phase = 'done'
  local d = run.spec.kind == 1 and run.spec.x or run.d
  local res = {
    t = tFin, trap = v, top = run.top, react = run.react or 0, falseStart = run.falseStart, splits = run.splits,
    et = tFin - (run.mode == 'race' and run.spec.kind == 1 and (run.react or 0) or 0),
    avg = tFin > 0 and (d / tFin * 3.6) or 0, car = run.car, track = ac.getTrackName and ac.getTrackName() or '', at = os.time(),
    spec = run.spec, name = R.specName(run.spec),
  }
  res.score = tFin + (run.falseStart and 1 or 0)
  run.result = res
  -- personal records (per car)
  local bests = XM.jget('raceBests', {})
  local key = specKey(run.spec) .. '|' .. run.car
  local old = bests[key]
  if not run.falseStart and (not old or res.t < old.t) then
    bests[key] = { t = res.t, trap = res.trap, at = res.at, name = res.name, car = run.car, spec = run.spec }
    XM.jset('raceBests', bests)
    res.record = true
    R.lbAt = 0
  end
  if run.mode == 'solo' then
    R.soloResult = res
    R.hudFade = 1
    if res.record then toast('New record', res.name .. ' · ' .. string.format('%.3f s', res.t), '🏁') end
  else
    local c = R.cur
    c.my = res
    R.state = 'finished'
    for i = 0, 2 do   -- result is sent a few times so a dropped packet can't leave the race unsettled
      setTimeout(function()
        if R.cur == c then send(7, c.oppSid, { t = res.t, react = res.react, v = res.trap, d = res.top, flags = res.falseStart and 2 or 0 }) end
      end, i * 0.8)
    end
    c.finishedAt = clock()
    if c.opp.fin then resolve() end
  end
end

-- ---------------------------------------------------------------- per-frame
function R.update(dt)
  local c = R.cur
  R.pump()
  if c and R.state == 'invited_out' then
    if c.inviteMsg and clock() > c.at + 1.2 then pcall(sendText, c.inviteMsg[1], c.inviteMsg[2]) c.inviteMsg = nil end
    if clock() > (c.resendAt or 0) then
      c.resendAt = clock() + 2.5
      push({ kind = 1, to = c.oppSid, rid = c.rid, rtype = c.spec.kind, x = math.floor(c.spec.x), y = math.floor(c.spec.y), wager = c.wager, t = 0, react = 0, d = 0, v = 0, flags = 0 })
    end
  elseif c and R.state == 'staging' and c.role == 'guest' and clock() > (c.resendAt or 0) and (c.acceptTries or 0) < 3 then
    c.acceptTries, c.resendAt = (c.acceptTries or 0) + 1, clock() + 2
    send(2, c.oppSid)
  end
  if c and R.state == 'staging' and clock() - c.at > 600 then refund() reset() return end
  if ac.getSim().isOnlineRace and clock() > (R.lbAt or 0) then R.lbBroadcast() end
  -- expire stale invitations
  if (R.state == 'invited_out' or R.state == 'invited_in') and c and clock() - c.at > 120 then
    if R.state == 'invited_out' then send(4, c.oppSid) end
    toast('Race invite expired', c.oppName, '🏁')
    reset()
  end
  -- opponent never finished: after 30s the win is yours
  if R.state == 'finished' and c and not c.outcome and c.finishedAt and clock() - c.finishedAt > 30 then resolve(true) end
  R.hudFade = math.max(0, R.hudFade - dt * 0.15)
  local run = R.run
  if not run or run.phase == 'done' then return end
  local sim = ac.getSim()
  if sim.isPaused or sim.isReplayActive then return end
  local car = ac.getCar(0)
  if not car then return end
  local v = car.speedKmh
  run.v = v

  if run.phase == 'countdown' then
    if run.spec.kind == 1 and run.spec.y == 0 and v > 5 and not run.falseStart then
      run.falseStart = true
      toast('False start', '+1.0 second penalty', '⚠️')
    end
    if clock() >= run.goAt then
      run.phase = 'running'
      if run.mode == 'race' then R.state = 'racing' end
      run.timing = run.spec.kind == 1 or v >= math.max(run.spec.y, 2)
      run.goFlash = 1
    end
    return
  end

  -- solo: wait for the launch
  if run.phase == 'armed' then
    if (run.spec.kind == 1 and v > 2) or (run.spec.kind == 2 and v >= math.max(run.spec.y, 2)) then
      run.phase, run.timing, run.react = 'running', true, 0
    else
      run.prevV = v
      return
    end
  end

  -- pull race: the clock starts as the car passes the start speed
  if run.phase == 'running' and not run.timing and run.spec.kind == 2 and v >= math.max(run.spec.y, 2) then run.timing = true run.t, run.d = 0, 0 end
  run.goFlash = math.max(0, (run.goFlash or 0) - dt * 1.5)
  if not run.timing then run.prevV = v return end

  local prevT, prevD, prevV = run.t, run.d, run.prevV
  run.t = run.t + dt
  run.d = run.d + v / 3.6 * dt
  run.top = math.max(run.top, v)
  if run.mode == 'race' and run.spec.kind == 1 and not run.react and v > 2 then run.react = run.t end
  -- timing marks
  if run.spec.kind == 1 then
    for _, m in ipairs(DIST_MARKS) do
      if not run.splits[m[2]] and run.d >= m[1] and prevD < m[1] and m[1] <= run.spec.x + 0.5 then
        run.splits[m[2]] = { t = prevT + (m[1] - prevD) / math.max(run.d - prevD, 1e-6) * dt, v = v }
      end
    end
  end
  if run.fromZero then
    for _, m in ipairs(SPEED_MARKS) do
      if not run.splits[m[2]] and v >= m[1] and prevV < m[1] and m[1] <= (run.spec.kind == 2 and run.spec.x or 1e9) then
        run.splits[m[2]] = { t = prevT + (m[1] - prevV) / math.max(v - prevV, 1e-6) * dt, v = m[1] }
      end
    end
  end
  run.prevV = v
  -- finish line
  local finished, tFin = false, run.t
  if run.spec.kind == 1 and run.d >= run.spec.x then
    finished, tFin = true, prevT + (run.spec.x - prevD) / math.max(run.d - prevD, 1e-6) * dt
  elseif run.spec.kind == 2 and v >= run.spec.x then
    finished, tFin = true, prevT + (run.spec.x - prevV) / math.max(v - prevV, 1e-6) * dt
  end
  if finished then finishRun(run, tFin, v) return end
  -- stuck for too long on a solo/pull
  if run.t > 180 then R.abort() R.run = nil return end
  -- live progress to the opponent
  if run.mode == 'race' and c and clock() - (c.sentAt or 0) > 0.25 then
    c.sentAt = clock()
    send(6, c.oppSid, { d = run.spec.kind == 1 and run.d or v, v = v })
  end
end

-- ---------------------------------------------------------------- HUD (action bar window)
local function progressOf(run, d, v)
  if run.spec.kind == 1 then return clamp(d / run.spec.x, 0, 1) end
  return clamp((v - run.spec.y) / math.max(1, run.spec.x - run.spec.y), 0, 1)
end

function R.drawHud(cx)
  local run = R.run
  local c = R.cur
  local ac1 = accent()
  local white = rgbm(1, 1, 1, 1)
  if not run then return end
  if run.phase == 'countdown' then
    local left = run.goAt - clock()
    local n = math.ceil(left - 0.2)
    local label = n >= 1 and tostring(math.min(n, 5)) or 'GO'
    local frac = left - math.floor(left)
    local col = n >= 1 and mix(rgbm(1, 0.25, 0.2, 1), rgbm(1, 0.85, 0.2, 1), clamp(1 - n / 5, 0, 1)) or rgbm(0.3, 1, 0.5, 1)
    for g = 3, 1, -1 do rect(cx - 70 - g * 6, 6 - g * 4, cx + 70 + g * 6, 96 + g * 4, A(col, 0.08 / g), 30 + g * 6) end
    rect(cx - 70, 6, cx + 70, 96, rgbm(0.03, 0.03, 0.05, 0.85), 30)
    rectLine(cx - 70, 6, cx + 70, 96, A(col, 0.9), 30, 2)
    text(label, 64 + math.floor(frac * 8), cx, 14, col, F.numb, 0.5)
    text(R.specName(run.spec):upper() .. (c and ('  ·  ' .. c.oppName:upper()) or ''), 10, cx, 108, rgbm(1, 1, 1, 0.8), F.b, 0.5)
    if run.falseStart then text('FALSE START  +1.0s', 12, cx, 124, T.red, F.b, 0.5) end
    return true
  end
  local showing = run.phase == 'running' or run.phase == 'armed' or (run.phase == 'done' and R.hudFade > 0)
  if not showing then return end
  local w, h = 470, 112
  local x1, x2 = cx - w / 2, cx + w / 2
  local y = 8
  local done = run.phase == 'done'
  local res = run.result
  local win = done and c and c.outcome and c.outcome.win
  local glow = done and ((c and c.outcome) and (win == true and rgbm(0.3, 1, 0.5, 1) or (win == false and T.red or ac1)) or ac1) or ac1
  for g = 3, 1, -1 do rect(x1 - g * 4, y - g * 4, x2 + g * 4, y + h + g * 4, A(glow, 0.07 / g), 24 + g * 4) end
  rect(x1, y, x2, y + h, rgbm(0.03, 0.03, 0.05, 0.88), 24)
  rectLine(x1, y, x2, y + h, A(glow, 0.7), 24, 1.5)
  local name = R.specName(run.spec)
  text(name:upper() .. (run.mode == 'solo' and '  ·  SOLO' or ''), 10, x1 + 20, y + 12, A(glow, 1), F.b)
  if run.phase == 'armed' then
    text('READY', 34, cx, y + 30, white, F.numb, 0.5)
    text(run.spec.kind == 1 and 'Launch when you’re ready, the clock starts when you move' or ('Timer starts at ' .. math.max(run.spec.y, 2) .. ' km/h'), 11, cx, y + 76, rgbm(1, 1, 1, 0.7), F.m, 0.5)
    return true
  end
  local t = done and res.t or run.t
  text(string.format('%.3f', t), 40, x1 + 20, y + 28, white, F.numb)
  text(string.format('%d', math.floor(done and res.trap or run.v)), 26, x2 - 76, y + 32, white, F.numb, 1)
  text(done and 'TRAP KM/H' or 'KM/H', 9, x2 - 20, y + 42, rgbm(1, 1, 1, 0.55), F.b, 1)
  -- lanes
  local bx1, bx2 = x1 + 20, x2 - 20
  local function lane(yy, p, col, label)
    rect(bx1, yy, bx2, yy + 8, rgbm(1, 1, 1, 0.12), 4)
    rect(bx1, yy, bx1 + math.max(8, (bx2 - bx1) * p), yy + 8, col, 4)
    text(label, 9, bx2, yy - 12, rgbm(1, 1, 1, 0.6), F.b, 1)
  end
  local myP = done and 1 or progressOf(run, run.d, run.v)
  if run.mode == 'race' and c then
    local oppP = c.opp.fin and 1 or progressOf(run, c.opp.d or 0, c.opp.v or 0)
    lane(y + 84, myP, ac1, 'YOU')
    lane(y + 98, oppP, rgbm(1, 0.35, 0.3, 1), c.oppName:upper())
    if not done and run.spec.kind == 1 then
      local gap = run.d - (c.opp.d or 0)
      text(string.format('%s%.0f m', gap >= 0 and '+' or '', gap), 14, cx + 10, y + 12, gap >= 0 and T.green or T.red, F.numb, 0.5)
    end
  else
    lane(y + 92, myP, ac1, run.spec.kind == 1 and string.format('%.0f m LEFT', math.max(0, run.spec.x - run.d)) or (math.floor(run.v) .. ' / ' .. run.spec.x))
  end
  if done and c and c.outcome then
    local o = c.outcome
    local msg = o.win == true and 'YOU WIN' or (o.win == false and 'YOU LOSE' or 'TIE')
    text(msg, 14, cx + 10, y + 10, glow, F.numb, 0.5)
  elseif done and res and res.record then
    text('NEW RECORD', 13, cx + 10, y + 10, rgbm(1, 0.82, 0.25, 1), F.numb, 0.5)
  end
  return true
end
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
    DIAG.mark('player joined')
    setTimeout(function()
      local name = ac.getDriverName(carIndex) or 'Someone'
      local fav = listHas(S.favorites, name)
      notify(name .. ' joined', (ac.getCarName(carIndex) or '') .. (fav and ' ⭐' or ''), '👋', nil, { quietWhenClosed = not fav })
      if XM.beaconSoon then XM.beaconSoon() end
      XM.greet(name, sessionID)
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
  local g, err = ac.grabCamera('HackaPhone: ' .. mode)
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
      if w.visible and w.title ~= 'HackaPhone' then
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
local function prm(key, label, mn, mx, def, fmt) return { key = key, label = label, min = mn, max = mx, def = def, fmt = fmt or '%.1f' } end
local COMMON = { prm('roll', 'Roll', -30, 30, 0, '%.0f°'), prm('shake', 'Camera shake', 0, 1, 0, '%.2f') }
local function withCommon(list) for _, c in ipairs(COMMON) do list[#list + 1] = c end return list end
VIDEO_SHOTS = {
  { id = 'orbit',   name = 'Orbit',     icon = '🔄', params = withCommon({
      prm('radius', 'Distance', 2.5, 30, 6.5, '%.1f m'), prm('height', 'Height', -0.5, 12, 1.2, '%.1f m'),
      prm('speed', 'Spin speed', -1.5, 1.5, 0.35, '%.2f'), prm('fov', 'Field of view', 12, 100, 42, '%.0f°'), prm('lookH', 'Aim height', -1, 2.5, 0, '%.1f m') }) },
  { id = 'drone',   name = 'Drone',     icon = '🚁', params = withCommon({
      prm('back', 'Distance behind', 4, 60, 14, '%.0f m'), prm('height', 'Height', 1, 40, 7, '%.0f m'), prm('side', 'Side offset', -20, 20, 0, '%.0f m'),
      prm('smooth', 'Follow smoothing', 0.4, 8, 2.2, '%.1f'), prm('fov', 'Field of view', 12, 100, 38, '%.0f°'), prm('lookH', 'Aim height', -1, 2.5, 0, '%.1f m') }) },
  { id = 'tracker', name = 'Tracking',  icon = '🎯', params = withCommon({
      prm('side', 'Side distance', -14, 14, 4.2, '%.1f m'), prm('ahead', 'Forward offset', -12, 12, 0.5, '%.1f m'), prm('height', 'Height', -0.5, 6, 0, '%.1f m'),
      prm('smooth', 'Follow smoothing', 1, 15, 6, '%.1f'), prm('fov', 'Field of view', 12, 100, 46, '%.0f°'), prm('lookH', 'Aim height', -1, 2.5, 0, '%.1f m') }) },
  { id = 'flyby',   name = 'Flyby',     icon = '💨', params = withCommon({
      prm('ahead', 'Distance ahead', 5, 70, 15, '%.0f m'), prm('side', 'Side distance', 2, 25, 7, '%.0f m'), prm('height', 'Height', 0.3, 8, 1.1, '%.1f m'),
      prm('lead', 'Lead time', 0, 5, 2.2, '%.1f s'), prm('zoomK', 'Zoom amount', 400, 4000, 1800, '%.0f'), prm('fovMin', 'Tightest zoom', 5, 30, 8, '%.0f°'), prm('fovMax', 'Widest', 20, 100, 55, '%.0f°') }) },
  { id = 'low',     name = 'Low Chase', icon = '📉', params = withCommon({
      prm('back', 'Distance behind', 2, 20, 5.5, '%.1f m'), prm('height', 'Height', -1, 4, -0.35, '%.2f m'), prm('side', 'Side offset', -6, 6, 0.9, '%.1f m'),
      prm('smooth', 'Follow smoothing', 1, 15, 8, '%.1f'), prm('fov', 'Field of view', 15, 110, 55, '%.0f°'), prm('lookH', 'Aim height', -1, 2.5, 0, '%.1f m') }) },
  { id = 'free',    name = 'Handheld',  icon = '🎥', params = withCommon({
      prm('fov', 'Field of view', 10, 110, 50, '%.0f°') }) },
}
-- values for a shot: saved edits fall back to defaults
local function shotVal(shotId, key)
  local cfg = XM.jget('shotCfg', {})[shotId]
  if cfg and cfg[key] ~= nil then return cfg[key] end
  for _, sh in ipairs(VIDEO_SHOTS) do
    if sh.id == shotId then for _, p in ipairs(sh.params) do if p.key == key then return p.def end end end
  end
  return 0
end
CAM.shotVal = shotVal

local function updateVideo(dt)
  local car = ac.getCar(CAM.target) or ac.getCar(0)
  local sim = ac.getSim()
  local shot = CAM.shot
  local v = function(k) return shotVal(shot, k) end
  local center = car.position + car.up * (0.6 + ((shot ~= 'free') and v('lookH') or 0))
  if shot == 'free' then updatePhoto(dt) return end
  local pos, fov = CAM.pos, v('fov')
  if shot == 'orbit' then
    CAM.orbit = CAM.orbit + dt * v('speed')
    local r = v('radius')
    pos = center + vec3(math.sin(CAM.orbit) * r, v('height'), math.cos(CAM.orbit) * r)
  elseif shot == 'drone' then
    local back = car.look:clone() back.y = 0
    if back:length() < 0.01 then back = vec3(0, 0, 1) end
    back = back:normalize()
    local target = center - back * v('back') + UP * v('height') + car.side * v('side')
    CAM.pos = CAM.pos:distance(target) > 80 and target or CAM.pos + (target - CAM.pos) * (1 - math.exp(-v('smooth') * dt))
    pos = CAM.pos
  elseif shot == 'tracker' then
    local target = center + car.side * v('side') + car.look * v('ahead') + UP * v('height')
    CAM.pos = CAM.pos:distance(target) > 40 and target or CAM.pos + (target - CAM.pos) * (1 - math.exp(-v('smooth') * dt))
    pos = CAM.pos
  elseif shot == 'low' then
    local target = center - car.look * v('back') + UP * v('height') + car.side * v('side')
    CAM.pos = CAM.pos:distance(target) > 40 and target or CAM.pos + (target - CAM.pos) * (1 - math.exp(-v('smooth') * dt))
    pos = CAM.pos
  elseif shot == 'flyby' then
    local d = CAM.pos:distance(center)
    local behind = (center - CAM.pos):dot(car.look) > 8
    if d > 110 or behind or CAM.flybyInit ~= CAM.target then
      CAM.flybyInit = CAM.target
      local ahead = center + car.velocity * v('lead') + car.look * v('ahead') + car.side * (math.random() > 0.5 and v('side') or -v('side'))
      local g = groundAt(ahead)
      CAM.pos = vec3(ahead.x, (g or ahead.y) + v('height'), ahead.z)
    end
    pos = CAM.pos
    fov = clamp(v('zoomK') / math.max(d, 5), v('fovMin'), v('fovMax'))
  end
  local g = groundAt(pos)
  if g and pos.y < g + 0.2 then pos = vec3(pos.x, g + 0.2, pos.z) end
  local shake = v('shake')
  local look = (center - pos):normalize()
  if shake > 0 then
    local tt = clock()
    pos = pos + vec3(math.sin(tt * 7.3), math.sin(tt * 9.1 + 1), math.sin(tt * 6.7 + 2)) * 0.035 * shake
    look = (look + vec3(math.sin(tt * 5.1), math.sin(tt * 6.3 + 1), math.sin(tt * 4.7 + 2)) * 0.006 * shake):normalize()
  end
  local roll = math.rad(v('roll'))
  local up = UP
  if roll ~= 0 then up = (UP + look:clone():cross(UP):normalize() * math.tan(roll)):normalize() end
  setTransform(pos, look, up, fov)
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

-- ---------------------------------------------------------------- camera editor override
-- places the camera relative to the car using the offsets saved in the Cam Editor (per view, per car)
local function finite(a, b, c, d, e, f, g)
  for _, v in ipairs({ a or 0/0, b or 0/0, c or 0/0, d or 0/0, e or 0/0, f or 0/0, g or 0 }) do
    if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then return false end
  end
  return true
end
local function updateTweak(dt)
  local e = CAM.tweakE
  if not e then return end
  local sim = ac.getSim()
  local car = ac.getCar(sim.focusedCar >= 0 and sim.focusedCar or 0)
  if not car then return end
  if not finite(e.x, e.y, e.z, e.yaw, e.pitch, e.roll, e.fov) then XM.cam.panic('Camera values were invalid') return end
  local look, up, side = car.look, car.up, car.side
  local yaw, pit, rol = math.rad(e.yaw), math.rad(e.pitch), math.rad(e.roll)
  local fx, fy, fz = math.sin(yaw) * math.cos(pit), math.sin(pit), math.cos(yaw) * math.cos(pit)
  local fwd = side * fx + up * fy + look * fz
  if fwd:length() < 0.001 then return end
  fwd = fwd:normalize()
  local upv = up - fwd * up:dot(fwd)
  if upv:length() < 0.001 then upv = vec3(0, 1, 0) else upv = upv:normalize() end
  upv = upv * math.cos(rol) + fwd:clone():cross(upv) * math.sin(rol)
  local pos = car.position + side * e.x + up * e.y + look * e.z
  if not finite(pos.x, pos.y, pos.z, upv.x, upv.y, upv.z) then return end
  setTransform(pos, fwd, upv, clamp(e.fov, 15, 130))
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

  -- Cam Editor: custom placement for the view you are driving in
  CAM.tweakE = nil
  if not wantChase and XM.cam and not ac.getSim().isReplayActive then CAM.tweakE = XM.cam.current() end
  local wantTweak = CAM.tweakE ~= nil
  if wantTweak and not CAM.mode then
    if now >= (CAM.tweakRetry or 0) then
      if not camGrab('tweak') then CAM.tweakRetry = now + 3 XM.cam.panic('Another camera script is using the camera') end
    end
  elseif CAM.mode == 'tweak' and not wantTweak then
    if CAM.grab then CAM.grab.ownShare = 0 end
    camRelease()
  end

  if not CAM.grab then return end
  if not CAM.grab:active() then CAM.grab, CAM.mode = nil, nil return end
  CAM.share = damp(CAM.share, 1, (CAM.mode == 'chase' or CAM.mode == 'tweak') and 30 or 6, dt)
  CAM.grab.ownShare = CAM.share
  local ok, err = pcall(function()
    if CAM.mode == 'photo' then updatePhoto(dt)
    elseif CAM.mode == 'walk' then updateWalk(dt)
    elseif CAM.mode == 'video' then updateVideo(dt)
    elseif CAM.mode == 'chase' then updateChase(dt)
    elseif CAM.mode == 'tweak' then updateTweak(dt) end
  end)
  if not ok then
    ac.log('HackaPhone camera error: ' .. tostring(err))
    if CAM.mode == 'tweak' and XM.cam then XM.cam.panic('Camera error, custom view switched off') end
  end
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
  if not (body:find('HackaPhone', 1, true) or body:find('AC Phone', 1, true)) then return false, 'not a HackaPhone file' end
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
      updSetState('uptodate', 'HackaPhone ' .. VERSION .. ' is up to date')
      return
    end
    if S.autoUpdate or manual then installFiles(feed)
    else updSetState('available', 'HackaPhone ' .. tostring(feed.version) .. ' is available') end
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
    notify('HackaPhone updated', 'Now on version ' .. VERSION .. '. Tap to see what’s new.', '⬆️', function()
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
--  * live leaderboard shared with everyone running HackaPhone
-- ===========================================================================

local HESI = {
  running = false, run = 0, mult = 1, combo = 0, comboMax = 7, slowT = 0, events = {}, feed = {},
  cars = {}, lastPassSide = 0, lastPassAt = -10, near = 0, best = 0, sessionBest = 0, sessionTotal = 0,
  board = {}, sendAt = 0, stats = { maxMult = 1, top = 0 }, lastRun = nil, heat = 0, crashFlash = 0, bankFlash = 0, lastBank = 0, runTime = 0,
  startSpeed = 70, endSpeed = 30, pw = {}, bankTime = 3, pulse = 0, seq = 0, anim = nil, crashes = 0,
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
local TIER_COL = { rgbm(0.55, 0.85, 1, 1), rgbm(1, 0.8, 0.25, 1), rgbm(1, 0.5, 0.15, 1), rgbm(1, 0.25, 0.3, 1), rgbm(0.8, 0.35, 1, 1) }
HESI.tierIndex = function(m)
  local idx = 1
  for i, x in ipairs(TIERS) do if (m or HESI.mult) >= x.at then idx = i end end
  return idx
end
HESI.tierColor = function(m) return TIER_COL[HESI.tierIndex(m)] end
HESI.tierCount = #TIERS
-- smooth value animation, keyed (used for count-ups and leaderboard reshuffles)
local ANIMS = {}
HESI.anim = function(key, target, rate)
  local now = clock()
  local a = ANIMS[key]
  if not a then ANIMS[key] = { v = target, t = now } return target end
  local dt = clamp(now - a.t, 0, 0.1)
  a.t = now
  a.v = a.v + (target - a.v) * (1 - math.exp(-dt * (rate or 12)))
  if math.abs(target - a.v) < 0.5 then a.v = target end
  return a.v
end

local function addEvent(kind, extra)
  local e = HESI_EVENTS[kind]
  if not e then return end
  local before = tierFor(HESI.mult)
  local car = ac.getCar(0)
  local speedFactor = clamp(car.speedKmh / 120, 0.6, 3)
  local fx = HESI.pw or {}
  local pts = e.pts * HESI.mult * speedFactor * (extra or 1) * (fx.mult or 1)
  if fx.magnet and (kind == 'near' or kind == 'close' or kind == 'oncoming' or kind == 'split') then pts = pts * 1.6 end
  local jackpot = fx.lucky and math.random() < 0.125
  if jackpot then pts = pts * 3 end
  HESI.run = HESI.run + pts
  HESI.mult = math.min(MAX_MULT, HESI.mult + e.mult * (fx.drive and 2 or 1))
  HESI.combo = HESI.comboMax
  HESI.heat = math.min(1, HESI.heat + 0.25)
  HESI.pulse = 1
  if kind ~= 'overtake' then HESI.near = HESI.near + 1 end
  local st = HESI.stats
  st[kind] = (st[kind] or 0) + 1
  if HESI.mult > st.maxMult then st.maxMult = HESI.mult end
  pushFeed((jackpot and 'JACKPOT  ' or '') .. e.name .. '  +' .. fmtPts(pts), jackpot and rgbm(1, 0.85, 0.2, 1) or e.color, jackpot or kind == 'split' or kind == 'close' or kind == 'trap')
  local after = tierFor(HESI.mult)
  if after.at > before.at and after.name ~= '' then pushFeed(after.name, rgbm(1, 0.8, 0.25, 1), true) end
end

local function startRun()
  HESI.running, HESI.run, HESI.mult, HESI.combo, HESI.slowT, HESI.runTime = true, 0, 1, 0, 0, 0
  HESI.cars = {}
  HESI.trapDone = false
  HESI.stats = { maxMult = 1, top = 0, dist = 0 }
  local fx = XM.armRun()
  HESI.pw = fx
  HESI.mult = fx.head and 3 or 1
  HESI.comboMax = 7 + (fx.hyper and 4 or 0)
  HESI.bankTime = fx.quick and 1.2 or 3
  pushFeed('RUN STARTED', rgbm(0.4, 1, 0.5, 1))
  if #fx.names > 0 then pushFeed('ARMED  ' .. table.concat(fx.names, ' · '), rgbm(0.8, 0.5, 1, 1)) end
end

local hesiSend
local function broadcast(evt, last)
  if not hesiSend then return end
  local data = {
    run = math.floor(HESI.run), best = math.floor(HESI.sessionBest), total = math.floor(HESI.sessionTotal),
    pb = math.floor(S.hesiPB), mult = math.floor(HESI.mult * 10), state = HESI.running and 1 or 0,
    evt = evt or 0, last = math.floor(last or 0), crashes = HESI.crashes, seq = HESI.seq,
  }
  if evt and evt ~= 0 then NET.send(function() return hesiSend(data) end, 2) else NET.send(function() return hesiSend(data) end, 3, 'hesi') end
  if evt and evt ~= 0 then
    -- crash/bank results are what the boards reshuffle on, so send them twice in case one is dropped
    setTimeout(function() NET.send(function() return hesiSend(data) end, 2) end, 0.7)
  end
end

local function endRun(crashed)
  if not HESI.running then return end
  DIAG.mark(crashed and 'my crash' or 'my run banked')
  local fx = HESI.pw or {}
  local saved = false
  if (not crashed) and fx.hunter and HESI.run > S.hesiPB then
    HESI.run = HESI.run * 1.25
    pushFeed('PB HUNTER  +25%', rgbm(1, 0.8, 0.25, 1), true)
  end
  HESI.running = false
  local score = math.floor(HESI.run)
  local st = HESI.stats or {}
  HESI.lastRun = { score = score, crashed = crashed, time = HESI.runTime, top = st.top or 0, maxMult = st.maxMult or 1,
    near = (st.near or 0), close = (st.close or 0), split = (st.split or 0), oncoming = (st.oncoming or 0),
    overtake = (st.overtake or 0), pb = score > S.hesiPB, at = os.date('%H:%M'),
    avg = (HESI.runTime > 1) and ((st.dist or 0) / HESI.runTime * 3.6) or 0, saved = saved, boost = fx.mult or 1, fxNames = fx.names }
  -- the crash frame is already the busiest of the whole session, so the saving, paying and notifying is spread over
  -- the next second instead of happening in the same frame
  local nearNow = HESI.near
  HESI.near = 0
  local lastRun = HESI.lastRun
  lastRun.pay = XM.payoutFor and XM.payoutFor(score, crashed, fx) or 0
  setTimeout(function()
    local okPay, payout = pcall(XM.onRunEnd, lastRun, crashed, fx)   -- money must never block scoring
    if okPay then pushFeed('CASH  +$' .. fmtPts(payout), rgbm(0.5, 1, 0.6, 1)) else DIAG.err('payout', payout) end
  end, 0.6)
  setTimeout(function()
    S.hesiRuns = S.hesiRuns + 1
    S.hesiNear = S.hesiNear + nearNow
    S.hesiTotal = S.hesiTotal + score
  end, 0.9)
  HESI.seq = (HESI.seq + 1) % 30000
  -- every run banks, crash or not: the points are yours either way
  if crashed then
    HESI.crashes = HESI.crashes + 1
    HESI.crashFlash = 1
    HESI.crashLost = score
    pushFeed('CRASHED  BANKED +' .. fmtPts(score), T.red, true)
  else
    HESI.bankFlash = 1
    HESI.lastBank = score
    pushFeed('BANKED  +' .. fmtPts(score), rgbm(0.3, 1, 0.5, 1), true)
  end
  HESI.sessionTotal = HESI.sessionTotal + score
  if score > HESI.sessionBest then HESI.sessionBest = score end
  local newPB = score > S.hesiPB
  if newPB then S.hesiPB = score end
  setTimeout(function()
    if newPB then notify('New personal best! 🏆', fmtPts(score) .. ' points', '🔥', nil, { force = true })
    elseif score > 5000 and not crashed then notify('Run banked', fmtPts(score) .. ' points', '🔥', nil, { quietWhenClosed = true }) end
  end, 1.2)
  HESI.run, HESI.mult, HESI.combo = 0, 1, 0
  HESI.pw, HESI.bankTime, HESI.comboMax = {}, 3, 7
  HESI.lastEvt = { kind = crashed and 1 or 2, score = score, at = clock() }
  broadcast(crashed and 1 or 2, score)
end
HESI.endRun = endRun

-- online leaderboard
hesiSend = ac.OnlineEvent({
  ac.StructItem.key('acphone.cutup.v1'),
  run = ac.StructItem.int32(), best = ac.StructItem.int32(), total = ac.StructItem.int32(),
  pb = ac.StructItem.int32(), mult = ac.StructItem.int16(), state = ac.StructItem.byte(),
  evt = ac.StructItem.byte(), last = ac.StructItem.int32(), crashes = ac.StructItem.int16(), seq = ac.StructItem.int16(),
}, function(sender, d)
  if not sender or sender.index == 0 then return end
  local name = ac.getDriverName(sender.index) or '?'
  local prev = HESI.board[sender.sessionID]
  local ev = prev and prev.ev or nil
  -- a crash or bank result: show it right away and keep it on their row for a bit
  if d.evt ~= 0 and (not prev or prev.evSeq ~= d.seq) then
    ev = { kind = d.evt, score = d.last, at = clock() }
    -- other people's crashes stay on the board only; a big bank gets one line, at most one every few seconds
    if d.evt == 2 and d.last >= 5000 and clock() - (HESI.lastOtherFeed or -99) > 6 then
      HESI.lastOtherFeed = clock()
      pushFeed(name:upper() .. ' BANKED  +' .. fmtPts(d.last), rgbm(0.35, 1, 0.55, 1), false)
    end
  end
  HESI.board[sender.sessionID] = { name = name, run = d.run, best = d.best, total = d.total, pb = d.pb, mult = d.mult / 10,
    running = d.state == 1, at = clock(), index = sender.index, ev = ev, evSeq = (d.evt ~= 0) and d.seq or (prev and prev.evSeq), crashes = d.crashes }
  -- crew all-time board (kept on this PC)
  if (HESI.crewSeen or {})[name] ~= d.pb then
    HESI.crewSeen = HESI.crewSeen or {}
    HESI.crewSeen[name] = d.pb
    local ok, crew = pcall(JSON.parse, S.hesiCrew)
    crew = (ok and type(crew) == 'table') and crew or {}
    if (crew[name] or 0) < d.pb then crew[name] = d.pb S.hesiCrew = JSON.stringify(crew) end
  end
  if prev and d.best > (prev.best or 0) and d.best > 5000 and d.best >= HESI.sessionBest and clock() - (HESI.lastTopNotify or -99) > 45 then
    HESI.lastTopNotify = clock()
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
  HESI.pulse = math.max(0, HESI.pulse - dt * 3)
  HESI.crashFlash = math.max(0, HESI.crashFlash - dt * 1.2)
  HESI.bankFlash = math.max(0, HESI.bankFlash - dt * 1.2)

  if XM.race.busy() then return end   -- racing: Cut-Up sits out
  if not S.hesiOn then if HESI.running then endRun(false) end return end
  if me.isInPitlane then if HESI.running then endRun(false) end return end

  if not HESI.running then
    if speed > HESI.startSpeed then startRun() else return end
  end

  HESI.runTime = HESI.runTime + dt
  if HESI.stats and speed > HESI.stats.top then HESI.stats.top = speed end
  -- speed points
  HESI.run = HESI.run + dt * (speed / 12) * HESI.mult * (HESI.pw.mult or 1)
  if HESI.stats then HESI.stats.dist = (HESI.stats.dist or 0) + speed / 3.6 * dt end
  -- combo timer / multiplier decay
  if HESI.combo > 0 then
    HESI.combo = HESI.combo - dt * (HESI.pw.warp and 0.4 or 1)
    if HESI.combo <= 0 then HESI.mult = math.max(1, HESI.mult * 0.7) if HESI.mult > 1.05 then HESI.combo = 2.5 end end
  end
  -- speed trap
  if speed > 260 and not HESI.trapDone then HESI.trapDone = true addEvent('trap') end
  if speed < 200 then HESI.trapDone = false end
  -- bank when slow for a few seconds
  if speed < HESI.endSpeed then
    HESI.slowT = HESI.slowT + dt
    if HESI.slowT > HESI.bankTime then endRun(false) return end
  else
    HESI.slowT = 0
  end

  -- traffic passes
  local fwd, side = me.look, me.side
  local sim = ac.getSim()
  local mp = me.position
  local mx, my, mz = mp.x, mp.y, mp.z
  for i = 1, sim.carsCount - 1 do
    local c = ac.getCar(i)
    if c and c.isConnected ~= false and c.isActive ~= false then
      local cp = c.position
      local ddx, ddy, ddz = cp.x - mx, cp.y - my, cp.z - mz
      local near2 = ddx * ddx + ddy * ddy + ddz * ddz
      local st = HESI.cars[i]
      if near2 < 900 then
        local rel = cp - mp
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
  if clock() > HESI.sendAt then HESI.sendAt = clock() + (HESI.running and 1.5 or 25) broadcast() end
end
HESI.update = hesiUpdate

-- a crash ends the run (points are banked), unless Ghost Shield soaks it up
HESI.collide = function()
  if not (HESI.running and HESI.runTime > 1) then return end
  if HESI.pw.shield and clock() - (HESI.shieldAt or -9) > 1 then
    HESI.pw.shield = false
    HESI.shieldAt = clock()
    HESI.pulse = 1
    pushFeed('GHOST SHIELD  blocked the crash', rgbm(0.75, 0.5, 1, 1), true)
    return
  end
  if clock() - (HESI.shieldAt or -9) <= 1 then return end   -- same impact as the one the shield took
  endRun(true)
end
if ac.onCarCollision then ac.onCarCollision(0, function() HESI.collide() end) end
end
-- ===========================================================================
-- Vault: an in-game music player for your own tracks (unreleased music, downloads from
-- Untitled, anything on your PC), with a library, search and a play queue.
-- ===========================================================================

XM.vault = { tracks = {}, queue = {}, history = {}, cur = nil, scanned = '', scanning = false, order = {} }

do
local VAULT = XM.vault
local AUDIO = { mp3 = true, wav = true, flac = true, m4a = true, ogg = true, aac = true, wma = true, opus = true, mp4 = false }
local player

local function parseName(file)
  local base = file:gsub('%.[%w]+$', '')
  base = base:gsub('^%d+[%.%-_ ]+', '')                 -- leading track number
  base = base:gsub('_', ' ')
  local artist, title = base:match('^(.-)%s+%-%s+(.+)$')
  if artist and title then return title, artist end
  return base, ''
end

local function findCover(dir, base)
  for _, ext in ipairs({ 'jpg', 'png', 'jpeg' }) do
    for _, n in ipairs({ base, 'cover', 'folder', 'artwork', 'Cover', 'Folder' }) do
      local p = dir .. '/' .. n .. '.' .. ext
      if io.fileExists(p) then return p end
    end
  end
end

local function scanInto(dir, out, depth)
  local ok, list = pcall(io.scanDir, dir, '*')
  if not ok or type(list) ~= 'table' then return end
  for _, f in ipairs(list) do
    local ext = f:lower():match('%.(%w+)$')
    if ext and AUDIO[ext] then
      local title, artist = parseName(f)
      local base = f:gsub('%.[%w]+$', '')
      out[#out + 1] = { path = dir .. '/' .. f, file = f, title = title, artist = artist, ext = ext, cover = findCover(dir, base),
        folder = dir:match('[^/\\]+$') or dir, search = (title .. ' ' .. artist .. ' ' .. f):lower() }
    elseif not ext and depth < 2 then
      scanInto(dir .. '/' .. f, out, depth + 1)
    end
  end
end

function VAULT.scan()
  local folder = S.vaultFolder
  if folder == '' or not io.dirExists(folder) then VAULT.tracks = {} VAULT.scanned = '' return end
  local out = {}
  scanInto(folder, out, 0)
  table.sort(out, function(a, b) return a.search < b.search end)
  VAULT.tracks, VAULT.scanned = out, folder
  VAULT.order = {}
  for i = 1, #out do VAULT.order[i] = i end
end

function VAULT.pickFolder()
  if not os.openFileDialog then toast('Not available', 'Needs a newer CSP', '⚠️') return end
  os.openFileDialog({ title = 'Choose your music folder', flags = os.DialogFlags.PickFolders + os.DialogFlags.PathMustExist }, function(err, path)
    if err or not path or path == '' then return end
    S.vaultFolder = path:gsub('[/\\]+$', '')
    VAULT.scan()
    toast('Vault ready', #VAULT.tracks .. ' tracks found', '♫')
  end)
end

function VAULT.openUntitled()
  if os.openURL then os.openURL(S.untitledUrl ~= '' and S.untitledUrl or 'https://untitled.stream', false) end
end

local function ensurePlayer()
  if not player then
    local ok, p = pcall(ui.MediaPlayer)
    if not ok or not p then toast('Vault', 'Audio playback isn’t available on this PC', '⚠️') return nil end
    player = p
  end
  return player
end

function VAULT.playing()
  return player ~= nil and VAULT.cur ~= nil and player:playing()
end
function VAULT.position() return player and VAULT.cur and player:currentTime() or 0 end
function VAULT.duration() return player and VAULT.cur and player:duration() or 0 end

function VAULT.play(track, noHistory)
  local p = ensurePlayer()
  if not p or not track then return end
  if VAULT.cur and not noHistory then
    VAULT.history[#VAULT.history + 1] = VAULT.cur
    while #VAULT.history > 40 do table.remove(VAULT.history, 1) end
  end
  VAULT.cur = track
  p:setSource(track.path):setVolume(S.vaultVol):setAutoPlay(true)
  pcall(p.play, p)
  VAULT.startedAt = clock()
  VAULT.paused = false
end

function VAULT.toggle()
  if not VAULT.cur then
    local t = VAULT.tracks[VAULT.order[1] or 1]
    if t then VAULT.play(t) end
    return
  end
  if not player then return end
  if player:playing() then pcall(player.pause, player) VAULT.paused = true
  else pcall(player.play, player) VAULT.paused = false end
end

local function indexOf(track)
  for i, t in ipairs(VAULT.tracks) do if t == track then return i end end
end

function VAULT.next()
  if #VAULT.queue > 0 then
    local t = table.remove(VAULT.queue, 1)
    VAULT.play(t)
    return
  end
  if #VAULT.tracks == 0 then return end
  if S.vaultShuffle then
    VAULT.play(VAULT.tracks[math.random(#VAULT.tracks)])
    return
  end
  local i = (indexOf(VAULT.cur) or 0) + 1
  if i > #VAULT.tracks then
    if S.vaultRepeat == 1 then VAULT.stop() return end   -- 1 = off, 2 = all, 3 = one
    i = 1
  end
  VAULT.play(VAULT.tracks[i])
end

function VAULT.prev()
  if VAULT.cur and VAULT.position() > 4 then player:setCurrentTime(0) return end
  local t = table.remove(VAULT.history)
  if t then VAULT.play(t, true) elseif VAULT.cur then player:setCurrentTime(0) end
end

function VAULT.stop()
  if player then pcall(player.pause, player) end
  VAULT.cur, VAULT.paused = nil, false
end

function VAULT.seek(frac)
  local d = VAULT.duration()
  if player and d > 0 then player:setCurrentTime(clamp(frac, 0, 1) * d) end
end

function VAULT.setVolume(v)
  S.vaultVol = clamp(v, 0, 1)
  if player then player:setVolume(S.vaultVol) end
end

function VAULT.enqueue(t) VAULT.queue[#VAULT.queue + 1] = t end
function VAULT.playNext(t) table.insert(VAULT.queue, 1, t) end
function VAULT.dequeue(i) table.remove(VAULT.queue, i) end
function VAULT.moveUp(i)
  if i > 1 then VAULT.queue[i], VAULT.queue[i - 1] = VAULT.queue[i - 1], VAULT.queue[i] end
end
function VAULT.clearQueue() VAULT.queue = {} end

function VAULT.search(q)
  q = (q or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
  if q == '' then return VAULT.tracks end
  local out = {}
  for _, t in ipairs(VAULT.tracks) do
    local all = true
    for word in q:gmatch('%S+') do if not t.search:find(word, 1, true) then all = false break end end
    if all then out[#out + 1] = t end
  end
  return out
end

-- looks like the system music data so the lock screen, island and Control Centre can show it
function VAULT.media()
  local t = VAULT.cur
  if not t then return nil end
  return { title = t.title, artist = t.artist, album = t.folder, hasCover = t.cover ~= nil, coverPath = t.cover,
    trackPosition = VAULT.position(), trackDuration = VAULT.duration(), isPlaying = VAULT.playing(), vault = true }
end

function VAULT.update(dt)
  if not VAULT.cur or not player then return end
  if VAULT.scanned == '' and S.vaultFolder ~= '' then return end
  -- finished? (give the file a moment to load before trusting ended())
  if clock() - (VAULT.startedAt or 0) > 1.5 and not VAULT.paused and player:ended() then
    if S.vaultRepeat == 3 then
      player:setCurrentTime(0) pcall(player.play, player)
    else
      VAULT.next()
    end
  end
end

-- first scan happens lazily
if S.vaultFolder ~= '' then setTimeout(function() pcall(VAULT.scan) end, 1) end
end

-- ===========================================================================
-- Music controls (Windows media keys) and image wallpapers
-- ===========================================================================

local MEDIA = { pendingPlay = nil, pendingAt = 0, lastSend = 0 }
local WALL = {}

do
local VAULT = XM.vault
-- fallback only: media keys through Windows Script Host (179 play/pause, 176 next, 177 previous, 175 vol up, 174 vol down)
local function sendMediaKeyFallback(vk)
  if not os.runConsoleProcess then return false end
  pcall(os.runConsoleProcess, {
    filename = 'powershell.exe',
    arguments = { '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command',
      '(New-Object -ComObject WScript.Shell).SendKeys([char]' .. vk .. ')' },
    timeout = 6000, terminateWithScript = false,
  }, function() end)
  return true
end

-- press a key through CSP (works while AC is the active window)
local function tapKey(vk)
  if not ac.sendKeyboardButtonEvent then return false end
  local ok = pcall(ac.sendKeyboardButtonEvent, vk, true)
  if not ok then return false end
  setTimeout(function() pcall(ac.sendKeyboardButtonEvent, vk, false) end, 0.05)
  return true
end

-- hold some keys together, press the last one, then let go (for recorder hotkeys)
function MEDIA.combo(keys)
  if not ac.sendKeyboardButtonEvent then return false end
  for _, k in ipairs(keys) do if not pcall(ac.sendKeyboardButtonEvent, k, true) then return false end end
  setTimeout(function()
    for i = #keys, 1, -1 do pcall(ac.sendKeyboardButtonEvent, keys[i], false) end
  end, 0.08)
  return true
end
-- Medal is required: Alt+F7 starts and stops a full-length recording ("Start/stop long recording hotkey" must be on in Medal)
MEDIA.medal = 'unknown'     -- unknown | running | missing
function MEDIA.medalCheck()
  if clock() - (MEDIA.medalAt or -99) < 4 then return end
  MEDIA.medalAt = clock()
  local ok = pcall(os.runConsoleProcess, { filename = 'tasklist', arguments = { '/FI', 'IMAGENAME eq Medal.exe', '/NH' }, timeout = 5000 }, function(err, res)
    if err or not res or res.exitCode ~= 0 then MEDIA.medal = 'unknown' return end
    MEDIA.medal = (res.stdout or ''):lower():find('medal.exe', 1, true) and 'running' or 'missing'
  end)
  if not ok then MEDIA.medal = 'unknown' end
end
function MEDIA.recorder(start) return MEDIA.combo({ 18, 118 }) end

local function guard()
  if clock() - MEDIA.lastSend < 0.25 then return false end
  MEDIA.lastSend = clock()
  return true
end

-- CSP's own media controls first; fall back to other methods on older CSP
local function media(builtin, vk)
  if not guard() then return end
  if builtin and pcall(builtin) then return end
  if tapKey(vk) then return end
  if not sendMediaKeyFallback(vk) then toast('Music controls', 'Your CSP version can’t control media', '⚠️') end
end

function MEDIA.playPause()
  if VAULT.cur then VAULT.toggle() return end
  local m = LIVE.music
  MEDIA.pendingPlay = not (m and m.isPlaying)
  MEDIA.pendingAt = clock()
  media(ac.mediaPlayPause, 179)
  LIVE.musicCheck = 0
end
function MEDIA.next() if VAULT.cur then VAULT.next() return end media(ac.mediaNextTrack, 176) LIVE.musicCheck = clock() - 0.3 end
function MEDIA.prev() if VAULT.cur then VAULT.prev() return end media(ac.mediaPreviousTrack, 177) LIVE.musicCheck = clock() - 0.3 end
function MEDIA.volUp() if VAULT.cur then VAULT.setVolume(S.vaultVol + 0.1) return end media(nil, 175) end
function MEDIA.volDown() if VAULT.cur then VAULT.setVolume(S.vaultVol - 0.1) return end media(nil, 174) end

-- current track, with an optimistic play state right after a tap
function MEDIA.now()
  if VAULT.cur then return VAULT.media(), VAULT.playing() end
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
  if m and m.hasCover then drawn = pcall(ui.drawImageRounded, m.coverPath or m, P(x1, y1), P(x2, y2), A(T.white), nil, nil, r) end
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
  if type(path) == 'table' and path.coverPath then path = path.coverPath end
  local okS, sz = pcall(ui.imageSize, path)
  if type(path) ~= 'string' and (not okS or not sz or sz.x <= 0) then sz = vec2(1, 1) end -- album art: assume square
  if not okS or not sz or sz.x <= 0 or sz.y <= 0 then return false end
  local boxAR, imgAR = (x2 - x1) / (y2 - y1), sz.x / sz.y
  local uv1, uv2
  if imgAR > boxAR then
    local f = boxAR / imgAR
    uv1, uv2 = vec2((1 - f) / 2, 0), vec2((1 + f) / 2, 1)
  else
    local f = imgAR / boxAR
    uv1, uv2 = vec2(0, (1 - f) / 2), vec2(1, (1 + f) / 2)
  end
  return (pcall(ui.drawImageRounded, path, P(x1, y1), P(x2, y2), A(tint or T.white), uv1, uv2, rounding or 0, ui.CornerFlags.All))
end

-- album art wallpaper: blurred (or sharp) cover of the current song, cross-fading when the song changes
WALL.musicKey, WALL.musicFade = nil, 1
function WALL.music(x1, y1, x2, y2, rounding)
  local m = MEDIA.now()
  if not (m and m.hasCover) then return false end
  local key = (m.title or '') .. '|' .. (m.artist or '')
  if key ~= WALL.musicKey then WALL.musicKey, WALL.musicFade = key, 0 end
  WALL.musicFade = math.min(1, WALL.musicFade + IN.dt / 0.6)
  local oldA = D.a
  D.a = D.a * WALL.musicFade
  local ok
  local mode = S.musicArtMode
  if mode ~= 1 and ui.beginBlurring then
    ui.beginBlurring()
    ok = WALL.cover(m, x1 - 40, y1 - 40, x2 + 40, y2 + 40, 0)
    ui.endBlurring(0.015 + 0.14 * S.musicBlurAmt)
  else
    ok = WALL.cover(m, x1, y1, x2, y2, rounding)
  end
  if mode == 3 and ok then
    local side = (x2 - x1) * 0.74
    local cx, top = (x1 + x2) / 2, y1 + (y2 - y1) * 0.17
    rect(cx - side / 2 - 2, top - 2, cx + side / 2 + 2, top + side + 2, rgbm(0, 0, 0, 0.35), 20)
    WALL.cover(m, cx - side / 2, top, cx + side / 2, top + side, 18)
  end
  D.a = oldA
  return ok
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

local APPMOD = { Messages = {}, Friends = {}, Camera = {}, Walk = {}, Video = {}, Chase = {}, Plates = {}, Skins = {}, Weather = {}, Library = {}, Settings = {}, Maps = {}, Hud = {}, Livery = {}, Themes = {}, CutUp = {}, Music = {}, Leaders = {}, Bank = {}, Market = {}, Power = {}, Runs = {}, Vault = {}, Race = {}, Car = {}, CamEdit = {} }

-- ===========================================================================
-- Shared pieces for app screens
-- ===========================================================================

local SW, SH = SCREEN.w, SCREEN.h
local BOTTOM = SH - 34          -- above home indicator
local PHONE = { minimized = false, minimizeReason = nil, locked = false }
PHONE_STATE = PHONE

PHONE.BASE, PHONE.CAP = vec2(380, 784), vec2(380, 96)

-- keeps the window exactly the size of the phone at the current scale (so it can never be squashed)
function PHONE.applySize()
  local k = clamp(S.phoneScale or 1, 0.6, 1.8)
  local size = (PHONE.minimized and PHONE.CAP or PHONE.BASE) * k
  if ac.setWindowSizeConstraints then ac.setWindowSizeConstraints('main', size, size) end
  PHONE.appliedScale, PHONE.appliedMin = k, PHONE.minimized
end

local function setMinimized(v, reason)
  PHONE.minimized = v
  PHONE.minimizeReason = v and reason or nil
  PHONE.applySize()
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
    textBox('Message a friend from the Friends app. Everyone on the server needs HackaPhone to receive messages.', 12, 24, y, SW - 24, y + 60, T.label3)
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
    if p then text(p.status, 14, SW / 2, y, T.green, F.m, 0.5) else text('No HackaPhone', 14, SW / 2, y, T.label3, F.r, 0.5) end
    y = y + 36
    -- action buttons (iOS contact style)
    local actions = {
      { '💬', 'message' }, { '🏁', 'race' }, { '📯', 'honk' }, { '👁', 'watch' }, { listHas(S.favorites, name) and '⭐' or '☆', 'star' },
    }
    local bw = (SW - 32 - 32) / 5
    for i, a in ipairs(actions) do
      local x = 16 + (i - 1) * (bw + 8)
      local fired, pressed = tap('pa' .. i, x, y, x + bw, y + 62)
      rect(x, y, x + bw, y + 62, pressed and T.cellHi or T.cell, 12)
      text(a[1], 20, x + bw / 2, y + 8, T.white, F.r, 0.5)
      text(a[2], 12, x + bw / 2, y + 38, accent(), F.m, 0.5)
      if fired then
        if a[2] == 'message' then getThread(sid, name) navPush(threadScreen(sid))
        elseif a[2] == 'race' then
          if p then
            XM.race.pending = { sid = sid, name = name }
            APPMOD.openApp('race')
          else toast('No HackaPhone', name .. ' can’t take a challenge', '⚠️') end
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
    if XM.usersScreen and W.button('fr.users', '👥  HackaPhone users', 16, y, SW - 32, 40, 'tinted') then navPush(XM.usersScreen()) end
    y = y + 50
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
    local curShot = VIDEO_SHOTS[1]
    for _, sh in ipairs(VIDEO_SHOTS) do if sh.id == CAM.shot then curShot = sh end end
    W.groupBg(y, 1)
    if W.row('v.edit', 'Edit ' .. curShot.name .. ' angle', y, { chevron = true, first = true, last = true, icon = '🎛️', iconBg = rgbm(0.45, 0.4, 1, 1), sub = 'Distance, height, speed, lens, roll, shake' }) then
      navPush(APPMOD.Video.editor(curShot.id))
    end
    y = y + 60
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
    MEDIA.medalCheck()
    y = W.sectionHeader('Recorder', y + 54)
    W.groupBg(y, 1)
    local ms = MEDIA.medal
    W.row('v.medal', 'Medal', y, { first = true, last = true, icon = '🎥', iconBg = rgbm(1, 0.7, 0.1, 1),
      sub = ms == 'running' and 'Running · ready to record' or (ms == 'missing' and 'Not running · open Medal first' or 'Required for recording') })
    circle(SW - 32, y + 23, 6, ms == 'running' and T.green or (ms == 'missing' and T.red or T.label3))
    y = W.sectionFooter('REC starts and Stop ends a full-length Medal recording (Alt+F7). In Medal turn on Settings › Capture Hotkeys › Long Recording › Start/stop long recording hotkey. Your video appears in Medal’s Library under Sessions.', y + 50)
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
      if MEDIA.medal == 'missing' then
        toast('Medal is required', 'Open Medal, then press REC again', '⚠️')
      else
        if CAM.mode ~= 'video' then if CAM.mode then camRelease() end videoStart() end
        CAM.recording = true
        CAM.recStart = clock()
        if S.camHideApps then hideOtherApps(true) end
        setMinimized(true, 'rec')
        setTimeout(function()
          if CAM.recording then
            CAM.recOn = MEDIA.recorder(true)
            if not CAM.recOn then toast('Couldn’t start Medal', 'Press Alt+F7 yourself', '⚠️') end
          end
        end, 0.8)
      end
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
    if w.title and w.title ~= '' and w.title ~= 'HackaPhone' and not w.layerDuplicate then out[#out + 1] = w end
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
    text('HackaPhone ' .. (newer and tostring(latest.version) or VERSION), 18, 108, y + 24, T.label, F.sb)
    text(newer and 'New version' or ('Installed · build ' .. BUILD), 13, 108, y + 50, T.label2)
    local status = UPD.message ~= '' and UPD.message or ('HackaPhone ' .. VERSION .. ' is installed')
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
    W.groupBg(y, 4)
    local hasUpd = UPD.latest and tonumber(UPD.latest.build) and tonumber(UPD.latest.build) > BUILD
    if W.row('se.upd', 'Software Update', y, { icon = '⬆️', iconBg = rgbm(0.45, 0.45, 0.5, 1), value = hasUpd and '1 new' or '', chevron = true, first = true }) then navPush(updateScreen()) end
    if hasUpd then circle(LIST.x + LIST.w - 70, y + 23, 9, T.red) text('1', 12, LIST.x + LIST.w - 70, y + 15, T.white, F.sb, 0.5) end
    y = y + 46
    W.row('se.ver', 'Version', y, { value = VERSION })
    W.row('se.srv', 'Server', y + 46, { value = ac.getSim().isOnlineRace and ((ac.getServerName and ac.getServerName()) or 'Online') or 'Offline' })
    if W.row('se.health', 'Phone health', y + 92, { value = #DIAG.errs > 0 and (#DIAG.errs .. ' issues') or 'OK', chevron = true, last = true }) then navPush(XM.healthScreen()) end
    y = W.sectionFooter('HackaPhone by smartnajeeri. Messages, plates and skins sync with friends on the same server.', y + 138)
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
local LV_PATTERNS = { 'Solid', 'Fade', 'Stripes', 'Checker', 'Camo', 'Carbon', 'Racing', 'Diagonal', 'Split', 'Forged', 'Digital', 'Tiger', 'Hex', 'Urban' }
local LV_NEEDS2 = { Fade = true, Stripes = true, Checker = true, Camo = true, Racing = true, Diagonal = true, Split = true, Digital = true, Tiger = true, Hex = true, Urban = true }
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

-- ---------------------------------------------------------------- 4K GPU paint textures
-- Patterns are rendered by a pixel shader into a 4096x4096 canvas (with MIPs), saved as DDS and applied to the paint.
local LV_SHADER = [[
#define LV_PI 3.14159265
float lvHash(float2 p) { p = frac(p * float2(234.34, 435.345)); p += dot(p, p + 34.23); return frac(p.x * p.y); }
float lvNoise(float2 p) {
  float2 i = floor(p); float2 f = frac(p);
  float a = lvHash(i); float b = lvHash(i + float2(1, 0)); float c = lvHash(i + float2(0, 1)); float d = lvHash(i + float2(1, 1));
  float2 u = f * f * (3.0 - 2.0 * f);
  return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}
float lvFbm(float2 p) {
  float v = 0.0; float a = 0.5;
  [unroll] for (int i = 0; i < 6; i++) { v += a * lvNoise(p); p = p * 2.02 + 17.0; a *= 0.5; }
  return v;
}
float lvEdge(float edge, float x) { float w = max(fwidth(x) * 1.5, 0.0005); return smoothstep(edge - w, edge + w, x); }
float lvHex(float2 p) { p = abs(p); return max(dot(p, normalize(float2(1.0, 1.7320508))), p.x); }

float4 main(PS_IN pin) {
  float2 uv = pin.Tex;
  float3 c1 = gC1.rgb;
  float3 c2 = gC2.rgb;
  float3 col = c1;
  int p = (int)(gPattern + 0.5);
  if (p == 2) {
    col = lerp(c1, c2, smoothstep(0.0, 1.0, uv.y));
  } else if (p == 3) {
    float s = frac(uv.y * 8.0);
    col = lerp(c1, c2, lvEdge(0.30, s) * (1.0 - lvEdge(0.42, s)));
  } else if (p == 4) {
    float2 g = floor(uv * 12.0);
    col = (fmod(g.x + g.y, 2.0) < 1.0) ? c2 : c1;
  } else if (p == 5 || p == 14) {
    float2 q = uv * 5.0 + gSeed;
    float n1 = lvFbm(q); float n2 = lvFbm(q * 1.6 + 31.7); float n3 = lvFbm(q * 2.3 + 71.1);
    float3 base = c1; float3 alt = c2;
    if (p == 14) { float g1 = dot(c1, float3(0.3, 0.59, 0.11)); float g2 = dot(c2, float3(0.3, 0.59, 0.11)); base = float3(g1, g1, g1); alt = float3(g2, g2, g2); }
    col = base;
    col = lerp(col, alt, lvEdge(0.50, n1));
    col = lerp(col, base * 0.42, lvEdge(0.55, n2));
    col = lerp(col, lerp(base, alt, 0.5) * 1.15, lvEdge(0.60, n3));
  } else if (p == 6) {
    float2 g = uv * 384.0; float2 cell = floor(g); float2 f = frac(g);
    bool horiz = fmod(cell.x + cell.y, 4.0) < 2.0;
    float across = horiz ? f.y : f.x;
    float along = horiz ? g.x : g.y;
    float shade = pow(sin(across * LV_PI), 0.8) * (0.85 + 0.15 * lvNoise(float2(along * 3.0, across * 40.0)));
    float3 dark = float3(0.022, 0.024, 0.028); float3 lite = float3(0.15, 0.155, 0.17);
    col = lerp(dark, lite, shade) + c1 * 0.04;
  } else if (p == 7) {
    float m = lvEdge(0.40, uv.x) * (1.0 - lvEdge(0.47, uv.x)) + lvEdge(0.53, uv.x) * (1.0 - lvEdge(0.60, uv.x));
    col = lerp(c1, c2, m);
  } else if (p == 8) {
    float s = frac((uv.x * 0.55 + uv.y) * 5.0);
    col = lerp(c1, c2, lvEdge(0.15, s) * (1.0 - lvEdge(0.45, s)));
  } else if (p == 9) {
    col = lerp(c1, c2, lvEdge(0.5, uv.y));
  } else if (p == 10) {
    float2 q = uv * 22.0 + float2(lvFbm(uv * 4.0), lvFbm(uv * 4.0 + 9.0)) * 2.0;
    float2 i = floor(q); float2 f = frac(q);
    float best = 8.0; float id = 0.0;
    [unroll] for (int y = -1; y <= 1; y++) [unroll] for (int x = -1; x <= 1; x++) {
      float2 o = float2(x, y); float2 pt = float2(lvHash(i + o), lvHash(i + o + 5.3));
      float d = length(o + pt - f);
      if (d < best) { best = d; id = lvHash(i + o + 11.7); }
    }
    float v = 0.05 + id * 0.16;
    col = float3(v, v, v * 1.04) * (0.8 + 0.2 * smoothstep(0.0, 0.6, best)) + c1 * 0.03;
  } else if (p == 11) {
    float2 g = floor(uv * 96.0) / 96.0;
    float n = lvFbm(g * 7.0 + gSeed) + (lvHash(floor(uv * 192.0)) - 0.5) * 0.12;
    col = c1;
    col = lerp(col, c2, step(0.48, n));
    col = lerp(col, c1 * 0.45, step(0.58, n));
    col = lerp(col, lerp(c1, c2, 0.5) * 1.2, step(0.66, n));
  } else if (p == 12) {
    float w = lvFbm(uv * 3.0 + gSeed) * 0.7;
    float s = sin((uv.x + w) * 42.0 + lvFbm(uv * 8.0) * 3.0) * 0.5 + 0.5;
    col = lerp(c1, c2, lvEdge(0.62, s));
  } else if (p == 13) {
    float2 r = float2(1.0, 1.7320508);
    float2 q = uv * 40.0;
    float2 a = fmod(q, r) - r * 0.5;
    float2 b = fmod(q - r * 0.5, r) - r * 0.5;
    float2 h = dot(a, a) < dot(b, b) ? a : b;
    float d = lvHex(h);
    col = lerp(c1, c2, lvEdge(0.44, d));
  }
  int fin = (int)(gFinish + 0.5);
  if (fin == 4 || fin == 5 || fin == 8) {
    float flake = lvHash(floor(uv * 2048.0));
    col += (flake - 0.5) * (fin == 5 ? 0.10 : 0.07) * (0.4 + dot(col, float3(0.33, 0.33, 0.33)));
  }
  if (fin == 5) col = lerp(col, col.gbr, 0.06 + 0.06 * sin(uv.x * 9.0 + uv.y * 5.0));
  if (fin == 8) col = col * col * 1.25;
  return float4(saturate(col), 1.0);
}
]]

LV.files = {}
LV.res = 4096
LV.shaderOK = nil   -- nil = untested, true/false after self-test

local function lvDir() return ac.getFolder(ac.FolderID.ScriptOrigin) .. '/liveries' end

local function lvValues(cfg)
  return { gC1 = col(cfg.c1), gC2 = col(cfg.c2), gPattern = cfg.pattern or 1, gFinish = cfg.finish or 1, gSeed = 3.7 }
end

-- renders cfg into a DDS file; returns its path or nil
local function lvRenderTexture(cfg, tag)
  if not (ui.ExtraCanvas and LV.shaderOK ~= false) then return nil end
  local ok, path = pcall(function()
    local canvas = ui.ExtraCanvas(vec2(LV.res, LV.res), 12)
    canvas:clear(col(cfg.c1))
    canvas:updateWithShader({ values = lvValues(cfg), shader = LV_SHADER, cacheKey = 7 })
    pcall(function() canvas:mipsUpdate() end)
    pcall(io.createDir, lvDir())
    LV.serial = (LV.serial or 0) + 1
    local file = lvDir() .. '/' .. tag .. '_' .. os.time() .. '_' .. LV.serial .. '.dds'
    canvas:save(file, ac.ImageFormat and ac.ImageFormat.DDS or nil)
    canvas:dispose()
    return file
  end)
  if not ok or not path then return nil end
  if LV.files[tag] and LV.files[tag] ~= path then pcall(io.deleteFile, LV.files[tag]) end
  LV.files[tag] = path
  return path
end

-- one-time check that the shader compiles on this PC; falls back to simple patterns if not
local function lvSelfTest()
  if LV.shaderOK ~= nil or not ui.ExtraCanvas then return end
  LV.shaderOK = false
  pcall(function()
    local probe = ui.ExtraCanvas(vec2(8, 8), 1)
    probe:clear(rgbm(1, 0, 1, 1))
    probe:updateWithShader({ values = { gC1 = rgbm(0, 1, 0, 1), gC2 = rgbm(0, 0, 1, 1), gPattern = 1, gFinish = 1, gSeed = 3.7 }, shader = LV_SHADER, cacheKey = 7 })
    probe:accessData(function(err, data)
      if not err and data then
        local c = data:color(4, 4)
        LV.shaderOK = c.g > 0.8 and c.r < 0.2
      end
      probe:dispose()
    end)
  end)
end
LV.selfTest = lvSelfTest

-- clear textures left from earlier sessions
pcall(function()
  for _, f in ipairs(io.scanDir(lvDir(), '*.dds') or {}) do pcall(io.deleteFile, lvDir() .. '/' .. f) end
end)

local function lvApply(index, cfg)
  if not cfg or not cfg.on then return 0 end
  local count = 0
  local body = lvMeshes(index, 'body')
  local tex = #body > 0 and lvRenderTexture(cfg, 'car' .. index) or nil
  for _, m in ipairs(body) do
    count = count + 1
    pcall(function()
      m:ensureUniqueMaterials()
      if tex and cfg.full then
        m:setMaterialTexture('txDiffuse', tex)
      elseif tex then
        m:setMaterialTexture('txDiffuse', {
          textureSize = vec2(2048, 2048),
          background = nil,
          callback = function() display.image({ image = tex, pos = vec2(0, 0), size = vec2(2048, 2048), color = rgbm(1, 1, 1, cfg.strength) }) end,
        })
      else
        m:setMaterialTexture('txDiffuse', {
          textureSize = vec2(1024, 1024),
          background = cfg.full and col(cfg.c1) or nil,
          callback = function() lvDrawPattern(cfg, 1024) end,
        })
      end
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
  if #n < 18 then return nil end
  local function c(i) return { n[i] / 255, n[i + 1] / 255, n[i + 2] / 255 } end
  return { on = true, c1 = c(1), c2 = c(4), pattern = n[7], finish = n[8], full = n[9] == 1, strength = n[10] / 100,
    rimsOn = n[11] == 1, rims = c(12), calOn = n[15] == 1, cal = c(16) }
end

local liveryEvent = ac.OnlineEvent({
  ac.StructItem.key('acphone.livery.v1'),
  data = ac.StructItem.string(96),
}, function(sender, msg)
  if not sender or sender.index == 0 or not S.liveryShowOthers then return end
  local raw = tostring(msg.data)
  local cfg = lvUnpack(raw)
  if not cfg then return end
  -- friends re-send every so often for late joiners; skip the redundant repaint
  local prev = LV.othersRaw and LV.othersRaw[sender.index]
  LV.othersRaw = LV.othersRaw or {}
  LV.othersRaw[sender.index] = { raw = raw, t = clock() }
  -- same livery as before and the sender has been around: nothing to repaint
  if prev and prev.raw == raw and clock() - prev.t < 100 then return end
  LV.others[sender.index] = cfg
  -- repaints are queued and done one at a time so a busy server never causes a hitch
  LV.queue = LV.queue or {}
  LV.queue[sender.index] = cfg
end)

local function lvDrain()
  if not LV.queue then return end
  for idx, cfg in pairs(LV.queue) do
    LV.queue[idx] = nil
    pcall(function()
      if cfg.on then lvApply(idx, cfg) else SK.skinApply(idx, SK.skinActive(idx)) end
    end)
    return
  end
end

local function lvBroadcast()
  if S.liverySync then local d = lvPack(LV.cfg) NET.send(function() return liveryEvent({ data = d }) end, 3, 'livery') end
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
  -- real preview: the same GPU shader, rendered small
  local drewShader = false
  if cfg.on and LV.shaderOK and ui.ExtraCanvas then
    local key = lvPack(cfg)
    if LV.prevKey ~= key then
      pcall(function()
        LV.prevCanvas = LV.prevCanvas or ui.ExtraCanvas(vec2(512, 512), 1)
        LV.prevCanvas:updateWithShader({ values = lvValues(cfg), shader = LV_SHADER, cacheKey = 7 })
      end)
      LV.prevKey = key
    end
    if LV.prevCanvas then
      drewShader = pcall(ui.drawImageRounded, LV.prevCanvas, P(bx1, by1), P(bx2, by2), A(T.white), vec2(0.15, 0.25), vec2(0.85, 0.55), 14)
      pcall(ui.drawImageRounded, LV.prevCanvas, P(bx1 + w * 0.24, by1 - 32), P(bx2 - w * 0.14, by1 + 4), A(T.white), vec2(0.3, 0.1), vec2(0.7, 0.2), 6)
      ui.drawQuadFilled(P(bx1 + w * 0.26, by1 - 2), P(bx1 + w * 0.34, by1 - 29), P(bx2 - w * 0.31, by1 - 29), P(bx2 - w * 0.16, by1 - 2), A(rgbm(0.12, 0.16, 0.22, 1)))
    end
  end
  if cfg.on and not drewShader then
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
    y = W.sectionFooter('Friends with HackaPhone see your paint live. Swapping skins replaces the livery until you re-apply it.', y + 92)
    scrollEnd(s, y + 20)
    navBar('Livery', { large = true }, s.y)
  end
  return scr
end

LIVERY_API.apply = lvApply
LIVERY_API.selfTest = function() LV.selfTest() end
LIVERY_API.shaderOK = function() return LV.shaderOK end
LIVERY_API.broadcast = lvBroadcast
LIVERY_API.tick = function(dt)
  LV.bt = (LV.bt or 0) + dt
  LV.dt_ = (LV.dt_ or 0) + dt
  if LV.dt_ > 0.5 then LV.dt_ = 0 lvDrain() end
  if LV.bt > 45 then
    LV.bt = 0
    -- (livery goes out with the phone's periodic hello and on changes)
  end
end
LIVERY_API.unpack, LIVERY_API.pack = lvUnpack, lvPack
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
      textFit(((m.artist or '') ~= '' and m.artist or 'Unknown artist') .. ((m.album or '') ~= '' and (' · ' .. m.album) or ''), 15, 36, y + 32, SW - 72, T.label2, F.m)
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
    if XM.vault.cur then
      if W.button('mu.stopvault', 'Playing from Vault · stop', 36, y + 30, SW - 72, 34, 'tinted') then XM.vault.stop() end
    else
      if W.button('mu.vault', 'Open Vault: queue, search, your own tracks', 36, y + 30, SW - 72, 34, 'tinted') then APPMOD.openApp('vault') end
    end
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
    local mArt = S.wallMode == 'music' and MEDIA.now()
    if mArt and mArt.hasCover and WALL.cover(mArt, px, y, px + pw, y + ph, 26) then
      if S.wallDim > 0 then rect(px, y, px + pw, y + ph, rgbm(0, 0, 0, S.wallDim), 26) end
    elseif not (wp and WALL.cover(wp, px, y, px + pw, y + ph, 26)) then
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
    local modes = { 'theme', 'car', 'track', 'custom', 'music' }
    local labels = { 'Theme', 'Car', 'Track', 'Photo', 'Music' }
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
    elseif S.wallMode == 'music' then
      text('ALBUM ART STYLE', 12, LIST.x + 16, y, T.label2, F.r)
      y = y + 22
      S.musicArtMode = W.segmented('wp.artmode', { 'Actual art', 'Blurred', 'Art + blur' }, S.musicArtMode, 16, y, SW - 32)
      y = y + 44
      if S.musicArtMode ~= 1 then
        rect(LIST.x, y, LIST.x + LIST.w, y + 74, T.cell, 14)
        local v, chb = W.sliderRow('wp.blurAmt', 'Blur amount', S.musicBlurAmt * 100, 0, 100, '%d%%', y, { last = true })
        if chb then S.musicBlurAmt = v / 100 end
        y = y + 84
      end
      y = W.sectionFooter('Your wallpaper becomes the cover of the song that’s playing and changes with every track. Actual art shows the sharp cover, Blurred softens it, and Art + blur floats the sharp cover over a blurred backdrop. With no song playing you get the theme wallpaper.', y + 46)
    elseif S.wallMode ~= 'theme' and not WALL.path() then
      y = W.sectionFooter(S.wallMode == 'car' and 'This skin has no preview image yet. Content Manager can generate one.' or 'This track has no preview image.', y)
    end
    if S.wallMode ~= 'theme' then
      rect(LIST.x, y + 4, LIST.x + LIST.w, y + 78, T.cell, 14)
      local v, ch2 = W.sliderRow('wp.dim', 'Dim', S.wallDim * 100, 0, 80, '%d%%', y + 4, { last = true })
      if ch2 then S.wallDim = v / 100 end
      y = y + 92
    end

    -- size
    y = W.sectionHeader('Size', y + 4)
    rect(LIST.x, y, LIST.x + LIST.w, y + 148, T.cell, 14)
    local pv, pch = W.sliderRow('pf.size', 'Phone size', (S.phoneScale or 1) * 100, 60, 180, '%d%%', y)
    if pch then S.phoneScale = math.floor(pv + 0.5) / 100 end
    local bv, bch = W.sliderRow('pf.bar', 'Action bar size', (S.barScale or 1) * 100, 50, 200, '%d%%', y + 74, { last = true })
    if bch then S.barScale = math.floor(bv + 0.5) / 100 end
    y = y + 156
    local sizes = { { 'S', 0.8 }, { 'M', 1.0 }, { 'L', 1.25 }, { 'XL', 1.5 } }
    local bw = (SW - 32 - 3 * 8) / 4
    for i, sz in ipairs(sizes) do
      if W.button('pf.sz' .. i, sz[1], 16 + (i - 1) * (bw + 8), y, bw, 36, math.abs((S.phoneScale or 1) - sz[2]) < 0.01 and 'filled' or 'gray') then S.phoneScale = sz[2] end
    end
    y = y + 44
    y = W.sectionFooter('You can also drag the phone’s frame edge or bottom-right corner to resize. Right-click and drag anywhere (or long-press the status bar) to move it.', y)

    -- type & icons
    y = W.sectionHeader('Font', y + 4)
    -- font gallery: every chip previews its own typeface
    do
      local cw, ch = (SW - 32 - 10) / 2, 54
      for i, f in ipairs(FONT_FAMILIES) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x, fy = 16 + col * (cw + 10), y + row * (ch + 8)
        local sel = (S.font or 1) == i
        local fired = tap('pf.font' .. i, x, fy, x + cw, fy + ch)
        rect(x, fy, x + cw, fy + ch, sel and A(accent(), 0.20) or T.cell, 14)
        if sel then rectLine(x, fy, x + cw, fy + ch, accent(), 14, 1.5) end
        local sf = FONT_FAMILIES.samples[i]
        if not sf then sf = makeFont(ui.DWriteFont.Weight.SemiBold, 'fs' .. i, f.family) FONT_FAMILIES.samples[i] = sf end
        text('Aa', 24, x + 16, fy + 10, sel and accent() or T.white, sf)
        text(f.name, 13, x + 62, fy + 12, T.label, sf)
        text('Race 0123', 10, x + 62, fy + 31, T.label2, sf)
        if fired and not sel then S.font = i buildFonts() end
      end
      y = y + math.ceil(#FONT_FAMILIES / 2) * (ch + 8) - 8
    end
    y = y + 44
    y = W.sectionHeader('App icons', y + 8)
    S.iconStyle = W.segmented('pf.icons', { 'Colour', 'Glass', 'Minimal' }, S.iconStyle or 1, 16, y, SW - 32)
    y = y + 52
    W.groupBg(y, 4)
    local v = W.toggleRow('th.thick', 'Bold text', S.thick, y, { first = true })
    if v ~= S.thick then S.thick = v buildFonts() end
    S.motifs = W.toggleRow('th.motif', 'Theme symbols', S.motifs, y + 46)
    if W.row('th.home', 'Home Screen apps', y + 92, { chevron = true }) then navPush(personalizeHome()) end
    if W.row('th.welcome', 'Welcome Screen', y + 138, { chevron = true, last = true }) then navPush(APPMOD.Themes.welcome()) end
    y = y + 196

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

local LV_TAB = 2
local function boardRows(kind)
  local rows = {}
  local myName = ac.getDriverName(0) or 'You'
  if kind == 3 then
    local ok, crew = pcall(JSON.parse, S.hesiCrew)
    crew = (ok and type(crew) == 'table') and crew or {}
    crew[myName] = math.max(crew[myName] or 0, S.hesiPB)
    for name, pb in pairs(crew) do rows[#rows + 1] = { name = name, score = pb, me = name == myName } end
  else
    rows[#rows + 1] = { name = myName, me = true, score = kind == 1 and HESI.run or HESI.sessionBest, running = HESI.running, mult = HESI.mult, total = HESI.sessionTotal, ev = HESI.lastEvt, crashes = HESI.crashes }
    for _, b in pairs(HESI.board) do
      if clock() - b.at < 120 then
        rows[#rows + 1] = { name = b.name, score = kind == 1 and b.run or b.best, running = b.running, mult = b.mult, total = b.total, ev = b.ev, crashes = b.crashes }
      end
    end
  end
  table.sort(rows, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.name < b.name end)
  return rows
end


HESI.ui = {}
local MEDAL = { rgbm(1, 0.82, 0.25, 1), rgbm(0.80, 0.82, 0.86, 1), rgbm(0.85, 0.55, 0.30, 1) }
local function evTag(r)
  local e = r.ev
  if e and clock() - e.at < 25 then
    local age = clock() - e.at
    if e.kind == 1 then return 'Crashed  +' .. HESI.fmt(e.score), T.red, 1, age end
    return 'Banked  +' .. HESI.fmt(e.score), rgbm(0.35, 1, 0.55, 1), 2, age
  end
end
local function subFor(r, kind)
  local tag, tc = evTag(r)
  if tag then return tag, tc end
  if kind == 1 then
    if r.running then return string.format('Running  x%.1f', r.mult or 1), HESI.tierColor(r.mult) end
    return 'Idle', T.label2
  elseif kind == 2 then return 'Banked ' .. HESI.fmt(r.total or 0), T.label2 end
  return 'Personal best', T.label2
end

-- top three on a podium; columns slide to their new places when the order changes
function HESI.ui.podium(rows, y, kind)
  if #rows < 1 then
    text('Nobody has a score yet. Go cut some traffic.', 13, SW / 2, y + 40, T.label2, F.r, 0.5)
    return y + 90
  end
  local pw = (SW - 32 - 16) / 3
  local heights = { 100, 78, 62 }
  local slotOf = { 2, 1, 3 }
  local base = y + 172
  for rank = 1, math.min(3, #rows) do
    local r = rows[rank]
    local key = 'pod' .. kind .. r.name
    local x = HESI.anim(key .. 'x', 16 + (slotOf[rank] - 1) * (pw + 8), 9)
    local h = HESI.anim(key .. 'h', heights[rank], 9)
    local col = MEDAL[rank]
    local tag, tcol, tk, age = evTag(r)
    if tk == 1 and age < 0.7 then x = x + math.sin(age * 55) * 5 * (1 - age / 0.7) end
    local colTop = base - h
    local cx = x + pw / 2
    local sc = HESI.anim(key .. 's', r.score, 7)
    local glow = r.running and (0.5 + 0.5 * math.sin(clock() * 5)) or 0
    -- column
    rect(x, colTop, x + pw, base, mix(T.cell, col, 0.2 + 0.12 * glow), 12, ui.CornerFlags.Top)
    rect(x, colTop, x + pw, colTop + 3, col, 2)
    if tk then
      local f = clamp(1 - age / 6, 0, 1)
      rect(x, colTop, x + pw, base, A(tcol, 0.22 * f), 12, ui.CornerFlags.Top)
    end
    text(tostring(rank), 24, cx, colTop + 8, col, F.numb, 0.5)
    textFit(HESI.fmt(sc), h > 70 and 15 or 13, cx, colTop + 38, pw - 8, T.white, F.numb, 0.5)
    -- avatar + name above the column
    avatar(r.name, cx - 22, colTop - 58, 44)
    if r.running then rectLine(cx - 25, colTop - 61, cx + 25, colTop - 11, A(HESI.tierColor(r.mult), 0.6 + 0.4 * glow), 25, 2) end
    if r.me then rectLine(cx - 25, colTop - 61, cx + 25, colTop - 11, A(accent(), 0.9), 25, 2) end
    textFit(r.name, 12, cx, colTop - 8, pw - 6, T.label, F.sb, 0.5)
    -- crash / bank / running tag under the column
    local label, lc = subFor(r, kind)
    if tag or r.running then
      rect(x + 2, base + 5, x + pw - 2, base + 23, A(lc, 0.16), 9)
      textFit(label, 10, cx, base + 8, pw - 10, lc, F.b, 0.5)
    end
  end
  return base + 32
end

-- ranks 4 and below, each row sliding smoothly when places change
function HESI.ui.list(rows, y, kind, from)
  local n = #rows - from + 1
  if n < 1 then return y end
  local h = 56
  rect(LIST.x, y, LIST.x + LIST.w, y + n * h, T.cell, 14)
  if S.thick then rectLine(LIST.x, y, LIST.x + LIST.w, y + n * h, T.border, 14, 1.5) end
  for i = from, #rows do
    local r = rows[i]
    local yy = HESI.anim('row' .. kind .. r.name, y + (i - from) * h, 10)
    local tag, tcol, tk, age = evTag(r)
    if r.me then rect(LIST.x, yy, LIST.x + LIST.w, yy + h, A(accent(), 0.14), 14) end
    if tk then rect(LIST.x, yy, LIST.x + LIST.w, yy + h, A(tcol, 0.16 * clamp(1 - age / 6, 0, 1)), 14) end
    local dx = (tk == 1 and age < 0.7) and math.sin(age * 55) * 5 * (1 - age / 0.7) or 0
    text(tostring(i), 16, LIST.x + 22 + dx, yy + 17, T.label2, F.numb, 0.5)
    avatar(r.name, LIST.x + 42 + dx, yy + 10, 36)
    textFit(r.name .. (r.me and '  (you)' or ''), 15, LIST.x + 88 + dx, yy + 9, LIST.w - 200, T.label, F.sb)
    local sub, sc = subFor(r, kind)
    textFit(sub, 12, LIST.x + 88 + dx, yy + 31, LIST.w - 200, sc)
    text(HESI.fmt(HESI.anim('rs' .. kind .. r.name, r.score, 7)), 17, LIST.x + LIST.w - 14, yy + 17, T.white, F.numb, 1)
  end
  return y + n * h
end

function APPMOD.CutUp.root()
  local scr = { title = 'Cut-Up' }
  local tab = 1
  function scr.draw()
    bgFill()
    local s = scrollBegin('cutup', 50, BOTTOM)
    local y = largeTitle('Cut-Up', 96, s.y)
    -- hero card: glows in the colour of your current tier
    local ac1 = accent()
    local run = HESI.running
    local tc = run and HESI.tierColor() or ac1
    local beat = 0.5 + 0.5 * math.sin(clock() * 4)
    local hot = run and clamp(HESI.mult / 10, 0, 1) or 0
    local H = 190
    rect(16, y, SW - 16, y + H, mix(T.cell, tc, run and (0.14 + 0.12 * HESI.pulse + 0.06 * beat * hot) or 0.06), 22)
    if HESI.crashFlash > 0 then rect(16, y, SW - 16, y + H, A(T.red, 0.35 * HESI.crashFlash), 22) end
    if HESI.bankFlash > 0 then rect(16, y, SW - 16, y + H, A(rgbm(0.3, 1, 0.5, 1), 0.3 * HESI.bankFlash), 22) end
    rectLine(16, y, SW - 16, y + H, A(tc, 0.45 + 0.4 * hot * beat + 0.3 * HESI.pulse), 22, 2)
    if run then
      text('@BURN LIVE RUN', 11, 34, y + 16, tc, F.b)
      local tier = HESI.tier()
      text(tier ~= '' and tier or 'CRUISING', 11, SW - 34, y + 16, tc, F.b, 1)
      local shown = HESI.anim('cu.score', HESI.run, 14)
      text(HESI.fmt(shown), 50 + math.floor(HESI.pulse * 4), 32, y + 34, T.white, F.numb)
      text(string.format('x%.1f', HESI.mult), 34, SW - 34, y + 52, tc, F.numb, 1)
      -- tier ladder
      local ladder = { 1, 3, 6, 10, 15 }
      local lw = (SW - 68 - 4 * 5) / 5
      for i, at in ipairs(ladder) do
        local x = 34 + (i - 1) * (lw + 5)
        local on = HESI.mult >= at
        rect(x, y + 104, x + lw, y + 110, on and HESI.tierColor(at) or rgbm(1, 1, 1, 0.1), 3)
      end
      -- combo timer
      local cf = clamp(HESI.combo / HESI.comboMax, 0, 1)
      rect(34, y + 118, SW - 34, y + 122, rgbm(1, 1, 1, 0.1), 2)
      rect(34, y + 118, 34 + (SW - 68) * cf, y + 122, cf < 0.25 and T.red or tc, 2)
      -- last events
      for i = 1, 2 do
        local f = HESI.feed[i]
        if f then
          local fa = clamp(1 - (f.t - 3) / 1.5, 0.25, 1)
          text(f.text, 13, 34, y + 130 + (i - 1) * 21, A(f.color, fa), F.numb)
        end
      end
    else
      glyph('BURN', 32, y + 24, 44, ac1)
      text('Ready to run', 22, 92, y + 26, T.white, F.b)
      text('Go over ' .. HESI.startSpeed .. ' km/h to start', 13, 92, y + 56, T.label2)
      local lr = HESI.lastRun
      if lr then
        text(lr.crashed and 'CRASHED · BANKED ANYWAY' or 'LAST RUN BANKED', 10, 34, y + 100, lr.crashed and T.red or rgbm(0.4, 1, 0.55, 1), F.b)
        text('+' .. HESI.fmt(lr.score), 30, 34, y + 116, lr.crashed and T.red or rgbm(0.4, 1, 0.55, 1), F.numb)
      end
      textBox('Near misses, close calls, lane splits and oncoming passes stack your multiplier.', 12, 34, y + 156, SW - 34, y + 184, T.label2)
    end
    y = y + 204
    local lr = HESI.lastRun
    if lr and not HESI.running then
      rect(16, y, SW - 16, y + 132, T.cell, 18)
      if S.thick then rectLine(16, y, SW - 16, y + 132, T.border, 18, 1.5) end
      text(lr.crashed and '@COLLISION LAST RUN · CRASHED, BANKED' or (lr.pb and '@TROPHY LAST RUN · NEW PB' or '@CONFIRM LAST RUN · BANKED'), 11, 32, y + 14,
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
    y = HESI.ui.podium(rows, y, tab)
    y = HESI.ui.list(rows, y, tab, 4) + 6
    y = W.sectionFooter('Everyone with HackaPhone shows here live. All-time bests are remembered on this PC.', y)
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

-- ===========================================================================
-- LEADERBOARDS (server standings, lap times, Cut-Up, drift)
-- ===========================================================================

local SESSION_NAMES = { [0] = 'Session', 'Practice', 'Qualifying', 'Race', 'Hotlap', 'Time Attack', 'Drift', 'Drag' }

local function standings()
  local rows, sim = {}, ac.getSim()
  for i = 0, sim.carsCount - 1 do
    local lbf = type(ac.getCar) == 'table' and ac.getCar.leaderboard or nil
    local c = lbf and lbf(i) or ac.getCar(i)
    if c and (c.index == 0 or c.isConnected) and c.isActive ~= false then
      rows[#rows + 1] = {
        index = c.index, name = ac.getDriverName(c.index) or ('Car ' .. c.index), car = ac.getCarName(c.index) or '',
        best = c.bestLapTimeMs or 0, last = c.previousLapTimeMs or 0, laps = c.lapCount or 0,
        pos = c.racePosition or (#rows + 1), pit = c.isInPitlane, drift = c.driftPoints or 0, me = c.index == 0,
      }
    end
  end
  return rows
end

local function lbRow(r, rank, y, right, sub, rightColor)
  local h = 58
  if r.me then rect(LIST.x, y, LIST.x + LIST.w, y + h, A(accent(), 0.14), 14) end
  local rc = rank == 1 and rgbm(1, 0.82, 0.25, 1) or (rank == 2 and rgbm(0.80, 0.82, 0.86, 1) or (rank == 3 and rgbm(0.85, 0.55, 0.30, 1) or T.label2))
  text(tostring(rank), 18, LIST.x + 22, y + 17, rc, F.numb, 0.5)
  avatar(r.name, LIST.x + 42, y + 11, 36)
  textFit(r.name .. (r.me and '  (you)' or ''), 15, LIST.x + 88, y + 10, LIST.w - 190, T.label, F.sb)
  textFit(sub, 12, LIST.x + 88, y + 32, LIST.w - 190, T.label2)
  text(right, 16, LIST.x + LIST.w - 14, y + 18, rightColor or T.white, F.numb, 1)
  return y + h
end

function APPMOD.Leaders.root()
  local scr = { title = 'Leaderboards' }
  local tab = 1
  function scr.draw()
    bgFill()
    local sim = ac.getSim()
    local s = scrollBegin('leaders', 50, BOTTOM)
    local y = largeTitle('Leaderboards', 96, s.y)
    -- session header
    local stype = SESSION_NAMES[sim.raceSessionType or 0] or 'Session'
    local left = sim.sessionTimeLeft and sim.sessionTimeLeft > 0 and sim.sessionTimeLeft or nil
    textFit((sim.isOnlineRace and ((ac.getServerName and ac.getServerName()) or 'Server') or 'Offline') .. ' · ' .. stype, 13, 16, y - 12, SW - 120, T.label2, F.m)
    if left then text(string.format('%d:%02d left', math.floor(left / 60000), math.floor(left / 1000) % 60), 13, SW - 16, y - 12, accent(), F.num, 1) end
    y = y + 14
    tab = W.segmented('lb.tab', { 'Standings', 'Laps', 'Drift' }, tab, 16, y, SW - 32)
    y = y + 50
    local rows = standings()
    local list = {}
    if tab == 1 then
      -- standings are ranked by Cut-Up points
      local bt = W.segmented('lb.cu', { 'Live', 'Session', 'All-time' }, LV_TAB or 2, 16, y, SW - 32)
      LV_TAB = bt
      y = y + 48
      local cr = boardRows(bt)
      y = HESI.ui.podium(cr, y, bt)
      y = HESI.ui.list(cr, y, bt, 4)
    elseif tab == 2 then
      for _, r in ipairs(rows) do if r.best > 0 then list[#list + 1] = r end end
      table.sort(list, function(a, b) return a.best < b.best end)
      if #list == 0 then text('No lap times set yet', 14, SW / 2, y + 20, T.label2, F.r, 0.5) y = y + 60 end
      rect(LIST.x, y, LIST.x + LIST.w, y + math.max(1, #list) * 58, T.cell, 14)
      for i, r in ipairs(list) do
        y = lbRow(r, i, y, fmtLap(r.best), 'Last ' .. fmtLap(r.last) .. ' · ' .. r.laps .. ' laps', i == 1 and rgbm(0.75, 0.45, 1, 1) or nil)
      end
    else
      for _, r in ipairs(rows) do if r.drift > 0 then list[#list + 1] = r end end
      table.sort(list, function(a, b) return a.drift > b.drift end)
      if #list == 0 then text('No drift points yet', 14, SW / 2, y + 20, T.label2, F.r, 0.5) y = y + 60 end
      rect(LIST.x, y, LIST.x + LIST.w, y + math.max(1, #list) * 58, T.cell, 14)
      for i, r in ipairs(list) do y = lbRow(r, i, y, HESI.fmt(r.drift), r.car) end
    end
    y = W.sectionFooter('Standings are Cut-Up points from drivers running HackaPhone. Lap times and drift come from the server.', y + 6)
    scrollEnd(s, y + 20)
    navBar('Leaderboards', { large = true }, s.y)
  end
  return scr
end

end
-- ===========================================================================
-- v1.0 apps: Bank, Market, Power-Ups, Runs, Vault, camera angle editor, welcome screen
-- ===========================================================================

do
local VAULT = XM.vault
local GOLD = rgbm(1, 0.8, 0.25, 1)
local MONEY_GREEN = rgbm(0.35, 0.95, 0.55, 1)
local money = XM.money

local function ago(t)
  local d = os.time() - t
  if d < 60 then return 'just now' end
  if d < 3600 then return math.floor(d / 60) .. ' min ago' end
  if d < 86400 then return math.floor(d / 3600) .. ' h ago' end
  return math.floor(d / 86400) .. ' d ago'
end

local function visible(s, yy, h) return yy + h > s.y - 20 and yy < s.y + SH + 20 end

local function tile(x, y, w, h, label, value, color)
  rect(x, y, x + w, y + h, T.cell, 14)
  if S.thick and T.border then rectLine(x, y, x + w, y + h, T.border, 14, 1.5) end
  text(label, 9, x + 10, y + 10, T.label2, F.b)
  textFit(value, 18, x + 10, y + 28, w - 20, color or T.white, F.numb)
end

local function tileRow(y, items)
  local n = #items
  local gap = 10
  local w = (SW - 32 - gap * (n - 1)) / n
  for i, it in ipairs(items) do tile(16 + (i - 1) * (w + gap), y, w, 62, it[1], it[2], it[3]) end
  return y + 74
end

local function sparkline(x1, y1, x2, y2, vals, color)
  local lo, hi = math.huge, -math.huge
  for _, v in ipairs(vals) do lo = math.min(lo, v) hi = math.max(hi, v) end
  if hi - lo < 1e-6 then hi = lo + 1 end
  local n = #vals
  local px, py
  for i, v in ipairs(vals) do
    local x = x1 + (x2 - x1) * (i - 1) / (n - 1)
    local y = y2 - (y2 - y1) * (v - lo) / (hi - lo)
    if px then line(px, py, x, y, color, 2) end
    px, py = x, y
  end
  circle(px, py, 3.5, color)
end

local function smallButton(id, label, x, y, w, h, style, color)
  return W.button(id, label, x, y, w, h or 30, style or 'tinted', color)
end

local function cardNumber(name)
  local h = 7919
  for i = 1, #name do h = (h * 31 + name:byte(i)) % 100000 end
  return string.format('•••• %04d', h % 10000)
end

-- ===========================================================================
-- CAMERA ANGLE EDITOR
-- ===========================================================================
function APPMOD.Video.editor(shotId)
  local shot
  for _, sh in ipairs(VIDEO_SHOTS) do if sh.id == shotId then shot = sh end end
  local scr = { title = shot.name .. ' angle' }
  local nameField = ''
  function scr.draw()
    bgFill()
    local s = scrollBegin('shotedit' .. shotId, 94, BOTTOM)
    local y = 104
    -- live preview switch: the camera follows your edits as you drag
    local live = CAM.mode == 'video' and CAM.shot == shotId
    W.groupBg(y, 1)
    local want = W.toggleRow('se.live', 'Live preview', live, y, { first = true, last = true, icon = '🎥', iconBg = rgbm(1, 0.35, 0.3, 1) })
    if want ~= live then
      if want then CAM.shot = shotId CAM.flybyInit = nil if CAM.mode then camRelease() end videoStart() else camRelease() end
    end
    y = W.sectionFooter('Turn this on and drag the sliders to see the angle change on your car straight away.', y + 46)
    local cfgAll = XM.jget('shotCfg', {})
    local cfg = cfgAll[shotId] or {}
    y = W.sectionHeader('Adjust', y)
    local n = #shot.params
    rect(LIST.x, y, LIST.x + LIST.w, y + n * 74, T.cell, 14)
    if S.thick and T.border then rectLine(LIST.x, y, LIST.x + LIST.w, y + n * 74, T.border, 14, 1.5) end
    for i, p in ipairs(shot.params) do
      local cur = cfg[p.key]
      if cur == nil then cur = p.def end
      local v, ch = W.sliderRow('se.' .. shotId .. p.key, p.label, cur, p.min, p.max, p.fmt, y, { last = i == n })
      if ch then
        cfg[p.key] = v
        cfgAll[shotId] = cfg
        XM.jset('shotCfg', cfgAll)
      end
      y = y + 74
    end
    y = y + 12
    if W.button('se.reset', 'Reset to default', 16, y, SW - 32, 40, 'gray') then
      cfgAll[shotId] = nil XM.jset('shotCfg', cfgAll)
    end
    y = y + 54
    -- saved angles
    y = W.sectionHeader('My ' .. shot.name .. ' angles', y)
    local presets = XM.jget('shotPresets', {})
    local list = presets[shotId] or {}
    rect(LIST.x, y, LIST.x + LIST.w, y + 56, T.cell, 14)
    nameField = W.field('se.name', nameField, 'Name this angle', LIST.x + 10, y + 10, LIST.w - 110, 36)
    if W.button('se.save', 'Save', LIST.x + LIST.w - 90, y + 10, 80, 36, 'filled') then
      local vals = {}
      for _, p in ipairs(shot.params) do vals[p.key] = cfg[p.key] ~= nil and cfg[p.key] or p.def end
      list[#list + 1] = { name = nameField ~= '' and nameField or ('Angle ' .. (#list + 1)), vals = vals }
      presets[shotId] = list XM.jset('shotPresets', presets)
      nameField = ''
    end
    y = y + 68
    if #list > 0 then
      W.groupBg(y, #list)
      for i, pr in ipairs(list) do
        local fired = W.row('se.pr' .. i, pr.name, y, { tap = true, first = i == 1, last = i == #list })
        if smallButton('se.del' .. i, 'Delete', LIST.x + LIST.w - 76, y + 8, 64, 30, 'danger') then
          table.remove(list, i) presets[shotId] = list XM.jset('shotPresets', presets)
        elseif fired then
          local copy = {}
          for k, v in pairs(pr.vals) do copy[k] = v end
          cfgAll[shotId] = copy XM.jset('shotCfg', cfgAll)
          toast('Angle loaded', pr.name, '🎥')
        end
        y = y + 46
      end
      y = W.sectionFooter('Tap a saved angle to load it.', y)
    end
    scrollEnd(s, y + 24)
    navBar(shot.name, { back = 'Video' })
  end
  return scr
end

-- ===========================================================================
-- BANK
-- ===========================================================================
local function sendScreen()
  local scr = { title = 'Send money' }
  local sel, amount = nil, 500
  function scr.draw()
    bgFill()
    local s = scrollBegin('bank.send', 94, BOTTOM)
    local y = 104
    local players = {}
    for _, p in ipairs(getPlayers()) do if p.hasApp then players[#players + 1] = p end end
    y = W.sectionHeader('To', y)
    if #players == 0 then
      text('Nobody with HackaPhone is on the server yet', 14, SW / 2, y + 16, T.label2, F.r, 0.5)
      y = y + 56
    else
      W.groupBg(y, #players)
      for i, p in ipairs(players) do
        local fired = W.row('bs.p' .. p.sid, p.name, y, { tap = true, first = i == 1, last = i == #players, sub = p.car })
        if sel == p.sid then text('✓', 17, SW - 36, y + 11, accent(), F.sb, 0) end
        if fired then sel = p.sid end
        y = y + 46
      end
    end
    y = y + 12
    y = W.sectionHeader('Amount', y)
    rect(LIST.x, y, LIST.x + LIST.w, y + 110, T.cell, 14)
    text(money(amount), 30, SW / 2, y + 12, T.white, F.numb, 0.5)
    local maxA = math.max(10, XM.cash())
    local v, ch = W.slider('bs.amt', math.sqrt(amount / maxA), 0, 1, LIST.x + 20, y + 60, LIST.w - 40)
    if ch then amount = math.max(10, math.floor(v * v * maxA / 10) * 10) end
    y = y + 124
    local chosen
    for _, p in ipairs(players) do if p.sid == sel then chosen = p end end
    local can = chosen and amount <= XM.cash() and amount > 0
    if W.button('bs.go', chosen and ('Send ' .. money(amount) .. ' to ' .. chosen.name) or 'Choose who to pay', 16, y, SW - 32, 48, can and 'filled' or 'gray') and can then
      if XM.sendMoney(chosen.sid, chosen.name, amount) then
        toast('Sent', money(amount) .. ' to ' .. chosen.name, '💾')
        navPop()
      end
    end
    y = W.sectionFooter('Money arrives straight away. You can only send to friends who have HackaPhone.', y + 60)
    scrollEnd(s, y + 24)
    navBar('Send money', { back = 'Bank' })
  end
  return scr
end

local function txScreen()
  local scr = { title = 'Activity' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('bank.tx', 94, BOTTOM)
    local y = 104
    local log = XM.jget('txLog', {})
    if #log == 0 then text('No activity yet. Finish a run to get paid.', 14, SW / 2, y + 20, T.label2, F.r, 0.5) y = y + 60 end
    W.groupBg(y, #log)
    for i, t in ipairs(log) do
      W.row('tx' .. i, t.why or '', y, { first = i == 1, last = i == #log, sub = ago(t.t) })
      if t.a ~= 0 then text((t.a > 0 and '+' or '') .. money(t.a), 16, SW - 32, y + 13, t.a > 0 and MONEY_GREEN or T.red, F.numb, 1) end
      y = y + 46
    end
    scrollEnd(s, y + 24)
    navBar('Activity', { back = 'Bank' })
  end
  return scr
end

function APPMOD.Bank.root()
  local scr = { title = 'Bank' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('bank', 50, BOTTOM)
    local y = largeTitle('Bank', 96, s.y)
    local ac1 = accent()
    -- card
    local bal = HESI.anim('bank.cash', XM.cash(), 8)
    local ch = 176
    rect(16, y, SW - 16, y + ch, mix(rgbm(0.05, 0.05, 0.07, 1), ac1, 0.35), 22)
    ui.drawRectFilledMultiColor(P(16, y + 22), P(SW - 16, y + ch - 22), A(ac1, 0.55), A(GOLD, 0.35), A(ac1, 0.1), A(rgbm(0, 0, 0, 1), 0.3))
    rectLine(16, y, SW - 16, y + ch, A(T.white, 0.25), 22, 1.5)
    text('HACKA BANK', 11, 36, y + 18, A(T.white, 0.85), F.b)
    text(XM.titleName():upper(), 10, SW - 36, y + 19, GOLD, F.b, 1)
    text(money(bal), 40, 36, y + 44, T.white, F.numb)
    text('AVAILABLE', 9, 36, y + 92, A(T.white, 0.6), F.b)
    local me = ac.getDriverName(0) or 'Driver'
    text(cardNumber(me), 14, 36, y + ch - 52, A(T.white, 0.9), F.num)
    text(me:upper(), 12, 36, y + ch - 30, A(T.white, 0.9), F.b)
    text('NET WORTH', 9, SW - 36, y + ch - 56, A(T.white, 0.6), F.b, 1)
    text(money(XM.netWorth()), 16, SW - 36, y + ch - 42, T.white, F.numb, 1)
    y = y + ch + 14
    -- actions
    local bw = (SW - 32 - 16) / 3
    if W.button('bk.send', 'Send', 16, y, bw, 44, 'filled') then navPush(sendScreen()) end
    if W.button('bk.act', 'Activity', 16 + bw + 8, y, bw, 44, 'gray') then navPush(txScreen()) end
    if W.button('bk.mkt', 'Market', 16 + (bw + 8) * 2, y, bw, 44, 'gray') then APPMOD.openApp('market') end
    y = y + 60
    -- run income
    local runs = XM.jget('runLog', {})
    local earned = 0
    for _, r in ipairs(runs) do earned = earned + (r.pay or 0) end
    y = tileRow(y, { { 'FROM RUNS', money(earned), MONEY_GREEN }, { 'SAVINGS', money(XM.saved()) }, { 'TOKENS', money(XM.holdValue()) } })
    -- savings
    y = W.sectionHeader('Savings account', y)
    rect(LIST.x, y, LIST.x + LIST.w, y + 130, T.cell, 14)
    if S.thick and T.border then rectLine(LIST.x, y, LIST.x + LIST.w, y + 130, T.border, 14, 1.5) end
    text(money(HESI.anim('bank.saved', XM.saved(), 8)), 26, LIST.x + 16, y + 12, T.white, F.numb)
    text(string.format('%.1f%% every minute · works while you’re offline', XM.rate() * 100), 12, LIST.x + 16, y + 48, MONEY_GREEN, F.m)
    local bw2 = (LIST.w - 32 - 16) / 3
    local by = y + 78
    if smallButton('bk.d25', 'Save 25%', LIST.x + 16, by, bw2, 36) then XM.deposit(XM.cash() * 0.25) end
    if smallButton('bk.d100', 'Save all', LIST.x + 16 + bw2 + 8, by, bw2, 36) then XM.deposit(XM.cash()) end
    if smallButton('bk.w', 'Withdraw', LIST.x + 16 + (bw2 + 8) * 2, by, bw2, 36, 'gray') then XM.withdraw(XM.saved()) end
    y = W.sectionFooter('Every run pays you: banked runs pay more, crashes still pay a little. Keep spare cash in savings and it grows.', y + 130)
    -- rich list
    y = W.sectionHeader('Richest drivers', y)
    local rich = XM.richList()
    W.groupBg(y, math.min(#rich, 8))
    for i = 1, math.min(#rich, 8) do
      local r = rich[i]
      W.row('rich' .. i, (i .. '.  ') .. r.name .. (r.me and '  (you)' or ''), y, { first = i == 1, last = i == math.min(#rich, 8) })
      text(money(r.wealth), 15, SW - 32, y + 12, i == 1 and GOLD or T.label2, F.numb, 1)
      y = y + 46
    end
    y = W.sectionFooter('Net worth counts cash, savings and tokens. Everyone with HackaPhone shows up here.', y)
    scrollEnd(s, y + 24)
    navBar('Bank', { large = true }, s.y)
  end
  return scr
end

-- ===========================================================================
-- MARKET
-- ===========================================================================
function APPMOD.Market.root()
  local scr = { title = 'Market' }
  local tab, qtyIdx = 1, 2
  local QTY = { 1, 5, 25, 100 }
  local sellSel, sellQty, sellPrice = nil, 1, 500
  function scr.draw()
    if scr.setTab then tab = scr.setTab scr.setTab = nil end
    bgFill()
    local s = scrollBegin('market', 50, BOTTOM)
    local y = largeTitle('Market', 96, s.y)
    text(money(XM.cash()), 13, SW - 16, y - 14, MONEY_GREEN, F.numb, 1)
    tab = W.segmented('mk.tab', { 'Exchange', 'Players', 'Sell', 'Shop' }, tab, 16, y, SW - 32)
    y = y + 46
    local now = os.time()
    if tab == 1 then
      qtyIdx = W.segmented('mk.qty', { 'x1', 'x5', 'x25', 'x100' }, qtyIdx, 16, y, SW - 32)
      y = y + 46
      local qty = QTY[qtyIdx]
      for _, t in ipairs(XM.TOKENS) do
        local h = 164
        local px = XM.price(t.id)
        local old = XM.priceAt(t, now - 300)
        local chg = (px - old) / old * 100
        local up = chg >= 0
        local col = up and MONEY_GREEN or T.red
        rect(16, y, SW - 16, y + h, T.cell, 18)
        if S.thick and T.border then rectLine(16, y, SW - 16, y + h, T.border, 18, 1.5) end
        glyph(t.icon:sub(2), 30, y + 14, 26, accent())
        text(t.name, 16, 64, y + 12, T.white, F.sb)
        text(t.id, 11, 64, y + 34, T.label2, F.num)
        text(string.format('$%.2f', HESI.anim('px' .. t.id, px * 100, 6) / 100), 22, SW - 30, y + 12, T.white, F.numb, 1)
        text(string.format('%s%.1f%%  5 min', up and '+' or '', chg), 12, SW - 30, y + 40, col, F.num, 1)
        local vals = {}
        for i = 0, 40 do vals[#vals + 1] = XM.priceAt(t, now - (40 - i) * 15) end
        sparkline(32, y + 66, SW - 32, y + 100, vals, col)
        local hold = XM.holdings()[t.id]
        local hn = hold and hold.n or 0
        local pl = hold and (px * hold.n - hold.cost) or 0
        text(hn > 0 and string.format('You hold %d · %s%s', hn, pl >= 0 and '+' or '', money(pl)) or 'You hold none', 12, 32, y + 108, hn > 0 and (pl >= 0 and MONEY_GREEN or T.red) or T.label2, F.m)
        local bw = (SW - 32 - 32 - 8) / 2
        local cost = math.ceil(px * qty * 1.01)
        if W.button('mk.b' .. t.id, 'Buy ' .. qty .. ' · ' .. money(cost), 32, y + 120, bw, 34, cost <= XM.cash() and 'filled' or 'gray') and cost <= XM.cash() then
          XM.buyToken(t.id, qty)
        end
        if W.button('mk.s' .. t.id, 'Sell ' .. qty, 32 + bw + 8, y + 120, bw, 34, hn >= qty and 'tinted' or 'gray', col) and hn >= qty then
          XM.sellToken(t.id, qty)
        end
        y = y + h + 12
      end
      y = W.sectionFooter('Prices move every few seconds and are the same for everybody on the server. Trades cost a 1% fee.', y)
    elseif tab == 2 then
      local rows = XM.marketRows()
      if #rows == 0 then
        glyph('GROUP', SW / 2 - 20, y + 20, 40, T.label3)
        text('No player listings right now', 15, SW / 2, y + 72, T.label2, F.sb, 0.5)
        text('Friends with HackaPhone can list power-ups and tokens here.', 12, SW / 2, y + 96, T.label3, F.r, 0.5)
        y = y + 130
      else
        rect(LIST.x, y, LIST.x + LIST.w, y + #rows * 64, T.cell, 14)
        for i, l in ipairs(rows) do
          local yy = y + (i - 1) * 64
          avatar(l.seller, LIST.x + 12, yy + 14, 36)
          textFit(l.qty .. 'x ' .. XM.itemName(l.item), 15, LIST.x + 58, yy + 10, 140, T.label, F.sb)
          textFit(l.seller .. string.format(' · %s each', money(l.price / math.max(1, l.qty))), 12, LIST.x + 58, yy + 34, 150, T.label2)
          local pend = XM.isPending(l)
          local can = XM.cash() >= l.price and not pend
          if W.button('mk.buy' .. l.sid .. l.id, pend and '…' or money(l.price), LIST.x + LIST.w - 104, yy + 14, 92, 36, can and 'filled' or 'gray') and can then
            XM.buyListing(l)
          end
          if i < #rows then line(LIST.x + 58, yy + 64, LIST.x + LIST.w, yy + 64, T.sep, 1) end
        end
        y = y + #rows * 64
      end
      y = W.sectionFooter('You pay now and get the item the moment the seller’s phone confirms. If they leave, you’re refunded.', y + 8)
    elseif tab == 3 then
      -- items you can sell
      local items = {}
      for _, p in ipairs(XM.PW) do local n = XM.have(p.id) if n > 0 then items[#items + 1] = { n = p.n, name = p.name, have = n, color = XM.rarityColor[p.rarity] } end end
      for _, t in ipairs(XM.TOKENS) do local h = XM.holdings()[t.id] if h and h.n > 0 then items[#items + 1] = { n = t.n, name = t.name, have = h.n, color = accent() } end end
      y = W.sectionHeader('Pick something to sell', y)
      if #items == 0 then
        text('You don’t own anything sellable yet', 14, SW / 2, y + 16, T.label2, F.r, 0.5)
        y = y + 56
      else
        W.groupBg(y, #items)
        for i, it in ipairs(items) do
          local fired = W.row('ms.i' .. it.n, it.name, y, { tap = true, first = i == 1, last = i == #items, value = 'x' .. it.have })
          if sellSel == it.n then rectLine(LIST.x + 2, y + 2, LIST.x + LIST.w - 2, y + 44, accent(), 10, 2) end
          if fired then sellSel = it.n sellQty = 1 sellPrice = 500 end
          y = y + 46
        end
        local cur
        for _, it in ipairs(items) do if it.n == sellSel then cur = it end end
        if cur then
          y = y + 12
          rect(LIST.x, y, LIST.x + LIST.w, y + 160, T.cell, 14)
          local v1, c1 = W.sliderRow('ms.qty', 'Quantity', sellQty, 1, math.max(1, cur.have), '%d', y, {})
          if c1 then sellQty = math.max(1, math.floor(v1 + 0.5)) end
          local v2, c2 = W.slider('ms.price', math.sqrt(sellPrice / 200000), 0, 1, LIST.x + 18, y + 90, LIST.w - 36)
          if c2 then sellPrice = math.max(10, math.floor(v2 * v2 * 200000 / 10) * 10) end
          text('Asking price', 14, LIST.x + 16, y + 84 - 24, T.label, F.r)
          text(money(sellPrice), 15, LIST.x + LIST.w - 16, y + 60, MONEY_GREEN, F.numb, 1)
          if W.button('ms.go', 'List ' .. sellQty .. 'x ' .. cur.name .. ' for ' .. money(sellPrice), LIST.x + 16, y + 118, LIST.w - 32, 34, 'filled') then
            if XM.listItem(cur.n, sellQty, sellPrice) then
              toast('Listed', sellQty .. 'x ' .. cur.name .. ' · ' .. money(sellPrice), '💾')
              sellSel = nil
            end
          end
          y = y + 172
        end
      end
      local mine = XM.jget('myList', {})
      if #mine > 0 then
        y = W.sectionHeader('Your listings', y + 6)
        W.groupBg(y, #mine)
        for i, l in ipairs(mine) do
          W.row('ml' .. l.id, l.qty .. 'x ' .. XM.itemName(l.item), y, { first = i == 1, last = i == #mine, sub = money(l.price) })
          if smallButton('mlc' .. l.id, 'Cancel', LIST.x + LIST.w - 78, y + 8, 66, 30, 'danger') then XM.unlist(l.id) end
          y = y + 46
        end
      end
      y = W.sectionFooter('Listed items are held for you until they sell or you cancel.', y + 4)
    else
      y = W.sectionHeader('Titles', y)
      local owned = XM.jget('titles', {})
      W.groupBg(y, #XM.TITLES)
      for i, tt in ipairs(XM.TITLES) do
        local isOwned = owned[tt.id] or tt.price == 0
        local sel = S.title == tt.id
        W.row('tt' .. tt.id, tt.name, y, { first = i == 1, last = i == #XM.TITLES, sub = isOwned and (sel and 'Equipped' or 'Owned') or money(tt.price) })
        local label = sel and 'Equipped' or (isOwned and 'Equip' or 'Buy')
        local can = sel or isOwned or XM.cash() >= tt.price
        if smallButton('ttb' .. tt.id, label, LIST.x + LIST.w - 90, y + 8, 78, 30, (not sel and can) and 'filled' or 'gray') and not sel and can then
          XM.buyTitle(tt)
        end
        y = y + 46
      end
      y = W.sectionFooter('Your title shows on your bank card.', y)
      y = W.sectionHeader('Permanent upgrades', y + 4)
      W.groupBg(y, #XM.PERKS, 58)
      for i, p in ipairs(XM.PERKS) do
        local lv = XM.perkLevel(p.id)
        local maxed = lv >= p.max
        local price = XM.perkPrice(p)
        local yy = y + (i - 1) * 58
        textFit(p.name .. '  ·  Lv ' .. lv .. '/' .. p.max, 15, LIST.x + 16, yy + 8, LIST.w - 130, T.label, F.sb)
        textFit(p.desc, 12, LIST.x + 16, yy + 32, LIST.w - 130, T.label2)
        local can = (not maxed) and XM.cash() >= price
        if smallButton('pk' .. p.id, maxed and 'MAX' or money(price), LIST.x + LIST.w - 102, yy + 12, 90, 34, can and 'filled' or 'gray') and can then XM.buyPerk(p) end
        if i < #XM.PERKS then line(LIST.x + 16, yy + 58, LIST.x + LIST.w, yy + 58, T.sep, 1) end
      end
      y = y + #XM.PERKS * 58
    end
    scrollEnd(s, y + 24)
    navBar('Market', { large = true }, s.y)
  end
  return scr
end

-- ===========================================================================
-- POWER-UPS
-- ===========================================================================
function APPMOD.Power.root()
  local scr = { title = 'Power-Ups' }
  local tab = 1
  local crate = nil   -- { t, result }
  function scr.draw()
    if scr.setTab then tab = scr.setTab scr.setTab = nil end
    bgFill()
    local s = scrollBegin('power', 50, BOTTOM)
    local y = largeTitle('Power-Ups', 96, s.y)
    text(money(XM.cash()), 13, SW - 16, y - 14, MONEY_GREEN, F.numb, 1)
    -- loadout
    local list = XM.equippedList()
    local slots = { { 'MULTIPLIER' }, { 'BOOST 1' }, { 'BOOST 2' } }
    local mult, fx = nil, {}
    for _, id in ipairs(list) do
      if XM.PW_BY[id].kind == 'mult' then mult = id else fx[#fx + 1] = id end
    end
    local fill = { mult, fx[1], fx[2] }
    local sw = (SW - 32 - 16) / 3
    for i = 1, 3 do
      local x = 16 + (i - 1) * (sw + 8)
      local id = fill[i]
      local p = id and XM.PW_BY[id]
      local col = p and XM.rarityColor[p.rarity] or T.label3
      rect(x, y, x + sw, y + 92, p and mix(T.cell, col, 0.18) or T.cell, 16)
      rectLine(x, y, x + sw, y + 92, p and A(col, 0.9) or T.sep, 16, p and 2 or 1)
      text(slots[i][1], 9, x + sw / 2, y + 8, T.label2, F.b, 0.5)
      if p then
        text(p.tag, p.kind == 'mult' and 28 or 18, x + sw / 2, y + 26, col, F.numb, 0.5)
        textFit(p.name, 12, x + sw / 2, y + 66, sw - 8, T.label, F.sb, 0.5)
      else
        glyph('PLUS', x + sw / 2 - 12, y + 34, 24, T.label3)
      end
    end
    y = y + 104
    if HESI.running and (#(HESI.pw.names or {}) > 0) then
      text('ACTIVE THIS RUN: ' .. table.concat(HESI.pw.names, ' · '), 11, SW / 2, y, rgbm(0.8, 0.5, 1, 1), F.b, 0.5)
      y = y + 22
    end
    tab = W.segmented('pw.tab', { 'Shop', 'My power-ups' }, tab, 16, y, SW - 32)
    y = y + 46
    if tab == 1 then
      local cw = (SW - 32 - 10) / 2
      for i, p in ipairs(XM.PW) do
        local c, r = (i - 1) % 2, math.floor((i - 1) / 2)
        local x, yy = 16 + c * (cw + 10), y + r * 186
        local col = XM.rarityColor[p.rarity]
        local owned = XM.have(p.id)
        rect(x, yy, x + cw, yy + 176, mix(T.cell, col, 0.10), 18)
        rectLine(x, yy, x + cw, yy + 176, A(col, 0.7), 18, 1.5)
        text(XM.rarityName[p.rarity], 9, x + 12, yy + 10, col, F.b)
        if owned > 0 then text('x' .. owned, 11, x + cw - 12, yy + 9, T.white, F.numb, 1) end
        text(p.tag, p.kind == 'mult' and 34 or 22, x + 12, yy + 26, col, F.numb)
        textFit(p.name, 14, x + 12, yy + 70, cw - 20, T.white, F.sb)
        textBox(p.desc, 11, x + 12, yy + 92, x + cw - 10, yy + 140, T.label2)
        local can = XM.cash() >= p.price
        if W.button('pw.buy' .. p.id, money(p.price), x + 10, yy + 138, cw - 20, 30, can and 'filled' or 'gray', col) and can then
          XM.buyPW(p)
          toast('Bought ' .. p.name, 'Find it in My power-ups', '🔥')
        end
      end
      y = y + math.ceil(#XM.PW / 2) * 186
      y = W.sectionFooter('Equip power-ups, then drive. They’re used up when your next run starts: multipliers boost every point, boosts bend the rules.', y)
    else
      local owned = {}
      for _, p in ipairs(XM.PW) do if XM.have(p.id) > 0 then owned[#owned + 1] = p end end
      if #owned == 0 then
        text('Nothing here yet', 15, SW / 2, y + 20, T.label, F.sb, 0.5)
        text('Buy power-ups in the Shop tab.', 13, SW / 2, y + 44, T.label2, F.r, 0.5)
        y = y + 90
      else
        W.groupBg(y, #owned, 56)
        for i, p in ipairs(owned) do
          local yy = y + (i - 1) * 56
          local col = XM.rarityColor[p.rarity]
          text(p.tag, p.kind == 'mult' and 20 or 13, LIST.x + 44, yy + (p.kind == 'mult' and 16 or 20), col, F.numb, 0.5)
          textFit(p.name .. '  x' .. XM.have(p.id), 15, LIST.x + 84, yy + 9, LIST.w - 190, T.label, F.sb)
          textFit(p.desc, 11, LIST.x + 84, yy + 31, LIST.w - 190, T.label2)
          if p.kind == 'crate' then
            if smallButton('pw.open', 'Open', LIST.x + LIST.w - 96, yy + 11, 84, 34, 'filled', col) and not crate then
              crate = { t = 0, result = XM.openCrate() }
            end
          else
            local eq = XM.isEquipped(p.id)
            if smallButton('pw.eq' .. p.id, eq and 'Equipped' or 'Equip', LIST.x + LIST.w - 96, yy + 11, 84, 34, eq and 'gray' or 'tinted', col) then XM.toggleEquip(p.id) end
          end
          if i < #owned then line(LIST.x + 16, yy + 56, LIST.x + LIST.w, yy + 56, T.sep, 1) end
        end
        y = y + #owned * 56
      end
      y = W.sectionFooter('You get 1 multiplier slot and 2 boost slots. Equipped items auto-reload from your stash until it runs out.', y + 6)
    end
    scrollEnd(s, y + 24)
    navBar('Power-Ups', { large = true }, s.y)
    -- crate opening: spin, flash, reveal
    if crate then
      crate.t = crate.t + IN.dt
      rect(0, 0, SW, SH, rgbm(0, 0, 0, 0.82), SCREEN.r)
      local cx, cy = SW / 2, 320
      if crate.t < 1.6 then
        local k = crate.t / 1.6
        local shake = math.sin(crate.t * 40) * 6 * k
        glyph('APPS', cx - 40 + shake, cy - 40, 80, GOLD)
        text('Opening…', 18, cx, cy + 70, T.white, F.sb, 0.5)
      else
        local p = crate.result
        local k = clamp((crate.t - 1.6) * 3, 0, 1)
        local col = p and XM.rarityColor[p.rarity] or T.white
        for g = 4, 1, -1 do rect(cx - 110 - g * 6, cy - 120 - g * 6, cx + 110 + g * 6, cy + 120 + g * 6, A(col, 0.06 * k), 30 + g * 6) end
        rect(cx - 110, cy - 120, cx + 110, cy + 120, mix(T.cell, col, 0.25), 30)
        rectLine(cx - 110, cy - 120, cx + 110, cy + 120, A(col, k), 30, 2.5)
        if p then
          D.a = D.a * k
          text(XM.rarityName[p.rarity], 12, cx, cy - 98, col, F.b, 0.5)
          text(p.tag, p.kind == 'mult' and 56 or 34, cx, cy - 66, col, F.numb, 0.5)
          text(p.name, 22, cx, cy + 16, T.white, F.sb, 0.5)
          textBox(p.desc, 13, cx - 90, cy + 52, cx + 90, cy + 110, T.label2)
          D.a = D.a / math.max(k, 0.001)
        end
        if W.button('pw.crateok', 'Nice', cx - 70, cy + 140, 140, 44, 'filled') then crate = nil end
      end
    end
  end
  return scr
end

-- ===========================================================================
-- RUNS
-- ===========================================================================
local function runDetail(r)
  local scr = { title = 'Run' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('rundetail', 94, BOTTOM)
    local y = 104
    local col = r.crashed and rgbm(1, 0.62, 0.25, 1) or MONEY_GREEN
    rect(16, y, SW - 16, y + 120, mix(T.cell, col, 0.14), 20)
    rectLine(16, y, SW - 16, y + 120, A(col, 0.6), 20, 2)
    text(r.crashed and (r.pb and 'CRASHED · NEW PERSONAL BEST' or 'CRASHED · BANKED') or (r.pb and 'NEW PERSONAL BEST' or 'BANKED'), 11, 34, y + 14, col, F.b)
    text(HESI.fmt(r.score), 44, 34, y + 32, T.white, F.numb)
    text('+' .. money(r.pay or 0), 14, SW - 34, y + 18, MONEY_GREEN, F.numb, 1)
    if (r.boost or 1) > 1 then text('x' .. r.boost .. ' boost', 12, SW - 34, y + 40, rgbm(0.8, 0.5, 1, 1), F.b, 1) end
    y = y + 134
    W.groupBg(y, 4)
    W.row('rd.car', 'Car', y, { value = r.car, first = true })
    W.row('rd.trk', 'Track', y + 46, { value = r.track ~= '' and r.track or '—' })
    W.row('rd.when', 'When', y + 92, { value = os.date('%b %d, %H:%M', r.t) })
    W.row('rd.dur', 'Run time', y + 138, { value = string.format('%d:%02d', math.floor(r.time / 60), r.time % 60), last = true })
    y = y + 200
    y = tileRow(y, { { 'TOP SPEED', r.top .. ' km/h' }, { 'AVG SPEED', (r.avg or 0) .. ' km/h' }, { 'BEST MULT', string.format('x%.1f', r.mult or 1), GOLD } })
    y = tileRow(y, { { 'NEAR MISS', tostring(r.near or 0) }, { 'CLOSE CALL', tostring(r.close or 0) }, { 'LANE SPLIT', tostring(r.split or 0) } })
    if r.fx and r.fx ~= '' then
      y = W.sectionHeader('Power-ups used', y)
      rect(LIST.x, y, LIST.x + LIST.w, y + 44, T.cell, 14)
      textFit(r.fx, 14, LIST.x + 16, y + 12, LIST.w - 32, rgbm(0.8, 0.5, 1, 1), F.sb)
      y = y + 56
    end
    scrollEnd(s, y + 20)
    navBar('Run', { back = 'Runs' })
  end
  return scr
end

function APPMOD.Runs.root()
  local scr = { title = 'Runs' }
  local tab = 1
  function scr.draw()
    if scr.setTab then tab = scr.setTab scr.setTab = nil end
    bgFill()
    local s = scrollBegin('runs', 50, BOTTOM)
    local y = largeTitle('Runs', 96, s.y)
    local runs = XM.jget('runLog', {})
    local best, top, pays = 0, 0, 0
    for _, r in ipairs(runs) do
      if r.score > best then best = r.score end
      if r.top > top then top = r.top end
      pays = pays + (r.pay or 0)
    end
    -- what you're driving right now
    local carNow = ac.getCarName(0) or '—'
    textFit('Driving ' .. carNow .. ((ac.getTrackName and ac.getTrackName() ~= '') and (' · ' .. ac.getTrackName()) or ''), 13, 16, y - 14, SW - 32, T.label2, F.m)
    y = tileRow(y + 6, { { 'RUNS', tostring(#runs) }, { 'BEST BANK', HESI.fmt(best), GOLD }, { 'TOP SPEED', top .. ' km/h' } })
    tab = W.segmented('rn.tab', { 'Runs', 'Garage' }, tab, 16, y, SW - 32)
    y = y + 46
    if #runs == 0 then
      glyph('STOPWATCH', SW / 2 - 20, y + 20, 40, T.label3)
      text('No runs logged yet', 15, SW / 2, y + 72, T.label2, F.sb, 0.5)
      text('Drive past ' .. HESI.startSpeed .. ' km/h to start one.', 12, SW / 2, y + 96, T.label3, F.r, 0.5)
      y = y + 130
    elseif tab == 1 then
      rect(LIST.x, y, LIST.x + LIST.w, y + #runs * 62, T.cell, 14)
      if S.thick and T.border then rectLine(LIST.x, y, LIST.x + LIST.w, y + #runs * 62, T.border, 14, 1.5) end
      for i, r in ipairs(runs) do
        local yy = y + (i - 1) * 62
        if visible(s, yy, 62) then
          local fired, pressed = tap('run' .. i, LIST.x, yy, LIST.x + LIST.w, yy + 62)
          if pressed then rect(LIST.x, yy, LIST.x + LIST.w, yy + 62, rgbm(1, 1, 1, 0.06), 14) end
          local col = r.crashed and rgbm(1, 0.62, 0.25, 1) or MONEY_GREEN
          rect(LIST.x + 10, yy + 14, LIST.x + 14, yy + 48, col, 2)
          textFit(r.car, 15, LIST.x + 26, yy + 9, LIST.w - 150, T.label, F.sb)
          textFit(string.format('%d km/h top · %s%s', r.top, ago(r.t), (r.boost or 1) > 1 and ('  ·  x' .. r.boost) or ''), 12, LIST.x + 26, yy + 33, LIST.w - 150, T.label2)
          text(HESI.fmt(r.score), 17, LIST.x + LIST.w - 14, yy + 11, T.white, F.numb, 1)
          text((r.crashed and 'crashed · banked' or (r.pb and 'new PB' or 'banked')), 11, LIST.x + LIST.w - 14, yy + 35, col, F.b, 1)
          if i < #runs then line(LIST.x + 26, yy + 62, LIST.x + LIST.w, yy + 62, T.sep, 1) end
          if fired then navPush(runDetail(r)) end
        end
      end
      y = y + #runs * 62
    else
      -- the garage: every car you've run, and how it did
      local cars, order = {}, {}
      for _, r in ipairs(runs) do
        local c = cars[r.car]
        if not c then c = { car = r.car, n = 0, crashes = 0, best = 0, top = 0, last = r.t, pay = 0 } cars[r.car] = c order[#order + 1] = c end
        c.n = c.n + 1
        if r.crashed then c.crashes = c.crashes + 1 end
        if r.score > c.best then c.best = r.score end
        c.top = math.max(c.top, r.top)
        c.last = math.max(c.last, r.t)
        c.pay = c.pay + (r.pay or 0)
      end
      table.sort(order, function(a, b) return a.last > b.last end)
      for _, c in ipairs(order) do
        local now = c.car == carNow
        rect(16, y, SW - 16, y + 104, now and A(accent(), 0.14) or T.cell, 18)
        if S.thick and T.border then rectLine(16, y, SW - 16, y + 104, now and accent() or T.border, 18, 1.5) end
        textFit(c.car, 16, 32, y + 12, SW - 150, T.white, F.sb)
        text(now and 'DRIVING NOW' or ('last ' .. ago(c.last)), 10, SW - 32, y + 15, now and accent() or T.label2, F.b, 1)
        local items = { { c.n .. '', 'RUNS' }, { HESI.fmt(c.best), 'BEST' }, { c.top .. '', 'TOP KM/H' }, { c.crashes .. '', 'CRASHES' } }
        local iw = (SW - 64) / 4
        for i, it in ipairs(items) do
          text(it[1], 16, 32 + (i - 1) * iw, y + 46, i == 2 and GOLD or T.white, F.numb)
          text(it[2], 9, 32 + (i - 1) * iw, y + 72, T.label2, F.b)
        end
        y = y + 116
      end
    end
    y = W.sectionFooter('Every run is logged with the car you drove, your top speed and what you earned. The latest 120 are kept on this PC.', y + 6)
    scrollEnd(s, y + 24)
    navBar('Runs', { large = true }, s.y)
  end
  return scr
end

-- ===========================================================================
-- VAULT (your own music, queue + search)
-- ===========================================================================
function APPMOD.Vault.root()
  local scr = { title = 'Vault' }
  local tab = 1
  local query = ''
  function scr.draw()
    if scr.setTab then tab = scr.setTab scr.setTab = nil end
    bgFill()
    local s = scrollBegin('vault', 50, BOTTOM)
    local y = largeTitle('Vault', 96, s.y)
    local cur = VAULT.cur
    local ac1 = accent()
    if S.vaultFolder == '' then
      rect(16, y, SW - 16, y + 230, T.cell, 20)
      glyph('MUSIC', SW / 2 - 24, y + 22, 48, ac1)
      text('Your music, in the game', 18, SW / 2, y + 84, T.white, F.sb, 0.5)
      textBox('Point the Vault at the folder where your unreleased tracks live (for example, where you save downloads from Untitled). Then search, queue and play them without leaving AC.', 13, 36, y + 112, SW - 36, y + 172, T.label2)
      if W.button('vt.pick', 'Choose music folder', 32, y + 176, SW - 64, 40, 'filled') then VAULT.pickFolder() end
      y = y + 246
      if W.button('vt.untitled0', 'Open Untitled in browser', 16, y, SW - 32, 44, 'gray') then VAULT.openUntitled() end
      y = W.sectionFooter('AC can’t show websites inside the game, so download your tracks from Untitled into a folder, then play them here.', y + 56)
    else
      -- now playing
      local cs = 190
      local cx = SW / 2
      MEDIA.cover(VAULT.media(), cx - cs / 2, y, cx + cs / 2, y + cs, 22)
      y = y + cs + 18
      if cur then
        textFit(cur.title, 20, cx, y, SW - 56, T.white, F.b, 0.5)
        textFit(cur.artist ~= '' and cur.artist or cur.folder, 14, cx, y + 28, SW - 56, T.label2, F.m, 0.5)
        y = y + 56
        local dur, pos = VAULT.duration(), VAULT.position()
        local v, ch = W.slider('vt.seek', dur > 0 and pos / dur or 0, 0, 1, 36, y, SW - 72, T.white)
        if ch then VAULT.seek(v) end
        text(MEDIA.fmtTime(pos), 11, 36, y + 28, T.label2, F.num)
        text(MEDIA.fmtTime(dur), 11, SW - 36, y + 28, T.label2, F.num, 1)
        y = y + 54
      else
        text('Nothing playing', 18, cx, y, T.white, F.sb, 0.5)
        text('Pick a track from the library', 13, cx, y + 26, T.label2, F.r, 0.5)
        y = y + 64
      end
      if MEDIA.button('vt.prev', 'PREVIOUS', cx - 84, y + 22, 28, T.white) then VAULT.prev() end
      if MEDIA.button('vt.pp', VAULT.playing() and 'PAUSE' or 'PLAY', cx, y + 22, 40, T.white) then VAULT.toggle() end
      if MEDIA.button('vt.next', 'NEXT', cx + 84, y + 22, 28, T.white) then VAULT.next() end
      y = y + 66
      local bw = (SW - 32 - 16) / 3
      if smallButton('vt.shuf', S.vaultShuffle and 'Shuffle on' or 'Shuffle', 16, y, bw, 32, S.vaultShuffle and 'filled' or 'gray') then S.vaultShuffle = not S.vaultShuffle end
      if smallButton('vt.rep', ({ 'Repeat off', 'Repeat all', 'Repeat one' })[S.vaultRepeat], 16 + bw + 8, y, bw, 32, S.vaultRepeat > 1 and 'filled' or 'gray') then S.vaultRepeat = S.vaultRepeat % 3 + 1 end
      if smallButton('vt.stop', 'Stop', 16 + (bw + 8) * 2, y, bw, 32, 'danger') then VAULT.stop() end
      y = y + 48
      tab = W.segmented('vt.tab', { 'Up next (' .. #VAULT.queue .. ')', 'Library', 'Settings' }, tab, 16, y, SW - 32)
      y = y + 46
      if tab == 1 then
        if #VAULT.queue == 0 then
          text('Your queue is empty', 14, SW / 2, y + 14, T.label2, F.sb, 0.5)
          text('Add songs from the Library tab with +Queue or Next.', 12, SW / 2, y + 38, T.label3, F.r, 0.5)
          y = y + 76
        else
          rect(LIST.x, y, LIST.x + LIST.w, y + #VAULT.queue * 54, T.cell, 14)
          local removeAt, upAt
          for i, t in ipairs(VAULT.queue) do
            local yy = y + (i - 1) * 54
            text(tostring(i), 14, LIST.x + 20, yy + 17, T.label2, F.numb, 0.5)
            textFit(t.title, 15, LIST.x + 40, yy + 8, LIST.w - 130, T.label, F.sb)
            textFit(t.artist ~= '' and t.artist or t.folder, 12, LIST.x + 40, yy + 30, LIST.w - 130, T.label2)
            if i > 1 and smallButton('vq.up' .. i, 'Up', LIST.x + LIST.w - 100, yy + 10, 40, 32, 'gray') then upAt = i end
            if smallButton('vq.rm' .. i, 'X', LIST.x + LIST.w - 52, yy + 10, 40, 32, 'danger') then removeAt = i end
            if i < #VAULT.queue then line(LIST.x + 40, yy + 54, LIST.x + LIST.w, yy + 54, T.sep, 1) end
          end
          if upAt then VAULT.moveUp(upAt) end
          if removeAt then VAULT.dequeue(removeAt) end
          y = y + #VAULT.queue * 54 + 10
          if W.button('vq.clear', 'Clear queue', 16, y, SW - 32, 38, 'gray') then VAULT.clearQueue() end
          y = y + 50
        end
      elseif tab == 2 then
        query = W.field('vt.q', query, 'Search your music', 16, y, SW - 32, 38, { icon = '🔍' })
        y = y + 50
        local list = VAULT.search(query)
        if #list == 0 then
          text(#VAULT.tracks == 0 and 'No audio files found in that folder' or 'No matches', 14, SW / 2, y + 16, T.label2, F.r, 0.5)
          y = y + 60
        else
          local shown = math.min(#list, 300)
          rect(LIST.x, y, LIST.x + LIST.w, y + shown * 58, T.cell, 14)
          for i = 1, shown do
            local t = list[i]
            local yy = y + (i - 1) * 58
            if visible(s, yy, 58) then
              local fired, pressed = tap('vl' .. i, LIST.x, yy, LIST.x + LIST.w - 116, yy + 58)
              if pressed then rect(LIST.x, yy, LIST.x + LIST.w, yy + 58, rgbm(1, 1, 1, 0.06), 14) end
              local playing = VAULT.cur == t
              textFit(t.title, 15, LIST.x + 16, yy + 9, LIST.w - 140, playing and ac1 or T.label, F.sb)
              textFit(t.artist ~= '' and t.artist or t.folder, 12, LIST.x + 16, yy + 33, LIST.w - 140, T.label2)
              if smallButton('vl.n' .. i, 'Next', LIST.x + LIST.w - 112, yy + 13, 48, 32, 'tinted') then VAULT.playNext(t) toast('Playing next', t.title, '♫') end
              if smallButton('vl.q' .. i, '+', LIST.x + LIST.w - 58, yy + 13, 46, 32, 'gray') then VAULT.enqueue(t) toast('Added to queue', t.title, '♫') end
              if i < shown then line(LIST.x + 16, yy + 58, LIST.x + LIST.w, yy + 58, T.sep, 1) end
              if fired then VAULT.play(t) end
            end
          end
          y = y + shown * 58 + 6
          if #list > shown then y = W.sectionFooter('Showing the first ' .. shown .. ' of ' .. #list .. '. Search to narrow it down.', y) end
        end
      else
        W.groupBg(y, 3)
        W.row('vs.f', 'Music folder', y, { first = true, value = (S.vaultFolder:match('[^/\\]+$') or S.vaultFolder) })
        if W.row('vs.change', 'Change folder', y + 46, { chevron = true }) then VAULT.pickFolder() end
        if W.row('vs.rescan', 'Rescan (' .. #VAULT.tracks .. ' tracks)', y + 92, { chevron = true, last = true }) then VAULT.scan() toast('Vault', #VAULT.tracks .. ' tracks', '♫') end
        y = y + 150
        y = W.sectionHeader('Untitled', y)
        rect(LIST.x, y, LIST.x + LIST.w, y + 56, T.cell, 14)
        S.untitledUrl = W.field('vs.url', S.untitledUrl, 'https://untitled.stream', LIST.x + 10, y + 10, LIST.w - 20, 36)
        y = y + 68
        if W.button('vs.open', 'Open Untitled in browser', 16, y, SW - 32, 44, 'gray') then VAULT.openUntitled() end
        y = W.sectionFooter('Download your unreleased tracks into your Vault folder and they show up here. Cover art: put cover.jpg in the folder, or name an image like the song.', y + 56)
        y = W.sectionHeader('Volume', y)
        rect(LIST.x, y, LIST.x + LIST.w, y + 56, T.cell, 14)
        local v, ch = W.slider('vs.vol', S.vaultVol, 0, 1, LIST.x + 20, y + 14, LIST.w - 40)
        if ch then VAULT.setVolume(v) end
        y = y + 70
      end
    end
    scrollEnd(s, y + 24)
    navBar('Vault', { large = true }, s.y)
  end
  return scr
end


-- ===========================================================================
-- WELCOME SCREEN (greets you when you join; fully editable)
-- ===========================================================================
local WEL = { t0 = -100, active = false }
XM.welcome = WEL

local function resolveText(str)
  local me = ac.getDriverName(0) or 'driver'
  local sim = ac.getSim()
  local server = sim.isOnlineRace and (ac.getServerName and ac.getServerName() or 'the server') or 'the track'
  local players = #getPlayers() + 1
  local r = str
  r = r:gsub('{name}', function() return me end)
  r = r:gsub('{server}', function() return server end)
  r = r:gsub('{car}', function() return ac.getCarName(0) or 'your car' end)
  r = r:gsub('{track}', function() return (ac.getTrackName and ac.getTrackName()) or 'the track' end)
  r = r:gsub('{players}', function() return tostring(players) end)
  return r
end
WEL.resolve = resolveText

function WEL.trigger(force)
  if not S.welcomeOn and not force then return end
  WEL.t0, WEL.active = clock(), true
  if (S.welcomeStyle == 2 or S.welcomeStyle == 3) and not ac.isWindowOpen('main') then ac.setWindowOpen('main', true) end
end
function WEL.age() return clock() - WEL.t0 end
function WEL.alive() return WEL.active and WEL.age() < S.welcomeSecs + 1 end

local function statsLine()
  local parts = {}
  if S.hesiPB > 0 then parts[#parts + 1] = 'PB ' .. HESI.fmt(S.hesiPB) end
  parts[#parts + 1] = money(XM.cash())
  parts[#parts + 1] = (#getPlayers() + 1) .. ' online'
  return table.concat(parts, '   ·   ')
end

-- slide-down card on the action bar window
function WEL.drawBanner(cx)
  if not WEL.alive() or (S.welcomeStyle ~= 1 and S.welcomeStyle ~= 3) then return end
  local t = WEL.age()
  local k = clamp(t / 0.5, 0, 1)
  k = 1 - (1 - k) ^ 3
  local out = clamp((t - S.welcomeSecs) / 0.6, 0, 1)
  local y = -110 + 118 * k - 120 * out * out
  local w, h = 440, S.welcomeStats and 92 or 72
  local x1, x2 = cx - w / 2, cx + w / 2
  local ac1 = accent()
  for g = 3, 1, -1 do rect(x1 - g * 4, y - g * 4, x2 + g * 4, y + h + g * 4, A(ac1, 0.07 / g), 22 + g * 4) end
  rect(x1, y, x2, y + h, rgbm(0.03, 0.03, 0.05, 0.9), 22)
  ui.drawRectFilledMultiColor(P(x1 + 22, y), P(x2 - 22, y + 2), A(ac1, 0), A(ac1, 1), A(ac1, 1), A(ac1, 0))
  rectLine(x1, y, x2, y + h, A(ac1, 0.6), 22, 1.5)
  avatar(ac.getDriverName(0) or 'You', x1 + 16, y + (h - 48) / 2, 48)
  textFit(resolveText(S.welcomeTitle), 20, x1 + 78, y + 12, w - 100, T.white, F.b)
  textFit(resolveText(S.welcomeTag), 13, x1 + 78, y + 40, w - 100, A(T.white, 0.7), F.m)
  if S.welcomeStats then text(statsLine(), 11, x1 + 78, y + 66, ac1, F.num) end
end

-- full-screen takeover on the phone
function WEL.drawPhone()
  if not WEL.alive() or (S.welcomeStyle ~= 2 and S.welcomeStyle ~= 3) then return end
  local t = WEL.age()
  local a = clamp(t / 0.45, 0, 1) * (1 - clamp((t - S.welcomeSecs) / 0.6, 0, 1))
  local oldA = D.a
  D.a = oldA * a
  local ac1 = accent()
  rect(0, 0, SW, SH, rgbm(0.02, 0.02, 0.04, 1), SCREEN.r)
  ui.drawRectFilledMultiColor(P(0, 0), P(SW, SH * 0.75), A(ac1, 0.55), A(ac1, 0.55), A(ac1, 0), A(ac1, 0))
  local me = ac.getDriverName(0) or 'You'
  local pulse = 0.5 + 0.5 * math.sin(t * 3)
  for g = 3, 1, -1 do circle(SW / 2, 210, 54 + g * 8 + pulse * 4, A(ac1, 0.10 / g)) end
  avatar(me, SW / 2 - 50, 160, 100)
  textBox(resolveText(S.welcomeTitle), 30, 30, 290, SW - 30, 380, T.white, F.b)
  textBox(resolveText(S.welcomeTag), 15, 30, 352, SW - 30, 410, A(T.white, 0.7), F.m)
  if S.welcomeStats then
    local items = { { 'PERSONAL BEST', HESI.fmt(S.hesiPB) }, { 'WALLET', money(XM.cash()) }, { 'ONLINE', tostring(#getPlayers() + 1) } }
    local tw = (SW - 32 - 16) / 3
    for i, it in ipairs(items) do
      local x = 16 + (i - 1) * (tw + 8)
      rect(x, 470, x + tw, 540, A(T.white, 0.08), 16)
      text(it[1], 9, x + tw / 2, 484, A(T.white, 0.6), F.b, 0.5)
      textFit(it[2], 17, x + tw / 2, 504, tw - 12, T.white, F.numb, 0.5)
    end
  end
  text('Tap to continue', 13, SW / 2, 650, A(T.white, 0.4 + 0.4 * pulse), F.m, 0.5)
  if tap('welcome.dismiss', 0, 0, SW, SH) then WEL.active = false end
  D.a = oldA
end

local function welcomeEditor()
  local scr = { title = 'Welcome Screen' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('welcome', 94, BOTTOM)
    local y = 104
    W.groupBg(y, 2)
    S.welcomeOn = W.toggleRow('wl.on', 'Greet me when I join', S.welcomeOn, y, { first = true, icon = '👋', iconBg = rgbm(1, 0.6, 0.2, 1) })
    S.greetJoin = W.toggleRow('wl.greet', 'Welcome new players', S.greetJoin, y + 46, { last = true, icon = '👥', iconBg = rgbm(0.3, 0.7, 1, 1) })
    y = W.sectionFooter('New players get a welcome in the group chat from whoever has been on the server longest, so it isn’t spammed.', y + 92)
    y = W.sectionHeader('Style', y)
    S.welcomeStyle = W.segmented('wl.style', { 'Banner', 'Phone', 'Both' }, S.welcomeStyle, 16, y, SW - 32)
    y = y + 50
    y = W.sectionHeader('Your message', y)
    rect(LIST.x, y, LIST.x + LIST.w, y + 112, T.cell, 14)
    S.welcomeTitle = W.field('wl.title', S.welcomeTitle, 'Title', LIST.x + 10, y + 10, LIST.w - 20, 40)
    S.welcomeTag = W.field('wl.tag', S.welcomeTag, 'Tagline', LIST.x + 10, y + 60, LIST.w - 20, 40)
    y = y + 124
    y = W.sectionFooter('You can use {name}, {server}, {car}, {track} and {players} and they fill in automatically.', y)
    W.groupBg(y, 1)
    S.welcomeStats = W.toggleRow('wl.stats', 'Show my stats', S.welcomeStats, y, { first = true, last = true })
    y = y + 56
    rect(LIST.x, y, LIST.x + LIST.w, y + 74, T.cell, 14)
    local v, ch = W.sliderRow('wl.secs', 'Stays on screen', S.welcomeSecs, 2, 12, '%d s', y, { last = true })
    if ch then S.welcomeSecs = math.floor(v + 0.5) end
    y = y + 90
    y = W.sectionHeader('Preview', y)
    local px = LIST.x
    rect(px, y, px + LIST.w, y + 120, T.cell, 18)
    avatar(ac.getDriverName(0) or 'You', px + 16, y + 20, 56)
    textFit(resolveText(S.welcomeTitle), 20, px + 88, y + 24, LIST.w - 104, T.white, F.b)
    textFit(resolveText(S.welcomeTag), 13, px + 88, y + 54, LIST.w - 104, T.label2, F.m)
    if S.welcomeStats then textFit(statsLine(), 11, px + 88, y + 82, LIST.w - 104, accent(), F.num) end
    y = y + 134
    if W.button('wl.play', 'Play it now', 16, y, SW - 32, 46, 'filled') then WEL.trigger(true) end
    y = y + 60
    scrollEnd(s, y + 20)
    navBar('Welcome Screen', { back = 'Personalize' })
  end
  return scr
end
APPMOD.Themes.welcome = welcomeEditor

end
-- ===========================================================================
-- RACE app: challenge friends, solo timing, records
-- ===========================================================================

do
local R = XM.race
local money = XM.money
local GOLD = rgbm(1, 0.8, 0.25, 1)
local RED = rgbm(1, 0.35, 0.3, 1)

local function tile(x, y, w, h, label, value, color)
  rect(x, y, x + w, y + h, T.cell, 14)
  if S.thick and T.border then rectLine(x, y, x + w, y + h, T.border, 14, 1.5) end
  text(label, 9, x + 10, y + 10, T.label2, F.b)
  textFit(value, 17, x + 10, y + 28, w - 20, color or T.white, F.numb)
end
local function tileRow(y, items)
  local n, gap = #items, 10
  local w = (SW - 32 - gap * (n - 1)) / n
  for i, it in ipairs(items) do tile(16 + (i - 1) * (w + gap), y, w, 60, it[1], it[2], it[3]) end
  return y + 72
end

local function fmtT(t) return string.format('%.3f s', t or 0) end

local function ago(t)
  local d = os.time() - t
  if d < 60 then return 'just now' end
  if d < 3600 then return math.floor(d / 60) .. ' min ago' end
  if d < 86400 then return math.floor(d / 3600) .. ' h ago' end
  return math.floor(d / 86400) .. ' d ago'
end

-- format picker: presets as chips, plus a custom distance or pull
local UI = { preset = 2, custom = { kind = 1, x = 800, y = 0 }, wager = 0 }
local function currentSpec()
  if UI.preset == 0 then
    local c = UI.custom
    return { kind = c.kind, x = math.floor(c.x), y = math.floor(c.y) }
  end
  local p = R.PRESETS[UI.preset]
  return { kind = p.kind, x = p.x, y = p.y }
end

local function pickSpec(idp, y)
  y = W.sectionHeader('Format', y)
  local cols, gap = 3, 8
  local cw = (SW - 32 - gap * (cols - 1)) / cols
  local items = {}
  for i, p in ipairs(R.PRESETS) do items[#items + 1] = { i, p.name } end
  items[#items + 1] = { 0, 'Custom' }
  for n, it in ipairs(items) do
    local c, r = (n - 1) % cols, math.floor((n - 1) / cols)
    local x, yy = 16 + c * (cw + gap), y + r * 42
    local sel = UI.preset == it[1]
    local fired, pressed = tap(idp .. 'f' .. n, x, yy, x + cw, yy + 36)
    rect(x, yy, x + cw, yy + 36, sel and A(accent(), 0.25) or (pressed and T.cellHi or T.cell), 12)
    if sel then rectLine(x, yy, x + cw, yy + 36, accent(), 12, 2) end
    text(it[2], 13, x + cw / 2, yy + 9, sel and T.white or T.label, sel and F.sb or F.m, 0.5)
    if fired then UI.preset = it[1] end
  end
  y = y + math.ceil(#items / cols) * 42 + 4
  if UI.preset == 0 then
    local c = UI.custom
    rect(LIST.x, y, LIST.x + LIST.w, y + (c.kind == 1 and 124 or 190), T.cell, 14)
    c.kind = W.segmented(idp .. 'ck', { 'Distance', 'Speed pull' }, c.kind, LIST.x + 12, y + 12, LIST.w - 24)
    if c.kind == 1 then
      local v, ch = W.sliderRow(idp .. 'cd', 'Distance', c.x, 100, 5000, '%d m', y + 48, { last = true })
      if ch then c.x = math.floor(v / 50 + 0.5) * 50 end
      y = y + 134
    else
      local v1, ch1 = W.sliderRow(idp .. 'cf', 'From', c.y, 0, 280, '%d km/h', y + 48, {})
      if ch1 then c.y = math.min(math.floor(v1 / 10 + 0.5) * 10, c.x - 20) end
      local v2, ch2 = W.sliderRow(idp .. 'ct', 'To', c.x, 40, 340, '%d km/h', y + 112, { last = true })
      if ch2 then c.x = math.max(math.floor(v2 / 10 + 0.5) * 10, c.y + 20) end
      y = y + 200
    end
  end
  return currentSpec(), y
end

-- timing sheet for a finished run
local function sheet(res, y, other)
  local items = {
    { 'TOTAL', fmtT(res.t), GOLD }, { 'TRAP', math.floor(res.trap) .. ' km/h' }, { 'TOP', math.floor(res.top) .. ' km/h' },
  }
  y = tileRow(y, items)
  local items2 = { { 'AVERAGE', math.floor(res.avg) .. ' km/h' }, { 'REACTION', res.spec.kind == 1 and fmtT(res.react) or '—' }, { 'PENALTY', res.falseStart and '+1.000 s' or 'none', res.falseStart and RED or nil } }
  y = tileRow(y, items2)
  local names = {}
  for k, sp in pairs(res.splits or {}) do names[#names + 1] = { k, sp } end
  table.sort(names, function(a, b) return a[2].t < b[2].t end)
  if #names > 0 then
    y = W.sectionHeader('Splits', y)
    W.groupBg(y, #names)
    for i, n in ipairs(names) do
      W.row('sp' .. n[1], n[1], y, { first = i == 1, last = i == #names, value = fmtT(n[2].t) })
      y = y + 46
    end
    y = y + 6
  end
  return y
end


local BOARD_KIND = { 'wins', 't60', 't200' }
local BOARD_TAB = 1
local BOARD_MEDAL = { rgbm(1, 0.82, 0.25, 1), rgbm(0.80, 0.82, 0.86, 1), rgbm(0.85, 0.55, 0.30, 1) }
function APPMOD.Race.board(y)
  BOARD_TAB = W.segmented('rc.bt', { 'Most wins', '0-60 mph', '0-200 km/h' }, BOARD_TAB, 16, y, SW - 32)
  y = y + 52
  local kind = BOARD_KIND[BOARD_TAB]
  local rows = R.boardRows(kind)
  local function val(r) return kind == 'wins' and (r.value .. (r.value == 1 and ' win' or ' wins')) or string.format('%.2f s', r.value) end
  if #rows == 0 then
    glyph('FLAG', SW / 2 - 18, y + 16, 36, T.label3)
    text(kind == 'wins' and 'No race wins yet' or 'No times yet', 15, SW / 2, y + 64, T.label, F.sb, 0.5)
    textBox(kind == 'wins' and 'Win a race against a friend to get on the board.' or 'Run a solo pull from the Solo tab to set a time.', 12, 40, y + 90, SW - 40, y + 130, T.label2)
    y = y + 140
  else
    local pw = (SW - 32 - 16) / 3
    local order, heights = { 2, 1, 3 }, { [1] = 100, [2] = 80, [3] = 66 }
    for k, rank in ipairs(order) do
      local r = rows[rank]
      if r then
        local x = 16 + (k - 1) * (pw + 8)
        local h = heights[rank]
        local top = y + 104 - h
        local col = BOARD_MEDAL[rank]
        avatar(r.name, x + pw / 2 - 22, top - 52, 44)
        textFit(r.name .. (r.me and ' (you)' or ''), 12, x + pw / 2, top - 4, pw - 6, T.label, F.sb, 0.5)
        rect(x, top + 14, x + pw, y + 118, mix(T.cell, col, 0.22), 12, ui.CornerFlags.Top)
        rect(x, top + 14, x + pw, top + 17, col, 2)
        text(tostring(rank), 26, x + pw / 2, top + 22, col, F.numb, 0.5)
        textFit(val(r), 12, x + pw / 2, top + 56, pw - 8, T.white, F.numb, 0.5)
      end
    end
    y = y + 134
    local n = math.min(#rows, 12)
    if n > 3 then
      rect(LIST.x, y, LIST.x + LIST.w, y + (n - 3) * 50, T.cell, 14)
      for i = 4, n do
        local r = rows[i]
        local ry = y + (i - 4) * 50
        if r.me then rect(LIST.x, ry, LIST.x + LIST.w, ry + 50, A(accent(), 0.14), 14) end
        text(tostring(i), 16, LIST.x + 22, ry + 15, T.label2, F.numb, 0.5)
        avatar(r.name, LIST.x + 40, ry + 7, 36)
        textFit(r.name .. (r.me and '  (you)' or ''), 15, LIST.x + 86, ry + 8, LIST.w - 190, T.label, F.sb)
        if r.car and r.car ~= '' then textFit(r.car, 11, LIST.x + 86, ry + 28, LIST.w - 190, T.label2) end
        text(val(r), 15, LIST.x + LIST.w - 14, ry + 16, T.white, F.numb, 1)
      end
      y = y + (n - 3) * 50
    end
  end
  if kind ~= 'wins' then
    local spec = kind == 't60' and R.PRESETS[6] or R.PRESETS[8]
    local armed = R.run and R.run.mode == 'solo'
    if W.button('rc.bd', armed and 'Armed, go!' or ('Run ' .. R.specName(spec) .. ' now'), 16, y + 14, SW - 32, 46, armed and 'gray' or 'filled') and not armed then R.soloArm(spec) end
    y = y + 70
  end
  y = W.sectionFooter('Times and wins from every driver running HackaPhone. The board remembers drivers between sessions.', y)
  return y
end

function APPMOD.Race.root()
  local scr = { title = 'Race' }
  local tab = 1
  function scr.draw()
    if scr.setTab then tab = scr.setTab scr.setTab = nil end
    local pend = R.pending
    bgFill()
    local s = scrollBegin('race', 50, BOTTOM)
    local y = largeTitle('Race', 96, s.y)
    local ac1 = accent()
    text(string.format('%dW  %dL  ·  streak %d', S.raceWins, S.raceLosses, S.raceStreak), 13, SW - 16, y - 14, GOLD, F.numb, 1)
    if R.cur and (R.state == 'invited_in' or R.state == 'invited_out' or R.state == 'staging') then tab = 1 end   -- an open race is always on the first tab
    tab = W.segmented('rc.tab', { 'Race', 'Solo', 'Records', 'Board' }, tab, 16, y, SW - 32)
    y = y + 46

    if tab == 4 then
      y = APPMOD.Race.board(y)
      scrollEnd(s, y + 20)
      navBar('Race', { large = true }, s.y)
      return
    end
    local c = R.cur
    if tab == 1 then
      if R.state == 'idle' then
        local spec
        spec, y = pickSpec('rc.', y)
        y = W.sectionHeader('Wager', y + 6)
        rect(LIST.x, y, LIST.x + LIST.w, y + 74, T.cell, 14)
        local maxW = math.max(100, math.min(XM.cash(), 100000))
        local v, ch = W.sliderRow('rc.wager', 'Winner takes', UI.wager, 0, maxW, '$%d', y, { last = true })
        if ch then UI.wager = v < 50 and 0 or math.floor(v / 50 + 0.5) * 50 end
        UI.wager = math.min(UI.wager, XM.cash())
        y = y + 86
        y = W.sectionHeader('Challenge a driver', y)
        local players = {}
        for _, p in ipairs(getPlayers()) do if p.hasApp then players[#players + 1] = p end end
        if #players == 0 then
          glyph('GROUP', SW / 2 - 18, y + 14, 36, T.label3)
          text('Nobody with HackaPhone is online', 14, SW / 2, y + 60, T.label2, F.sb, 0.5)
          text('Friends need the phone app to take a challenge.', 12, SW / 2, y + 82, T.label3, F.r, 0.5)
          y = y + 112
        else
          W.groupBg(y, #players, 58)
          for i, p in ipairs(players) do
            local yy = y + (i - 1) * 58
            avatar(p.name, LIST.x + 12, yy + 11, 36)
            textFit(p.name, 15, LIST.x + 58, yy + 9, LIST.w - 170, T.label, F.sb)
            textFit(p.car, 12, LIST.x + 58, yy + 32, LIST.w - 170, T.label2)
            if pend and pend.sid == p.sid then rect(LIST.x + 2, yy + 2, LIST.x + LIST.w - 2, yy + 56, A(accent(), 0.12), 12) end
            if W.button('rc.ch' .. p.sid, 'Challenge', LIST.x + LIST.w - 100, yy + 12, 88, 34, 'filled') then
              if R.challenge(p, spec, UI.wager) then toast('Challenge sent', p.name .. ' · ' .. R.specName(spec), '🏁') end
            end
            if i < #players then line(LIST.x + 58, yy + 58, LIST.x + LIST.w, yy + 58, T.sep, 1) end
          end
          y = y + #players * 58
        end
        y = W.sectionFooter('They get a notification and a message. Distance races time from the green light and pulls time from the start speed. Wagers are paid out by the winner’s phone.', y + 6)
      elseif R.state == 'invited_out' or R.state == 'invited_in' or R.state == 'staging' then
        local incoming = R.state == 'invited_in'
        rect(16, y, SW - 16, y + 196, mix(T.cell, ac1, 0.12), 22)
        rectLine(16, y, SW - 16, y + 196, A(ac1, 0.7), 22, 2)
        avatar(c.oppName, SW / 2 - 28, y + 16, 56)
        text(c.oppName, 20, SW / 2, y + 80, T.white, F.b, 0.5)
        text(R.specName(c.spec), 28, SW / 2, y + 108, ac1, F.numb, 0.5)
        text(c.wager > 0 and ('for ' .. money(c.wager) .. ' · winner takes ' .. money(c.wager * 2)) or 'no wager, bragging rights', 13, SW / 2, y + 148, T.label2, F.m, 0.5)
        local status = incoming and 'wants to race you' or (R.state == 'invited_out' and 'Waiting for them to accept…' or (c.role == 'host' and 'Line up, then start the countdown' or ('Waiting for ' .. c.oppName .. ' to start')))
        text(status, 13, SW / 2, y + 168, T.label, F.sb, 0.5)
        y = y + 212
        if incoming then
          local bw = (SW - 40) / 2
          if W.button('rc.acc', 'Accept', 16, y, bw, 48, 'filled') then R.accept() end
          if W.button('rc.dec', 'Decline', 24 + bw, y, bw, 48, 'danger') then R.decline() end
        elseif R.state == 'staging' and c.role == 'host' then
          if W.button('rc.go', 'Start countdown', 16, y, SW - 32, 52, 'filled') then R.start() end
          y = y + 62
          if W.button('rc.cx', 'Cancel race', 16, y, SW - 32, 40, 'gray') then R.cancel() end
        else
          if W.button('rc.cx', 'Cancel', 16, y, SW - 32, 44, 'gray') then R.cancel() end
        end
        y = y + 60
        y = W.sectionFooter('Pull up side by side. The phone closes itself when the countdown starts and the race HUD takes over the top of your screen. Quitting mid-race forfeits it.', y)
      elseif R.state == 'countdown' or R.state == 'racing' or (R.state == 'finished' and not (c.outcome)) then
        local run = R.run
        rect(16, y, SW - 16, y + 150, T.cell, 22)
        text(R.state == 'finished' and 'You’re done. Waiting for ' .. c.oppName .. '…' or ('Racing ' .. c.oppName), 15, SW / 2, y + 22, T.label, F.sb, 0.5)
        if c.my then text(fmtT(c.my.t), 40, SW / 2, y + 56, GOLD, F.numb, 0.5)
        elseif run then text(string.format('%.3f', run.t), 40, SW / 2, y + 56, T.white, F.numb, 0.5) end
        text(R.specName(c.spec) .. (c.wager > 0 and ('  ·  ' .. money(c.wager) .. ' on it') or ''), 13, SW / 2, y + 116, T.label2, F.m, 0.5)
        y = y + 166
        if R.state ~= 'finished' then
          if W.button('rc.abort', 'Forfeit', 16, y, SW - 32, 44, 'danger') then R.abort() end
          y = y + 56
        end
      else
        -- finished with a result
        local o, my, op = c.outcome, c.my, c.opp.fin
        local col = o.win == true and rgbm(0.3, 1, 0.5, 1) or (o.win == false and RED or ac1)
        rect(16, y, SW - 16, y + 170, mix(T.cell, col, 0.16), 22)
        rectLine(16, y, SW - 16, y + 170, A(col, 0.8), 22, 2)
        text(o.win == true and 'YOU WIN' or (o.win == false and 'YOU LOSE' or 'TIE'), 34, SW / 2, y + 16, col, F.numb, 0.5)
        if o.forfeit then text(o.win and (c.oppName .. ' didn’t finish') or 'You forfeited', 12, SW / 2, y + 62, T.label2, F.m, 0.5) end
        local half = (SW - 32) / 2
        text('YOU', 10, 16 + half / 2, y + 86, T.label2, F.b, 0.5)
        text(o.mine and fmtT(o.mine) or 'DNF', 22, 16 + half / 2, y + 104, T.white, F.numb, 0.5)
        text(c.oppName:upper(), 10, 16 + half * 1.5, y + 86, T.label2, F.b, 0.5)
        text(o.theirs and fmtT(o.theirs) or 'DNF', 22, 16 + half * 1.5, y + 104, T.white, F.numb, 0.5)
        if o.payout and o.payout > 0 then text((o.win and '+' or '') .. money(o.payout), 14, SW / 2, y + 142, rgbm(0.35, 0.95, 0.55, 1), F.numb, 0.5)
        elseif c.wager > 0 and o.win == false then text('-' .. money(c.wager), 14, SW / 2, y + 142, RED, F.numb, 0.5) end
        y = y + 186
        local bw = (SW - 40) / 2
        if W.button('rc.rematch', 'Rematch', 16, y, bw, 46, 'filled') then
          local spec, wager, who = c.spec, c.wager, { sid = c.oppSid, name = c.oppName }
          R.dismiss() R.challenge(who, spec, wager)
        end
        if W.button('rc.done', 'Done', 24 + bw, y, bw, 46, 'gray') then R.dismiss() end
        y = y + 62
        if my and my.splits then y = sheet(my, y) end
      end
    elseif tab == 2 then
      local run = R.run
      local armed = run and run.mode == 'solo' and run.phase ~= 'done'
      local spec
      if not armed then spec, y = pickSpec('so.', y) end
      if armed then
        rect(16, y, SW - 16, y + 150, mix(T.cell, ac1, 0.12), 22)
        rectLine(16, y, SW - 16, y + 150, A(ac1, 0.7), 22, 2)
        text(run.phase == 'armed' and 'READY' or string.format('%.3f', run.t), 44, SW / 2, y + 22, T.white, F.numb, 0.5)
        text(R.specName(run.spec) .. (run.phase == 'armed' and '  ·  go when you’re ready' or ('  ·  ' .. math.floor(run.v) .. ' km/h')), 14, SW / 2, y + 90, ac1, F.sb, 0.5)
        text('Close the phone and drive. The timer shows at the top of your screen.', 12, SW / 2, y + 116, T.label2, F.r, 0.5)
        y = y + 164
        if W.button('so.cancel', 'Cancel', 16, y, SW - 32, 44, 'gray') then R.abort() end
        y = y + 56
      else
        y = y + 8
        if W.button('so.arm', 'Arm ' .. R.specName(spec) .. ' run', 16, y, SW - 32, 52, 'filled') then
          R.soloArm(spec)
        end
        y = y + 64
      end
      local res = R.soloResult
      if res and not armed then
        y = W.sectionHeader('Last run', y + 4)
        rect(16, y, SW - 16, y + 96, mix(T.cell, res.record and GOLD or ac1, 0.12), 20)
        text(res.record and 'NEW PERSONAL RECORD' or res.name:upper(), 10, 34, y + 14, res.record and GOLD or ac1, F.b)
        text(fmtT(res.t), 38, 34, y + 32, T.white, F.numb)
        textFit(res.car, 12, SW - 34, y + 20, 140, T.label2, F.m, 1)
        y = y + 110
        y = sheet(res, y)
      end
      y = W.sectionFooter('Solo runs and races are saved to Records with the car you used.', y)
    else
      y = tileRow(y, { { 'WINS', tostring(S.raceWins), rgbm(0.35, 0.95, 0.55, 1) }, { 'LOSSES', tostring(S.raceLosses), RED }, { 'STREAK', tostring(S.raceStreak), GOLD } })
      local bests = XM.jget('raceBests', {})
      local list = {}
      for k, b in pairs(bests) do list[#list + 1] = b end
      table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
      y = W.sectionHeader('Personal records', y)
      if #list == 0 then
        text('No records yet. Arm a solo run or race a friend.', 13, SW / 2, y + 16, T.label2, F.r, 0.5)
        y = y + 50
      else
        W.groupBg(y, #list)
        for i, b in ipairs(list) do
          W.row('rec' .. i, b.name, y, { first = i == 1, last = i == #list, sub = (b.car or '') .. ' · ' .. ago(b.at or 0) })
          text(fmtT(b.t), 16, SW - 32, y + 13, GOLD, F.numb, 1)
          y = y + 46
        end
      end
      local log = XM.jget('raceLog', {})
      y = W.sectionHeader('Race history', y + 12)
      if #log == 0 then
        text('No races yet', 13, SW / 2, y + 12, T.label2, F.r, 0.5)
        y = y + 44
      else
        W.groupBg(y, #log)
        for i, r in ipairs(log) do
          W.row('rl' .. i, 'vs ' .. (r.opp or '?'), y, { first = i == 1, last = i == #log, sub = (r.spec or '') .. ' · ' .. (r.car or '') .. ' · ' .. ago(r.t) })
          local col = r.win == true and rgbm(0.35, 0.95, 0.55, 1) or (r.win == false and RED or T.label2)
          text(r.win == true and 'WIN' or (r.win == false and 'LOSS' or 'TIE'), 14, SW - 32, y + 6, col, F.numb, 1)
          if (r.wager or 0) > 0 then text(money(r.wager), 11, SW - 32, y + 26, T.label2, F.num, 1) end
          y = y + 46
        end
      end
    end
    scrollEnd(s, y + 24)
    navBar('Race', { large = true }, s.y)
  end
  return scr
end

-- bring the phone back to the result when a race ends
R.openUI = function() if APPMOD.openApp then APPMOD.openApp('race') end end
end
-- ===========================================================================
-- CAR app: lights, light colours, doors, bonnet and boot, all from the phone
-- ===========================================================================

XM.car = { lights = {}, hist = 0 }

do
local C = XM.car
-- colour presets for headlight and tail glow
C.COLORS = {
  { 'Stock white', rgbm(1.0, 0.96, 0.88, 1) }, { 'Ice blue', rgbm(0.55, 0.78, 1.0, 1) }, { 'Red', rgbm(1.0, 0.1, 0.08, 1) },
  { 'Orange', rgbm(1.0, 0.5, 0.1, 1) }, { 'Yellow', rgbm(1.0, 0.85, 0.2, 1) }, { 'Green', rgbm(0.2, 1.0, 0.35, 1) },
  { 'Cyan', rgbm(0.1, 0.95, 1.0, 1) }, { 'Blue', rgbm(0.15, 0.3, 1.0, 1) }, { 'Purple', rgbm(0.65, 0.25, 1.0, 1) },
  { 'Pink', rgbm(1.0, 0.25, 0.65, 1) }, { 'Lime', rgbm(0.7, 1.0, 0.1, 1) }, { 'Warm', rgbm(1.0, 0.7, 0.35, 1) },
}
local LETTERS = 'ABCDEFGHIJKLMNOP'
function C.lc(c, k) if type(rgb) == 'function' or type(rgb) == 'table' then return rgb(c.r * k, c.g * k, c.b * k) end return rgbm(c.r * k, c.g * k, c.b * k, 1) end

local function car0() return ac.getCar(0) end
local function safe(fn, ...) local ok, r = pcall(fn, ...) if ok then return r end end

-- ---- actions
function C.headlights() local c = car0() if c and ac.setHeadlights then ac.setHeadlights(not c.headlightsActive) end end
function C.highBeams() local c = car0() if c and ac.setHighBeams then ac.setHighBeams(not c.highBeams) end end
-- flashing is done here (not with ac.flashLights, which can latch): tap once to start blinking, tap again to stop
function C.flash()
  local c = car0()
  if not c then return end
  if C.flashing then
    C.flashing = false
    if ac.setHighBeams then ac.setHighBeams(C.prevHigh and true or false) end
    if ac.setHeadlights then ac.setHeadlights(C.prevHead and true or false) end
  else
    C.prevHead, C.prevHigh = c.headlightsActive, c.highBeams
    C.flashing, C.flashT0 = true, clock()
  end
end
function C.flashStep()
  if not C.flashing then return end
  local on = math.floor((clock() - C.flashT0) * 6) % 2 == 0
  if ac.setHeadlights then ac.setHeadlights(on) end
  if ac.setHighBeams then ac.setHighBeams(on) end
end
function C.daytime() local c = car0() if c and ac.setDaytimeLights then ac.setDaytimeLights(not c.daytimeRunningLights) end end
function C.hazards() local c = car0() if c and ac.setTurningLights then ac.setTurningLights(c.hazardLights and 0 or 3) end end
function C.driverDoor() local c = car0() if c and ac.setDriverDoorOpen then ac.setDriverDoorOpen(0, not c.isDriverDoorOpen, false) end end

-- switches the car exposes (bonnet, boot, doors and the like live here on CSP cars)
function C.switches()
  local out, c = {}, car0()
  if not c or not ac.isExtraSwitchAvailable then return out end
  for i = 0, 15 do
    if safe(ac.isExtraSwitchAvailable, i) then
      local name = safe(ac.getExtraSwitchName, i)
      if type(name) ~= 'string' or name == '' then name = 'Switch ' .. LETTERS:sub(i + 1, i + 1) end
      local low = name:lower()
      local role = (low:find('bonnet') or low:find('hood')) and 'bonnet' or ((low:find('trunk') or low:find('boot') or low:find('tailgate') or low:find('hatch') or low:find('rear lid')) and 'trunk'
        or (low:find('door') and 'door' or 'other'))
      out[#out + 1] = { index = i, name = name, role = role, on = c['extra' .. LETTERS:sub(i + 1, i + 1)] and true or false }
    end
  end
  return out
end
function C.toggleSwitch(sw) if ac.setExtraSwitch then ac.setExtraSwitch(sw.index, not sw.on) end end


-- ---- body panels moved straight from the car model (works on cars with no switches, as long as the parts are named in the model)
C.PARTS = {
  { id = 'bonnet', name = 'Bonnet', pat = 'hood*,bonnet*,capot*,bonnet', kind = 'hood', deg = 55 },
  { id = 'trunk',  name = 'Boot',   pat = 'trunk*,boot*,tailgate*,hatch*,bootlid*,trunklid*', kind = 'trunk', deg = 58 },
  { id = 'dlf',    name = 'Front left door',  pat = 'doorlf*,door_lf*,door_l_f*,doorfl*,door_fl*,door_l,door_left*', kind = 'door', deg = 62 },
  { id = 'drf',    name = 'Front right door', pat = 'doorrf*,door_rf*,door_r_f*,doorfr*,door_fr*,door_r,door_right*', kind = 'door', deg = 62 },
  { id = 'dlr',    name = 'Rear left door',   pat = 'doorlr*,door_lr*,door_l_r*,doorrl*,door_rl*,doorlb*', kind = 'door', deg = 58 },
  { id = 'drr',    name = 'Rear right door',  pat = 'doorrr*,door_rr*,door_r_r*,doorrr*,door_rr*,doorrb*', kind = 'door', deg = 58 },
}
C.partState = {}
local function rotPoint(axis, a, x, y, z)
  local c, sn = math.cos(a), math.sin(a)
  if axis == 'x' then return x, y * c - z * sn, y * sn + z * c end
  return x * c + z * sn, y, -x * sn + z * c
end
C.rotPoint = rotPoint

function C.partScan()
  local id = safe(ac.getCarID, 0) or 'car'
  if C.scanned == id then return end
  C.scanned = id
  -- put anything still open back before switching cars
  C.partState = {}
  local root = safe(ac.findNodes, 'carRoot:0')
  if not root then return end
  for _, def in ipairs(C.PARTS) do
    local refs = {}
    local found = safe(function() return root:findNodes(def.pat) end)
    local n = found and safe(function() return found:size() end) or 0
    for i = 1, math.min(n, 4) do
      local ref = safe(function() return found:at(i) end)
      if ref then
        local base = safe(function() return ref:getPosition() end)
        local look = safe(function() return ref:getLook() end)
        local up = safe(function() return ref:getUp() end)
        local mn, mx = safe(function() return ref:getLocalAABB() end)
        -- only plain nodes (no baked-in rotation) can be swung safely
        if base and look and up and mn and mx and math.abs(look.z - 1) < 0.01 and math.abs(up.y - 1) < 0.01 and mx.x - mn.x > 0.01 then
          refs[#refs + 1] = { ref = ref, bx = base.x, by = base.y, bz = base.z, mn = mn, mx = mx }
        end
      end
    end
    if #refs > 0 then C.partState[def.id] = { def = def, refs = refs, t = 0, target = 0 } end
  end
end

local function applyPart(st)
  local def = st.def
  local th = math.rad(def.deg) * st.t
  for _, r in ipairs(st.refs) do
    local cx, cy = (r.mn.x + r.mx.x) / 2, (r.mn.y + r.mx.y) / 2
    local axis, a, px, py, pz
    if def.kind == 'hood' then axis, a, px, py, pz = 'x', -th, cx, r.mx.y, r.mn.z
    elseif def.kind == 'trunk' then axis, a, px, py, pz = 'x', th, cx, r.mx.y, r.mx.z
    else
      local s = cx >= 0 and 1 or -1
      axis, a, px, py, pz = 'y', -s * th, cx, cy, r.mx.z
    end
    local ax = axis == 'x' and vec3(1, 0, 0) or vec3(0, 1, 0)
    local ok = pcall(function()
      r.ref:setRotation(ax, a)
      -- make sure the engine turns the same way as the maths below (flip if it doesn't)
      local lk = r.ref:getLook()
      local ex, ey, ez = rotPoint(axis, a, 0, 0, 1)
      if lk.x * ex + lk.y * ey + lk.z * ez < 0 and math.abs(th) > 1e-4 then
        r.ref:setRotation(ax, -a)
      end
      local rx, ry, rz = rotPoint(axis, a, px, py, pz)
      r.ref:setPosition(vec3(r.bx + px - rx, r.by + py - ry, r.bz + pz - rz))
    end)
    if not ok then st.broken = true end
  end
end

function C.partList()
  pcall(C.partScan)
  local out = {}
  for _, def in ipairs(C.PARTS) do
    local st = C.partState[def.id]
    if st and not st.broken then out[#out + 1] = { id = def.id, name = def.name, on = st.target > 0.5 } end
  end
  return out
end
function C.partToggle(id)
  local st = C.partState[id]
  if st then st.target = st.target > 0.5 and 0 or 1 end
end
function C.partStep(dt)
  for _, st in pairs(C.partState) do
    if st.t ~= st.target then
      local d = (st.target - st.t)
      local stp = math.min(1, dt * 2.2)
      st.t = math.abs(d) < 0.01 and st.target or (st.t + d * stp + (d > 0 and 0.004 or -0.004))
      st.t = math.max(0, math.min(1, st.t))
      applyPart(st)
    end
  end
end

-- ---- colour glow: tinted lights on the car (beams ahead, glow on the lamps, glow at the tail)
local function killLights(kind)
  for _, l in ipairs(C.lights[kind] or {}) do pcall(l.dispose, l) end
  C.lights[kind] = nil
end
local function makeLight(spot)
  if not ac.LightSource then C.err = 'This CSP build has no light sources' return nil end
  local ok, l = pcall(ac.LightSource, 1)
  if not ok or not l then C.err = 'Could not create a light: ' .. tostring(l) return nil end
  l.spot = spot
  l.spotSharpness = 0.35
  l.specularMultiplier = 0.6
  l.diffuseConcentration = 0.4
  l.affectsCars = true
  l.showInReflections = true
  l.skipLightMap = false
  return l
end
local function setLight(l, pos, dir, col, k, range, fade)
  l.position = pos
  if dir then l.direction = dir end
  l.color = C.lc(col, k)
  l.range, l.fadeAt, l.fadeSmooth = range, fade, fade * 0.6
end

function C.step(dt)
  local c = car0()
  if not c or not c.position or not c.look or not c.side then return end
  local look, side, up = c.look, c.side, c.up or vec3(0, 1, 0)
  C.active = { head = false, tail = false }
  if S.carHeadOn then
    if not C.lights.head then
      local L = { makeLight(40), makeLight(40), makeLight(150), makeLight(150) }   -- two beams, two lamp glows
      if L[1] and L[2] and L[3] and L[4] then C.lights.head = L else for _, l in pairs(L) do pcall(l.dispose, l) end end
    end
    local hs = C.lights.head
    if hs then
      local col = C.COLORS[S.carHeadCol] or C.COLORS[1]
      local on = (c.headlightsActive or c.lowBeams or c.highBeams) and 1 or 0
      local boost = c.highBeams and 1.6 or 1
      C.active.head = on > 0
      for i = 1, 2 do
        local sd = i == 1 and -0.62 or 0.62
        setLight(hs[i], c.position + look * 2.1 + side * sd + up * 0.62, look, col[2], on * 60 * S.carHeadPow * boost, 90, 70)
        setLight(hs[i + 2], c.position + look * 2.35 + side * sd * 1.1 + up * 0.7, look, col[2], on * 14 * S.carHeadPow, 7, 5)
      end
    end
  elseif C.lights.head then killLights('head') end
  if S.carTailOn then
    if not C.lights.tail then
      local L = { makeLight(150), makeLight(150), makeLight(170), makeLight(170) }
      if L[1] and L[2] and L[3] and L[4] then C.lights.tail = L else for _, l in pairs(L) do pcall(l.dispose, l) end end
    end
    local ts = C.lights.tail
    if ts then
      local col = C.COLORS[S.carTailCol] or C.COLORS[3]
      local lit = (c.headlightsActive or c.brakeLightsActive or c.daytimeRunningLights or c.lowBeams) and 1 or 0
      local boost = c.brakeLightsActive and 2.6 or 1
      C.active.tail = lit > 0
      for i = 1, 2 do
        local sd = i == 1 and -0.6 or 0.6
        setLight(ts[i], c.position - look * 2.2 + side * sd + up * 0.7, look * -1, col[2], lit * 18 * boost * S.carTailPow, 24, 18)
        setLight(ts[i + 2], c.position - look * 2.25 + side * sd * 1.05 + up * 0.72, look * -1, col[2], lit * 12 * boost * S.carTailPow, 5, 4)
      end
    end
  elseif C.lights.tail then killLights('tail') end
end

function C.update(dt)
  pcall(C.flashStep)
  pcall(C.partStep, dt)
  local ok, err = pcall(C.step, dt)
  if ok then C.stepErr = nil elseif C.stepErr ~= tostring(err) then C.stepErr = tostring(err) ac.log('HackaPhone car lights: ' .. C.stepErr) end
end

-- ---- UI
local function bigTile(id, x, y, w, h, label, sub, on, icon)
  local fired, pressed = tap(id, x, y, x + w, y + h)
  local a = anim(id .. '#on', on and 1 or 0, 14)
  local p = anim(id .. '#p', pressed and 1 or 0, 30)
  local ac1 = accent()
  rect(x, y, x + w, y + h, mix(T.cell, A(ac1, 0.32), a), 18)
  if a > 0.02 then rectLine(x, y, x + w, y + h, A(ac1, 0.9 * a), 18, 1.5) end
  if p > 0.01 then rect(x, y, x + w, y + h, rgbm(1, 1, 1, 0.1 * p), 18) end
  text(icon, 22, x + 16, y + 12, mix(T.label2, ac1, a), F.sb)
  textFit(label, 14, x + 16, y + h - 40, w - 24, T.label, F.sb)
  textFit(sub, 11, x + 16, y + h - 22, w - 24, on and ac1 or T.label2, F.r)
  return fired, pressed
end

local function swatches(idKey, y, selected, onPick)
  local n = #C.COLORS
  local cols, size, gap = 6, 40, (SW - 32 - 6 * 40) / 5
  for i, cdef in ipairs(C.COLORS) do
    local cx, cy = 16 + ((i - 1) % cols) * (size + gap), y + math.floor((i - 1) / cols) * (size + 10)
    local fired = tap(idKey .. i, cx, cy, cx + size, cy + size)
    circle(cx + size / 2, cy + size / 2, size / 2 - 2, cdef[2])
    if selected == i then
      circleLine(cx + size / 2, cy + size / 2, size / 2 + 1, T.white, 2.5)
    end
    if fired then onPick(i) end
  end
  return y + math.ceil(n / cols) * (size + 10)
end

function APPMOD.Car.root()
  local scr = { title = 'Car' }
  function scr.draw()
    bgFill()
    local c = car0()
    local s = scrollBegin('carapp', 50, BOTTOM)
    local y = largeTitle('Car', 96, s.y)
    textFit((ac.getCarName and ac.getCarName(0) or 'Your car'), 14, 16, y - 10, SW - 32, T.label2, F.m)
    y = y + 12
    local gw, gh = (SW - 32 - 10) / 2, 92
    local tiles = {
      { 'hl', 'Headlights', c and c.headlightsActive and 'On' or 'Off', c and c.headlightsActive, '●', C.headlights },
      { 'hb', 'High beams', c and c.highBeams and 'On' or 'Off', c and c.highBeams, '◉', C.highBeams },
      { 'hz', 'Hazards', c and c.hazardLights and 'Flashing' or 'Off', c and c.hazardLights, '▲', C.hazards },
      { 'fl', 'Flash', C.flashing and 'Flashing, tap to stop' or 'Tap to start', C.flashing, '⚡', C.flash },
      { 'dl', 'Daytime lights', c and c.daytimeRunningLights and 'On' or 'Off', c and c.daytimeRunningLights, '☀', C.daytime },
      { 'dd', 'Driver door', c and c.isDriverDoorOpen and 'Open' or 'Closed', c and c.isDriverDoorOpen, '▯', C.driverDoor },
    }
    for i, t in ipairs(tiles) do
      local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
      local fired = bigTile('car.' .. t[1], 16 + col * (gw + 10), y + row * (gh + 10), gw, gh, t[2], t[3], t[4] and true or false, t[5])
      if fired then t[6]() end
    end
    y = y + 3 * (gh + 10) + 6

    -- colour: headlights
    y = W.sectionHeader('Headlight colour', y)
    W.groupBg(y, 1)
    S.carHeadOn = W.toggleRow('car.hc', 'Custom colour', S.carHeadOn, y, { first = true, last = true })
    y = y + 52
    if S.carHeadOn then
      y = swatches('car.hs', y + 6, S.carHeadCol, function(i) S.carHeadCol = i end)
      rect(LIST.x, y + 4, LIST.x + LIST.w, y + 78, T.cell, 12)
      S.carHeadPow = W.sliderRow('car.hp', 'Brightness', S.carHeadPow, 0.2, 2.5, '%.1fx', y + 4, { last = true })
      y = y + 90
    end
    y = W.sectionFooter(C.err or C.stepErr or (S.carHeadOn and (C.active and C.active.head and 'Colour is live.' or 'Turn your headlights on (tile above) to see the colour.') or 'Adds tinted beams and a glow on the lamps whenever your headlights are on.'), y)

    -- colour: tail lights
    y = W.sectionHeader('Tail light colour', y + 4)
    W.groupBg(y, 1)
    S.carTailOn = W.toggleRow('car.tc', 'Custom glow', S.carTailOn, y, { first = true, last = true })
    y = y + 52
    if S.carTailOn then
      y = swatches('car.ts', y + 6, S.carTailCol, function(i) S.carTailCol = i end)
      rect(LIST.x, y + 4, LIST.x + LIST.w, y + 78, T.cell, 12)
      S.carTailPow = W.sliderRow('car.tp', 'Brightness', S.carTailPow, 0.2, 2.5, '%.1fx', y + 4, { last = true })
      y = y + 90
    end
    y = W.sectionFooter(C.err or C.stepErr or (S.carTailOn and (C.active and C.active.tail and 'Colour is live.' or 'Glows once your headlights are on or you brake.') or 'Glows with your headlights and flares when you brake.'), y)

    -- body: bonnet, boot, doors
    y = W.sectionHeader('Bonnet, boot and doors', y + 4)
    local sw = C.switches()
    local parts = C.partList()
    if #sw == 0 and #parts == 0 then
      rect(LIST.x, y, LIST.x + LIST.w, y + 86, T.cell, 14)
      textBox('This car’s model doesn’t have bonnet, boot or door parts the phone can recognise. The driver door button above still works.', 13, LIST.x + 16, y + 14, LIST.x + LIST.w - 16, y + 80, T.label2)
      y = y + 98
    else
      local total = #parts + #sw
      W.groupBg(y, total)
      local row = 0
      for _, o in ipairs(parts) do
        local v = W.toggleRow('car.pt' .. o.id, o.name, o.on, y + row * 46, { first = row == 0, last = row == total - 1, sub = o.on and 'Open' or 'Closed' })
        if v ~= o.on then C.partToggle(o.id) end
        row = row + 1
      end
      for _, o in ipairs(sw) do
        local icon = o.role == 'bonnet' and 'Bonnet' or (o.role == 'trunk' and 'Boot' or (o.role == 'door' and 'Door' or 'Extra'))
        local v = W.toggleRow('car.sw' .. o.index, o.name, o.on, y + row * 46, { first = row == 0, last = row == total - 1, sub = icon })
        if v ~= o.on then C.toggleSwitch(o) end
        row = row + 1
      end
      y = y + total * 46
      y = W.sectionFooter('Panels move on your screen only. Cars that define their own switches are listed too.', y + 6)
    end
    scrollEnd(s, y + 20)
    navBar('Car', { large = true }, s.y)
  end
  return scr
end

end
-- ===========================================================================
-- CAM EDITOR: the Assetto Corsa camera editor on your phone. Cockpit seat, FOV,
-- every F6 car camera, plus one-tap switching between all the drivable views.
-- ===========================================================================

XM.cam = { tab = 1, f6 = 0, base = {} }

do
local K = XM.cam
local function sim() return ac.getSim() end
local function seat()
  local ok, p = pcall(ac.getOnboardCameraParams, 0)
  if ok and type(p) == 'table' and p.position and type(p.pitch) == 'number' then return p end
end
local function seatDefault()
  local ok, p = pcall(ac.getOnboardCameraDefaultParams, 0)
  if ok and type(p) == 'table' and p.position and type(p.pitch) == 'number' then return p end
end
local function seatSet(pos, pitch, yaw)
  pcall(function() ac.setOnboardCameraParams(0, ac.SeatParams(pos, pitch, yaw), true) end)
end


-- ---- custom view placement (drives the camera hook in 3_camera.lua)
K.VIEWS = {
  { key = 'chase',  name = 'Chase',   mode = 2, sub = 0, def = { x = 0, y = 1.9, z = -6.2, yaw = 0, pitch = -7, roll = 0, fov = 60 } },
  { key = 'chase2', name = 'Chase 2', mode = 2, sub = 1, def = { x = 0, y = 3.0, z = -8.5, yaw = 0, pitch = -10, roll = 0, fov = 60 } },
  { key = 'bonnet', name = 'Bonnet',  mode = 2, sub = 2, def = { x = 0, y = 1.15, z = 0.9, yaw = 0, pitch = 0, roll = 0, fov = 65 } },
  { key = 'bumper', name = 'Bumper',  mode = 2, sub = 3, def = { x = 0, y = 0.55, z = 2.3, yaw = 0, pitch = 0, roll = 0, fov = 70 } },
  { key = 'dash',   name = 'Dash',    mode = 2, sub = 4, def = { x = 0, y = 1.0, z = 0.35, yaw = 0, pitch = 0, roll = 0, fov = 62 } },
}
function K.activeView()
  local sm = ac.getSim()
  if sm.cameraMode ~= 2 then return nil end
  for _, v in ipairs(K.VIEWS) do if v.sub == sm.driveableCameraMode then return v end end
end
local function entryKey(v) return v.key .. '|' .. (ac.getCarID and ac.getCarID(0) or 'car') end
function K.entry(v) return XM.jget('camTweaks', {})[entryKey(v)] end
function K.save(v, e) local t = XM.jget('camTweaks', {}) t[entryKey(v)] = e XM.jset('camTweaks', t) end
-- the entry in force right now: only for the view you're in, only when it's switched on
function K.current()
  local v = K.activeView()
  if not v then return nil end
  local e = K.entry(v)
  if e and e.on then return e end
end
-- safety: if a custom camera ever misbehaves, switch it off and hand the camera back to AC
function K.panic(why)
  local v = K.activeView()
  local e = v and K.entry(v)
  if e and e.on then e.on = false K.save(v, e) end
  if clock() - (K.panicAt or -9) > 5 then K.panicAt = clock() toast('Custom camera off', why, '⚠️') end
end
-- take the live AC camera as the starting point
function K.capture(v)
  local sm = ac.getSim()
  local car = ac.getCar(sm.focusedCar >= 0 and sm.focusedCar or 0)
  local e = {}
  for k, val in pairs(v.def) do e[k] = val end
  if car and sm.cameraPosition and sm.cameraLook and not (K.live) then
    local d = sm.cameraPosition - car.position
    local l = sm.cameraLook
    e.x, e.y, e.z = d:dot(car.side), d:dot(car.up), d:dot(car.look)
    e.yaw = math.deg(math.atan2(l:dot(car.side), l:dot(car.look)))
    e.pitch = math.deg(math.asin(clamp(l:dot(car.up), -1, 1)))
    e.roll = 0
    local f = ac.getCameraFOV and ac.getCameraFOV() or 60
    if f and f > 5 and f < 150 then e.fov = f end
  end
  e.on = false
  return e
end

function K.goCockpit() pcall(ac.setCurrentCamera, 0) end
function K.goDrivable(i) pcall(ac.setCurrentCamera, 2) pcall(ac.setCurrentDrivableCamera, i) end
function K.goF6(i) pcall(ac.setCurrentCamera, 1) pcall(ac.setCurrentCarCamera, i) end

local function card(y, h, tint)
  rect(LIST.x, y, LIST.x + LIST.w, y + h, tint or T.cell, 18)
end
-- one slider tile with a big live value
local function dial(id, label, v, lo, hi, fmt, y, tint)
  card(y, 78, tint)
  local nv, ch = W.sliderRow(id, label, v, lo, hi, fmt, y, { last = true })
  return ch and nv or v, ch, y + 88
end

local function hero(title, sub, big, y)
  local ac1 = accent()
  rect(16, y, SW - 16, y + 104, mix(T.cell, ac1, 0.14), 24)
  rectLine(16, y, SW - 16, y + 104, A(ac1, 0.5), 24, 1.5)
  text(title, 12, 34, y + 16, A(ac1, 1), F.b)
  textFit(sub, 13, 34, y + 36, SW - 150, T.label2, F.m)
  text(big, 40, SW - 34, y + 30, T.white, F.numb, 1)
  return y + 118
end

function APPMOD.CamEdit.root()
  local scr = { title = 'Cam Editor' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('camedit', 50, BOTTOM)
    local y = largeTitle('Cam Editor', 96, s.y)
    K.tab = W.segmented('ce.tab', { 'Cockpit', 'Views', 'F6 Cams' }, K.tab, 16, y, SW - 32)
    y = y + 48
    local sm = sim()
    if K.tab == 1 then
      -- driver seat: exactly what AC's own camera positioning app edits
      local p, d = seat(), seatDefault()
      y = hero('COCKPIT CAMERA', p and 'Your seat, saved per car' or 'Not available right now', string.format('%d°', math.floor((sm.firstPersonCameraFOV or 56) + 0.5)), y)
      if W.button('ce.cp', 'Look through it now', 16, y, SW - 32, 44, 'filled') then K.goCockpit() end
      y = y + 56
      local fov = sm.firstPersonCameraFOV or 56
      local nf, ch = dial('ce.fov', 'Field of view', fov, 20, 120, '%.0f°', y)
      if ch then pcall(ac.setFirstPersonCameraFOV, nf) end
      y = y + 88
      if p then
        local px, py, pz = p.position.x, p.position.y, p.position.z
        local dx, dy, dz = d and d.position.x or px, d and d.position.y or py, d and d.position.z or pz
        local changed
        local nx, c1 = dial('ce.x', 'Left / right', px, dx - 0.4, dx + 0.4, '%.3f m', y) y = y + 88
        local ny, c2 = dial('ce.y', 'Height', py, dy - 0.3, dy + 0.3, '%.3f m', y) y = y + 88
        local nz, c3 = dial('ce.z', 'Forward / back', pz, dz - 0.5, dz + 0.5, '%.3f m', y) y = y + 88
        local np, c4 = dial('ce.p', 'Look up / down', p.pitch, -25, 25, '%.1f°', y) y = y + 88
        local nyaw, c5 = dial('ce.w', 'Look left / right', p.yaw, -30, 30, '%.1f°', y) y = y + 88
        if c1 or c2 or c3 or c4 or c5 then seatSet(vec3(nx, ny, nz), np, nyaw) end
        local bw = (SW - 40) / 2
        if W.button('ce.rs', 'Reset seat', 16, y, bw, 44, 'gray') and d then seatSet(d.position, d.pitch, d.yaw or 0) end
        if W.button('ce.rf', 'Reset FOV', 24 + bw, y, bw, 44, 'gray') then pcall(ac.resetFirstPersonCameraFOV) end
        y = y + 56
        y = W.sectionFooter('Moves your eye point live and saves it for this car. Reset puts it back to the car’s original view.', y)
      else
        y = W.sectionFooter('This car doesn’t expose its cockpit camera to the phone. FOV still works.', y)
      end
    elseif K.tab == 2 then
      local views = {
        { 'Cockpit', 'Driver seat', function() K.goCockpit() end, sm.cameraMode == 0 },
        { 'Chase', 'Behind the car', function() K.goDrivable(0) end, sm.cameraMode == 2 and sm.driveableCameraMode == 0 },
        { 'Chase 2', 'Higher chase', function() K.goDrivable(1) end, sm.cameraMode == 2 and sm.driveableCameraMode == 1 },
        { 'Bonnet', 'On the bonnet', function() K.goDrivable(2) end, sm.cameraMode == 2 and sm.driveableCameraMode == 2 },
        { 'Bumper', 'Low at the front', function() K.goDrivable(3) end, sm.cameraMode == 2 and sm.driveableCameraMode == 3 },
        { 'Dash', 'Over the dashboard', function() K.goDrivable(4) end, sm.cameraMode == 2 and sm.driveableCameraMode == 4 },
      }
      local gw, gh = (SW - 32 - 10) / 2, 84
      for i, v in ipairs(views) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x, vy = 16 + col * (gw + 10), y + row * (gh + 10)
        local fired = tap('ce.v' .. i, x, vy, x + gw, vy + gh)
        local a = anim('ce.va' .. i, v[4] and 1 or 0, 14)
        rect(x, vy, x + gw, vy + gh, mix(T.cell, A(accent(), 0.32), a), 18)
        if a > 0.02 then rectLine(x, vy, x + gw, vy + gh, A(accent(), 0.9 * a), 18, 1.5) end
        text(v[1], 16, x + 16, vy + 18, T.white, F.b)
        text(v[2], 12, x + 16, vy + 44, v[4] and accent() or T.label2, F.m)
        if fired then v[3]() end
      end
      y = y + 3 * (gh + 10) + 6
      -- editor for the view you are in right now
      local av = K.activeView()
      if av then
        y = W.sectionHeader('Edit ' .. av.name, y)
        local e = K.entry(av)
        card(y, 56)
        text('Custom ' .. av.name .. ' camera', 15, LIST.x + 16, y + 18, T.white, F.sb)
        local on = e and e.on or false
        local non = W.toggle('ce.on', on, LIST.x + LIST.w - 62, y + 14)
        if non ~= on then
          if not e then e = K.capture(av) end
          e.on = non
          K.save(av, e)
        end
        y = y + 68
        if e and e.on then
          local ch
          local function row(id, label, field, lo, hi, fmt)
            local nv, c = dial(id, label, e[field], lo, hi, fmt, y)
            if c then e[field] = nv ch = true end
            y = y + 88
          end
          row('ce.cx', 'Left / right', 'x', -3, 3, '%.2f m')
          row('ce.cy', 'Height', 'y', -0.5, 5, '%.2f m')
          row('ce.cz', 'Distance (forward / back)', 'z', -14, 5, '%.2f m')
          row('ce.cyaw', 'Look left / right', 'yaw', -90, 90, '%.0f°')
          row('ce.cpit', 'Look up / down', 'pitch', -45, 45, '%.1f°')
          row('ce.croll', 'Tilt', 'roll', -30, 30, '%.1f°')
          row('ce.cfov', 'Field of view', 'fov', 20, 120, '%.0f°')
          if ch then K.dirty = true end
          if K.dirty and not IN.down then K.save(av, e) K.dirty = false end   -- saved when you let go, not on every frame
          local bw = (SW - 40) / 2
          if W.button('ce.cap', 'Reset (back to AC)', 16, y, bw, 44, 'gray') then
            K.save(av, nil)
          end
          if W.button('ce.def', 'Standard preset', 24 + bw, y, bw, 44, 'gray') then
            local d2 = {} for k2, v2 in pairs(av.def) do d2[k2] = v2 end d2.on = true K.save(av, d2)
          end
          y = y + 56
        end
        y = W.sectionFooter('Turn it on and the camera is yours to place, relative to the car. It starts from where the camera is right now. Settings are saved per car and per view.', y)
      else
        y = W.sectionFooter('Switch to Chase, Chase 2, Bonnet, Bumper or Dash to edit that camera. The cockpit tab edits your seat; the F6 tab edits the fixed car cameras.', y)
      end
    else
      local car = ac.getCar(0)
      local n = car and car.carCamerasCount or 0
      if n <= 0 then
        card(y, 90)
        textBox('This car has no F6 cameras to edit.', 14, LIST.x + 18, y + 18, LIST.x + LIST.w - 18, y + 76, T.label2)
        y = y + 100
      else
        K.f6 = clamp(K.f6, 0, n - 1)
        local okc, cam = pcall(ac.accessCarCamera, K.f6)
        if not okc or type(cam) ~= 'table' and type(cam) ~= 'userdata' then cam = nil end
        y = hero('F6 CAMERA ' .. (K.f6 + 1) .. ' OF ' .. n, cam and 'Fixed camera on your car' or 'Not available', cam and string.format('%d°', math.floor(cam.fov + 0.5)) or '--', y)
        local bw = (SW - 40) / 3
        if W.button('ce.pv', '‹ Prev', 16, y, bw, 44, 'gray') then K.f6 = (K.f6 - 1) % n end
        if W.button('ce.go', 'View it', 20 + bw, y, bw, 44, 'filled') then K.goF6(K.f6) end
        if W.button('ce.nx', 'Next ›', 24 + 2 * bw, y, bw, 44, 'gray') then K.f6 = (K.f6 + 1) % n end
        y = y + 58
        if cam then
          K.base[K.f6] = K.base[K.f6] or { fov = cam.fov, exp = cam.exposure, pos = vec3(cam.transform.position.x, cam.transform.position.y, cam.transform.position.z) }
          local b = K.base[K.f6]
          local nf, c1 = dial('ce.f6f', 'Field of view', cam.fov, 10, 120, '%.0f°', y) y = y + 88
          if c1 then cam.fov = nf end
          local ne, c2 = dial('ce.f6e', 'Exposure', cam.exposure or 1, 0.1, 4, '%.2f', y) y = y + 88
          if c2 then cam.exposure = ne end
          local t = cam.transform
          local px, py, pz = t.position.x, t.position.y, t.position.z
          local nx, c3 = dial('ce.f6x', 'Left / right', px, b.pos.x - 1.5, b.pos.x + 1.5, '%.2f m', y) y = y + 88
          local ny, c4 = dial('ce.f6y', 'Height', py, b.pos.y - 1.5, b.pos.y + 1.5, '%.2f m', y) y = y + 88
          local nz, c5 = dial('ce.f6z', 'Forward / back', pz, b.pos.z - 2, b.pos.z + 2, '%.2f m', y) y = y + 88
          if c3 or c4 or c5 then
            pcall(function() local m = cam.transform m.position = vec3(nx, ny, nz) cam.transform = m end)
          end
          local nc, c6 = dial('ce.f6c', 'Near clip', cam.clipNear or 0.1, 0.01, 1, '%.2f m', y) y = y + 88
          if c6 then cam.clipNear = nc end
          if W.button('ce.f6r', 'Reset this camera', 16, y, SW - 32, 44, 'gray') then
            cam.fov, cam.exposure = b.fov, b.exp
            pcall(function() local m = cam.transform m.position = b.pos cam.transform = m end)
          end
          y = y + 56
          y = W.sectionFooter('Changes apply live to the camera you’re viewing. They last for this session; reset puts the camera back.', y)
        end
      end
    end
    scrollEnd(s, y + 20)
    navBar('Cam Editor', { large = true }, s.y)
  end
  return scr
end

end


-- ===========================================================================
-- HackaPhone users met on servers: who is running the app, which version, when last seen (kept on this phone only)
-- ===========================================================================
XM.users = {}
do
local U = XM.users
local function ago(t)
  local d = os.time() - t
  if d < 60 then return 'just now' end
  if d < 3600 then return math.floor(d / 60) .. ' min ago' end
  if d < 86400 then return math.floor(d / 3600) .. ' h ago' end
  return math.floor(d / 86400) .. ' d ago'
end
function U.note(name, ver, build, minGap)
  if not name or name == '' then return end
  local db = XM.jget('userLog', {})
  local e = db[name]
  local now = os.time()
  if e and minGap and now - (e.last or 0) < minGap and not ver then return end
  e = e or { first = now }
  e.last = now
  if ver and ver ~= '' then e.ver, e.build = ver, build end
  e.server = (ac.getServerName and ac.getServerName() or '') or ''
  db[name] = e
  local n = 0
  for _ in pairs(db) do n = n + 1 end
  if n > 300 then   -- forget the longest-gone
    local oldK, oldT
    for k, v in pairs(db) do if not oldT or (v.last or 0) < oldT then oldK, oldT = k, v.last or 0 end end
    if oldK then db[oldK] = nil end
  end
  XM.jset('userLog', db)
end

local verEvent = ac.OnlineEvent({
  ac.StructItem.key('acphone.ver.v1'),
  ver = ac.StructItem.string(12), build = ac.StructItem.int32(),
}, function(sender, d)
  if not sender or sender.index == 0 then return end
  pcall(U.note, ac.getDriverName(sender.index), tostring(d.ver), d.build)
end)
-- announce my version once; the game re-sends it to anyone who joins later
function U.announce() NET.send(function() return verEvent({ ver = VERSION, build = BUILD }) end, 3, 'ver') end
-- anyone sending presence is running the app (older versions don't announce a version)
function U.tick(dt)
  U.t = (U.t or 0) + dt
  if U.t < 15 then return end
  U.t = 0
  if not ac.getSim().isOnlineRace then return end
  for _, p in ipairs(getPlayers()) do if p.hasApp then pcall(U.note, p.name, nil, nil, 300) end end
end

function XM.usersScreen()
  local scr = { title = 'HackaPhone users' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('users', 94, BOTTOM)
    local y = 104
    local db = XM.jget('userLog', {})
    local list = {}
    for name, e in pairs(db) do list[#list + 1] = { name = name, e = e } end
    table.sort(list, function(a, b) return (a.e.last or 0) > (b.e.last or 0) end)
    if #list == 0 then
      textBox('Nobody yet. Everyone running HackaPhone on a server you join is remembered here, with their version.', 14, 40, y + 10, SW - 40, y + 90, T.label2)
      y = y + 100
    else
      local latest = 0
      for _, r in ipairs(list) do latest = math.max(latest, tonumber(r.e.build) or 0) end
      y = W.sectionHeader(#list .. ' users met', y)
      W.groupBg(y, #list)
      for i, r in ipairs(list) do
        local e = r.e
        local sub = (e.ver and ('v' .. e.ver) or 'old version') .. ' · ' .. ago(e.last or 0)
        W.row('usr' .. i, r.name, y, { first = i == 1, last = i == #list, sub = sub })
        local upToDate = (tonumber(e.build) or 0) >= math.max(latest, BUILD)
        text(upToDate and 'Up to date' or 'Needs update', 13, SW - 32, y + 15, upToDate and T.green or T.orange or T.label2, F.r, 1)
        y = y + 46
      end
    end
    scrollEnd(s, y + 24)
    navBar('HackaPhone users', { back = 'Friends' })
  end
  return scr
end
end


-- ===========================================================================
-- Phone health: network queue, hitches and any errors the phone caught, with a copy-able report
-- ===========================================================================
function XM.memMB() local ok, v = pcall(collectgarbage, 'count') return ok and (v / 1024) or 0 end
function XM.healthReport()
  local lines = {
    'HackaPhone ' .. VERSION .. ' (build ' .. BUILD .. ')',
    'Car: ' .. tostring(ac.getCarID(0)) .. ' · Online: ' .. tostring(ac.getSim().isOnlineRace) .. ' · Cars: ' .. tostring(ac.getSim().carsCount),
    string.format('Net: sent %d · retried %d · dropped %d · queued %d', NET.sent, NET.retried, NET.dropped, #NET.q),
    string.format('Frames: %d · hitches>100ms %d · worst %.0f ms · memory %.1f MB', DIAG.frames, DIAG.hitches, DIAG.worst * 1000, XM.memMB()),
  }
  local names = {}
  for k in pairs(DIAG.cost) do names[#names + 1] = k end
  table.sort(names, function(a, b) return DIAG.cost[a] > DIAG.cost[b] end)
  for i = 1, math.min(5, #names) do lines[#lines + 1] = string.format('cost %s %.2f ms (peak %.1f)', names[i], DIAG.cost[names[i]] * 1000, (DIAG.peak[names[i]] or 0) * 1000) end
  for _, e in ipairs(DIAG.errs) do lines[#lines + 1] = string.format('[%s x%d] %s', e.tag, e.n, e.msg) end
  return table.concat(lines, '\n')
end

function XM.healthScreen()
  local scr = { title = 'Phone health' }
  function scr.draw()
    bgFill()
    local s = scrollBegin('health', 94, BOTTOM)
    local y = 104
    y = W.sectionHeader('Network', y)
    W.groupBg(y, 4)
    W.row('h.sent', 'Sent', y, { value = tostring(NET.sent), first = true })
    W.row('h.retry', 'Retried (server was busy)', y + 46, { value = tostring(NET.retried) })
    W.row('h.drop', 'Gave up on', y + 92, { value = tostring(NET.dropped) })
    W.row('h.q', 'Waiting to send', y + 138, { value = tostring(#NET.q), last = true })
    y = y + 138 + 46 + 14
    y = W.sectionHeader('Performance', y)
    W.groupBg(y, 3)
    W.row('h.hit', 'Hitches over 100 ms', y, { value = tostring(DIAG.hitches), first = true })
    W.row('h.worst', 'Worst frame', y + 46, { value = string.format('%.0f ms', DIAG.worst * 1000) })
    W.row('h.mem', 'Phone memory', y + 92, { value = string.format('%.1f MB', XM.memMB()), last = true })
    y = y + 138 + 14
    local names = {}
    for k in pairs(DIAG.cost) do names[#names + 1] = k end
    table.sort(names, function(a, b) return DIAG.cost[a] > DIAG.cost[b] end)
    local nShow = math.min(4, #names)
    if nShow > 0 then
      y = W.sectionHeader('Time per frame (top ' .. nShow .. ')', y)
      W.groupBg(y, nShow)
      for i = 1, nShow do
        local k = names[i]
        W.row('h.c' .. k, k, y, { first = i == 1, last = i == nShow, value = string.format('%.2f ms · peak %.1f', DIAG.cost[k] * 1000, (DIAG.peak[k] or 0) * 1000) })
        y = y + 46
      end
      y = y + 14
    end
    y = W.sectionHeader(#DIAG.errs == 0 and 'No problems caught' or 'Problems caught', y)
    if #DIAG.errs > 0 then
      W.groupBg(y, #DIAG.errs)
      for i, e in ipairs(DIAG.errs) do
        W.row('h.e' .. i, e.tag .. (e.n > 1 and (' ×' .. e.n) or ''), y, { first = i == 1, last = i == #DIAG.errs, sub = e.msg })
        y = y + 46
      end
      y = y + 8
    end
    if W.button('h.copy', 'Copy report', 16, y, (SW - 40) / 2, 42, 'filled') then
      pcall(ui.setClipboardText, XM.healthReport())
      toast('Copied', 'Paste it to whoever is fixing the phone', '📋')
    end
    if W.button('h.clear', 'Clear', 24 + (SW - 40) / 2, y, (SW - 40) / 2, 42, 'gray') then
      DIAG.errs = {} DIAG.hitches, DIAG.worst, DIAG.frames = 0, 0, 0
      NET.sent, NET.retried, NET.dropped = 0, 0, 0
    end
    y = y + 56
    scrollEnd(s, y + 24)
    navBar('Phone health', { back = 'Settings' })
  end
  return scr
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
  { id = 'leaders',  name = 'Leaderboards', icon = '@LEADERBOARD', c1 = rgbm(1.00, 0.80, 0.30, 1), c2 = rgbm(0.90, 0.50, 0.05, 1), root = APPMOD.Leaders.root },
  { id = 'bank',     name = 'Bank',     icon = '@STATS', c1 = rgbm(0.30, 0.85, 0.55, 1), c2 = rgbm(0.05, 0.55, 0.35, 1), root = APPMOD.Bank.root },
  { id = 'market',   name = 'Market',   icon = '@UP_ALT', c1 = rgbm(0.35, 0.80, 1.00, 1), c2 = rgbm(0.10, 0.45, 0.85, 1), root = APPMOD.Market.root },
  { id = 'power',    name = 'Power-Ups', icon = '@CONSTELLATION', c1 = rgbm(0.80, 0.45, 1.00, 1), c2 = rgbm(0.50, 0.15, 0.90, 1), root = APPMOD.Power.root },
  { id = 'runs',     name = 'Runs',     icon = '@STOPWATCH', c1 = rgbm(1.00, 0.60, 0.25, 1), c2 = rgbm(0.90, 0.30, 0.10, 1), root = APPMOD.Runs.root },
  { id = 'vault',    name = 'Vault',    icon = '@SAVE', c1 = rgbm(0.25, 0.25, 0.30, 1), c2 = rgbm(0.05, 0.05, 0.08, 1), root = APPMOD.Vault.root },
  { id = 'race',     name = 'Race',     icon = '@FLAG', c1 = rgbm(1.00, 0.30, 0.30, 1), c2 = rgbm(0.65, 0.05, 0.10, 1), root = APPMOD.Race.root, badge = function() return XM.race.state == 'invited_in' and 1 or 0 end },
  { id = 'car',      name = 'Car',      icon = '@CAR_FRONT', c1 = rgbm(0.30, 0.75, 1.00, 1), c2 = rgbm(0.08, 0.35, 0.80, 1), root = APPMOD.Car.root },
  { id = 'camedit',  name = 'Cam Editor', icon = '@SLIDERS', c1 = rgbm(0.35, 0.85, 0.75, 1), c2 = rgbm(0.10, 0.45, 0.65, 1), root = APPMOD.CamEdit.root },
  { id = 'music',    name = 'Music',    icon = '@MUSIC', c1 = rgbm(1.00, 0.36, 0.45, 1), c2 = rgbm(0.86, 0.10, 0.30, 1), root = APPMOD.Music.root },
  { id = 'weather',  name = 'Weather',  icon = '@WEATHER_FEW_CLOUDS', c1 = rgbm(0.45, 0.75, 1.00, 1), c2 = rgbm(0.15, 0.45, 0.90, 1), root = APPMOD.Weather.root },
  { id = 'library',  name = 'Apps',     icon = '@APPS', c1 = rgbm(0.45, 0.50, 1.00, 1), c2 = rgbm(0.25, 0.25, 0.80, 1), root = APPMOD.Library.root },
  { id = 'settings', name = 'Settings', icon = '@SETTINGS', c1 = rgbm(0.60, 0.60, 0.64, 1), c2 = rgbm(0.36, 0.36, 0.40, 1), root = APPMOD.Settings.root, badge = function() return (UPD.latest and tonumber(UPD.latest.build) and tonumber(UPD.latest.build) > BUILD and UPD.state ~= 'ready') and 1 or 0 end },
}
local APP_BY_ID = {}
APPMOD.APPS = APPS
for _, a in ipairs(APPS) do APP_BY_ID[a.id] = a end
local DOCK = { 'messages', 'music', 'camera', 'settings' }
local GRID = { 'cutup', 'leaders', 'maps', 'friends', 'walk', 'video', 'chase', 'livery', 'skins', 'plates', 'hud', 'weather', 'themes', 'library', 'runs', 'race', 'power', 'bank', 'market', 'vault', 'car', 'camedit' }

APPMOD.openApp = function(id) APPMOD.openAppImpl(id) end
local appIconRects = {}   -- id -> {x, y, size} for open/close zoom

local function openApp(id)
  local app = APP_BY_ID[id]
  if not app then return end
  NAV.app = app
  NAV.stack = { app.root() }
  local r = appIconRects[id]
  NAV.trans = { kind = 'open', t = 0, icon = r }
end

APPMOD.openAppImpl = openApp

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
  T_.XM, T_.APPMOD, T_.VIDEO_SHOTS, T_.camRelease, T_.MEDIA = XM, APPMOD, VIDEO_SHOTS, camRelease, MEDIA
  T_.LIVERY = { selfTest = LIVERY_API.selfTest, apply = LIVERY_API.apply, cfg = LIVERY_API.cfg, shaderOK = LIVERY_API.shaderOK, unpack = LIVERY_API.unpack, pack = LIVERY_API.pack }
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
  local musicArt = false
  if S.wallMode == 'music' then
    -- theme art underneath, so the cross-fade between songs looks smooth
    rect(0, 0, SW, SH, th.bottom, SCREEN.r)
    pushClip(0, 0, SW, SH)
    musicArt = WALL.music(0, 0, SW, SH, SCREEN.r)
    popClip()
  end
  if musicArt or (wp and WALL.cover(wp, 0, 0, SW, SH, SCREEN.r)) then
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

-- the live lap only exists once the car has moved; the clock counts from that moment
-- (and from the line on every new lap), so a car sitting in the pits shows nothing
function PHONE.lapTrack()
  local car = ac.getCar(0)
  if not car then return end
  local now, spd = clock(), car.speedKmh or 0
  local lt, laps = car.lapTimeMs or 0, car.lapCount or 0
  -- the live lap stops when the car stops dead, goes back to the pits, or takes a huge hit
  local stop = false
  if spd < 1 then
    PHONE.lapStill = PHONE.lapStill or now
    if now - PHONE.lapStill > 0.6 then stop = true end
  else PHONE.lapStill = nil end
  if car.isInPitlane then stop = true end
  local h = PHONE.lapHist or {}
  PHONE.lapHist = h
  h[#h + 1] = { now, spd }
  while #h > 0 and now - h[1][1] > 0.35 do table.remove(h, 1) end
  if h[1] and h[1][2] - spd > 70 then stop = true h = {} PHONE.lapHist = h end   -- 70+ km/h shed in a third of a second
  if PHONE.lapMoved and (laps ~= PHONE.lapSeen or lt + 1500 < (PHONE.lapPrev or 0)) then
    PHONE.lapMoved = false
    PHONE.lapOff = 0
    if laps ~= PHONE.lapSeen and spd > 3 and not stop then PHONE.lapMoved = true end   -- new lap, still rolling
  end
  if stop then
    PHONE.lapMoved = false
  elseif not PHONE.lapMoved and spd > 3 then
    PHONE.lapMoved, PHONE.lapOff = true, (laps ~= PHONE.lapSeen and 0 or lt)
  end
  PHONE.lapSeen, PHONE.lapPrev = laps, lt
end
function PHONE.lapMs(car) return math.max(0, (car.lapTimeMs or 0) - (PHONE.lapOff or 0)) end

local function lapActive()
  local car = ac.getCar(0)
  PHONE.lapTrack()
  return S.liveActivity and car and PHONE.lapMoved and not ac.getSim().isPaused
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
  local rr = XM.race.run
  if rr and rr.phase == 'running' then
    return '🏁 ' .. string.format('%.2f', rr.t), math.floor(rr.v) .. ' km/h', accent(), 'lap'
  end
  if lapActive() then
    local car = ac.getCar(0)
    local d = car.performanceMeter or 0
    local hasBest = LIVE.bestMs > 0
    return '⏱ ' .. fmtLapShort(PHONE.lapMs(car)), hasBest and string.format('%+.2f', d) or (math.floor(car.speedKmh) .. ' km/h'),
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
      text(fmtLap(PHONE.lapMs(car)), 26, x1 + 22, y1 + 62, T.white, F.numb)
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
  text(fmtLap(PHONE.lapMs(car)), 28, 28, y + 30, T.white, F.numb)
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

-- an incoming race invite is shown on top of everything, on any screen, so it can always be accepted
function PHONE.raceInviteOn()
  local R = XM.race
  return R.state == 'invited_in' and R.cur ~= nil and not R.busy()
end
function PHONE.raceInvite()
  local R, c = XM.race, XM.race.cur
  local x1, y1, x2, y2 = 12, 56, SW - 12, 152
  local ac1 = accent()
  rect(x1, y1, x2, y2, rgbm(0.07, 0.07, 0.09, 0.97), 24)
  rectLine(x1, y1, x2, y2, A(ac1, 0.9), 24, 2)
  avatar(c.oppName, x1 + 14, y1 + 12, 44)
  textFit('🏁 ' .. c.oppName .. ' wants to race you', 14, x1 + 68, y1 + 14, x2 - x1 - 80, T.white, F.b)
  textFit(R.specName(c.spec) .. (c.wager > 0 and ('  ·  for ' .. XM.money(c.wager)) or ''), 12, x1 + 68, y1 + 36, x2 - x1 - 80, T.label2, F.m)
  local bw = (x2 - x1 - 36) / 2
  if W.button('ri.acc', 'Accept', x1 + 14, y1 + 58, bw, 30, 'filled') then
    R.accept()
    if APPMOD.openApp then APPMOD.openApp('race') end
  end
  if W.button('ri.dec', 'Decline', x1 + 22 + bw, y1 + 58, bw, 30, 'danger') then R.decline() end
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

local HOME = { page = 1, offset = 0, dragging = false, edit = false, hits = {}, holdT = 0 }
PHONE.home = HOME
local ICON, COLS = 60, 4
local GAPX = (SW - 48 - ICON * COLS) / (COLS - 1)

local function appIconDraw(id, icon, label, x, y, c1, c2, badgeN, onTap, dot, slot)
  local fired, pressed = false, false
  local editing = slot and slot ~= 'drag' and HOME.edit
  if slot == 'drag' then
    -- the icon being carried: draw only
  elseif editing then
    -- edit mode: icons wiggle, a minus badge removes them, a press starts a drag
    x = x + math.sin(clock() * 17 + slot.n) * 1.3
    y = y + math.cos(clock() * 14 + slot.n * 1.7) * 0.9
    HOME.hits[#HOME.hits + 1] = { id = id, x = x + slot.ox, y = y }
  else
    fired, pressed = tap('icon.' .. id, x - 6, y - 6, x + ICON + 6, y + ICON + 24)
    if slot then
      if pressed and not HOME.drag then
        if HOME.holdId ~= id then HOME.holdId, HOME.holdT = id, 0 end
        HOME.holdT = HOME.holdT + IN.dt
        if math.abs(IN.m.x - IN.pressPos.x) < 10 and math.abs(IN.m.y - IN.pressPos.y) < 10 and HOME.holdT > 0.5 then
          HOME.edit = true
          HOME.drag = { id = id, x = x + slot.ox + ICON / 2, y = y + ICON / 2 }
          IN.active = '__drag'
          fired = false
        end
      elseif HOME.holdId == id then HOME.holdId = nil end
    end
  end
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
  if editing then
    local rx, ry = x - 3, y - 3
    if tap('rm.' .. id, rx - 8, ry - 8, rx + 26, ry + 26) then HOME.remove(id) end
    circle(rx + 9, ry + 9, 10, rgbm(0.28, 0.28, 0.30, 1))
    rect(rx + 4, ry + 8, rx + 14, ry + 10.4, T.white, 1)
  end
  if badgeN and badgeN > 0 and not editing then
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

-- ---- home layout: three pages, apps can be moved between them or removed (long-press)
HOME.PAGES = 3
function HOME.defaultLayout()
  local p2 = { 'car', 'camedit', 'race', 'runs', 'power', 'bank', 'market', 'vault' }
  local in2 = {}
  for _, id in ipairs(p2) do in2[id] = true end
  local p1 = {}
  for _, id in ipairs(GRID) do if not in2[id] then p1[#p1 + 1] = id end end
  return { p1, p2, {} }
end
function HOME.get()
  if HOME.L then return HOME.L end
  local L = XM.jget('homeLayout', nil)
  if type(L) ~= 'table' or type(L[1]) ~= 'table' then L = HOME.defaultLayout() end
  local seen = {}
  for p = 1, HOME.PAGES do
    L[p] = type(L[p]) == 'table' and L[p] or {}
    for i = #L[p], 1, -1 do
      local id = L[p][i]
      if not APP_BY_ID[id] or seen[id] then table.remove(L[p], i) else seen[id] = true end
    end
  end
  for _, id in ipairs(GRID) do   -- apps added by updates land at the end of page 1
    if not seen[id] then L[1][#L[1] + 1] = id end
  end
  HOME.L = L
  return L
end
function HOME.save() XM.jset('homeLayout', HOME.get()) end
function HOME.visible(page, skip)
  local out = {}
  for _, id in ipairs(HOME.get()[page]) do
    if id ~= skip and not listHas(S.hiddenApps, id) then out[#out + 1] = id end
  end
  return out
end
function HOME.remove(id)
  if not listHas(S.hiddenApps, id) then S.hiddenApps = listToggle(S.hiddenApps, id) end
end
function HOME.restore(id, page)
  local L = HOME.get()
  for p = 1, HOME.PAGES do for i, v in ipairs(L[p]) do if v == id then table.remove(L[p], i) break end end end
  L[page][#L[page] + 1] = id
  if listHas(S.hiddenApps, id) then S.hiddenApps = listToggle(S.hiddenApps, id) end
  HOME.save()
end
function HOME.moveTo(id, page, n)
  local L = HOME.get()
  for p = 1, HOME.PAGES do for i, v in ipairs(L[p]) do if v == id then table.remove(L[p], i) break end end end
  local vis = HOME.visible(page)
  local idx = #L[page] + 1
  if vis[n] then for i, v in ipairs(L[page]) do if v == vis[n] then idx = i break end end end
  table.insert(L[page], idx, id)
  HOME.save()
end
-- grid geometry: page 1 sits under the widgets
function HOME.slot(page, n)
  local c, r = (n - 1) % COLS, math.floor((n - 1) / COLS)
  if page == 1 then return 24 + c * (ICON + GAPX), 212 + r * 88 end
  return 24 + c * (ICON + GAPX), HOME.top0 + r * 92
end
function HOME.nearest(page, mx, my, count)
  local best, bd = 1, 1e9
  for n = 1, count + 1 do
    local x, y = HOME.slot(page, n)
    local d = (x + ICON / 2 - mx) ^ 2 + (y + ICON / 2 - my) ^ 2
    if d < bd then best, bd = n, d end
  end
  return best
end

function HOME.drawPage(page, ox)
  local oldX = D.x
  D.x = D.x + ox
  local top0 = 70
  if page == 3 and MEDIA.now() then top0 = nowPlayingCard(58, 'hm') + 6 end
  HOME.top0 = page == 1 and 212 or top0
  if page == 1 then
    local ww = ICON * 2 + GAPX
    widgetFriends(24, 62, ww, 132)
    widgetWeather(24 + ww + GAPX, 62, ww, 132)
  end
  local list = HOME.visible(page, HOME.drag and HOME.drag.id or nil)
  local gap = nil
  if HOME.drag and page == HOME.page then gap = HOME.nearest(page, HOME.drag.x, HOME.drag.y, #list) end
  local n = 0
  local function put(id)
    n = n + 1
    local a = APP_BY_ID[id]
    local x, y = HOME.slot(page, n)
    appIconDraw(id, a.icon, a.name, x, y, a.c1, a.c2, a.badge and a.badge() or 0, function() openApp(id) end, nil, { n = n, ox = ox })
  end
  for i = 1, #list + 1 do
    if gap == i then n = n + 1 end
    if list[i] then put(list[i]) end
  end
  -- game apps pinned from the Apps app live on the last page, after your apps
  if page == HOME.PAGES then
    local wins = {}
    if ac.getAppWindows then for _, w in ipairs(ac.getAppWindows()) do wins[w.name] = w end end
    local pinnedN = 0
    for _, name in ipairs(splitList(S.pinnedApps)) do
      local w = wins[name]
      if w then
        pinnedN = pinnedN + 1
        n = n + 1
        local x, y = HOME.slot(page, n)
        local col = avatarColor(w.title)
        local icon = appIcon(w.title) or utf8Trim(w.title, 1):upper()
        appIconDraw('win.' .. name, icon, w.title, x, y, rgbm(col.r * 1.15, col.g * 1.15, col.b * 1.15, 1), col, 0,
          function() toggleWindow(name) end, w.visible)
      end
    end
    if n == 0 and not HOME.edit then
      text('🧩', 40, SW / 2, 200, T.white, F.r, 0.5)
      text('Your page', 20, SW / 2, 260, T.white, F.sb, 0.5)
      textBox('Press and hold any app, then drag it here. Game apps you star in the Apps app show up here too.', 14, 50, 292, SW - 50, 360, rgbm(1, 1, 1, 0.75))
      if W.button('h2.lib', 'Open Apps', SW / 2 - 70, 370, 140, 40, 'filled') then openApp('library') end
    end
  end
  D.x = oldX
end

function HOME.draw()
  HOME.hits = {}
  local edit = HOME.edit
  -- page swipe
  local act = IN.active
  local canDrag = not HOME.drag and (act == nil or (type(act) == 'string' and (act:sub(1, 5) == 'icon.' or act:sub(1, 2) == 'w.')))
  if not IN.locked and IN.down and not HOME.dragging and canDrag and hit(0, 50, SW, SH - 120) then
    local dx = IN.m.x - IN.pressPos.x
    if math.abs(dx) > 10 and math.abs(dx) > math.abs(IN.m.y - IN.pressPos.y) then HOME.dragging = true IN.active = '__page' HOME.holdId = nil end
  end
  if HOME.dragging and IN.clicked == false and IN.active == '__page' then
    local dx = IN.m.x - IN.pressPos.x
    HOME.offset = clamp(-(HOME.page - 1) * SW + dx, -(HOME.PAGES - 1) * SW - 40, 40)
    if IN.released then
      if dx < -60 then HOME.page = math.min(HOME.PAGES, HOME.page + 1) elseif dx > 60 then HOME.page = math.max(1, HOME.page - 1) end
      HOME.dragging = false
    end
  else
    HOME.offset = damp(HOME.offset, -(HOME.page - 1) * SW, 14, IN.dt)
  end
  pushClip(0, 0, SW, SH)
  for p = 1, HOME.PAGES do
    if math.abs(HOME.offset + (p - 1) * SW) < SW + 20 then HOME.drawPage(p, HOME.offset + (p - 1) * SW) end
  end
  -- dragging an icon: it follows the finger, and pushing against an edge turns the page
  local mx, my = IN.m.x - D.x, IN.m.y - D.y
  if edit and not HOME.drag and IN.clicked and IN.active == nil then
    for _, h in ipairs(HOME.hits) do
      if mx >= h.x - 4 and mx <= h.x + ICON + 4 and my >= h.y - 4 and my <= h.y + ICON + 20 then
        HOME.drag = { id = h.id, x = mx, y = my }
        IN.active = '__drag'
        break
      end
    end
  end
  if HOME.drag then
    local d = HOME.drag
    if IN.down then
      d.x, d.y = mx, my
      if (mx < 18 and HOME.page > 1 or mx > SW - 18 and HOME.page < HOME.PAGES) and clock() > (HOME.flipAt or 0) then
        HOME.page = HOME.page + (mx < 18 and -1 or 1)
        HOME.flipAt = clock() + 0.8
      end
      local a = APP_BY_ID[d.id]
      appIconDraw(d.id, a.icon, nil, d.x - ICON / 2, d.y - ICON / 2 - 8, a.c1, a.c2, 0, nil, nil, 'drag')
    else
      local list = HOME.visible(HOME.page, d.id)
      HOME.moveTo(d.id, HOME.page, HOME.nearest(HOME.page, d.x, d.y, #list))
      HOME.drag = nil
    end
  end
  popClip()
  -- edit mode chrome: Done button and a tray with removed apps
  if edit then
    local dx1, dy1 = SW - 82, 52
    rect(dx1, dy1, dx1 + 68, dy1 + 28, rgbm(1, 1, 1, 0.22), 14)
    text('Done', 14, dx1 + 34, dy1 + 5, T.white, F.sb, 0.5)
    if tap('home.done', dx1, dy1, dx1 + 68, dy1 + 28) then HOME.edit = false HOME.drag = nil end
    local gone = {}
    for _, id in ipairs(GRID) do if listHas(S.hiddenApps, id) then gone[#gone + 1] = id end end
    if #gone > 0 and not HOME.drag then
      local ty = SH - 214
      rect(14, ty, SW - 14, ty + 62, rgbm(0, 0, 0, 0.35), 18)
      text('REMOVED  ·  tap to add back', 10, 26, ty + 5, rgbm(1, 1, 1, 0.7), F.b)
      for i = 1, math.min(#gone, 6) do
        local a = APP_BY_ID[gone[i]]
        local ix = 26 + (i - 1) * 50
        if tap('add.' .. gone[i], ix, ty + 20, ix + 40, ty + 60) then HOME.restore(gone[i], HOME.page) end
        rect(ix, ty + 20, ix + 40, ty + 58, a.c2, 11)
        local g = leadingIcon(a.icon)
        if g then glyph(g, ix + 9, ty + 27, 22, T.white) end
      end
    end
  end
  -- page dots
  local dy = SH - 140
  local dw = (HOME.PAGES - 1) * 9 + 14
  rect(SW / 2 - dw - 4, dy - 8, SW / 2 + dw + 4, dy + 8, rgbm(0, 0, 0, 0.2), 8)
  for i = 1, HOME.PAGES do
    local sel = HOME.page == i
    local cx = SW / 2 + (i - (HOME.PAGES + 1) / 2) * 18
    circle(cx, dy, 3.5, rgbm(1, 1, 1, sel and 1 or 0.4))
    if tap('dot' .. i, cx - 9, dy - 10, cx + 9, dy + 10) then HOME.page = i end
  end
end

function HOME.dock()
  -- dock
  local dockY = SH - 112
  rect(12, dockY, SW - 12, SH - 18, rgbm(1, 1, 1, 0.16), 32)
  local dgap = (SW - 24 - 24 - ICON * 4) / 3
  for i, id in ipairs(DOCK) do
    local a = APP_BY_ID[id]
    appIconDraw(id, a.icon, nil, 24 + (i - 1) * (ICON + dgap), dockY + 17, a.c1, a.c2, a.badge and a.badge() or 0, function() openApp(id) end)
  end
end

-- safety net: if the layout code ever fails, fall back to a plain grid so the apps are never lost
function HOME.legacy()
  local ww = ICON * 2 + GAPX
  widgetFriends(24, 62, ww, 132)
  widgetWeather(24 + ww + GAPX, 62, ww, 132)
  local n = 0
  for _, id in ipairs(GRID) do
    local a = APP_BY_ID[id]
    if a and not listHas(S.hiddenApps, id) then
      n = n + 1
      local c, r = (n - 1) % COLS, math.floor((n - 1) / COLS)
      appIconDraw(id, a.icon, a.name, 24 + c * (ICON + GAPX), 212 + r * 78, a.c1, a.c2, a.badge and a.badge() or 0, function() openApp(id) end)
    end
  end
end

local function homeScreen()
  wallpaper()
  local depth = #clipStack
  local ok, err = pcall(HOME.draw)
  if not ok then
    while #clipStack > depth do popClip() end
    HOME.err = tostring(err)
    DIAG.err('home', err)
    if HOME.errLogged ~= HOME.err then HOME.errLogged = HOME.err ac.log('HackaPhone home: ' .. HOME.err) end
    HOME.drag, HOME.edit = nil, false
    HOME.L = nil
    S.homeLayout = ''
    local ok2, err2 = pcall(HOME.legacy)
    if not ok2 then ac.log('HackaPhone home fallback: ' .. tostring(err2)) end
  end
  HOME.dock()
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
      D.x = D.x + (ix - cx) * (1 - e) * 0.15
      D.y = D.y + (iy - cy) * (1 - e) * 0.15 + 30 * (1 - e)
      D.a = D.a * clamp(e * 1.4, 0, 1)
      scr.draw(scr)
      cornerMasks()
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
      if CAM.recOn then
        CAM.recOn = false
        pcall(MEDIA.recorder, false)
        toast('Recording stopped', 'Find it in Medal › Library › Sessions', '🎬')
      else
        toast('Recording stopped', 'Press Alt+F7 if Medal is still recording', '🎬')
      end
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

local function readInput(dt, k)
  k = k or 1
  local wp = ui.windowPos()
  local mp = ui.mousePos()
  IN.raw = mp - wp
  IN.m = IN.raw / k
  local ws = ui.windowSize()
  local inside = IN.raw.x >= 0 and IN.raw.y >= 0 and IN.raw.x <= ws.x and IN.raw.y <= ws.y
  IN.hovered = inside and ui.windowHovered(ui.HoveredFlags.AllowWhenBlockedByActiveItem)
  IN.dt = dt
  IN.down = ui.mouseDown(ui.MouseButton.Left)
  IN.clicked = IN.hovered and ui.mouseClicked(ui.MouseButton.Left)
  IN.released = ui.mouseReleased(ui.MouseButton.Left)
  IN.delta = ui.mouseDelta() / k
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
  if now - lastDraw > 2.0 then      -- only a real close/reopen replays the slide-in, never a frame hitch
    openAnim = 0
    if S.lockScreen and lastDraw > 0 and now - lastDraw > 30 then PHONE.locked = true PHONE.unlock = 0 SHEET.kind = nil end
  end
  lastDraw = now
  dt = clamp(dt or 0.016, 0, 0.1)
  local k = clamp(S.phoneScale or 1, 0.6, 1.8)
  if PHONE.appliedScale ~= k or PHONE.appliedMin ~= PHONE.minimized then PHONE.applySize() end
  readInput(dt, k)
  PHONE.keepPlace()
  if CAM.hidden then endInput() return end      -- taking a photo: draw nothing
  if PHONE.minimized then
    GS.begin(k)
    capsule()
    GS.finish()
    endInput()
    return
  end
  GS.begin(k)

  openAnim = math.min(1, openAnim + dt / 0.35)
  local e = easeOut(openAnim)
  D.x, D.y, D.a = 0, 60 * (1 - e), e
  if openAnim < 1 then IN.locked = true end

  -- phone body (design units; the whole phone scales together)
  local ws = PHONE.BASE
  rect(0, 0, ws.x, ws.y, T.body, 47)
  -- rim: invisible until the cursor is over the phone, then it fades in with a soft accent edge
  PHONE.rimA = (PHONE.rimA or 0) + ((IN.hovered and 1 or 0) - (PHONE.rimA or 0)) * math.min(1, IN.dt * 10)
  if PHONE.rimA > 0.01 then
    local oa, ac_ = D.a, accent()
    D.a = oa * PHONE.rimA
    rectLine(1, 1, ws.x - 1, ws.y - 1, rgbm(ac_.r, ac_.g, ac_.b, 0.22), 47, 5)
    rectLine(1.5, 1.5, ws.x - 1.5, ws.y - 1.5, T.frame, 46, 2.5)
    rectLine(3, 3, ws.x - 3, ws.y - 3, rgbm(1, 1, 1, 0.16), 45, 1)
    D.a = oa
  end

  -- screen
  D.x, D.y = SCREEN.x, SCREEN.y + 60 * (1 - e)
  local baseX, baseY = D.x, D.y
  local inviteUp = PHONE.raceInviteOn()
  local inviteHit = inviteUp and hit(12, 56, SW - 12, 152)
  if PHONE.locked then
    IN.locked = openAnim < 1 or SHEET.kind ~= nil or inviteHit
    lockScreen()
    if not PHONE.locked and not IN.locked then IN.active = '__unlocked' end
  else
    IN.locked = IN.locked or SHEET.kind ~= nil
    -- the expanded music/lap card sits over the widgets: while it's open, touches inside it belong to it only
    if (LIVE.expanded > 0.02 and hit(14, 10, SW - 14, 134)) or inviteHit then IN.locked = true end
    compose()
  end
  XM.welcome.drawPhone()
  D.x, D.y = baseX, baseY
  IN.locked = (NAV.trans ~= nil) or openAnim < 1
  sheets()
  cornerMasks()
  statusBar(false)
  statusGestures()
  banners()
  if PHONE.raceInviteOn() then PHONE.raceInvite() end

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

  -- resize: grab any edge or corner of the frame (proportions stay locked)
  D.x, D.y, D.a = 0, 0, 1
  local gx, gy = PHONE.BASE.x, PHONE.BASE.y
  local m = IN.m
  local onEdge = IN.hovered and (m.x > gx - 16 or m.y > gy - 16 or m.x < 12 or (m.x > gx - 40 and m.y > gy - 40))
  local inScreen = m.x > SCREEN.x and m.x < SCREEN.x + SW and m.y > SCREEN.y and m.y < SCREEN.y + SH
  if onEdge and inScreen and not (m.x > gx - 40 and m.y > gy - 40) then onEdge = false end
  if onEdge and IN.clicked then
    IN.active = '__resize'
    PHONE.resizing = true
    PHONE.resizeFrom, PHONE.resizeK = ui.mousePos(), k
    PHONE.resizeLeft = m.x < 12
  end
  if onEdge or PHONE.resizing then
    ui.setMouseCursor(type(ui.MouseCursor) == 'table' and ui.MouseCursor.ResizeNWSE or 6)
    local a = PHONE.resizing and 0.95 or 0.55
    rectLine(2, 2, gx - 2, gy - 2, rgbm(accent().r, accent().g, accent().b, a * 0.8), 46, 3)
    for i = 0, 2 do line(gx - 14 - i * 8, gy - 6, gx - 6, gy - 14 - i * 8, rgbm(1, 1, 1, a), 2.5) end
    if PHONE.resizing then
      local label = string.format('%d%%', math.floor(k * 100 + 0.5))
      rect(gx / 2 - 34, gy / 2 - 18, gx / 2 + 34, gy / 2 + 18, rgbm(0, 0, 0, 0.75), 18)
      text(label, 18, gx / 2, gy / 2 - 12, T.white, F.numb, 0.5)
    end
  end
  -- long-press the status bar to move the phone
  if IN.clicked and IN.m.y < SCREEN.y + 46 then PHONE.pressAt, PHONE.pressRaw = clock(), ui.mousePos() PHONE.winStart = ui.windowPos() end
  if IN.down and PHONE.pressAt and not PHONE.moving and clock() - PHONE.pressAt > 0.4 and (IN.m - IN.pressPos):length() < 8 and (IN.active == nil or IN.active == 'sb.left' or IN.active == 'sb.right' or IN.active == 'island') then
    PHONE.moving = true
    PHONE.winStart, PHONE.pressRaw = ui.windowPos(), ui.mousePos()
    IN.active = '__move'
  end
  if PHONE.moving then
    rect(0, 0, PHONE.BASE.x, PHONE.BASE.y, rgbm(1, 1, 1, 0.06), 47)
    local label = 'Drag to move'
    local w = measure(label, 13, F.sb).x + 28
    rect(gx / 2 - w / 2, 70, gx / 2 + w / 2, 98, rgbm(0, 0, 0, 0.75), 14)
    text(label, 13, gx / 2, 75, T.white, F.sb, 0.5)
  end
  GS.finish()

  if PHONE.resizing then
    if IN.down then
      -- grow with the drag: diagonal distance relative to the phone size, keeping the top-left pinned
      local d = ui.mousePos() - PHONE.resizeFrom
      if PHONE.resizeLeft then d = vec2(-d.x, d.y) end
      local grow = math.max(d.x / PHONE.BASE.x, d.y / PHONE.BASE.y)
      local nk = clamp(PHONE.resizeK + grow, 0.6, 1.8)
      S.phoneScale = math.floor(nk * 100 + 0.5) / 100
    else
      PHONE.resizing = false
    end
  end
  -- right-click and drag anywhere to move
  if IN.hovered and ui.mouseClicked(ui.MouseButton.Right) then
    PHONE.rightMove, PHONE.pressRaw, PHONE.winStart = true, ui.mousePos(), ui.windowPos()
  end
  if PHONE.rightMove then
    if ui.mouseDown(ui.MouseButton.Right) then
      local acc = PHONE.selfWindow()
      if acc then acc:move(PHONE.winStart + (ui.mousePos() - PHONE.pressRaw)) end
    else
      PHONE.rightMove = false
    end
  end
  if PHONE.moving then
    if IN.down then
      local acc = PHONE.selfWindow()
      if acc then acc:move(PHONE.winStart + (ui.mousePos() - PHONE.pressRaw)) end
    else
      PHONE.moving, PHONE.pressAt = false, nil
    end
  end
  if not IN.down then PHONE.pressAt = nil end

  -- invisible catchers so clicks on the screen and grip don't drag the window (drag by the frame or long-press the status bar)
  ui.setCursor(vec2(SCREEN.x, SCREEN.y) * k)
  ui.invisibleButton('##acphone_screen', vec2(SW, SH) * k)
  -- frame edges used for resizing (left, right, bottom strips)
  ui.setCursor(vec2((PHONE.BASE.x - 16) * k, 60 * k))
  ui.invisibleButton('##acphone_gripR', vec2(16 * k, (PHONE.BASE.y - 60) * k))
  ui.setCursor(vec2(0, (PHONE.BASE.y - 16) * k))
  ui.invisibleButton('##acphone_gripB', vec2(PHONE.BASE.x * k, 16 * k))
  ui.setCursor(vec2(0, 60 * k))
  ui.invisibleButton('##acphone_gripL', vec2(12 * k, (PHONE.BASE.y - 60) * k))
  endInput()
end

-- our own window, for moving it from code
-- the phone should only ever move when you move it: if the window gets shoved while no button is held
-- (a layout change, a hitch, a stray drag), put it back where it was
function PHONE.keepPlace()
  local wp = ui.windowPos()
  local now = clock()
  local held = ui.mouseDown(ui.MouseButton.Left) or ui.mouseDown(ui.MouseButton.Right) or PHONE.moving or PHONE.rightMove or PHONE.resizing
  local last = PHONE.placeAt
  if held or PHONE.appliedScale ~= PHONE.placeScale or PHONE.appliedMin ~= PHONE.placeMin or not last or now - (PHONE.placeT or 0) > 1 then
    PHONE.placeAt, PHONE.placeT = wp, now
    PHONE.placeScale, PHONE.placeMin = PHONE.appliedScale, PHONE.appliedMin
    return
  end
  local d = wp - last
  if math.abs(d.x) + math.abs(d.y) > 24 then
    PHONE.fixes = PHONE.fixes or {}
    local n = #PHONE.fixes
    while n > 0 and now - PHONE.fixes[1] > 20 do table.remove(PHONE.fixes, 1) n = n - 1 end
    if n < 3 then
      local acc = PHONE.selfWindow()
      if acc then pcall(acc.move, acc, last) PHONE.fixes[#PHONE.fixes + 1] = now end
      PHONE.placeT = now
      return
    end
  end
  -- small drift, or the window keeps getting moved by something else: accept the new spot
  PHONE.placeT, PHONE.placeAt = now, wp
end

function PHONE.selfWindow()
  if PHONE.selfAcc and PHONE.selfAcc:valid() then return PHONE.selfAcc end
  if not ac.getAppWindows then return nil end
  for _, w in ipairs(ac.getAppWindows()) do
    if w.title == 'HackaPhone' then PHONE.selfAcc = ac.accessAppWindow(w.name) return PHONE.selfAcc end
  end
  return nil
end

-- ===========================================================================
-- Action bar: on-screen Cut-Up HUD (its own window, works with the phone closed)
-- ===========================================================================

local BAR_BASE = vec2(560, 180)
local barApplied = nil
function script.actionBar(dt)
  D.x, D.y, D.a = 0, 0, 1
  local bk = clamp(S.barScale or 1, 0.5, 2)
  if barApplied ~= bk and ac.setWindowSizeConstraints then
    ac.setWindowSizeConstraints('actionbar', BAR_BASE * bk, BAR_BASE * bk)
    barApplied = bk
  end
  GS.begin(bk)
  local ok, err = pcall(script.actionBarDraw, dt)
  GS.finish()
  if not ok then ac.log('HackaPhone action bar: ' .. tostring(err)) end
end


function script.actionBarDraw(dt)
  local ws = BAR_BASE
  local cx = ws.x / 2
  -- window edge: invisible until hovered, so you can see where to grab and resize
  local hov = ui.windowHovered(ui.HoveredFlags.AllowWhenBlockedByActiveItem) and true or false
  PHONE.barHover = (PHONE.barHover or 0) + ((hov and 1 or 0) - (PHONE.barHover or 0)) * math.min(1, (dt or 0.016) * 10)
  if PHONE.barHover > 0.01 then
    local oa = D.a
    D.a = oa * PHONE.barHover
    local c = accent()
    rect(1, 1, ws.x - 1, ws.y - 1, rgbm(1, 1, 1, 0.025), 28)
    rectLine(1.5, 1.5, ws.x - 1.5, ws.y - 1.5, rgbm(c.r, c.g, c.b, 0.55), 28, 1.5)
    D.a = oa
  end
  local ac1 = accent()
  local gold = rgbm(1, 0.78, 0.22, 1)
  local minimal = S.barStyle == 2
  if XM.race.drawHud(cx) then return end
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
    local tcol = HESI.tierColor()
    local beat = 0.5 + 0.5 * math.sin(clock() * 6)
    local bw = minimal and 300 or 480
    local bh = minimal and 50 or 64
    local x1, x2 = cx - bw / 2, cx + bw / 2
    -- tier glow: soft halo that gets stronger with the multiplier and flares on every event
    for g = 3, 1, -1 do
      local gi = (0.05 + 0.10 * hot + 0.14 * HESI.pulse + 0.04 * beat * hot) / g
      rect(x1 - g * 4, y0 - g * 4, x2 + g * 4, y0 + bh + g * 4, A(tcol, gi), bh / 2 + g * 4)
    end
    -- glass bar
    rect(x1, y0, x2, y0 + bh, rgbm(0.03, 0.03, 0.04, 0.82), bh / 2)
    ui.drawRectFilledMultiColor(P(x1 + bh / 2, y0), P(x2 - bh / 2, y0 + 1.5), A(rgbm(1, 1, 1, 0)), A(rgbm(1, 1, 1, 0)), A(rgbm(1, 1, 1, 0.25)), A(rgbm(1, 1, 1, 0.25)))
    rectLine(x1, y0, x2, y0 + bh, A(tcol, (0.12 + hot * 0.3 + HESI.pulse * 0.3) * (1 - 0.5 * (1 - PHONE.barHover)) + 0.35 * PHONE.barHover), bh / 2, 1.5)
    -- combo timer underline
    local frac = clamp(HESI.combo / HESI.comboMax, 0, 1)
    rect(x1 + bh / 2, y0 + bh - 3, x1 + bh / 2 + (bw - bh) * frac, y0 + bh - 1, frac < 0.25 and T.red or tcol, 1)
    if minimal then
      text(HESI.fmt(HESI.anim('bar.score', HESI.run, 16)), 30, cx - 20, y0 + 7, T.white, F.numb, 0.5)
      text(string.format('x%.1f', HESI.mult), 20, x2 - 22, y0 + 13, tcol, F.numb, 1)
    else
      -- multiplier
      text(string.format('x%.1f', HESI.mult), 26 + math.floor(HESI.pulse * 3), x1 + 34, y0 + 14, tcol, F.numb, 0)
      local tier = HESI.tier()
      if tier ~= '' then text(tier, 9, x1 + 36, y0 + 46, tcol, F.b) end
      -- score
      text(HESI.fmt(HESI.anim('bar.score', HESI.run, 16)), 38 + math.floor(HESI.pulse * 3), cx, y0 + 8, T.white, F.numb, 0.5)
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
    if #(HESI.pw.names or {}) > 0 and HESI.slowT <= 0.3 then
      text(table.concat(HESI.pw.names, '  ·  '):upper(), 10, cx, y0 + bh + 8, rgbm(0.8, 0.55, 1, 0.95), F.b, 0.5)
    end
    if HESI.slowT > 0.3 then
      local w = 170
      rect(cx - w / 2, y0 + bh + 6, cx + w / 2, y0 + bh + 28, rgbm(0.1, 0.55, 0.3, 0.92), 11)
      text(string.format('BANKING  %.1f', math.max(0, HESI.bankTime - HESI.slowT)), 12, cx, y0 + bh + 10, T.white, F.numb, 0.5)
    end
  else
    local armed = #XM.equippedList()
    local label = S.hesiOn and ('@BURN  PB ' .. HESI.fmt(S.hesiPB) .. '   ·   ' .. XM.money(XM.cash()) .. (armed > 0 and ('   ·   ' .. armed .. ' POWER-UP' .. (armed > 1 and 'S' or '') .. ' READY') or '') .. '   ·   ' .. HESI.startSpeed .. '+ KM/H') or '@BURN  CUT-UP OFF'
    local w = measure(label, 12, F.numb).x + 34
    rect(cx - w / 2, y0 + 24, cx + w / 2, y0 + 52, rgbm(0.03, 0.03, 0.04, 0.6), 14)
    text(label, 12, cx, y0 + 31, rgbm(1, 1, 1, 0.85), F.numb, 0.5)
  end
  XM.welcome.drawBanner(cx)
  if HESI.crashFlash > 0 then
    local f = HESI.crashFlash
    local oldA = D.a
    local shake = math.sin(f * 60) * 8 * f * f
    D.a = oldA * f * 0.5
    rect(cx - 150 + shake, 8, cx + 150 + shake, 70, T.red, 31)
    D.a = oldA * clamp(f * 1.6, 0, 1)
    text('CRASHED', 30, cx + shake, 12, T.white, F.numb, 0.5)
    text('BANKED +' .. HESI.fmt(HESI.crashLost or 0) .. '   ' .. (HESI.lastRun and HESI.lastRun.pay and ('+' .. XM.money(HESI.lastRun.pay)) or ''), 15, cx + shake, 46, rgbm(1, 0.85, 0.85, 1), F.numb, 0.5)
    D.a = oldA
  elseif HESI.bankFlash > 0 then
    local f = HESI.bankFlash
    local oldA = D.a
    local gr = rgbm(0.3, 1, 0.5, 1)
    D.a = oldA * f * 0.45
    rect(cx - 160, 8, cx + 160, 70, gr, 31)
    D.a = oldA * clamp(f * 1.6, 0, 1)
    text('BANKED', 14, cx, 10, T.white, F.numb, 0.5)
    text('+' .. HESI.fmt(HESI.lastBank), 28 + math.floor(f * 6), cx, 26, T.white, F.numb, 0.5)
    if HESI.lastRun and HESI.lastRun.pay then text('+' .. XM.money(HESI.lastRun.pay) .. ' cash', 12, cx, 58, rgbm(0.85, 1, 0.9, 1), F.numb, 0.5) end
    D.a = oldA
  end
end

-- ===========================================================================
-- Background work
-- ===========================================================================

-- one small, spread-out hello (status, version, plate, livery, wealth) instead of everyone answering a join at once
function PHONE.beacon()
  if not ac.getSim().isOnlineRace then return end
  local steps = { broadcastPresence, XM.users.announce, XM.ecoBeacon, PL.broadcast, LIVERY_API.broadcast }
  for i, fn in ipairs(steps) do
    setTimeout(function() pcall(fn) end, (i - 1) * 0.6)
  end
end
function PHONE.beaconSoon()
  if PHONE.beaconQueued then return end
  PHONE.beaconQueued = true
  setTimeout(function() PHONE.beaconQueued = false PHONE.beacon() end, 3 + math.random() * 9)
end
XM.beaconSoon = PHONE.beaconSoon
function PHONE.beaconTick(dt)
  PHONE.beaconT = (PHONE.beaconT or (40 + math.random() * 30)) - dt
  if PHONE.beaconT <= 0 then PHONE.beaconT = 90 + math.random() * 30 PHONE.beacon() end
end

function script.update(dt)
  NET.tick()
  DIAG.frames = DIAG.frames + 1
  if dt > 0.1 then
    DIAG.hitches = DIAG.hitches + 1
    local why = {}
    for _, m in ipairs(DIAG.marks) do if clock() - m.t < 4 then why[#why + 1] = m.text end end
    DIAG.note(string.format('HITCH %d ms · online %s · cars %d · queue %d · after: %s', dt * 1000, tostring(ac.getSim().isOnlineRace), ac.getSim().carsCount, #NET.q, #why > 0 and table.concat(why, ', ') or 'nothing noted'))
  end
  DIAG.snapT = (DIAG.snapT or 0) + dt
  if DIAG.snapT > 60 then
    DIAG.snapT = 0
    if ac.getSim().isOnlineRace then
      local names = {}
      for k in pairs(DIAG.cost) do names[#names + 1] = k end
      table.sort(names, function(a, b) return DIAG.cost[a] > DIAG.cost[b] end)
      local top = {}
      for i = 1, math.min(3, #names) do top[#top + 1] = string.format('%s %.2fms', names[i], DIAG.cost[names[i]] * 1000) end
      DIAG.note(string.format('online · cars %d · net sent %d retried %d dropped %d queued %d · %s · mem %.1f MB', ac.getSim().carsCount, NET.sent, NET.retried, NET.dropped, #NET.q, table.concat(top, ', '), XM.memMB()))
    end
  end
  DIAG.flush()
  if dt > DIAG.worst then DIAG.worst = dt end
  do local ok, e = pcall(PHONE.beaconTick, dt) if not ok then DIAG.err('beacon', e) end end
  if not SHEET.started then
    SHEET.started = true
    pcall(LIVERY_API.selfTest)
    setTimeout(function()
      if ac.getSim().isOnlineRace then
        broadcastPresence()
        NET.send(function() return skinRequest({ received = true }) end, 3, 'skinreq')
      end
      if S.plateAutoApply and PL.text ~= '' then PL.apply(0, PL.text, PL.country) PL.broadcast() end
      pcall(XM.users.announce)
      UPD.announce()
      XM.welcome.trigger()
      if S.actionBar then ac.setWindowOpen('actionbar', true) end
      local lv = LIVERY_API.cfg()
      if lv and lv.on then LIVERY_API.apply(0, lv) LIVERY_API.broadcast() end
    end, 2)
  end
  if phoneButton and phoneButton:pressed() then
    ac.setWindowOpen('main', not ac.isWindowOpen('main'))
  end
  DIAG.time('camera', shutterTick)
  DIAG.time('plates', PL.update)
  DIAG.time('livery', LIVERY_API.tick, dt)
  DIAG.time('live', liveUpdate)
  DIAG.time('updates', UPD.tick)
  DIAG.time('laps', PHONE.lapTrack)
  DIAG.time('cut-up', HESI.update, dt)
  DIAG.time('economy', XM.tick, dt)
  DIAG.time('race', XM.race.update, dt)
  DIAG.time('vault', XM.vault.update, dt)
  do local ok, e = pcall(XM.car.update, dt) if not ok then DIAG.err('car', e) end end
  do local ok, e = pcall(XM.users.tick, dt) if not ok then DIAG.err('users', e) end end
  -- walking/video/photo stop if the phone is closed while minimised? keep running; chase handled in camUpdate
end

end
