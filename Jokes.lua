-- The saved joke list (DadJokesDB): starter jokes plus the player's own, validation, editing, and
-- the shuffle that tells every joke once before any repeats. Lua 5.1 (client) and 5.4 (harness).
local ADDON, ns = ...

ns.FORMAT = 1
ns.MAX_BYTES = 255 -- the game's limit for one chat line

local handlers = {}
local frame = CreateFrame('Frame')
frame:SetScript('OnEvent', function(_, event, ...)
  for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end)

function ns.on(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    frame:RegisterEvent(event)
  end
  table.insert(handlers[event], fn)
end

function ns.print(msg) print('|cffff8000Campfire Dad Jokes:|r ' .. msg) end

local function addRaw(setup, punch, starter)
  local db = DadJokesDB
  table.insert(db.jokes, { id = db.nextId, setup = setup, punch = punch, starter = starter })
  db.nextId = db.nextId + 1
end

function ns.initDB()
  if type(DadJokesDB) ~= 'table' or DadJokesDB.format ~= ns.FORMAT then
    DadJokesDB = { format = ns.FORMAT, nextId = 1, jokes = {} }
    for n, s in ipairs(ns.STARTERS) do addRaw(s[1], s[2], n) end
  end
  DadJokesDB.jokes = DadJokesDB.jokes or {}
  DadJokesDB.nextId = DadJokesDB.nextId or (#DadJokesDB.jokes + 1)
end

local function clean(s)
  if type(s) ~= 'string' then return '' end
  s = string.gsub(s, '[\r\n]+', ' ')
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  return s
end

-- The cleaned setup and punch line, or nil and why: 'empty', 'too_long' (over 255 bytes) or
-- 'pipe' (WoW chat reads | as an escape code).
function ns.validate(setup, punch)
  setup, punch = clean(setup), clean(punch)
  if setup == '' or punch == '' then return nil, 'empty' end
  if #setup > ns.MAX_BYTES or #punch > ns.MAX_BYTES then return nil, 'too_long' end
  if string.find(setup, '|', 1, true) or string.find(punch, '|', 1, true) then return nil, 'pipe' end
  return setup, punch
end

ns.REASONS = {
  empty = 'A joke needs both a setup and a punch line.',
  too_long = 'Each part must fit in one chat line (255 characters, fewer with accents).',
  pipe = 'The | character cannot be used in chat.',
}

local function changed()
  if ns.ui and ns.ui.refresh then ns.ui.refresh() end
end

-- Add a joke. Returns true, or nil and the reason it was refused.
function ns.addJoke(setup, punch)
  local s, p = ns.validate(setup, punch)
  if not s then return nil, p end
  addRaw(s, p, nil)
  changed()
  return true
end

function ns.editJoke(i, setup, punch)
  local j = DadJokesDB.jokes[i]
  if not j then return nil, 'missing' end
  local s, p = ns.validate(setup, punch)
  if not s then return nil, p end
  j.setup, j.punch = s, p
  changed()
  return true
end

function ns.deleteJoke(i)
  if not DadJokesDB.jokes[i] then return false end
  table.remove(DadJokesDB.jokes, i)
  changed()
  return true
end

-- Re-add every starter joke no longer in the list (an edited starter still counts as present).
-- Returns how many came back.
function ns.restoreStarters()
  local have, added = {}, 0
  for _, j in ipairs(DadJokesDB.jokes) do
    if j.starter then have[j.starter] = true end
  end
  for n, s in ipairs(ns.STARTERS) do
    if not have[n] then
      addRaw(s[1], s[2], n)
      added = added + 1
    end
  end
  if added > 0 then changed() end
  return added
end

-- Shuffle bag of joke ids (not positions, which shift on delete): every joke once per pass.
local bag = {}

local function refill()
  bag = {}
  for _, j in ipairs(DadJokesDB.jokes) do bag[#bag + 1] = j.id end
  for i = #bag, 2, -1 do
    local k = math.random(1, i)
    bag[i], bag[k] = bag[k], bag[i]
  end
end

local function byId(id)
  for _, j in ipairs(DadJokesDB.jokes) do
    if j.id == id then return j end
  end
  return nil
end

-- The next joke to tell, or nil when the list is empty.
function ns.nextJoke()
  if #DadJokesDB.jokes == 0 then return nil end
  while true do
    if #bag == 0 then refill() end
    local j = byId(table.remove(bag))
    if j then return j end
  end
end

ns.on('ADDON_LOADED', function(name)
  if name == ADDON then ns.initDB() end
end)
